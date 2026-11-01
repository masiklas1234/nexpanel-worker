// ZARR CHAT - Audio & Notifikasi dan Penyimpanan Media (halaman di Pengaturan).
//
// - AudioPrefs: volume suara di dalam aplikasi, suara pesan masuk, getar. Disimpan di perangkat.
// - MediaPrefs: pilihan unduh otomatis media. Disimpan di perangkat.
// - Halaman penyimpanan menghitung dan menghapus berkas media yang diunduh ke HP.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'media.dart';
import 'models.dart';
import 'push.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart' show fmtDur;
import 'widgets.dart';

// ====================================================================== suara bawaan (dibuat lewat kode)
/// Satu nada: (frekuensi Hz, lama detik). Frekuensi 0 = hening.
typedef _Seg = (double, double);

class MsgSound {
  final String id;
  final String name;
  final List<_Seg> segs;
  const MsgSound(this.id, this.name, this.segs);
}

const List<MsgSound> kMsgSounds = [
  MsgSound('ping', 'Ping', [(1175.0, 0.09), (0.0, 0.03), (1568.0, 0.16)]),
  MsgSound('pop', 'Pop', [(660.0, 0.07), (880.0, 0.10)]),
  MsgSound('lonceng', 'Lonceng', [(988.0, 0.12), (0.0, 0.04), (1319.0, 0.12), (0.0, 0.04), (1760.0, 0.22)]),
  MsgSound('dingdong', 'Ding Dong', [(880.0, 0.22), (0.0, 0.03), (659.0, 0.30)]),
];

double _tanh(double x) {
  final e = math.exp(2 * x.clamp(-20.0, 20.0));
  return (e - 1) / (e + 1);
}

Uint8List _buildSoundWav(List<_Seg> segs, {double amp = 0.97}) {
  const rate = 22050;
  final samples = <int>[];
  for (final s in segs) {
    final n = (s.$2 * rate).round();
    for (var i = 0; i < n; i++) {
      final t = i / rate;
      // Amplop halus (naik cepat, turun pelan) supaya tidak berderak di awal/akhir nada.
      final attack = math.min(1.0, i / (rate * 0.006));
      final release = math.min(1.0, (n - i) / (rate * 0.03));
      final env = math.min(attack, release);
      // Nada dasar + harmonik terdengar jauh lebih keras di speaker HP daripada sinus murni; tanh = kompresi lembut tanpa pecah.
      final w = s.$1 <= 0
          ? 0.0
          : (math.sin(2 * math.pi * s.$1 * t) + 0.55 * math.sin(2 * math.pi * 2 * s.$1 * t) + 0.3 * math.sin(2 * math.pi * 3 * s.$1 * t)) / 1.85;
      final v = s.$1 <= 0 ? 0.0 : (_tanh(w * 2.6) / _tanh(2.6)) * env * amp;
      samples.add((v * 32767).round().clamp(-32768, 32767));
    }
  }
  final dataLen = samples.length * 2;
  final b = BytesBuilder();
  void str(String x) => b.add(x.codeUnits);
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(rate);
  u32(rate * 2);
  u16(2);
  u16(16);
  str('data');
  u32(dataLen);
  final d = ByteData(dataLen);
  for (var i = 0; i < samples.length; i++) {
    d.setInt16(i * 2, samples[i], Endian.little);
  }
  b.add(d.buffer.asUint8List());
  return b.toBytes();
}

// ====================================================================== pengaturan audio
class AudioPrefs extends ChangeNotifier {
  /// Volume suara di dalam aplikasi: 0.0 - 1.0 (berlaku untuk pesan suara, musik latar, nada panggilan, suara pesan).
  double volume = 1.0;
  bool messageSound = true;
  bool vibrate = true;
  String soundId = 'ping'; // ping | pop | lonceng | dingdong | custom (MP3 sendiri)
  DateTime _lastPlay = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, Uint8List> _wav = {};

  // ---- MP3 sendiri untuk suara notifikasi pesan dan nada panggilan.
  // Suara notifikasi Android dimainkan oleh SISTEM lewat "saluran notifikasi" yang suaranya tidak bisa diubah setelah dibuat.
  // Karena itu setiap ganti berkas, nomor versi (ver) naik dan aplikasi membuat saluran baru (lihat push.dart).
  static const MethodChannel _sounds = MethodChannel('com.zarr.chat/sounds');
  static const int maxCustomBytes = 8 * 1024 * 1024;
  static const int maxNotifSec = 30;
  static const int maxCallSec = 60;
  String customNotifName = '';
  String customNotifPath = ''; // salinan di penyimpanan aplikasi (diputar saat aplikasi terbuka)
  String customNotifUri = ''; // alamat di penyimpanan suara sistem (dipakai saluran notifikasi Android)
  int customNotifVer = 0;
  String callSoundId = 'default'; // default | custom
  String customCallName = '';
  String customCallPath = '';
  String customCallUri = '';
  int customCallVer = 0;
  ap.AudioPlayer? _previewPl;

  bool get hasCustomNotif => customNotifPath.isNotEmpty && customNotifUri.isNotEmpty && File(customNotifPath).existsSync();
  bool get hasCustomCall => customCallPath.isNotEmpty && customCallUri.isNotEmpty && File(customCallPath).existsSync();

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      volume = (sp.getDouble('zc_volume') ?? 1.0).clamp(0.0, 1.0);
      messageSound = sp.getBool('zc_msg_sound') ?? true;
      vibrate = sp.getBool('zc_msg_vibrate') ?? true;
      customNotifName = sp.getString('zc_cn_name') ?? '';
      customNotifPath = sp.getString('zc_cn_path') ?? '';
      customNotifUri = sp.getString('zc_cn_uri') ?? '';
      customNotifVer = sp.getInt('zc_cn_ver') ?? 0;
      customCallName = sp.getString('zc_cc_name') ?? '';
      customCallPath = sp.getString('zc_cc_path') ?? '';
      customCallUri = sp.getString('zc_cc_uri') ?? '';
      customCallVer = sp.getInt('zc_cc_ver') ?? 0;
      final s = sp.getString('zc_msg_sound_id') ?? 'ping';
      soundId = (kMsgSounds.any((x) => x.id == s) || (s == 'custom' && hasCustomNotif)) ? s : 'ping';
      final c = sp.getString('zc_call_sound_id') ?? 'default';
      callSoundId = (c == 'custom' && hasCustomCall) ? 'custom' : 'default';
    } catch (_) {
      // pakai nilai bawaan
    }
  }

  Future<void> _save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble('zc_volume', volume);
      await sp.setBool('zc_msg_sound', messageSound);
      await sp.setBool('zc_msg_vibrate', vibrate);
      await sp.setString('zc_msg_sound_id', soundId);
      await sp.setString('zc_call_sound_id', callSoundId);
      await sp.setString('zc_cn_name', customNotifName);
      await sp.setString('zc_cn_path', customNotifPath);
      await sp.setString('zc_cn_uri', customNotifUri);
      await sp.setInt('zc_cn_ver', customNotifVer);
      await sp.setString('zc_cc_name', customCallName);
      await sp.setString('zc_cc_path', customCallPath);
      await sp.setString('zc_cc_uri', customCallUri);
      await sp.setInt('zc_cc_ver', customCallVer);
    } catch (_) {
      // gagal menyimpan: nilai tetap dipakai selama aplikasi terbuka
    }
  }

  void setVolume(double v) {
    volume = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  Future<void> commitVolume() => _save();

  Future<void> setMessageSound(bool v) async {
    messageSound = v;
    notifyListeners();
    await _save();
  }

  Future<void> setVibrate(bool v) async {
    vibrate = v;
    notifyListeners();
    await _save();
  }

  /// Memilih suara notifikasi pesan. Berlaku untuk bunyi di dalam aplikasi DAN notifikasi Android (saluran notifikasi ikut diganti).
  Future<void> setSound(String id) async {
    soundId = (kMsgSounds.any((x) => x.id == id) || (id == 'custom' && hasCustomNotif)) ? id : 'ping';
    notifyListeners();
    await _save();
    await push.onSoundChanged();
  }

  /// Memilih nada panggilan masuk: 'default' (bawaan) atau 'custom' (MP3 sendiri).
  Future<void> setCallSound(String id) async {
    callSoundId = (id == 'custom' && hasCustomCall) ? 'custom' : 'default';
    notifyListeners();
    await _save();
    await push.onSoundChanged();
  }

  String get soundName => soundId == 'custom' ? 'MP3: $customNotifName' : kMsgSounds.firstWhere((s) => s.id == soundId, orElse: () => kMsgSounds.first).name;
  String get callSoundName => callSoundId == 'custom' ? 'MP3: $customCallName' : 'Bawaan ZARR CHAT';

  /// Sumber suara untuk pesan [id] (tombol putar / bunyi pesan masuk).
  ap.Source _notifSource(String id) {
    if (id == 'custom' && hasCustomNotif) return ap.DeviceFileSource(customNotifPath);
    final def = kMsgSounds.firstWhere((s) => s.id == id, orElse: () => kMsgSounds.first);
    return ap.BytesSource(_wav[def.id] ??= _buildSoundWav(def.segs));
  }

  Future<void> stopPreview() async {
    final pl = _previewPl;
    _previewPl = null;
    if (pl == null) return;
    try {
      await pl.stop();
    } catch (_) {}
    try {
      await pl.dispose();
    } catch (_) {}
  }

  /// Contoh suara di halaman pengaturan: [call] true = nada panggilan, false = suara notifikasi. Hanya satu contoh berbunyi sekaligus.
  Future<void> preview({required bool call, required String id}) async {
    await stopPreview();
    try {
      final ap.Source src;
      if (call) {
        src = (id == 'custom' && hasCustomCall)
            ? ap.DeviceFileSource(customCallPath)
            : ap.BytesSource(_wav['call'] ??= _buildSoundWav(const [(440.0, 0.45), (0.0, 0.15), (440.0, 0.45)]));
      } else {
        src = _notifSource(id);
      }
      final pl = ap.AudioPlayer();
      _previewPl = pl;
      await pl.setReleaseMode(ap.ReleaseMode.stop);
      try {
        await pl.setAudioContext(ap.AudioContext(
          android: ap.AudioContextAndroid(
            contentType: ap.AndroidContentType.sonification,
            usageType: call ? ap.AndroidUsageType.notificationRingtone : ap.AndroidUsageType.notification,
          ),
        ));
      } catch (_) {}
      await pl.setVolume(volume);
      await pl.play(src);
    } catch (_) {
      // tanpa contoh suara: pengaturan tetap tersimpan
    }
  }

  /// Memilih berkas audio sendiri untuk notifikasi ([call] false) atau nada panggilan ([call] true).
  /// Mengembalikan null bila berhasil, 'batal' bila pengguna membatalkan, selain itu pesan galat untuk ditampilkan.
  Future<String?> pickCustom({required bool call}) async {
    String? tmpCopy;
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (r == null || r.files.isEmpty) return 'batal';
      final f = r.files.single;
      final src = f.path;
      if (src == null || src.isEmpty) return 'Berkas tidak bisa dibaca.';
      if (f.size > maxCustomBytes) return 'Berkas terlalu besar (maksimal 8 MB).';
      final ms = (await _sounds.invokeMethod<int>('durationMs', {'path': src})) ?? 0;
      if (ms <= 0) return 'Berkas ini bukan audio yang bisa diputar.';
      final limit = call ? maxCallSec : maxNotifSec;
      if (ms > limit * 1000) return 'Durasi ${fmtDur((ms / 1000).round())} terlalu panjang. Pilih audio maksimal $limit detik.';
      var ext = src.contains('.') ? src.substring(src.lastIndexOf('.') + 1).toLowerCase() : 'mp3';
      if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) ext = 'mp3';
      final mime = switch (ext) {
        'm4a' || 'mp4' => 'audio/mp4',
        'aac' => 'audio/aac',
        'ogg' || 'opus' => 'audio/ogg',
        'wav' => 'audio/wav',
        _ => 'audio/mpeg',
      };
      final ver = (call ? customCallVer : customNotifVer) + 1;
      final base = 'zarr_${call ? 'ring' : 'notif'}_$ver.$ext';
      final dir = await getApplicationSupportDirectory();
      final dest = File('${dir.path}/$base');
      await File(src).copy(dest.path);
      tmpCopy = dest.path;
      final uri = await _sounds.invokeMethod<String>('install', {'path': dest.path, 'name': base, 'mime': mime, 'ringtone': call});
      if (uri == 'permission') {
        await dest.delete();
        return 'Izinkan akses penyimpanan, lalu pilih berkasnya lagi.';
      }
      if (uri == null || !uri.contains('://')) {
        await dest.delete();
        return 'Gagal menyimpan suara. Coba berkas audio lain.';
      }
      tmpCopy = null;
      final oldUri = call ? customCallUri : customNotifUri;
      final oldPath = call ? customCallPath : customNotifPath;
      final shown = f.name.length > 40 ? '${f.name.substring(0, 37)}...' : f.name;
      if (call) {
        customCallName = shown;
        customCallPath = dest.path;
        customCallUri = uri;
        customCallVer = ver;
        callSoundId = 'custom';
      } else {
        customNotifName = shown;
        customNotifPath = dest.path;
        customNotifUri = uri;
        customNotifVer = ver;
        soundId = 'custom';
      }
      notifyListeners();
      await _save();
      await push.onSoundChanged();
      // berkas lama dibersihkan setelah yang baru aktif
      if (oldUri.isNotEmpty) unawaited(_sounds.invokeMethod<bool>('remove', {'uri': oldUri}).catchError((Object _) => false));
      if (oldPath.isNotEmpty && oldPath != dest.path) {
        try {
          await File(oldPath).delete();
        } catch (_) {}
      }
      return null;
    } catch (e) {
      if (tmpCopy != null) {
        try {
          await File(tmpCopy).delete();
        } catch (_) {}
      }
      return 'Gagal memilih berkas audio.';
    }
  }

  /// Memutar suara pesan [id] (atau pilihan sekarang) pada volume aplikasi.
  Future<void> play({String? id}) async {
    try {
      final sid = id ?? soundId;
      final src = _notifSource(sid);
      final pl = ap.AudioPlayer();
      await pl.setReleaseMode(ap.ReleaseMode.release);
      try {
        await pl.setAudioContext(ap.AudioContext(
          android: const ap.AudioContextAndroid(
            contentType: ap.AndroidContentType.sonification,
            usageType: ap.AndroidUsageType.notification,
          ),
        ));
      } catch (_) {}
      await pl.setVolume(volume);
      unawaited(pl.onPlayerComplete.first.timeout(const Duration(seconds: 6), onTimeout: () {}).whenComplete(() => pl.dispose()));
      await pl.play(src);
    } catch (_) {
      // tanpa suara: pesan tetap tampil
    }
  }

  /// Dipanggil saat pesan dari orang lain masuk dan aplikasi sedang dibuka.
  void onIncomingMessage() {
    final now = DateTime.now();
    if (now.difference(_lastPlay).inMilliseconds < 900) return; // banyak pesan beruntun: cukup satu bunyi
    _lastPlay = now;
    if (vibrate) HapticFeedback.lightImpact();
    if (messageSound && volume > 0) unawaited(play());
  }
}

final AudioPrefs audioPrefs = AudioPrefs();

// ====================================================================== unduh otomatis
const List<(String, String)> kAutoDownloadModes = [
  ('all', 'Semua media (foto, video, audio)'),
  ('photovideo', 'Foto & video saja'),
  ('audio', 'Audio saja'),
  ('none', 'Tidak ada (unduh manual)'),
];

class MediaPrefs extends ChangeNotifier {
  String autoDownload = 'none';

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getString('zc_auto_dl') ?? 'none';
      autoDownload = kAutoDownloadModes.any((m) => m.$1 == v) ? v : 'none';
    } catch (_) {
      // pakai bawaan
    }
  }

  Future<void> set(String v) async {
    autoDownload = v;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('zc_auto_dl', v);
    } catch (_) {
      // abaikan
    }
  }
}

final MediaPrefs mediaPrefs = MediaPrefs();

/// Mengunduh media pesan masuk lebih dulu sesuai pilihan "Unduh otomatis". Gagal diam-diam: media tetap bisa dibuka manual.
Future<void> autoDownloadMedia(Message m) async {
  try {
    final md = m.media;
    if (md == null || m.senderId == app.me?.id) return;
    final k = md.kind;
    final bool want;
    switch (mediaPrefs.autoDownload) {
      case 'all':
        want = k == 'image' || k == 'video' || k == 'audio';
        break;
      case 'photovideo':
        want = k == 'image' || k == 'video';
        break;
      case 'audio':
        want = k == 'audio';
        break;
      default:
        want = false;
    }
    if (!want || md.size > 50 * 1024 * 1024) return;
    if (k == 'image') {
      final fi = await DefaultCacheManager().downloadFile(app.api.abs(md.url), authHeaders: app.api.mediaHeaders);
      await saveImageCopy(md.url, fi.file);
    } else {
      await cachedMediaFile(md.url, ext: k == 'audio' ? 'm4a' : 'mp4');
    }
  } catch (_) {
    // abaikan
  }
}

// ====================================================================== pemindaian penyimpanan
class MediaStats {
  int photo = 0;
  int video = 0;
  int voice = 0;
  int other = 0;
  int get total => photo + video + voice + other;
}

const _videoExt = {'mp4', 'mov', 'webm', 'mkv', '3gp', 'avi'};
const _audioExt = {'m4a', 'aac', 'mp3', 'ogg', 'opus', 'wav', 'amr'};
const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'avif', 'bmp'};

String _extOf(String path) {
  final name = path.split('/').last;
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// Berkas media unduhan (diawali "zc_"): di folder aplikasi (files/Audio, Video, Images, Documents) dan sisa lama di folder sementara.
Future<List<File>> _downloadedFiles() async {
  final out = <File>[];
  final dirs = <Directory>[await getTemporaryDirectory()];
  final root = await appFilesDir();
  for (final n in kMediaFolders) {
    dirs.add(Directory('${root.path}/$n'));
  }
  for (final dir in dirs) {
    if (!dir.existsSync()) continue;
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is File && e.uri.pathSegments.last.startsWith('zc_')) out.add(e);
      }
    } catch (_) {
      // folder sedang berubah: lewati
    }
  }
  return out;
}

int _dirSize(Directory d) {
  var n = 0;
  try {
    if (!d.existsSync()) return 0;
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is File) n += e.lengthSync();
    }
  } catch (_) {
    // folder sedang berubah: hitung sebisanya
  }
  return n;
}

Future<Directory> _imageCacheDir() async => Directory('${(await getTemporaryDirectory()).path}/libCachedImageData');

Future<MediaStats> scanMediaStats() async {
  final s = MediaStats();
  for (final f in await _downloadedFiles()) {
    int len;
    try {
      len = f.lengthSync();
    } catch (_) {
      continue;
    }
    final ext = _extOf(f.path);
    if (_videoExt.contains(ext)) {
      s.video += len;
    } else if (_audioExt.contains(ext)) {
      s.voice += len;
    } else if (_imageExt.contains(ext)) {
      s.photo += len;
    } else {
      s.other += len;
    }
  }
  s.photo += _dirSize(await _imageCacheDir());
  return s;
}

Future<void> _deleteDownloaded(bool Function(String ext) test) async {
  for (final f in await _downloadedFiles()) {
    try {
      if (test(_extOf(f.path))) f.deleteSync();
    } catch (_) {
      // berkas sedang dipakai: lewati
    }
  }
}

Future<void> _clearImages() async {
  try {
    await DefaultCacheManager().emptyCache();
  } catch (_) {
    // lanjut ke pembersihan memori
  }
  imageCache.clear();
  imageCache.clearLiveImages();
}

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

// ====================================================================== halaman: Audio & Notifikasi
const MethodChannel _system = MethodChannel('com.zarr.chat/system');

class AudioNotifPage extends StatefulWidget {
  const AudioNotifPage({super.key});
  @override
  State<AudioNotifPage> createState() => _AudioNotifPageState();
}

class _AudioNotifPageState extends State<AudioNotifPage> {
  @override
  void initState() {
    super.initState();
    audioPrefs.addListener(_rebuild);
  }

  @override
  void dispose() {
    audioPrefs.removeListener(_rebuild);
    unawaited(audioPrefs.stopPreview());
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> openAndroidSettings() async {
    try {
      final ok = await _system.invokeMethod<bool>('notificationSettings');
      if (ok != true) app.toast('Tidak dapat membuka pengaturan notifikasi Android.', error: true);
    } catch (_) {
      app.toast('Tidak dapat membuka pengaturan notifikasi Android.', error: true);
    }
  }

  Future<void> testNotif() async {
    if (!await push.notificationsAllowed()) {
      app.toast('Notifikasi ZARR CHAT dimatikan di Android. Aktifkan lewat "Semua notifikasi ZARR CHAT".', error: true);
      return;
    }
    await push.test();
  }

  /// Lembar pilihan suara: suara bawaan + "MP3 sendiri". [call] true = nada panggilan, false = suara notifikasi.
  Future<void> pickSound({required bool call}) async {
    final hasCustom = call ? audioPrefs.hasCustomCall : audioPrefs.hasCustomNotif;
    final current = call ? audioPrefs.callSoundId : audioPrefs.soundId;
    final customName = call ? audioPrefs.customCallName : audioPrefs.customNotifName;
    final limit = call ? AudioPrefs.maxCallSec : AudioPrefs.maxNotifSec;
    final options = call ? const [('default', 'Bawaan ZARR CHAT')] : [for (final s in kMsgSounds) (s.id, s.name)];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(call ? 'Nada panggilan' : 'Suara notifikasi', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                leading: Icon(o.$1 == current ? Icons.radio_button_checked : Icons.radio_button_off),
                trailing: IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => audioPrefs.preview(call: call, id: o.$1)),
                onTap: () => Navigator.of(ctx).pop(o.$1),
              ),
            const Divider(height: 1),
            if (hasCustom)
              ListTile(
                title: const Text('MP3 sendiri', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(customName, maxLines: 1, overflow: TextOverflow.ellipsis),
                leading: Icon(current == 'custom' ? Icons.radio_button_checked : Icons.radio_button_off),
                trailing: IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => audioPrefs.preview(call: call, id: 'custom')),
                onTap: () => Navigator.of(ctx).pop('custom'),
              ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: Text(hasCustom ? 'Ganti MP3 sendiri…' : 'Pilih MP3 sendiri…', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Dari file di HP, maksimal $limit detik'),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
          ]),
        ),
      ),
    );
    await audioPrefs.stopPreview();
    if (chosen == null) return;
    if (chosen == 'pick') {
      final err = await audioPrefs.pickCustom(call: call);
      if (err == null) {
        app.toast(call ? 'Nada panggilan diganti.' : 'Suara notifikasi diganti.');
        unawaited(audioPrefs.preview(call: call, id: 'custom'));
      } else if (err != 'batal') {
        app.toast(err, error: true);
      }
      return;
    }
    if (call) {
      await audioPrefs.setCallSound(chosen);
      unawaited(audioPrefs.preview(call: true, id: chosen));
    } else {
      await audioPrefs.setSound(chosen);
      unawaited(audioPrefs.play());
    }
  }

  Future<void> testCall() async {
    if (!await push.notificationsAllowed()) {
      app.toast('Notifikasi ZARR CHAT dimatikan di Android. Aktifkan lewat "Semua notifikasi ZARR CHAT".', error: true);
      return;
    }
    await push.testCall();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final pct = (audioPrefs.volume * 100).round();
    return Scaffold(
      appBar: zAppBar(context, text: 'Audio & Notifikasi', centerTitle: true),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 28), children: [
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(audioPrefs.volume <= 0 ? Icons.volume_off : (audioPrefs.volume < 0.5 ? Icons.volume_down : Icons.volume_up), color: const Color(0xFFFF4560)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Volume', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
              Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ]),
            Slider(
              value: audioPrefs.volume,
              min: 0,
              max: 1,
              divisions: 20,
              activeColor: const Color(0xFFFF4560),
              onChanged: audioPrefs.setVolume,
              onChangeEnd: (_) async {
                await audioPrefs.commitVolume();
                unawaited(audioPrefs.play());
              },
            ),
            Text('Berlaku untuk pesan suara, musik latar, nada panggilan, dan suara pesan masuk. Untuk suara lebih keras, naikkan juga volume HP (tombol samping). Suara lawan bicara saat panggilan sudah diperkeras otomatis.',
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ]),
        ),
        const NeoSection('Suara notifikasi & panggilan'),
        NeoTile(
          icon: Icons.library_music_outlined,
          title: 'Suara Notifikasi',
          subtitle: '${audioPrefs.soundName} • berlaku juga untuk notifikasi Android',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => pickSound(call: false),
        ),
        NeoTile(
          icon: Icons.ring_volume_outlined,
          title: 'Nada Panggilan',
          subtitle: '${audioPrefs.callSoundName} • dering telepon masuk',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => pickSound(call: true),
        ),
        const NeoSection('Notifikasi Android (suara dari HP)'),
        NeoTile(
          icon: Icons.notifications_active,
          title: 'Tes notifikasi',
          subtitle: 'Munculkan notifikasi percobaan sekarang',
          trailing: const Icon(Icons.play_arrow),
          onTap: testNotif,
        ),
        NeoTile(
          icon: Icons.phone_in_talk_outlined,
          title: 'Tes nada panggilan',
          subtitle: 'Bunyikan nada panggilan lewat notifikasi percobaan',
          trailing: const Icon(Icons.play_arrow),
          onTap: testCall,
        ),
        NeoTile(
          icon: Icons.battery_saver_outlined,
          title: 'Izinkan berjalan di latar belakang',
          subtitle: 'Agar notifikasi tidak tertahan saat HP diam atau sedang main game',
          trailing: const Icon(Icons.open_in_new),
          onTap: () => push.requestBatteryExemption(force: true),
        ),
        NeoTile(
          icon: Icons.settings_outlined,
          title: 'Semua notifikasi ZARR CHAT',
          subtitle: 'Buka pengaturan notifikasi Android',
          trailing: const Icon(Icons.open_in_new),
          onTap: openAndroidSettings,
        ),
        const NeoSection('Suara di dalam app'),
        NeoSwitchTile(
          icon: Icons.music_note,
          title: 'Suara pesan masuk',
          subtitle: 'Berbunyi saat ada pesan baru dan aplikasi sedang dibuka',
          value: audioPrefs.messageSound,
          onChanged: audioPrefs.setMessageSound,
        ),
        NeoSwitchTile(
          icon: Icons.vibration,
          title: 'Getar pesan masuk',
          subtitle: 'Getar singkat saat ada pesan baru',
          value: audioPrefs.vibrate,
          onChanged: audioPrefs.setVibrate,
        ),
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          color: p.surface2,
          child: Text('Saat aplikasi ditutup atau sedang main game, pesan, panggilan, dan pengumuman tetap muncul lewat notifikasi push. Suara notifikasi dan nada panggilan yang Anda pilih (termasuk MP3 sendiri) dipakai juga oleh notifikasi tersebut. Bila tidak muncul atau suaranya tidak berubah, tekan Tes notifikasi, lalu pastikan notifikasi diizinkan dan penghematan baterai dimatikan untuk ZARR CHAT. Pesan dari obrolan yang dibisukan tidak berbunyi.',
              style: TextStyle(color: p.text, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

// ====================================================================== halaman: Penyimpanan Media
class MediaStoragePage extends StatefulWidget {
  const MediaStoragePage({super.key});
  @override
  State<MediaStoragePage> createState() => _MediaStoragePageState();
}

class _MediaStoragePageState extends State<MediaStoragePage> {
  MediaStats? stats;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    mediaPrefs.addListener(_rebuild);
    refresh();
  }

  @override
  void dispose() {
    mediaPrefs.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    final s = await scanMediaStats();
    if (mounted) setState(() => stats = s);
  }

  Future<void> run(Future<void> Function() job, String done) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await job();
      app.toast(done);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    busy = false;
    await refresh();
  }

  Future<void> deleteOne(String label, Future<void> Function() job) async {
    final ok = await showConfirm(context, 'Hapus $label?', 'Berkas $label yang tersimpan di HP akan dihapus. Pesannya tidak ikut terhapus, dan media bisa diunduh lagi saat dibuka.', 'Hapus', danger: true);
    if (!ok) return;
    await run(job, '$label dihapus.');
  }

  Future<void> deleteAll() async {
    final ok = await showConfirm(context, 'Hapus semua media?', 'Semua media yang tersimpan di HP akan dihapus. Pesannya tidak ikut terhapus, dan media bisa diunduh lagi saat dibuka.', 'Hapus semua', danger: true);
    if (!ok) return;
    await run(() async {
      await _deleteDownloaded((_) => true);
      await _clearImages();
    }, 'Semua media dihapus.');
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final s = stats;
    Widget row(IconData icon, String label, int? bytes, VoidCallback onDelete) {
      return NeoTile(
        icon: icon,
        title: label,
        subtitle: bytes == null ? 'Menghitung…' : fmtBytes(bytes),
        trailing: Text('Hapus', style: TextStyle(color: (bytes ?? 0) > 0 ? const Color(0xFFF44336) : p.muted, fontWeight: FontWeight.w800)),
        onTap: (bytes ?? 0) > 0 ? onDelete : null,
      );
    }

    return Scaffold(
      appBar: zAppBar(context, text: 'Penyimpanan Media', centerTitle: true),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 28), children: [
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(children: [
            const Icon(Icons.sd_storage, size: 44, color: Color(0xFFFF4560)),
            const SizedBox(height: 10),
            Text(s == null ? '…' : fmtBytes(s.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34)),
            const SizedBox(height: 4),
            Text('Media chat tersimpan di HP', style: TextStyle(color: p.muted, fontSize: 13)),
          ]),
        ),
        const NeoSection('Unduh otomatis'),
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final m in kAutoDownloadModes)
              InkWell(
                onTap: () => mediaPrefs.set(m.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Expanded(child: Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    Icon(mediaPrefs.autoDownload == m.$1 ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: mediaPrefs.autoDownload == m.$1 ? const Color(0xFFFF4560) : p.text),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        row(Icons.image, 'Foto & gambar', s?.photo, () => deleteOne('foto & gambar', () async {
          await _deleteDownloaded(_imageExt.contains);
          await _clearImages();
        })),
        row(Icons.videocam, 'Video', s?.video, () => deleteOne('video', () => _deleteDownloaded(_videoExt.contains))),
        row(Icons.mic, 'Pesan suara', s?.voice, () => deleteOne('pesan suara', () => _deleteDownloaded(_audioExt.contains))),
        row(Icons.insert_drive_file_outlined, 'Dokumen & lainnya', s?.other, () => deleteOne('dokumen & lainnya', () => _deleteDownloaded((e) => !_videoExt.contains(e) && !_audioExt.contains(e) && !_imageExt.contains(e)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF44336), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              onPressed: busy || (s?.total ?? 0) == 0 ? null : deleteAll,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Hapus semua media', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Text(
              '"Foto & gambar" mencakup foto chat, stiker, foto profil, dan story yang disimpan sementara. Media yang kamu unduh disimpan di HP (folder Android/data/com.zarr.chat/files: Audio, Video, Images, Documents) supaya tidak diunduh ulang. Menghapus media tidak menghapus pesannya.',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ),
      ]),
    );
  }
}
