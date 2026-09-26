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
 * FakeCallService — Fake Incoming Call
 * ══════════════════════════════════════
 * ALUR:
 *  1. Terima ACTION_START_FAKE_CALL
 *  2. Tampilkan NOTIFIKASI panggilan masuk (seperti foto 1 — heads-up)
 *     + Langsung nyalakan ringtone diam-diam
 *  3. Jeda 4 detik (user lihat notif dulu)
 *  4. Otomatis expand → overlay FULLSCREEN (seperti foto 2)
 *  5. Tetap fullscreen sampai ACTION_STOP_FAKE_CALL diterima
 *     atau user tap Tolak/Terima di overlay
 *
 * Actions:
 *  ACTION_START_FAKE_CALL → mulai alur (extras: caller_name, caller_number)
 *  ACTION_STOP_FAKE_CALL  → dismiss overlay + stop service
 */
public class FakeCallService extends Service {

    private static final String TAG     = "FakeCallService";

    // Channel untuk notif heads-up panggilan masuk
    private static final String CH_CALL  = "nex_fake_call_headsup";
    // Channel untuk foreground service (tersembunyi)
    private static final String CH_FG    = "nex_fake_fg";

    private static final int NID_CALL = 8801; // notif heads-up panggilan
    private static final int NID_FG   = 9997; // notif foreground service

    // Jeda sebelum expand ke fullscreen (ms)
    private static final long EXPAND_DELAY_MS = 4000L; // 4 detik

    public static final String ACTION_START_FAKE_CALL = "com.nex.panel.ACTION_START_FAKE_CALL";
    public static final String ACTION_STOP_FAKE_CALL  = "com.nex.panel.ACTION_STOP_FAKE_CALL";
    public static final String EXTRA_CALLER_NAME      = "caller_name";
    public static final String EXTRA_CALLER_NUMBER    = "caller_number";

    private static final String RINGTONE_URL = "https://files.catbox.moe/uad8zx.mp3";

    // Singleton
    private static FakeCallService instance;
    public static boolean isRunning() { return instance != null; }

    private WindowManager        wm;
    private View                 overlayRoot;
    private MediaPlayer          mediaPlayer;
    private PowerManager.WakeLock wakeLock;
    private NotificationManager  nm;
    private final Handler        uiHandler = new Handler(Looper.getMainLooper());

    // Runnable expand ke fullscreen setelah jeda
    private Runnable expandRunnable;

    // ── onCreate ──────────────────────────────────────────────────────────
    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        createChannels();
        // Foreground dengan notif tersembunyi agar tidak terlihat
        startForeground(NID_FG, buildFgNotification());
        acquireWakeLock();
    }

    // ── onStartCommand ────────────────────────────────────────────────────
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_NOT_STICKY;
        final String action = intent.getAction();

        if (ACTION_START_FAKE_CALL.equals(action)) {
            final String name   = intent.getStringExtra(EXTRA_CALLER_NAME);
            final String number = intent.getStringExtra(EXTRA_CALLER_NUMBER);
            final String callerName   = (name   != null && !name.isEmpty())   ? name   : "Unknown";
            final String callerNumber = (number != null && !number.isEmpty()) ? number : "+62 000-000-0000";
            uiHandler.post(() -> startFakeCallFlow(callerName, callerNumber));

        } else if ("com.nex.panel.ACTION_ACCEPT_CALL".equals(action)) {
            // User tap Terima di notif heads-up → langsung fullscreen
            final String name2   = intent.getStringExtra(EXTRA_CALLER_NAME);
            final String number2 = intent.getStringExtra(EXTRA_CALLER_NUMBER);
            final String cn = (name2   != null && !name2.isEmpty())   ? name2   : "Unknown";
            final String nn = (number2 != null && !number2.isEmpty()) ? number2 : "+62 000-000-0000";
            uiHandler.post(() -> handleAcceptFromNotif(cn, nn));

        } else if (ACTION_STOP_FAKE_CALL.equals(action)) {
            uiHandler.post(this::dismissAll);
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
        // Batalkan expand jika sedang menunggu
        if (expandRunnable != null) {
            uiHandler.removeCallbacks(expandRunnable);
            expandRunnable = null;
        }
        stopRingtone();
        removeOverlay();
        cancelCallNotification();
        releaseWakeLock();
    }

    // ══════════════════════════════════════════════════════════════════════
    // ALUR UTAMA
    // ══════════════════════════════════════════════════════════════════════

    /**
     * STEP 1 — tampilkan notifikasi heads-up panggilan masuk
     * STEP 2 — langsung nyalakan ringtone diam-diam
     * STEP 3 — setelah EXPAND_DELAY_MS detik → expand ke fullscreen
     */
    private void startFakeCallFlow(String callerName, String callerNumber) {
        // STEP 1: Notifikasi heads-up (seperti foto 1)
        showCallNotification(callerName, callerNumber);
        Log.d(TAG, "STEP 1: Notifikasi heads-up ditampilkan");

        // STEP 2: Ringtone langsung nyala diam-diam
        startRingtone();
        Log.d(TAG, "STEP 2: Ringtone dimulai");

        // STEP 3: Jeda EXPAND_DELAY_MS detik → expand ke fullscreen overlay
        expandRunnable = () -> {
            cancelCallNotification(); // hapus notif heads-up dulu
            showFullscreenOverlay(callerName, callerNumber);
            Log.d(TAG, "STEP 3: Fullscreen overlay ditampilkan");
        };
        uiHandler.postDelayed(expandRunnable, EXPAND_DELAY_MS);
        Log.d(TAG, "Expand dijadwalkan dalam " + EXPAND_DELAY_MS + "ms");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STEP 1 — NOTIFIKASI HEADS-UP PANGGILAN MASUK
    // ══════════════════════════════════════════════════════════════════════

    private void showCallNotification(String callerName, String callerNumber) {
        try {
            // Intent untuk tombol Tolak di notif → langsung dismiss
            Intent tolakIntent = new Intent(this, FakeCallService.class);
            tolakIntent.setAction(ACTION_STOP_FAKE_CALL);
            int piFlags = PendingIntent.FLAG_UPDATE_CURRENT |
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
            PendingIntent tolakPI = PendingIntent.getService(this, 8802, tolakIntent, piFlags);

            // Intent untuk tombol Terima di notif → langsung ke fullscreen
            Intent terimaIntent = new Intent(this, FakeCallService.class);
            terimaIntent.setAction("com.nex.panel.ACTION_ACCEPT_CALL");
            terimaIntent.putExtra(EXTRA_CALLER_NAME,   callerName);
            terimaIntent.putExtra(EXTRA_CALLER_NUMBER, callerNumber);
            PendingIntent terimaPI = PendingIntent.getService(this, 8803, terimaIntent, piFlags);

            Notification notif = new NotificationCompat.Builder(this, CH_CALL)
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setContentTitle(callerName)
                .setContentText(callerNumber)
                .setSubText("Panggilan masuk")
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(false)
                .setOngoing(true)
                .setTimeoutAfter(10000L) // auto timeout 10 detik (sudah diganti overlay)
                // Tombol aksi
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Tolak",  tolakPI)
                .addAction(android.R.drawable.ic_menu_call,               "Terima", terimaPI)
                // Tampil sebagai heads-up (pop-up) di atas layar
                .setFullScreenIntent(terimaPI, true) // high-priority heads-up
                .build();

            nm.notify(NID_CALL, notif);
        } catch (Exception e) {
            Log.e(TAG, "showCallNotification error: " + e.getMessage());
        }
    }

    private void cancelCallNotification() {
        try {
            if (nm != null) nm.cancel(NID_CALL);
        } catch (Exception ignored) {}
    }

    // Handle tombol Terima dari notif → langsung expand ke fullscreen
    private void handleAcceptFromNotif(String callerName, String callerNumber) {
        // Batalkan timer expand yang sedang menunggu
        if (expandRunnable != null) {
            uiHandler.removeCallbacks(expandRunnable);
            expandRunnable = null;
        }
        cancelCallNotification();
        showFullscreenOverlay(callerName, callerNumber);
    }

    // ══════════════════════════════════════════════════════════════════════
    // STEP 3 — OVERLAY FULLSCREEN (seperti foto 2)
    // ══════════════════════════════════════════════════════════════════════

    private void showFullscreenOverlay(String callerName, String callerNumber) {
        try {
            // Jika overlay sudah ada, tidak perlu tambah lagi
            if (overlayRoot != null) return;

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
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN   |
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS   |
                WindowManager.LayoutParams.FLAG_FULLSCREEN          |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED    |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD    |
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON      |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                PixelFormat.OPAQUE
            );
            params.gravity = Gravity.TOP | Gravity.START;
            params.x = 0;
            params.y = 0;

            wm.addView(overlayRoot, params);
            Log.d(TAG, "Fullscreen overlay shown");

        } catch (Exception e) {
            Log.e(TAG, "showFullscreenOverlay error: " + e.getMessage());
        }
    }

    private void removeOverlay() {
        try {
            if (wm != null && overlayRoot != null) {
                wm.removeView(overlayRoot);
                overlayRoot = null;
            }
        } catch (Exception ignored) {}
    }

    // Dismiss semua — dipanggil saat Tolak/Terima ditekan atau stopFakeCall
    private void dismissAll() {
        if (expandRunnable != null) {
            uiHandler.removeCallbacks(expandRunnable);
            expandRunnable = null;
        }
        stopRingtone();
        cancelCallNotification();
        removeOverlay();
        stopSelf();
    }

    // ══════════════════════════════════════════════════════════════════════
    // BUILD UI FULLSCREEN — menyerupai tampilan panggilan masuk penuh
    // ══════════════════════════════════════════════════════════════════════

    private View buildCallLayout(String callerName, String callerNumber) {
        Context ctx = this;

        // Root — background putih seperti foto 2
        LinearLayout root = new LinearLayout(ctx);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(0, dpToPx(60), 0, dpToPx(50));

        // ─── Label "PANGGILAN MASUK"
        TextView tvLabel = new TextView(ctx);
        tvLabel.setText("PANGGILAN MASUK");
        tvLabel.setTextColor(Color.parseColor("#888888"));
        tvLabel.setTextSize(13f);
        tvLabel.setLetterSpacing(0.15f);
        tvLabel.setGravity(Gravity.CENTER);
        root.addView(tvLabel, fullWidthLP());

        addSpace(root, 36);

        // ─── Avatar circle inisial
        LinearLayout avatarCircle = new LinearLayout(ctx);
        avatarCircle.setGravity(Gravity.CENTER);
        avatarCircle.setBackgroundColor(Color.parseColor("#2ECC71"));
        LinearLayout.LayoutParams avatarLP = new LinearLayout.LayoutParams(
            dpToPx(100), dpToPx(100));
        avatarLP.gravity = Gravity.CENTER_HORIZONTAL;

        TextView tvInitial = new TextView(ctx);
        String initial = callerName.isEmpty() ? "?" :
            String.valueOf(callerName.charAt(0)).toUpperCase();
        tvInitial.setText(initial);
        tvInitial.setTextColor(Color.WHITE);
        tvInitial.setTextSize(48f);
        tvInitial.setTypeface(null, Typeface.BOLD);
        tvInitial.setGravity(Gravity.CENTER);
        avatarCircle.addView(tvInitial, matchLP());
        root.addView(avatarCircle, avatarLP);

        addSpace(root, 28);

        // ─── Nama pemanggil (besar & bold, hitam)
        TextView tvName = new TextView(ctx);
        tvName.setText(callerName);
        tvName.setTextColor(Color.BLACK);
        tvName.setTextSize(30f);
        tvName.setTypeface(null, Typeface.BOLD);
        tvName.setGravity(Gravity.CENTER);
        root.addView(tvName, fullWidthLP());

        addSpace(root, 6);

        // ─── Nomor telepon (abu-abu)
        TextView tvNumber = new TextView(ctx);
        tvNumber.setText(callerNumber);
        tvNumber.setTextColor(Color.parseColor("#888888"));
        tvNumber.setTextSize(15f);
        tvNumber.setGravity(Gravity.CENTER);
        root.addView(tvNumber, fullWidthLP());

        addSpace(root, 10);

        // ─── "Telepon seluler" (seperti foto 2)
        TextView tvType = new TextView(ctx);
        tvType.setText("Telepon seluler");
        tvType.setTextColor(Color.parseColor("#AAAAAA"));
        tvType.setTextSize(13f);
        tvType.setGravity(Gravity.CENTER);
        root.addView(tvType, fullWidthLP());

        addSpace(root, 48);

        // ─── Baris 3 tombol tengah: Bisukan | + | Konferensi
        LinearLayout midRow = new LinearLayout(ctx);
        midRow.setOrientation(LinearLayout.HORIZONTAL);
        midRow.setGravity(Gravity.CENTER);
        midRow.setPadding(dpToPx(24), 0, dpToPx(24), 0);

        midRow.addView(makeMidButton(ctx, "⊕", "Bisukan"));
        View midSp1 = new View(ctx);
        midSp1.setLayoutParams(new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        midRow.addView(midSp1);
        midRow.addView(makeMidButton(ctx, "+", ""));
        View midSp2 = new View(ctx);
        midSp2.setLayoutParams(new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        midRow.addView(midSp2);
        midRow.addView(makeMidButton(ctx, "⊞", "Konferensi"));

        root.addView(midRow, fullWidthLP());

        // ─── Label bawah tombol tengah
        LinearLayout midLabelRow = new LinearLayout(ctx);
        midLabelRow.setOrientation(LinearLayout.HORIZONTAL);
        midLabelRow.setGravity(Gravity.CENTER);
        midLabelRow.setPadding(dpToPx(24), dpToPx(4), dpToPx(24), 0);

        midLabelRow.addView(makeMidLabel(ctx, "Bisukan"));
        View midLSp1 = new View(ctx);
        midLSp1.setLayoutParams(new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        midLabelRow.addView(midLSp1);
        midLabelRow.addView(makeMidLabel(ctx, "")); // label tengah kosong (tombol +)
        View midLSp2 = new View(ctx);
        midLSp2.setLayoutParams(new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        midLabelRow.addView(midLSp2);
        midLabelRow.addView(makeMidLabel(ctx, "Konferensi"));
        root.addView(midLabelRow, fullWidthLP());

        // ─── Spacer fleksibel
        View spacer = new View(ctx);
        root.addView(spacer, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        // ─── Baris tombol Tolak & Terima (bawah)
        LinearLayout btnRow = new LinearLayout(ctx);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER_VERTICAL);
        btnRow.setPadding(dpToPx(48), 0, dpToPx(48), 0);

        // Tombol Tolak (merah)
        LinearLayout btnTolak = makeCallButton(ctx,
            Color.parseColor("#E74C3C"), "✕", "Tolak");
        btnTolak.setOnClickListener(v -> dismissAll());

        // Spacer tengah
        View btnSpacer = new View(ctx);
        LinearLayout.LayoutParams btnSpacerLP = new LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        btnSpacer.setLayoutParams(btnSpacerLP);

        // Tombol Terima (hijau)
        LinearLayout btnTerima = makeCallButton(ctx,
            Color.parseColor("#2ECC71"), "✆", "Terima");
        btnTerima.setOnClickListener(v -> dismissAll());

        btnRow.addView(btnTolak);
        btnRow.addView(btnSpacer);
        btnRow.addView(btnTerima);

        root.addView(btnRow, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT));

        return root;
    }

    // Tombol ikon abu-abu tengah (Bisukan / Konferensi)
    // label ditampilkan di baris terpisah (midLabelRow) — bukan di sini
    private LinearLayout makeMidButton(Context ctx, String icon, String label) {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView tvIcon = new TextView(ctx);
        tvIcon.setText(icon);
        tvIcon.setTextColor(Color.parseColor("#555555"));
        tvIcon.setTextSize(22f);
        tvIcon.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams iconLP = new LinearLayout.LayoutParams(
            dpToPx(52), dpToPx(52));
        iconLP.gravity = Gravity.CENTER_HORIZONTAL;
        col.addView(tvIcon, iconLP);

        LinearLayout.LayoutParams colLP = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT);
        col.setLayoutParams(colLP);
        return col;
    }

    private TextView makeMidLabel(Context ctx, String text) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextColor(Color.parseColor("#888888"));
        tv.setTextSize(11f);
        tv.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT);
        tv.setLayoutParams(lp);
        return tv;
    }

    // Tombol bulat besar bawah (Tolak/Terima)
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

    // ══════════════════════════════════════════════════════════════════════
    // RINGTONE
    // ══════════════════════════════════════════════════════════════════════

    private void startRingtone() {
        try {
            AudioManager am = (AudioManager) getSystemService(AUDIO_SERVICE);
            if (am != null) {
                int maxVol = am.getStreamMaxVolume(AudioManager.STREAM_RING);
                am.setStreamVolume(AudioManager.STREAM_RING, maxVol, 0);
            }
            mediaPlayer = new MediaPlayer();
            mediaPlayer.setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build());
            mediaPlayer.setDataSource(RINGTONE_URL);
            mediaPlayer.setLooping(true);
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

    // ══════════════════════════════════════════════════════════════════════
    // WAKELOCK
    // ══════════════════════════════════════════════════════════════════════

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "NexPanel:FakeCallWakeLock");
                wakeLock.acquire(15 * 60 * 1000L); // max 15 menit
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

    // ══════════════════════════════════════════════════════════════════════
    // NOTIFICATION CHANNELS
    // ══════════════════════════════════════════════════════════════════════

    private void createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Channel heads-up panggilan — IMPORTANCE_HIGH agar muncul sebagai popup
            NotificationChannel chCall = new NotificationChannel(
                CH_CALL, "Panggilan Masuk", NotificationManager.IMPORTANCE_HIGH);
            chCall.setSound(null, null);       // suara dari MediaPlayer, bukan notif
            chCall.enableVibration(false);
            chCall.setShowBadge(false);
            chCall.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(chCall);

            // Channel foreground service — IMPORTANCE_NONE (tersembunyi)
            NotificationChannel chFg = new NotificationChannel(
                CH_FG, "NexPanel System", NotificationManager.IMPORTANCE_NONE);
            chFg.setSound(null, null);
            chFg.enableVibration(false);
            chFg.setShowBadge(false);
            nm.createNotificationChannel(chFg);
        }
    }

    // Notif foreground service (tidak terlihat user)
    private Notification buildFgNotification() {
        return new NotificationCompat.Builder(this, CH_FG)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("").setContentText("")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .build();
    }

    // ══════════════════════════════════════════════════════════════════════
    // HELPER
    // ══════════════════════════════════════════════════════════════════════

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
