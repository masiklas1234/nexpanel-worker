// ZARR CHAT - Musik Latar: musik yang menyala di background.
// - Dinyalakan/dimatikan dari Pengaturan → Musik Latar; pilihan disimpan di perangkat.
// - Bila nyala, musik otomatis diputar lagi setiap aplikasi dibuka dan terus berulang
//   (juga saat aplikasi dikecilkan / ditutup) sampai pengguna mematikannya.
// - Diputar lewat layanan foreground (just_audio_background) supaya tidak dimatikan sistem.
// - Otomatis dijeda saat ada panggilan suara/video, lalu dilanjutkan setelah panggilan selesai.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_storage.dart';
import 'calls.dart';
import 'state.dart';

class MusicStore extends ChangeNotifier {
  static const String _asset = 'assets/audio/musik_latar.mp3';
  static const String _prefKey = 'bg_music_on';

  AudioPlayer? _player;
  SharedPreferences? _prefs;
  Timer? _keeper;
  bool _loaded = false; // sumber audio sudah dipasang di pemutar
  bool _pausedForCall = false;
  bool _pausedForChat = false; // sedang memutar audio dari chat (pemutar global): musik latar ditahan
  bool _foreground = true;
  bool _busy = false;
  bool _starting = false; // mencegah dua pemuatan berjalan bersamaan
  bool _attached = false;

  /// Pilihan pengguna: musik latar nyala / mati.
  bool enabled = false;

  /// Sedang memproses nyala/mati (untuk mencegah ketukan berulang).
  bool get busy => _busy;

  /// Baca pilihan tersimpan lalu putar bila sebelumnya dinyalakan. Aman dipanggil sebelum runApp.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      enabled = _prefs!.getBool(_prefKey) ?? false;
    } catch (_) {
      enabled = false;
    }
    if (!_attached) {
      _attached = true;
      callManager.addListener(_onCallChanged);
    }
    notifyListeners();
    if (enabled) unawaited(_start());
  }

  Future<void> _savePref(bool v) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_prefKey, v);
    } catch (_) {}
  }

  /// Dipanggil dari tombol di Pengaturan.
  Future<void> setEnabled(bool v) async {
    if (_busy || v == enabled) return;
    _busy = true;
    notifyListeners();
    if (v) {
      enabled = true;
      await _savePref(true);
      final ok = await _start();
      if (!ok) {
        enabled = false;
        await _savePref(false);
        app.toast('Musik latar tidak dapat diputar.', error: true);
      }
    } else {
      enabled = false;
      _pausedForCall = false;
      _keeper?.cancel();
      await _savePref(false);
      await _stop();
    }
    _busy = false;
    notifyListeners();
  }

  // ------------------------------------------------------------ pemutar
  Future<bool> _start() async {
    if (!enabled) return false;
    // Selama panggilan berlangsung musik tetap dianggap "nyala", tetapi ditahan sampai panggilan selesai.
    if (callManager.call != null) {
      _pausedForCall = true;
      return true;
    }
    if (_pausedForChat) return true; // dilanjutkan otomatis oleh holdForChat(false)
    if (_starting) return true;
    _starting = true;
    try {
      var pl = _player;
      if (pl == null) {
        pl = AudioPlayer();
        _player = pl;
        pl.playingStream.listen(_onPlaying);
        final player = pl;
        unawaited(player.setVolume(audioPrefs.volume));
        audioPrefs.addListener(() => player.setVolume(audioPrefs.volume));
      }
      if (!_loaded) {
        await pl.setAudioSource(
          AudioSource.asset(
            _asset,
            tag: const MediaItem(id: 'zarr_musik_latar', title: 'Musik Latar', artist: 'ZARR CHAT', album: 'ZARR CHAT'),
          ),
        );
        await pl.setLoopMode(LoopMode.one);
        _loaded = true;
      }
      if (!enabled) return false; // dimatikan saat sedang memuat
      // play() baru selesai ketika pemutaran berhenti, jadi tidak di-await.
      unawaited(pl.play().catchError((Object _) {}));
      return true;
    } catch (e) {
      debugPrint('Musik latar gagal: $e');
      _loaded = false;
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    final pl = _player;
    if (pl == null) return;
    try {
      await pl.stop();
    } catch (_) {}
    _loaded = false;
  }

  /// Bila pemutaran berhenti sendiri (mis. fokus audio diambil suara/video lain) saat aplikasi
  /// sedang dibuka, nyalakan lagi — kecuali sedang panggilan atau pengguna sudah mematikannya.
  void _onPlaying(bool playing) {
    _keeper?.cancel();
    if (playing || !enabled || _pausedForCall || _pausedForChat || !_foreground || _busy) return;
    _keeper = Timer(const Duration(seconds: 3), () {
      if (enabled && !_pausedForCall && !_pausedForChat && _foreground && !(_player?.playing ?? false)) unawaited(_start());
    });
  }

  void _onCallChanged() {
    final inCall = callManager.call != null;
    if (inCall && !_pausedForCall) {
      if (!enabled) return;
      _pausedForCall = true;
      _keeper?.cancel();
      try {
        _player?.pause();
      } catch (_) {}
    } else if (!inCall && _pausedForCall) {
      _pausedForCall = false;
      if (enabled) {
        // Beri waktu sebentar agar sesi audio panggilan dilepas dulu.
        Timer(const Duration(milliseconds: 800), () {
          if (enabled && !_pausedForCall) unawaited(_start());
        });
      }
    }
  }

  /// Pemutar audio chat (musik/pesan suara) mulai / berhenti: musik latar dijeda lalu dilanjutkan otomatis setelahnya.
  void holdForChat(bool hold) {
    if (hold == _pausedForChat) return;
    _pausedForChat = hold;
    if (!enabled) return;
    if (hold) {
      _keeper?.cancel();
      try {
        _player?.pause();
      } catch (_) {}
    } else if (!_pausedForCall) {
      Timer(const Duration(milliseconds: 600), () {
        if (enabled && !_pausedForChat && !_pausedForCall) unawaited(_start());
      });
    }
  }

  /// Dipanggil saat aplikasi kembali dibuka / dikecilkan.
  void onLifecycle(bool foreground) {
    _foreground = foreground;
    if (foreground && enabled && !_pausedForCall && !_pausedForChat && !(_player?.playing ?? false)) unawaited(_start());
  }
}

final MusicStore music = MusicStore();
