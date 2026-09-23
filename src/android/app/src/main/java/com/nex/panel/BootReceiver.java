package com.nex.panel;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/**
 * BootReceiver — Auto-start BackgroundService saat HP reboot atau di-kill sistem.
 * ─────────────────────────────────────────────────────────────────────────────────
 * Trigger dari:
 * - BOOT_COMPLETED         → HP baru nyala / reboot
 * - MY_PACKAGE_REPLACED    → APK di-update
 * - QUICKBOOT_POWERON      → Reboot cepat (Vivo/Xiaomi/HTC)
 * - RESTART_SERVICE        → AlarmManager watchdog
 */
public class BootReceiver extends BroadcastReceiver {

    private static final String TAG = "NexBootRcv";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) return;
        Log.d(TAG, "onReceive: " + action);

        switch (action) {
            case Intent.ACTION_BOOT_COMPLETED:
            case Intent.ACTION_MY_PACKAGE_REPLACED:
            case "android.intent.action.QUICKBOOT_POWERON":
            case "com.htc.intent.action.QUICKBOOT_POWERON":
            case "MIUI.intent.action.QUICKBOOT_POWERON":
            case "com.nex.panel.RESTART_SERVICE":
                startService(context);
                break;
        }
    }

    private void startService(Context context) {
        // 1. Langsung start service
        try {
            Intent service = new Intent(context, BackgroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service);
            } else {
                context.startService(service);
            }
            Log.d(TAG, "BackgroundService started");
        } catch (Exception e) {
            Log.e(TAG, "startService error: " + e.getMessage());
        }

        // 2. Set watchdog alarm repeating setiap 2 menit
        setWatchdogAlarm(context);
    }

    private void setWatchdogAlarm(Context context) {
        try {
            Intent restart = new Intent(context, BootReceiver.class);
            restart.setAction("com.nex.panel.RESTART_SERVICE");
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pi = PendingIntent.getBroadcast(context, 9002, restart, flags);
            AlarmManager am  = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;

            long intervalMs = 2 * 60 * 1000L; // 2 menit
            long triggerAt  = System.currentTimeMillis() + intervalMs;

            // setExactAndAllowWhileIdle → bekerja meskipun Doze Mode aktif
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi);
            }
            // setRepeating sebagai backup
            am.setRepeating(AlarmManager.RTC_WAKEUP, triggerAt, intervalMs, pi);
            Log.d(TAG, "Watchdog alarm set: setiap 2 menit");
        } catch (Exception e) {
            Log.e(TAG, "setWatchdogAlarm: " + e.getMessage());
        }
    }
}
