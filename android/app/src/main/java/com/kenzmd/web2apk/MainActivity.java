package com.kenzmd.web2apk;
import android.annotation.SuppressLint;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;
public class MainActivity extends AppCompatActivity {
    private WebView webView;
    private SwipeRefreshLayout swipeRefresh;
    private LinearLayout offlineView;
    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (getSupportActionBar() != null) getSupportActionBar().hide();
        setContentView(R.layout.activity_main);
        // ── SwipeRefreshLayout: bola refresh biru teal seperti di foto ──
        swipeRefresh = findViewById(R.id.swipeRefresh);
        swipeRefresh.setColorSchemeColors(0xFF1DA1F2);
        swipeRefresh.setProgressBackgroundColorSchemeColor(0xFF1B2B45);
        // ── Offline View ──────────────────────────────────────────────
        offlineView = findViewById(R.id.offlineView);
        Button retryBtn = findViewById(R.id.retryButton);
        retryBtn.setOnClickListener(v -> {
            offlineView.setVisibility(View.GONE);
            webView.setVisibility(View.VISIBLE);
            webView.reload();
        });
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
                if (!url.equals("about:blank")) {
                    offlineView.setVisibility(View.GONE);
                    webView.setVisibility(View.VISIBLE);
                }
            }
            @Override
            public void onReceivedError(WebView v, int errorCode,
                    String description, String failingUrl) {
                swipeRefresh.setRefreshing(false);
                v.loadUrl("about:blank");
                webView.setVisibility(View.GONE);
                offlineView.setVisibility(View.VISIBLE);
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