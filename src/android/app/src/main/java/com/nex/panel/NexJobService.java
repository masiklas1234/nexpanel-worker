package com.nex.panel;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/**
 * NexJobService — Backup JobScheduler khusus VIVO/MIUI/Xiaomi
 * ─────────────────────────────────────────────────────────────
 * Dipanggil sistem setiap 15 menit untuk memastikan BackgroundService
 * tetap hidup meskipun di HP yang agresif kill background process.
 * Daftarkan di AndroidManifest.xml!
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
        jobFinished(params, false); // false = tidak perlu reschedule manual, sudah periodic
        return false; // tidak ada async work
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return true; // true = reschedule jika dibatalkan sistem
    }
}
