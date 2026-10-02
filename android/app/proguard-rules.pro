# Jaga class app sendiri
-keep class com.kenzmd.web2apk.** { *; }

# WebView — jangan di-strip, wajib untuk load website
-keep class android.webkit.** { *; }
-keepclassmembers class * extends android.webkit.WebViewClient { *; }
-keepclassmembers class * extends android.webkit.WebChromeClient { *; }

# SwipeRefreshLayout
-keep class androidx.swiperefreshlayout.** { *; }

# AndroidX AppCompat
-keep class androidx.appcompat.** { *; }

# Hapus log debug (kecilkan APK)
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
}
