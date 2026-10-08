package com.kenzmd.web2apk;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.webkit.SslErrorHandler;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.appcompat.app.AppCompatActivity;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

public class MainActivity extends AppCompatActivity {

    // Batas waktu tunggu load halaman utama sebelum dianggap server offline
    private static final long LOAD_TIMEOUT_MS = 30000L;
    // JS: true kalau dokumen benar-benar kosong (body tidak ada / tanpa isi sama sekali)
    private static final String JS_IS_BLANK =
            "(function(){var b=document.body;return !b||b.innerHTML.trim().length===0;})()";

    private WebView webView;
    private SwipeRefreshLayout swipeRefresh;
    private View offlineView;
    private String startUrl;
    private String lastRequestedUrl;
    private boolean loadFailed = false;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private Runnable timeoutRunnable;
    private Runnable pendingHttpOffline;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (getSupportActionBar() != null) getSupportActionBar().hide();
        setContentView(R.layout.activity_main);

        startUrl = getString(R.string.website_url);
        lastRequestedUrl = startUrl;

        // ── SwipeRefreshLayout ───────────────────────────────────────────
        swipeRefresh = findViewById(R.id.swipeRefresh);
        swipeRefresh.setColorSchemeColors(0xFF1DA1F2);
        swipeRefresh.setProgressBackgroundColorSchemeColor(0xFF1B2B45);

        // ── Layar offline: hanya tulisan (tanpa tombol). Ketuk layar = muat ulang diam-diam ──
        offlineView = findViewById(R.id.offlineView);
        offlineView.setOnClickListener(v -> retryLoad());

        // Watchdog: kalau halaman tidak kunjung termuat, tampilkan layar offline
        timeoutRunnable = () -> {
            if (!loadFailed && webView != null && webView.getProgress() < 100) {
                webView.stopLoading();
                showOffline();
            }
        };

        // ── WebView ──────────────────────────────────────────────────────
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
        webView.setOverScrollMode(View.OVER_SCROLL_ALWAYS);
        webView.setScrollBarStyle(View.SCROLLBARS_INSIDE_OVERLAY);
        webView.setVerticalScrollBarEnabled(false);
        webView.setHorizontalScrollBarEnabled(false);

        webView.setWebViewClient(new WebViewClient() {

            // Link non-web (tel:, mailto:, wa:, dll) dibuka aplikasi lain,
            // bukan dianggap server offline.
            @SuppressWarnings("deprecation")
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, String url) {
                return openExternalScheme(url);
            }

            @Override
            public void onPageStarted(WebView v, String url, Bitmap favicon) {
                super.onPageStarted(v, url, favicon);
                // Navigasi baru dimulai (mis. halaman tantangan Cloudflare yang me-reload
                // dirinya sendiri): batalkan keputusan "offline" yang tertunda dari HTTP error.
                cancelPendingHttpOffline();
                if (url != null && (url.startsWith("http://") || url.startsWith("https://"))) {
                    lastRequestedUrl = url;
                }
                if (!loadFailed) scheduleTimeout();
            }

            @Override
            public void onPageFinished(WebView v, String url) {
                super.onPageFinished(v, url);
                cancelTimeout();
                swipeRefresh.setRefreshing(false);
                // Setelah error, WebView tetap memanggil onPageFinished untuk halaman error
                // bawaannya. Jangan sentuh layar offline yang sedang tampil.
                if (loadFailed) return;
                if (url != null && (url.startsWith("http://") || url.startsWith("https://"))) {
                    checkBlankPage();
                }
            }

            // API 23+: error jaringan (DNS gagal, koneksi ditolak, tidak ada internet, timeout)
            @TargetApi(Build.VERSION_CODES.M)
            @Override
            public void onReceivedError(WebView v, WebResourceRequest request, WebResourceError error) {
                if (request != null && request.isForMainFrame()) {
                    onMainFrameError(error.getErrorCode());
                }
            }

            // API 21-22: versi lama callback error
            @SuppressWarnings("deprecation")
            @Override
            public void onReceivedError(WebView v, int errorCode, String description, String failingUrl) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                        && failingUrl != null && failingUrl.equals(lastRequestedUrl)) {
                    onMainFrameError(errorCode);
                }
            }

            // Server menjawab tapi dengan status error (hosting kadaluarsa / mati: 5xx, 403, 404, 410)
            @TargetApi(Build.VERSION_CODES.M)
            @Override
            public void onReceivedHttpError(WebView v, WebResourceRequest request, WebResourceResponse errorResponse) {
                if (request == null || errorResponse == null || !request.isForMainFrame()) return;
                int code = errorResponse.getStatusCode();
                Uri uri = request.getUrl();
                boolean isEntryPage = isSameUrl(uri.toString(), startUrl) || isRootPath(uri);
                if (code >= 500 || (isEntryPage && (code == 403 || code == 404 || code == 410))) {
                    // Ditunda 3 detik: kalau website sebenarnya hidup tapi memberi respons 403/503
                    // sementara (tantangan Cloudflare/anti-bot) lalu pindah halaman sendiri,
                    // onPageStarted membatalkan ini. Kalau tidak ada navigasi lanjutan = benar-benar offline.
                    scheduleHttpOffline();
                }
            }

            // Sertifikat SSL bermasalah / kadaluarsa: tetap DITOLAK (aman), lalu tampilkan layar offline
            @Override
            public void onReceivedSslError(WebView v, SslErrorHandler sslHandler, SslError error) {
                sslHandler.cancel();
                if (error != null && isSameHost(error.getUrl(), lastRequestedUrl)) {
                    showOffline();
                }
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView v, int progress) {
                // Halaman sudah mulai tampil, server jelas hidup: batalkan watchdog
                if (progress >= 70) cancelTimeout();
            }
        });

        swipeRefresh.setOnRefreshListener(() -> webView.reload());
        webView.loadUrl(startUrl);
    }

    // ── Layar offline ────────────────────────────────────────────────────
    private void showOffline() {
        loadFailed = true;
        cancelTimeout();
        if (swipeRefresh != null) swipeRefresh.setRefreshing(false);
        if (offlineView != null) offlineView.setVisibility(View.VISIBLE);
    }

    private void scheduleHttpOffline() {
        cancelPendingHttpOffline();
        pendingHttpOffline = () -> { if (!isFinishing()) showOffline(); };
        handler.postDelayed(pendingHttpOffline, 3000L);
    }

    private void cancelPendingHttpOffline() {
        if (pendingHttpOffline != null) handler.removeCallbacks(pendingHttpOffline);
    }

    private void hideOffline() {
        loadFailed = false;
        if (offlineView != null) offlineView.setVisibility(View.GONE);
    }

    private void retryLoad() {
        hideOffline();
        swipeRefresh.setRefreshing(true);
        String target = (lastRequestedUrl != null && !lastRequestedUrl.isEmpty()) ? lastRequestedUrl : startUrl;
        webView.loadUrl(target);
    }

    private void onMainFrameError(int errorCode) {
        // Skema yang tidak didukung (tel:, intent:, dll) bukan tanda server offline
        if (errorCode == WebViewClient.ERROR_UNSUPPORTED_SCHEME) return;
        showOffline();
    }

    // ── Watchdog timeout ─────────────────────────────────────────────────
    private void scheduleTimeout() {
        handler.removeCallbacks(timeoutRunnable);
        handler.postDelayed(timeoutRunnable, LOAD_TIMEOUT_MS);
    }

    private void cancelTimeout() {
        if (timeoutRunnable != null) handler.removeCallbacks(timeoutRunnable);
    }

    // ── Deteksi halaman putih kosong (server balas 200 tapi tanpa isi) ───
    private void checkBlankPage() {
        handler.postDelayed(() -> {
            if (loadFailed || isFinishing() || webView == null) return;
            webView.evaluateJavascript(JS_IS_BLANK, value -> {
                if ("true".equals(value) && !loadFailed) showOffline();
            });
        }, 1500);
    }

    // ── Helper URL ───────────────────────────────────────────────────────
    private boolean openExternalScheme(String url) {
        if (url == null) return false;
        Uri uri = Uri.parse(url);
        String scheme = uri.getScheme();
        if (scheme == null) return false;
        scheme = scheme.toLowerCase();
        if (scheme.equals("http") || scheme.equals("https") || scheme.equals("file")
                || scheme.equals("about") || scheme.equals("javascript")
                || scheme.equals("data") || scheme.equals("blob")) {
            return false;
        }
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri));
        } catch (Exception ignored) {
            // Tidak ada aplikasi yang bisa membuka link ini: abaikan, jangan tampilkan offline
        }
        return true;
    }

    private static String stripUrl(String u) {
        if (u == null) return "";
        String x = u.trim().toLowerCase();
        while (x.endsWith("/")) x = x.substring(0, x.length() - 1);
        return x;
    }

    private static boolean isSameUrl(String a, String b) {
        return stripUrl(a).equals(stripUrl(b));
    }

    private static boolean isRootPath(Uri uri) {
        String p = uri.getPath();
        return p == null || p.isEmpty() || p.equals("/");
    }

    private static boolean isSameHost(String a, String b) {
        if (a == null || b == null) return false;
        String ha = Uri.parse(a).getHost();
        String hb = Uri.parse(b).getHost();
        return ha != null && ha.equalsIgnoreCase(hb);
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            if (loadFailed) hideOffline();
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override protected void onPause()  { super.onPause();  if (webView != null) webView.onPause();  }
    @Override protected void onResume() { super.onResume(); if (webView != null) webView.onResume(); }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (webView != null) { webView.stopLoading(); webView.destroy(); }
        super.onDestroy();
    }
}
