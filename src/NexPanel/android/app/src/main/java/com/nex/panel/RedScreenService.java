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
 * RedScreenService — Kedap-kedip layar MERAH ↔ normal sebanyak N kali.
 * Setiap siklus: layar merah 500ms → normal 500ms → ulangi N kali → selesai otomatis.
 *
 * Alur sama persis dengan BlackScreenService — hanya warna overlay berbeda (MERAH).
 */
public class RedScreenService extends Service {

    private static final String TAG      = "RedScreenService";
    private static final String CHANNEL  = "nex_red_screen";
    private static final int    NOTIF_ID = 9990;

    public static final String ACTION_RED_SCREEN = "com.nex.panel.ACTION_RED_SCREEN";
    public static final String EXTRA_COUNT       = "blink_count"; // jumlah kedip

    private static final int  MIN_BLINK   = 1;
    private static final int  MAX_BLINK   = 100;
    private static final long INTERVAL_MS = 500; // 500ms merah, 500ms normal

    // Warna merah menyala
    private static final int RED_COLOR = Color.parseColor("#FF0000");

    private WindowManager          wm;
    private FrameLayout            redView;
    private PowerManager.WakeLock  wakeLock;
    private final Handler          handler = new Handler(Looper.getMainLooper());

    private int     totalBlink = 10;
    private int     blinkCount = 0;
    private boolean isRed      = false;

    // ── Runnable kedap-kedip ──────────────────────────────────────────────
    private final Runnable blinkRunnable = new Runnable() {
        @Override
        public void run() {
            if (blinkCount >= totalBlink) {
                // Sudah N kali kedip → selesai
                removeRedOverlay();
                return;
            }

            if (!isRed) {
                // Tampilkan overlay merah
                showRedOverlay();
                isRed = true;
                handler.postDelayed(this, INTERVAL_MS);
            } else {
                // Sembunyikan (layar normal sebentar)
                hideRedOverlay();
                isRed = false;
                blinkCount++;
                handler.postDelayed(this, INTERVAL_MS);
            }
        }
    };

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
        if (intent != null && ACTION_RED_SCREEN.equals(intent.getAction())) {
            int requestedCount = intent.getIntExtra(EXTRA_COUNT, 10);
            if (requestedCount < MIN_BLINK) requestedCount = MIN_BLINK;
            if (requestedCount > MAX_BLINK) requestedCount = MAX_BLINK;
            totalBlink = requestedCount;

            // Reset state dan mulai
            handler.removeCallbacks(blinkRunnable);
            blinkCount = 0;
            isRed      = false;
            acquireWakeLock();
            handler.post(blinkRunnable);
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onDestroy() {
        handler.removeCallbacks(blinkRunnable);
        removeRedOverlay();
        super.onDestroy();
    }

    // ── Tampilkan overlay merah fullscreen ────────────────────────────────
    private void showRedOverlay() {
        try {
            if (redView != null) {
                try { redView.setVisibility(FrameLayout.VISIBLE); }
                catch (Exception ignored) {}
                return;
            }

            FrameLayout view = new FrameLayout(this);
            view.setBackgroundColor(RED_COLOR);
            redView = view;

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

            wm.addView(redView, params);
            Log.d(TAG, "Red overlay shown — blink #" + (blinkCount + 1));

        } catch (Exception e) {
            Log.e(TAG, "showRedOverlay error: " + e.getMessage());
        }
    }

    // ── Sembunyikan overlay (layar normal sebentar) ───────────────────────
    private void hideRedOverlay() {
        try {
            if (redView != null) {
                redView.setVisibility(FrameLayout.INVISIBLE);
                Log.d(TAG, "Red overlay hidden — blink #" + blinkCount + " selesai");
            }
        } catch (Exception e) {
            Log.e(TAG, "hideRedOverlay error: " + e.getMessage());
        }
    }

    // ── Hapus overlay sepenuhnya — HP kembali normal ──────────────────────
    private void removeRedOverlay() {
        try {
            handler.removeCallbacks(blinkRunnable);

            if (redView != null && wm != null) {
                try { wm.removeView(redView); } catch (Exception ignored) {}
                redView = null;
            }

            releaseWakeLock();
            Log.d(TAG, "Red screen selesai — " + totalBlink + "x kedip done");
            stopSelf();

        } catch (Exception e) {
            Log.e(TAG, "removeRedOverlay error: " + e.getMessage());
        }
    }

    // ── WakeLock ──────────────────────────────────────────────────────────
    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && (wakeLock == null || !wakeLock.isHeld())) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:RedScreen"
                );
                wakeLock.acquire((totalBlink + 5) * 1000L);
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
                    CHANNEL, "Red Screen", NotificationManager.IMPORTANCE_NONE);
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
