// ZARR CHAT - fitur grup (seperti WhatsApp): tautan undangan, teks pemberitahuan, mention, pemilih anggota,
// dialog teruskan/kirim, laporan, dan halaman "Gabung grup".
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'auth.dart';
import 'config.dart';
import 'group_chat.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

// ------------------------------------------------------------------ tautan undangan

// Kode undangan sekarang berupa 6 atau 8 angka (dipilih acak oleh server) sehingga domain/port tidak ikut terlihat.
// Kode lama (huruf+angka, 10-40 karakter) tetap dikenali supaya tautan lama tidak error.
final RegExp _codeRe = RegExp(r'^(\d{6}|\d{8}|[A-Za-z0-9_-]{10,40})$');
final RegExp _inviteTextRe = RegExp(r'Kode undangan grup:\s*(\d{6}|\d{8})(?!\d)');

/// Teks undangan yang dibagikan: hanya berisi nama grup dan kode angka (tanpa domain/port).
String inviteText(String groupName, String code) => 'Gabung ke grup "$groupName" di ZARR CHAT.\nKode undangan grup: $code';

/// Mengambil kode undangan dari tautan. [anyHost] = true menerima domain mana pun (saat ditempel manual).
String? inviteCodeFromUrl(String url, {bool anyHost = false}) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme) return null;
  if (!anyHost) {
    final base = Uri.tryParse(kBaseUrl);
    if (base == null || u.host != base.host) return null;
  }
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length == 2 && segs[0] == 'g' && _codeRe.hasMatch(segs[1])) return segs[1];
  return null;
}

/// Kode undangan dari teks yang ditempel pengguna: kodenya saja, pesan undangan lengkap, atau tautan lama.
String? parseInviteInput(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  final inText = _inviteTextRe.firstMatch(t);
  if (inText != null) return inText.group(1);
  final fromUrl = inviteCodeFromUrl(t, anyHost: true);
  if (fromUrl != null) return fromUrl;
  return _codeRe.hasMatch(t) ? t : null;
}

/// Kode undangan pertama yang ada di dalam sebuah pesan (untuk kartu pratinjau grup).
String? inviteCodeInText(String? text) {
  if (text == null) return null;
  final inText = _inviteTextRe.firstMatch(text);
  if (inText != null) return inText.group(1);
  if (!text.contains('/g/')) return null;
  for (final m in RegExp(r'https?://[^\s<>"]+').allMatches(text)) {
    final c = inviteCodeFromUrl(m.group(0)!);
    if (c != null) return c;
  }
  return null;
}

// ------------------------------------------------------------------ membuka grup

void openGroup(int groupId, {GroupItem? group}) {
  final nav = app.navKey.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute<void>(builder: (_) => GroupChatScreen(groupId: groupId, initial: group ?? app.groupById(groupId))));
}

void openGroupInvite(String code) {
  final nav = app.navKey.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute<void>(builder: (_) => JoinGroupPage(code: code)));
}

/// Dialog "Gabung dengan kode": masukkan kode angka undangan (boleh juga menempel pesan undangan).
void showJoinByLinkDialog(BuildContext context) {
  final c = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Gabung dengan kode', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Masukkan kode undangan grup (6 atau 8 angka) dari admin grup.', style: TextStyle(color: pal(ctx).muted)),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: neoDeco(ctx, hint: 'Contoh: 483920', suffix: IconButton(
              icon: const Icon(Icons.content_paste),
              tooltip: 'Tempel',
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) c.text = d!.text!.trim();
              },
            )),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              final code = parseInviteInput(c.text);
              if (code == null) {
                app.toast('Kode grup tidak valid. Masukkan 6 atau 8 angka.', error: true);
                return;
              }
              Navigator.pop(ctx);
              openGroupInvite(code);
            },
            child: const Text('Lanjut', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      );
    },
  );
}

// ------------------------------------------------------------------ teks pemberitahuan sistem

int _idOf(dynamic v) => v is int ? v : (v is num ? v.toInt() : (int.tryParse('$v') ?? 0));

String disappearLabel(int sec) {
  if (sec >= 7776000) return '90 hari';
  if (sec >= 604800) return '7 hari';
  if (sec >= 86400) return '24 jam';
  return 'Mati';
}

String _nameList(List<dynamic> list, int meId) {
  final out = <String>[];
  for (final t in list) {
    final m = asMap(t);
    final n = _idOf(m['id']) == meId ? 'Anda' : (m['username'] ?? '').toString();
    if (n.isNotEmpty) out.add(n);
  }
  if (out.isEmpty) return '';
  if (out.length == 1) return out.first;
  return '${out.sublist(0, out.length - 1).join(', ')} dan ${out.last}';
}

/// Kalimat pemberitahuan di tengah chat grup ("Anda membuat grup", "Ani menambahkan Budi", dst.).
String sysText(Message m, int meId) {
  final s = m.sys;
  if (s == null) return '';
  final event = (s['event'] ?? '').toString();
  final extra = asMap(s['extra']);
  final actorMap = s['actor'] is Map ? asMap(s['actor']) : null;
  final actor = actorMap == null ? '' : (_idOf(actorMap['id']) == meId ? 'Anda' : (actorMap['username'] ?? '').toString());
  final targets = _nameList(asList(s['targets']), meId);
  switch (event) {
    case 'created':
      return '$actor membuat grup "${extra['name'] ?? ''}"';
    case 'added':
      return '$actor menambahkan $targets';
    case 'removed':
      return '$actor mengeluarkan $targets';
    case 'left':
      return '$actor keluar dari grup';
    case 'joined_link':
      return '$actor bergabung lewat kode grup';
    case 'promoted':
      return actorMap == null ? '$targets sekarang menjadi admin' : '$actor menjadikan $targets admin';
    case 'demoted':
      return '$actor menghapus $targets dari admin';
    case 'rename':
      return '$actor mengubah nama grup menjadi "${extra['name'] ?? ''}"';
    case 'description':
      return '$actor mengubah deskripsi grup';
    case 'icon':
      return '$actor mengubah ikon grup';
    case 'icon_removed':
      return '$actor menghapus ikon grup';
    case 'settings':
      final key = (extra['key'] ?? '').toString();
      final admins = extra['value'] == 'admins';
      String what;
      if (key == 'send_mode') {
        what = admins ? 'hanya admin yang dapat mengirim pesan' : 'semua anggota dapat mengirim pesan';
      } else if (key == 'edit_info') {
        what = admins ? 'hanya admin yang dapat mengedit info grup' : 'semua anggota dapat mengedit info grup';
      } else {
        what = admins ? 'hanya admin yang dapat menambahkan anggota' : 'semua anggota dapat menambahkan anggota';
      }
      return '$actor mengatur agar $what';
    case 'disappear':
      final sec = _idOf(extra['seconds']);
      return sec > 0
          ? '$actor menyalakan pesan menghilang. Pesan baru akan hilang setelah ${disappearLabel(sec)}.'
          : '$actor mematikan pesan menghilang.';
    default:
      return '';
  }
}

/// Satu baris pratinjau pesan terakhir untuk daftar chat grup ("Ani: halo").
String groupPreview(GroupItem g, int meId) {
  final m = g.last;
  if (m == null) return '';
  if (m.isSystem) return sysText(m, meId);
  final who = m.senderId == meId ? 'Anda' : (m.senderName.isEmpty ? '' : m.senderName);
  if (m.deleted) return who.isEmpty ? 'Pesan ini dihapus' : '$who: Pesan ini dihapus';
  final text = previewText(m);
  return who.isEmpty ? text : '$who: $text';
}

// ------------------------------------------------------------------ warna nama pengirim

const List<Color> _nameLight = [
  Color(0xFFC7102F), Color(0xFF0B6FA8), Color(0xFF157A31), Color(0xFF8E24AA), Color(0xFFD35400),
  Color(0xFF00796B), Color(0xFF6D4C41), Color(0xFF3949AB), Color(0xFFAD1457), Color(0xFF558B2F),
];
const List<Color> _nameDark = [
  Color(0xFFFF7088), Color(0xFF4DB6F5), Color(0xFF5FD27C), Color(0xFFCE93D8), Color(0xFFFFAB66),
  Color(0xFF4DD0C0), Color(0xFFBCAAA4), Color(0xFF9FA8DA), Color(0xFFF48FB1), Color(0xFFAED581),
];

/// Warna nama pengirim yang tetap untuk tiap anggota (seperti grup WhatsApp).
Color senderColor(BuildContext context, int userId) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final list = dark ? _nameDark : _nameLight;
  return list[userId.abs() % list.length];
}

// ------------------------------------------------------------------ teks dengan mention & tautan

class GroupText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final Color mentionColor;
  final List<String> names; // nama anggota untuk mengenali @mention
  final String myName;
  const GroupText(this.text,
      {super.key, required this.style, required this.linkColor, required this.mentionColor, this.names = const <String>[], this.myName = ''});
  @override
  State<GroupText> createState() => _GroupTextState();
}

class _GroupTextState extends State<GroupText> {
  final List<TapGestureRecognizer> _recs = [];

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

  RegExp _pattern() {
    const urlPart = r'(https?://[^\s<>"]+)';
    final names = widget.names.where((n) => n.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty || !widget.text.contains('@')) return RegExp(urlPart);
    final alts = names.map(RegExp.escape).join('|');
    return RegExp('$urlPart|(@(?:$alts))(?![\\p{L}\\p{N}_])', unicode: true);
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _pattern().allMatches(widget.text)) {
      if (m.start > last) spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      final url = m.group(1);
      if (url != null) {
        final rec = TapGestureRecognizer()..onTap = () => openLink(url);
        _recs.add(rec);
        spans.add(TextSpan(
          text: url,
          recognizer: rec,
          style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline, fontWeight: FontWeight.w700),
        ));
      } else {
        final mention = m.group(0)!;
        final mine = widget.myName.isNotEmpty && mention.toLowerCase() == '@${widget.myName}'.toLowerCase();
        spans.add(TextSpan(
          text: mention,
          style: TextStyle(color: widget.mentionColor, fontWeight: FontWeight.w800, backgroundColor: mine ? widget.mentionColor.withAlpha(40) : null),
        ));
      }
      last = m.end;
    }
    if (last < widget.text.length) spans.add(TextSpan(text: widget.text.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

// ------------------------------------------------------------------ kartu undangan grup di dalam chat

final Map<String, Future<Map<String, dynamic>?>> _previewCache = {};

Future<Map<String, dynamic>?> fetchInvitePreview(String code, {bool refresh = false}) {
  if (refresh) _previewCache.remove(code);
  return _previewCache.putIfAbsent(code, () async {
    try {
      final r = asMap(await app.api.get('/groups/join/$code'));
      return asMap(r['preview']);
    } catch (_) {
      _previewCache.remove(code); // gagal sementara: coba lagi saat kartu dibuka berikutnya
      return null;
    }
  });
}

/// Kartu pratinjau grup untuk pesan yang berisi tautan undangan (seperti WhatsApp).
class InviteCard extends StatelessWidget {
  final String code;
  final Color fg;
  const InviteCard({super.key, required this.code, required this.fg});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder<Map<String, dynamic>?>(
      future: fetchInvitePreview(code),
      builder: (context, snap) {
        final pv = snap.data;
        if (snap.connectionState != ConnectionState.done || pv == null) return const SizedBox.shrink();
        final already = pv['alreadyMember'] == true;
        final count = pv['memberCount'] is int ? pv['memberCount'] as int : 0;
        return GestureDetector(
          onTap: () {
            if (already) {
              final id = pv['id'];
              if (id is int) {
                openGroup(id);
                return;
              }
            }
            openGroupInvite(code);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black.withAlpha(20), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Avatar(url: pv['avatarUrl'] as String?, name: (pv['name'] ?? '?').toString(), size: 44, group: true, ringStyle: (pv['ringStyle'] ?? 'comic').toString()),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((pv['name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
                  Text('Undangan grup · $count anggota', style: TextStyle(color: p.muted, fontSize: 12)),
                  Text(already ? 'Buka grup' : 'Gabung grup', style: TextStyle(color: p.accentText, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ halaman "Gabung grup"

class JoinGroupPage extends StatefulWidget {
  final String code;
  const JoinGroupPage({super.key, required this.code});
  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  Map<String, dynamic>? pv;
  String? error;
  bool loading = true;
  bool joining = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = asMap(await app.api.get('/groups/join/${widget.code}'));
      pv = asMap(r['preview']);
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> join() async {
    setState(() => joining = true);
    try {
      final r = asMap(await app.api.post('/groups/join/${widget.code}'));
      final g = GroupItem.fromJson(r['group']);
      _previewCache.remove(widget.code);
      await app.loadChatsNow();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => GroupChatScreen(groupId: g.id, initial: g)));
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null || pv == null) {
      body = EmptyState(
        icon: Icons.link_off,
        title: 'Kode tidak dapat dipakai',
        text: error ?? 'Kode grup tidak valid atau sudah diatur ulang.',
        action: NeoButton('Coba lagi', onPressed: load),
      );
    } else {
      final g = pv!;
      final members = asList(g['members']).map((m) => User.fromJson(m)).toList();
      final count = g['memberCount'] is int ? g['memberCount'] as int : members.length;
      final already = g['alreadyMember'] == true;
      final full = g['full'] == true;
      final desc = (g['description'] ?? '').toString().trim();
      body = ListView(padding: const EdgeInsets.all(18), children: [
        const SizedBox(height: 8),
        Center(child: Avatar(url: g['avatarUrl'] as String?, name: (g['name'] ?? '?').toString(), size: 120, group: true, ringStyle: (g['ringStyle'] ?? 'comic').toString())),
        const SizedBox(height: 14),
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text((g['name'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            if (g['isVerified'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: VerifiedBadge(size: 22)),
          ]),
        ),
        const SizedBox(height: 4),
        Center(child: Text('Grup · $count anggota', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 14),
          NeoCard(child: Text(desc)),
        ],
        if (members.isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: members.map((u) => Avatar(user: u, size: 38)).toList(),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              members.length > 3 ? '${members.take(3).map((u) => u.username).join(', ')} dan ${count - 3} lainnya' : members.map((u) => u.username).join(', '),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 22),
        if (already)
          NeoButton('Buka grup', icon: Icons.chat_bubble_outline, onPressed: () {
            final id = g['id'];
            if (id is int) {
              Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => GroupChatScreen(groupId: id, initial: app.groupById(id))));
            }
          })
        else if (full)
          Center(child: Text('Grup ini sudah penuh.', style: TextStyle(color: p.bad, fontWeight: FontWeight.w800)))
        else
          NeoButton('Gabung grup', icon: Icons.login, busy: joining, onPressed: join),
        const SizedBox(height: 10),
        Center(child: Text('Dengan bergabung, Anda dapat melihat pesan setelah Anda masuk.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12))),
      ]);
    }
    return Scaffold(appBar: zAppBar(context, text: 'Undangan grup'), body: body);
  }
}

// ------------------------------------------------------------------ pilih tujuan (teruskan / kirim tautan)

class _Target {
  final String kind; // 'chat' | 'group'
  final int id;
  final String name;
  final Widget avatar;
  _Target(this.kind, this.id, this.name, this.avatar);
  String get key => '$kind:$id';
}

/// Dialog pilih percakapan/grup tujuan (maksimal 5). Mengembalikan [{kind, id}] atau null bila dibatalkan.
Future<List<Map<String, dynamic>>?> showTargetPicker(BuildContext context, {required String title, required String confirm}) {
  final entries = <_Target>[];
  for (final c in [...app.chats, ...app.archived]) {
    entries.add(_Target('chat', c.id, c.peer.username, Avatar(user: c.peer, size: 36)));
  }
  for (final g in [...app.groups, ...app.archivedGroups]) {
    if (!g.canSend) continue;
    entries.add(_Target('group', g.id, g.name, Avatar(url: g.avatarUrl, name: g.name, size: 36, group: true, ringStyle: g.ringStyle)));
  }
  final picked = <String>{};
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: double.maxFinite,
          child: entries.isEmpty
              ? const Text('Belum ada percakapan atau grup.')
              : ListView(
                  shrinkWrap: true,
                  children: entries
                      .map((t) => CheckboxListTile(
                            value: picked.contains(t.key),
                            title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(t.kind == 'group' ? 'Grup' : 'Chat', style: TextStyle(color: pal(ctx).muted, fontSize: 12)),
                            secondary: t.avatar,
                            onChanged: (v) {
                              if (v == true) {
                                if (picked.length >= 5) {
                                  app.toast('Maksimal 5 tujuan.');
                                  return;
                                }
                                picked.add(t.key);
                              } else {
                                picked.remove(t.key);
                              }
                              setD(() {});
                            },
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
            onPressed: picked.isEmpty
                ? null
                : () => Navigator.pop(
                    ctx,
                    entries.where((t) => picked.contains(t.key)).map((t) => <String, dynamic>{'kind': t.kind, 'id': t.id}).toList()),
            child: Text(confirm, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    ),
  );
}

/// Meneruskan pesan dari chat pribadi ([source] = 'chat') atau grup ([source] = 'group') ke chat/grup lain.
Future<void> showForwardDialog(BuildContext context, {required String source, int? groupId, required List<int> ids}) async {
  final targets = await showTargetPicker(context, title: 'Teruskan ke…', confirm: 'Teruskan');
  if (targets == null || targets.isEmpty) return;
  try {
    await app.emit('forward:send', {'source': source, 'groupId': groupId, 'ids': ids, 'targets': targets});
    app.toast('Pesan diteruskan.');
    app.loadChats();
  } catch (e) {
    app.toast(errText(e), error: true);
  }
}

/// Menu bagikan kode undangan: salin, kirim lewat ZARR CHAT, WhatsApp, Telegram.
void shareInviteSheet(BuildContext context, GroupItem g) {
  final code = g.inviteCode;
  if (code == null || code.isEmpty) {
    app.toast('Kode grup tidak tersedia.', error: true);
    return;
  }
  final text = inviteText(g.name, code);
  showMenuSheet(context, [
    MenuItem(Icons.pin_outlined, 'Salin kode', () {
      Clipboard.setData(ClipboardData(text: code));
      app.toast('Kode grup disalin.');
    }),
    MenuItem(Icons.send_outlined, 'Kirim lewat ZARR CHAT', () async {
      final ctx = app.navKey.currentContext;
      if (ctx == null) return;
      final targets = await showTargetPicker(ctx, title: 'Kirim kode ke…', confirm: 'Kirim');
      if (targets == null || targets.isEmpty) return;
      var failed = 0;
      for (final t in targets) {
        final isGroup = t['kind'] == 'group';
        try {
          await app.emit(isGroup ? 'group:send' : 'message:send', {
            isGroup ? 'groupId' : 'conversationId': t['id'],
            'type': 'text',
            'body': text,
            'clientId': newClientId(),
          });
        } catch (_) {
          failed++;
        }
      }
      app.toast(failed == 0 ? 'Kode terkirim.' : 'Sebagian kode gagal terkirim.', error: failed > 0);
      app.loadChats();
    }),
    MenuItem(Icons.chat_outlined, 'Bagikan lewat WhatsApp', () => openLink('https://wa.me/?text=${Uri.encodeComponent(text)}')),
    MenuItem(Icons.near_me_outlined, 'Bagikan lewat Telegram', () => openLink('https://t.me/share/url?url=${Uri.encodeComponent(text)}')),
  ], title: 'Bagikan kode grup');
}

// ------------------------------------------------------------------ laporan

/// Dialog laporan untuk grup ([userId] dan [messageId] kosong), anggota, atau satu pesan.
void showGroupReport(BuildContext context, int groupId, {int? userId, int? messageId, String title = 'Laporkan grup'}) {
  String reason = 'spam';
  final det = TextEditingController();
  const reasons = {
    'spam': 'Spam',
    'pelecehan': 'Pelecehan',
    'penipuan': 'Penipuan',
    'konten_tidak_pantas': 'Konten tidak pantas',
    'lainnya': 'Lainnya',
  };
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(messageId != null
                ? 'Pesan yang dilaporkan akan dibagikan kepada administrator.'
                : 'Administrator akan meninjau laporan Anda. Isi chat tidak dibagikan kecuali Anda melaporkan pesan tertentu.'),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: reason,
              isExpanded: true,
              items: reasons.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setD(() => reason = v ?? 'spam'),
            ),
            TextField(controller: det, maxLength: 450, maxLines: 3, decoration: neoDeco(ctx, hint: 'Detail tambahan (opsional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              final body = <String, dynamic>{'reason': reason, 'details': det.text};
              if (userId != null) body['userId'] = userId;
              if (messageId != null) body['messageId'] = messageId;
              Navigator.pop(ctx);
              try {
                await app.api.post('/groups/$groupId/report', body);
                app.toast('Laporan terkirim. Terima kasih.');
              } catch (e) {
                app.toast(errText(e), error: true);
              }
            },
            child: const Text('Kirim laporan', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ pemilih anggota (buat grup & tambah anggota)

class UserPicker extends StatefulWidget {
  final Map<int, User> selected; // dimiliki induk; diubah di sini lalu [onChanged] dipanggil
  final VoidCallback onChanged;
  final Set<int> excludeIds;
  final int maxSelect;
  const UserPicker({super.key, required this.selected, required this.onChanged, this.excludeIds = const <int>{}, this.maxSelect = 255});
  @override
  State<UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<UserPicker> {
  final TextEditingController search = TextEditingController();
  Timer? timer;
  List<User> results = [];
  bool loading = false;
  String? error;
  String last = '';

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  List<User> contacts() {
    final seen = <int>{};
    final out = <User>[];
    for (final c in app.chats) {
      final u = c.peer;
      if (u.id == app.me?.id || widget.excludeIds.contains(u.id) || !seen.add(u.id)) continue;
      out.add(u);
    }
    out.sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
    return out;
  }

  void onChanged(String _) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 350), run);
    setState(() {});
  }

  Future<void> run() async {
    final t = search.text.trim();
    last = t;
    if (t.length < 2) {
      setState(() {
        results = [];
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
        results = asList(r['users']).map((u) => User.fromJson(u)).where((u) => !widget.excludeIds.contains(u.id)).toList();
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

  void toggle(User u) {
    if (widget.selected.containsKey(u.id)) {
      widget.selected.remove(u.id);
    } else {
      if (widget.selected.length >= widget.maxSelect) {
        app.toast('Maksimal ${widget.maxSelect} anggota.');
        return;
      }
      widget.selected[u.id] = u;
    }
    setState(() {});
    widget.onChanged();
  }

  Widget chip(User u) {
    final p = pal(context);
    return GestureDetector(
      onTap: () => toggle(u),
      child: SizedBox(
        width: 66,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Avatar(user: u, size: 44),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle, border: Border.all(color: p.line, width: 1.5)),
                child: const Icon(Icons.close, size: 14),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(u.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget row(User u) {
    final p = pal(context);
    final on = widget.selected.containsKey(u.id);
    return NeoRow(
      onTap: () => toggle(u),
      color: on ? p.surface2 : null,
      leading: Avatar(user: u, size: 44),
      title: NameWithBadge(u),
      subtitle: Text(u.about, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
      trailing: Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, color: on ? p.good : p.muted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final typed = search.text.trim().length >= 2;
    Widget list;
    if (typed) {
      if (loading) {
        list = const Spin(label: 'Mencari…');
      } else if (error != null) {
        list = EmptyState(icon: Icons.error_outline, title: 'Gagal mencari', text: error);
      } else if (results.isEmpty) {
        list = const EmptyState(icon: Icons.search_off, title: 'Pengguna tidak ditemukan', text: 'Pastikan nama atau nomornya benar dan orang tersebut sudah mendaftar.');
      } else {
        list = ListView(padding: const EdgeInsets.only(top: 4, bottom: 12), children: results.map(row).toList());
      }
    } else {
      final cs = contacts();
      list = ListView(padding: const EdgeInsets.only(top: 4, bottom: 12), children: [
        const SectionTitle('Kontak dari chat Anda'),
        if (cs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text('Belum ada kontak. Ketik nama atau nomor (+62…) di kolom cari untuk menemukan pengguna.', style: TextStyle(color: p.muted)),
          ),
        ...cs.map(row),
      ]);
    }
    return Column(children: [
      if (widget.selected.isNotEmpty)
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: widget.selected.values.map(chip).toList(),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: TextField(
          controller: search,
          onChanged: onChanged,
          decoration: neoDeco(context, hint: 'Cari nama atau nomor (+62…)', prefix: const Icon(Icons.search)),
        ),
      ),
      Expanded(child: list),
    ]);
  }
}
