package com.kenzmd.web2apk;
import android.annotation.SuppressLint;
import android.graphics.Color;
import android.os.Bundle;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.appcompat.app.AppCompatActivity;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;
public class MainActivity extends AppCompatActivity {
    private WebView webView;
    private SwipeRefreshLayout swipeRefresh;
    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (getSupportActionBar() != null) getSupportActionBar().hide();
        setContentView(R.layout.activity_main);
        // ── SwipeRefreshLayout: bola refresh biru teal seperti di foto ──
        swipeRefresh = findViewById(R.id.swipeRefresh);
        swipeRefresh.setProgressViewOffset(false, 0, 120);
        swipeRefresh.setSize(SwipeRefreshLayout.LARGE);
        swipeRefresh.setColorSchemeColors(0xFF00B4D8);
        swipeRefresh.setProgressBackgroundColorSchemeColor(0xFF1B2A40);
        // ── WebView ───────────────────────────────────────────────────
        webView = findViewById(R.id.webView);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setBuiltInZoomControls(false);
        s.setSupportZoom(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        webView.setOverScrollMode(android.view.View.OVER_SCROLL_ALWAYS);
        webView.setScrollBarStyle(android.view.View.SCROLLBARS_INSIDE_OVERLAY);
        webView.setVerticalScrollBarEnabled(false);
        webView.setHorizontalScrollBarEnabled(false);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView v, String url) {
                super.onPageFinished(v, url);
                swipeRefresh.setRefreshing(false);
            }
            @Override
            public void onReceivedError(WebView v, int errorCode,
                    String description, String failingUrl) {
                swipeRefresh.setRefreshing(false);
            }
        });
        webView.setWebChromeClient(new WebChromeClient());
        swipeRefresh.setOnRefreshListener(() -> webView.reload());
        webView.loadUrl(getString(R.string.website_url));
    }
    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
    @Override protected void onPause()   { super.onPause();   if (webView != null) webView.onPause();  }
    @Override protected void onResume()  { super.onResume();  if (webView != null) webView.onResume(); }
    @Override protected void onDestroy() {
        if (webView != null) { webView.stopLoading(); webView.destroy(); }
        super.onDestroy();
    }
}