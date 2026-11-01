// ZARR CHAT - tab Chats: daftar percakapan, cari, chat baru, arsip, notifikasi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'chat_screen.dart';
import 'group_pages.dart';
import 'groups.dart';
import 'meta_ai.dart';
import 'models.dart';
import 'profile_view.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

/// Membuka layar chat. Memakai navigatorKey global supaya aman dipanggil dari sheet/dialog yang sudah ditutup.
void openChat(BuildContext context, int conversationId, User peer) {
  final nav = app.navKey.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute<void>(builder: (_) => ChatScreen(conversationId: conversationId, peer: peer)));
}

Future<void> openChatWithUser(BuildContext context, int userId) async {
  try {
    final r = asMap(await app.api.post('/chats', {'userId': userId}));
    final id = r['conversationId'];
    if (id is int) openChat(context, id, User.fromJson(r['peer']));
  } catch (e) {
    app.toast(errText(e), error: true);
  }
}

/// Tanda terkirim / diterima / dibaca.
class MsgTick extends StatelessWidget {
  final Message m;
  final Color? base;
  const MsgTick(this.m, {super.key, this.base});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final c = base ?? p.muted;
    if (m.state == 'sending') return Icon(Icons.access_time, size: 14, color: c);
    if (m.state == 'failed') return Icon(Icons.error_outline, size: 14, color: p.bad);
    if (m.readAt != null) return const Icon(Icons.done_all, size: 16, color: Color(0xFF0B6FA8));
    if (m.deliveredAt != null) return Icon(Icons.done_all, size: 16, color: c);
    return Icon(Icons.done, size: 15, color: c);
  }
}

/// Satu baris di daftar: chat pribadi atau grup, diurutkan berdasarkan aktivitas terakhir.
class _Entry {
  final ChatItem? chat;
  final GroupItem? group;
  final DateTime time;
  _Entry.chat(ChatItem c)
      : chat = c,
        group = null,
        time = c.last?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  _Entry.group(GroupItem g)
      : chat = null,
        group = g,
        time = g.activityTime;

  /// Kunci unik baris di daftar chat: "c:<id>" untuk chat pribadi, "g:<id>" untuk grup.
  String get key => chat != null ? 'c:${chat!.id}' : 'g:${group!.id}';
}

Widget groupRow(BuildContext context, GroupItem g, {bool compact = false, bool selected = false, bool pinned = false, VoidCallback? onTap, VoidCallback? onLongPress}) {
  final p = pal(context);
  final m = g.last;
  final meId = app.me?.id ?? 0;
  final mine = m != null && !m.isSystem && m.senderId == meId;
  final typingNames = (app.groupTyping[g.id] ?? const <int, String>{}).values.where((n) => n.isNotEmpty).toList();
  final typing = typingNames.isNotEmpty;
  return NeoRow(
    onTap: onTap ?? () => openGroup(g.id, group: g),
    onLongPress: onLongPress,
    color: selected ? p.accent.withAlpha(46) : null,
    leading: selectableAvatar(context, Avatar(url: g.avatarUrl, name: g.name, size: compact ? 44 : 48, group: true, ringStyle: g.ringStyle), selected),
    title: Row(children: [
      Expanded(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (g.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedBadge()),
        ]),
      ),
      const SizedBox(width: 6),
      Text(m == null ? '' : listTime(m.createdAt),
          style: TextStyle(fontSize: 12, color: g.unread > 0 ? p.accentText : p.muted, fontWeight: g.unread > 0 ? FontWeight.w800 : FontWeight.w500)),
    ]),
    subtitle: Row(children: [
      if (m != null && mine && !m.deleted) Padding(padding: const EdgeInsets.only(right: 4), child: MsgTick(m)),
      Expanded(
        child: Text(
          typing ? '${typingNames.first}${typingNames.length > 1 ? ' dan lainnya' : ''} sedang mengetik…' : groupPreview(g, meId),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: typing ? p.good : p.muted, fontStyle: typing ? FontStyle.italic : FontStyle.normal),
        ),
      ),
      if (g.muted) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.volume_off, size: 14, color: p.muted)),
      if (pinned) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 14, color: p.muted)),
      if (g.unread > 0)
        Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: g.muted ? p.divider : p.accent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line, width: 1.5),
          ),
          child: Text('${g.unread}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: g.muted ? p.text : Colors.white)),
        ),
    ]),
  );
}

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});
  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final search = TextEditingController();

  // ---------------------------------------------------------------- mode pilih (tekan lama, seperti WhatsApp)
  final Set<String> sel = {}; // kunci baris terpilih ("c:<id>" / "g:<id>")
  Set<String> pins = {}; // chat/grup yang disematkan di bagian atas daftar (disimpan di HP ini)
  List<String> _visibleKeys = [];
  static const int maxPins = 3;

  bool get selecting => sel.isNotEmpty;
  String get _pinKey => 'zc_chat_pins_${app.me?.id ?? 0}';
  List<ChatItem> get selChats => app.chats.where((c) => sel.contains('c:${c.id}')).toList();
  List<GroupItem> get selGroups => app.groups.where((g) => sel.contains('g:${g.id}')).toList();

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _loadPins() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final l = sp.getStringList(_pinKey) ?? const <String>[];
      if (mounted) setState(() => pins = l.toSet());
    } catch (_) {
      // sematan hanya kemudahan tampilan; gagal memuat tidak boleh mengganggu daftar chat
    }
  }

  Future<void> _savePins() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_pinKey, pins.toList());
    } catch (_) {
      // abaikan
    }
  }

  void toggleSel(String k) => setState(() {
        if (!sel.remove(k)) sel.add(k);
      });

  void longPressRow(String k) {
    HapticFeedback.mediumImpact();
    toggleSel(k);
  }

  void clearSel() => setState(sel.clear);

  void pinSelected() {
    final keys = sel.toList();
    if (keys.isEmpty) return;
    if (keys.every(pins.contains)) {
      setState(() {
        pins.removeAll(keys);
        sel.clear();
      });
      app.toast('Sematan dilepas.');
    } else {
      final add = keys.where((k) => !pins.contains(k)).toList();
      if (pins.length + add.length > maxPins) {
        app.toast('Maksimal $maxPins chat yang bisa disematkan.', error: true);
        return;
      }
      setState(() {
        pins.addAll(add);
        sel.clear();
      });
      app.toast('Chat disematkan.');
    }
    _savePins();
  }

  Future<void> muteSelected() async {
    final cs = selChats;
    final gs = selGroups;
    if (cs.isEmpty && gs.isEmpty) return;
    final to = !(cs.every((c) => c.muted) && gs.every((g) => g.muted));
    clearSel();
    var fail = 0;
    for (final c in cs) {
      try {
        await app.api.patch('/chats/${c.id}', {'muted': to});
      } catch (_) {
        fail++;
      }
    }
    for (final g in gs) {
      try {
        await app.api.patch('/groups/${g.id}/me', {'muted': to});
      } catch (_) {
        fail++;
      }
    }
    await app.loadChatsNow();
    app.toast(fail > 0 ? 'Sebagian gagal diproses.' : (to ? 'Notifikasi dibisukan.' : 'Notifikasi diaktifkan.'), error: fail > 0);
  }

  Future<void> archiveSelected() async {
    final cs = selChats;
    final gs = selGroups;
    if (cs.isEmpty && gs.isEmpty) return;
    final keys = sel.toList();
    final hadPins = pins.any(keys.contains);
    clearSel();
    var fail = 0;
    for (final c in cs) {
      try {
        await app.api.patch('/chats/${c.id}', {'archived': true});
      } catch (_) {
        fail++;
      }
    }
    for (final g in gs) {
      try {
        await app.api.patch('/groups/${g.id}/me', {'archived': true});
      } catch (_) {
        fail++;
      }
    }
    if (hadPins && mounted) {
      setState(() => pins.removeAll(keys));
      _savePins();
    }
    await app.loadChatsNow();
    app.toast(fail > 0 ? 'Sebagian gagal diproses.' : 'Percakapan diarsipkan.', error: fail > 0);
  }

  Future<void> deleteSelected() async {
    final cs = selChats;
    final gs = selGroups;
    final n = cs.length + gs.length;
    if (n == 0) return;
    final title = n == 1 ? (gs.isEmpty ? 'Hapus percakapan?' : 'Keluar dari grup?') : 'Hapus $n percakapan?';
    final text = gs.isEmpty
        ? 'Percakapan beserta seluruh pesannya dihapus dari akun Anda dan hilang dari daftar chat. Pesan baru akan memunculkannya lagi.'
        : cs.isEmpty
            ? 'Anda akan keluar dari ${gs.length == 1 ? 'grup "${gs.first.name}"' : '${gs.length} grup'} dan tidak menerima pesannya lagi.'
            : 'Percakapan pribadi dihapus dari akun Anda, dan Anda keluar dari ${gs.length} grup yang dipilih.';
    final ok = await showConfirm(context, title, text, cs.isEmpty ? 'Keluar' : 'Hapus', danger: true);
    if (!ok || !mounted) return;
    final keys = sel.toList();
    final hadPins = pins.any(keys.contains);
    clearSel();
    var fail = 0;
    for (final c in cs) {
      try {
        await app.api.delete('/chats/${c.id}');
      } catch (_) {
        fail++;
      }
    }
    for (final g in gs) {
      try {
        await app.api.post('/groups/${g.id}/leave');
      } catch (_) {
        fail++;
      }
    }
    if (hadPins && mounted) {
      setState(() => pins.removeAll(keys));
      _savePins();
    }
    await app.loadChatsNow();
    app.toast(fail > 0 ? 'Sebagian gagal diproses.' : (n == 1 ? 'Percakapan dihapus.' : '$n percakapan dihapus.'), error: fail > 0);
  }

  /// Bar atas saat ada baris terpilih: jumlah terpilih + sematkan, hapus, bisukan, arsipkan, dan menu titik tiga.
  PreferredSizeWidget selectionBar() {
    final cs = selChats;
    final gs = selGroups;
    final allPinned = sel.isNotEmpty && sel.every(pins.contains);
    final allMuted = cs.every((c) => c.muted) && gs.every((g) => g.muted);
    return zAppBar(
      context,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: clearSel),
      titleSpacing: 0,
      title: Text('${sel.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
      actions: [
        IconButton(
          tooltip: allPinned ? 'Lepas sematan' : 'Sematkan',
          icon: Icon(allPinned ? Icons.push_pin : Icons.push_pin_outlined),
          onPressed: pinSelected,
        ),
        IconButton(tooltip: 'Hapus', icon: const Icon(Icons.delete_outline), onPressed: deleteSelected),
        IconButton(
          tooltip: allMuted ? 'Aktifkan notifikasi' : 'Bisukan notifikasi',
          icon: Icon(allMuted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
          onPressed: muteSelected,
        ),
        IconButton(tooltip: 'Arsipkan', icon: const Icon(Icons.archive_outlined), onPressed: archiveSelected),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Menu',
          onSelected: (v) {
            if (v == 'all') {
              setState(() {
                sel
                  ..clear()
                  ..addAll(_visibleKeys);
              });
            } else if (v == 'profile') {
              final one = selChats;
              if (one.length == 1) showProfilePreview(context, one.first.peer, conversationId: one.first.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(value: 'all', child: Text('Pilih semua')),
            if (sel.length == 1 && selChats.length == 1) const PopupMenuItem<String>(value: 'profile', child: Text('Lihat profil')),
          ],
        ),
      ],
    );
  }

  Widget row(BuildContext context, ChatItem c) {
    final p = pal(context);
    final m = c.last;
    final mine = m != null && m.senderId == app.me?.id;
    final typing = app.typing[c.id] == true;
    final k = 'c:${c.id}';
    final isSel = sel.contains(k);
    final isPin = pins.contains(k);
    return NeoRow(
      onTap: selecting ? () => toggleSel(k) : () => openChat(context, c.id, c.peer),
      onLongPress: () => longPressRow(k),
      color: isSel ? p.accent.withAlpha(46) : null,
      leading: selectableAvatar(
          context,
          Avatar(user: c.peer, size: 48, onTap: selecting ? () => toggleSel(k) : () => showProfilePreview(context, c.peer, conversationId: c.id)),
          isSel),
      title: Row(children: [
        Expanded(child: NameWithBadge(c.peer)),
        const SizedBox(width: 6),
        Text(m == null ? '' : listTime(m.createdAt),
            style: TextStyle(fontSize: 12, color: c.unread > 0 ? p.accentText : p.muted, fontWeight: c.unread > 0 ? FontWeight.w800 : FontWeight.w500)),
      ]),
      subtitle: Row(children: [
        if (m != null && mine && !m.deleted) Padding(padding: const EdgeInsets.only(right: 4), child: MsgTick(m)),
        Expanded(
          child: Text(
            typing ? (c.peer.isBot && !c.peer.isMetaAi ? 'sedang memproses…' : 'sedang mengetik…') : previewText(m),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: typing ? p.good : p.muted, fontStyle: typing ? FontStyle.italic : FontStyle.normal),
          ),
        ),
        if (c.muted) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.volume_off, size: 14, color: p.muted)),
        if (isPin) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin, size: 14, color: p.muted)),
        if (c.unread > 0)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: c.muted ? p.divider : p.accent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line, width: 1.5),
            ),
            child: Text('${c.unread}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c.muted ? p.text : Colors.white)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        // Chat/grup yang sudah hilang dari daftar (dihapus, diarsipkan dari tempat lain) tidak ikut terpilih.
        final live = <String>{...app.chats.map((c) => 'c:${c.id}'), ...app.groups.map((g) => 'g:${g.id}')};
        sel.removeWhere((k) => !live.contains(k));
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && selecting) clearSel();
          },
          child: Scaffold(
      // Tombol bulat logo Meta AI di atas tombol "+" (chat baru), seperti WhatsApp. Disembunyikan saat mode pilih.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: selecting ? null : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        const MetaAiFab(),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.line, width: 3),
            boxShadow: [BoxShadow(color: p.line, offset: const Offset(3, 3))],
          ),
          child: FloatingActionButton(
            heroTag: 'new_chat_fab',
            elevation: 0,
            focusElevation: 0,
            hoverElevation: 0,
            highlightElevation: 0,
            backgroundColor: p.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            tooltip: 'Chat baru',
            onPressed: () => showNewChat(context),
            child: const Icon(Icons.add, size: 30),
          ),
        ),
      ]),
      appBar: selecting ? selectionBar() : zAppBar(context, text: 'Chat', actions: [
        ListenableBuilder(
          listenable: app,
          builder: (context, _) => Stack(alignment: Alignment.center, children: [
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsPage())),
            ),
            if (app.notifCount > 0)
              Positioned(
                right: 6,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line, width: 1.5)),
                  child: Text('${app.notifCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.add_comment_outlined),
          onPressed: () => showMenuSheet(context, [
            MenuItem(Icons.chat_outlined, 'Chat baru', () => showNewChat(context)),
            MenuItem(Icons.group_add_outlined, 'Grup baru', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreateGroupPage()))),
            MenuItem(Icons.pin_outlined, 'Gabung dengan kode', () => showJoinByLinkDialog(context)),
          ]),
        ),
      ]),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final t = search.text.trim().toLowerCase();
          final meId = app.me?.id ?? 0;
          final entries = <_Entry>[
            ...app.chats.where((c) => t.isEmpty || c.peer.username.toLowerCase().contains(t) || previewText(c.last).toLowerCase().contains(t)).map(_Entry.chat),
            ...app.groups.where((g) => t.isEmpty || g.name.toLowerCase().contains(t) || groupPreview(g, meId).toLowerCase().contains(t)).map(_Entry.group),
          ]..sort((a, b) {
              // Chat yang disematkan selalu di atas; sisanya urut waktu terbaru.
              final pa = pins.contains(a.key);
              final pb = pins.contains(b.key);
              if (pa != pb) return pa ? -1 : 1;
              return b.time.compareTo(a.time);
            });
          _visibleKeys = entries.map((e) => e.key).toList();
          final archivedCount = app.archived.length + app.archivedGroups.length;
          final ann = app.cfg?.announcements ?? const <Announcement>[];
          return Column(children: [
            if (ann.isNotEmpty)
              NeoCard(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                color: p.surface2,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ann.first.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(ann.first.body),
                    ]),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: neoDeco(context, hint: 'Cari percakapan atau pengguna', prefix: const Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: app.loadChatsNow,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 2, bottom: 170),
                  children: [
                    if (t.isEmpty && archivedCount > 0)
                      NeoRow(
                        leading: const Icon(Icons.archive_outlined, size: 28),
                        title: const Text('Diarsipkan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        trailing: Text('$archivedCount', style: TextStyle(color: p.text, fontWeight: FontWeight.w900)),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ArchivedPage())),
                      ),
                    if (entries.isEmpty && t.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: EmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: 'Belum ada percakapan',
                          text: 'Mulai chat pertama Anda dengan mencari nama pengguna atau nomor telepon, atau buat grup baru.',
                          action: NeoButton('Chat baru', icon: Icons.add, onPressed: () => showNewChat(context)),
                        ),
                      ),
                    ...entries.map((e) => e.group != null
                        ? groupRow(context, e.group!,
                            selected: sel.contains(e.key),
                            pinned: pins.contains(e.key),
                            onTap: selecting ? () => toggleSel(e.key) : null,
                            onLongPress: () => longPressRow(e.key))
                        : row(context, e.chat!)),
                    if (t.isNotEmpty)
                      NeoRow(
                        leading: const Icon(Icons.search, size: 28),
                        title: Text('Cari pengguna "${search.text.trim()}"', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('Cari berdasarkan nama atau nomor', style: TextStyle(color: p.muted)),
                        onTap: () => showNewChat(context, initial: search.text.trim()),
                      ),
                  ],
                ),
              ),
            ),
          ]);
        },
      ),
    ));
      },
    );
  }
}

class ArchivedPage extends StatelessWidget {
  const ArchivedPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: zAppBar(context, text: 'Diarsipkan'),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.archived.isEmpty && app.archivedGroups.isEmpty) {
            return const EmptyState(icon: Icons.archive_outlined, title: 'Tidak ada arsip', text: 'Percakapan yang diarsipkan muncul di sini.');
          }
          return ListView(
            padding: const EdgeInsets.only(top: 14, bottom: 20),
            children: [
              ...app.archivedGroups.map((g) => groupRow(context, g, compact: true)),
              ...app.archived.map((c) => NeoRow(
                    leading: Avatar(user: c.peer, size: 44),
                    title: NameWithBadge(c.peer),
                    subtitle: Text(previewText(c.last), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
                    onTap: () => openChat(context, c.id, c.peer),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationItem> items = [];
  List<Announcement> announcements = [];
  bool loading = true;
  String? error;
  final Set<int> sel = {}; // id notifikasi terpilih (mode pilih seperti WhatsApp: tekan lama)

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
          ..addAll(items.map((n) => n.id));
      });

  Future<void> deleteSelected() async {
    final ids = sel.toList();
    if (ids.isEmpty) return;
    final ok = await showConfirm(context, ids.length == 1 ? 'Hapus notifikasi ini?' : 'Hapus ${ids.length} notifikasi?', 'Notifikasi yang dipilih dihapus dari daftar Anda.', 'Hapus', danger: true);
    if (!ok || !mounted) return;
    try {
      await app.api.post('/notifications/delete', {'ids': ids});
      if (!mounted) return;
      setState(() {
        items.removeWhere((n) => ids.contains(n.id));
        sel.clear();
      });
      app.toast(ids.length == 1 ? 'Notifikasi dihapus.' : '${ids.length} notifikasi dihapus.');
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Bar atas saat ada notifikasi terpilih: jumlah terpilih + Hapus + menu titik tiga (Pilih semua).
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
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/notifications'));
      items = asList(r['items']).map((e) => NotificationItem.fromJson(e)).toList();
      announcements = asList(r['announcements']).map((e) => Announcement.fromJson(e)).toList();
      sel.removeWhere((id) => !items.any((n) => n.id == id));
      await app.api.post('/notifications/read');
      app.notifCount = 0;
      app.refresh();
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null) {
      body = EmptyState(icon: Icons.error_outline, title: 'Gagal memuat', text: error);
    } else if (items.isEmpty && announcements.isEmpty) {
      body = const EmptyState(icon: Icons.notifications_none, title: 'Belum ada notifikasi', text: 'Panggilan tak terjawab dan pengumuman muncul di sini.');
    } else {
      body = ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 20), children: [
        ...announcements.map((a) => NeoCard(
              color: p.surface2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(a.body),
              ]),
            )),
        ...items.map((n) {
          final isSel = sel.contains(n.id);
          return NeoCard(
            color: isSel ? p.accent.withAlpha(46) : (n.read ? p.surface : p.surface2),
            onTap: selecting ? () => toggleSel(n.id) : null,
            onLongPress: () => longPressRow(n.id),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 1),
                  child: Icon(isSel ? Icons.check_circle : Icons.radio_button_unchecked, color: isSel ? p.good : p.muted, size: 22),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  if ((n.body ?? '').isNotEmpty) Text(n.body!, style: TextStyle(color: p.muted)),
                  Text(dateTimeText(n.createdAt), style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
              ),
            ]),
          );
        }),
      ]);
    }
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clearSel();
      },
      child: Scaffold(appBar: selecting ? selectionBar() : zAppBar(context, text: 'Notifikasi'), body: body),
    );
  }
}

void showNewChat(BuildContext context, {String initial = ''}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal(context).surface,
    builder: (_) => _NewChatSheet(initial: initial),
  );
}

class _NewChatSheet extends StatefulWidget {
  final String initial;
  const _NewChatSheet({required this.initial});
  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  late final TextEditingController input = TextEditingController(text: widget.initial);
  Timer? timer;
  List<User> users = [];
  bool loading = false;
  String? error;
  String last = '';

  @override
  void initState() {
    super.initState();
    if (widget.initial.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) run();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  void onChanged(String _) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 350), run);
  }

  Future<void> run() async {
    final t = input.text.trim();
    last = t;
    if (t.length < 2) {
      setState(() {
        users = [];
        error = null;
        loading = false;
      });
      return;
    }
    setState(() => loading = true);
    try {
      final r = asMap(await app.api.get('/users/search?q=${Uri.encodeQueryComponent(t)}'));
      if (!mounted || last != t) return;
      setState(() {
        users = asList(r['users']).map((u) => User.fromJson(u)).toList();
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
                const Expanded(child: Text('Chat baru', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
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
                    child: Text('Ketik minimal 2 karakter. Untuk mencari nomor, pakai format internasional, misalnya +628123456789.',
                        style: TextStyle(color: p.muted)),
                  );
                }
                if (loading) return const Spin(label: 'Mencari…');
                if (error != null) return EmptyState(icon: Icons.error_outline, title: 'Gagal mencari', text: error);
                if (users.isEmpty) {
                  return const EmptyState(
                      icon: Icons.search_off, title: 'Pengguna tidak ditemukan', text: 'Pastikan nama atau nomornya benar dan orang tersebut sudah mendaftar.');
                }
                return ListView(
                  padding: const EdgeInsets.only(top: 14, bottom: 14),
                  children: users
                      .map((u) => NeoRow(
                            leading: Avatar(user: u, size: 44),
                            title: NameWithBadge(u),
                            subtitle: Text(u.about, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
                            onTap: () async {
                              final nav = Navigator.of(context);
                              try {
                                final r = asMap(await app.api.post('/chats', {'userId': u.id}));
                                final id = r['conversationId'];
                                final peer = User.fromJson(r['peer']);
                                nav.pop();
                                if (id is int) openChat(context, id, peer);
                              } catch (e) {
                                app.toast(errText(e), error: true);
                              }
                            },
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
