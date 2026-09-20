import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class WebViewPage extends StatefulWidget {
  final String uid;
  const WebViewPage({super.key, required this.uid});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _ctrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWebView();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _initWebView() {
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 12; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/112.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) async {
          if (mounted) setState(() => _loading = false);
          // Hanya disable overscroll-behavior agar tidak ada putih
          // TIDAK disable scroll agar halaman tetap bisa di-scroll
          await _ctrl.runJavaScript(r'''
            (function() {
              var s = document.createElement('style');
              s.innerHTML =
                'html { overscroll-behavior-y: none !important; }' +
                'body { overscroll-behavior-y: none !important; }';
              document.head.appendChild(s);
            })();
          ''');
        },
        onWebResourceError: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse('https://m.apkpure.com/id/'));

    // Matikan overscroll glow di native Android WebView level
    final platform = _ctrl.platform;
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (await _ctrl.canGoBack()) {
          _ctrl.goBack();
          return false;
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Langsung Stack tanpa NotificationListener
        // WebViewWidget handle gesture scroll sendiri secara native
        body: Stack(
          children: [
            // WebView fullscreen - scroll bebas atas bawah
            WebViewWidget(controller: _ctrl),
            // Loading overlay
            if (_loading)
              Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFFFFCC00), strokeWidth: 3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
