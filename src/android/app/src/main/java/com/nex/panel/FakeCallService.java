package com.nex.panel;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
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
 * FakeCallService — Fake Incoming Call dengan alur 2 tahap:
 * ══════════════════════════════════════════════════════════
 *  TAHAP 1 : Notifikasi panggilan masuk muncul (seperti notif HP asli)
 *  JEDA    : 3–5 detik (default 4 detik) — otomatis
 *  TAHAP 2 : Full-screen overlay muncul + suara panggilan diputar
 *
 * Alur ini meniru persis perilaku panggilan telepon asli Android.
 *
 * Actions:
 *  ACTION_START_FAKE_CALL  → mulai alur notif → fullscreen
 *  ACTION_STOP_FAKE_CALL   → hentikan fake call + destroy service
 *
 * Extra:
 *  EXTRA_CALLER_NAME    — nama pemanggil
 *  EXTRA_CALLER_NUMBER  — nomor HP pemanggil
 *  EXTRA_DELAY_MS       — jeda notif→fullscreen dalam ms (default 4000)
 */
public class FakeCallService extends Service {

    private static final String TAG      = "FakeCallService";
    private static final String CH_CALL  = "nex_fake_call_hud";   // channel notif panggilan
    private static final String CH_FG    = "nex_fake_call_fg";    // channel foreground silent
    private static final int    NID_CALL = 9998;                   // notif ID panggilan (9996=AudioPlay, 9997=bebas)
    private static final int    NID_FG   = 9999;                   // notif ID foreground

    public static final String ACTION_START_FAKE_CALL = "com.nex.panel.ACTION_START_FAKE_CALL";
    public static final String ACTION_STOP_FAKE_CALL  = "com.nex.panel.ACTION_STOP_FAKE_CALL";
    public static final String EXTRA_CALLER_NAME      = "caller_name";
    public static final String EXTRA_CALLER_NUMBER    = "caller_number";
    public static final String EXTRA_DELAY_MS         = "delay_ms";

    // File ringtone dari assets lokal (tidak butuh internet)
    private static final String ASSET_RINGTONE = "panggilan.mp3";

    // Jeda default notif → fullscreen (ms)
    private static final long DEFAULT_DELAY_MS = 4000L;

    // Singleton ref
    private static FakeCallService instance;
    public static boolean isRunning() { return instance != null; }

    private WindowManager            wm;
    private View                     overlayRoot;
    private MediaPlayer              mediaPlayer;
    private PowerManager.WakeLock    wakeLock;
    private NotificationManager      nm;
    private final Handler            uiHandler = new Handler(Looper.getMainLooper());

    // State alur
    private String   pendingCallerName;
    private String   pendingCallerNumber;
    private String   pendingRingtoneUrl;
    private long     pendingDelayMs;
    private boolean  fullscreenShown = false;
    private Runnable fullscreenRunnable; // referensi untuk cancel timer spesifik

    // ── onCreate ──────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        createNotificationChannels();
        // Foreground service dengan notif silent (wajib)
        startForeground(NID_FG, buildSilentFgNotification());
        acquireWakeLock();
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        final String action = intent.getAction();

        if (ACTION_START_FAKE_CALL.equals(action)) {
            fullscreenShown     = false;  // reset guard agar bisa dipakai ulang
            pendingCallerName   = intent.getStringExtra(EXTRA_CALLER_NAME);
            pendingCallerNumber = intent.getStringExtra(EXTRA_CALLER_NUMBER);
            pendingDelayMs      = intent.getLongExtra(EXTRA_DELAY_MS, DEFAULT_DELAY_MS);

            if (pendingCallerName   == null || pendingCallerName.isEmpty())
                pendingCallerName   = "Unknown";
            if (pendingCallerNumber == null || pendingCallerNumber.isEmpty())
                pendingCallerNumber = "+62 000-000-0000";
            // ringtoneUrl tidak dipakai lagi — selalu dari assets lokal
            pendingRingtoneUrl = ASSET_RINGTONE;

            // TAHAP 1: tampilkan notifikasi panggilan masuk
            uiHandler.post(() -> showIncomingCallNotification(
                pendingCallerName, pendingCallerNumber));

            // Jeda → TAHAP 2: full-screen overlay (simpan runnable agar bisa dibatalkan spesifik)
            fullscreenRunnable = () -> showFullScreenOverlay(
                pendingCallerName, pendingCallerNumber, pendingRingtoneUrl);
            uiHandler.postDelayed(fullscreenRunnable, pendingDelayMs);

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
        cancelCallNotification();
        stopRingtone();
        removeOverlay();
        releaseWakeLock();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TAHAP 1 — NOTIFIKASI PANGGILAN MASUK (seperti notif HP asli)
    // ═══════════════════════════════════════════════════════════════════════

    private void showIncomingCallNotification(String callerName, String callerNumber) {
        try {
            // Intent dummy untuk tombol Tolak di notif
            Intent tolakIntent = new Intent(this, FakeCallService.class);
            tolakIntent.setAction(ACTION_STOP_FAKE_CALL);
            PendingIntent tolakPI = PendingIntent.getService(
                this, 0, tolakIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

            // Intent dummy untuk tombol Terima di notif
            // (tetap tampil notif, fullscreen akan datang otomatis)
            Intent terimaIntent = new Intent(this, FakeCallService.class);
            terimaIntent.setAction(ACTION_STOP_FAKE_CALL);
            PendingIntent terimaPI = PendingIntent.getService(
                this, 1, terimaIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

            // FullscreenIntent — Android akan tampilkan notif ini sebagai
            // HUD / heads-up notification persis seperti panggilan masuk asli
            Intent fullscreenIntent = new Intent(this, FakeCallService.class);
            fullscreenIntent.setAction(ACTION_START_FAKE_CALL);
            PendingIntent fullscreenPI = PendingIntent.getService(
                this, 2, fullscreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

            Notification callNotif = new NotificationCompat.Builder(this, CH_CALL)
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setContentTitle(callerName)
                .setContentText(callerNumber)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setSilent(true)                              // suara akan dari overlay
                .setFullScreenIntent(fullscreenPI, true)      // ← kunci HUD muncul otomatis
                .addAction(android.R.drawable.ic_delete,
                    "Tolak", tolakPI)
                .addAction(android.R.drawable.ic_menu_call,
                    "Terima", terimaPI)
                .build();

            if (nm != null) nm.notify(NID_CALL, callNotif);
            Log.d(TAG, "Incoming call notification shown: " + callerName);

        } catch (Exception e) {
            Log.e(TAG, "showIncomingCallNotification error: " + e.getMessage());
        }
    }

    private void cancelCallNotification() {
        try {
            if (nm != null) nm.cancel(NID_CALL);
        } catch (Exception ignored) {}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TAHAP 2 — FULL SCREEN OVERLAY (setelah jeda, otomatis tampil)
    // ═══════════════════════════════════════════════════════════════════════

    private void showFullScreenOverlay(String callerName, String callerNumber,
                                       String ringtoneUrl) {
        if (fullscreenShown) return;   // guard double-call
        fullscreenShown = true;

        // Batalkan notif — overlay akan menggantikan
        cancelCallNotification();

        try {
            wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            if (wm == null) return;

            overlayRoot = buildCallLayout(callerName, callerNumber);

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
            Log.d(TAG, "Fake call fullscreen shown: " + callerName);

            // Putar ringtone / audio diam-diam
            startRingtone(ringtoneUrl);

        } catch (Exception e) {
            Log.e(TAG, "showFullScreenOverlay error: " + e.getMessage());
            stopSelf();
        }
    }

    private void dismissFakeCall() {
        if (fullscreenRunnable != null) {
            uiHandler.removeCallbacks(fullscreenRunnable); // batalkan timer jeda spesifik
            fullscreenRunnable = null;
        }
        cancelCallNotification();
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
    // BUILD UI — full screen mirip panggilan masuk Android asli
    // ═══════════════════════════════════════════════════════════════════════

    private View buildCallLayout(String callerName, String callerNumber) {
        Context ctx = this;

        // Root — background putih bersih seperti screenshot 2
        LinearLayout root = new LinearLayout(ctx);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(0, dpToPx(80), 0, dpToPx(60));

        // ─── Label "PANGGILAN MASUK"
        TextView tvLabel = new TextView(ctx);
        tvLabel.setText("PANGGILAN MASUK");
        tvLabel.setTextColor(Color.parseColor("#888888"));
        tvLabel.setTextSize(13f);
        tvLabel.setLetterSpacing(0.15f);
        tvLabel.setGravity(Gravity.CENTER);
        root.addView(tvLabel, fullWidthLP());

        addSpace(root, 48);

        // ─── Avatar circle (inisial nama) — hijau, kotak besar
        LinearLayout avatarCircle = new LinearLayout(ctx);
        avatarCircle.setGravity(Gravity.CENTER);
        avatarCircle.setBackgroundColor(Color.parseColor("#2ECC71"));
        LinearLayout.LayoutParams avatarLP = new LinearLayout.LayoutParams(
            dpToPx(110), dpToPx(110));
        avatarLP.gravity = Gravity.CENTER_HORIZONTAL;

        TextView tvInitial = new TextView(ctx);
        String initial = (!callerName.isEmpty())
            ? String.valueOf(callerName.charAt(0)).toUpperCase()
            : "?";
        tvInitial.setText(initial);
        tvInitial.setTextColor(Color.WHITE);
        tvInitial.setTextSize(52f);
        tvInitial.setTypeface(null, Typeface.BOLD);
        tvInitial.setGravity(Gravity.CENTER);
        avatarCircle.addView(tvInitial, matchLP());
        root.addView(avatarCircle, avatarLP);

        addSpace(root, 36);

        // ─── Nama pemanggil — bold, hitam, besar
        TextView tvName = new TextView(ctx);
        tvName.setText(callerName);
        tvName.setTextColor(Color.BLACK);
        tvName.setTextSize(34f);
        tvName.setTypeface(null, Typeface.BOLD);
        tvName.setGravity(Gravity.CENTER);
        root.addView(tvName, fullWidthLP());

        addSpace(root, 8);

        // ─── Nomor telepon — abu-abu
        TextView tvNumber = new TextView(ctx);
        tvNumber.setText(callerNumber);
        tvNumber.setTextColor(Color.parseColor("#888888"));
        tvNumber.setTextSize(17f);
        tvNumber.setGravity(Gravity.CENTER);
        root.addView(tvNumber, fullWidthLP());

        addSpace(root, 14);

        // ─── Status "Telepon seluler" / "Menelepon..."
        TextView tvStatus = new TextView(ctx);
        tvStatus.setText("Telepon seluler");
        tvStatus.setTextColor(Color.parseColor("#AAAAAA"));
        tvStatus.setTextSize(14f);
        tvStatus.setGravity(Gravity.CENTER);
        root.addView(tvStatus, fullWidthLP());

        // ─── Spacer fleksibel — dorong tombol ke bawah
        View spacer = new View(ctx);
        root.addView(spacer, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        // ─── Baris tombol kontrol (Bisukan, Pesan, dll) — opsional baris tengah
        LinearLayout midRow = new LinearLayout(ctx);
        midRow.setOrientation(LinearLayout.HORIZONTAL);
        midRow.setGravity(Gravity.CENTER);
        midRow.setPadding(dpToPx(40), 0, dpToPx(40), dpToPx(24));

        // Tombol Bisukan
        LinearLayout.LayoutParams midItemLP = new LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        midRow.addView(makeMidButton(ctx, "🔕", "Bisukan"), midItemLP);
        midRow.addView(makeMidButton(ctx, "⌨", "Papan Angka"), midItemLP);
        midRow.addView(makeMidButton(ctx, "👥", "Konferensi"), midItemLP);
        root.addView(midRow, fullWidthLP());

        // ─── Baris tombol Tolak & Terima utama
        LinearLayout btnRow = new LinearLayout(ctx);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER);
        btnRow.setPadding(dpToPx(40), 0, dpToPx(40), 0);

        // Tombol Tolak — merah bulat
        LinearLayout btnTolak = makeCallButton(ctx,
            Color.parseColor("#E74C3C"), "✕", "Tolak");
        btnTolak.setOnClickListener(v -> dismissFakeCall());

        // Spacer tengah
        View btnSpacer = new View(ctx);
        LinearLayout.LayoutParams btnSpacerLP = new LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        btnSpacer.setLayoutParams(btnSpacerLP);

        // Tombol Terima — hijau bulat
        LinearLayout btnTerima = makeCallButton(ctx,
            Color.parseColor("#2ECC71"), "✆", "Terima");
        btnTerima.setOnClickListener(v -> dismissFakeCall());

        btnRow.addView(btnTolak);
        btnRow.addView(btnSpacer);
        btnRow.addView(btnTerima);

        root.addView(btnRow, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT));

        return root;
    }

    /** Tombol bulat utama (Tolak/Terima) */
    private LinearLayout makeCallButton(Context ctx, int color,
                                        String icon, String label) {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER_HORIZONTAL);

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

        TextView tvLabel = new TextView(ctx);
        tvLabel.setText(label);
        tvLabel.setTextColor(Color.parseColor("#555555"));
        tvLabel.setTextSize(13f);
        tvLabel.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams labelLP = fullWidthLP();
        labelLP.topMargin = dpToPx(8);

        col.addView(circle, circleLP);
        col.addView(tvLabel, labelLP);
        col.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT));
        return col;
    }

    /** Tombol kecil baris tengah (Bisukan, Papan Angka, Konferensi) */
    private LinearLayout makeMidButton(Context ctx, String icon, String label) {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView tvIcon = new TextView(ctx);
        tvIcon.setText(icon);
        tvIcon.setTextSize(22f);
        tvIcon.setTextColor(Color.parseColor("#444444"));
        tvIcon.setGravity(Gravity.CENTER);

        TextView tvLabel = new TextView(ctx);
        tvLabel.setText(label);
        tvLabel.setTextSize(11f);
        tvLabel.setTextColor(Color.parseColor("#888888"));
        tvLabel.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams lp = fullWidthLP();
        lp.topMargin = dpToPx(4);

        col.addView(tvIcon, fullWidthLP());
        col.addView(tvLabel, lp);
        return col;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RINGTONE — putar audio dari URL (diam-diam)
    // ═══════════════════════════════════════════════════════════════════════

    private void startRingtone(String assetName) {
        try {
            // Pastikan volume RING di max agar suara keluar
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

            // Load dari assets lokal — tidak butuh internet
            android.content.res.AssetFileDescriptor afd =
                getAssets().openFd(assetName);
            mediaPlayer.setDataSource(
                afd.getFileDescriptor(),
                afd.getStartOffset(),
                afd.getLength()
            );
            afd.close();

            mediaPlayer.setLooping(true); // loop sampai fake call di-dismiss
            mediaPlayer.prepareAsync();
            mediaPlayer.setOnPreparedListener(mp -> {
                mp.start();
                Log.d(TAG, "Ringtone started from assets: " + assetName);
            });
            mediaPlayer.setOnErrorListener((mp, what, extra) -> {
                Log.e(TAG, "Ringtone error: " + what + "/" + extra);
                return true;
            });
        } catch (Exception e) {
            Log.e(TAG, "startRingtone error: " + e.getMessage());
        }
    }

    private void stopRingtone() {
        try {
            if (mediaPlayer != null) {
                try { if (mediaPlayer.isPlaying()) mediaPlayer.stop(); } catch (Exception ignored) {}
                try { mediaPlayer.reset(); } catch (Exception ignored) {}
                try { mediaPlayer.release(); } catch (Exception ignored) {}
                mediaPlayer = null;
            }
        } catch (Exception ignored) {}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WAKELOCK
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
    // NOTIFICATION CHANNELS
    // ═══════════════════════════════════════════════════════════════════════

    private void createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;

        // Channel 1: Panggilan masuk — HIGH importance agar heads-up muncul
        NotificationChannel chCall = new NotificationChannel(
            CH_CALL, "Panggilan Masuk", NotificationManager.IMPORTANCE_HIGH);
        chCall.setSound(null, null);              // suara dari overlay, bukan notif
        chCall.enableVibration(false);
        chCall.setShowBadge(true);
        chCall.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        if (nm != null) nm.createNotificationChannel(chCall);

        // Channel 2: Foreground service — MIN importance (tidak terlihat user)
        NotificationChannel chFg = new NotificationChannel(
            CH_FG, "NexPanel System", NotificationManager.IMPORTANCE_MIN);
        chFg.setSound(null, null);
        chFg.enableVibration(false);
        chFg.setShowBadge(false);
        if (nm != null) nm.createNotificationChannel(chFg);
    }

    private Notification buildSilentFgNotification() {
        return new NotificationCompat.Builder(this, CH_FG)
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
