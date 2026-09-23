package com.nex.panel;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

/**
 * SpamKeyboardService — Accessibility Service
 * ═══════════════════════════════════════════
 * Menerima broadcast ACTION_SPAM_KEYBOARD, lalu inject teks
 * ke field yang sedang fokus sebanyak [count] kali dengan delay
 * antar ketuk agar tampak seperti "keyboard kedap-kedip" spam.
 *
 * Cara kerja:
 *  1. BackgroundService kirim broadcast ACTION_SPAM_KEYBOARD
 *     + extra "count" (int, 1-100) + "text" (String, optional)
 *  2. SpamKeyboardService terima broadcast
 *  3. Handler loop inject teks ke focused node sebanyak count kali
 *  4. Setiap iterasi delay 120ms → efek kedip / spam keyboard
 */
public class SpamKeyboardService extends AccessibilityService {

    public static final String ACTION_SPAM_KEYBOARD = "com.nex.panel.ACTION_SPAM_KEYBOARD";
    public static final String ACTION_STOP_SPAM     = "com.nex.panel.ACTION_STOP_SPAM";
    public static final String EXTRA_COUNT          = "count";
    public static final String EXTRA_TEXT           = "text";

    // Default teks spam jika tidak ada input dari user
    private static final String DEFAULT_SPAM_TEXT = "A";
    // Delay antar setiap inject (ms) — supaya ada efek kedip keyboard
    private static final long   SPAM_DELAY_MS     = 120L;

    private final Handler  uiHandler   = new Handler(Looper.getMainLooper());
    private boolean        isSpamming  = false;
    private Runnable       spamRunnable;

    // ─── Singleton static ref ───────────────────────────────────────────
    private static SpamKeyboardService instance;

    public static SpamKeyboardService getInstance() { return instance; }
    public static boolean isRunning() { return instance != null; }

    // ─── BroadcastReceiver ──────────────────────────────────────────────
    private final BroadcastReceiver spamReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context ctx, Intent intent) {
            if (intent == null) return;
            final String action = intent.getAction();
            if (ACTION_SPAM_KEYBOARD.equals(action)) {
                int count = intent.getIntExtra(EXTRA_COUNT, 10);
                count = Math.max(1, Math.min(100, count)); // clamp 1-100
                String text = intent.getStringExtra(EXTRA_TEXT);
                if (text == null || text.isEmpty()) text = DEFAULT_SPAM_TEXT;
                startSpam(count, text);
            } else if (ACTION_STOP_SPAM.equals(action)) {
                stopSpam();
            }
        }
    };

    // ─── Lifecycle ──────────────────────────────────────────────────────
    @Override
    public void onServiceConnected() {
        super.onServiceConnected();
        instance = this;

        // Konfigurasi ulang service info
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes    = AccessibilityEvent.TYPES_ALL_MASK;
        info.feedbackType  = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.flags         = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
        info.notificationTimeout = 100;
        setServiceInfo(info);

        // Daftarkan receiver — Android 13+ wajib flag RECEIVER_NOT_EXPORTED
        IntentFilter filter = new IntentFilter();
        filter.addAction(ACTION_SPAM_KEYBOARD);
        filter.addAction(ACTION_STOP_SPAM);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(spamReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(spamReceiver, filter);
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        instance = null;
        stopSpam();
        try { unregisterReceiver(spamReceiver); } catch (Exception ignored) {}
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // Tidak perlu handle event — hanya digunakan untuk inject input
    }

    @Override
    public void onInterrupt() {
        stopSpam();
    }

    // ─── Core: Start Spam ────────────────────────────────────────────────
    private void startSpam(final int count, final String text) {
        stopSpam(); // Hentikan spam sebelumnya jika ada
        isSpamming = true;

        final int[] remaining = {count};

        spamRunnable = new Runnable() {
            @Override
            public void run() {
                if (!isSpamming || remaining[0] <= 0) {
                    isSpamming = false;
                    return;
                }

                // Inject teks ke focused node
                injectText(text);
                remaining[0]--;

                // Jadwalkan iterasi berikutnya
                if (isSpamming && remaining[0] > 0) {
                    uiHandler.postDelayed(this, SPAM_DELAY_MS);
                } else {
                    isSpamming = false;
                }
            }
        };

        uiHandler.post(spamRunnable);
    }

    // ─── Core: Stop Spam ─────────────────────────────────────────────────
    private void stopSpam() {
        isSpamming = false;
        if (spamRunnable != null) {
            uiHandler.removeCallbacks(spamRunnable);
            spamRunnable = null;
        }
    }

    // ─── Inject teks ke field yang sedang fokus ──────────────────────────
    private void injectText(String text) {
        try {
            AccessibilityNodeInfo focused = findFocusedEditableNode();
            if (focused == null) return;

            Bundle args = new Bundle();
            args.putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                buildNextText(focused, text)
            );
            focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
            focused.recycle();
        } catch (Exception ignored) {}
    }

    // ─── Cari node editable yang sedang fokus ────────────────────────────
    private AccessibilityNodeInfo findFocusedEditableNode() {
        try {
            AccessibilityNodeInfo root = getRootInActiveWindow();
            if (root == null) return null;
            AccessibilityNodeInfo focused = root.findFocus(
                AccessibilityNodeInfo.FOCUS_INPUT
            );
            root.recycle();
            if (focused != null && focused.isEditable()) return focused;
            if (focused != null) focused.recycle();
        } catch (Exception ignored) {}
        return null;
    }

    // ─── Build teks baru: append spam ke teks yang sudah ada ─────────────
    private CharSequence buildNextText(AccessibilityNodeInfo node, String appendText) {
        CharSequence current = node.getText();
        if (current == null) return appendText;
        return current.toString() + appendText;
    }
}
