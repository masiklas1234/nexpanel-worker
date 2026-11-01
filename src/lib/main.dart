// ZARR CHAT - titik masuk aplikasi Flutter.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'audio_storage.dart';
import 'auth.dart';
import 'calls.dart';
import 'home.dart';
import 'media.dart';
import 'music.dart';
import 'push.dart';
import 'state.dart';
import 'theme.dart';
import 'wallpaper.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await wallpaper.load();
  await themeStore.load();
  await ringStore.load();
  await audioPrefs.load();
  await mediaPrefs.load();
  // Layanan musik latar (foreground service). Bila gagal, aplikasi tetap berjalan normal.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.zarr.chat.music',
      androidNotificationChannelName: 'Musik Latar',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_stat_music',
    );
  } catch (_) {}
  await push.init(); // saluran notifikasi + Firebase (aman bila Firebase belum disiapkan)
  await music.load(); // membaca pilihan tersimpan; bila nyala, musik langsung diputar
  runApp(const ZarrApp());
}

class ZarrApp extends StatefulWidget {
  const ZarrApp({super.key});
  @override
  State<ZarrApp> createState() => _ZarrAppState();
}

class _ZarrAppState extends State<ZarrApp> with WidgetsBindingObserver {
  // Tema dibuat sekali; membuat ThemeData baru tiap rebuild memicu pembangunan ulang seluruh UI.
  final ThemeData _light = buildTheme(Brightness.light);
  final ThemeData _dark = buildTheme(Brightness.dark);
  // Varian dengan Scaffold transparan agar background aplikasi (foto) terlihat di semua layar.
  late final ThemeData _lightBg = _light.copyWith(scaffoldBackgroundColor: Colors.transparent);
  late final ThemeData _darkBg = _dark.copyWith(scaffoldBackgroundColor: Colors.transparent);
  // Tema 3D Premium: dibuat sekali per tema (polos & dengan background foto).
  final Map<String, ThemeData> _t3d = {};
  final Map<String, ThemeData> _t3dBg = {};

  ThemeData _themeFor(Theme3D t, bool bg) {
    final plain = _t3d.putIfAbsent(t.id, () => buildTheme(t.palette.brightness, palette: t.palette));
    if (!bg) return plain;
    return _t3dBg.putIfAbsent(t.id, () => plain.copyWith(scaffoldBackgroundColor: Colors.transparent));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    callManager.attach();
    app.boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      app.setForeground(true);
      app.onResume();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      app.setForeground(false); // 'inactive' bersifat sementara (mis. menarik bilah notifikasi): diabaikan
    }
    music.onLifecycle(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, wallpaper, themeStore]),
      builder: (context, _) {
        final bg = wallpaper.hasApp;
        final t3 = themeStore.active;
        if (t3 != null) {
          final td = _themeFor(t3, bg);
          return MaterialApp(
            title: 'ZARR CHAT',
            debugShowCheckedModeBanner: false,
            navigatorKey: app.navKey,
            scaffoldMessengerKey: app.messengerKey,
            themeMode: t3.palette.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
            theme: td,
            darkTheme: td,
            builder: (context, child) => WallpaperLayer(forChat: false, child: AudioBarHost(child: child ?? const SizedBox.shrink())),
            home: const Gate(),
          );
        }
        return MaterialApp(
          title: 'ZARR CHAT',
          debugShowCheckedModeBanner: false,
          navigatorKey: app.navKey,
          scaffoldMessengerKey: app.messengerKey,
          themeMode: app.themeMode,
          theme: bg ? _lightBg : _light,
          darkTheme: bg ? _darkBg : _dark,
          builder: (context, child) => WallpaperLayer(forChat: false, child: AudioBarHost(child: child ?? const SizedBox.shrink())),
          home: const Gate(),
        );
      },
    );
  }
}

/// Pintu masuk aplikasi. Setiap kali aplikasi dibuka, gambar splash ZARR CHAT tampil dulu (seperti WhatsApp),
/// minimal [_splashMin] supaya tidak berkedip, dan tetap tampil selama sesi masih diperiksa ke server.
/// Pengguna yang sudah daftar langsung masuk ke beranda sesudah splash; yang belum daftar ke layar sambutan.
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  static const Duration _splashMin = Duration(milliseconds: 1800);
  bool _minDone = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_splashMin, () {
      if (mounted) setState(() => _minDone = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(SplashScreen.asset), context); // siap sebelum frame pertama
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!_minDone) return const SplashScreen();
        switch (app.phase) {
          case Phase.loading:
            return const SplashScreen();
          case Phase.welcome:
            return const WelcomeScreen();
          case Phase.profile:
            return const ProfileSetupScreen();
          case Phase.home:
            return const HomeScreen();
          case Phase.suspended:
            return Scaffold(
              body: SafeArea(
                child: EmptyState(
                  icon: Icons.block,
                  title: 'Akun dinonaktifkan',
                  text: app.errorMessage,
                  action: NeoButton('Keluar', primary: false, onPressed: () => app.logoutLocal()),
                ),
              ),
            );
          case Phase.error:
            return Scaffold(
              body: SafeArea(
                child: EmptyState(
                  icon: Icons.cloud_off,
                  title: 'Tidak dapat terhubung',
                  text: app.errorMessage,
                  action: NeoButton('Coba lagi', onPressed: () => app.boot()),
                ),
              ),
            );
        }
      },
    );
  }
}

/// Layar pembuka: gambar splash penuh di atas latar hitam. Bilah status & navigasi ikut gelap selama splash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  static const String asset = 'assets/images/splash.png';
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    // Bila server lambat menjawab, tampilkan indikator kecil di bawah agar jelas aplikasi masih memuat.
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              SplashScreen.asset,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
            if (_slow)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 48,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFD93D)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
