// ZARR CHAT - halaman grup: buat grup, info grup, edit info, tambah anggota, media bersama, info pesan.
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'auth.dart';
import 'avatar_cropper.dart';
import 'chats_tab.dart';
import 'group_chat.dart';
import 'groups.dart';
import 'media.dart';
import 'models.dart';
import 'profile_view.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

Future<String?> _pickPhoto(BuildContext context) => pickAndCropAvatar(context, title: 'Atur foto grup');

// ------------------------------------------------------------------ buat grup

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});
  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final Map<int, User> selected = {};
  final TextEditingController name = TextEditingController();
  final TextEditingController desc = TextEditingController();
  int step = 0;
  String? photoPath;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> create() async {
    final n = name.text.trim();
    if (n.isEmpty) {
      app.toast('Isi nama grup terlebih dahulu.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final body = <String, dynamic>{'name': n, 'description': desc.text.trim(), 'memberIds': selected.keys.toList()};
      if (photoPath != null) body['avatarMediaId'] = await app.api.upload(photoPath!, 'avatar');
      final r = asMap(await app.api.post('/groups', body));
      final g = GroupItem.fromJson(r['group']);
      final skipped = asList(r['skipped']);
      await app.loadChatsNow();
      if (!mounted) return;
      if (skipped.isNotEmpty) app.toast('${skipped.length} orang tidak dapat ditambahkan.');
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => groupChatRoute(g)));
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  Widget stepOne() {
    return Column(children: [
      Expanded(child: UserPicker(selected: selected, onChanged: () => setState(() {}))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            child: NeoButton(selected.isEmpty ? 'Pilih anggota' : 'Lanjut (${selected.length})',
                icon: Icons.arrow_forward, onPressed: selected.isEmpty ? null : () => setState(() => step = 1)),
          ),
        ),
      ),
    ]);
  }

  Widget stepTwo() {
    final p = pal(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: GestureDetector(
          onTap: () async {
            final path = await _pickPhoto(context);
            if (path != null && mounted) setState(() => photoPath = path);
          },
          child: Stack(children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.yellow, border: Border.all(color: p.line, width: 3)),
              clipBehavior: Clip.antiAlias,
              child: photoPath != null
                  ? Image.file(File(photoPath!), fit: BoxFit.cover)
                  : const Icon(Icons.groups, size: 56, color: Color(0xFF111111)),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle, border: Border.all(color: p.line, width: 2)),
                child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
              ),
            ),
          ]),
        ),
      ),
      if (photoPath != null)
        Center(child: TextButton(onPressed: () => setState(() => photoPath = null), child: const Text('Hapus foto'))),
      const SizedBox(height: 14),
      TextField(
        controller: name,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: neoDeco(context, hint: 'Nama grup', prefix: const Icon(Icons.edit_outlined)),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: desc,
        maxLength: 500,
        maxLines: 3,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: neoDeco(context, hint: 'Deskripsi grup (opsional)'),
      ),
      const SizedBox(height: 8),
      Text('Anggota: ${selected.length}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        children: selected.values
            .map((u) => SizedBox(
                  width: 62,
                  child: Column(children: [
                    Avatar(user: u, size: 42),
                    const SizedBox(height: 3),
                    Text(u.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ]),
                ))
            .toList(),
      ),
      const SizedBox(height: 22),
      NeoButton('Buat grup', icon: Icons.check, busy: busy, onPressed: create),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == 0 || busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && step == 1) setState(() => step = 0);
      },
      child: Scaffold(
        appBar: zAppBar(context, text: step == 0 ? 'Tambah anggota grup' : 'Grup baru'),
        body: step == 0 ? stepOne() : stepTwo(),
      ),
    );
  }
}

// ------------------------------------------------------------------ info grup

class GroupInfoPage extends StatefulWidget {
  final GroupItem group;
  const GroupInfoPage({super.key, required this.group});
  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late GroupItem g = widget.group;
  List<GroupMember> members = [];
  bool loading = true;
  String? error;
  StreamSubscription<SocketEvent>? sub;

  int get meId => app.me?.id ?? 0;

  @override
  void initState() {
    super.initState();
    sub = app.events.listen((e) {
      if (!mounted) return;
      if (e.name == 'group:updated' && e.data['groupId'] == g.id) load(quiet: true);
      if (e.name == 'group:removed' && e.data['groupId'] == g.id) Navigator.of(context).popUntil((r) => r.isFirst);
      if (e.name == 'reconnected') load(quiet: true);
    });
    load();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) setState(() => loading = true);
    try {
      final r = asMap(await app.api.get('/groups/${g.id}'));
      final fresh = GroupItem.fromJson(r['group']);
      g.merge(fresh);
      members = asList(r['members']).map((m) => GroupMember.fromJson(m)).toList();
      error = null;
    } catch (e) {
      if (!quiet) error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> patchGroup(Map<String, dynamic> body, String okMsg) async {
    try {
      await app.api.patch('/groups/${g.id}', body);
      await load(quiet: true);
      app.loadChatsNow();
      if (okMsg.isNotEmpty) app.toast(okMsg);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> openRing() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RingPickerPage(
        title: 'Ring Avatar grup',
        note: 'Ring ini hanya untuk grup ini dan terlihat oleh semua anggota. Ring profil dan saluran tidak ikut berubah.',
        initial: g.ringStyle,
        preview: (size, style) => Avatar(url: g.avatarUrl, name: g.name, size: size, group: true, ringStyle: style),
        onSave: (id) async {
          await app.api.patch('/groups/${g.id}', {'ringStyle': id});
          g.ringStyle = id;
          app.loadChatsNow();
        },
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> patchMine(Map<String, dynamic> body) async {
    try {
      await app.api.patch('/groups/${g.id}/me', body);
      if (body.containsKey('muted')) g.muted = body['muted'] == true;
      app.loadChatsNow();
      if (mounted) setState(() {});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void openPhoto() {
    final url = g.avatarUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImageViewerPage(url: url)));
  }

  Future<void> leave() async {
    final ok = await showConfirm(context, 'Keluar dari grup?', 'Anda tidak akan menerima pesan dari grup "${g.name}" lagi. Anggota lain akan diberi tahu.', 'Keluar', danger: true);
    if (!ok) return;
    try {
      await app.api.post('/groups/${g.id}/leave');
      app.loadChatsNow();
      app.toast('Anda keluar dari grup.');
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> addMembers() async {
    final n = await Navigator.of(context).push<int>(MaterialPageRoute<int>(builder: (_) => AddMembersPage(group: g, existing: members.map((m) => m.user.id).toSet())));
    if (n != null && n > 0) {
      app.toast('$n anggota ditambahkan.');
      load(quiet: true);
    }
  }

  void memberMenu(GroupMember m) {
    final u = m.user;
    if (u.id == meId) return;
    final iAmOwner = g.isOwner;
    final canRemove = g.isAdmin && !m.isOwner && (!m.isAdmin || iAmOwner);
    final canPromote = g.isAdmin && !m.isAdmin;
    final canDemote = iAmOwner && m.isAdmin && !m.isOwner;
    showMenuSheet(context, [
      MenuItem(Icons.chat_outlined, 'Kirim pesan ke ${u.username}', () => openChatWithUser(context, u.id)),
      MenuItem(Icons.info_outline, 'Info ${u.username}', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ContactInfoPage(peer: u)))),
      if (canPromote) MenuItem(Icons.admin_panel_settings_outlined, 'Jadikan admin grup', () => setRole(m, 'admin')),
      if (canDemote) MenuItem(Icons.remove_moderator_outlined, 'Hapus dari admin', () => setRole(m, 'member')),
      if (g.isAdmin) MenuItem(Icons.flag_outlined, 'Laporkan ${u.username}', () => showGroupReport(context, g.id, userId: u.id, title: 'Laporkan anggota'), danger: true),
      if (canRemove) MenuItem(Icons.person_remove_outlined, 'Keluarkan dari grup', () => removeMember(m), danger: true),
    ], title: u.username);
  }

  Future<void> setRole(GroupMember m, String role) async {
    try {
      await app.api.put('/groups/${g.id}/members/${m.user.id}/role', {'role': role});
      await load(quiet: true);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> removeMember(GroupMember m) async {
    final ok = await showConfirm(context, 'Keluarkan anggota?', '${m.user.username} akan dikeluarkan dari grup "${g.name}".', 'Keluarkan', danger: true);
    if (!ok) return;
    try {
      await app.api.delete('/groups/${g.id}/members/${m.user.id}');
      await load(quiet: true);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void choose(String title, String key, String current) {
    showMenuSheet(context, [
      MenuItem(Icons.groups_outlined, 'Semua anggota', () => patchGroup({key: 'all'}, ''), checked: current == 'all'),
      MenuItem(Icons.admin_panel_settings_outlined, 'Hanya admin', () => patchGroup({key: 'admins'}, ''), checked: current == 'admins'),
    ], title: title);
  }

  void disappearMenu() {
    if (!g.isAdmin) {
      app.toast('Hanya admin yang dapat mengubah pesan menghilang.');
      return;
    }
    final opts = <int, String>{0: 'Mati', 86400: '24 jam', 604800: '7 hari', 7776000: '90 hari'};
    showMenuSheet(
      context,
      opts.entries.map((e) => MenuItem(Icons.timer_outlined, e.value, () => patchGroup({'disappearSeconds': e.key}, ''), checked: g.disappearSeconds == e.key)).toList(),
      title: 'Pesan menghilang',
    );
  }

  Widget quick(IconData icon, String label, VoidCallback onTap) {
    final p = pal(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            Icon(icon, color: p.accentText, size: 26),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: p.accentText, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  Widget linkCard() {
    final p = pal(context);
    final code = g.inviteCode;
    if (code == null || code.isEmpty) return const SizedBox.shrink();
    return NeoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.pin_outlined),
          const SizedBox(width: 8),
          Text('Kode undangan grup', style: TextStyle(color: p.muted, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        SelectableText(code, style: TextStyle(color: p.accentText, fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: 4)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: NeoButton('Salin', icon: Icons.copy, primary: false, onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              app.toast('Kode grup disalin.');
            }),
          ),
          const SizedBox(width: 10),
          Expanded(child: NeoButton('Bagikan', icon: Icons.share, onPressed: () => shareInviteSheet(context, g))),
        ]),
        if (g.isAdmin)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final ok = await showConfirm(context, 'Atur ulang kode?', 'Kode lama tidak akan berfungsi lagi. Anggota yang sudah bergabung tidak terpengaruh.', 'Atur ulang', danger: true);
                if (!ok) return;
                try {
                  await app.api.post('/groups/${g.id}/invite/reset');
                  await load(quiet: true);
                  app.toast('Kode grup diatur ulang.');
                } catch (e) {
                  app.toast(errText(e), error: true);
                }
              },
              icon: Icon(Icons.refresh, color: p.bad, size: 18),
              label: Text('Atur ulang kode', style: TextStyle(color: p.bad, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }

  Widget memberRow(GroupMember m) {
    final p = pal(context);
    final me = m.user.id == meId;
    return NeoRow(
      onTap: me ? null : () => memberMenu(m),
      leading: Avatar(user: m.user, size: 44),
      title: Row(children: [
        Flexible(child: me ? const Text('Anda', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)) : NameWithBadge(m.user)),
      ]),
      subtitle: Text(m.user.about, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
      trailing: m.isAdmin
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: p.yellow, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line, width: 1.5)),
              child: Text(m.isOwner ? 'Pembuat' : 'Admin', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF111111))),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    if (loading && members.isEmpty) return Scaffold(appBar: zAppBar(context, text: 'Info grup'), body: const Spin());
    if (error != null && members.isEmpty) {
      return Scaffold(
        appBar: zAppBar(context, text: 'Info grup'),
        body: EmptyState(icon: Icons.error_outline, title: 'Gagal memuat', text: error, action: NeoButton('Coba lagi', onPressed: load)),
      );
    }
    final desc = g.description.trim();
    final created = g.createdAt == null ? '' : 'Dibuat ${g.creatorName.isEmpty ? '' : 'oleh ${g.creatorName} '}pada ${dateTimeText(g.createdAt)}';
    final canInvite = g.canAddMembers;
    return Scaffold(
      appBar: zAppBar(context, text: 'Info grup', actions: [
        if (g.canEditInfo)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => EditGroupPage(group: g)));
              if (changed == true) load(quiet: true);
            },
          ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        Center(child: Avatar(url: g.avatarUrl, name: g.name, size: 140, group: true, ringStyle: g.ringStyle, onTap: openPhoto)),
        const SizedBox(height: 12),
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(g.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            if (g.isVerified) const Padding(padding: EdgeInsets.only(left: 6), child: VerifiedBadge(size: 22)),
          ]),
        ),
        const SizedBox(height: 2),
        Center(child: Text('Grup · ${g.memberCount} anggota', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
        const SizedBox(height: 12),
        NeoCard(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            if (canInvite) quick(Icons.person_add_alt_1_outlined, 'Tambah', addMembers),
            quick(Icons.search, 'Cari', () => Navigator.pop(context, 'search')),
            if (canInvite && g.inviteCode != null) quick(Icons.pin_outlined, 'Kode', () => shareInviteSheet(context, g)),
          ]),
        ),
        NeoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Deskripsi', style: TextStyle(color: p.muted, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 6),
            desc.isEmpty
                ? Text(g.canEditInfo ? 'Belum ada deskripsi. Ketuk ikon pensil untuk menambahkan.' : 'Belum ada deskripsi.', style: TextStyle(color: p.muted))
                : LinkText(desc, style: TextStyle(color: p.text, fontSize: 16), linkColor: p.accentText),
            if (created.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(created, style: TextStyle(color: p.muted, fontSize: 12)),
            ],
          ]),
        ),
        NeoTile(
          icon: Icons.photo_library_outlined,
          title: 'Media, tautan, dan dokumen',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SharedMediaPage(groupId: g.id))),
        ),
        NeoSwitchTile(icon: Icons.volume_off_outlined, title: 'Bisukan notifikasi', value: g.muted, onChanged: (v) => patchMine({'muted': v})),
        NeoTile(icon: Icons.timer_outlined, title: 'Pesan menghilang', subtitle: disappearLabel(g.disappearSeconds), onTap: disappearMenu),
        if (g.isAdmin) ...[
          const NeoSection('Pengaturan grup'),
          NeoTile(
            icon: Icons.account_circle_outlined,
            title: 'Ring Avatar',
            subtitle: 'Bingkai foto grup ini',
            onTap: openRing,
          ),
          NeoTile(
            icon: Icons.edit_note,
            title: 'Edit info grup',
            subtitle: g.editInfo == 'admins' ? 'Hanya admin' : 'Semua anggota',
            onTap: () => choose('Siapa yang dapat mengedit info grup?', 'editInfo', g.editInfo),
          ),
          NeoTile(
            icon: Icons.chat_outlined,
            title: 'Kirim pesan',
            subtitle: g.sendMode == 'admins' ? 'Hanya admin' : 'Semua anggota',
            onTap: () => choose('Siapa yang dapat mengirim pesan?', 'sendMode', g.sendMode),
          ),
          NeoTile(
            icon: Icons.person_add_alt_outlined,
            title: 'Tambah anggota',
            subtitle: g.addMembers == 'admins' ? 'Hanya admin' : 'Semua anggota',
            onTap: () => choose('Siapa yang dapat menambah anggota?', 'addMembers', g.addMembers),
          ),
        ],
        linkCard(),
        NeoSection('${members.length} anggota'),
        if (canInvite)
          NeoRow(
            onTap: addMembers,
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle, border: Border.all(color: p.line, width: 2)),
              child: const Icon(Icons.person_add, color: Colors.white),
            ),
            title: const Text('Tambah anggota', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ...members.map(memberRow),
        const SizedBox(height: 8),
        NeoCard(
          onTap: leave,
          child: Row(children: [
            Icon(Icons.exit_to_app, color: p.bad),
            const SizedBox(width: 12),
            Text('Keluar dari grup', style: TextStyle(fontWeight: FontWeight.w800, color: p.bad)),
          ]),
        ),
        NeoCard(
          onTap: () => showGroupReport(context, g.id),
          child: Row(children: [
            Icon(Icons.thumb_down_alt_outlined, color: p.bad),
            const SizedBox(width: 12),
            Text('Laporkan grup', style: TextStyle(fontWeight: FontWeight.w800, color: p.bad)),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ edit info grup

class EditGroupPage extends StatefulWidget {
  final GroupItem group;
  const EditGroupPage({super.key, required this.group});
  @override
  State<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends State<EditGroupPage> {
  late final TextEditingController name = TextEditingController(text: widget.group.name);
  late final TextEditingController desc = TextEditingController(text: widget.group.description);
  String? newPhoto;
  bool removePhoto = false;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final g = widget.group;
    final n = name.text.trim();
    if (n.isEmpty) {
      app.toast('Nama grup tidak boleh kosong.', error: true);
      return;
    }
    final body = <String, dynamic>{};
    if (n != g.name) body['name'] = n;
    if (desc.text.trim() != g.description.trim()) body['description'] = desc.text.trim();
    setState(() => busy = true);
    try {
      if (newPhoto != null) {
        body['avatarMediaId'] = await app.api.upload(newPhoto!, 'avatar');
      } else if (removePhoto) {
        body['avatarMediaId'] = null;
      }
      if (body.isEmpty) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      await app.api.patch('/groups/${g.id}', body);
      app.loadChatsNow();
      app.toast('Info grup diperbarui.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final g = widget.group;
    final hasOld = !removePhoto && g.avatarUrl != null && g.avatarUrl!.isNotEmpty;
    Widget photo;
    if (newPhoto != null) {
      photo = Image.file(File(newPhoto!), fit: BoxFit.cover);
    } else if (hasOld) {
      photo = CachedNetworkImage(imageUrl: app.api.abs(g.avatarUrl), httpHeaders: app.api.mediaHeaders, fit: BoxFit.cover);
    } else {
      photo = const Icon(Icons.groups, size: 56, color: Color(0xFF111111));
    }
    return Scaffold(
      appBar: zAppBar(context, text: 'Edit info grup'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              final path = await _pickPhoto(context);
              if (path != null && mounted) {
                setState(() {
                  newPhoto = path;
                  removePhoto = false;
                });
              }
            },
            child: Stack(children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.yellow, border: Border.all(color: p.line, width: 3)),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: photo,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle, border: Border.all(color: p.line, width: 2)),
                  child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
        if (newPhoto != null || hasOld)
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                newPhoto = null;
                removePhoto = true;
              }),
              child: Text('Hapus foto', style: TextStyle(color: p.bad)),
            ),
          ),
        const SizedBox(height: 12),
        TextField(controller: name, maxLength: 60, decoration: neoDeco(context, hint: 'Nama grup', prefix: const Icon(Icons.edit_outlined))),
        const SizedBox(height: 8),
        TextField(controller: desc, maxLength: 500, minLines: 2, maxLines: 6, decoration: neoDeco(context, hint: 'Deskripsi grup')),
        const SizedBox(height: 16),
        NeoButton('Simpan', icon: Icons.check, busy: busy, onPressed: save),
      ]),
    );
  }
}

// ------------------------------------------------------------------ tambah anggota

class AddMembersPage extends StatefulWidget {
  final GroupItem group;
  final Set<int> existing;
  const AddMembersPage({super.key, required this.group, required this.existing});
  @override
  State<AddMembersPage> createState() => _AddMembersPageState();
}

class _AddMembersPageState extends State<AddMembersPage> {
  final Map<int, User> selected = {};
  bool busy = false;

  Future<void> add() async {
    setState(() => busy = true);
    try {
      final r = asMap(await app.api.post('/groups/${widget.group.id}/members', {'userIds': selected.keys.toList()}));
      final added = asList(r['added']).length;
      final skipped = asList(r['skipped']).length;
      if (skipped > 0) app.toast('$skipped orang tidak dapat ditambahkan.');
      if (mounted) Navigator.pop(context, added);
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = 256 - widget.group.memberCount;
    return Scaffold(
      appBar: zAppBar(context, text: 'Tambah anggota'),
      body: Column(children: [
        Expanded(child: UserPicker(selected: selected, excludeIds: widget.existing, maxSelect: room < 1 ? 1 : room, onChanged: () => setState(() {}))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: NeoButton(selected.isEmpty ? 'Pilih anggota' : 'Tambahkan (${selected.length})',
                  icon: Icons.person_add, busy: busy, onPressed: selected.isEmpty ? null : add),
            ),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ media, tautan, dokumen

class SharedMediaPage extends StatelessWidget {
  final int groupId;
  const SharedMediaPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: pal(context).yellow,
          foregroundColor: const Color(0xFF111111),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: const Text('Media, tautan, dokumen', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
          bottom: TabBar(
            labelColor: const Color(0xFF111111),
            unselectedLabelColor: const Color(0xFF5E5841),
            indicatorColor: pal(context).line,
            tabs: const [Tab(text: 'Media'), Tab(text: 'Dokumen'), Tab(text: 'Tautan')],
          ),
        ),
        body: TabBarView(children: [
          _MediaTab(groupId: groupId, kind: 'media'),
          _MediaTab(groupId: groupId, kind: 'docs'),
          _MediaTab(groupId: groupId, kind: 'links'),
        ]),
      ),
    );
  }
}

class _MediaTab extends StatefulWidget {
  final int groupId;
  final String kind;
  const _MediaTab({required this.groupId, required this.kind});
  @override
  State<_MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<_MediaTab> with AutomaticKeepAliveClientMixin {
  List<Message> items = [];
  bool loading = true;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/groups/${widget.groupId}/media?kind=${widget.kind}'));
      items = asList(r['messages']).map((m) => Message.fromJson(m)).toList();
      error = null;
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  String? firstLink(String? body) {
    if (body == null) return null;
    final m = RegExp(r'https?://[^\s<>"]+').firstMatch(body);
    return m?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = pal(context);
    if (loading) return const Spin();
    if (error != null) return EmptyState(icon: Icons.error_outline, title: 'Gagal memuat', text: error, action: NeoButton('Coba lagi', onPressed: load));
    if (items.isEmpty) {
      return EmptyState(
        icon: widget.kind == 'media' ? Icons.photo_outlined : (widget.kind == 'docs' ? Icons.insert_drive_file_outlined : Icons.link),
        title: 'Belum ada ${widget.kind == 'media' ? 'media' : (widget.kind == 'docs' ? 'dokumen' : 'tautan')}',
        text: 'Yang dibagikan di grup ini akan muncul di sini.',
      );
    }
    if (widget.kind == 'media') {
      return GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        padding: const EdgeInsets.all(3),
        children: items.where((m) => m.media != null).map((m) {
          final media = m.media!;
          if (m.type == 'video') {
            return GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VideoPage(url: media.url))),
              child: Container(color: Colors.black, child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 40)),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImageViewerPage(url: media.url))),
            child: CachedNetworkImage(
              imageUrl: app.api.abs(media.url),
              httpHeaders: app.api.mediaHeaders,
              fit: BoxFit.cover,
              placeholder: (c, u) => Container(color: p.surface2),
              errorWidget: (c, u, e) => Container(color: p.surface2, child: const Icon(Icons.broken_image)),
            ),
          );
        }).toList(),
      );
    }
    if (widget.kind == 'docs') {
      return ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 16),
        children: items.where((m) => m.media != null).map((m) {
          final media = m.media!;
          return NeoRow(
            onTap: () => openDocument(media),
            leading: const Icon(Icons.insert_drive_file, size: 32),
            title: Text(media.name ?? 'Dokumen', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${fmtSize(media.size)} · ${m.senderName} · ${dateTimeText(m.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
          );
        }).toList(),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 16),
      children: items.map((m) {
        final link = firstLink(m.body);
        if (link == null) return const SizedBox.shrink();
        return NeoRow(
          onTap: () => openLink(link),
          leading: const Icon(Icons.link, size: 30),
          title: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.accentText, fontWeight: FontWeight.w700)),
          subtitle: Text('${m.senderName} · ${dateTimeText(m.createdAt)}', style: TextStyle(color: p.muted, fontSize: 12)),
        );
      }).toList(),
    );
  }
}

// ------------------------------------------------------------------ info pesan (dibaca / diterima oleh)

class MessageInfoPage extends StatefulWidget {
  final int groupId;
  final Message message;
  const MessageInfoPage({super.key, required this.groupId, required this.message});
  @override
  State<MessageInfoPage> createState() => _MessageInfoPageState();
}

class _MessageInfoPageState extends State<MessageInfoPage> {
  List<User> readBy = [];
  List<User> deliveredTo = [];
  List<User> remaining = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/groups/${widget.groupId}/messages/${widget.message.id}/info'));
      readBy = asList(r['readBy']).map((u) => User.fromJson(u)).toList();
      deliveredTo = asList(r['deliveredTo']).map((u) => User.fromJson(u)).toList();
      remaining = asList(r['remaining']).map((u) => User.fromJson(u)).toList();
      error = null;
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  List<Widget> section(String title, IconData icon, Color color, List<User> list) {
    if (list.isEmpty) return const <Widget>[];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text('$title (${list.length})', style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
      ),
      ...list.map((u) => NeoRow(leading: Avatar(user: u, size: 40), title: NameWithBadge(u))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final m = widget.message;
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null) {
      body = EmptyState(icon: Icons.error_outline, title: 'Gagal memuat', text: error, action: NeoButton('Coba lagi', onPressed: load));
    } else {
      body = ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        NeoCard(
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          color: p.bubbleOut,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(previewText(m), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF111111), fontSize: 15)),
            const SizedBox(height: 4),
            Text(dateTimeText(m.createdAt), style: const TextStyle(color: Color(0xFF5E5841), fontSize: 12)),
          ]),
        ),
        ...section('Dibaca oleh', Icons.done_all, const Color(0xFF0B6FA8), readBy),
        ...section('Diterima oleh', Icons.done_all, p.muted, deliveredTo),
        ...section('Belum diterima', Icons.done, p.muted, remaining),
      ]);
    }
    return Scaffold(appBar: zAppBar(context, text: 'Info pesan'), body: body);
  }
}
