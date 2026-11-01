// ZARR CHAT - tampilan media: foto, video, pesan suara, dokumen, teks bertautan.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'audio_storage.dart';
import 'auth.dart';
import 'models.dart';
import 'music.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

final Map<String, String> _fileCache = {};

String _safeName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

const _imgExtSet = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'avif', 'bmp'};
const _vidExtSet = {'mp4', 'mov', 'webm', 'mkv', '3gp', 'avi'};
const _audExtSet = {'m4a', 'aac', 'mp3', 'ogg', 'opus', 'wav', 'amr'};

String _fileExt(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// Nama subfolder penyimpanan menurut jenis berkas.
String mediaFolderName(String ext) {
  final e = ext.toLowerCase();
  if (_audExtSet.contains(e)) return 'Audio';
  if (_vidExtSet.contains(e)) return 'Video';
  if (_imgExtSet.contains(e)) return 'Images';
  return 'Documents';
}

const List<String> kMediaFolders = ['Audio', 'Video', 'Images', 'Documents'];

Directory? _filesRoot;

/// Folder penyimpanan aplikasi di HP: Android/data/com.zarr.chat/files (tanpa izin tambahan).
/// Bila tidak tersedia (mis. bukan Android), memakai folder dokumen aplikasi.
Future<Directory> appFilesDir() async {
  final c = _filesRoot;
  if (c != null) return c;
  Directory d;
  try {
    d = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  } catch (_) {
    d = await getApplicationDocumentsDirectory();
  }
  _filesRoot = d;
  return d;
}

/// Path tujuan unduhan: files/<Audio|Video|Images|Documents>/zc_<url>_<nama>. Folder dibuat otomatis.
Future<String> _downloadPath(String url, String base) async {
  final root = await appFilesDir();
  final sub = Directory('${root.path}/${mediaFolderName(_fileExt(base))}');
  if (!sub.existsSync()) sub.createSync(recursive: true);
  return '${sub.path}/zc_${_safeName(url)}_$base';
}

/// Lokasi lama (folder sementara) sebelum unduhan dipindah ke folder aplikasi; dipakai lagi bila masih ada.
Future<String> _legacyPath(String url, String base) async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/zc_${_safeName(url)}_$base';
}

/// Path berkas bila media ini sudah diunduh sebelumnya; null bila belum (tanpa mengunduh).
Future<String?> _preDownloadedPath(String url, String ext) async {
  try {
    final cached = _fileCache[url];
    if (cached != null && File(cached).existsSync()) return cached;
    final base = '${_safeName(url)}.$ext';
    final path = await _downloadPath(url, base);
    if (File(path).existsSync()) return path;
    final old = await _legacyPath(url, base);
    return File(old).existsSync() ? old : null;
  } catch (_) {
    return null;
  }
}

/// Mengunduh media (yang butuh login) ke folder aplikasi (Android/data/com.zarr.chat/files/...) dan mengembalikan path-nya.
Future<String> cachedMediaFile(String url, {String? ext, String? fileName}) async {
  final cached = _fileCache[url];
  if (cached != null && File(cached).existsSync()) return cached;
  final base = fileName != null && fileName.isNotEmpty ? _safeName(fileName) : '${_safeName(url)}.${ext ?? 'bin'}';
  final path = await _downloadPath(url, base);
  // Sudah pernah diunduh (mis. lewat Unduh otomatis atau sebelum aplikasi dimulai ulang): pakai lagi.
  if (File(path).existsSync()) {
    _fileCache[url] = path;
    return path;
  }
  final old = await _legacyPath(url, base);
  if (File(old).existsSync()) {
    _fileCache[url] = old;
    return old;
  }
  await app.api.downloadToFile(url, path);
  _fileCache[url] = path;
  return path;
}

String _imageExtOf(List<int> h) {
  if (h.length >= 3 && h[0] == 0xFF && h[1] == 0xD8) return 'jpg';
  if (h.length >= 4 && h[0] == 0x89 && h[1] == 0x50 && h[2] == 0x4E && h[3] == 0x47) return 'png';
  if (h.length >= 4 && h[0] == 0x47 && h[1] == 0x49 && h[2] == 0x46) return 'gif';
  if (h.length >= 12 && h[0] == 0x52 && h[1] == 0x49 && h[8] == 0x57 && h[9] == 0x45) return 'webp';
  if (h.length >= 12 && h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70) return 'heic';
  return 'jpg';
}

/// Menyalin foto yang sudah ada di cache ke folder aplikasi (files/Images) supaya tersimpan dan terlihat di pengelola berkas.
Future<void> saveImageCopy(String url, File src) async {
  try {
    if (!src.existsSync()) return;
    final raf = await src.open();
    final head = await raf.read(12);
    await raf.close();
    final dest = await _downloadPath(url, '${_safeName(url)}.${_imageExtOf(head)}');
    if (!File(dest).existsSync()) await src.copy(dest);
  } catch (_) {
    // gagal menyalin tidak boleh mengganggu tampilan foto
  }
}

/// Mengambil foto (dari cache bila sudah ada) lalu menyimpan salinannya ke folder aplikasi. Gagal diam-diam.
Future<void> saveRemoteImage(String url) async {
  try {
    final f = await DefaultCacheManager().getSingleFile(app.api.abs(url), headers: app.api.mediaHeaders);
    await saveImageCopy(url, f);
  } catch (_) {
    // abaikan
  }
}

const MethodChannel _galleryChannel = MethodChannel('com.zarr.chat/gallery');

/// Menyimpan foto/video ke galeri HP (Pictures/ZARR CHAT atau Movies/ZARR CHAT), seperti menu "Simpan" di WhatsApp.
/// Media yang belum ada di HP diunduh dulu (dan ikut tersimpan di folder aplikasi).
Future<void> saveToGallery({String? url, String? localPath, required bool video}) async {
  try {
    var path = localPath;
    if (path == null || !File(path).existsSync()) {
      if (url == null || url.isEmpty) {
        app.toast('Berkas tidak ditemukan.', error: true);
        return;
      }
      app.toast(video ? 'Menyimpan video…' : 'Menyimpan foto…');
      if (video) {
        path = await cachedMediaFile(url, ext: 'mp4');
      } else {
        final f = await DefaultCacheManager().getSingleFile(app.api.abs(url), headers: app.api.mediaHeaders);
        path = f.path;
      }
    }
    var ext = 'mp4';
    var mime = 'video/mp4';
    if (!video) {
      final raf = await File(path).open();
      final head = await raf.read(12);
      await raf.close();
      ext = _imageExtOf(head);
      mime = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
    }
    final name = 'ZARR_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final r = await _galleryChannel.invokeMethod<String>('save', {'path': path, 'name': name, 'mime': mime, 'video': video});
    if (r == 'ok') {
      app.toast(video ? 'Video tersimpan di galeri.' : 'Foto tersimpan di galeri.');
    } else if (r == 'permission') {
      app.toast('Izinkan akses penyimpanan, lalu ketuk Simpan lagi.', error: true);
    } else {
      app.toast('Gagal menyimpan ke galeri.', error: true);
    }
  } catch (_) {
    app.toast('Gagal menyimpan ke galeri.', error: true);
  }
}

/// Menu titik tiga di pojok kanan atas penampil foto/video: "Simpan ke galeri".
Widget galleryMenu({String? url, String? localPath, required bool video}) {
  return PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'Menu',
    onSelected: (v) {
      if (v == 'save') unawaited(saveToGallery(url: url, localPath: localPath, video: video));
    },
    itemBuilder: (context) => const [
      PopupMenuItem<String>(
        value: 'save',
        child: Row(children: [Icon(Icons.download, size: 20), SizedBox(width: 12), Text('Simpan ke galeri')]),
      ),
    ],
  );
}

Future<void> openDocument(Media m) async {
  try {
    app.toast('Mengunduh…');
    final path = await cachedMediaFile(m.url, fileName: m.name ?? 'file');
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done) {
      app.toast('Tidak ada aplikasi untuk membuka file ini.', error: true);
    }
  } catch (e) {
    app.toast(errText(e), error: true);
  }
}

/// Teks dengan tautan yang bisa diketuk.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  const LinkText(this.text, {super.key, required this.style, required this.linkColor});
  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final List<TapGestureRecognizer> _recs = [];
  static final RegExp _re = RegExp(r'(https?://[^\s<>"]+)');

  void _clear() {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _re.allMatches(widget.text)) {
      if (m.start > last) spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      final url = m.group(0)!;
      final rec = TapGestureRecognizer()..onTap = () => openLink(url);
      _recs.add(rec);
      spans.add(TextSpan(
        text: url,
        recognizer: rec,
        style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline, fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < widget.text.length) spans.add(TextSpan(text: widget.text.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

/// Foto layar penuh (cubit untuk zoom). Foto yang dibuka juga disimpan ke folder aplikasi (files/Images).
class ImageViewerPage extends StatefulWidget {
  final String? url;
  final String? localPath;
  const ImageViewerPage({super.key, this.url, this.localPath});
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  @override
  void initState() {
    super.initState();
    final u = widget.url;
    if (widget.localPath == null && u != null && u.isNotEmpty) unawaited(saveRemoteImage(u));
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final localPath = widget.localPath;
    Widget img;
    if (localPath != null) {
      img = Image.file(File(localPath), fit: BoxFit.contain);
    } else {
      img = CachedNetworkImage(
        imageUrl: app.api.abs(url),
        httpHeaders: app.api.mediaHeaders,
        fit: BoxFit.contain,
        placeholder: (c, u) => const Spin(),
        errorWidget: (c, u, e) => const Icon(Icons.broken_image, color: Colors.white, size: 64),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [galleryMenu(url: url, localPath: localPath, video: false)],
      ),
      body: Center(child: InteractiveViewer(minScale: 1, maxScale: 5, child: img)),
    );
  }
}

/// Pemutar video layar penuh.
class VideoPage extends StatefulWidget {
  final String? url;
  final String? localPath;
  const VideoPage({super.key, this.url, this.localPath});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? c;
  String? error;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      final remoteUrl = widget.url;
      var pre = widget.localPath == null && remoteUrl != null ? await _preDownloadedPath(remoteUrl, 'mp4') : null;
      if (pre == null && widget.localPath == null && remoteUrl != null && remoteUrl.isNotEmpty) {
        // Video diunduh dulu ke folder aplikasi (files/Video) lalu diputar dari sana; bila gagal, diputar langsung lewat jaringan.
        try {
          pre = await cachedMediaFile(remoteUrl, ext: 'mp4');
        } catch (_) {
          pre = null;
        }
      }
      final ctl = widget.localPath != null
          ? VideoPlayerController.file(File(widget.localPath!))
          : pre != null
              ? VideoPlayerController.file(File(pre))
              : VideoPlayerController.networkUrl(Uri.parse(app.api.abs(widget.url)), httpHeaders: app.api.mediaHeaders);
      c = ctl;
      await ctl.initialize();
      await ctl.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => error = 'Video tidak dapat diputar.');
    }
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = c;
    Widget body;
    if (error != null) {
      body = Text(error!, style: const TextStyle(color: Colors.white));
    } else if (ctl == null || !ctl.value.isInitialized) {
      body = const CircularProgressIndicator(color: Colors.white);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        AspectRatio(aspectRatio: ctl.value.aspectRatio, child: VideoPlayer(ctl)),
        VideoProgressIndicator(ctl, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Color(0xFFFFDC35))),
        const SizedBox(height: 8),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: ctl,
          builder: (context, v, _) => IconButton(
            iconSize: 48,
            color: Colors.white,
            icon: Icon(v.isPlaying ? Icons.pause_circle : Icons.play_circle),
            onPressed: () => v.isPlaying ? ctl.pause() : ctl.play(),
          ),
        ),
      ]);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [galleryMenu(url: widget.url, localPath: widget.localPath, video: true)],
      ),
      body: Center(child: body),
    );
  }
}

// =====================================================================================================================
// Pemutar audio GLOBAL (musik / pesan suara) — tetap menyala saat pindah layar, seperti Telegram.
// Satu pemutar untuk seluruh aplikasi; yang tampil di gelembung chat dan di bar mini di atas layar hanyalah "remote"-nya.
// Bar mini punya tombol jeda/putar dan tombol X (X = hentikan dan tutup bar).
// =====================================================================================================================
class ChatAudio extends ChangeNotifier {
  AudioPlayer? _pl;
  final List<StreamSubscription<dynamic>> _subs = [];
  int _gen = 0; // penanda permintaan terbaru (mencegah balapan saat pengguna cepat berpindah lagu)

  String? key; // identitas audio yang sedang aktif (url / path); null = tidak ada
  String title = '';
  String subtitle = '';
  bool playing = false;
  bool loading = false;
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;

  bool get active => key != null;

  AudioPlayer _player() {
    var pl = _pl;
    if (pl != null) return pl;
    pl = AudioPlayer();
    _pl = pl;
    _subs.add(pl.onPositionChanged.listen((d) {
      if (!active) return;
      pos = d;
      notifyListeners();
    }));
    _subs.add(pl.onDurationChanged.listen((d) {
      if (!active) return;
      dur = d;
      notifyListeners();
    }));
    _subs.add(pl.onPlayerStateChanged.listen((st) {
      if (!active) return;
      playing = st == PlayerState.playing;
      notifyListeners();
    }));
    _subs.add(pl.onPlayerComplete.listen((_) => unawaited(stop()))); // selesai diputar: bar ikut hilang
    audioPrefs.addListener(() => _pl?.setVolume(audioPrefs.volume));
    return pl;
  }

  /// Ketuk tombol di gelembung: audio yang sama = jeda/lanjut; audio lain = ganti ke audio itu.
  Future<void> toggle({required String id, String? url, String? localPath, required String title, String subtitle = ''}) async {
    if (key == id) {
      await pauseOrResume();
      return;
    }
    final gen = ++_gen;
    key = id;
    this.title = title;
    this.subtitle = subtitle;
    playing = false;
    loading = true;
    pos = Duration.zero;
    dur = Duration.zero;
    notifyListeners();
    music.holdForChat(true); // musik latar berhenti sementara agar tidak bertabrakan
    try {
      final pl = _player();
      await pl.stop();
      final path = localPath ?? await cachedMediaFile(url ?? '', ext: 'm4a');
      if (gen != _gen) return; // sudah diganti permintaan lain
      await pl.setVolume(audioPrefs.volume);
      await pl.play(DeviceFileSource(path));
      if (gen != _gen) return;
      loading = false;
      notifyListeners();
    } catch (e) {
      if (gen != _gen) return;
      app.toast('Audio tidak dapat diputar.', error: true);
      await stop();
    }
  }

  Future<void> pauseOrResume() async {
    final pl = _pl;
    if (pl == null || !active || loading) return;
    try {
      if (playing) {
        await pl.pause();
      } else {
        music.holdForChat(true);
        await pl.resume();
      }
    } catch (_) {
      app.toast('Audio tidak dapat diputar.', error: true);
    }
  }

  /// Geser posisi (0..1).
  Future<void> seekFraction(double f) async {
    final pl = _pl;
    if (pl == null || !active || dur.inMilliseconds <= 0) return;
    try {
      await pl.seek(Duration(milliseconds: (dur.inMilliseconds * f.clamp(0.0, 1.0)).round()));
    } catch (_) {}
  }

  /// Tombol X / selesai: hentikan, tutup bar, lanjutkan musik latar bila sebelumnya menyala.
  Future<void> stop() async {
    _gen++;
    final pl = _pl;
    key = null;
    playing = false;
    loading = false;
    pos = Duration.zero;
    dur = Duration.zero;
    notifyListeners();
    try {
      await pl?.stop();
    } catch (_) {}
    music.holdForChat(false);
  }
}

final ChatAudio chatAudio = ChatAudio();

/// Keterangan di bawah foto/video/audio dibatasi selebar media-nya. Tanpa batas ini, keterangan yang panjang melebarkan
/// gelembung dan menyisakan ruang kosong di samping foto atau pemutar lagu.
Widget captionUnderMedia(String type, Widget caption) {
  final maxW = type == 'audio' ? 250.0 : (type == 'image' || type == 'video') ? 230.0 : null;
  if (maxW == null) return caption;
  return ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: caption);
}

/// Durasi lagu dari keterangan bot (baris "⏱️ 3:12"), supaya pemutar tidak menampilkan "--:--" sebelum diputar. Null bila tidak ada.
String? captionDuration(String? body) {
  if (body == null || body.isEmpty) return null;
  final m = RegExp('\u23F1\uFE0F?\\s*(\\d{1,2}:\\d{2}(?::\\d{2})?)').firstMatch(body);
  return m?.group(1);
}

String _audioTitle(String? name) {
  var n = (name ?? '').trim();
  if (n.isEmpty || RegExp(r'^(voice|vn|ptt|rec|audio_?\d)', caseSensitive: false).hasMatch(n)) return 'Pesan suara';
  n = n.replaceFirst(RegExp(r'\.(mp3|m4a|aac|ogg|opus|wav|webm|mp4)$', caseSensitive: false), '');
  return n.isEmpty ? 'Pesan suara' : n;
}

/// Pemutar audio di dalam gelembung chat (remote untuk [chatAudio]): tombol putar bulat, gelombang suara,
/// durasi di bawahnya, dan tombol unduh di kanan.
class VoicePlayer extends StatelessWidget {
  final String? url;
  final String? localPath;
  final Color color;
  final String? name; // nama berkas (judul lagu)
  final String sender; // pengirim (ditampilkan di bar mini)
  final String? fallbackDur; // durasi dari keterangan pesan, dipakai selama durasi asli belum diketahui
  const VoicePlayer({super.key, this.url, this.localPath, required this.color, this.name, this.sender = '', this.fallbackDur});

  String get _id => (url != null && url!.isNotEmpty) ? url! : (localPath ?? '');

  static const int _bars = 30;

  /// Tinggi batang gelombang (tetap untuk audio yang sama, dibuat dari id-nya).
  List<double> _wave() {
    var h = 17;
    for (final c in _id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final out = <double>[];
    for (var i = 0; i < _bars; i++) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      final shape = 0.55 + 0.45 * ((i % 7) / 6.0);
      out.add((0.25 + 0.75 * ((h % 1000) / 1000.0)) * shape);
    }
    return out;
  }

  Future<void> _download() async {
    final u = url;
    if (u == null || u.isEmpty) return;
    try {
      app.toast('Mengunduh audio…');
      await cachedMediaFile(u, ext: 'm4a');
      app.toast('Audio tersimpan di folder aplikasi (Audio).');
    } catch (_) {
      app.toast('Audio tidak dapat diunduh.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = color.computeLuminance() < 0.5;
    final btnBg = color;
    final btnFg = dark ? Colors.white : Colors.black;
    final bars = _wave();
    return ListenableBuilder(
      listenable: chatAudio,
      builder: (context, _) {
        final mine = chatAudio.key == _id && _id.isNotEmpty;
        final playing = mine && chatAudio.playing;
        final loading = mine && chatAudio.loading;
        final pos = mine ? chatAudio.pos : Duration.zero;
        final dur = mine ? chatAudio.dur : Duration.zero;
        final total = dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds;
        final frac = (pos.inMilliseconds / total).clamp(0.0, 1.0);
        final playedBars = (frac * _bars).round();
        return SizedBox(
          width: 250,
          child: Row(children: [
            GestureDetector(
              onTap: _id.isEmpty ? null : () => chatAudio.toggle(id: _id, url: url, localPath: localPath, title: _audioTitle(name), subtitle: sender),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: btnBg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: loading
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: btnFg))
                    : Icon(playing ? Icons.pause : Icons.play_arrow, size: 30, color: btnFg),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 34,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < _bars; i++)
                        Container(
                          width: 3,
                          height: 6 + 28 * bars[i],
                          decoration: BoxDecoration(
                            color: i < playedBars ? color : color.withAlpha(90),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(mine && (playing || pos > Duration.zero) ? fmtDur(pos.inSeconds) : (dur.inSeconds > 0 ? fmtDur(dur.inSeconds) : (fallbackDur ?? '--:--')),
                    style: TextStyle(fontSize: 12, color: color)),
              ]),
            ),
            if (url != null && url!.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.download, size: 24, color: color),
                onPressed: _download,
              ),
          ]),
        );
      },
    );
  }
}

/// Bar mini di paling atas layar (di semua halaman) selama ada audio aktif. Ketuk bar = jeda/lanjut, X = hentikan.
class AudioBarHost extends StatelessWidget {
  final Widget child;
  const AudioBarHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Struktur widget SENGAJA tetap sama saat bar muncul/hilang agar Navigator (dan seluruh layar) tidak dibangun ulang.
    return ListenableBuilder(
      listenable: chatAudio,
      builder: (context, _) {
        final active = chatAudio.active;
        final mq = MediaQuery.of(context);
        return Column(children: [
          if (active) _bar(context, mq.padding.top) else const SizedBox.shrink(),
          Expanded(
            child: MediaQuery(
              data: active ? mq.copyWith(padding: mq.padding.copyWith(top: 0), viewPadding: mq.viewPadding.copyWith(top: 0)) : mq,
              child: child,
            ),
          ),
        ]);
      },
    );
  }

  Widget _bar(BuildContext context, double topInset) {
    final p = pal(context);
    final a = chatAudio;
    final total = a.dur.inMilliseconds <= 0 ? 1 : a.dur.inMilliseconds;
    final frac = (a.pos.inMilliseconds / total).clamp(0.0, 1.0);
    return Material(
      color: p.surface,
      elevation: 3,
      child: Container(
        padding: EdgeInsets.only(top: topInset),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line, width: 1.5))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 50,
            child: Row(children: [
              a.loading
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)))
                  : IconButton(
                      icon: Icon(a.playing ? Icons.pause : Icons.play_arrow, color: p.text),
                      onPressed: a.pauseOrResume,
                    ),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 14)),
                  if (a.subtitle.isNotEmpty) Text(a.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
              ),
              IconButton(icon: Icon(Icons.close, color: p.muted), onPressed: a.stop),
            ]),
          ),
          LinearProgressIndicator(value: frac.toDouble(), minHeight: 3, color: p.accent, backgroundColor: p.divider),
        ]),
      ),
    );
  }
}

// =====================================================================================================================
// Kirim foto / video ala WhatsApp + foto/video "sekali lihat" (view once)
// =====================================================================================================================

/// Pilihan pengguna di layar pratinjau kirim.
class MediaSendChoice {
  final String caption;
  final bool viewOnce;
  const MediaSendChoice({required this.caption, required this.viewOnce});
}

/// Membuka layar pratinjau kirim layar penuh (pengganti dialog "Kirim foto"). Mengembalikan null bila dibatalkan.
Future<MediaSendChoice?> showMediaCompose(
  BuildContext context, {
  required String path,
  required String kind,
  required String toName,
  bool allowViewOnce = true,
}) {
  return Navigator.of(context).push<MediaSendChoice>(MaterialPageRoute<MediaSendChoice>(
    fullscreenDialog: true,
    builder: (_) => MediaComposePage(path: path, kind: kind, toName: toName, allowViewOnce: allowViewOnce),
  ));
}

/// Perlindungan layar Android (FLAG_SECURE): screenshot & rekam layar diblokir, pratinjau aplikasi terbaru kosong.
/// Dipakai selama foto/video sekali lihat tampil.
class SecureScreen {
  static const MethodChannel _ch = MethodChannel('com.zarr.chat/secure');
  static int _users = 0;

  /// true bila perlindungan benar-benar aktif. Bila false, media sekali lihat TIDAK boleh ditampilkan.
  static Future<bool> enable() async {
    _users++;
    try {
      return (await _ch.invokeMethod<bool>('setSecure', <String, dynamic>{'on': true})) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> disable() async {
    if (_users > 0) _users--;
    if (_users > 0) return;
    try {
      await _ch.invokeMethod<bool>('setSecure', <String, dynamic>{'on': false});
    } catch (_) {
      // abaikan
    }
  }
}

class MediaComposePage extends StatefulWidget {
  final String path;
  final String kind; // 'image' | 'video'
  final String toName;
  final bool allowViewOnce;
  const MediaComposePage({super.key, required this.path, required this.kind, required this.toName, this.allowViewOnce = true});
  @override
  State<MediaComposePage> createState() => _MediaComposePageState();
}

class _MediaComposePageState extends State<MediaComposePage> {
  final TextEditingController cap = TextEditingController();
  final FocusNode focus = FocusNode();
  VideoPlayerController? vc;
  bool viewOnce = false;
  bool videoFailed = false;
  bool muted = true;

  bool get isVideo => widget.kind == 'video';

  @override
  void initState() {
    super.initState();
    if (isVideo) initVideo();
  }

  Future<void> initVideo() async {
    try {
      final c = VideoPlayerController.file(File(widget.path));
      vc = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => videoFailed = true);
    }
  }

  @override
  void dispose() {
    vc?.dispose();
    cap.dispose();
    focus.dispose();
    super.dispose();
  }

  void toggleOnce() {
    HapticFeedback.selectionClick();
    setState(() => viewOnce = !viewOnce);
  }

  void toggleMute() {
    final c = vc;
    if (c == null || !c.value.isInitialized) return;
    setState(() => muted = !muted);
    c.setVolume(muted ? 0 : 1);
  }

  void send() {
    focus.unfocus();
    Navigator.of(context).pop(MediaSendChoice(caption: cap.text.trim(), viewOnce: widget.allowViewOnce && viewOnce));
  }

  Widget roundBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x66000000)),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget preview() {
    if (!isVideo) {
      return InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Image.file(
          File(widget.path),
          fit: BoxFit.contain,
          errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      );
    }
    final c = vc;
    if (videoFailed) return const Icon(Icons.videocam_off, color: Colors.white54, size: 64);
    if (c == null || !c.value.isInitialized) return const CircularProgressIndicator(color: Colors.white);
    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
      },
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: c.value.aspectRatio <= 0 ? 1 : c.value.aspectRatio, child: VideoPlayer(c)),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, v, _) => v.isPlaying
              ? const SizedBox.shrink()
              : Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                ),
        ),
      ]),
    );
  }

  Widget onceToggle(ZPalette p) {
    const ink = Color(0xFF111111);
    return Tooltip(
      message: 'Sekali lihat',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggleOnce,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: viewOnce ? p.yellow : Colors.transparent,
              border: Border.all(color: viewOnce ? ink : Colors.white70, width: 2),
            ),
            alignment: Alignment.center,
            child: Text('1', style: TextStyle(color: viewOnce ? ink : Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    const ink = Color(0xFF111111);
    const none = InputBorder.none;
    final what = isVideo ? 'video' : 'foto';
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              roundBtn(Icons.close, 'Batal', () => Navigator.of(context).pop()),
              const Spacer(),
              if (isVideo && vc != null && vc!.value.isInitialized) roundBtn(muted ? Icons.volume_off : Icons.volume_up, muted ? 'Nyalakan suara' : 'Matikan suara', toggleMute),
            ]),
          ),
          Expanded(child: Center(child: preview())),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (viewOnce)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.visibility_outlined, size: 16, color: p.yellow),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Sekali lihat: $what ini hanya bisa dibuka 1 kali oleh penerima. Tidak bisa disimpan, diteruskan, atau di-screenshot.',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ),
                  ]),
                ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: TextField(
                      controller: cap,
                      focusNode: focus,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      cursorColor: p.yellow,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Tambahkan keterangan…',
                        hintStyle: TextStyle(color: Colors.white54),
                        filled: false,
                        fillColor: Colors.transparent,
                        border: none,
                        enabledBorder: none,
                        focusedBorder: none,
                        errorBorder: none,
                        disabledBorder: none,
                        focusedErrorBorder: none,
                        counterText: '',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (widget.allowViewOnce) onceToggle(p),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                // Nama penerima di kiri, tombol kirim didorong ke ujung kanan (seperti WhatsApp).
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.person, size: 16, color: Colors.white70),
                        const SizedBox(width: 6),
                        Flexible(child: Text(widget.toName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: send,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.yellow, border: Border.all(color: Colors.white, width: 2)),
                          child: const Icon(Icons.send, color: ink, size: 24),
                        ),
                      ),
                      if (viewOnce)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: ink, width: 1.5)),
                            alignment: Alignment.center,
                            child: const Text('1', style: TextStyle(color: ink, fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Kotak "sekali lihat" di dalam gelembung chat (pengganti pratinjau foto/video).
class ViewOnceTile extends StatelessWidget {
  final Message m;
  final bool mine;
  final Color fg;
  final VoidCallback onTap;
  const ViewOnceTile({super.key, required this.m, required this.mine, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final isVideo = m.type == 'video';
    String sub;
    var strong = false;
    if (m.state == 'sending') {
      sub = 'Mengirim…';
    } else if (m.state == 'failed') {
      sub = 'Gagal dikirim';
    } else if (m.viewOnceState == 'expired') {
      sub = 'Kedaluwarsa';
    } else if (mine) {
      sub = m.viewOnceState == 'opened' ? (m.viewCount > 1 ? 'Dibuka oleh ${m.viewCount}' : 'Dibuka') : 'Belum dibuka';
    } else if (m.viewOnceState == 'opened') {
      sub = 'Dibuka';
    } else {
      sub = 'Ketuk untuk membuka';
      strong = true;
    }
    final ring = strong ? p.accentText : fg.withAlpha(150);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: const BoxConstraints(minWidth: 180),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withAlpha(20), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
            alignment: Alignment.center,
            child: Text('1', style: TextStyle(color: ring, fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isVideo ? Icons.videocam : Icons.photo_camera, size: 16, color: fg),
                const SizedBox(width: 4),
                Text(isVideo ? 'Video' : 'Foto', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
              Text(sub, style: TextStyle(color: strong ? p.accentText : p.muted, fontSize: 12.5, fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Membuka pesan sekali lihat: layar penuh, tanpa screenshot, tertutup otomatis bila aplikasi ke latar belakang.
/// Penerima hanya bisa membuka SATU kali; server mencatatnya begitu halaman ini meminta media.
Future<void> openViewOnce(BuildContext context, {required Message m, required bool group, required String from, VoidCallback? onOpened}) {
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    builder: (_) => ViewOnceViewerPage(
      messageId: m.id,
      event: group ? 'group:open_once' : 'message:open_once',
      kind: m.type == 'video' ? 'video' : 'image',
      from: from,
      onOpened: onOpened,
    ),
  ));
}

class ViewOnceViewerPage extends StatefulWidget {
  final int messageId;
  final String event; // 'message:open_once' | 'group:open_once'
  final String kind; // 'image' | 'video'
  final String from;
  final VoidCallback? onOpened;
  const ViewOnceViewerPage({super.key, required this.messageId, required this.event, required this.kind, required this.from, this.onOpened});
  @override
  State<ViewOnceViewerPage> createState() => _ViewOnceViewerPageState();
}

class _ViewOnceViewerPageState extends State<ViewOnceViewerPage> with WidgetsBindingObserver {
  bool loading = true;
  bool opened = false; // server sudah mencatat "dibuka": tidak bisa dibuka ulang, hanya boleh mencoba memuat ulang media
  String? error;
  String? url;
  String? caption;
  Uint8List? bytes;
  VideoPlayerController? vc;
  bool closing = false;

  bool get isVideo => widget.kind == 'video';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vc?.dispose();
    vc = null;
    bytes = null;
    unawaited(SecureScreen.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keluar dari aplikasi / buka bilah notifikasi / ganti aplikasi -> tutup agar isi tidak tertinggal di layar.
    if (state != AppLifecycleState.resumed) close();
  }

  void close() {
    if (closing || !mounted) return;
    closing = true;
    Navigator.of(context).maybePop();
  }

  Future<void> start() async {
    // 1) Perlindungan layar HARUS aktif lebih dulu. Bila gagal, pesan tidak dibuka (dan tidak dihitung "sudah dibuka").
    final secured = await SecureScreen.enable();
    if (!mounted) return;
    if (!secured) {
      setState(() {
        loading = false;
        error = 'Perlindungan layar tidak tersedia di perangkat ini, jadi pesan sekali lihat tidak dibuka.';
      });
      return;
    }
    // 2) Minta ke server: dicatat satu kali, server membalas alamat bertoken berumur pendek.
    try {
      final r = await app.emit(widget.event, {'id': widget.messageId});
      opened = true;
      widget.onOpened?.call();
      url = r['url']?.toString();
      final c = r['caption'];
      caption = c is String && c.trim().isNotEmpty ? c.trim() : null;
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = errText(e);
        });
      }
      return;
    }
    await loadMedia();
  }

  Future<void> loadMedia() async {
    final u = url;
    if (u == null || u.isEmpty) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Media tidak tersedia.';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      if (isVideo) {
        vc?.dispose();
        final c = VideoPlayerController.networkUrl(Uri.parse(app.api.abs(u)), httpHeaders: app.api.mediaHeaders);
        vc = c;
        await c.initialize();
        await c.setLooping(false);
        await c.play();
      } else if (bytes == null) {
        Object? last;
        for (var i = 0; i < 3 && bytes == null; i++) {
          try {
            bytes = Uint8List.fromList(await app.api.download(u));
          } catch (e) {
            last = e;
            await Future<void>.delayed(const Duration(milliseconds: 700));
            if (!mounted) return;
          }
        }
        if (bytes == null) throw last ?? Exception('gagal');
      }
      if (mounted) setState(() => loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Media tidak dapat dimuat. Periksa koneksi lalu coba lagi.';
        });
      }
    }
  }

  Widget videoView() {
    final c = vc;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(alignment: Alignment.center, children: [
          AspectRatio(aspectRatio: c.value.aspectRatio <= 0 ? 1 : c.value.aspectRatio, child: VideoPlayer(c)),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) => v.isPlaying
                ? const SizedBox.shrink()
                : Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                  ),
          ),
        ]),
        VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Color(0xFFFFDC35))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = error != null && bytes == null && (vc == null || !vc!.value.isInitialized);
    Widget body;
    if (failed) {
      body = Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(opened ? Icons.wifi_off : Icons.visibility_off_outlined, color: Colors.white70, size: 56),
          const SizedBox(height: 14),
          Text(error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 18),
          if (opened && url != null)
            FilledButton(onPressed: loadMedia, child: const Text('Coba lagi'))
          else
            TextButton(onPressed: close, child: const Text('Tutup', style: TextStyle(color: Colors.white))),
        ]),
      );
    } else if (loading) {
      body = const CircularProgressIndicator(color: Colors.white);
    } else if (isVideo) {
      body = videoView();
    } else if (bytes != null) {
      body = InteractiveViewer(minScale: 1, maxScale: 5, child: Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true));
    } else {
      body = const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        Center(child: body),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Color(0x00000000)])),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 16),
                child: Row(children: [
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), tooltip: 'Tutup', onPressed: close),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.from, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(isVideo ? 'Video sekali lihat' : 'Foto sekali lihat', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ]),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 2)),
                    alignment: Alignment.center,
                    child: const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (caption != null && !failed && !loading)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Color(0x00000000)])),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
                  child: Text(caption!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
