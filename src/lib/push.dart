// ZARR CHAT - notifikasi HP: push FCM (aplikasi tertutup / sedang main game) + notifikasi lokal.
//
// Cara kerja:
//  - Server mengirim push FCM ke HP bila aplikasi TIDAK sedang dibuka: pesan, telepon masuk, telepon tak terjawab, broadcast.
//    Push ini ditampilkan oleh sistem Android (muncul di atas game, ada suara & getar sesuai saluran notifikasi).
//  - Bila Firebase belum disiapkan (tidak ada google-services.json), aplikasi tetap jalan normal; notifikasi lokal
//    tetap muncul selama aplikasi masih tersambung di latar belakang.
//  - Aplikasi sedang dibuka: tidak ada push (sudah ada banner + nada di dalam aplikasi), kecuali broadcast.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_storage.dart';
import 'chats_tab.dart';
import 'groups.dart';
import 'models.dart';
import 'state.dart';

// ID saluran harus sama dengan CH di backend (src/services/push.js). "_v2" = suara kustom yang lebih keras (android/app/src/main/res/raw).
const String kChMessages = 'zarr_messages_v2';
const String kChCalls = 'zarr_calls_v2';
const String kChBroadcast = 'zarr_broadcast_v2';
const String _icon = 'ic_stat_zarr';

// Suara notifikasi pilihan pengguna. Suara sebuah saluran Android tidak bisa diubah setelah dibuat, jadi setiap suara punya saluran
// sendiri: pesan = "zarr_msg_<suara>" (ping, pop, lonceng, dingdong) atau "zarr_msg_custom_<versi>" (MP3 sendiri);
// panggilan = kChCalls (bawaan) atau "zarr_call_custom_<versi>". Server diberi tahu ID-nya (lihat registerDevice) agar push FCM
// saat aplikasi tertutup berbunyi sama. kChMessages / kChCalls tetap dipakai sebagai nama "logis" di seluruh aplikasi.
String get kMsgChannelId => audioPrefs.soundId == 'custom' ? 'zarr_msg_custom_${audioPrefs.customNotifVer}' : 'zarr_msg_${audioPrefs.soundId}';
String get kCallChannelId => audioPrefs.callSoundId == 'custom' ? 'zarr_call_custom_${audioPrefs.customCallVer}' : kChCalls;

AndroidNotificationSound _msgSound() =>
    audioPrefs.soundId == 'custom' ? UriAndroidNotificationSound(audioPrefs.customNotifUri) : RawResourceAndroidNotificationSound('notif_${audioPrefs.soundId}');
AndroidNotificationSound _callSound() =>
    audioPrefs.callSoundId == 'custom' ? UriAndroidNotificationSound(audioPrefs.customCallUri) : const RawResourceAndroidNotificationSound('notif_call');

/// Dijalankan Android di isolate terpisah saat ada pesan data-only dan aplikasi di latar belakang/tertutup.
/// Dipakai untuk menghapus notifikasi dering saat panggilan sudah berakhir / dibatalkan / diangkat di tempat lain.
@pragma('vm:entry-point')
Future<void> zarrFirebaseBackgroundHandler(RemoteMessage m) async {
  try {
    if (m.data['type'] != 'call_end') return;
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings(_icon)));
    await plugin.cancel(0, tag: 'call:${m.data['callId']}');
  } catch (_) {
    // abaikan: notifikasi akan hilang sendiri
  }
}

class PushService {
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  bool _firebaseReady = false;
  bool _listening = false;
  String? _token;
  bool _registered = false;
  Map<String, dynamic>? _pendingTap;
  StreamSubscription<String>? _refreshSub;
  Timer? _retryTimer;
  final Map<String, DateTime> _lastShown = {};
  Future<void>? _logoutTask; // pembersihan keluar akun yang sedang berjalan; pendaftaran perangkat baru menunggunya

  /// Token FCM perangkat ini (null bila belum ada). Dikirim saat keluar agar server melepasnya dari akun.
  String? get currentToken => _token;

  /// true bila push FCM aktif untuk akun ini (token terdaftar di server).
  bool get active => _firebaseReady && _token != null && _registered;

  // ---------------------------------------------------------------- persiapan (dipanggil dari main)
  Future<void> init() async {
    await _initLocal();
    await _initFirebase();
  }

  Future<void> _initLocal() async {
    try {
      await _local.initialize(
        const InitializationSettings(android: AndroidInitializationSettings(_icon)),
        onDidReceiveNotificationResponse: (r) => _tapPayload(r.payload),
      );
      final a = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      // Saluran lama (suara bawaan yang pelan) dihapus; saluran baru memakai suara kustom yang keras.
      for (final old in const ['zarr_messages', 'zarr_calls', 'zarr_broadcast']) {
        try {
          await a?.deleteNotificationChannel(old);
        } catch (_) {}
      }
      // Saluran dibuat sejak awal: push FCM memakainya (muncul di atas aplikasi lain, dengan suara & getar).
      await a?.createNotificationChannel(const AndroidNotificationChannel(
        kChMessages, 'Pesan',
        description: 'Pesan chat, grup, dan panggilan tak terjawab',
        importance: Importance.max, playSound: true, enableVibration: true, enableLights: true,
        sound: RawResourceAndroidNotificationSound('notif_message'),
        audioAttributesUsage: AudioAttributesUsage.notification,
      ));
      await a?.createNotificationChannel(AndroidNotificationChannel(
        kChCalls, 'Panggilan',
        description: 'Panggilan suara & video masuk',
        importance: Importance.max, playSound: true, enableVibration: true, enableLights: true,
        vibrationPattern: Int64List.fromList(<int>[0, 800, 500, 800, 500, 800]),
        sound: const RawResourceAndroidNotificationSound('notif_call'),
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      ));
      await a?.createNotificationChannel(const AndroidNotificationChannel(
        kChBroadcast, 'Pengumuman',
        description: 'Pengumuman resmi dari ZARR CHAT',
        importance: Importance.max, playSound: true, enableVibration: true, enableLights: true,
        sound: RawResourceAndroidNotificationSound('notif_broadcast'),
        audioAttributesUsage: AudioAttributesUsage.notification,
      ));
      await _syncChannels();
      _localReady = true;
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) _tapPayload(launch?.notificationResponse?.payload);
    } catch (e) {
      debugPrint('push: notifikasi lokal gagal: $e');
    }
  }

  /// Membuat saluran untuk suara yang sedang dipilih (pesan & panggilan) dan menghapus saluran suara lain yang tidak dipakai lagi,
  /// supaya daftar saluran di pengaturan Android tidak menumpuk. Aman dipanggil berulang.
  Future<void> _syncChannels() async {
    try {
      final a = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (a == null) return;
      final msgId = kMsgChannelId;
      final callId = kCallChannelId;
      final msgCustom = audioPrefs.soundId == 'custom';
      final msgLabel = msgCustom ? 'MP3 sendiri' : audioPrefs.soundName;
      await a.createNotificationChannel(AndroidNotificationChannel(
        msgId, 'Pesan ($msgLabel)',
        description: 'Pesan chat, grup, dan panggilan tak terjawab',
        importance: Importance.max, playSound: true, enableVibration: true, enableLights: true,
        sound: _msgSound(),
        audioAttributesUsage: AudioAttributesUsage.notification,
      ));
      if (callId != kChCalls) {
        await a.createNotificationChannel(AndroidNotificationChannel(
          callId, 'Panggilan (MP3 sendiri)',
          description: 'Panggilan suara & video masuk',
          importance: Importance.max, playSound: true, enableVibration: true, enableLights: true,
          vibrationPattern: Int64List.fromList(<int>[0, 800, 500, 800, 500, 800]),
          sound: _callSound(),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        ));
      }
      // Bersih-bersih hanya bila pilihan berubah sejak terakhir kali (menghindari puluhan panggilan sistem tiap aplikasi dibuka).
      final sp = await SharedPreferences.getInstance();
      final key = '$msgId|$callId';
      if (sp.getString('zc_ch_key') == key) return;
      final stale = <String>[
        for (final id in const ['ping', 'pop', 'lonceng', 'dingdong']) 'zarr_msg_$id',
        for (var v = 1; v <= audioPrefs.customNotifVer; v++) 'zarr_msg_custom_$v',
        for (var v = 1; v <= audioPrefs.customCallVer; v++) 'zarr_call_custom_$v',
      ];
      for (final id in stale) {
        if (id == msgId || id == callId) continue;
        try {
          await a.deleteNotificationChannel(id);
        } catch (_) {}
      }
      await sp.setString('zc_ch_key', key);
    } catch (e) {
      debugPrint('push: saluran suara gagal: $e');
    }
  }

  /// Dipanggil setelah pengguna mengganti suara notifikasi / nada panggilan: buat saluran barunya, lalu beri tahu server.
  Future<void> onSoundChanged() async {
    await _syncChannels();
    final t = _token;
    if (!_firebaseReady || t == null || app.me == null) return;
    try {
      await app.api.post('/push/register', _tokenBody(t));
      _registered = true;
    } catch (_) {
      // dicoba lagi saat aplikasi dibuka berikutnya (registerDevice mengirim saluran yang sama)
    }
  }

  Map<String, dynamic> _tokenBody(String t) => {'token': t, 'msgChannel': kMsgChannelId, 'callChannel': kCallChannelId};

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp(); // memakai google-services.json; gagal bila file itu tidak ada
      FirebaseMessaging.onBackgroundMessage(zarrFirebaseBackgroundHandler);
      _firebaseReady = true;
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessage.listen(_onForeground);
        FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(m.data));
        final first = await FirebaseMessaging.instance.getInitialMessage();
        if (first != null) _handleTap(first.data);
      }
    } catch (e) {
      _firebaseReady = false;
      debugPrint('push: Firebase tidak aktif ($e). Notifikasi push dinonaktifkan.');
    }
  }

  // ---------------------------------------------------------------- pendaftaran perangkat ke server
  /// Dipanggil setelah masuk/aplikasi dibuka dengan akun yang sudah login.
  Future<void> registerDevice() async {
    // Bila akun sebelumnya baru saja keluar, tunggu token lamanya selesai dihapus: kalau tidak, penghapusan itu bisa
    // menimpa token baru dan akun yang baru login tidak menerima notifikasi.
    final pending = _logoutTask;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
      if (identical(_logoutTask, pending)) _logoutTask = null;
    }
    if (app.me == null) return;
    // Izin notifikasi (Android 13+) diminta walau Firebase belum aktif, supaya notifikasi lokal tetap bisa tampil.
    try {
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
    if (!_firebaseReady) return;
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      final t = await FirebaseMessaging.instance.getToken();
      if (t == null || t.isEmpty) {
        _retryRegister();
        return;
      }
      _token = t;
      await app.api.post('/push/register', _tokenBody(t));
      _registered = true;
      _retryTimer?.cancel();
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((n) async {
        _token = n;
        _registered = false;
        if (app.me == null) return;
        try {
          await app.api.post('/push/register', _tokenBody(n));
          _registered = true;
        } catch (_) {
          // dicoba lagi saat aplikasi dibuka berikutnya
        }
      });
    } catch (e) {
      _registered = false;
      debugPrint('push: daftar perangkat gagal: $e');
      _retryRegister();
    }
  }

  /// Gagal daftar (jaringan putus, server sedang mulai ulang): coba lagi sendiri, jangan menunggu aplikasi dibuka ulang.
  void _retryRegister() {
    _retryTimer?.cancel();
    if (app.me == null) return;
    _retryTimer = Timer(const Duration(seconds: 20), () {
      if (app.me != null && !active) unawaited(registerDevice());
    });
  }

  // ---------------------------------------------------------------- agar notifikasi tidak ditahan sistem (hemat baterai)
  static const MethodChannel _sys = MethodChannel('com.zarr.chat/system');

  /// true bila ZARR CHAT sudah dikecualikan dari penghematan baterai (notifikasi tidak ditunda saat HP diam / main game).
  Future<bool> batteryUnrestricted() async {
    try {
      return (await _sys.invokeMethod<bool>('batteryUnrestricted')) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Menampilkan dialog sistem "izinkan berjalan di latar belakang". Dipanggil sekali otomatis setelah login, atau dari Pengaturan.
  Future<void> requestBatteryExemption({bool force = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!force && (sp.getBool('zc_battery_asked') ?? false)) return;
      await sp.setBool('zc_battery_asked', true);
      if (await batteryUnrestricted()) return;
      await _sys.invokeMethod<bool>('requestBatteryExemption');
    } catch (_) {}
  }

  /// true bila notifikasi ZARR CHAT diizinkan di pengaturan Android.
  Future<bool> notificationsAllowed() async {
    try {
      return (await _sys.invokeMethod<bool>('notificationsEnabled')) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Dipanggil SEBELUM keluar akun (masih punya sesi): server berhenti mengirim push ke perangkat ini.
  Future<void> unregisterDevice() async {
    final t = _token;
    _registered = false;
    if (t == null) return;
    try {
      await app.api.post('/push/unregister', {'token': t}).timeout(const Duration(seconds: 4));
    } catch (_) {
      // token lama dihapus server sendiri begitu FCM menolaknya
    }
  }

  /// Dipanggil setiap kali keluar akun di perangkat ini.
  Future<void> onLogout() {
    _registered = false;
    _retryTimer?.cancel();
    _pendingTap = null;
    return _logoutTask = _logoutCleanup();
  }

  Future<void> _logoutCleanup() async {
    try {
      await _local.cancelAll();
    } catch (_) {}
    if (_firebaseReady) {
      try {
        // token lama mati; login berikutnya mendapat token baru. Dibatasi waktu supaya tidak menahan login berikutnya.
        await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    _token = null;
    _registered = false;
  }

  // ---------------------------------------------------------------- push saat aplikasi terbuka
  void _onForeground(RemoteMessage m) {
    // Pesan/telepon sudah ditangani socket (banner + nada). Hanya broadcast yang perlu notifikasi sistem.
    final d = m.data;
    if (d['type'] == 'broadcast') {
      final n = m.notification;
      show(
        tag: 'broadcast:${d['broadcastId'] ?? ''}', channel: kChBroadcast,
        title: n?.title ?? '📢 PENGUMUMAN RESMI', body: n?.body ?? '', data: d,
      );
    }
  }

  // ---------------------------------------------------------------- notifikasi lokal
  /// Menampilkan notifikasi sistem. [tag] sama = menggantikan notifikasi sebelumnya (tidak menumpuk).
  Future<void> show({required String tag, required String channel, required String title, required String body, Map<String, dynamic>? data}) async {
    if (!_localReady) return;
    // Pengaman anti-spam: tag yang sama tidak dibunyikan ulang lebih sering dari tiap 2 detik.
    final now = DateTime.now();
    final last = _lastShown[tag];
    if (last != null && now.difference(last).inMilliseconds < 2000) return;
    _lastShown[tag] = now;
    if (_lastShown.length > 200) _lastShown.removeWhere((_, v) => now.difference(v).inMinutes > 5);
    try {
      final call = channel == kChCalls;
      // Nama logis (kChMessages / kChCalls) -> saluran sesuai suara pilihan pengguna.
      final resolved = channel == kChMessages ? kMsgChannelId : (call ? kCallChannelId : channel);
      final AndroidNotificationSound snd = channel == kChMessages ? _msgSound() : (call ? _callSound() : const RawResourceAndroidNotificationSound('notif_broadcast'));
      await _local.show(
        0, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            resolved, call ? 'Panggilan' : (channel == kChBroadcast ? 'Pengumuman' : 'Pesan'),
            sound: snd, // Android 8+: suara ditentukan saluran (sudah dibuat di atas); Android 7: dipakai langsung dari sini
            importance: call ? Importance.max : Importance.high,
            priority: call ? Priority.max : Priority.high,
            tag: tag,
            icon: _icon,
            category: call ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
            visibility: call ? NotificationVisibility.public : NotificationVisibility.private,
            fullScreenIntent: call, // panggilan masuk muncul penuh di atas layar kunci / aplikasi lain
            additionalFlags: call ? Int32List.fromList(<int>[4]) : null, // FLAG_INSISTENT: dering terus berulang sampai dijawab
            ongoing: call,
            enableLights: true,
            styleInformation: BigTextStyleInformation(body),
            autoCancel: true,
            timeoutAfter: call ? 45000 : null,
          ),
        ),
        payload: jsonEncode(data ?? <String, dynamic>{}),
      );
    } catch (e) {
      debugPrint('push: tampil notifikasi gagal: $e');
    }
  }

  Future<void> cancelTag(String tag) async {
    try {
      await _local.cancel(0, tag: tag);
    } catch (_) {}
  }

  Future<void> cancelChat(int id) => cancelTag('chat:$id');
  Future<void> cancelGroup(int id) => cancelTag('group:$id');
  Future<void> cancelCall(dynamic callId) => cancelTag('call:$callId');

  // ---------------------------------------------------------------- ketuk notifikasi
  void _tapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      _handleTap(asMap(jsonDecode(payload)));
    } catch (_) {}
  }

  void _handleTap(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    if (app.phase == Phase.home && app.navKey.currentContext != null) {
      _navigate(data);
    } else {
      _pendingTap = data; // aplikasi baru dibuka: dijalankan setelah beranda siap
    }
  }

  /// Dipanggil saat beranda sudah siap (setelah login/boot).
  void flushPending() {
    final d = _pendingTap;
    if (d == null) return;
    _pendingTap = null;
    Future<void>.delayed(const Duration(milliseconds: 400), () => _navigate(d));
  }

  /// Notifikasi percobaan dari Pengaturan: memastikan suara & tampilan notifikasi berfungsi di HP ini.
  Future<void> test() async {
    await show(tag: 'test:${DateTime.now().millisecondsSinceEpoch}', channel: kChMessages, title: 'ZARR CHAT', body: 'Tes notifikasi berhasil. Suara ini harus terdengar keras.');
  }

  /// Tes nada panggilan dari Pengaturan: notifikasi singkat (8 detik) pada saluran panggilan pilihan, tanpa dering berulang.
  Future<void> testCall() async {
    if (!_localReady) return;
    try {
      await _local.show(
        0, 'ZARR CHAT', 'Tes nada panggilan',
        NotificationDetails(
          android: AndroidNotificationDetails(
            kCallChannelId, 'Panggilan',
            importance: Importance.max, priority: Priority.max,
            tag: 'test_call', icon: _icon, enableLights: true,
            category: AndroidNotificationCategory.call,
            sound: _callSound(),
            audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
            timeoutAfter: 8000, autoCancel: true,
          ),
        ),
        payload: jsonEncode(<String, dynamic>{}),
      );
    } catch (e) {
      debugPrint('push: tes nada panggilan gagal: $e');
    }
  }

  Future<void> _navigate(Map<String, dynamic> d) async {
    try {
      final ctx = app.navKey.currentContext;
      if (ctx == null) return;
      final type = (d['type'] ?? '').toString();
      if (type == 'message' || type == 'missed_call') {
        final sid = int.tryParse((d['senderId'] ?? d['callerId'] ?? '').toString());
        if (sid != null) await openChatWithUser(ctx, sid);
      } else if (type == 'group_message') {
        final gid = int.tryParse((d['groupId'] ?? '').toString());
        if (gid != null) openGroup(gid);
      }
      // 'call' dan 'broadcast': cukup membuka aplikasi (panggilan masuk dimunculkan oleh socket).
    } catch (_) {
      // gagal membuka layar tujuan: aplikasi tetap terbuka di beranda
    }
  }
}

final PushService push = PushService();
