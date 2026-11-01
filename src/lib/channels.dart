// ZARR CHAT - Saluran (channel) satu arah seperti WhatsApp Channels:
// daftar, jelajahi, buat/ubah saluran, halaman saluran, info saluran.
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'avatar_cropper.dart';
import 'media.dart';
import 'chat_screen.dart' show StickerPanel;
import 'models.dart';
import 'state.dart';
import 'stickers.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

// ====================================================================== model
int _ci(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

bool _cb(dynamic v) => v == true || v == 1 || v == '1';

class ChannelPost {
  final int id;
  final int channelId;
  final String type;
  final String? body;
  final int? mediaId;
  final String? mediaUrl;
  final DateTime createdAt;
  int views;
  Map<String, int> reactions;
  String? myReaction;
  ChannelPost({
    required this.id,
    required this.channelId,
    required this.type,
    this.body,
    this.mediaId,
    this.mediaUrl,
    required this.createdAt,
    this.views = 0,
    Map<String, int>? reactions,
    this.myReaction,
  }) : reactions = reactions ?? <String, int>{};

  factory ChannelPost.fromJson(dynamic raw) {
    final j = asMap(raw);
    final rx = <String, int>{};
    asMap(j['reactions']).forEach((k, v) => rx[k] = _ci(v));
    return ChannelPost(
      id: _ci(j['id']),
      channelId: _ci(j['channelId']),
      type: (j['type'] ?? 'text').toString(),
      body: j['body'] as String?,
      mediaId: j['mediaId'] == null ? null : _ci(j['mediaId']),
      mediaUrl: j['mediaUrl'] as String?,
      createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
      views: _ci(j['views']),
      reactions: rx,
      myReaction: j['myReaction'] as String?,
    );
  }

  String get preview {
    final b = (body ?? '').trim();
    switch (type) {
      case 'image':
        return b.isEmpty ? 'Foto' : 'Foto · $b';
      case 'video':
        return b.isEmpty ? 'Video' : 'Video · $b';
      case 'sticker':
        return 'Sticker';
      default:
        return b;
    }
  }
}

class Channel {
  final int id;
  String name;
  String description;
  final int ownerId;
  String? avatarUrl;
  bool isVerified;
  String ringStyle; // Ring Avatar milik saluran ini (diatur pemilik/admin)
  int followerCount;
  bool isFollowing;
  bool isOwner;
  bool isAdmin; // saya admin (bukan pemilik)
  bool canPost; // pemilik atau admin: boleh kirim pesan/sticker
  int adminCount; // termasuk pemilik
  bool muted;
  int unread;
  final DateTime createdAt;
  ChannelPost? lastPost;
  Channel({
    required this.id,
    required this.name,
    this.description = '',
    required this.ownerId,
    this.avatarUrl,
    this.isVerified = false,
    this.ringStyle = 'comic',
    this.followerCount = 0,
    this.isFollowing = false,
    this.isOwner = false,
    this.isAdmin = false,
    this.canPost = false,
    this.adminCount = 1,
    this.muted = false,
    this.unread = 0,
    required this.createdAt,
    this.lastPost,
  });

  factory Channel.fromJson(dynamic raw) {
    final j = asMap(raw);
    final lp = j['lastPost'];
    return Channel(
      id: _ci(j['id']),
      name: (j['name'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      ownerId: _ci(j['ownerId']),
      avatarUrl: j['avatarUrl'] as String?,
      isVerified: _cb(j['isVerified']),
      ringStyle: (j['ringStyle'] ?? 'comic').toString(),
      followerCount: _ci(j['followerCount']),
      isFollowing: _cb(j['isFollowing']),
      isOwner: _cb(j['isOwner']),
      isAdmin: _cb(j['isAdmin']),
      canPost: _cb(j['canPost']) || _cb(j['isOwner']),
      adminCount: j['adminCount'] == null ? 1 : _ci(j['adminCount']),
      muted: _cb(j['muted']),
      unread: _ci(j['unread']),
      createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
      lastPost: lp == null ? null : ChannelPost.fromJson({...asMap(lp), 'channelId': j['id']}),
    );
  }

  void copyFrom(Channel o) {
    name = o.name;
    description = o.description;
    avatarUrl = o.avatarUrl;
    isVerified = o.isVerified;
    ringStyle = o.ringStyle;
    followerCount = o.followerCount;
    isFollowing = o.isFollowing;
    isOwner = o.isOwner;
    isAdmin = o.isAdmin;
    canPost = o.canPost;
    adminCount = o.adminCount;
    muted = o.muted;
    unread = o.unread;
    lastPost = o.lastPost ?? lastPost;
  }
}

String followersText(int n) => '${_ribuan(n)} pengikut';

String _ribuan(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Memuat daftar saluran yang diikuti dan saran saluran.
Future<({List<Channel> following, List<Channel> suggested})> loadChannelFeed() async {
  final r = asMap(await app.api.get('/channels'));
  return (
    following: asList(r['following']).map((c) => Channel.fromJson(c)).toList(),
    suggested: asList(r['suggested']).map((c) => Channel.fromJson(c)).toList(),
  );
}

// ====================================================================== komponen
/// Foto saluran bulat; tanpa foto tampil ikon pengumuman berwarna merah muda.
class ChannelAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final String ringStyle; // Ring Avatar milik saluran (bukan ring profil)
  const ChannelAvatar({super.key, this.url, this.size = 62, this.ringStyle = 'comic'});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final u = url;
    return RingFrame(
      box: size,
      plain: size,
      styleOverride: ringStyle,
      photo: (d) {
        final fallback = Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          color: p.accent.withAlpha(55),
          child: Icon(Icons.campaign, size: d * 0.5, color: p.accent),
        );
        if (u == null || u.isEmpty) return fallback;
        return CachedNetworkImage(
          imageUrl: app.api.abs(u),
          httpHeaders: app.api.mediaHeaders,
          width: d,
          height: d,
          fit: BoxFit.cover,
          placeholder: (c, s) => fallback,
          errorWidget: (c, s, e) => fallback,
        );
      },
    );
  }
}

/// Tombol kapsul "Ikuti" (merah muda) / "Mengikuti".
class FollowPill extends StatelessWidget {
  final bool following;
  final bool busy;
  final VoidCallback? onTap;
  const FollowPill({super.key, required this.following, this.busy = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    // Solid + tepi tinta supaya jelas di atas wallpaper / background foto.
    final bg = following ? p.surface : p.accent;
    final fg = following ? p.text : Colors.white;
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: p.line, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy || following ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 78, minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: busy
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
              : Text(following ? 'Mengikuti' : 'Ikuti', style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 13.5)),
        ),
      ),
    );
  }
}

/// Satu baris saluran. [showFollow] true = saran saluran (tombol Ikuti); false = saluran yang diikuti.
class ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool showFollow;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onFollow;
  const ChannelTile({super.key, required this.channel, required this.showFollow, required this.onTap, this.onFollow, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final c = channel;
    final lp = c.lastPost;
    final Widget trailing;
    final String subtitle;
    if (showFollow) {
      subtitle = followersText(c.followerCount);
      trailing = FollowPill(following: c.isFollowing, busy: busy, onTap: onFollow);
    } else {
      subtitle = lp != null && lp.preview.isNotEmpty ? lp.preview : followersText(c.followerCount);
      trailing = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (lp != null) Text(listTime(lp.createdAt), style: TextStyle(fontSize: 11.5, color: c.unread > 0 ? p.accentText : p.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (c.muted) Icon(Icons.volume_off, size: 16, color: p.muted),
          if (c.unread > 0)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(12)),
              child: Text(c.unread > 99 ? '99+' : '${c.unread}', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
        ]),
      ]);
    }
    return NeoCard(
      onTap: onTap,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 9),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(children: [
          ChannelAvatar(url: c.avatarUrl, size: 46, ringStyle: c.ringStyle),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                if (c.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedBadge()),
              ]),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 10),
          trailing,
        ]),
    );
  }
}

/// Mengikuti / berhenti mengikuti saluran. Mengembalikan saluran terbaru atau null bila gagal.
Future<Channel?> setFollow(Channel c, bool follow) async {
  try {
    final r = asMap(follow ? await app.api.post('/channels/${c.id}/follow') : await app.api.delete('/channels/${c.id}/follow'));
    final fresh = Channel.fromJson(r['channel']);
    c.copyFrom(fresh);
    return c;
  } catch (e) {
    app.toast(errText(e), error: true);
    return null;
  }
}

Future<void> openChannel(BuildContext context, Channel c) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelPage(channel: c)));

Future<void> openCreateChannel(BuildContext context) async {
  final created = await Navigator.of(context).push<Channel>(MaterialPageRoute<Channel>(builder: (_) => const ChannelFormPage()));
  if (created != null && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelPage(channel: created)));
  }
}

// ====================================================================== jelajahi
class ExploreChannelsPage extends StatefulWidget {
  const ExploreChannelsPage({super.key});
  @override
  State<ExploreChannelsPage> createState() => _ExploreChannelsPageState();
}

class _ExploreChannelsPageState extends State<ExploreChannelsPage> {
  final TextEditingController search = TextEditingController();
  List<Channel> items = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  String? error;
  Timer? debounce;
  final Set<int> busy = {};
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final seq = ++_seq;
    if (more) {
      setState(() => loadingMore = true);
    } else {
      setState(() => loading = items.isEmpty);
    }
    try {
      final offset = more ? items.length : 0;
      final r = asMap(await app.api.get('/channels/explore?q=${Uri.encodeQueryComponent(search.text.trim())}&offset=$offset'));
      if (seq != _seq || !mounted) return;
      final got = asList(r['channels']).map((c) => Channel.fromJson(c)).toList();
      setState(() {
        items = more ? [...items, ...got] : got;
        hasMore = r['hasMore'] == true;
        error = null;
        loading = false;
        loadingMore = false;
      });
    } catch (e) {
      if (seq != _seq || !mounted) return;
      setState(() {
        error = errText(e);
        loading = false;
        loadingMore = false;
      });
    }
  }

  void onSearch(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () => load());
  }

  Future<void> follow(Channel c) async {
    setState(() => busy.add(c.id));
    await setFollow(c, true);
    if (mounted) setState(() => busy.remove(c.id));
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null && items.isEmpty) {
      body = EmptyState(icon: Icons.error_outline, title: 'Gagal memuat saluran', text: error, action: NeoButton('Coba lagi', onPressed: () => load()));
    } else if (items.isEmpty) {
      body = EmptyState(
        icon: Icons.campaign_outlined,
        title: search.text.trim().isEmpty ? 'Belum ada saluran' : 'Saluran tidak ditemukan',
        text: search.text.trim().isEmpty ? 'Jadilah yang pertama membuat saluran.' : 'Coba kata kunci lain.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => load(),
        child: ListView(children: [
          ...items.map((c) => ChannelTile(
                channel: c,
                showFollow: true,
                busy: busy.contains(c.id),
                onTap: () async {
                  await openChannel(context, c);
                  if (mounted) setState(() {});
                },
                onFollow: () => follow(c),
              )),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: loadingMore ? const CircularProgressIndicator() : TextButton(onPressed: () => load(more: true), child: const Text('Muat lebih banyak'))),
            ),
          const SizedBox(height: 24),
        ]),
      );
    }
    return Scaffold(
      appBar: zAppBar(context, text: 'Jelajahi saluran'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: search,
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            decoration: neoDeco(context, hint: 'Cari saluran', prefix: Icon(Icons.search, color: p.muted)),
          ),
        ),
        ListTile(
          leading: CircleAvatar(radius: 24, backgroundColor: p.accent, child: const Icon(Icons.add, color: Colors.white)),
          title: const Text('Buat saluran baru', style: TextStyle(fontWeight: FontWeight.w800)),
          onTap: () => openCreateChannel(context),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

// ====================================================================== buat / ubah saluran
class ChannelFormPage extends StatefulWidget {
  final Channel? edit;
  const ChannelFormPage({super.key, this.edit});
  @override
  State<ChannelFormPage> createState() => _ChannelFormPageState();
}

class _ChannelFormPageState extends State<ChannelFormPage> {
  late final TextEditingController name = TextEditingController(text: widget.edit?.name ?? '');
  late final TextEditingController desc = TextEditingController(text: widget.edit?.description ?? '');
  String? photoPath; // foto baru yang dipilih
  bool removePhoto = false;
  bool busy = false;

  bool get editing => widget.edit != null;

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    final path = await pickAndCropAvatar(context, title: 'Atur foto saluran');
    if (path != null && mounted) {
      setState(() {
        photoPath = path;
        removePhoto = false;
      });
    }
  }

  Future<void> save() async {
    final n = name.text.trim();
    if (n.length < 2) {
      app.toast('Nama saluran minimal 2 karakter.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final body = <String, dynamic>{'name': n, 'description': desc.text.trim()};
      if (photoPath != null) {
        body['avatarMediaId'] = await app.api.upload(photoPath!, 'avatar');
      } else if (removePhoto) {
        body['avatarMediaId'] = null;
      }
      final r = asMap(editing ? await app.api.patch('/channels/${widget.edit!.id}', body) : await app.api.post('/channels', body));
      final ch = Channel.fromJson(r['channel']);
      if (editing) {
        widget.edit!.copyFrom(ch);
        app.toast('Saluran diperbarui.');
        if (mounted) Navigator.pop(context, widget.edit);
      } else {
        app.toast('Saluran dibuat.');
        if (mounted) Navigator.pop(context, ch);
      }
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final existing = removePhoto ? null : widget.edit?.avatarUrl;
    final Widget avatar = photoPath != null
        ? ClipOval(child: Image.file(File(photoPath!), width: 120, height: 120, fit: BoxFit.cover))
        : ChannelAvatar(url: existing, size: 120, ringStyle: widget.edit?.ringStyle ?? 'comic');
    return Scaffold(
      appBar: zAppBar(context, text: editing ? 'Ubah saluran' : 'Buat saluran'),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Center(
          child: GestureDetector(
            onTap: pickPhoto,
            child: Stack(children: [
              avatar,
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: p.yellow, shape: BoxShape.circle, border: Border.all(color: p.line, width: 2)),
                  child: const Icon(Icons.camera_alt, size: 20, color: Color(0xFF111111)),
                ),
              ),
            ]),
          ),
        ),
        if (photoPath != null || (existing != null && existing.isNotEmpty))
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                photoPath = null;
                removePhoto = true;
              }),
              child: const Text('Hapus foto'),
            ),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: name,
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          decoration: neoDeco(context, label: 'Nama saluran'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: desc,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: neoDeco(context, label: 'Deskripsi (opsional)'),
        ),
        const SizedBox(height: 6),
        Text(
          'Saluran bersifat publik: siapa pun dapat menemukan dan mengikutinya. Hanya Anda yang dapat mengirim pesan; pengikut dapat membaca dan memberi reaksi.',
          style: TextStyle(color: p.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 18),
        NeoButton(editing ? 'Simpan' : 'Buat saluran', busy: busy, onPressed: save),
      ]),
    );
  }
}

// ====================================================================== info saluran
class ChannelInfoPage extends StatefulWidget {
  final Channel channel;
  const ChannelInfoPage({super.key, required this.channel});
  @override
  State<ChannelInfoPage> createState() => _ChannelInfoPageState();
}

class _ChannelInfoPageState extends State<ChannelInfoPage> {
  Channel get c => widget.channel;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = asMap(await app.api.get('/channels/${c.id}'));
      c.copyFrom(Channel.fromJson(r['channel']));
      if (mounted) setState(() {});
    } catch (_) {
      // pakai data yang sudah ada
    }
  }

  Future<void> toggleFollow() async {
    setState(() => busy = true);
    await setFollow(c, !c.isFollowing);
    if (mounted) setState(() => busy = false);
  }

  Future<void> toggleMute(bool muted) async {
    try {
      final r = asMap(await app.api.patch('/channels/${c.id}/mute', {'muted': muted}));
      c.copyFrom(Channel.fromJson(r['channel']));
      if (mounted) setState(() {});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> edit() async {
    await Navigator.of(context).push<Channel>(MaterialPageRoute<Channel>(builder: (_) => ChannelFormPage(edit: c)));
    if (mounted) setState(() {});
  }

  Future<void> openRing() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RingPickerPage(
        title: 'Ring Avatar saluran',
        note: 'Ring ini hanya untuk saluran ini dan terlihat oleh semua pengikut. Ring profil dan grup tidak ikut berubah.',
        initial: c.ringStyle,
        preview: (size, style) => ChannelAvatar(url: c.avatarUrl, size: size, ringStyle: style),
        onSave: (id) async {
          final r = asMap(await app.api.patch('/channels/${c.id}', {'ringStyle': id}));
          c.copyFrom(Channel.fromJson(r['channel']));
        },
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> delete() async {
    final ok = await showConfirm(context, 'Hapus saluran?', 'Saluran "${c.name}" beserta semua pesannya akan dihapus permanen untuk semua pengikut.', 'Hapus', danger: true);
    if (!ok) return;
    try {
      await app.api.delete('/channels/${c.id}');
      app.toast('Saluran dihapus.');
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void report() => reportChannel(context, c);

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: zAppBar(context, text: 'Info saluran'),
      body: ListView(children: [
        const SizedBox(height: 22),
        Center(child: ChannelAvatar(url: c.avatarUrl, size: 120, ringStyle: c.ringStyle)),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(c.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            if (c.isVerified) const Padding(padding: EdgeInsets.only(left: 6), child: VerifiedBadge(size: 20)),
          ]),
        ),
        const SizedBox(height: 4),
        Center(child: Text('Saluran · ${followersText(c.followerCount)}', style: TextStyle(color: p.muted, fontSize: 15))),
        const SizedBox(height: 16),
        if (!c.canPost)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: NeoButton(c.isFollowing ? 'Berhenti mengikuti' : 'Ikuti', primary: !c.isFollowing, busy: busy, onPressed: toggleFollow),
          ),
        if (c.description.trim().isNotEmpty) ...[
          const SectionTitle('Deskripsi'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(c.description, style: const TextStyle(fontSize: 15.5))),
        ],
        const SectionTitle('Dibuat'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(dateTimeText(c.createdAt), style: TextStyle(color: p.muted))),
        const SizedBox(height: 14),
        NeoTile(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Admin saluran',
          subtitle: c.isOwner
              ? '${c.adminCount} admin termasuk Anda · tambah atau cabut admin'
              : (c.isAdmin ? 'Anda admin saluran ini · ${c.adminCount} admin' : '${c.adminCount} admin'),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelAdminsPage(channel: c)));
            await refresh();
          },
        ),
        if (c.isFollowing && !c.isOwner)
          NeoSwitchTile(
            icon: c.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
            title: 'Bisukan notifikasi',
            value: c.muted,
            onChanged: toggleMute,
          ),
        if (c.canPost) NeoTile(icon: Icons.edit_outlined, title: 'Ubah saluran', subtitle: 'Nama, deskripsi, dan foto', onTap: edit),
        if (c.canPost) NeoTile(icon: Icons.account_circle_outlined, title: 'Ring Avatar', subtitle: 'Bingkai foto saluran ini', onTap: openRing),
        if (c.isOwner)
          NeoTile(icon: Icons.delete_outline, title: 'Hapus saluran', subtitle: 'Menghapus saluran dan semua pesannya', danger: true, onTap: delete)
        else if (!c.canPost)
          NeoTile(icon: Icons.flag_outlined, title: 'Laporkan saluran', danger: true, onTap: report),
        const SizedBox(height: 24),
      ]),
    );
  }
}

// ====================================================================== admin saluran
/// Daftar pemilik + admin saluran. Pemilik dapat menambah/mencabut admin; admin dapat mundur sendiri.
class ChannelAdminsPage extends StatefulWidget {
  final Channel channel;
  const ChannelAdminsPage({super.key, required this.channel});
  @override
  State<ChannelAdminsPage> createState() => _ChannelAdminsPageState();
}

class _ChannelAdminsPageState extends State<ChannelAdminsPage> {
  Channel get c => widget.channel;
  User? owner;
  List<User> admins = [];
  int maxAdmins = 10;
  bool loading = true;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/channels/${c.id}/admins'));
      owner = r['owner'] == null ? null : User.fromJson(r['owner']);
      admins = asList(r['admins']).map((u) => User.fromJson(u)).toList();
      maxAdmins = r['max'] == null ? 10 : _ci(r['max']);
      c.adminCount = admins.length + 1;
      error = null;
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> add() async {
    if (admins.length >= maxAdmins) {
      app.toast('Maksimal $maxAdmins admin per saluran.', error: true);
      return;
    }
    final taken = <int>{c.ownerId, ...admins.map((a) => a.id)};
    final picked = await showModalBottomSheet<User>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pal(context).surface,
      builder: (_) => _AdminPickerSheet(exclude: taken),
    );
    if (picked == null || !mounted) return;
    final ok = await showConfirm(context, 'Jadikan admin?', '${picked.username} akan dapat mengirim pesan dan sticker, menghapus pesan, serta mengubah info saluran "${c.name}".', 'Jadikan admin');
    if (!ok) return;
    setState(() => busy = true);
    try {
      await app.api.post('/channels/${c.id}/admins', {'userId': picked.id});
      app.toast('${picked.username} sekarang admin saluran.');
      await load();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> remove(User u) async {
    final self = u.id == app.me?.id;
    final ok = await showConfirm(
      context,
      self ? 'Mundur dari admin?' : 'Cabut admin?',
      self ? 'Anda tidak akan bisa lagi mengirim pesan di saluran "${c.name}".' : '${u.username} tidak akan bisa lagi mengirim pesan di saluran ini.',
      self ? 'Mundur' : 'Cabut',
      danger: true,
    );
    if (!ok) return;
    setState(() => busy = true);
    try {
      await app.api.delete('/channels/${c.id}/admins/${u.id}');
      app.toast(self ? 'Anda bukan lagi admin.' : 'Admin dicabut.');
      if (self) {
        c.isAdmin = false;
        c.canPost = c.isOwner;
      }
      await load();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Widget row(User u, {required bool isOwnerRow}) {
    final p = pal(context);
    final me = u.id == app.me?.id;
    Widget? trailing;
    if (isOwnerRow) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: p.yellow, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line, width: 1.5)),
        child: const Text('Pemilik', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF111111))),
      );
    } else if (c.isOwner) {
      trailing = IconButton(tooltip: 'Cabut admin', icon: Icon(Icons.person_remove_outlined, color: p.bad), onPressed: busy ? null : () => remove(u));
    } else if (me) {
      trailing = TextButton(onPressed: busy ? null : () => remove(u), child: Text('Mundur', style: TextStyle(color: p.bad, fontWeight: FontWeight.w800)));
    }
    return NeoRow(
      leading: Avatar(user: u, size: 44),
      title: NameWithBadge(u),
      subtitle: Text(me ? 'Anda · ${isOwnerRow ? 'pemilik saluran' : 'admin'}' : (isOwnerRow ? 'Pemilik saluran' : 'Admin'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null && owner == null) {
      body = EmptyState(icon: Icons.error_outline, title: 'Gagal memuat admin', text: error, action: NeoButton('Coba lagi', onPressed: () {
        setState(() {
          loading = true;
          error = null;
        });
        load();
      }));
    } else {
      body = RefreshIndicator(
        onRefresh: load,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.only(top: 14, bottom: 28), children: [
          if (c.isOwner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: NeoButton('Tambah admin', icon: Icons.person_add_alt_1_outlined, busy: busy, onPressed: add),
            ),
          if (c.isOwner)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text('Admin dapat mengirim pesan & sticker, menghapus pesan, dan mengubah info saluran. Hanya pemilik yang bisa menambah/mencabut admin dan menghapus saluran. (${admins.length}/$maxAdmins)',
                  style: TextStyle(color: p.text, fontSize: 12.5)),
            ),
          const NeoSection('Pemilik'),
          if (owner != null) row(owner!, isOwnerRow: true),
          NeoSection('Admin (${admins.length})'),
          if (admins.isEmpty)
            NeoCard(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 11),
              child: Text(c.isOwner ? 'Belum ada admin. Ketuk "Tambah admin" untuk mengajak orang lain mengelola saluran ini.' : 'Belum ada admin selain pemilik.', style: TextStyle(color: p.muted)),
            ),
          ...admins.map((u) => row(u, isOwnerRow: false)),
        ]),
      );
    }
    return Scaffold(appBar: zAppBar(context, text: 'Admin saluran'), body: body);
  }
}

/// Mencari pengguna (nama / nomor +62…) untuk dijadikan admin. Menutup lembar dengan pengguna terpilih.
class _AdminPickerSheet extends StatefulWidget {
  final Set<int> exclude;
  const _AdminPickerSheet({required this.exclude});
  @override
  State<_AdminPickerSheet> createState() => _AdminPickerSheetState();
}

class _AdminPickerSheetState extends State<_AdminPickerSheet> {
  final TextEditingController input = TextEditingController();
  Timer? timer;
  List<User> users = [];
  bool loading = false;
  String? error;
  String last = '';

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  void onChanged(String _) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 350), run);
    setState(() {});
  }

  Future<void> run() async {
    final t = input.text.trim();
    last = t;
    if (t.length < 2) {
      if (mounted) {
        setState(() {
          users = [];
          error = null;
          loading = false;
        });
      }
      return;
    }
    setState(() => loading = true);
    try {
      final r = asMap(await app.api.get('/users/search?q=${Uri.encodeQueryComponent(t)}'));
      if (!mounted || last != t) return;
      setState(() {
        users = asList(r['users']).map((u) => User.fromJson(u)).where((u) => !widget.exclude.contains(u.id)).toList();
        error = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = errText(e);
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Expanded(child: Text('Tambah admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: input,
                autofocus: true,
                onChanged: onChanged,
                decoration: neoDeco(context, hint: 'Nama atau nomor (+62…)', prefix: const Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: Builder(builder: (context) {
                if (input.text.trim().length < 2) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Ketik minimal 2 karakter. Orang yang dipilih harus sudah mendaftar di ZARR CHAT.', style: TextStyle(color: p.muted)),
                  );
                }
                if (loading) return const Spin(label: 'Mencari…');
                if (error != null) return EmptyState(icon: Icons.error_outline, title: 'Gagal mencari', text: error);
                if (users.isEmpty) {
                  return const EmptyState(icon: Icons.search_off, title: 'Pengguna tidak ditemukan', text: 'Pastikan nama atau nomornya benar dan orang tersebut belum menjadi admin.');
                }
                return ListView(
                  padding: const EdgeInsets.only(top: 14, bottom: 14),
                  children: users
                      .map((u) => NeoRow(
                            leading: Avatar(user: u, size: 44),
                            title: NameWithBadge(u),
                            subtitle: Text(u.about, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
                            onTap: () => Navigator.pop(context, u),
                          ))
                      .toList(),
                );
              }),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Melaporkan saluran (laporan dikirim terhadap pemilik saluran, lengkap dengan nama saluran).
Future<void> reportChannel(BuildContext context, Channel c) async {
  const reasons = <String, String>{
    'spam': 'Spam',
    'pelecehan': 'Pelecehan',
    'penipuan': 'Penipuan',
    'konten_tidak_pantas': 'Konten tidak pantas',
    'lainnya': 'Lainnya',
  };
  await showMenuSheet(
    context,
    reasons.entries
        .map((e) => MenuItem(Icons.flag_outlined, e.value, () async {
              try {
                await app.api.post('/users/${c.ownerId}/report', {'reason': e.key, 'details': 'Saluran "${c.name}" (#${c.id})'});
                app.toast('Laporan terkirim. Terima kasih.');
              } catch (err) {
                app.toast(errText(err), error: true);
              }
            }))
        .toList(),
    title: 'Laporkan saluran',
  );
}

// ====================================================================== halaman saluran
const List<String> _kReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

class ChannelPage extends StatefulWidget {
  final Channel channel;
  const ChannelPage({super.key, required this.channel});
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  Channel get c => widget.channel;
  List<ChannelPost> posts = [];
  bool loading = true;
  bool hasMore = false;
  bool loadingMore = false;
  String? error;
  bool sending = false;
  bool followBusy = false;
  bool stickerOpen = false; // panel sticker di bawah kolom ketik
  final TextEditingController input = TextEditingController();
  StreamSubscription<SocketEvent>? sub;
  final ScrollController scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    sub = app.events.listen(onEvent);
    start();
  }

  @override
  void dispose() {
    sub?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> start() async {
    try {
      final r = asMap(await app.api.get('/channels/${c.id}'));
      c.copyFrom(Channel.fromJson(r['channel']));
    } catch (_) {
      // lanjut memuat pesan
    }
    await load();
    markRead();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/channels/${c.id}/posts?limit=30'));
      if (!mounted) return;
      setState(() {
        posts = asList(r['posts']).map((p) => ChannelPost.fromJson(p)).toList();
        hasMore = r['hasMore'] == true;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = errText(e);
        loading = false;
      });
    }
  }

  Future<void> older() async {
    if (loadingMore || posts.isEmpty) return;
    setState(() => loadingMore = true);
    try {
      final r = asMap(await app.api.get('/channels/${c.id}/posts?limit=30&before=${posts.first.id}'));
      final got = asList(r['posts']).map((p) => ChannelPost.fromJson(p)).toList();
      if (!mounted) return;
      setState(() {
        posts = [...got, ...posts];
        hasMore = r['hasMore'] == true;
        loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => loadingMore = false);
      app.toast(errText(e), error: true);
    }
  }

  void markRead() {
    c.unread = 0;
    app.api.post('/channels/${c.id}/read').catchError((Object _) => null);
  }

  void onEvent(SocketEvent e) {
    final d = e.data;
    if (_ci(d['channelId']) != c.id) return;
    switch (e.name) {
      case 'channel:post':
        {
          final np = ChannelPost.fromJson(d['post']);
          if (!posts.any((x) => x.id == np.id) && mounted) {
            setState(() => posts = [...posts, np]);
            markRead();
          }
          break;
        }
      case 'channel:post_updated':
        {
          final pid = _ci(d['postId']);
          final i = posts.indexWhere((x) => x.id == pid);
          if (i >= 0 && mounted) {
            final rx = <String, int>{};
            asMap(d['reactions']).forEach((k, v) => rx[k] = _ci(v));
            setState(() {
              posts[i].reactions = rx;
              posts[i].views = _ci(d['views']);
            });
          }
          break;
        }
      case 'channel:post_deleted':
        {
          final pid = _ci(d['postId']);
          if (mounted) setState(() => posts = posts.where((x) => x.id != pid).toList());
          break;
        }
      case 'channel:updated':
        app.api.get('/channels/${c.id}').then((r) {
          c.copyFrom(Channel.fromJson(asMap(r)['channel']));
          if (mounted) setState(() {});
        }).catchError((Object _) => null);
        break;
      case 'channel:deleted':
        if (mounted) {
          app.toast('Saluran ini telah dihapus.');
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
        break;
      default:
        break;
    }
  }

  // ------------------------------------------------------------ aksi
  Future<void> follow() async {
    setState(() => followBusy = true);
    await setFollow(c, true);
    if (mounted) setState(() => followBusy = false);
  }

  Future<void> unfollow() async {
    final ok = await showConfirm(context, 'Berhenti mengikuti?', 'Anda tidak akan menerima pesan baru dari "${c.name}".', 'Berhenti');
    if (!ok) return;
    await setFollow(c, false);
    if (mounted) setState(() {});
  }

  Future<void> toggleMute() async {
    try {
      final r = asMap(await app.api.patch('/channels/${c.id}/mute', {'muted': !c.muted}));
      c.copyFrom(Channel.fromJson(r['channel']));
      app.toast(c.muted ? 'Notifikasi saluran dibisukan.' : 'Notifikasi saluran diaktifkan.');
      if (mounted) setState(() {});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> openInfo() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelInfoPage(channel: c)));
    if (mounted) setState(() {});
  }

  void menu() {
    showMenuSheet(context, [
      MenuItem(Icons.info_outline, 'Info saluran', openInfo),
      if (c.isFollowing && !c.isOwner) MenuItem(c.muted ? Icons.volume_up_outlined : Icons.volume_off_outlined, c.muted ? 'Aktifkan notifikasi' : 'Bisukan notifikasi', toggleMute),
      if (c.isFollowing && !c.canPost) MenuItem(Icons.logout, 'Berhenti mengikuti', unfollow, danger: true),
      if (c.canPost) MenuItem(Icons.edit_outlined, 'Ubah saluran', () async {
            await Navigator.of(context).push<Channel>(MaterialPageRoute<Channel>(builder: (_) => ChannelFormPage(edit: c)));
            if (mounted) setState(() {});
          }),
      if (!c.canPost) MenuItem(Icons.flag_outlined, 'Laporkan saluran', () => reportChannel(context, c), danger: true),
    ]);
  }

  void toggleStickers() {
    FocusScope.of(context).unfocus();
    setState(() => stickerOpen = !stickerOpen);
  }

  Media _stickerMedia(ChannelPost p) => Media(id: p.mediaId ?? 0, kind: 'sticker', mime: 'image/png', size: 0, url: p.mediaUrl ?? '');

  Future<void> sendText() async {
    final t = input.text.trim();
    if (t.isEmpty || sending) return;
    await _post({'type': 'text', 'body': t});
  }

  Future<void> sendMedia(String type) async {
    if (sending) return;
    try {
      final picker = ImagePicker();
      final XFile? f = type == 'image'
          ? await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920, imageQuality: 85)
          : await picker.pickVideo(source: ImageSource.gallery);
      if (f == null) return;
      setState(() => sending = true);
      final id = await app.api.upload(f.path, type, filename: f.name);
      await _post({'type': type, 'mediaId': id, 'body': input.text.trim()});
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _post(Map<String, dynamic> body) async {
    if (sending) return;
    setState(() => sending = true);
    try {
      final r = asMap(await app.api.post('/channels/${c.id}/posts', body));
      final p = ChannelPost.fromJson(r['post']);
      if (body['type'] != 'sticker') input.clear();
      if (mounted) {
        setState(() {
          if (!posts.any((x) => x.id == p.id)) posts = [...posts, p];
          sending = false;
        });
      }
      c.lastPost = p;
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => sending = false);
    }
  }

  void attachMenu() {
    showMenuSheet(context, [
      MenuItem(Icons.image_outlined, 'Foto', () => sendMedia('image')),
      MenuItem(Icons.videocam_outlined, 'Video', () => sendMedia('video')),
    ]);
  }

  Future<void> react(ChannelPost p, String emoji) async {
    final newEmoji = p.myReaction == emoji ? null : emoji;
    final old = p.myReaction;
    final oldRx = Map<String, int>.from(p.reactions);
    // Tampilkan langsung, lalu sinkronkan dengan server.
    setState(() {
      if (old != null) {
        final n = (p.reactions[old] ?? 1) - 1;
        if (n <= 0) {
          p.reactions.remove(old);
        } else {
          p.reactions[old] = n;
        }
      }
      if (newEmoji != null) p.reactions[newEmoji] = (p.reactions[newEmoji] ?? 0) + 1;
      p.myReaction = newEmoji;
    });
    try {
      final r = asMap(await app.api.post('/channels/${c.id}/posts/${p.id}/react', {'emoji': newEmoji}));
      final fresh = ChannelPost.fromJson(r['post']);
      if (mounted) {
        setState(() {
          p.reactions = fresh.reactions;
          p.myReaction = fresh.myReaction;
          p.views = fresh.views;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          p.reactions = oldRx;
          p.myReaction = old;
        });
      }
      app.toast(errText(e), error: true);
    }
  }

  Future<void> deletePost(ChannelPost p) async {
    final ok = await showConfirm(context, 'Hapus pesan?', 'Pesan ini akan dihapus untuk semua pengikut.', 'Hapus', danger: true);
    if (!ok) return;
    try {
      await app.api.delete('/channels/${c.id}/posts/${p.id}');
      if (mounted) setState(() => posts = posts.where((x) => x.id != p.id).toList());
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void postMenu(ChannelPost p) {
    final pl = pal(context);
    showMenuSheet(
      context,
      [
        if ((p.body ?? '').isNotEmpty)
          MenuItem(Icons.copy, 'Salin', () {
            Clipboard.setData(ClipboardData(text: p.body ?? ''));
            app.toast('Disalin.');
          }),
        if (p.type == 'sticker' && p.mediaId != null)
          MenuItem(Icons.star_border, 'Favorit sticker', () => showStickerDetail(context, _stickerMedia(p))),
        if (c.canPost) MenuItem(Icons.delete_outline, 'Hapus pesan', () => deletePost(p), danger: true),
      ],
      header: Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _kReactions
                .map((e) => InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.pop(ctx);
                        react(p, e);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: p.myReaction == e ? BoxDecoration(color: pl.surface2, shape: BoxShape.circle) : null,
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ tampilan
  /// Sticker tampil tanpa gelembung; ketuk = tambahkan ke favorit, tahan = menu.
  Widget stickerBubble(ChannelPost p) {
    final pl = pal(context);
    final rx = p.reactions.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        child: GestureDetector(
          onTap: p.mediaId == null ? null : () => showStickerDetail(context, _stickerMedia(p)),
          onLongPress: () => postMenu(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            CachedNetworkImage(
              imageUrl: app.api.abs(p.mediaUrl),
              httpHeaders: app.api.mediaHeaders,
              width: 150,
              height: 150,
              fit: BoxFit.contain,
              placeholder: (cx, u) => const SizedBox(width: 150, height: 150),
              errorWidget: (cx, u, e) => const SizedBox(width: 150, height: 150, child: Icon(Icons.broken_image)),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: pl.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: pl.line, width: 1.5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ...rx.map((e) => GestureDetector(
                      onTap: () => react(p, e.key),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: p.myReaction == e.key ? pl.yellow : pl.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: p.myReaction == e.key ? pl.line : pl.divider, width: 1.5),
                        ),
                        child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    )),
                Icon(Icons.visibility_outlined, size: 13, color: pl.muted),
                const SizedBox(width: 3),
                Text('${p.views}', style: TextStyle(fontSize: 11, color: pl.muted)),
                const SizedBox(width: 8),
                Text(fmtTime(p.createdAt), style: TextStyle(fontSize: 11, color: pl.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget bubble(ChannelPost p) {
    if (p.type == 'sticker') return stickerBubble(p);
    final pl = pal(context);
    // Pesan teks/foto/video selebar layar (seperti saluran WhatsApp); hanya sticker yang ukurannya kecil di tengah.
    final w = MediaQuery.of(context).size.width - 20;
    final body = (p.body ?? '').trim();
    final Widget? media = p.type == 'image'
        ? GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImageViewerPage(url: p.mediaUrl))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: app.api.abs(p.mediaUrl),
                httpHeaders: app.api.mediaHeaders,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (cx, u) => const SizedBox(height: 180, child: Spin()),
                errorWidget: (cx, u, e) => const SizedBox(height: 120, child: Center(child: Icon(Icons.broken_image))),
              ),
            ),
          )
        : p.type == 'video'
            ? GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VideoPage(url: p.mediaUrl))),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(color: const Color(0xFF1B1B1B), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 56)),
                ),
              )
            : null;
    final rx = p.reactions.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final inner = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (media != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: media),
      if (body.isNotEmpty) LinkText(body, style: TextStyle(color: pl.text, fontSize: 15.5), linkColor: pl.accentText),
      if (rx.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            ...rx.map((e) => GestureDetector(
                  onTap: () => react(p, e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.myReaction == e.key ? pl.yellow : pl.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.myReaction == e.key ? pl.line : pl.divider, width: 1.5),
                    ),
                    child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                )),
          ]),
        ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.visibility_outlined, size: 13, color: pl.muted),
          const SizedBox(width: 3),
          Text('${p.views}', style: TextStyle(fontSize: 11, color: pl.muted)),
          const SizedBox(width: 8),
          Text(fmtTime(p.createdAt), style: TextStyle(fontSize: 11, color: pl.muted)),
        ]),
      ),
    ]);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: w, minWidth: w),
          child: GestureDetector(
            onLongPress: () => postMenu(p),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              decoration: BoxDecoration(
                color: pl.bubbleIn,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pl.line, width: 2),
              ),
              child: inner,
            ),
          ),
        ),
      ),
    );
  }

  Widget messageList() {
    final pl = pal(context);
    if (loading) return const Spin();
    if (error != null && posts.isEmpty) {
      return EmptyState(icon: Icons.error_outline, title: 'Gagal memuat pesan', text: error, action: NeoButton('Coba lagi', onPressed: () {
        setState(() {
          loading = true;
          error = null;
        });
        load();
      }));
    }
    if (posts.isEmpty) {
      return EmptyState(
        icon: Icons.campaign_outlined,
        title: 'Belum ada pesan',
        text: c.canPost ? 'Kirim pesan pertama ke pengikut saluran ini.' : 'Pesan dari saluran ini akan muncul di sini.',
      );
    }
    final items = <Widget>[];
    if (hasMore) {
      items.add(Center(child: loadingMore ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()) : TextButton(onPressed: older, child: const Text('Muat pesan sebelumnya'))));
    }
    DateTime? prev;
    for (final p in posts) {
      if (prev == null || !sameDay(prev, p.createdAt)) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(color: pl.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: pl.line, width: 1.5)),
              child: Text(dayLabel(p.createdAt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ),
        ));
      }
      prev = p.createdAt;
      items.add(bubble(p));
    }
    // reverse: true -> daftar menempel di bawah dan pesan terbaru terlihat lebih dulu.
    return ListView(reverse: true, controller: scroll, padding: const EdgeInsets.symmetric(vertical: 8), children: items.reversed.toList());
  }

  Widget bottomBar() {
    final pl = pal(context);
    if (c.canPost) {
      return Container(
        color: pl.surface,
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(icon: const Icon(Icons.attach_file), onPressed: sending ? null : attachMenu),
                IconButton(
                  tooltip: stickerOpen ? 'Keyboard' : 'Sticker',
                  icon: Icon(stickerOpen ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined),
                  onPressed: toggleStickers,
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    onTap: () {
                      if (stickerOpen) setState(() => stickerOpen = false);
                    },
                    decoration: neoDeco(context, hint: 'Ketik pesan saluran').copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11)),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: pl.yellow,
                  shape: CircleBorder(side: BorderSide(color: pl.line, width: 2)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: sending ? null : sendText,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: sending
                          ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF111111)))
                          : const Icon(Icons.send, color: Color(0xFF111111)),
                    ),
                  ),
                ),
              ]),
            ),
            if (stickerOpen)
              Container(
                height: 300,
                decoration: BoxDecoration(color: pl.bg, border: Border(top: BorderSide(color: pl.line, width: 2))),
                // Ketuk sticker langsung terkirim; panel tetap terbuka agar bisa kirim beberapa sticker.
                child: StickerPanel(onSend: (st) => _post({'type': 'sticker', 'mediaId': st.mediaId})),
              ),
          ]),
        ),
      );
    }
    if (!c.isFollowing) {
      return Container(
        color: pl.surface,
        child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: NeoButton('Ikuti saluran', busy: followBusy, onPressed: follow))),
      );
    }
    return Container(
      color: pl.surface,
      width: double.infinity,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Text('Hanya pemilik dan admin saluran yang dapat mengirim pesan.', textAlign: TextAlign.center, style: TextStyle(color: pl.muted, fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pl = pal(context);
    return Scaffold(
      appBar: zAppBar(
        context,
        titleSpacing: 0,
        title: InkWell(
          onTap: openInfo,
          child: Row(children: [
            ChannelAvatar(url: c.avatarUrl, size: 40, ringStyle: c.ringStyle),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                  if (c.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedBadge()),
                ]),
                Text(followersText(c.followerCount), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: menu)],
      ),
      body: Container(
        color: pl.chatBg,
        child: Column(children: [
          Expanded(child: messageList()),
          bottomBar(),
        ]),
      ),
    );
  }
}
