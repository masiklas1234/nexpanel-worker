package com.zarr.chat

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.app.NotificationManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// AudioServiceActivity: berbagi mesin Flutter dengan layanan musik latar,
// sehingga musik tetap berjalan saat aplikasi ditutup / tidak sedang dibuka.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13+: izin notifikasi dibutuhkan agar kontrol musik tampil di bilah notifikasi.
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    // Menyalin foto/video ke galeri: Pictures/ZARR CHAT atau Movies/ZARR CHAT.
    // Android 10+ lewat MediaStore (tanpa izin); Android 9 ke bawah butuh izin WRITE_EXTERNAL_STORAGE.
    // Hasil: "ok", "permission" (izin baru diminta, pengguna perlu mengetuk Simpan lagi), "missing", atau "error".
    private fun saveToGallery(path: String, name: String, mime: String, video: Boolean): String {
        val src = File(path)
        if (!src.exists()) return "missing"
        val folder = "ZARR CHAT"
        if (Build.VERSION.SDK_INT >= 29) {
            val root = if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$root/$folder")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = if (video) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val uri = contentResolver.insert(collection, values) ?: return "error"
            return try {
                val out = contentResolver.openOutputStream(uri)
                if (out == null) {
                    contentResolver.delete(uri, null, null)
                    "error"
                } else {
                    out.use { o -> src.inputStream().use { it.copyTo(o) } }
                    val done = ContentValues()
                    done.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, done, null, null)
                    "ok"
                }
            } catch (e: Exception) {
                try {
                    contentResolver.delete(uri, null, null)
                } catch (e2: Exception) {
                }
                "error"
            }
        }
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            runOnUiThread { requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 1002) }
            return "permission"
        }
        val base = Environment.getExternalStoragePublicDirectory(if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES)
        val dir = File(base, folder)
        if (!dir.exists()) dir.mkdirs()
        val dest = File(dir, name)
        src.copyTo(dest, true)
        MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), arrayOf(mime), null)
        return "ok"
    }

    // Memasukkan MP3 pilihan pengguna ke penyimpanan suara sistem (Notifications / Ringtones) agar notifikasi Android bisa memutarnya:
    // suara saluran notifikasi dibaca oleh sistem Android, bukan oleh aplikasi, jadi berkasnya harus ada di tempat yang bisa diakses sistem.
    // Hasil: alamat content:// (berhasil), "permission" (Android 9 ke bawah: izin baru diminta, ulangi), "missing", atau "error".
    private fun installSound(path: String, name: String, mime: String, ringtone: Boolean): String {
        val src = File(path)
        if (!src.exists()) return "missing"
        val folder = "ZARR CHAT"
        if (Build.VERSION.SDK_INT >= 29) {
            val root = if (ringtone) Environment.DIRECTORY_RINGTONES else Environment.DIRECTORY_NOTIFICATIONS
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$root/$folder")
                put(MediaStore.Audio.Media.IS_RINGTONE, if (ringtone) 1 else 0)
                put(MediaStore.Audio.Media.IS_NOTIFICATION, if (ringtone) 0 else 1)
                put(MediaStore.Audio.Media.IS_MUSIC, 0)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = contentResolver.insert(collection, values) ?: return "error"
            return try {
                val out = contentResolver.openOutputStream(uri)
                if (out == null) {
                    contentResolver.delete(uri, null, null)
                    "error"
                } else {
                    out.use { o -> src.inputStream().use { it.copyTo(o) } }
                    val done = ContentValues()
                    done.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, done, null, null)
                    uri.toString()
                }
            } catch (e: Exception) {
                try {
                    contentResolver.delete(uri, null, null)
                } catch (e2: Exception) {
                }
                "error"
            }
        }
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            runOnUiThread { requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 1003) }
            return "permission"
        }
        val base = Environment.getExternalStoragePublicDirectory(if (ringtone) Environment.DIRECTORY_RINGTONES else Environment.DIRECTORY_NOTIFICATIONS)
        val dir = File(base, folder)
        if (!dir.exists()) dir.mkdirs()
        val dest = File(dir, name)
        src.copyTo(dest, true)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DATA, dest.absolutePath)
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.IS_RINGTONE, if (ringtone) 1 else 0)
            put(MediaStore.Audio.Media.IS_NOTIFICATION, if (ringtone) 0 else 1)
            put(MediaStore.Audio.Media.IS_MUSIC, 0)
        }
        val uri = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values) ?: return "error"
        return uri.toString()
    }

    // Durasi berkas audio dalam milidetik; 0 bila bukan audio yang bisa dibaca.
    private fun audioDurationMs(path: String): Long {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            0L
        } finally {
            try {
                r.release()
            } catch (e2: Exception) {
            }
        }
    }

    // Saluran ke Flutter: nyalakan / matikan layanan foreground panggilan.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarr.chat/call").setMethodCallHandler { call, result ->
            try {
                val intent = Intent(this, CallService::class.java)
                when (call.method) {
                    "start" -> {
                        intent.putExtra("title", call.argument<String>("title") ?: "Panggilan ZARR CHAT")
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }
        // Saluran ke Flutter: suara notifikasi / nada panggilan pilihan pengguna (MP3 sendiri).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarr.chat/sounds").setMethodCallHandler { call, result ->
            when (call.method) {
                "install" -> {
                    val path = call.argument<String>("path") ?: ""
                    val name = call.argument<String>("name") ?: "zarr_${System.currentTimeMillis()}.mp3"
                    val mime = call.argument<String>("mime") ?: "audio/mpeg"
                    val ringtone = call.argument<Boolean>("ringtone") ?: false
                    Thread {
                        val r = try {
                            installSound(path, name, mime, ringtone)
                        } catch (e: Exception) {
                            "error"
                        }
                        runOnUiThread { result.success(r) }
                    }.start()
                }
                "remove" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    Thread {
                        try {
                            if (uri.isNotEmpty()) contentResolver.delete(Uri.parse(uri), null, null)
                        } catch (e: Exception) {
                            // sudah terhapus / bukan milik aplikasi: abaikan
                        }
                        runOnUiThread { result.success(true) }
                    }.start()
                }
                "durationMs" -> {
                    val path = call.argument<String>("path") ?: ""
                    Thread {
                        val d = try {
                            audioDurationMs(path)
                        } catch (e: Exception) {
                            0L
                        }
                        runOnUiThread { result.success(d) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        // Saluran ke Flutter: simpan foto/video ke galeri HP.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarr.chat/gallery").setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> {
                    val path = call.argument<String>("path") ?: ""
                    val name = call.argument<String>("name") ?: "ZARR_${System.currentTimeMillis()}"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val video = call.argument<Boolean>("video") ?: false
                    Thread {
                        val r = try {
                            saveToGallery(path, name, mime, video)
                        } catch (e: Exception) {
                            "error"
                        }
                        runOnUiThread { result.success(r) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        // Saluran ke Flutter: perlindungan layar untuk foto/video "sekali lihat".
        // FLAG_SECURE memblokir screenshot, perekaman layar, dan pratinjau di daftar aplikasi terbaru selama flag menyala.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarr.chat/secure").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setSecure" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }
        // Saluran ke Flutter: buka pengaturan notifikasi Android untuk aplikasi ini.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarr.chat/system").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "notificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= 26) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(android.net.Uri.parse("package:$packageName"))
                        }
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    // true bila ZARR CHAT sudah dikecualikan dari penghematan baterai (notifikasi tidak ditunda sistem).
                    "batteryUnrestricted" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(Build.VERSION.SDK_INT < 23 || pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    // Dialog sistem "Izinkan berjalan di latar belakang?" agar push tidak tertahan saat HP diam / main game.
                    "requestBatteryExemption" -> {
                        try {
                            val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(android.net.Uri.parse("package:$packageName"))
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                        } catch (e: Exception) {
                            // Sebagian HP tidak punya dialog ini: buka daftar pengecualian baterai.
                            val i = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                        }
                        result.success(true)
                    }
                    "notificationsEnabled" -> {
                        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        result.success(Build.VERSION.SDK_INT < 24 || nm.areNotificationsEnabled())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }
}
