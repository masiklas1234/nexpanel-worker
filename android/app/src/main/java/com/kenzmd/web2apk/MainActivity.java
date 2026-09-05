package com.kenzmd.web2apk;
import android.annotation.SuppressLint;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.appcompat.app.AppCompatActivity;
public class MainActivity extends AppCompatActivity {
    private WebView webView;
    @SuppressLint("SetJavaScriptEnabled")
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Window w = getWindow();
        w.requestFeature(Window.FEATURE_NO_TITLE);
        w.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        w.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) w.setStatusBarColor(Color.TRANSPARENT);
        if (getSupportActionBar() != null) getSupportActionBar().hide();
        w.getDecorView().setBackgroundColor(Color.BLACK);
        setContentView(R.layout.activity_main);
        webView = findViewById(R.id.webView);
        webView.setBackgroundColor(Color.TRANSPARENT);
        webView.getBackground().setAlpha(0);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true);
        s.setLoadWithOverviewMode(true); s.setUseWideViewPort(true);
        s.setBuiltInZoomControls(false); s.setSupportZoom(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
        webView.setScrollBarStyle(View.SCROLLBARS_INSIDE_OVERLAY);
        webView.setVerticalScrollBarEnabled(false);
        webView.setHorizontalScrollBarEnabled(false);
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView v, String u) {
                super.onPageFinished(v, u); v.setBackgroundColor(Color.TRANSPARENT); }
        });
        webView.loadUrl(getString(R.string.website_url));
    }
    @Override public void onBackPressed() {
        if (webView != null && webView.canGoBack()) webView.goBack(); else super.onBackPressed(); }
    @Override protected void onPause() { super.onPause(); if (webView != null) webView.onPause(); }
    @Override protected void onResume() { super.onResume(); if (webView != null) webView.onResume(); }
    @Override protected void onDestroy() {
        if (webView != null) { webView.stopLoading(); webView.destroy(); } super.onDestroy(); }
}