// ZARR CHAT - status aplikasi global: sesi, daftar chat, socket real-time.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'api.dart';
import 'audio_storage.dart';
import 'config.dart';
import 'models.dart';
import 'push.dart';
import 'util.dart';

enum Phase { loading, welcome, profile, home, error, suspended }

class SocketEvent {
  final String name;
  final Map<String, dynamic> data;
  SocketEvent(this.name, this.data);
}

const List<String> _socketEvents = [
  'message:new',
  'message:updated',
  'ai:stream',
  'message:removed',
  'message:status',
  'typing',
  'chat:updated',
  'chat:cleared',
  'chat:read',
  'call:incoming',
  'call:ringing',
  'call:accepted',
  'call:signal',
  'call:ended',
  'status:viewed',
  'status:new',
  'status:deleted',
  'channel:post',
  'channel:post_updated',
  'channel:post_deleted',
  'channel:updated',
  'channel:deleted',
  'presence',
  'notification:new',
  'group:message',
  'group:message_updated',
  'group:message_removed',
  'group:receipt',
  'group:typing',
  'group:updated',
  'group:removed',
  'group:read',
];

class AppState extends ChangeNotifier {
  final Api api = Api();
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  SharedPreferences? _prefs;
  Phase phase = Phase.loading;
  String errorMessage = '';
  User? me;
  AppConfig? cfg;
  DateTime? cfgAt; // kapan konfigurasi server terakhir berhasil dimuat
  List<ChatItem> chats = [];
  List<ChatItem> archived = [];
  List<GroupItem> groups = [];
  List<GroupItem> archivedGroups = [];
  int notifCount = 0;
  bool connected = false;
  int activeChatId = 0; // percakapan yang sedang dibuka (untuk tanda dibaca & banner)
  int activeGroupId = 0; // grup yang sedang dibuka
  bool inForeground = true; // aplikasi sedang dibuka di layar (untuk menentukan banner dalam aplikasi vs notifikasi HP)

  final Map<int, bool> online = {};
  final Map<int, DateTime?> lastSeen = {};
  final Map<int, bool> typing = {};
  final Map<int, Timer> _typingTimers = {};
  final Map<int, Map<int, String>> groupTyping = {}; // grupId -> {userId: nama} yang sedang mengetik
  final Map<String, Timer> _groupTypingTimers = {};

  sio.Socket? _socket;
  final StreamController<SocketEvent> _events = StreamController<SocketEvent>.broadcast();
  Stream<SocketEvent> get events => _events.stream;
  Timer? _chatsTimer;
  bool _firstConnect = true;
  Timer? _watchdog; // pengaman: memeriksa berkala bahwa socket hidup (tidak macet / "mati diam-diam")
  Timer? _bannerTimer; // banner "Menyambungkan ulang" baru muncul bila putus cukup lama
  DateTime _attemptAt = DateTime.now(); // kapan socket terakhir dibuat ulang
  int _tick = 0;
  bool _probing = false;
  bool _loggingOut = false; // mencegah logoutLocal berjalan ganda (mis. beberapa permintaan 401 bersamaan)
  bool _verifying = false; // sedang memeriksa apakah sesi masih berlaku setelah socket menolak
  Timer? _reopenTimer; // jadwal membuat ulang socket setelah galat tingkat namespace (pustaka tidak menyambung ulang sendiri)
  /// Banner merah "Menyambungkan ulang…". Hanya muncul bila benar-benar terputus lebih dari beberapa detik,
  /// bukan pada setiap kedipan sinyal (sambung ulang singkat terjadi diam-diam di belakang layar).
  bool offlineBanner = false;

  ThemeMode get themeMode {
    switch (me?.theme) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.light; // bawaan web: terang
    }
  }

  int get totalUnread =>
      chats.fold<int>(0, (n, c) => n + (c.muted ? 0 : c.unread)) + groups.fold<int>(0, (n, g) => n + (g.muted ? 0 : g.unread));

  // ---------------------------------------------------------------- util UI
  void toast(String msg, {bool error = false}) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFD4163A) : const Color(0xFF111111),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: error ? 4 : 2),
    ));
  }

  void refresh() => notifyListeners();

  // ---------------------------------------------------------------- boot & sesi
  Future<void> boot() async {
    phase = Phase.loading;
    notifyListeners();
    api.onUnauthorized = _onUnauthorized;
    _prefs ??= await SharedPreferences.getInstance();
    api.token = _prefs!.getString('zc_token');
    if (api.token == null || api.token!.isEmpty) {
      phase = Phase.welcome;
      notifyListeners();
      return;
    }
    try {
      final r = asMap(await api.get('/auth/me'));
      me = User.fromJson(r['user']);
      notifCount = _unreadOf(r['user']);
      if (asMap(r['user'])['needsProfile'] == true) {
        phase = Phase.profile;
        notifyListeners();
      } else {
        await startApp();
      }
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _clearSession();
        phase = Phase.welcome;
      } else if (e.status == 403 && e.code == 'suspended') {
        errorMessage = e.message;
        phase = Phase.suspended;
      } else {
        errorMessage = e.message;
        phase = Phase.error;
      }
      notifyListeners();
    }
  }

  int _unreadOf(dynamic user) {
    final v = asMap(user)['unreadNotifications'];
    return v is int ? v : 0;
  }

  Future<void> _saveToken() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (api.token != null) await _prefs!.setString('zc_token', api.token!);
  }

  Future<void> _clearSession() async {
    api.token = null;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove('zc_token');
  }

  /// Dipanggil setelah /auth/login atau /auth/register berhasil.
  Future<void> onAuthenticated(dynamic response) async {
    final r = asMap(response);
    me = User.fromJson(r['user']);
    notifCount = _unreadOf(r['user']);
    await _saveToken();
    _disposeSocket(); // pastikan tidak ada sambungan akun sebelumnya yang tersisa
    if (me!.username.isEmpty) {
      phase = Phase.profile;
      notifyListeners();
    } else {
      await startApp();
    }
  }

  /// Memuat ulang konfigurasi server (termasuk kredensial TURN yang berumur pendek). Gagal = pakai yang lama.
  /// [force] = false: lewati bila konfigurasi masih baru (kurang dari 3 menit), agar panggilan tidak menunggu jaringan.
  Future<void> refreshConfig({bool force = true}) async {
    final at = cfgAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(minutes: 3)) return;
    try {
      final r = await api.get('/config').timeout(const Duration(seconds: 5));
      cfg = AppConfig.fromJson(r);
      cfgAt = DateTime.now();
    } catch (_) {
      // pakai konfigurasi yang lama
    }
  }

  Future<void> startApp() async {
    try {
      cfg = AppConfig.fromJson(await api.get('/config'));
      cfgAt = DateTime.now();
      final n = asMap(await api.get('/notifications'));
      notifCount = asList(n['items']).where((x) => asMap(x)['read'] != true).length;
    } on ApiException catch (e) {
      errorMessage = e.message;
      phase = Phase.error;
      notifyListeners();
      return;
    }
    phase = Phase.home;
    notifyListeners();
    connectSocket();
    unawaited(push.registerDevice());
    unawaited(Future<void>.delayed(const Duration(seconds: 6), push.requestBatteryExemption));
    push.flushPending();
    await loadChatsNow();
  }

  void _onUnauthorized() {
    if (me == null || _loggingOut) return;
    logoutLocal(message: 'Sesi berakhir. Silakan login kembali.');
  }

  /// Socket ditolak server dengan "unauthenticated". Itu BELUM tentu berarti sesi berakhir (mis. server baru restart / data belum siap),
  /// jadi sesi diperiksa lewat HTTP dulu: 401 -> keluar; sesi masih sah -> socket dibuat ulang, bukan mengeluarkan pengguna.
  Future<void> _verifySession(sio.Socket s) async {
    final user = me;
    if (user == null || _verifying) return;
    _verifying = true;
    try {
      await api.get('/auth/me'); // 401 'unauthenticated' dikerjakan oleh onUnauthorized
      if (identical(_socket, s) && me == user) _scheduleReopen(s, const Duration(seconds: 2));
    } on ApiException catch (e) {
      if (e.status == 403 && e.code == 'suspended' && me == user) {
        errorMessage = e.message;
        _disposeSocket();
        phase = Phase.suspended;
        notifyListeners();
      } else if (identical(_socket, s) && me == user && e.status != 401) {
        _scheduleReopen(s, const Duration(seconds: 4)); // server/jaringan bermasalah: coba lagi nanti
      }
    } finally {
      _verifying = false;
    }
  }

  /// Membuat ulang socket [s] bila sesudah [delay] masih belum tersambung. Pustaka socket.io tidak menyambung ulang sendiri
  /// setelah galat tingkat namespace (mis. server belum siap), jadi tanpa ini koneksi bisa macet selamanya.
  void _scheduleReopen(sio.Socket s, Duration delay) {
    _reopenTimer?.cancel();
    _reopenTimer = Timer(delay, () {
      _reopenTimer = null;
      if (me != null && identical(_socket, s) && !s.connected) _openSocket();
    });
  }

  /// Memberi tahu bagian lain (mis. panggilan yang sedang berjalan) bahwa akun akan keluar. Dikirim SEBELUM socket ditutup.
  void _announceLogout() => _events.add(SocketEvent('logout', <String, dynamic>{}));

  Future<void> logout() async {
    _announceLogout();
    final token = push.currentToken;
    await push.unregisterDevice(); // berhenti menerima notifikasi akun ini di HP ini
    try {
      await api.post('/auth/logout', {if (token != null) 'pushToken': token}).timeout(const Duration(seconds: 8));
    } catch (_) {
      // tetap keluar di perangkat ini
    }
    await logoutLocal();
  }

  Future<void> logoutAll() async {
    _announceLogout();
    try {
      await api.post('/auth/logout-all').timeout(const Duration(seconds: 8));
    } catch (_) {
      // tetap keluar di perangkat ini
    }
    await logoutLocal();
  }

  /// Membersihkan SEMUA keadaan akun sebelumnya (socket, timer, token, cache, data di memori) supaya akun berikutnya
  /// (login atau daftar baru) mulai dari keadaan bersih. Sisa keadaan lama adalah penyebab utama "Menyambungkan ulang…" yang tak kunjung hilang.
  Future<void> logoutLocal({String? message}) async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      _announceLogout();
      _disposeSocket();
      _bannerTimer?.cancel();
      _bannerTimer = null;
      _reopenTimer?.cancel();
      _reopenTimer = null;
      _chatsTimer?.cancel();
      _chatsTimer = null;
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      for (final t in _groupTypingTimers.values) {
        t.cancel();
      }
      _groupTypingTimers.clear();
      offlineBanner = false;
      _firstConnect = true;
      _tick = 0;
      _probing = false;
      _verifying = false;
      await _clearSession();
      me = null;
      cfg = null;
      cfgAt = null;
      chats = [];
      archived = [];
      groups = [];
      archivedGroups = [];
      notifCount = 0;
      groupTyping.clear();
      activeGroupId = 0;
      online.clear();
      lastSeen.clear();
      typing.clear();
      activeChatId = 0;
      errorMessage = '';
      phase = Phase.welcome;
      notifyListeners();
      final nav = navKey.currentState;
      if (nav != null) nav.popUntil((r) => r.isFirst);
      if (message != null) toast(message, error: true);
      // Notifikasi & token FCM akun lama dibuang. push.registerDevice() menunggu pekerjaan ini selesai lebih dulu,
      // jadi login cepat sesudahnya tidak bertabrakan dengan penghapusan token.
      unawaited(push.onLogout());
      // Gambar/berkas cache akun lama dibuang (tidak boleh terlihat oleh akun berikutnya di perangkat yang sama).
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      unawaited(DefaultCacheManager().emptyCache().catchError((Object _) {}));
    } finally {
      _loggingOut = false;
    }
  }

  // ---------------------------------------------------------------- daftar chat
  void loadChats() {
    _chatsTimer?.cancel();
    _chatsTimer = Timer(const Duration(milliseconds: 250), () {
      loadChatsNow();
    });
  }

  Future<Map<String, dynamic>?> _tryGet(String path, {bool quiet = false}) async {
    try {
      return asMap(await api.get(path));
    } on ApiException catch (e) {
      if (!quiet && !e.network) toast(e.message, error: true);
      return null;
    }
  }

  Future<void> loadChatsNow() async {
    final r = await Future.wait([
      _tryGet('/chats'),
      _tryGet('/chats?archived=1'),
      _tryGet('/groups', quiet: true),
      _tryGet('/groups?archived=1', quiet: true),
    ]);
    final c0 = r[0];
    final c1 = r[1];
    final g0 = r[2];
    final g1 = r[3];
    if (c0 != null && c1 != null) {
      chats = asList(c0['chats']).map((c) => ChatItem.fromJson(c)).toList();
      archived = asList(c1['chats']).map((c) => ChatItem.fromJson(c)).toList();
    }
    if (g0 != null && g1 != null) {
      groups = asList(g0['groups']).map((g) => GroupItem.fromJson(g)).toList();
      archivedGroups = asList(g1['groups']).map((g) => GroupItem.fromJson(g)).toList();
    }
    notifyListeners();
  }

  GroupItem? groupById(int id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    for (final g in archivedGroups) {
      if (g.id == id) return g;
    }
    return null;
  }

  ChatItem? chatById(int id) {
    for (final c in chats) {
      if (c.id == id) return c;
    }
    for (final c in archived) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Memuat ulang status akun (peran/centang) secara diam-diam; gagal = abaikan.
  Future<void> refreshMe() async {
    final cur = me;
    if (cur == null) return;
    try {
      final u = User.fromJson(asMap(await api.get('/auth/me'))['user']);
      if (me != cur) return; // sudah ganti akun / keluar
      final changed = cur.role != u.role || cur.isVerified != u.isVerified;
      cur.role = u.role;
      cur.isVerified = u.isVerified;
      cur.isDeveloper = u.isDeveloper;
      if (changed) notifyListeners();
    } catch (_) {
      // abaikan; coba lagi saat aplikasi dibuka kembali
    }
  }

  Future<void> saveMe(Map<String, dynamic> patch) async {
    final r = asMap(await api.patch('/me', patch));
    final u = User.fromJson(r['user']);
    final cur = me;
    if (cur != null) {
      cur.username = u.username;
      cur.about = u.about;
      cur.avatarUrl = u.avatarUrl;
      cur.coverUrl = u.coverUrl;
      cur.theme = u.theme;
      cur.notifyPreview = u.notifyPreview;
      cur.privacyLastSeen = u.privacyLastSeen;
      cur.privacyStatus = u.privacyStatus;
      cur.readReceipts = u.readReceipts;
      cur.autoReplyEnabled = u.autoReplyEnabled;
      cur.autoReplyMessage = u.autoReplyMessage;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- socket
  /// Membuka sambungan real-time baru (dipanggil saat sesi dimulai).
  void connectSocket() {
    _firstConnect = true;
    _openSocket();
  }

  /// Status koneksi dipakai banner: berubah ke "putus" hanya menjadwalkan banner (muncul bila tetap putus > 8 detik).
  void _setConnected(bool v) {
    connected = v;
    if (v) {
      _bannerTimer?.cancel();
      _bannerTimer = null;
      if (offlineBanner) {
        offlineBanner = false;
        notifyListeners();
      }
      return;
    }
    _armBanner();
  }

  void _armBanner() {
    if (offlineBanner || (_bannerTimer?.isActive ?? false)) return;
    _bannerTimer = Timer(const Duration(seconds: 8), () {
      _bannerTimer = null;
      if (!connected && inForeground && me != null && !offlineBanner) {
        offlineBanner = true;
        notifyListeners();
      }
    });
  }

  /// Membuat ulang socket dari nol. Aman dipanggil berulang (socket lama dibuang dulu).
  /// Sambung ulang otomatis (jeda 1-5 detik, tanpa batas) dikerjakan oleh pustaka socket.io; di sini hanya pengaman tambahan.
  void _openSocket() {
    _disposeSocket();
    final token = api.token;
    if (token == null || me == null) return;
    _attemptAt = DateTime.now();
    // forceNew WAJIB: tanpa ini pustaka memakai ulang Manager/Socket lama dari cache (berdasarkan alamat server) beserta header Cookie
    // akun sebelumnya. Akibatnya setelah keluar lalu masuk/daftar akun lain, sambungan memakai sesi lama yang sudah dihapus
    // dan terus gagal ("Menyambungkan ulang…").
    final opts = <String, dynamic>{
      ...sio.OptionBuilder().setTransports(['websocket']).setExtraHeaders({'Cookie': 'zc_sid=$token'}).disableAutoConnect().build(),
      'forceNew': true,
    };
    final s = sio.io(kBaseUrl, opts);
    _socket = s;
    s.onConnect((_) {
      if (!identical(_socket, s)) return;
      _setConnected(true);
      if (!_firstConnect) {
        loadChatsNow();
        _events.add(SocketEvent('reconnected', <String, dynamic>{}));
      }
      _firstConnect = false;
      emitQuiet('app:state', {'foreground': inForeground}); // beri tahu server status aplikasi di koneksi baru ini
    });
    s.onDisconnect((reason) {
      if (!identical(_socket, s)) return;
      _setConnected(false);
      // Bila server yang memutus, pustaka tidak menyambung ulang sendiri: sambungkan lagi dari sini.
      if (reason.toString().contains('io server disconnect')) {
        Timer(const Duration(seconds: 1), () {
          if (identical(_socket, s) && !s.connected) s.connect();
        });
      }
    });
    s.onConnectError((err) {
      if (!identical(_socket, s)) return;
      _setConnected(false);
      if (err.toString().contains('unauthenticated')) {
        unawaited(_verifySession(s));
      } else {
        // Galat jaringan: pustaka mencoba lagi sendiri. Galat dari server (mis. server_not_ready): socket sudah ditutup
        // pustaka dan tidak akan mencoba lagi, jadi dibuat ulang dari sini bila tetap belum tersambung.
        _scheduleReopen(s, const Duration(seconds: 5));
      }
    });
    for (final ev in _socketEvents) {
      s.on(ev, (dynamic data) => _onSocketEvent(ev, asMap(data is List && data.isNotEmpty ? data.first : data)));
    }
    // Pengaman: tiap 5 detik. Bila terhubung -> sesekali cek benar-benar hidup. Bila putus lama -> buat ulang socket.
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (me == null) return;
      final cur = _socket;
      if (cur == null) {
        _openSocket();
        return;
      }
      if (cur.connected) {
        _tick++;
        if (_tick % 4 == 0 && inForeground) unawaited(_probe());
        return;
      }
      connected = false;
      _armBanner();
      if (DateTime.now().difference(_attemptAt) > const Duration(seconds: 20)) _openSocket();
    });
    s.connect();
  }

  /// Memastikan sambungan benar-benar hidup: server harus membalas dalam beberapa detik.
  /// Sambungan yang "mati diam-diam" (HP di latar belakang / pindah jaringan) dibuat ulang saat itu juga.
  Future<void> _probe({int timeoutSec = 6}) async {
    final s = _socket;
    if (s == null || !s.connected || _probing) return;
    _probing = true;
    try {
      final c = Completer<bool>();
      s.emitWithAck('app:state', {'foreground': inForeground}, ack: (dynamic _) {
        if (!c.isCompleted) c.complete(true);
      });
      final ok = await c.future.timeout(Duration(seconds: timeoutSec), onTimeout: () => false);
      if (!ok && identical(_socket, s) && me != null) {
        _setConnected(false);
        _openSocket();
      }
    } catch (_) {
      // abaikan; pengecekan berikutnya akan mencoba lagi
    } finally {
      _probing = false;
    }
  }

  void _disposeSocket() {
    _watchdog?.cancel();
    _watchdog = null;
    _reopenTimer?.cancel();
    _reopenTimer = null;
    final s = _socket;
    _socket = null;
    connected = false;
    if (s != null) {
      try {
        s.clearListeners();
        s.dispose();
      } catch (_) {
        // abaikan
      }
    }
  }

  /// Mengirim kejadian lokal (bukan dari server) ke semua pendengar, mis. 'tab:status'.
  void pokeEvent(String name) => _events.add(SocketEvent(name, <String, dynamic>{}));

  /// Menunggu sampai socket tersambung (maks. [seconds] detik). True bila tersambung.
  Future<bool> ensureConnected({int seconds = 6}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!(_socket?.connected ?? false)) {
      if (me == null || DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return true;
  }

  /// Dilaporkan ke server: bila aplikasi tidak sedang dibuka, server mengirim notifikasi push ke HP.
  void setForeground(bool v) {
    if (inForeground == v) return;
    inForeground = v;
    if (me != null && (_socket?.connected ?? false)) emitQuiet('app:state', {'foreground': v});
  }

  /// Dipanggil saat aplikasi kembali ke latar depan.
  void onResume() {
    if (me == null) return;
    if (!push.active) unawaited(push.registerDevice()); // token baru / gagal daftar sebelumnya
    refreshMe();
    // Kembali dari latar belakang: sambungan lama sering sudah mati. Putus -> buat ulang sekarang; terlihat hidup -> uji dulu.
    final s = _socket;
    if (s == null || !s.connected) {
      _openSocket();
    } else {
      unawaited(_probe(timeoutSec: 4));
    }
    loadChats();
    _events.add(SocketEvent('resumed', <String, dynamic>{}));
  }

  /// Notifikasi HP dari socket. Hanya dipakai bila push FCM TIDAK aktif di HP ini (bila aktif, server sudah mengirim push: jangan dobel).
  /// Broadcast tampil juga saat aplikasi dibuka (sama seperti push FCM); notifikasi lain hanya saat aplikasi di latar belakang.
  void _systemNoticeFromSocket(Map<String, dynamic> d) {
    try {
      if (push.active) return;
      final type = (d['type'] ?? '').toString();
      final title = (d['title'] ?? '').toString();
      final body = (d['body'] ?? '').toString();
      if (title.isEmpty && body.isEmpty) return;
      if (type == 'broadcast') {
        push.show(
          tag: 'broadcast:${d['broadcastId'] ?? title}', channel: kChBroadcast,
          title: title.isEmpty ? '📢 PENGUMUMAN RESMI' : title, body: body, data: {'type': 'broadcast', 'broadcastId': d['broadcastId']},
        );
      } else if (!inForeground) {
        push.show(
          tag: 'notice:$type', channel: kChMessages,
          title: title.isEmpty ? kAppName : title, body: body, data: {'type': 'notice', 'noticeType': type},
        );
      }
    } catch (_) {
      // gagal menampilkan notifikasi: abaikan, daftar notifikasi di aplikasi tetap bertambah
    }
  }

  void _onSocketEvent(String ev, Map<String, dynamic> d) {
    switch (ev) {
      case 'presence':
        final uid = d['userId'];
        if (uid is int) {
          online[uid] = d['online'] == true;
          lastSeen[uid] = parseDate(d['lastSeen']);
        }
        notifyListeners();
        break;
      case 'notification:new':
        notifCount += 1;
        notifyListeners();
        _systemNoticeFromSocket(d);
        break;
      case 'call:incoming':
        {
          // Di latar belakang tanpa push FCM: tampilkan notifikasi dering lewat socket.
          if (!inForeground && !push.active) {
            final callerName = (asMap(d['from'])['username'] ?? kAppName).toString();
            push.show(
              tag: 'call:${d['callId']}',
              channel: kChCalls,
              title: callerName,
              body: d['type'] == 'video' ? 'Panggilan video masuk' : 'Panggilan suara masuk',
              data: {'type': 'call', 'callId': d['callId']},
            );
          }
          break;
        }
      case 'call:ended':
        push.cancelCall(d['callId']);
        break;
      case 'typing':
        final cid = d['conversationId'];
        if (cid is int) {
          _typingTimers[cid]?.cancel();
          if (d['typing'] == true) {
            typing[cid] = true;
            _typingTimers[cid] = Timer(const Duration(seconds: 5), () {
              typing.remove(cid);
              notifyListeners();
            });
          } else {
            typing.remove(cid);
          }
          notifyListeners();
        }
        break;
      case 'message:new':
        _autoDownload(d);
        _maybeBanner(d);
        loadChats();
        break;
      case 'message:updated':
      case 'message:removed':
      case 'message:status':
      case 'chat:cleared':
      case 'chat:read':
        loadChats();
        break;
      case 'group:typing':
        _onGroupTyping(d);
        break;
      case 'group:message':
        _autoDownload(d);
        _maybeGroupBanner(d);
        loadChats();
        break;
      case 'group:message_updated':
      case 'group:message_removed':
      case 'group:updated':
      case 'group:removed':
      case 'group:read':
        loadChats();
        break;
      default:
        break;
    }
    _events.add(SocketEvent(ev, d));
  }

  void _onGroupTyping(Map<String, dynamic> d) {
    final gid = d['groupId'];
    final uid = d['userId'];
    if (gid is! int || uid is! int) return;
    final key = '$gid:$uid';
    _groupTypingTimers[key]?.cancel();
    final map = groupTyping.putIfAbsent(gid, () => <int, String>{});
    if (d['typing'] == true) {
      map[uid] = (d['username'] ?? '').toString();
      _groupTypingTimers[key] = Timer(const Duration(seconds: 5), () {
        groupTyping[gid]?.remove(uid);
        notifyListeners();
      });
    } else {
      map.remove(uid);
    }
    notifyListeners();
  }

  void _maybeGroupBanner(Map<String, dynamic> d) {
    final raw = d['message'];
    if (raw == null) return;
    final m = Message.fromJson(raw);
    if (m.isSystem || m.senderId == me?.id || m.conversationId == activeGroupId) return;
    final g = groupById(m.conversationId);
    if (g != null && g.muted) return;
    final text = (me?.notifyPreview ?? true) ? previewText(m) : 'Pesan baru';
    if (!inForeground) {
      // Di latar belakang: bila push FCM aktif, server sudah mengirim notifikasinya (jangan dobel).
      if (!push.active) {
        push.show(tag: 'group:${m.conversationId}', channel: kChMessages, title: g?.name ?? kAppName, body: '${m.senderName}: $text',
            data: {'type': 'group_message', 'groupId': m.conversationId});
      }
      return;
    }
    // Tanpa banner di dalam aplikasi: pemberitahuan pesan hanya lewat notifikasi di HP.
    audioPrefs.onIncomingMessage();
  }

  /// Unduh media pesan masuk lebih dulu bila pengguna memilihnya di Penyimpanan Media.
  void _autoDownload(Map<String, dynamic> d) {
    try {
      final raw = d['message'];
      if (raw == null) return;
      final m = Message.fromJson(raw);
      if (m.isSystem || m.media == null) return;
      unawaited(autoDownloadMedia(m));
    } catch (_) {
      // abaikan
    }
  }

  void _maybeBanner(Map<String, dynamic> d) {
    final raw = d['message'];
    if (raw == null) return;
    final m = Message.fromJson(raw);
    if (m.senderId == me?.id || m.conversationId == activeChatId) return;
    final c = chatById(m.conversationId);
    if (c != null && c.muted) return;
    final who = c?.peer.username ?? kAppName;
    final text = (me?.notifyPreview ?? true) ? previewText(m) : 'Pesan baru';
    if (!inForeground) {
      if (!push.active) {
        push.show(tag: 'chat:${m.conversationId}', channel: kChMessages, title: who, body: text,
            data: {'type': 'message', 'conversationId': m.conversationId, 'senderId': m.senderId});
      }
      return;
    }
    // Tanpa banner di dalam aplikasi: pemberitahuan pesan hanya lewat notifikasi di HP.
    audioPrefs.onIncomingMessage();
  }

  /// Kirim event socket dan tunggu jawaban (ack) dari server.
  /// Bila socket sedang menyambung ulang, tunggu sebentar (maks. 6 detik) dulu sebelum menyerah.
  Future<Map<String, dynamic>> emit(String event, Map<String, dynamic> data, {bool wait = true}) async {
    if (wait && !(_socket?.connected ?? false)) await ensureConnected();
    final s = _socket;
    if (s == null || !s.connected) {
      throw ApiException('Belum tersambung ke server. Tunggu sebentar lalu coba lagi.', network: true);
    }
    final c = Completer<Map<String, dynamic>>();
    s.emitWithAck(event, data, ack: (dynamic resp) {
      if (c.isCompleted) return;
      final m = asMap(resp is List && resp.isNotEmpty ? resp.first : resp);
      if (m['ok'] == true) {
        c.complete(m);
      } else {
        c.completeError(ApiException((m['message'] ?? 'Gagal.').toString()));
      }
    });
    return c.future.timeout(const Duration(seconds: 15), onTimeout: () {
      throw ApiException('Server tidak merespons. Periksa koneksi Anda.', network: true);
    });
  }

  /// Emit tanpa menunggu hasil (mis. status mengetik).
  void emitQuiet(String event, Map<String, dynamic> data) {
    emit(event, data, wait: false).catchError((Object _) => <String, dynamic>{});
  }

  bool get socketConnected => _socket?.connected ?? false;
}

final AppState app = AppState();
