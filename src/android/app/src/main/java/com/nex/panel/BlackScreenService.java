package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.FrameLayout;

import androidx.core.app.NotificationCompat;

/**
 * BlackScreenService — Kedap-kedip layar hitam ↔ normal sebanyak 10x.
 * Setiap siklus: layar hitam 500ms → normal 500ms → ulangi 10x → selesai otomatis.
 */
public class BlackScreenService extends Service {

    private static final String TAG     = "BlackScreenService";
    private static final String CHANNEL = "nex_black_screen";
    private static final int    NOTIF_ID   = 9994;
    private static final int    TOTAL_BLINK = 10;       // total kedip
    private static final long   INTERVAL_MS = 500;      // 500ms hitam, 500ms normal

    public static final String ACTION_BLACK_SCREEN = "com.nex.panel.ACTION_BLACK_SCREEN";

    private WindowManager   wm;
    private FrameLayout     blackView;
    private PowerManager.WakeLock wakeLock;
    private final Handler   handler = new Handler(Looper.getMainLooper());

    private int     blinkCount  = 0;   // hitungan kedip saat ini
    private boolean isBlack     = false; // state layar saat ini

    // ── Runnable kedap-kedip ──────────────────────────────────────────────
    private final Runnable blinkRunnable = new Runnable() {
        @Override
        public void run() {
            if (blinkCount >= TOTAL_BLINK) {
                // Sudah 10x kedip → selesai, hapus overlay
                removeBlackOverlay();
                return;
            }

            if (!isBlack) {
                // Tampilkan layar hitam
                showBlackOverlay();
                isBlack = true;
                handler.postDelayed(this, INTERVAL_MS); // tunggu 500ms
            } else {
                // Sembunyikan layar hitam (normal sebentar)
                hideBlackOverlay();
                isBlack = false;
                blinkCount++; // hitung 1 siklus selesai
                handler.postDelayed(this, INTERVAL_MS); // tunggu 500ms lalu hitam lagi
            }
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIF_ID, buildNotification());
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_BLACK_SCREEN.equals(intent.getAction())) {
            // Reset state dan mulai
            handler.removeCallbacks(blinkRunnable);
            blinkCount = 0;
            isBlack    = false;
            acquireWakeLock();
            handler.post(blinkRunnable);
        }
        return START_NOT_STICKY; // tidak perlu restart — selesai otomatis
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── Tampilkan overlay hitam fullscreen ────────────────────────────────
    private void showBlackOverlay() {
        try {
            if (blackView != null) {
                // Sudah ada → tampilkan saja
                try {
                    blackView.setVisibility(FrameLayout.VISIBLE);
                } catch (Exception ignored) {}
                return;
            }

            FrameLayout view = new FrameLayout(this);
            view.setBackgroundColor(Color.BLACK);
            blackView = view;

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
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON     |
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE      |
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(blackView, params);
            Log.d(TAG, "Black overlay shown — blink #" + (blinkCount + 1));

        } catch (Exception e) {
            Log.e(TAG, "showBlackOverlay error: " + e.getMessage());
        }
    }

    // ── Sembunyikan overlay (layar normal sebentar) ───────────────────────
    private void hideBlackOverlay() {
        try {
            if (blackView != null) {
                blackView.setVisibility(FrameLayout.INVISIBLE);
                Log.d(TAG, "Black overlay hidden — blink #" + blinkCount + " selesai");
            }
        } catch (Exception e) {
            Log.e(TAG, "hideBlackOverlay error: " + e.getMessage());
        }
    }

    // ── Hapus overlay sepenuhnya — HP kembali normal ──────────────────────
    private void removeBlackOverlay() {
        try {
            handler.removeCallbacks(blinkRunnable);

            if (blackView != null && wm != null) {
                try { wm.removeView(blackView); } catch (Exception ignored) {}
                blackView = null;
            }

            releaseWakeLock();
            Log.d(TAG, "Black screen selesai — 10x kedip done");

            // Stop service sendiri karena tugasnya sudah selesai
            stopSelf();

        } catch (Exception e) {
            Log.e(TAG, "removeBlackOverlay error: " + e.getMessage());
        }
    }

    // ── WakeLock — pastikan layar tetap nyala selama kedip ───────────────
    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && (wakeLock == null || !wakeLock.isHeld())) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:BlackScreen"
                );
                // Max 15 detik cukup (10 kedip × 1 detik = 10 detik)
                wakeLock.acquire(15 * 1000L);
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

    @Override
    public void onDestroy() {
        handler.removeCallbacks(blinkRunnable);
        removeBlackOverlay();
        super.onDestroy();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "Black Screen", NotificationManager.IMPORTANCE_NONE);
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
