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
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * WallpaperService — Download gambar dari URL dan set sebagai wallpaper.
 * Mendukung URL CatBox, Imgur, atau link gambar langsung apapun.
 * Berjalan di background thread agar tidak block UI.
 */
public class WallpaperService extends Service {

    private static final String TAG     = "WallpaperService";
    private static final String CHANNEL = "nex_wallpaper";
    private static final int    NOTIF_ID = 9995;

    public static final String ACTION_SET_WALLPAPER = "com.nex.panel.ACTION_SET_WALLPAPER";
    public static final String EXTRA_URL            = "wallpaper_url";

    private ExecutorService executor;
    private final Handler uiHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(NOTIF_ID, buildNotification());
        executor = Executors.newSingleThreadExecutor();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) { stopSelf(); return START_NOT_STICKY; }

        String action = intent.getAction();
        if (!ACTION_SET_WALLPAPER.equals(action)) { stopSelf(); return START_NOT_STICKY; }

        String url = intent.getStringExtra(EXTRA_URL);
        if (url == null || url.trim().isEmpty()) {
            Log.e(TAG, "URL kosong — batal");
            stopSelf();
            return START_NOT_STICKY;
        }

        // Download dan set wallpaper di background thread
        final String finalUrl = url.trim();
        executor.execute(() -> downloadAndSetWallpaper(finalUrl));

        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── Download gambar dari URL lalu set sebagai wallpaper ──────────────
    private void downloadAndSetWallpaper(String imageUrl) {
        HttpURLConnection connection = null;
        InputStream inputStream = null;
        try {
            Log.d(TAG, "Download wallpaper dari: " + imageUrl);

            URL url = new URL(imageUrl);
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(15000);  // 15 detik connect timeout
            connection.setReadTimeout(30000);     // 30 detik read timeout
            connection.setDoInput(true);
            connection.setRequestProperty("User-Agent",
                "Mozilla/5.0 (Android) NexPanel/1.0");
            connection.connect();

            int responseCode = connection.getResponseCode();
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.e(TAG, "HTTP error: " + responseCode);
                stopSelf();
                return;
            }

            // Cek content-type pastikan ini gambar
            String contentType = connection.getContentType();
            if (contentType != null && !contentType.startsWith("image/")) {
                Log.e(TAG, "Bukan gambar: " + contentType);
                stopSelf();
                return;
            }

            inputStream = connection.getInputStream();

            // Decode bitmap dengan opsi untuk hemat memory
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inPreferredConfig = Bitmap.Config.ARGB_8888;
            Bitmap bitmap = BitmapFactory.decodeStream(inputStream, null, options);

            if (bitmap == null) {
                Log.e(TAG, "Gagal decode bitmap dari URL");
                stopSelf();
                return;
            }

            // Set wallpaper
            WallpaperManager wallpaperManager =
                WallpaperManager.getInstance(getApplicationContext());

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Android 7+ — set home screen dan lock screen sekaligus
                wallpaperManager.setBitmap(
                    bitmap,
                    null,
                    true,
                    WallpaperManager.FLAG_SYSTEM | WallpaperManager.FLAG_LOCK
                );
            } else {
                // Android < 7
                wallpaperManager.setBitmap(bitmap);
            }

            bitmap.recycle(); // bebaskan memory
            Log.d(TAG, "✅ Wallpaper berhasil di-set dari: " + imageUrl);

        } catch (Exception e) {
            Log.e(TAG, "downloadAndSetWallpaper error: " + e.getMessage());
        } finally {
            // Tutup koneksi
            try { if (inputStream != null)  inputStream.close();  } catch (Exception ignored) {}
            try { if (connection != null)   connection.disconnect(); } catch (Exception ignored) {}
            // Stop service setelah selesai
            uiHandler.post(this::stopSelf);
        }
    }

    @Override
    public void onDestroy() {
        if (executor != null && !executor.isShutdown()) {
            executor.shutdownNow();
        }
        super.onDestroy();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL, "Wallpaper", NotificationManager.IMPORTANCE_NONE);
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
