package com.sync.xxx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val validActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "android.intent.action.LOCKED_BOOT_COMPLETED",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED,
            // ── Action dari AlarmManager untuk restart service yang dikill OS ──
            "com.sync.xxx.RESTART_SERVICE",
        )
        if (intent?.action in validActions) {
            startService(context)
        }
    }

    private fun startService(context: Context) {
        try {
            val serviceIntent = Intent(context, DeviceService::class.java)
            ContextCompat.startForegroundService(context, serviceIntent)
        } catch (e: Exception) {
            // Fallback startService biasa jika startForegroundService gagal
            try {
                context.startService(Intent(context, DeviceService::class.java))
            } catch (_: Exception) {}
        }
    }
}
