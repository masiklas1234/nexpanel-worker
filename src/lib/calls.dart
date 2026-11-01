// ZARR CHAT - panggilan suara/video (WebRTC) dan riwayat panggilan.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api.dart';
import 'audio_storage.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

class ActiveCall {
  int? id;
  final User peer;
  final String type; // 'voice' | 'video'
  final String role; // 'caller' | 'callee'
  String state;
  bool accepted = false;
  bool connected = false;
  bool reconnecting = false;
  bool ringingEarly = false; // 'call:ringing' tiba sebelum ack undangan sempat diproses
  bool acceptedEarly = false; // 'call:accepted' tiba sebelum ack undangan sempat diproses
  bool muted = false;
  bool camOff = false;
  bool frontCamera = true;
  bool speaker;
  final Set<String?> boosted = <String?>{};
  int secs = 0;
  MediaStream? local;
  MediaStream? remote;
  RTCPeerConnection? pc;
  final RTCVideoRenderer localR = RTCVideoRenderer();
  final RTCVideoRenderer remoteR = RTCVideoRenderer();
  final List<RTCIceCandidate> pending = [];
  Timer? timer;
  Timer? connectTimer;
  Timer? dropTimer;
  Timer? restartTimer;
  bool negotiating = false; // penelepon sudah mulai membuat sambungan (mencegah dobel bila kabar "diangkat" datang dua kali)
  bool restarting = false; // sedang membuat offer ICE-restart
  int restartCount = 0; // berapa kali pencarian jalur dimulai ulang
  DateTime? lastFailAt; // dua laporan 'gagal' beruntun (koneksi & ICE) dihitung satu
  bool renderersReady = false;
  ActiveCall({required this.peer, required this.type, required this.role, required this.state, required this.speaker});
}

/// Dilempar bila panggilan sudah berakhir saat persiapan sambungan masih berjalan.
class _CallGone implements Exception {
  const _CallGone();
}

double _tanhC(double x) {
  final e = math.exp(2 * x.clamp(-20.0, 20.0));
  return (e - 1) / (e + 1);
}

/// Membuat nada WAV 16-bit mono di memori (tanpa file aset). Tiap segmen = (frekuensi Hz, detik); frekuensi 0 = hening.
Uint8List _buildWav(List<(double, double)> segments, {double volume = 0.55, double drive = 1.0}) {
  const rate = 16000;
  final samples = <int>[];
  for (final seg in segments) {
    final n = (seg.$2 * rate).round();
    for (var i = 0; i < n; i++) {
      var v = 0.0;
      if (seg.$1 > 0) {
        final t = i / rate;
        // Fade 8 ms di awal/akhir mencegah bunyi "klik"; dua nada berdekatan memberi bunyi dering telepon yang khas.
        final env = math.min(1.0, math.min(i, n - 1 - i) / (rate * 0.008));
        final w = (math.sin(2 * math.pi * seg.$1 * t) + math.sin(2 * math.pi * seg.$1 * 1.12 * t) + 0.5 * math.sin(2 * math.pi * seg.$1 * 2 * t)) / 2.5;
        // drive > 1: kompresi lembut (tanh) membuat dering jauh lebih keras tanpa pecah.
        final shaped = drive > 1 ? (_tanhC(w * drive) / _tanhC(drive)) : w;
        v = shaped * env * volume;
      }
      final iv = (v * 32767).round();
      samples.add(math.max(-32768, math.min(32767, iv)));
    }
  }
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

class CallManager extends ChangeNotifier {
  ActiveCall? call;
  bool _starting = false;
  bool _accepting = false;
  Route<void>? _route;
  Timer? _ring;
  ap.AudioPlayer? _tonePlayer;
  int _toneToken = 0;
  Uint8List? _ringWav;
  Uint8List? _backWav;
  StreamSubscription<SocketEvent>? _sub;
  Future<void> _sigQ = Future<void>.value(); // sinyal WebRTC diproses satu per satu agar tidak saling tabrakan

  void attach() {
    _sub ??= app.events.listen((e) {
      switch (e.name) {
        case 'call:incoming':
          _onIncoming(e.data);
          break;
        case 'call:ringing':
          _onRinging(e.data);
          break;
        case 'call:accepted':
          _onAccepted(e.data);
          break;
        case 'call:signal':
          _enqueueSignal(e.data);
          break;
        case 'call:ended':
          _onEnded(e.data);
          break;
        case 'reconnected':
          _onReconnected();
          break;
        case 'logout':
          // Keluar akun saat panggilan berjalan / berdering: akhiri dulu (socket masih terbuka sehingga lawan bicara diberi tahu).
          if (call != null) hangup();
          break;
        default:
          break;
      }
    });
  }

  /// Setelah socket tersambung lagi: kirim sinyal yang tertahan, dan pastikan panggilan masih ada di server.
  Future<void> _onReconnected() async {
    final c = call;
    if (c == null) return;
    _flushSignals();
    final id = c.id;
    if (id == null) return;
    try {
      final r = await app.emit('call:state', {'callId': id});
      if (call != c) return;
      if (r['exists'] != true) {
        app.toast('Panggilan berakhir.');
        await _cleanup();
      }
    } catch (_) {
      // gagal bertanya: biarkan, panggilan tetap berjalan
    }
  }

  // ------------------------------------------------------------ util
  Future<MediaStream> _getMedia(String type) {
    final constraints = <String, dynamic>{
      // Peredam gema/noise & penyetel volume otomatis agar suara jernih dan tidak berdengung.
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': type == 'video' ? {'facingMode': 'user'} : false,
    };
    return navigator.mediaDevices.getUserMedia(constraints);
  }

  static const MethodChannel _native = MethodChannel('com.zarr.chat/call');

  /// Menjaga mikrofon tetap hidup saat aplikasi dikecilkan (Android). Gagal = abaikan.
  Future<void> _keepAlive(bool on, [String? name]) async {
    try {
      await _native.invokeMethod<bool>(on ? 'start' : 'stop', on ? {'title': 'Panggilan dengan ${name ?? 'pengguna'}'} : null);
    } catch (_) {}
  }

  void _mediaError() {
    app.toast('Izin mikrofon/kamera ditolak atau perangkat tidak ditemukan. Izinkan di pengaturan aplikasi lalu coba lagi.', error: true);
  }

  // Sinyal WebRTC (offer/answer/kandidat) yang belum terkirim karena socket sedang putus ditahan di sini dan
  // dikirim begitu tersambung lagi. Tanpa ini satu kedipan sinyal saja bisa membuat panggilan macet di "Menyambungkan…".
  final List<Map<String, dynamic>> _outSig = [];

  void _sendSignal(Map<String, dynamic> data) {
    final c = call;
    if (c == null || c.id == null) return;
    _outSig.add({'callId': c.id, 'data': data});
    _flushSignals();
  }

  void _flushSignals() {
    if (!app.socketConnected || _outSig.isEmpty) return; // sisanya dikirim saat 'reconnected'
    final c = call;
    final pending = List<Map<String, dynamic>>.from(_outSig);
    _outSig.clear();
    for (final item in pending) {
      if (c == null || c.id != item['callId']) continue;
      app.emit('call:signal', item, wait: false).catchError((Object e) {
        // Gagal karena jaringan: simpan lagi untuk dikirim ulang. Ditolak server (mis. panggilan sudah selesai): buang.
        if (e is ApiException && e.network && call == c) _outSig.add(item);
        return <String, dynamic>{};
      });
    }
  }

  void _show() {
    final nav = app.navKey.currentState;
    if (nav == null || _route != null) return;
    final r = MaterialPageRoute<void>(builder: (_) => const CallScreen(), fullscreenDialog: true);
    _route = r;
    nav.push(r);
  }

  void _hide() {
    final r = _route;
    _route = null;
    final nav = app.navKey.currentState;
    if (r != null && nav != null && r.isActive) nav.removeRoute(r);
  }

  // ------------------------------------------------------------ nada dering
  Future<void> _disposeTonePlayer() async {
    final pl = _tonePlayer;
    _tonePlayer = null;
    if (pl == null) return;
    try {
      await pl.stop();
    } catch (_) {}
    try {
      await pl.dispose();
    } catch (_) {}
  }

  Future<void> _stopTone() async {
    _toneToken++;
    await _disposeTonePlayer();
  }

  /// [incoming] true = dering panggilan masuk; false = nada tunggu untuk si penelepon.
  Future<void> _playTone({required bool incoming}) async {
    final t = ++_toneToken;
    await _disposeTonePlayer();
    if (t != _toneToken) return;
    try {
      final Uint8List bytes;
      if (incoming) {
        bytes = _ringWav ??= _buildWav(const [(440.0, 0.45), (0.0, 0.15), (440.0, 0.45), (0.0, 2.45)], volume: 0.98, drive: 2.8);
      } else {
        bytes = _backWav ??= _buildWav(const [(425.0, 1.0), (0.0, 3.0)], volume: 0.8, drive: 1.8);
      }
      final pl = ap.AudioPlayer();
      _tonePlayer = pl;
      await pl.setReleaseMode(ap.ReleaseMode.loop);
      // Dering memakai aliran "dering telepon" (ikut volume dering HP); nada tunggu memakai aliran panggilan suara.
      try {
        await pl.setAudioContext(ap.AudioContext(
          android: ap.AudioContextAndroid(
            contentType: incoming ? ap.AndroidContentType.sonification : ap.AndroidContentType.speech,
            usageType: incoming ? ap.AndroidUsageType.notificationRingtone : ap.AndroidUsageType.voiceCommunication,
          ),
        ));
      } catch (_) {}
      await pl.setVolume(audioPrefs.volume);
      if (t != _toneToken) return; // sudah dihentikan selagi menyiapkan
      // Dering panggilan masuk: MP3 pilihan pengguna (Pengaturan > Audio & Notifikasi > Nada Panggilan) bila ada, kalau tidak nada bawaan.
      final ap.Source src = (incoming && audioPrefs.callSoundId == 'custom' && audioPrefs.hasCustomCall)
          ? ap.DeviceFileSource(audioPrefs.customCallPath)
          : ap.BytesSource(bytes);
      await pl.play(src);
    } catch (_) {
      // tanpa nada, panggilan tetap berjalan (getar tetap aktif)
    }
  }

  void _startRing() {
    _ring?.cancel();
    HapticFeedback.heavyImpact();
    _ring = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.heavyImpact();
    });
    _playTone(incoming: true);
  }

  void _stopRing() {
    _ring?.cancel();
    _ring = null;
    _stopTone();
  }

  // ------------------------------------------------------------ renderer & koneksi
  Future<void> _initRenderers(ActiveCall c) async {
    try {
      await c.localR.initialize();
      await c.remoteR.initialize();
      c.renderersReady = true;
      _attach(c);
    } catch (_) {
      // tanpa renderer panggilan suara tetap berjalan; video hanya tidak tampil
    }
  }

  /// Menyambungkan stream ke renderer, hanya jika renderer sudah siap (renderer yang belum siap membuat layar error).
  /// Suara lawan bicara diperkeras (WebRTC mengizinkan penguatan 0-10x) supaya tidak pelan walau volume HP sudah penuh.
  void _boostRemote(ActiveCall c) {
    final tracks = c.remote?.getAudioTracks() ?? <MediaStreamTrack>[];
    for (final t in tracks) {
      if (c.boosted.contains(t.id)) continue;
      c.boosted.add(t.id);
      unawaited(Helper.setVolume(2.5, t).catchError((Object _) {}));
    }
  }

  void _attach(ActiveCall c) {
    _boostRemote(c);
    if (!c.renderersReady) return;
    try {
      if (c.type == 'video' && c.local != null) c.localR.srcObject = c.local;
      if (c.remote != null) c.remoteR.srcObject = c.remote;
    } catch (_) {}
  }

  Future<RTCPeerConnection> _makePC(ActiveCall c) async {
    await app.refreshConfig(force: false); // kredensial TURN dijaga tetap segar tanpa membuat panggilan menunggu
    if (call != c) throw const _CallGone();
    final servers = app.cfg?.iceServers ?? <Map<String, dynamic>>[];
    final ice = servers.isEmpty
        ? <Map<String, dynamic>>[
            {'urls': 'stun:stun.l.google.com:19302'}
          ]
        : servers;
    final pc = await createPeerConnection({'iceServers': ice, 'sdpSemantics': 'unified-plan'});
    if (call != c) {
      try {
        await pc.close();
      } catch (_) {}
      throw const _CallGone();
    }
    c.pc = pc;
    final local = c.local;
    if (local != null) {
      for (final t in local.getTracks()) {
        await pc.addTrack(t, local);
      }
    }
    pc.onTrack = (RTCTrackEvent e) async {
      if (call != c) return;
      if (e.streams.isNotEmpty) {
        c.remote = e.streams[0];
      } else {
        try {
          c.remote ??= await createLocalMediaStream('remote-${c.id}');
          await c.remote!.addTrack(e.track);
        } catch (_) {}
      }
      if (call != c) return;
      _attach(c);
      notifyListeners();
    };
    pc.onIceCandidate = (RTCIceCandidate cand) {
      if (cand.candidate == null) return;
      _sendSignal({
        'type': 'candidate',
        'candidate': {'candidate': cand.candidate, 'sdpMid': cand.sdpMid, 'sdpMLineIndex': cand.sdpMLineIndex},
      });
    };
    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (call != c) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected(c);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _onDisrupted(c, failed: false);
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _onDisrupted(c, failed: true);
      }
    };
    pc.onIceConnectionState = (RTCIceConnectionState s) {
      if (call != c) return;
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected || s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected(c);
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _onDisrupted(c, failed: true);
      }
    };
    // Bila dalam 40 detik belum tersambung (biasanya jaringan butuh TURN), hentikan dengan pesan jelas.
    c.connectTimer?.cancel();
    c.connectTimer = Timer(const Duration(seconds: 40), () {
      if (call == c && !c.connected) _failed();
    });
    return pc;
  }

  /// Jalur suara terganggu. Bukan langsung menyerah: mulai ulang pencarian jalur (ICE restart) beberapa kali,
  /// baru dianggap gagal bila tetap tidak pulih.
  void _onDisrupted(ActiveCall c, {required bool failed}) {
    if (call != c) return;
    if (failed) {
      final now = DateTime.now();
      if (c.lastFailAt != null && now.difference(c.lastFailAt!) < const Duration(seconds: 3)) return;
      c.lastFailAt = now;
      if (c.restartCount >= 3) {
        _failed();
        return;
      }
      c.restartCount++;
    } else if (!c.connected || c.reconnecting) {
      return; // belum pernah tersambung (ditangani batas waktu) atau sudah ditangani
    }
    if (c.connected) {
      c.reconnecting = true;
      c.dropTimer?.cancel();
      c.dropTimer = Timer(const Duration(seconds: 25), () {
        if (call == c && c.reconnecting) _failed();
      });
      notifyListeners();
    }
    unawaited(_restartIce(c));
    c.restartTimer?.cancel();
    c.restartTimer = Timer.periodic(const Duration(seconds: 6), (t) {
      if (call != c || !c.reconnecting) {
        t.cancel();
        return;
      }
      unawaited(_restartIce(c));
    });
  }

  /// Mencari jalur koneksi baru tanpa memutus panggilan. Hanya penelepon yang membuat offer; penerima meminta lewat sinyal 'restart'.
  Future<void> _restartIce(ActiveCall c) async {
    if (call != c) return;
    if (c.role != 'caller') {
      _sendSignal({'type': 'restart'});
      return;
    }
    final pc = c.pc;
    if (pc == null || c.restarting) return;
    c.restarting = true;
    try {
      final offer = await pc.createOffer({'mandatory': {'IceRestart': true}, 'optional': []});
      await pc.setLocalDescription(offer);
      if (call != c) return;
      _sendSignal({'type': 'offer', 'sdp': offer.sdp});
    } catch (_) {
      // gagal membuat offer: percobaan berikutnya (timer) akan mengulang
    } finally {
      c.restarting = false;
    }
  }

  void _failed() {
    final turn = app.cfg?.turnConfigured ?? false;
    app.toast(
        turn
            ? 'Koneksi panggilan gagal. Periksa jaringan Anda.'
            : 'Koneksi panggilan gagal. Jaringan Anda mungkin membutuhkan server TURN yang belum dikonfigurasi di server ini.',
        error: true);
    hangup();
  }

  void _markConnected(ActiveCall c) {
    c.dropTimer?.cancel();
    if (c.connected) {
      // pulih dari putus sesaat
      if (c.reconnecting) {
        c.reconnecting = false;
        c.restartTimer?.cancel();
        notifyListeners();
      }
      return;
    }
    c.connected = true;
    c.reconnecting = false;
    c.connectTimer?.cancel();
    _stopTone();
    c.state = 'Terhubung';
    c.timer?.cancel();
    c.timer = Timer.periodic(const Duration(seconds: 1), (_) {
      c.secs++;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _cleanup() async {
    final c = call;
    if (c == null) return;
    call = null;
    _starting = false;
    _accepting = false;
    _stopRing();
    unawaited(_keepAlive(false));
    c.timer?.cancel();
    c.connectTimer?.cancel();
    c.dropTimer?.cancel();
    c.restartTimer?.cancel();
    _outSig.clear();
    c.renderersReady = false;
    _hide(); // tutup layar panggilan lebih dulu supaya widget video dilepas sebelum renderer di-dispose
    notifyListeners();
    final pc = c.pc;
    c.pc = null;
    try {
      pc?.onTrack = null;
      pc?.onIceCandidate = null;
      pc?.onConnectionState = null;
      pc?.onIceConnectionState = null;
    } catch (_) {}
    try {
      for (final t in c.local?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await c.local?.dispose();
    } catch (_) {}
    try {
      await pc?.close();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 200));
    try {
      c.localR.srcObject = null;
      c.remoteR.srcObject = null;
    } catch (_) {}
    try {
      await c.localR.dispose();
    } catch (_) {}
    try {
      await c.remoteR.dispose();
    } catch (_) {}
    if (call == null) {
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ aksi
  Future<void> startCall(User peer, String type) async {
    if (call != null || _starting) {
      app.toast('Anda sedang dalam panggilan.');
      return;
    }
    _starting = true;
    if (!app.socketConnected && !await app.ensureConnected(seconds: 6)) {
      _starting = false;
      app.toast('Belum tersambung ke server. Periksa koneksi internet Anda lalu coba lagi.');
      return;
    }
    MediaStream stream;
    try {
      stream = await _getMedia(type);
    } catch (_) {
      _starting = false;
      _mediaError();
      return;
    }
    final c = ActiveCall(peer: peer, type: type, role: 'caller', state: 'Memanggil…', speaker: type == 'video');
    c.local = stream;
    call = c;
    _starting = false;
    unawaited(_keepAlive(true, peer.username));
    app.refreshConfig(force: false); // siapkan kredensial TURN selagi menunggu dijawab
    await _initRenderers(c);
    if (call != c) return; // dibatalkan selagi menyiapkan renderer
    _attach(c);
    _show();
    notifyListeners();
    try {
      final r = await app.emit('call:invite', {'toUserId': peer.id, 'type': type});
      final cid = r['callId'];
      if (call != c) {
        if (cid is int) app.emitQuiet('call:end', {'callId': cid});
        return;
      }
      c.id = cid is int ? cid : null;
      // Penerima offline: tetap "Memanggil…" sampai ia membuka aplikasi dan teleponnya benar-benar berdering.
      c.state = (r['ringing'] == false && !c.ringingEarly) ? 'Memanggil…' : 'Berdering…';
      notifyListeners();
      if (c.acceptedEarly) {
        _onAccepted({'callId': c.id});
      } else {
        _playTone(incoming: false);
      }
    } catch (e) {
      app.toast(errText(e));
      if (call == c) await _cleanup();
    }
  }

  void _onIncoming(Map<String, dynamic> d) {
    final cid = d['callId'];
    if (cid is! int) return;
    if (call != null && call!.id == cid) return; // duplikat: server mengirim ulang setelah sambungan pulih
    if (call != null || _starting) {
      app.emitQuiet('call:reject', {'callId': cid});
      return;
    }
    final type = d['type'] == 'video' ? 'video' : 'voice';
    final c = ActiveCall(
      peer: User.fromJson(d['from']),
      type: type,
      role: 'callee',
      state: type == 'video' ? 'Panggilan video masuk' : 'Panggilan suara masuk',
      speaker: type == 'video',
    );
    c.id = cid;
    call = c;
    app.refreshConfig(force: false); // siapkan kredensial TURN sebelum diterima
    _initRenderers(c).then((_) => notifyListeners());
    _startRing();
    _show();
    notifyListeners();
  }

  Future<void> accept() async {
    final c = call;
    if (c == null || c.accepted || _accepting) return;
    _accepting = true;
    try {
      MediaStream stream;
      try {
        stream = await _getMedia(c.type);
      } catch (_) {
        _mediaError();
        reject();
        return;
      }
      if (call != c) {
        for (final t in stream.getTracks()) {
          await t.stop();
        }
        await stream.dispose();
        return;
      }
      _stopRing();
      c.local = stream;
      unawaited(_keepAlive(true, c.peer.username));
      _attach(c);
      c.accepted = true;
      c.state = 'Menyambungkan…';
      notifyListeners();
      try {
        await _makePC(c);
        try {
          await Helper.setSpeakerphoneOn(c.speaker);
        } catch (_) {}
        if (call != c) return;
        await app.emit('call:accept', {'callId': c.id});
      } on _CallGone {
        return;
      } catch (e) {
        if (call != c) return;
        app.toast(errText(e), error: true);
        if (c.id != null) app.emitQuiet('call:reject', {'callId': c.id});
        await _cleanup();
      }
    } finally {
      _accepting = false;
    }
  }

  void reject() {
    final c = call;
    if (c == null) return;
    if (c.id != null) app.emitQuiet('call:reject', {'callId': c.id});
    _cleanup();
  }

  void hangup() {
    final c = call;
    if (c == null) return;
    if (c.id != null) app.emitQuiet('call:end', {'callId': c.id});
    _cleanup();
  }

  void _onRinging(Map<String, dynamic> d) {
    final c = call;
    if (c == null || c.role != 'caller' || c.accepted) return;
    if (c.id == null) {
      c.ringingEarly = true; // diproses setelah id panggilan diketahui (lihat startCall)
      return;
    }
    if (c.id != d['callId']) return;
    c.state = 'Berdering…';
    notifyListeners();
  }

  Future<void> _onAccepted(Map<String, dynamic> d) async {
    final c = call;
    if (c == null || c.role != 'caller' || c.pc != null || c.negotiating) return;
    if (c.id == null) {
      c.acceptedEarly = true; // diproses setelah id panggilan diketahui (lihat startCall)
      return;
    }
    if (c.id != d['callId']) return;
    c.negotiating = true;
    _stopTone();
    c.state = 'Menyambungkan…';
    notifyListeners();
    try {
      final pc = await _makePC(c);
      try {
        await Helper.setSpeakerphoneOn(c.speaker);
      } catch (_) {}
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      if (call != c) return;
      _sendSignal({'type': 'offer', 'sdp': offer.sdp});
    } on _CallGone {
      return;
    } catch (_) {
      if (call != c) return;
      app.toast('Gagal memulai panggilan.', error: true);
      hangup();
    }
  }

  Future<void> _addPending(ActiveCall c) async {
    final pc = c.pc;
    if (pc == null) return;
    final list = List<RTCIceCandidate>.from(c.pending);
    c.pending.clear();
    for (final cand in list) {
      try {
        await pc.addCandidate(cand);
      } catch (_) {
        // kandidat rusak diabaikan
      }
    }
  }

  void _enqueueSignal(Map<String, dynamic> d) {
    _sigQ = _sigQ.then((_) => _handleSignal(d)).catchError((Object _) {});
  }

  Future<void> _handleSignal(Map<String, dynamic> d) async {
    final c = call;
    if (c == null || c.id != d['callId']) return;
    final data = asMap(d['data']);
    final type = data['type'];
    final pc = c.pc;
    try {
      if (type == 'candidate') {
        final cm = asMap(data['candidate']);
        final cand = RTCIceCandidate(cm['candidate'] as String?, cm['sdpMid'] as String?, cm['sdpMLineIndex'] as int?);
        if (pc == null || await pc.getRemoteDescription() == null) {
          c.pending.add(cand); // simpan dulu, dipasang setelah remote description ada
        } else {
          await pc.addCandidate(cand);
        }
        return;
      }
      if (type == 'restart') {
        if (c.role == 'caller') unawaited(_restartIce(c));
        return;
      }
      if (pc == null) return;
      if (type == 'offer') {
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'offer'));
        await _addPending(c);
        final ans = await pc.createAnswer();
        await pc.setLocalDescription(ans);
        if (call != c) return;
        _sendSignal({'type': 'answer', 'sdp': ans.sdp});
      } else if (type == 'answer') {
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String?, 'answer'));
        await _addPending(c);
      }
    } catch (_) {
      // sinyal yang gagal diproses diabaikan; koneksi akan melaporkan kegagalan sendiri
    }
  }

  void _onEnded(Map<String, dynamic> d) {
    final c = call;
    if (c == null || c.id != d['callId']) return;
    if (d['self'] != true) {
      const reasons = {
        'rejected': 'Panggilan ditolak.',
        'no_answer': 'Tidak dijawab.',
        'cancelled': 'Panggilan dibatalkan.',
        'hangup': 'Panggilan berakhir.',
        'disconnected': 'Koneksi terputus.',
        'answered_elsewhere': 'Dijawab di perangkat lain.',
      };
      app.toast(reasons[d['reason']] ?? 'Panggilan berakhir.');
    }
    _cleanup();
  }

  void toggleMute() {
    final c = call;
    if (c == null) return;
    c.muted = !c.muted;
    for (final t in c.local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !c.muted;
    }
    notifyListeners();
  }

  void toggleCam() {
    final c = call;
    if (c == null) return;
    c.camOff = !c.camOff;
    for (final t in c.local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !c.camOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final c = call;
    if (c == null || c.type != 'video') return;
    final tracks = c.local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      c.frontCamera = !c.frontCamera;
      notifyListeners();
    } catch (_) {
      app.toast('Tidak dapat mengganti kamera.', error: true);
    }
  }

  Future<void> toggleSpeaker() async {
    final c = call;
    if (c == null) return;
    c.speaker = !c.speaker;
    try {
      await Helper.setSpeakerphoneOn(c.speaker);
    } catch (_) {}
    notifyListeners();
  }
}

final CallManager callManager = CallManager();

// ====================================================================== layar panggilan
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  /// Tombol bulat besar dengan label (terima / tolak / akhiri).
  Widget _action(IconData icon, Color bg, String label, VoidCallback onTap, {double size = 72}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 5))],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.44),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }

  /// Tombol bulat berbingkai putih (bisukan, speaker, kamera, balik kamera, akhiri) — gaya v2.
  Widget _ctl(IconData icon, String label, bool active, VoidCallback onTap, {Color? bg, double size = 62}) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg ?? (active ? Colors.white : Colors.white24),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(icon, color: (bg == null && active) ? Colors.black : Colors.white, size: size * 0.42),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ListenableBuilder(
        listenable: callManager,
        builder: (context, _) {
          final c = callManager.call;
          if (c == null) return const Scaffold(backgroundColor: Colors.black);
          final p = pal(context);
          final incoming = c.role == 'callee' && !c.accepted;
          final isVideo = c.type == 'video';
          final remoteOn = isVideo && c.remote != null && c.renderersReady;
          final stateText = c.reconnecting ? 'Menyambungkan ulang…' : (c.connected ? fmtDur(c.secs) : c.state);
          final top = MediaQuery.of(context).padding.top;

          final statusPill = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(20)),
            child: Text(stateText, style: TextStyle(color: p.yellow, fontSize: 16, fontWeight: FontWeight.w800)),
          );

          // Identitas lawan bicara: besar di tengah, atau ringkas di kiri atas saat video lawan sudah tampil.
          final Widget identity = remoteOn
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 140, 0),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      NameWithBadge(c.peer, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(stateText, style: TextStyle(color: p.yellow, fontSize: 15, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                )
              : Center(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(isVideo ? 'PANGGILAN VIDEO' : 'PANGGILAN SUARA',
                          style: const TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                      const SizedBox(height: 22),
                      Avatar(user: c.peer, size: 132, ring: p.yellow),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: NameWithBadge(c.peer, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(height: 12),
                      statusPill,
                    ]),
                  ),
                );

          final Widget controls = incoming
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _action(Icons.call_end, p.bad, 'Tolak', callManager.reject, size: 74),
                    _action(isVideo ? Icons.videocam : Icons.call, const Color(0xFF1C8A3C), 'Terima', callManager.accept, size: 74),
                  ]),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _ctl(c.muted ? Icons.mic_off : Icons.mic, c.muted ? 'Suara mati' : 'Bisukan', c.muted, callManager.toggleMute),
                    _ctl(c.speaker ? Icons.volume_up : Icons.volume_down, 'Speaker', c.speaker, callManager.toggleSpeaker),
                    if (isVideo) _ctl(c.camOff ? Icons.videocam_off : Icons.videocam, c.camOff ? 'Kamera mati' : 'Kamera', c.camOff, callManager.toggleCam),
                    if (isVideo) _ctl(Icons.cameraswitch, 'Balik kamera', false, callManager.switchCamera),
                    _ctl(Icons.call_end, 'Akhiri', false, callManager.hangup, bg: p.bad, size: 72),
                  ]),
                );

          return Scaffold(
            backgroundColor: const Color(0xFF0B0B0B),
            body: Stack(children: [
              if (remoteOn)
                Positioned.fill(child: RTCVideoView(c.remoteR, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
              else
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.35),
                        radius: 1.05,
                        colors: [Color(0x40FFDC35), Color(0xFF0B0B0B)],
                        stops: [0.0, 0.85],
                      ),
                    ),
                  ),
                ),
              // Bayangan atas & bawah agar teks dan tombol tetap terbaca di atas video.
              if (remoteOn)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                        stops: [0.0, 0.25, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              // Elemen kecil agar suara lawan bicara selalu terpasang pada panggilan suara.
              if (!isVideo && c.remote != null && c.renderersReady) SizedBox(width: 1, height: 1, child: RTCVideoView(c.remoteR)),
              SafeArea(
                child: Column(children: [
                  Expanded(child: identity),
                  Padding(padding: const EdgeInsets.only(bottom: 48), child: controls),
                ]),
              ),
              if (isVideo && !incoming && c.local != null && c.renderersReady)
                Positioned(
                  right: 16,
                  top: top + 12,
                  width: 104,
                  height: 150,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: c.camOff
                          ? const ColoredBox(color: Color(0xFF222222), child: Center(child: Icon(Icons.videocam_off, color: Colors.white54, size: 30)))
                          : RTCVideoView(c.localR, mirror: c.frontCamera, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ====================================================================== riwayat panggilan
class CallsTab extends StatefulWidget {
  const CallsTab({super.key});
  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  List<CallRecord> calls = [];
  bool loading = true;
  String? error;
  StreamSubscription<SocketEvent>? sub;
  final Set<int> sel = {}; // id panggilan terpilih (mode pilih seperti WhatsApp: tekan lama)

  bool get selecting => sel.isNotEmpty;

  void toggleSel(int id) => setState(() {
        if (!sel.remove(id)) sel.add(id);
      });

  void longPressRow(int id) {
    HapticFeedback.mediumImpact();
    toggleSel(id);
  }

  void clearSel() => setState(sel.clear);

  void selectAll() => setState(() {
        sel
          ..clear()
          ..addAll(calls.map((c) => c.id));
      });

  /// Hapus riwayat panggilan yang dipilih. Hanya hilang dari daftar Anda; riwayat lawan bicara tidak terpengaruh.
  Future<void> deleteSelected() async {
    final ids = sel.toList();
    if (ids.isEmpty) return;
    final ok = await showConfirm(context, ids.length == 1 ? 'Hapus panggilan ini?' : 'Hapus ${ids.length} panggilan?', 'Riwayat panggilan yang dipilih dihapus dari daftar Anda. Riwayat milik lawan bicara tidak terpengaruh.', 'Hapus', danger: true);
    if (!ok || !mounted) return;
    try {
      await app.api.post('/calls/delete', {'ids': ids});
      if (!mounted) return;
      setState(() {
        calls.removeWhere((c) => ids.contains(c.id));
        sel.clear();
      });
      app.toast(ids.length == 1 ? 'Panggilan dihapus.' : '${ids.length} panggilan dihapus.');
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Bar atas saat ada panggilan terpilih: jumlah terpilih + Hapus + menu titik tiga (Pilih semua).
  PreferredSizeWidget selectionBar() {
    return zAppBar(
      context,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: clearSel),
      titleSpacing: 0,
      title: Text('${sel.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
      actions: [
        IconButton(tooltip: 'Hapus', icon: const Icon(Icons.delete_outline), onPressed: deleteSelected),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Menu',
          onSelected: (v) {
            if (v == 'all') selectAll();
          },
          itemBuilder: (context) => const [PopupMenuItem<String>(value: 'all', child: Text('Pilih semua'))],
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    load();
    sub = app.events.listen((e) {
      if (e.name == 'call:ended' || e.name == 'reconnected') load();
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/calls'));
      calls = asList(r['calls']).map((c) => CallRecord.fromJson(c)).toList();
      sel.removeWhere((id) => !calls.any((c) => c.id == id)); // panggilan yang sudah hilang tidak ikut terpilih
      error = null;
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  String label(CallRecord c) {
    final incoming = c.direction == 'incoming';
    switch (c.status) {
      case 'missed':
        return incoming ? 'Tidak terjawab' : 'Tidak dijawab';
      case 'rejected':
        return 'Ditolak';
      case 'busy':
        return 'Sibuk';
      case 'failed':
        return 'Gagal';
      default:
        if (c.durationSec > 0) return '${incoming ? 'Masuk' : 'Keluar'} · ${fmtDur(c.durationSec)}';
        return incoming ? 'Masuk' : 'Keluar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null && calls.isEmpty) {
      body = EmptyState(icon: Icons.error_outline, title: 'Gagal memuat riwayat', text: error, action: NeoButton('Coba lagi', onPressed: load));
    } else if (calls.isEmpty) {
      body = const EmptyState(icon: Icons.call_outlined, title: 'Belum ada panggilan', text: 'Mulai panggilan suara dari dalam percakapan.');
    } else {
      body = RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.only(top: 14, bottom: 20),
          children: calls.map((c) {
            final missedIn = c.status == 'missed' && c.direction == 'incoming';
            final isSel = sel.contains(c.id);
            // Hari ini cukup jam saja ("18:18"); hari lain "Kemarin, 18:18" / "29/10/26, 18:18" (sebelumnya jam tampil dobel).
            final lt = listTime(c.createdAt);
            final ft = fmtTime(c.createdAt);
            final when = lt == ft ? ft : '$lt, $ft';
            return NeoRow(
              color: isSel ? p.accent.withAlpha(46) : null,
              onTap: selecting ? () => toggleSel(c.id) : null,
              onLongPress: () => longPressRow(c.id),
              leading: selectableAvatar(context, Avatar(user: c.peer, size: 44), isSel),
              title: NameWithBadge(c.peer),
              subtitle: Row(children: [
                Icon(c.direction == 'incoming' ? Icons.call_received : Icons.call_made, size: 14, color: missedIn ? p.bad : p.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('${c.type == 'video' ? 'Video' : 'Suara'} · ${label(c)} · $when',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: missedIn ? p.bad : p.muted, fontSize: 12.5)),
                ),
              ]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                InkResponse(
                  radius: 22,
                  onTap: selecting ? () => toggleSel(c.id) : () => callManager.startCall(c.peer, 'voice'),
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.call_outlined)),
                ),
                InkResponse(
                  radius: 22,
                  onTap: selecting ? () => toggleSel(c.id) : () => showVideoCallSoon(context),
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.videocam_outlined)),
                ),
              ]),
            );
          }).toList(),
        ),
      );
    }
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clearSel();
      },
      child: Scaffold(appBar: selecting ? selectionBar() : zAppBar(context, text: 'Panggilan'), body: body),
    );
  }
}
