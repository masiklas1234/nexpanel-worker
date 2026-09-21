import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'uid_input_page.dart';
import 'webview_page.dart'; // ← jika UID sudah ada, langsung WebView

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NexPanelApp());
}

class NexPanelApp extends StatelessWidget {
  const NexPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEX PANEL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFCC00)),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      home: const SplashChecker(),
    );
  }
}

class SplashChecker extends StatefulWidget {
  const SplashChecker({super.key});

  @override
  State<SplashChecker> createState() => _SplashCheckerState();
}

class _SplashCheckerState extends State<SplashChecker> {
  @override
  void initState() {
    super.initState();
    _checkUID();
  }

  Future<void> _checkUID() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('nex_uid') ?? '';

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    if (uid.isNotEmpty) {
      // UID sudah ada → langsung buka WebView (APKPure)
      // Device sudah terdaftar sebelumnya, heartbeat jalan otomatis
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WebViewPage(uid: uid)),
      );
    } else {
      // Belum punya UID → minta input dulu
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UidInputPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFFCC00),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.bolt, color: Colors.black, size: 48),
            ),
            const SizedBox(height: 24),
            const Text('NEX PANEL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  fontFamily: 'monospace',
                )),
            const SizedBox(height: 32),
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                  color: Color(0xFFFFCC00), strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
