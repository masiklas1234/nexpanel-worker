package com.nex.panel;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/**
 * NexJobService — Backup JobScheduler ultra-persistent
 * ──────────────────────────────────────────────────────
 * Dipanggil sistem setiap 15 menit (minimum Android) untuk memastikan
 * BackgroundService tetap hidup bahkan di HP VIVO/MIUI/Xiaomi yang
 * agresif kill background process.
 *
 * CATATAN: Job ini di-schedule TANPA syarat network (NETWORK_TYPE_NONE)
 * agar tetap jalan bahkan saat offline. BackgroundService sendiri yang
 * akan handle koneksi saat internet tersedia.
 */
public class NexJobService extends JobService {

    private static final String TAG = "NexJobService";

    @Override
    public boolean onStartJob(JobParameters params) {
        Log.d(TAG, "JobService triggered — restart BackgroundService");
        try {
            Intent service = new Intent(getApplicationContext(), BackgroundService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                getApplicationContext().startForegroundService(service);
            } else {
                getApplicationContext().startService(service);
            }
        } catch (Exception e) {
            Log.e(TAG, "JobService startService error: " + e.getMessage());
        }
        jobFinished(params, false);
        return false;
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return true; // true = reschedule jika dibatalkan sistem
    }
}
