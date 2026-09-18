-keep class com.sync.xxx.** { *; }  # FIX: package name dikoreksi dari ndraoffc.cyberpro ke com.sync.xxx
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
