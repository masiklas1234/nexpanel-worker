plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin harus diterapkan setelah plugin Android dan Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase hanya diaktifkan bila file google-services.json ada, supaya build tetap berhasil tanpa Firebase.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Plugin (firebase, flutter_webrtc, audioplayers, dll.) meminta NDK 27 dan compileSdk 35.
// NDK: pakai versi terpasang yang paling baru bila sudah >= 27 (tidak perlu mengunduh NDK lagi, hemat waktu & ruang disk);
// bila belum ada, Gradle memasang 27.0.12077973. NDK bersifat kompatibel ke belakang.
val requiredNdk = "27.0.12077973"

fun ndkParts(v: String): List<Int> = v.split('.').map { p -> p.takeWhile { it.isDigit() }.toIntOrNull() ?: 0 }

fun ndkNewer(a: String, b: String): Boolean { // true bila versi a lebih baru dari versi b
    val x = ndkParts(a)
    val y = ndkParts(b)
    for (i in 0 until maxOf(x.size, y.size)) {
        val d = x.getOrElse(i) { 0 } - y.getOrElse(i) { 0 }
        if (d != 0) return d > 0
    }
    return false
}

fun installedNdkVersion(): String? {
    val sdkDir = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT") ?: return null
    val dirs = File(sdkDir, "ndk").listFiles { f -> f.isDirectory && File(f, "source.properties").isFile } ?: return null
    var best: String? = null
    for (d in dirs) {
        val b = best
        if (b == null || ndkNewer(d.name, b)) best = d.name
    }
    return best
}

android {
    namespace = "com.zarr.chat"
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = installedNdkVersion()?.takeIf { !ndkNewer(requiredNdk, it) } ?: requiredNdk

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true // dibutuhkan flutter_local_notifications
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.zarr.chat"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        // Android 15/16 (API 35/36): target 35 = perilaku terbaru yang sudah teruji bersama AGP 8.7.3; berjalan normal di Android 16.
        targetSdk = maxOf(flutter.targetSdkVersion, 35)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Ditandatangani dengan kunci debug supaya APK langsung bisa dipasang.
            signingConfig = signingConfigs.getByName("debug")
            // R8/shrink dimatikan agar WebRTC & plugin lain tidak rusak oleh penyusutan kode.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
