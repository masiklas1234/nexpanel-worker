// ZARR CHAT - tab Updates: status teks/foto/video.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'channels.dart';
import 'chats_tab.dart';
import 'models.dart';
import 'settings.dart' show PrivacyPage;
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

/// Cara menampilkan foto/video [media] di area [avail] tanpa gepeng:
///  - rasio hampir sama dengan area (selisih <= 8%) -> memenuhi area (cover), pemotongan paling banyak sekitar 8%;
///  - rasio berbeda jauh -> tampil UTUH di tengah (contain), tidak terpotong dan tidak melar.
/// Dipakai pratinjau kartu, halaman buat status, dan layar penonton status supaya hasilnya konsisten.
BoxFit statusFitFor(Size media, Size avail) {
  if (media.width <= 0 || media.height <= 0 || avail.width <= 0 || avail.height <= 0) return BoxFit.contain;
  final mr = media.width / media.height;
  final ar = avail.width / avail.height;
  final diff = (mr / ar - 1).abs();
  // Video/foto tegak (portrait) di layar HP tinggi: dibuat memenuhi layar seperti WhatsApp (pemotongan di sisi paling banyak ~23%).
  final tol = (mr < 1 && ar < 1) ? 0.30 : 0.08;
  return diff <= tol ? BoxFit.cover : BoxFit.contain;
}

/// Ukuran asli gambar [p] setelah dimuat. null bila gagal / terlalu lama.
Future<Size?> resolveImageSize(ImageProvider p, {Duration timeout = const Duration(seconds: 12)}) {
  final done = Completer<Size?>();
  final stream = p.resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  void finish(Size? v) {
    if (!done.isCompleted) done.complete(v);
    stream.removeListener(l);
  }

  l = ImageStreamListener(
    (info, _) => finish(Size(info.image.width.toDouble(), info.image.height.toDouble())),
    onError: (Object e, StackTrace? st) => finish(null),
  );
  stream.addListener(l);
  return done.future.timeout(timeout, onTimeout: () {
    stream.removeListener(l);
    return null;
  });
}

/// Pratinjau video memakai satu dekoder video per kartu. Jumlahnya dibatasi supaya HP kelas bawah tidak kehabisan dekoder
/// (penyebab video gagal dimuat / aplikasi tersendat bila banyak status video).
class _PreviewSlots {
  static const int max = 4;
  static int _used = 0;
  static bool tryAcquire() {
    if (_used >= max) return false;
    _used++;
    return true;
  }

  static void release() {
    if (_used > 0) _used--;
  }
}

/// Foto pratinjau di kartu Status: memenuhi kartu bila rasionya cocok, selain itu tampil utuh di atas latar buram foto yang sama.
class _StatusThumb extends StatefulWidget {
  final String url;
  const _StatusThumb({super.key, required this.url});
  @override
  State<_StatusThumb> createState() => _StatusThumbState();
}

class _StatusThumbState extends State<_StatusThumb> {
  static final Map<String, Size> _sizes = {};
  late ImageProvider provider;
  Size? size;

  ImageProvider _make() => ResizeImage(CachedNetworkImageProvider(widget.url, headers: app.api.mediaHeaders), width: 400);

  @override
  void initState() {
    super.initState();
    provider = _make();
    size = _sizes[widget.url];
    if (size == null) _loadSize();
  }

  @override
  void didUpdateWidget(covariant _StatusThumb old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      provider = _make();
      size = _sizes[widget.url];
      if (size == null) _loadSize();
    }
  }

  Future<void> _loadSize() async {
    final url = widget.url;
    final sz = await resolveImageSize(provider);
    if (sz == null) return;
    if (_sizes.length > 300) _sizes.clear();
    _sizes[url] = sz;
    if (mounted && widget.url == url) setState(() => size = sz);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final avail = Size(box.maxWidth, box.maxHeight);
      final sz = size;
      final fit = sz == null ? BoxFit.cover : statusFitFor(sz, avail);
      Widget img(BoxFit f) => Image(
            image: provider,
            fit: f,
            width: avail.width,
            height: avail.height,
            gaplessPlayback: true,
            errorBuilder: (c, e, st) => const SizedBox.shrink(),
          );
      return Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xFF1B1B1B)),
        if (fit == BoxFit.cover)
          img(BoxFit.cover)
        else ...[
          ClipRect(child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: img(BoxFit.cover))),
          const ColoredBox(color: Color(0x44000000)),
          img(BoxFit.contain),
        ],
      ]);
    });
  }
}

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});
  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  List<StatusGroup> feed = [];
  List<StatusItem> mine = [];
  List<Channel> following = [];
  List<Channel> suggested = [];
  bool loading = true;
  String? error;
  final Set<int> followBusy = {};
  StreamSubscription<SocketEvent>? sub;

  @override
  void initState() {
    super.initState();
    load();
    sub = app.events.listen((e) {
      if (e.name == 'status:viewed' || e.name == 'status:new' || e.name == 'status:deleted' || e.name == 'reconnected' || e.name == 'resumed' || e.name == 'tab:status') {
        loadStatus();
      }
      if (e.name == 'reconnected') loadChannels();
      if (e.name == 'channel:post' || e.name == 'channel:updated' || e.name == 'channel:deleted') loadChannels();
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    await Future.wait([loadStatus(), loadChannels()]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> loadStatus() async {
    try {
      final r = asMap(await app.api.get('/status'));
      feed = asList(r['feed']).map((g) {
        final m = asMap(g);
        return StatusGroup(
          user: User.fromJson(m['user']),
          statuses: asList(m['statuses']).map((s) => StatusItem.fromJson(s)).toList(),
          allViewed: m['allViewed'] == true,
        );
      }).toList();
      mine = asList(r['mine']).map((s) => StatusItem.fromJson(s)).toList();
      error = null;
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() {});
  }

  Future<void> loadChannels() async {
    try {
      final r = await loadChannelFeed();
      following = r.following;
      suggested = r.suggested;
    } catch (_) {
      // daftar saluran tetap memakai data terakhir
    }
    if (mounted) setState(() {});
  }

  Future<void> openViewer(List<StatusGroup> groups, int index, bool own) async {
    final r = await Navigator.of(context).push<String>(MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => StatusViewerPage(groups: groups, start: index, own: own),
    ));
    await loadStatus();
    if (r == 'add' && mounted) compose();
  }

  Future<void> compose() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => const StatusComposePage()));
    loadStatus(); // selalu muat ulang: sebagian status mungkin sudah terkirim
  }

  Future<void> explore() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExploreChannelsPage()));
    loadChannels();
  }

  Future<void> createChannel() async {
    await openCreateChannel(context);
    loadChannels();
  }

  Future<void> open(Channel c) async {
    await openChannel(context, c);
    loadChannels();
  }

  Future<void> follow(Channel c) async {
    setState(() => followBusy.add(c.id));
    final ok = await setFollow(c, true);
    if (ok != null) await loadChannels();
    if (mounted) setState(() => followBusy.remove(c.id));
  }

  void fabMenu() {
    showMenuSheet(context, [
      MenuItem(Icons.donut_large, 'Buat status', compose),
      MenuItem(Icons.campaign_outlined, 'Buat saluran', createChannel),
    ]);
  }

  /// Kartu status vertikal (latar foto / teks berwarna) dengan avatar di kiri atas dan nama di bawah.
  Widget statusCard({
    required User user,
    required String label,
    required StatusItem? latest,
    required Color ring,
    required VoidCallback onTap,
    bool addBadge = false,
    VoidCallback? onAdd,
  }) {
    final p = pal(context);
    Widget bg;
    if (latest != null && latest.type == 'image' && latest.mediaUrl != null) {
      // Kartu kecil (memori hemat: lebar 400 px). Rasio foto dihormati: tidak terpotong berlebihan, tidak melar.
      bg = _StatusThumb(key: ValueKey('thumb-${latest.id}'), url: app.api.abs(latest.mediaUrl));
    } else if (latest != null && latest.type == 'text') {
      bg = ColoredBox(color: hexColor(latest.bgColor, p.accent));
    } else if (latest != null && latest.type == 'video' && latest.mediaUrl != null) {
      bg = StatusVideoFrame(key: ValueKey('card-${latest.id}'), url: app.api.abs(latest.mediaUrl));
    } else {
      bg = const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF263042), Color(0xFF111111)])),
      );
    }
    // Badge + berada di dalam area Stack supaya mudah diketuk (menambah status baru kapan saja).
    final avatar = SizedBox(
      width: 56,
      height: 56,
      child: Stack(children: [
        Positioned(left: 0, top: 0, child: Avatar(user: user, size: 44, ring: ring)),
        if (addBadge)
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAdd,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF111111), width: 1.5)),
                child: const Icon(Icons.add, size: 20, color: Color(0xFF111111)),
              ),
            ),
          ),
      ]),
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(fit: StackFit.expand, children: [
            bg,
            if (latest != null && latest.type == 'text')
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 70, 10, 50),
                child: Center(
                  child: Text(latest.body ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            if (latest != null && latest.type == 'video') const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40)),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)], stops: [0.0, 0.55, 1.0]),
                ),
              ),
            ),
            Positioned(left: 10, top: 10, child: avatar),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget statusRow() {
    final p = pal(context);
    final me = app.me;
    final hasMe = me != null;
    return SizedBox(
      height: 226,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: (hasMe ? 1 : 0) + feed.length,
        itemBuilder: (_, idx) {
          if (hasMe && idx == 0) {
            return statusCard(
              user: me,
              label: 'Status saya',
              latest: mine.isEmpty ? null : mine.last,
              ring: mine.isEmpty ? p.yellow : p.accent,
              addBadge: true,
              onAdd: compose,
              onTap: () {
                if (mine.isEmpty) {
                  compose();
                } else {
                  openViewer([StatusGroup(user: me, statuses: mine, allViewed: true)], 0, true);
                }
              },
            );
          }
          final i = hasMe ? idx - 1 : idx;
          final g = feed[i];
          return statusCard(
            user: g.user,
            label: g.user.username,
            latest: g.statuses.last,
            ring: g.allViewed ? Colors.white54 : p.accent,
            onTap: () => openViewer(feed, i, false),
          );
        },
      ),
    );
  }

  Widget heading(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget exploreButton() {
    final p = pal(context);
    return Material(
      color: p.yellow,
      shape: StadiumBorder(side: BorderSide(color: p.line, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: explore,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          child: const Text('Jelajahi', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Color(0xFF111111))),
        ),
      ),
    );
  }

  Widget fab() {
    final p = pal(context);
    return GestureDetector(
      onTap: fabMenu,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: p.accent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line, width: 2.5),
          boxShadow: [BoxShadow(color: p.line, offset: const Offset(4, 4))],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 34),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null && feed.isEmpty && mine.isEmpty && following.isEmpty && suggested.isEmpty) {
      body = EmptyState(icon: Icons.error_outline, title: 'Gagal memuat pembaruan', text: error, action: NeoButton('Coba lagi', onPressed: load));
    } else {
      body = RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.only(top: 18, bottom: 100), children: [
          heading('Status'),
          statusRow(),
          const SizedBox(height: 26),
          heading('Saluran', trailing: exploreButton()),
          ...following.map((c) => ChannelTile(channel: c, showFollow: false, onTap: () => open(c))),
          if (suggested.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text('Temukan saluran untuk diikuti', style: TextStyle(color: p.muted, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...suggested.map((c) => ChannelTile(
                  channel: c,
                  showFollow: true,
                  busy: followBusy.contains(c.id),
                  onTap: () => open(c),
                  onFollow: () => follow(c),
                )),
          ],
          if (following.isEmpty && suggested.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Belum ada saluran. Buat saluran pertama Anda lewat tombol +.', style: TextStyle(color: p.muted, fontSize: 15)),
            ),
        ]),
      );
    }
    return Scaffold(
      appBar: zAppBar(context, text: 'Pembaruan', centerTitle: true, actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'status':
                compose();
                break;
              case 'channel':
                createChannel();
                break;
              case 'explore':
                explore();
                break;
              case 'privacy':
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPage()));
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'status', child: Text('Buat status')),
            PopupMenuItem(value: 'channel', child: Text('Buat saluran')),
            PopupMenuItem(value: 'explore', child: Text('Jelajahi saluran')),
            PopupMenuItem(value: 'privacy', child: Text('Privasi status')),
          ],
        ),
      ]),
      floatingActionButton: fab(),
      body: body,
    );
  }
}

/// Satu foto/video yang dipilih untuk dibagikan sebagai status.
class _Pick {
  final String path;
  final bool video;
  final TextEditingController caption = TextEditingController();
  _Pick(this.path, this.video);
}

bool _looksLikeVideo(String path, String? mime) {
  if (mime != null && mime.startsWith('video/')) return true;
  if (mime != null && mime.startsWith('image/')) return false;
  final l = path.toLowerCase();
  for (final e in const ['.mp4', '.mov', '.mkv', '.webm', '.3gp', '.avi', '.m4v']) {
    if (l.endsWith(e)) return true;
  }
  return false;
}

class StatusComposePage extends StatefulWidget {
  const StatusComposePage({super.key});
  @override
  State<StatusComposePage> createState() => _StatusComposePageState();
}

class _StatusComposePageState extends State<StatusComposePage> {
  static const List<String> colors = ['#FF3F5D', '#111111', '#1C8A3C', '#168BD0', '#7A3DF0', '#D9480F'];
  static const int maxItems = 20;
  String mode = 'text';
  String color = colors.first;
  String privacy = 'everyone'; // default: semua pengguna bisa melihat (ubah lewat pilihan privasi di bawah)
  final List<_Pick> items = [];
  final text = TextEditingController();
  final Set<int> audience = {};
  bool busy = false;
  int progress = 0;

  @override
  void dispose() {
    text.dispose();
    for (final it in items) {
      it.caption.dispose();
    }
    super.dispose();
  }

  Future<void> pick() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultipleMedia(maxWidth: 1920, maxHeight: 1920, imageQuality: 85);
      if (files.isEmpty) return;
      var skipped = 0;
      setState(() {
        for (final f in files) {
          if (items.length >= maxItems) {
            skipped++;
            continue;
          }
          if (items.any((e) => e.path == f.path)) continue;
          items.add(_Pick(f.path, _looksLikeVideo(f.path, f.mimeType)));
        }
      });
      if (skipped > 0) app.toast('Maksimal $maxItems foto/video sekali bagikan.', error: true);
    } catch (_) {
      app.toast('Tidak dapat membuka galeri.', error: true);
    }
  }

  void removeAt(int i) {
    setState(() {
      items.removeAt(i).caption.dispose();
    });
  }

  Future<void> post() async {
    if (busy) return;
    final aud = audience.toList();
    if (privacy == 'selected' && aud.isEmpty) {
      app.toast('Pilih minimal satu penerima status.', error: true);
      return;
    }
    if (mode == 'text' && text.text.trim().isEmpty) {
      app.toast('Ketik status terlebih dahulu.', error: true);
      return;
    }
    if (mode == 'media' && items.isEmpty) {
      app.toast('Pilih foto atau video terlebih dahulu.', error: true);
      return;
    }
    setState(() {
      busy = true;
      progress = 0;
    });
    try {
      if (mode == 'text') {
        await app.api.post('/status', {'type': 'text', 'privacy': privacy, 'audience': aud, 'body': text.text, 'bgColor': color});
      } else {
        final max = (app.cfg?.maxUploadMb ?? 2048) * 1048576;
        // Kirim satu per satu; yang sudah terkirim dihapus dari daftar sehingga bila gagal di tengah tidak terkirim dobel.
        while (items.isNotEmpty) {
          final it = items.first;
          final kind = it.video ? 'video' : 'image';
          if (await File(it.path).length() > max) throw ApiException('Ukuran file maksimal ${maxSizeText(app.cfg?.maxUploadMb ?? 2048)}.');
          final mediaId = await app.api.upload(it.path, kind);
          await app.api.post('/status', {'type': kind, 'privacy': privacy, 'audience': aud, 'mediaId': mediaId, 'body': it.caption.text});
          if (mounted) {
            setState(() {
              progress++;
              items.removeAt(0).caption.dispose();
            });
          }
        }
      }
      app.toast('Status dibagikan.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  Widget itemCard(int i) {
    final p = pal(context);
    final it = items[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line, width: 2)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: [
          SizedBox(
            height: 280,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              if (it.video)
                StatusVideoFrame(key: ValueKey(it.path), file: it.path, playable: true)
              else
                // Foto tampil UTUH (sama seperti saat dibuka penonton), bukan dipotong memenuhi kotak. cacheWidth menghemat memori bila memilih banyak foto.
                ColoredBox(color: Colors.black, child: Image.file(File(it.path), fit: BoxFit.contain, cacheWidth: 1000, errorBuilder: (c, e, st) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40)))),
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : () => removeAt(i),
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.close, color: Colors.white, size: 20)),
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: TextField(controller: it.caption, maxLength: 200, enabled: !busy, decoration: neoDeco(context, hint: 'Keterangan (opsional)')),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: zAppBar(context, text: 'Buat status'),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            for (final m in const [('text', 'Teks'), ('media', 'Foto / Video')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF111111))),
                  selected: mode == m.$1,
                  selectedColor: p.yellow,
                  onSelected: busy ? null : (_) => setState(() => mode = m.$1),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          if (mode == 'text') ...[
            Container(
              height: 260,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: hexColor(color, p.accent), borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line, width: 2)),
              alignment: Alignment.center,
              child: TextField(
                controller: text,
                maxLength: 700,
                maxLines: null,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: 'Ketik status…',
                  hintStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: colors
                  .map((c) => GestureDetector(
                        onTap: () => setState(() => color = c),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: hexColor(c, p.accent),
                            shape: BoxShape.circle,
                            border: Border.all(color: color == c ? p.yellow : p.line, width: color == c ? 4 : 2),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ] else ...[
            NeoButton(items.isEmpty ? 'Pilih foto / video' : 'Tambah foto / video', icon: Icons.add_photo_alternate_outlined, primary: false, onPressed: busy ? null : pick),
            const SizedBox(height: 4),
            Text('Bisa pilih banyak sekaligus (maks. $maxItems). Tiap foto/video menjadi satu status.', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++) itemCard(i),
          ],
          const SizedBox(height: 14),
          const Text('Siapa yang bisa melihat', style: TextStyle(fontWeight: FontWeight.w800)),
          DropdownButton<String>(
            value: privacy,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'contacts', child: Text('Kontak saya')),
              DropdownMenuItem(value: 'everyone', child: Text('Semua pengguna')),
              DropdownMenuItem(value: 'selected', child: Text('Hanya yang dipilih…')),
            ],
            onChanged: busy ? null : (v) => setState(() => privacy = v ?? 'contacts'),
          ),
          if (privacy == 'selected')
            ...app.chats.map((c) => CheckboxListTile(
                  value: audience.contains(c.peer.id),
                  title: Text(c.peer.username),
                  secondary: Avatar(user: c.peer, size: 36),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      audience.add(c.peer.id);
                    } else {
                      audience.remove(c.peer.id);
                    }
                  }),
                )),
          const SizedBox(height: 6),
          Text('Status hilang otomatis setelah masa berlaku. Anda bisa menghapusnya kapan saja.', style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 14),
          NeoButton(
            busy && mode == 'media' && items.isNotEmpty ? 'Mengirim ${progress + 1}…' : (mode == 'media' && items.length > 1 ? 'Bagikan ${items.length} status' : 'Bagikan status'),
            busy: busy,
            onPressed: post,
          ),
        ]),
      ),
    );
  }
}

/// Menampilkan frame pertama sebuah video (dari server atau file lokal) sebagai pratinjau/thumbnail.
class StatusVideoFrame extends StatefulWidget {
  final String? url;
  final String? file;
  final bool playable; // true: ketuk untuk putar/jeda (dipakai di halaman buat status)
  const StatusVideoFrame({super.key, this.url, this.file, this.playable = false});
  @override
  State<StatusVideoFrame> createState() => _StatusVideoFrameState();
}

class _StatusVideoFrameState extends State<StatusVideoFrame> {
  VideoPlayerController? c;
  bool ready = false;
  bool failed = false;
  bool _slot = false; // memegang satu slot dekoder
  bool _gone = false;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    init();
  }

  void _freeSlot() {
    if (_slot) {
      _slot = false;
      _PreviewSlots.release();
    }
  }

  Future<void> init() async {
    if (_gone) return;
    // Dekoder video terbatas: menunggu giliran (kartu yang keluar dari layar melepas slotnya).
    if (!_PreviewSlots.tryAcquire()) {
      _retry = Timer(const Duration(milliseconds: 800), init);
      return;
    }
    _slot = true;
    VideoPlayerController? v;
    try {
      final opts = VideoPlayerOptions(mixWithOthers: true);
      if (widget.file != null) {
        v = VideoPlayerController.file(File(widget.file!), videoPlayerOptions: opts);
      } else {
        v = VideoPlayerController.networkUrl(Uri.parse(widget.url ?? ''), httpHeaders: app.api.mediaHeaders, videoPlayerOptions: opts);
      }
      c = v;
      await v.initialize().timeout(const Duration(seconds: 30));
      if (_gone) return;
      await v.setVolume(widget.playable ? 1 : 0);
      await v.setLooping(widget.playable);
      if (!widget.playable) await v.seekTo(const Duration(milliseconds: 300));
      if (mounted) setState(() => ready = true);
    } catch (_) {
      // Gagal (format tidak didukung perangkat, jaringan, atau waktu habis): lepas dekoder, tampilkan kotak gelap, jangan crash.
      try {
        await v?.dispose();
      } catch (_) {}
      if (identical(c, v)) c = null;
      _freeSlot();
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    _gone = true;
    _retry?.cancel();
    c?.dispose();
    c = null;
    _freeSlot();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = c;
    if (!ready || v == null || failed) {
      return ColoredBox(
        color: const Color(0xFF1B1B1B),
        child: widget.playable ? Center(child: Icon(failed ? Icons.videocam_off : Icons.movie_outlined, color: Colors.white54, size: 40)) : null,
      );
    }
    final raw = v.value.size;
    final media = (raw.width <= 0 || raw.height <= 0) ? const Size(16, 9) : raw;
    Widget video(BoxFit f) => FittedBox(
          fit: f,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: media.width, height: media.height, child: VideoPlayer(v)),
        );
    final Widget frame = LayoutBuilder(builder: (context, box) {
      final avail = Size(box.maxWidth.isFinite ? box.maxWidth : media.width, box.maxHeight.isFinite ? box.maxHeight : media.height);
      if (statusFitFor(media, avail) == BoxFit.cover) return video(BoxFit.cover);
      // Rasio berbeda jauh: video tampil UTUH (tidak terpotong berlebihan, tidak melar). Sisa ruang: hitam (pemutar) / salinan buram (kartu).
      return Stack(fit: StackFit.expand, children: [
        if (widget.playable)
          const ColoredBox(color: Colors.black)
        else ...[
          ClipRect(child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: video(BoxFit.cover))),
          const ColoredBox(color: Color(0x44000000)),
        ],
        video(BoxFit.contain),
      ]);
    });
    if (!widget.playable) return frame;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (v.value.isPlaying) {
          v.pause();
        } else {
          v.play();
        }
        setState(() {});
      },
      child: Stack(fit: StackFit.expand, children: [
        frame,
        if (!v.value.isPlaying) const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 54)),
      ]),
    );
  }
}

/// Mengunduh video status ke folder sementara (cadangan bila pemutaran langsung dari jaringan gagal).
Future<File> _statusVideoFile(int id, String url) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/status_video_$id.mp4');
  if (f.existsSync() && f.lengthSync() > 0) return f;
  await app.api.downloadToFile(url, f.path);
  return f;
}

class StatusViewerPage extends StatefulWidget {
  final List<StatusGroup> groups;
  final int start;
  final bool own;
  const StatusViewerPage({super.key, required this.groups, required this.start, required this.own});
  @override
  State<StatusViewerPage> createState() => _StatusViewerPageState();
}

class _StatusViewerPageState extends State<StatusViewerPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  late int gi = widget.start;
  int si = 0;
  AnimationController? ac;
  VideoPlayerController? vc;
  int token = 0; // mencegah callback usang setelah pindah status
  final ValueNotifier<double> prog = ValueNotifier<double>(0); // kemajuan status yang sedang tampil (0..1)
  bool loadingMedia = false; // foto/video sedang dimuat: waktu belum berjalan
  bool failed = false; // foto/video gagal dimuat
  bool buffering = false; // video sedang menunggu data
  bool videoDone = false;
  Size? mediaSize; // ukuran asli foto/video yang sedang tampil (untuk menentukan penskalaan yang proporsional)
  final FocusNode focus = FocusNode();
  final TextEditingController replyCtrl = TextEditingController();
  bool sendingReply = false;
  bool paused = false; // true selama jari menahan layar / keyboard / menu terbuka
  bool holding = false; // true saat tahan lama: header & bilah bawah disembunyikan (seperti WhatsApp)
  DateTime? downAt;
  bool ignoreUp = false;
  Timer? holdTimer;

  StatusGroup get group => widget.groups[gi];
  StatusItem get cur => group.statuses[si];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Saat mengetik balasan, status berhenti sejenak; lanjut lagi setelah keyboard ditutup.
    focus.addListener(() {
      if (focus.hasFocus) {
        pauseAll();
      } else {
        resumeAll();
      }
      if (mounted) setState(() {});
    });
    final t0 = cur.type;
    loadingMedia = (t0 == 'image' || t0 == 'video') && cur.mediaUrl != null;
    // Dimulai setelah frame pertama: memuat foto butuh context yang sudah siap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) show();
    });
  }

  /// Aplikasi masuk latar belakang: video/waktu status berhenti (tidak terus bersuara); lanjut saat kembali dibuka.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!paused) pauseAll();
    } else if (state == AppLifecycleState.resumed) {
      if (paused && !focus.hasFocus && downAt == null && !failed && mounted) resumeAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    token++;
    holdTimer?.cancel();
    ac?.dispose();
    vc?.dispose();
    prog.dispose();
    focus.dispose();
    replyCtrl.dispose();
    super.dispose();
  }

  void pauseAll() {
    paused = true;
    ac?.stop();
    vc?.pause();
  }

  void resumeAll() {
    paused = false;
    final c = ac;
    if (c != null && c.status != AnimationStatus.completed) c.forward();
    final v = vc;
    if (v != null && v.value.isInitialized && !videoDone) v.play();
  }

  // Sentuh = jeda (progress & video berhenti). Lepas cepat = pindah status; tahan lama = lanjut saat dilepas.
  void zoneDown() {
    if (focus.hasFocus) {
      ignoreUp = true;
      return;
    }
    ignoreUp = false;
    downAt = DateTime.now();
    pauseAll();
    holdTimer?.cancel();
    holdTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && paused && downAt != null) setState(() => holding = true);
    });
  }

  void zoneUp(int d) {
    holdTimer?.cancel();
    if (ignoreUp) {
      ignoreUp = false;
      focus.unfocus();
      return;
    }
    final t = downAt;
    downAt = null;
    final longPress = t != null && DateTime.now().difference(t).inMilliseconds >= 250;
    if (holding) setState(() => holding = false);
    if (longPress) {
      resumeAll();
    } else {
      step(d);
    }
  }

  void zoneCancel() {
    holdTimer?.cancel();
    if (ignoreUp) return;
    downAt = null;
    if (holding) setState(() => holding = false);
    resumeAll();
  }

  Widget tapZone(int d) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => zoneDown(),
        onPointerUp: (_) => zoneUp(d),
        onPointerCancel: (_) => zoneCancel(),
        child: const SizedBox.expand(),
      );

  /// Potongan singkat isi status untuk keterangan balasan.
  String snippet() {
    final s = cur;
    final b = (s.body ?? '').trim().replaceAll('\n', ' ');
    if (b.isNotEmpty) return b.length > 40 ? '${b.substring(0, 40)}…' : b;
    return s.type == 'video' ? 'video' : (s.type == 'image' ? 'foto' : '');
  }

  /// Balasan/reaksi dikirim sebagai pesan chat biasa ke pemilik status.
  Future<void> sendToOwner(String body, {String? okMsg}) async {
    if (sendingReply) return;
    sendingReply = true;
    try {
      final r = asMap(await app.api.post('/chats', {'userId': group.user.id}));
      final cid = r['conversationId'];
      if (cid is! int) throw ApiException('Percakapan tidak ditemukan.');
      await app.emit('message:send', {'conversationId': cid, 'type': 'text', 'body': body, 'clientId': newClientId()});
      app.toast(okMsg ?? 'Balasan terkirim.');
      app.loadChats();
      replyCtrl.clear();
      focus.unfocus();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    sendingReply = false;
    if (mounted) setState(() {});
  }

  void sendReply() {
    final t = replyCtrl.text.trim();
    if (t.isEmpty) return;
    final sn = snippet();
    final tail = sn.isEmpty ? '' : ' ("$sn")';
    sendToOwner('Membalas status$tail\n$t');
  }

  void sendReaction(String emoji) {
    final sn = snippet();
    final tail = sn.isEmpty ? '' : ' ("$sn")';
    sendToOwner('$emoji Bereaksi pada status$tail', okMsg: 'Reaksi terkirim.');
  }

  void releaseCurrent() {
    token++;
    ac?.dispose();
    ac = null;
    vc?.dispose();
    vc = null;
    videoDone = false;
    buffering = false;
  }

  void startTimer(Duration d) {
    final t = token;
    final c = AnimationController(vsync: this, duration: d);
    ac = c;
    c.addListener(() {
      if (t == token) prog.value = c.value;
    });
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        Future<void>.microtask(() {
          if (t == token && mounted) step(1);
        });
      }
    });
    if (paused) {
      // jari sedang menahan layar saat status dimuat: tunggu sampai dilepas
      setState(() {});
      return;
    }
    c.forward();
    setState(() {});
  }

  /// Memuat status yang sedang tampil. Waktu (garis kemajuan) baru berjalan SETELAH foto selesai dimuat / video siap diputar,
  /// jadi koneksi lambat tidak membuat status habis dan tertutup sebelum sempat terlihat.
  Future<void> show() async {
    releaseCurrent();
    final t = token;
    final s = cur;
    failed = false;
    mediaSize = null;
    prog.value = 0;
    if (!widget.own) {
      s.viewed = true;
      app.api.post('/status/${s.id}/view').catchError((Object _) => null);
    }
    final url = s.mediaUrl;
    if (s.type == 'video' && url != null) {
      loadingMedia = true;
      if (mounted) setState(() {});
      try {
        VideoPlayerController v = VideoPlayerController.networkUrl(Uri.parse(app.api.abs(url)), httpHeaders: app.api.mediaHeaders);
        vc = v;
        try {
          await v.initialize().timeout(const Duration(seconds: 30));
        } catch (_) {
          // Streaming gagal (jaringan putus-putus / server tidak mendukung potongan): unduh dulu ke penyimpanan sementara, lalu putar dari file.
          if (t != token || !mounted) return;
          try {
            await v.dispose();
          } catch (_) {}
          if (identical(vc, v)) vc = null;
          final f = await _statusVideoFile(s.id, url);
          if (t != token || !mounted) return;
          v = VideoPlayerController.file(f);
          vc = v;
          try {
            await v.initialize().timeout(const Duration(seconds: 20));
          } catch (_) {
            // Berkas sementara lama bisa rusak / versi sebelum server merapikan video: hapus lalu unduh ulang satu kali.
            if (t != token || !mounted) return;
            try {
              await v.dispose();
            } catch (_) {}
            if (identical(vc, v)) vc = null;
            try {
              f.deleteSync();
            } catch (_) {}
            final f2 = await _statusVideoFile(s.id, url);
            if (t != token || !mounted) return;
            v = VideoPlayerController.file(f2);
            vc = v;
            await v.initialize().timeout(const Duration(seconds: 20));
          }
        }
        if (t != token || !mounted) return;
        v.addListener(() => onVideoTick(t, v));
        mediaSize = v.value.size;
        loadingMedia = false;
        if (!paused) await v.play();
        if (t != token || !mounted) return;
        setState(() {});
      } catch (_) {
        if (t == token && mounted) {
          loadingMedia = false;
          failed = true;
          setState(() {});
        }
      }
    } else if (s.type == 'image' && url != null) {
      loadingMedia = true;
      if (mounted) setState(() {});
      var err = false;
      Size? imgSize;
      // Dicoba sampai 2 kali: jaringan HP yang putus-putus sering gagal sesaat lalu normal lagi.
      for (var attempt = 0; attempt < 2; attempt++) {
        err = false;
        imgSize = null;
        try {
          final provider = CachedNetworkImageProvider(app.api.abs(url), headers: app.api.mediaHeaders);
          await precacheImage(
            provider,
            context,
            onError: (Object e, StackTrace? st) => err = true,
          ).timeout(const Duration(seconds: 45));
          if (!err) imgSize = await resolveImageSize(provider, timeout: const Duration(seconds: 5)); // sudah di cache: cepat
        } catch (_) {
          err = true;
        }
        if (!err) break;
        if (t != token || !mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (t != token || !mounted) return;
      }
      if (t != token || !mounted) return;
      loadingMedia = false;
      mediaSize = imgSize;
      if (err) {
        failed = true;
        setState(() {});
      } else {
        startTimer(const Duration(seconds: 6));
      }
    } else {
      loadingMedia = false;
      startTimer(const Duration(seconds: 6));
    }
  }

  /// Kemajuan video mengikuti posisi putar sebenarnya (bukan timer terpisah), jadi video yang tersendat tidak terpotong.
  void onVideoTick(int t, VideoPlayerController v) {
    if (t != token || !mounted) return;
    final val = v.value;
    if (val.hasError) {
      if (!failed) {
        failed = true;
        setState(() {});
      }
      return;
    }
    final dur = val.duration.inMilliseconds;
    final pos = val.position.inMilliseconds;
    if (dur > 0) prog.value = (pos / dur).clamp(0.0, 1.0);
    if (val.isBuffering != buffering) {
      buffering = val.isBuffering;
      setState(() {});
    }
    if (!videoDone && dur > 0 && pos >= dur - 250) {
      videoDone = true;
      // Ditunda sampai pemberitahuan listener selesai: controller lama dibuang saat pindah status.
      Future<void>.microtask(() {
        if (t == token && mounted) step(1);
      });
    }
  }

  void step(int d) {
    var ng = gi;
    var ns = si + d;
    if (ns < 0) {
      if (ng > 0) {
        ng--;
        ns = widget.groups[ng].statuses.length - 1;
      } else {
        ns = 0;
      }
    } else if (ns >= widget.groups[ng].statuses.length) {
      if (ng < widget.groups.length - 1) {
        ng++;
        ns = 0;
      } else {
        releaseCurrent();
        Navigator.pop(context);
        return;
      }
    }
    paused = false;
    holding = false;
    setState(() {
      gi = ng;
      si = ns;
    });
    show();
  }

  Future<void> viewers() async {
    pauseAll();
    try {
      final r = asMap(await app.api.get('/status/${cur.id}/viewers'));
      final list = asList(r['viewers']);
      cur.viewCount = list.length;
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: list.isEmpty
              ? const SizedBox(height: 160, child: Center(child: Text('Belum ada yang melihat.')))
              : ListView(
                  shrinkWrap: true,
                  children: list.map((v) {
                    final m = asMap(v);
                    final u = User.fromJson(m);
                    return ListTile(
                      leading: Avatar(user: u, size: 40),
                      title: NameWithBadge(u),
                      subtitle: Text(dateTimeText(parseDate(m['viewedAt']))),
                    );
                  }).toList(),
                ),
        ),
      );
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    resumeAll();
    if (mounted) setState(() {});
  }

  Future<void> remove() async {
    pauseAll();
    final ok = await showConfirm(context, 'Hapus status?', 'Status ini akan dihapus untuk semua orang.', 'Hapus', danger: true);
    if (!ok) {
      resumeAll();
      return;
    }
    try {
      await app.api.delete('/status/${cur.id}');
      app.toast('Status dihapus.');
      group.statuses.removeAt(si);
      if (group.statuses.isEmpty) {
        releaseCurrent();
        if (mounted) Navigator.pop(context);
        return;
      }
      if (si >= group.statuses.length) si = group.statuses.length - 1;
      paused = false;
      show();
    } catch (e) {
      app.toast(errText(e), error: true);
      resumeAll();
    }
  }

  /// Isi status saja (teks, foto, atau video). Caption ditampilkan terpisah di bawahnya (lihat build).
  Widget stage() {
    final s = cur;
    if (s.type == 'text') {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Text(s.body ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
        ),
      );
    }
    if (failed) {
      return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 72));
    }
    if (s.type == 'image') {
      if (loadingMedia) return const Center(child: CircularProgressIndicator(color: Colors.white));
      // Area penuh (batas ketat) agar foto diskalakan sebesar mungkin, tetapi tidak dipotong berlebihan dan tidak melar:
      // rasio hampir sama dengan layar -> memenuhi layar; selain itu tampil utuh di tengah (lihat statusFitFor).
      return LayoutBuilder(builder: (context, box) {
        final avail = Size(box.maxWidth, box.maxHeight);
        final ms = mediaSize;
        final fit = ms == null ? BoxFit.contain : statusFitFor(ms, avail);
        return SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: app.api.abs(s.mediaUrl),
            httpHeaders: app.api.mediaHeaders,
            fit: fit,
            placeholder: (c, u) => const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorWidget: (c, u, e) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 72)),
          ),
        );
      });
    }
    final v = vc;
    if (v != null && v.value.isInitialized && !loadingMedia) {
      // Ukuran video dibaca dari pemutar (sudah memperhitungkan rotasi). Penskalaan sama dengan foto; tidak pernah gepeng.
      final raw = v.value.size;
      final media = (raw.width <= 0 || raw.height <= 0) ? const Size(9, 16) : raw;
      return Stack(alignment: Alignment.center, children: [
        LayoutBuilder(builder: (context, box) {
          final avail = Size(box.maxWidth, box.maxHeight);
          return ClipRect(
            child: SizedBox.fromSize(
              size: avail,
              child: FittedBox(
                fit: statusFitFor(media, avail),
                alignment: Alignment.center,
                child: SizedBox(width: media.width, height: media.height, child: VideoPlayer(v)),
              ),
            ),
          );
        }),
        if (buffering) const CircularProgressIndicator(color: Colors.white),
      ]);
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }

  Widget replyBar() {
    final hasText = replyCtrl.text.trim().isNotEmpty;
    const fieldBg = Color(0xCC1E1E1E);
    Widget emo(String e) => InkWell(
          onTap: () => sendReaction(e),
          borderRadius: BorderRadius.circular(20),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Text(e, style: const TextStyle(fontSize: 24))),
        );
    return Row(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white24)),
          padding: const EdgeInsets.only(left: 18, right: 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: replyCtrl,
                focusNode: focus,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: Colors.white,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Balas',
                  hintStyle: TextStyle(color: Colors.white70, fontSize: 16),
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (hasText)
              IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: sendReply)
            else ...[emo('😍'), emo('😂'), emo('😮')],
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Material(
        color: fieldBg,
        shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => sendReaction('❤️'),
          child: const Padding(padding: EdgeInsets.all(14), child: Icon(Icons.favorite_border, color: Colors.white)),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final g = group;
    final s = cur;
    final isText = s.type == 'text';
    final caption = isText ? '' : (s.body ?? '').trim();
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final safeBottom = kb > 0 ? 0.0 : mq.padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false, // foto tetap di tempat saat keyboard muncul
      body: Stack(children: [
        // 1) Latar + isi status memenuhi layar (seperti WhatsApp)
        Positioned.fill(child: ColoredBox(color: isText ? hexColor(s.bgColor, pal(context).accent) : Colors.black)),
        Positioned.fill(child: SafeArea(bottom: false, child: IgnorePointer(child: stage()))),
        // 2) Area sentuh: kiri = sebelumnya, kanan = berikutnya; tahan = status berhenti (seperti WhatsApp)
        Positioned.fill(
          child: Row(children: [
            Expanded(child: tapZone(-1)),
            Expanded(flex: 2, child: tapZone(1)),
          ]),
        ),
        // Foto/video gagal dimuat: tombol coba lagi (ketuk kanan/kiri tetap bisa untuk lanjut)
        if (failed)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 150),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Status tidak dapat dimuat', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ElevatedButton.icon(onPressed: show, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
              ]),
            ),
          ),
        // 3) Header: garis kemajuan, panah kembali, avatar, nama, waktu, menu
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: holding ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)]),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: List.generate(g.statuses.length, (i) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: i == si
                              ? ValueListenableBuilder<double>(
                                  valueListenable: prog,
                                  builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 3, color: Colors.white, backgroundColor: Colors.white30),
                                )
                              : LinearProgressIndicator(value: i < si ? 1 : 0, minHeight: 3, color: Colors.white, backgroundColor: Colors.white30),
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
                  child: Row(children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        releaseCurrent();
                        Navigator.pop(context);
                      },
                    ),
                    Avatar(user: g.user, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        DefaultTextStyle(
                          style: const TextStyle(color: Colors.white),
                          child: NameWithBadge(g.user, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        Text('${dayLabel(s.createdAt)}, ${fmtTime(s.createdAt)}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onOpened: pauseAll,
                      onCanceled: resumeAll,
                      onSelected: (v) {
                        if (v == 'viewers') {
                          viewers();
                        } else if (v == 'add') {
                          releaseCurrent();
                          Navigator.pop(context, 'add');
                        } else if (v == 'delete') {
                          remove();
                        } else if (v == 'chat') {
                          final uid = g.user.id;
                          releaseCurrent();
                          Navigator.pop(context);
                          openChatWithUser(context, uid);
                        }
                      },
                      itemBuilder: (_) => widget.own
                          ? [
                              PopupMenuItem(value: 'viewers', child: Text('Penonton (${s.viewCount})')),
                              const PopupMenuItem(value: 'add', child: Text('Tambah status')),
                              const PopupMenuItem(value: 'delete', child: Text('Hapus status')),
                            ]
                          : [const PopupMenuItem(value: 'chat', child: Text('Kirim pesan'))],
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          ),
        ),
        // 4) Bawah: caption di atas bilah Balas (atau jumlah penonton untuk status sendiri)
        Positioned(
          left: 0,
          right: 0,
          bottom: kb,
          child: AnimatedOpacity(
            opacity: holding ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)]),
            ),
            padding: EdgeInsets.fromLTRB(12, caption.isEmpty ? 8 : 24, 12, 10 + safeBottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
                  child: IgnorePointer(
                    child: Text(
                      caption,
                      textAlign: TextAlign.center,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.3, shadows: [Shadow(color: Colors.black87, blurRadius: 6)]),
                    ),
                  ),
                ),
              if (widget.own)
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton.icon(
                    onPressed: viewers,
                    icon: const Icon(Icons.visibility, color: Colors.white),
                    label: Text('${s.viewCount}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      releaseCurrent();
                      Navigator.pop(context, 'add');
                    },
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                    label: const Text('Tambah status', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ])
              else
                replyBar(),
            ]),
          ),
          ),
        ),
      ]),
    );
  }
}
