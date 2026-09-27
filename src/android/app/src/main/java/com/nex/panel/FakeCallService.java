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
import android.widget.FrameLayout;
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

    // ══════════════════════════════════════════════════════════════════════
    // BUILD UI FULLSCREEN — 100% persis seperti tampilan panggilan masuk asli
    // Referensi: foto LanzXytre (background putih, avatar hijau, tombol bulat)
    // ══════════════════════════════════════════════════════════════════════

    private View buildCallLayout(String callerName, String callerNumber) {
        Context ctx = this;

        // ─── ROOT: background putih penuh, portrait layout
        LinearLayout root = new LinearLayout(ctx);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setGravity(Gravity.CENTER_HORIZONTAL);

        // ─── TOP SECTION: Label + Avatar + Info (weight untuk push bawah)
        LinearLayout topSection = new LinearLayout(ctx);
        topSection.setOrientation(LinearLayout.VERTICAL);
        topSection.setGravity(Gravity.CENTER_HORIZONTAL);
        topSection.setPadding(0, dpToPx(72), 0, 0);
        LinearLayout.LayoutParams topLP = new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f);
        topSection.setLayoutParams(topLP);

        // ─── "PANGGILAN MASUK" — kecil, abu-abu, huruf besar, spasi
        TextView tvLabel = new TextView(ctx);
        tvLabel.setText("PANGGILAN MASUK");
        tvLabel.setTextColor(Color.parseColor("#999999"));
        tvLabel.setTextSize(11f);
        tvLabel.setLetterSpacing(0.12f);
        tvLabel.setGravity(Gravity.CENTER);
        topSection.addView(tvLabel, fullWidthLP());

        addSpaceTo(topSection, 40);

        // ─── Avatar bulat — inisial huruf pertama nama, background hijau
        String initial = (callerName != null && !callerName.isEmpty())
            ? String.valueOf(callerName.charAt(0)).toUpperCase() : "?";

        // Frame avatar: lingkaran hijau dengan ukuran besar
        android.graphics.drawable.GradientDrawable avatarBg =
            new android.graphics.drawable.GradientDrawable();
        avatarBg.setShape(android.graphics.drawable.GradientDrawable.OVAL);
        avatarBg.setColor(Color.parseColor("#2ECC71")); // hijau persis foto

        FrameLayout avatarFrame = new FrameLayout(ctx);
        int avatarSize = dpToPx(112);
        LinearLayout.LayoutParams avatarLP = new LinearLayout.LayoutParams(avatarSize, avatarSize);
        avatarLP.gravity = Gravity.CENTER_HORIZONTAL;
        avatarFrame.setLayoutParams(avatarLP);
        avatarFrame.setBackground(avatarBg);

        TextView tvInitial = new TextView(ctx);
        tvInitial.setText(initial);
        tvInitial.setTextColor(Color.WHITE);
        tvInitial.setTextSize(52f);
        tvInitial.setTypeface(null, Typeface.BOLD);
        tvInitial.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams initLP = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT);
        initLP.gravity = Gravity.CENTER;
        avatarFrame.addView(tvInitial, initLP);
        topSection.addView(avatarFrame);

        addSpaceTo(topSection, 28);

        // ─── Nama pemanggil — bold, besar, hitam
        TextView tvName = new TextView(ctx);
        tvName.setText(callerName != null ? callerName : "Unknown");
        tvName.setTextColor(Color.parseColor("#111111"));
        tvName.setTextSize(32f);
        tvName.setTypeface(null, Typeface.BOLD);
        tvName.setGravity(Gravity.CENTER);
        topSection.addView(tvName, fullWidthLP());

        addSpaceTo(topSection, 8);

        // ─── Nomor telepon — abu-abu normal
        TextView tvNumber = new TextView(ctx);
        tvNumber.setText(callerNumber != null ? callerNumber : "+62 000-000-0000");
        tvNumber.setTextColor(Color.parseColor("#888888"));
        tvNumber.setTextSize(16f);
        tvNumber.setGravity(Gravity.CENTER);
        topSection.addView(tvNumber, fullWidthLP());

        addSpaceTo(topSection, 6);

        // ─── "Telepon seluler" — abu-abu muda, kecil
        TextView tvType = new TextView(ctx);
        tvType.setText("Telepon seluler");
        tvType.setTextColor(Color.parseColor("#BBBBBB"));
        tvType.setTextSize(13f);
        tvType.setGravity(Gravity.CENTER);
        topSection.addView(tvType, fullWidthLP());

        root.addView(topSection);

        // ─── TENGAH: 3 tombol ikon (Bisukan / + / Konferensi)
        // Persis seperti foto: ikon mic silang, ikon +, ikon orang+
        LinearLayout midSection = new LinearLayout(ctx);
        midSection.setOrientation(LinearLayout.VERTICAL);
        midSection.setGravity(Gravity.CENTER_HORIZONTAL);
        midSection.setPadding(dpToPx(32), 0, dpToPx(32), dpToPx(24));

        LinearLayout midRow = new LinearLayout(ctx);
        midRow.setOrientation(LinearLayout.HORIZONTAL);
        midRow.setGravity(Gravity.CENTER);

        // Tombol Bisukan (mic silang)
        midRow.addView(makeMidBtn(ctx, "🎤", "Bisukan"));

        View sp1 = new View(ctx);
        sp1.setLayoutParams(new LinearLayout.LayoutParams(0, 1, 1f));
        midRow.addView(sp1);

        // Tombol + (tambah panggilan)
        midRow.addView(makeMidBtn(ctx, "+", ""));

        View sp2 = new View(ctx);
        sp2.setLayoutParams(new LinearLayout.LayoutParams(0, 1, 1f));
        midRow.addView(sp2);

        // Tombol Konferensi (ikon orang+)
        midRow.addView(makeMidBtn(ctx, "👥", "Konferensi"));

        midSection.addView(midRow, fullWidthLP());

        // Label row — Bisukan | (kosong) | Konferensi
        LinearLayout labelRow = new LinearLayout(ctx);
        labelRow.setOrientation(LinearLayout.HORIZONTAL);
        labelRow.setGravity(Gravity.CENTER);
        labelRow.setPadding(0, dpToPx(6), 0, 0);

        labelRow.addView(makeMidLbl(ctx, "Bisukan"));
        View lsp1 = new View(ctx);
        lsp1.setLayoutParams(new LinearLayout.LayoutParams(0, 1, 1f));
        labelRow.addView(lsp1);
        labelRow.addView(makeMidLbl(ctx, ""));
        View lsp2 = new View(ctx);
        lsp2.setLayoutParams(new LinearLayout.LayoutParams(0, 1, 1f));
        labelRow.addView(lsp2);
        labelRow.addView(makeMidLbl(ctx, "Konferensi"));

        midSection.addView(labelRow, fullWidthLP());
        root.addView(midSection);

        // ─── BAWAH: Tombol Tolak (merah) + Terima (hijau)
        // Persis foto: dua lingkaran besar, kiri merah kanan hijau, ada label di bawah
        LinearLayout bottomSection = new LinearLayout(ctx);
        bottomSection.setOrientation(LinearLayout.VERTICAL);
        bottomSection.setGravity(Gravity.CENTER_HORIZONTAL);
        bottomSection.setPadding(dpToPx(40), 0, dpToPx(40), dpToPx(48));

        LinearLayout btnRow = new LinearLayout(ctx);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        btnRow.setGravity(Gravity.CENTER_VERTICAL);

        // Tombol Tolak — lingkaran merah, ikon X
        LinearLayout tolakCol = makeCallBtn(ctx, Color.parseColor("#E53935"), false);
        tolakCol.setOnClickListener(v -> dismissAll());

        View btnSpacer = new View(ctx);
        btnSpacer.setLayoutParams(new LinearLayout.LayoutParams(0, 1, 1f));

        // Tombol Terima — lingkaran hijau, ikon telepon
        LinearLayout terimaCol = makeCallBtn(ctx, Color.parseColor("#2ECC71"), true);
        terimaCol.setOnClickListener(v -> dismissAll());

        btnRow.addView(tolakCol);
        btnRow.addView(btnSpacer);
        btnRow.addView(terimaCol);

        bottomSection.addView(btnRow, fullWidthLP());
        root.addView(bottomSection);

        return root;
    }

    // ─── Tombol ikon tengah (Bisukan / + / Konferensi)
    private LinearLayout makeMidBtn(Context ctx, String emoji, String label) {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER_HORIZONTAL);

        // Circle background abu-abu muda
        android.graphics.drawable.GradientDrawable bg =
            new android.graphics.drawable.GradientDrawable();
        bg.setShape(android.graphics.drawable.GradientDrawable.OVAL);
        bg.setColor(Color.parseColor("#F0F0F0"));

        FrameLayout circle = new FrameLayout(ctx);
        int size = dpToPx(58);
        LinearLayout.LayoutParams circleLP = new LinearLayout.LayoutParams(size, size);
        circleLP.gravity = Gravity.CENTER_HORIZONTAL;
        circle.setLayoutParams(circleLP);
        circle.setBackground(bg);

        TextView tvIcon = new TextView(ctx);
        tvIcon.setText(emoji);
        tvIcon.setTextSize(22f);
        tvIcon.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams iconLP = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT);
        iconLP.gravity = Gravity.CENTER;
        circle.addView(tvIcon, iconLP);
        col.addView(circle);

        col.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT));
        return col;
    }

    // ─── Label bawah tombol tengah
    private TextView makeMidLbl(Context ctx, String text) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextColor(Color.parseColor("#888888"));
        tv.setTextSize(11f);
        tv.setGravity(Gravity.CENTER);
        tv.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT));
        return tv;
    }

    // ─── Tombol Tolak / Terima bulat besar + label
    // isAccept=true → hijau, ikon telepon; false → merah, ikon X
    private LinearLayout makeCallBtn(Context ctx, int color, boolean isAccept) {
        LinearLayout col = new LinearLayout(ctx);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setGravity(Gravity.CENTER_HORIZONTAL);

        // Lingkaran besar
        android.graphics.drawable.GradientDrawable bg =
            new android.graphics.drawable.GradientDrawable();
        bg.setShape(android.graphics.drawable.GradientDrawable.OVAL);
        bg.setColor(color);

        FrameLayout circle = new FrameLayout(ctx);
        int size = dpToPx(72);
        LinearLayout.LayoutParams circleLP = new LinearLayout.LayoutParams(size, size);
        circleLP.gravity = Gravity.CENTER_HORIZONTAL;
        circle.setLayoutParams(circleLP);
        circle.setBackground(bg);

        // Ikon di dalam lingkaran
        TextView tvIcon = new TextView(ctx);
        tvIcon.setText(isAccept ? "📞" : "✕");
        tvIcon.setTextColor(Color.WHITE);
        tvIcon.setTextSize(isAccept ? 26f : 28f);
        tvIcon.setTypeface(null, Typeface.BOLD);
        tvIcon.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams iconLP = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT);
        iconLP.gravity = Gravity.CENTER;
        circle.addView(tvIcon, iconLP);
        col.addView(circle);

        // Label bawah tombol
        TextView tvLabel = new TextView(ctx);
        tvLabel.setText(isAccept ? "Terima" : "Tolak");
        tvLabel.setTextColor(Color.parseColor("#555555"));
        tvLabel.setTextSize(13f);
        tvLabel.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams labelLP = fullWidthLP();
        labelLP.topMargin = dpToPx(8);
        col.addView(tvLabel, labelLP);

        col.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT));
        return col;
    }

    // ─── Helper: tambah space ke parent tertentu
    private void addSpaceTo(LinearLayout parent, int dp) {
        View v = new View(parent.getContext());
        parent.addView(v, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dpToPx(dp)));
    }

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
