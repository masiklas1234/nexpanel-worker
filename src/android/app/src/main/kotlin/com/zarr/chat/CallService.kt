package com.zarr.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

// Layanan foreground selama panggilan suara/video. Tanpa ini Android menghentikan mikrofon
// begitu aplikasi dikecilkan, sehingga lawan bicara tidak lagi mendengar suara kita.
class CallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Panggilan", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val pi = if (open != null) {
            PendingIntent.getActivity(
                this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val title = intent?.getStringExtra("title") ?: "Panggilan ZARR CHAT"
        builder.setContentTitle(title)
            .setContentText("Panggilan sedang berlangsung. Ketuk untuk kembali.")
            .setSmallIcon(R.drawable.ic_stat_music)
            .setOngoing(true)
        if (pi != null) builder.setContentIntent(pi)
        val n = builder.build()
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIF_ID, n)
            }
        } catch (e: Exception) {
            // Bila sistem menolak, panggilan tetap berjalan saat aplikasi terbuka.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        const val CHANNEL_ID = "zarr_call"
        const val NOTIF_ID = 4107
    }
}
