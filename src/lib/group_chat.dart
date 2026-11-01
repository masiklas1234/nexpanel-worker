// ZARR CHAT - layar chat grup (seperti grup WhatsApp): nama & foto pengirim, pemberitahuan sistem,
// balas/edit/hapus/reaksi/sematkan/teruskan, mention (@nama), tautan, centang terkirim/dibaca.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'api.dart';
import 'auth.dart';
import 'chat_screen.dart';
import 'chats_tab.dart';
import 'group_pages.dart';
import 'groups.dart';
import 'media.dart';
import 'models.dart';
import 'profile_view.dart';
import 'push.dart';
import 'state.dart';
import 'stickers.dart';
import 'theme.dart';
import 'util.dart';
import 'wallpaper.dart';
import 'widgets.dart';

const List<String> _emoji = [
  '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😅', '😉', '🙂', '🙃', '😴', '😭', '😢', '😡', '🤯', '😱', '🥳',
  '🥰', '😇', '🤗', '🙄', '😬', '😏', '🤝', '👍', '👎', '👏', '🙌', '🙏', '💪', '👀', '🔥', '✨', '🎉', '💯', '❤️', '🧡',
  '💛', '💚', '💙', '💜', '🖤', '💔', '⭐', '✅', '❌', '❓', '❗', '🎵', '📷', '📍', '🍕', '🍔', '☕', '🍰', '🎂', '🎁',
  '🌹', '🌞', '🌙', '⚽', '🎮', '🚗', '✈️', '🏠', '📱', '💻',
];

Widget groupChatRoute(GroupItem g) => GroupChatScreen(groupId: g.id, initial: g);

class GroupChatScreen extends StatefulWidget {
  final int groupId;
  final GroupItem? initial;
  const GroupChatScreen({super.key, required this.groupId, this.initial});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> with WidgetsBindingObserver {
  late GroupItem group = widget.initial ?? GroupItem(id: widget.groupId);
  List<GroupMember> members = [];
  List<Message> messages = [];
  List<Message> pinned = [];
  bool hasMore = false;
  bool loading = true;
  String? error;

  Message? reply;
  Message? editing;
  final TextEditingController input = TextEditingController();
  final FocusNode focus = FocusNode();
  final ScrollController scroll = ScrollController();
  final Map<int, GlobalKey> keys = {};
  final GlobalKey listAreaKey = GlobalKey(); // area daftar pesan (acuan posisi pil reaksi)
  int flashId = 0;
  final Set<int> selected = {};
  int _localSeq = 0;
  bool hasText = false;
  bool panelOpen = false;
  int panelTab = 0;
  int lastReadSent = 0;
  int dividerBefore = 0; // id pesan pertama yang belum dibaca (untuk garis "pesan belum dibaca")
  int dividerCount = 0;
  bool dividerSet = false;
  String? mentionQuery; // teks setelah "@" yang sedang diketik, null bila tidak sedang menyebut

  StreamSubscription<SocketEvent>? sub;
  Timer? typingTimer;
  int lastTypingSent = 0;

  // rekam suara
  final AudioRecorder rec = AudioRecorder();
  bool recording = false;
  int recSecs = 0;
  Timer? recTimer;

  int get id => widget.groupId;
  User get me => app.me!;
  bool get resumed {
    final st = WidgetsBinding.instance.lifecycleState;
    return st == null || st == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.activeGroupId = id;
    push.cancelGroup(id);
    sub = app.events.listen(onEvent);
    input.addListener(() {
      final h = input.text.trim().isNotEmpty;
      if (h != hasText) setState(() => hasText = h);
    });
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (app.activeGroupId == id) app.activeGroupId = 0;
    sub?.cancel();
    typingTimer?.cancel();
    recTimer?.cancel();
    if (lastTypingSent != 0) app.emitQuiet('group:typing', {'groupId': id, 'typing': false});
    rec.dispose();
    input.dispose();
    focus.dispose();
    scroll.dispose();
    app.loadChats();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) markRead();
  }

  // ------------------------------------------------------------ anggota
  GroupMember? memberOf(int uid) {
    for (final m in members) {
      if (m.user.id == uid) return m;
    }
    return null;
  }

  String nameOf(int uid, [String fallback = '']) {
    if (uid == me.id) return 'Anda';
    final m = memberOf(uid);
    if (m != null) return m.user.username;
    return fallback.isEmpty ? 'Mantan anggota' : fallback;
  }

  // ------------------------------------------------------------ data
  void leaveScreen(String msg) {
    app.toast(msg, error: true);
    app.loadChatsNow();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void computeDivider() {
    final lr = group.lastReadId;
    final unread = messages.where((m) => !m.isSystem && !m.isLocal && !m.deleted && m.senderId != me.id && m.id > lr).toList();
    if (unread.isNotEmpty) {
      dividerBefore = unread.first.id;
      dividerCount = unread.length;
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = asMap(await app.api.get('/groups/$id/messages?limit=40'));
      final locals = messages.where((m) => m.isLocal).toList();
      messages = asList(r['messages']).map((m) => Message.fromJson(m)).toList()..addAll(locals);
      hasMore = r['hasMore'] == true;
      pinned = asList(r['pinned']).map((m) => Message.fromJson(m)).toList();
      group.merge(GroupItem.fromJson(r['group']));
      members = asList(r['members']).map((m) => GroupMember.fromJson(m)).toList();
      if (!dividerSet) {
        computeDivider();
        dividerSet = true;
      }
      recomputeTicks();
      if (mounted) setState(() => loading = false);
      markRead();
      app.loadChats();
    } catch (e) {
      if (e is ApiException && e.status == 404) {
        leaveScreen('Anda bukan anggota grup ini.');
        return;
      }
      if (mounted) {
        setState(() {
          loading = false;
          error = errText(e);
        });
      }
    }
  }

  Future<void> loadInfo() async {
    try {
      final r = asMap(await app.api.get('/groups/$id'));
      group.merge(GroupItem.fromJson(r['group']));
      members = asList(r['members']).map((m) => GroupMember.fromJson(m)).toList();
      recomputeTicks();
      if (mounted) setState(() {});
    } catch (e) {
      if (e is ApiException && e.status == 404) leaveScreen('Anda bukan anggota grup ini.');
    }
  }

  Future<void> older() async {
    final first = messages.where((m) => !m.isLocal).toList();
    if (first.isEmpty) return;
    try {
      final r = asMap(await app.api.get('/groups/$id/messages?limit=40&before=${first.first.id}'));
      final more = asList(r['messages']).map((m) => Message.fromJson(m)).toList();
      setState(() {
        messages = [...more, ...messages];
        hasMore = r['hasMore'] == true;
        recomputeTicks();
      });
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Centang pesan sendiri: terkirim bila semua anggota lain menerima, biru bila semuanya (yang mengizinkan) membaca.
  void recomputeTicks() {
    final others = members.where((x) => x.user.id != me.id).toList();
    for (final m in messages) {
      if (m.senderId != me.id || m.isLocal || m.isSystem || m.deleted) continue;
      final rel = others.where((x) => x.joinedAt == null || !x.joinedAt!.isAfter(m.createdAt)).toList();
      if (rel.isEmpty) {
        m.deliveredAt = null;
        m.readAt = null;
        continue;
      }
      final delivered = rel.every((x) => x.lastDelivered >= m.id || x.lastRead >= m.id);
      final read = rel.every((x) => x.lastRead >= m.id);
      m.deliveredAt = delivered ? (m.deliveredAt ?? m.createdAt) : null;
      m.readAt = read ? (m.readAt ?? m.createdAt) : null;
    }
  }

  void markRead() {
    if (!mounted || !resumed) return;
    var maxId = 0;
    for (final m in messages) {
      if (!m.isLocal && m.id > maxId) maxId = m.id;
    }
    if (maxId == 0 || maxId <= lastReadSent) return;
    lastReadSent = maxId;
    app.emit('group:read', {'groupId': id}).then((_) {
      app.loadChats();
    }).catchError((Object _) {
      lastReadSent = 0;
    });
  }

  void upsert(Message m) {
    final i = messages.indexWhere((x) => x.id == m.id || (m.clientId != null && x.clientId == m.clientId));
    if (i >= 0) {
      messages[i] = m;
    } else {
      messages.add(m);
    }
  }

  void onEvent(SocketEvent e) {
    if (!mounted) return;
    final d = e.data;
    switch (e.name) {
      case 'reconnected':
        load();
        break;
      case 'group:message':
        {
          final m = Message.fromJson(d['message']);
          if (m.conversationId != id) return;
          setState(() {
            upsert(m);
            recomputeTicks();
          });
          if (m.isSystem) loadInfo();
          markRead();
          break;
        }
      case 'group:message_updated':
        {
          final m = Message.fromJson(d['message']);
          if (m.conversationId != id) return;
          setState(() {
            upsert(m);
            recomputeTicks();
            pinned = messages.where((x) => x.pinned && !x.deleted).toList().reversed.toList();
          });
          break;
        }
      case 'group:message_removed':
        if (d['groupId'] != id) return;
        setState(() => messages.removeWhere((m) => m.id == d['id']));
        break;
      case 'group:receipt':
        {
          if (d['groupId'] != id) return;
          for (final it in asList(d['items'])) {
            final x = asMap(it);
            final uid = x['userId'];
            final mem = uid is int ? memberOf(uid) : null;
            if (mem == null) continue;
            final lr = x['lastRead'];
            final ld = x['lastDelivered'];
            if (lr is int && lr > mem.lastRead) mem.lastRead = lr;
            if (ld is int && ld > mem.lastDelivered) mem.lastDelivered = ld;
          }
          setState(recomputeTicks);
          break;
        }
      case 'group:updated':
        if (d['groupId'] != id) return;
        loadInfo();
        break;
      case 'group:removed':
        if (d['groupId'] != id) return;
        if (d['left'] == true) {
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        } else {
          leaveScreen('Anda dikeluarkan dari grup "${group.name}".');
        }
        break;
      default:
        break;
    }
  }

  // ------------------------------------------------------------ kirim
  Future<void> sendMessage({
    required String type,
    String? body,
    String? localPath,
    String? localName,
    int? mediaId,
    bool viewOnce = false,
  }) async {
    final rp = reply;
    final m = Message(
      id: -(++_localSeq),
      clientId: newClientId(),
      conversationId: id,
      senderId: me.id,
      senderName: me.username,
      type: type,
      body: body,
      viewOnce: viewOnce,
      viewOnceState: viewOnce ? 'new' : null,
      createdAt: DateTime.now(),
      state: 'sending',
      localPath: localPath,
      localName: localName,
      uploadedMediaId: mediaId,
      replyToId: rp?.id,
      replyTo: rp == null ? null : ReplyRef(id: rp.id, senderId: rp.senderId, type: rp.type, body: rp.body, deleted: false, senderName: rp.senderName),
    );
    setState(() {
      messages.add(m);
      reply = null;
    });
    scrollBottom();
    await dispatch(m);
  }

  Future<void> dispatch(Message m) async {
    try {
      if (m.localPath != null && m.uploadedMediaId == null) {
        m.uploadedMediaId = await app.api.upload(m.localPath!, m.type, filename: m.localName);
      }
      final payload = <String, dynamic>{
        'groupId': id,
        'type': m.type,
        'clientId': m.clientId,
      };
      if (m.body != null && m.body!.isNotEmpty) payload['body'] = m.body;
      if (m.uploadedMediaId != null) payload['mediaId'] = m.uploadedMediaId;
      if (m.replyToId != null) payload['replyToId'] = m.replyToId;
      if (m.viewOnce) payload['viewOnce'] = true;
      final r = await app.emit('group:send', payload);
      final real = Message.fromJson(r['message']);
      if (!mounted) return;
      setState(() {
        final i = messages.indexWhere((x) => identical(x, m) || (x.clientId != null && x.clientId == real.clientId));
        if (i >= 0) {
          messages[i] = real;
        } else {
          upsert(real);
        }
        recomputeTicks();
      });
      app.loadChats();
    } catch (e) {
      m.state = 'failed';
      app.toast(errText(e), error: true);
      if (mounted) setState(() {});
    }
  }

  void retry(Message m) {
    setState(() => m.state = 'sending');
    dispatch(m);
  }

  /// Ketukan tombol menu bot: perintah langsung dikirim, atau (bila butuh tambahan seperti judul lagu) diisikan ke kolom ketik.
  void runBotButton(BotButton b) {
    if (b.ask) {
      input.text = '${b.cmd} ';
      input.selection = TextSelection.collapsed(offset: input.text.length);
      focus.requestFocus();
      return;
    }
    sendMessage(type: 'text', body: b.cmd);
  }

  void sendText() {
    final t = input.text.trim();
    if (t.isEmpty) return;
    final ed = editing;
    if (ed != null) {
      setState(() => editing = null);
      input.clear();
      app.emit('group:edit', {'id': ed.id, 'body': t}).catchError((Object e) {
        app.toast(errText(e), error: true);
        return <String, dynamic>{};
      });
      return;
    }
    input.clear();
    stopTyping();
    setState(() => mentionQuery = null);
    sendMessage(type: 'text', body: t);
  }

  void scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void onTextChanged(String _) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastTypingSent > 2500) {
      lastTypingSent = now;
      app.emitQuiet('group:typing', {'groupId': id, 'typing': true});
    }
    typingTimer?.cancel();
    typingTimer = Timer(const Duration(seconds: 3), stopTyping);
    updateMention();
  }

  void stopTyping() {
    typingTimer?.cancel();
    if (lastTypingSent != 0) {
      lastTypingSent = 0;
      app.emitQuiet('group:typing', {'groupId': id, 'typing': false});
    }
  }

  // ------------------------------------------------------------ mention (@nama)
  int cursorPos() {
    final sel = input.selection;
    final len = input.text.length;
    if (!sel.isValid || sel.baseOffset < 0 || sel.baseOffset > len) return len;
    return sel.baseOffset;
  }

  void updateMention() {
    final before = input.text.substring(0, cursorPos());
    final m = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    final q = m?.group(1);
    if (q != mentionQuery && mounted) setState(() => mentionQuery = q);
  }

  List<GroupMember> mentionMatches() {
    final q = mentionQuery;
    if (q == null) return const <GroupMember>[];
    final lq = q.toLowerCase();
    final list = members.where((m) => m.user.id != me.id && (lq.isEmpty || m.user.username.toLowerCase().contains(lq))).toList();
    list.sort((a, b) {
      final sa = a.user.username.toLowerCase().startsWith(lq) ? 0 : 1;
      final sb = b.user.username.toLowerCase().startsWith(lq) ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      return a.user.username.toLowerCase().compareTo(b.user.username.toLowerCase());
    });
    return list.take(6).toList();
  }

  void insertMention(GroupMember mem) {
    final text = input.text;
    final pos = cursorPos();
    final before = text.substring(0, pos);
    final at = before.lastIndexOf('@');
    if (at < 0) return;
    final ins = '@${mem.user.username} ';
    input.value = TextEditingValue(
      text: before.substring(0, at) + ins + text.substring(pos),
      selection: TextSelection.collapsed(offset: at + ins.length),
    );
    setState(() => mentionQuery = null);
    focus.requestFocus();
  }

  Widget mentionList() {
    final p = pal(context);
    final list = mentionMatches();
    if (list.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.line, width: 2))),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: list
            .map((m) => ListTile(
                  dense: true,
                  leading: Avatar(user: m.user, size: 32),
                  title: Text(m.user.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => insertMention(m),
                ))
            .toList(),
      ),
    );
  }

  // ------------------------------------------------------------ lampiran
  bool tooBig(int bytes) {
    final max = (app.cfg?.maxUploadMb ?? 2048) * 1048576;
    if (bytes > max) {
      app.toast('Ukuran file maksimal ${maxSizeText(app.cfg?.maxUploadMb ?? 2048)}.', error: true);
      return true;
    }
    return false;
  }

  Future<void> pickMedia(String kind, {bool camera = false}) async {
    try {
      final picker = ImagePicker();
      XFile? f;
      if (kind == 'image') {
        f = await picker.pickImage(
            source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1920, maxHeight: 1920, imageQuality: 85);
      } else {
        f = await picker.pickVideo(source: camera ? ImageSource.camera : ImageSource.gallery);
      }
      if (f == null) return;
      final len = await File(f.path).length();
      if (tooBig(len)) return;
      if (!mounted) return;
      await previewAndSend(f.path, kind, f.name);
    } catch (_) {
      app.toast('Tidak dapat membuka ${kind == 'image' ? 'foto' : 'video'}.', error: true);
    }
  }

  Future<void> previewAndSend(String path, String kind, String name) async {
    // Layar pratinjau layar penuh ala WhatsApp: keterangan, tombol "1" (sekali lihat), dan tombol kirim.
    final r = await showMediaCompose(context, path: path, kind: kind, toName: group.name);
    if (r == null || !mounted) return;
    sendMessage(type: kind, body: r.caption.isEmpty ? null : r.caption, localPath: path, localName: name, viewOnce: r.viewOnce);
  }

  bool openingOnce = false;

  /// Membuka foto/video sekali lihat dari anggota lain (tiap anggota hanya bisa 1 kali).
  Future<void> openOnce(Message m) async {
    if (m.state == 'failed') {
      onMsgLongPress(m);
      return;
    }
    if (selecting) {
      toggleSel(m);
      return;
    }
    if (m.state != null) return;
    if (m.senderId == me.id) {
      app.toast('Anda tidak dapat membuka pesan sekali lihat yang Anda kirim.');
      return;
    }
    if (m.viewOnceState == 'opened') {
      app.toast('Pesan sekali lihat ini sudah dibuka.');
      return;
    }
    if (m.viewOnceState == 'expired') {
      app.toast('Pesan sekali lihat ini sudah kedaluwarsa.');
      return;
    }
    if (openingOnce) return;
    openingOnce = true;
    try {
      await openViewOnce(context, m: m, group: true, from: m.senderName.isEmpty ? group.name : m.senderName, onOpened: () {
        m.viewOnceState = 'opened';
        if (mounted) setState(() {});
      });
    } finally {
      openingOnce = false;
    }
  }

  Future<void> pickDocument() async {
    try {
      // Semua jenis file boleh dikirim sebagai dokumen (ZIP, HTML, PDF, Office, APK, dll.).
      final r = await FilePicker.platform.pickFiles(type: FileType.any);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      final path = f.path;
      if (path == null) return;
      if (tooBig(f.size)) return;
      sendMessage(type: 'document', localPath: path, localName: f.name);
    } catch (_) {
      app.toast('Tidak dapat membuka dokumen.', error: true);
    }
  }

  Future<void> shareLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        app.toast('Aktifkan layanan lokasi (GPS) terlebih dahulu.', error: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        app.toast('Izin lokasi ditolak. Aktifkan di pengaturan aplikasi.', error: true);
        return;
      }
      app.toast('Mengambil lokasi…');
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 15));
      sendMessage(type: 'location', body: '{"lat":${pos.latitude},"lng":${pos.longitude}}');
    } catch (_) {
      app.toast('Lokasi tidak tersedia.', error: true);
    }
  }

  void shareContact() {
    final list = app.chats;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal(context).surface,
      builder: (ctx) => SafeArea(
        child: list.isEmpty
            ? const SizedBox(height: 200, child: EmptyState(icon: Icons.person_outline, title: 'Belum ada kontak', text: 'Kontak berasal dari percakapan Anda.'))
            : ListView(
                shrinkWrap: true,
                children: list
                    .map((c) => ListTile(
                          leading: Avatar(user: c.peer, size: 40),
                          title: NameWithBadge(c.peer),
                          onTap: () {
                            Navigator.pop(ctx);
                            sendMessage(type: 'contact', body: '{"userId":${c.peer.id}}');
                          },
                        ))
                    .toList(),
              ),
      ),
    );
  }

  void attachMenu() {
    showMenuSheet(context, [
      MenuItem(Icons.image_outlined, 'Foto (galeri)', () => pickMedia('image')),
      MenuItem(Icons.photo_camera_outlined, 'Kamera', () => pickMedia('image', camera: true)),
      MenuItem(Icons.videocam_outlined, 'Video', () => pickMedia('video')),
      MenuItem(Icons.insert_drive_file_outlined, 'Dokumen (PDF, Office, TXT, CSV)', pickDocument),
      MenuItem(Icons.place_outlined, 'Lokasi saya', shareLocation),
      MenuItem(Icons.person_outline, 'Kontak', shareContact),
    ], title: 'Lampirkan');
  }

  // ------------------------------------------------------------ suara
  Future<void> startRec() async {
    try {
      if (!await rec.hasPermission()) {
        app.toast('Izin mikrofon ditolak. Aktifkan di pengaturan aplikasi.', error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/suara_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, autoGain: true, bitRate: 128000, sampleRate: 44100), path: path);
      setState(() {
        recording = true;
        recSecs = 0;
      });
      recTimer?.cancel();
      recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => recSecs++);
        if (recSecs >= 300) stopRec();
      });
    } catch (_) {
      app.toast('Tidak dapat memulai perekaman.', error: true);
    }
  }

  Future<void> stopRec({bool cancel = false}) async {
    recTimer?.cancel();
    final secs = recSecs;
    String? path;
    try {
      path = await rec.stop();
    } catch (_) {
      path = null;
    }
    if (mounted) setState(() => recording = false);
    if (path == null) return;
    if (cancel || secs < 1) {
      try {
        await File(path).delete();
      } catch (_) {}
      if (!cancel) app.toast('Rekaman terlalu singkat.');
      return;
    }
    sendMessage(type: 'audio', localPath: path, localName: 'suara.m4a');
  }

  // ------------------------------------------------------------ aksi pesan
  void jumpTo(int mid) {
    final ctx = keys[mid]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 300));
      setState(() => flashId = mid);
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => flashId = 0);
      });
    } else {
      app.toast('Pesan ini lebih lama. Muat pesan sebelumnya lalu coba lagi.');
    }
  }

  Future<void> react(Message m, String emoji) async {
    try {
      await app.emit('group:react', {'id': m.id, 'emoji': emoji});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Membalas pesan (dipakai oleh geser pesan dan menu "Balas").
  void startReply(Message m) {
    if (m.deleted || m.viewOnce || m.isSystem || m.state == 'sending' || m.state == 'failed' || !group.canSend || recording) return;
    setState(() {
      editing = null;
      reply = m;
    });
    focus.requestFocus();
  }

  // ------------------------------------------------------------ pilih pesan (tahan = pilih, seperti WhatsApp)
  bool get selecting => selected.isNotEmpty;
  List<Message> get selectedMessages => messages.where((m) => selected.contains(m.id)).toList();

  void clearSel() => setState(selected.clear);

  void toggleSel(Message m) {
    if (m.isLocal || m.isSystem) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!selected.remove(m.id)) selected.add(m.id);
    });
  }

  void onMsgLongPress(Message m) {
    if (m.state == 'sending' || m.isSystem) return;
    if (m.state == 'failed') {
      showMenuSheet(context, [
        MenuItem(Icons.send, 'Kirim ulang', () => retry(m)),
        MenuItem(Icons.delete_outline, 'Hapus', () => setState(() => messages.remove(m)), danger: true),
      ]);
      return;
    }
    toggleSel(m);
  }

  void onMsgTap(Message m) {
    if (selecting) {
      toggleSel(m);
    } else if (m.state == 'failed') {
      onMsgLongPress(m);
    } else if (m.type == 'sticker' && !m.deleted && m.media != null) {
      showStickerDetail(context, m.media!);
    }
  }

  /// Dialog hapus ala WhatsApp. Admin grup juga dapat menghapus pesan anggota lain untuk semua orang.
  Future<void> deleteSelected() async {
    final sel = selectedMessages;
    if (sel.isEmpty) return;
    final p = pal(context);
    final now = DateTime.now();
    final win = app.cfg?.deleteWindowMin ?? 60;
    final canAll = sel.every((m) => !m.deleted && ((m.senderId == me.id && now.difference(m.createdAt).inMinutes < win) || group.isAdmin));
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        Widget opt(String value, IconData icon, String label) => SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                onPressed: () => Navigator.pop(ctx, value),
                icon: Icon(icon, color: p.bad, size: 20),
                label: Text(label, style: TextStyle(color: p.bad, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            );
        return AlertDialog(
          title: Text(sel.length == 1 ? 'Hapus pesan?' : 'Hapus ${sel.length} pesan?', style: const TextStyle(fontWeight: FontWeight.w900)),
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (canAll) opt('everyone', Icons.delete_forever_outlined, 'Hapus untuk semua orang'),
            opt('me', Icons.delete_outline, 'Hapus untuk saya'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w800)))],
        );
      },
    );
    if (choice == null) return;
    setState(selected.clear);
    String? err;
    for (final m in sel) {
      try {
        await app.emit('group:delete', {'id': m.id, 'scope': choice});
      } catch (e) {
        err ??= errText(e);
      }
    }
    if (err != null) app.toast(err, error: true);
  }

  void copySelected() {
    final sel = selectedMessages.where((m) => m.type == 'text' && !m.deleted && (m.body ?? '').isNotEmpty).toList();
    if (sel.isEmpty) return;
    Clipboard.setData(ClipboardData(text: sel.map((m) => m.body).join('\n')));
    app.toast('Disalin.');
    clearSel();
  }

  Future<void> toggleStickerFav(Message m) async {
    final media = m.media;
    if (media == null) return;
    clearSel();
    try {
      final isFav = await StickerStore.isFavorite(media.id);
      if (isFav) {
        await StickerStore.removeFavorite(media.id);
        app.toast('Dihapus dari favorit.');
      } else {
        await StickerStore.addFavorite(media.id);
        app.toast('Ditambahkan ke favorit.');
      }
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  PreferredSizeWidget selectionBar() {
    final p = pal(context);
    final sel = selectedMessages;
    final one = sel.length == 1 ? sel.first : null;
    final allLive = sel.isNotEmpty && sel.every((m) => !m.deleted);
    final anyOnce = sel.any((m) => m.viewOnce); // sekali lihat: tidak bisa dibalas, diteruskan, atau disematkan
    final allText = allLive && sel.every((m) => m.type == 'text');
    final mine = one != null && one.senderId == me.id;
    final age = one == null ? Duration.zero : DateTime.now().difference(one.createdAt);
    final editable = one != null && mine && one.type == 'text' && !one.deleted && age.inMinutes < (app.cfg?.editWindowMin ?? 15);
    return zAppBar(
      context,
      leading: IconButton(icon: const Icon(Icons.close), onPressed: clearSel),
      title: Text('${sel.length}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
      actions: [
        if (one != null && !one.deleted && !one.viewOnce && group.canSend)
          IconButton(
            tooltip: 'Balas',
            icon: const Icon(Icons.reply),
            onPressed: () {
              clearSel();
              startReply(one);
            },
          ),
        if (allText) IconButton(tooltip: 'Salin', icon: const Icon(Icons.copy), onPressed: copySelected),
        if (allLive && !anyOnce && sel.length <= 10)
          IconButton(
            tooltip: 'Teruskan',
            icon: const Icon(Icons.forward),
            onPressed: () {
              final list = sel;
              clearSel();
              forward(list);
            },
          ),
        IconButton(tooltip: 'Hapus', icon: const Icon(Icons.delete_outline), onPressed: deleteSelected),
        if (one != null && !one.deleted)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: p.surface,
            onSelected: (v) {
              switch (v) {
                case 'info':
                  clearSel();
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MessageInfoPage(groupId: id, message: one)));
                  break;
                case 'pin':
                  final pin = !one.pinned;
                  clearSel();
                  app.emit('group:pin', {'id': one.id, 'pinned': pin}).catchError((Object e) {
                    app.toast(errText(e), error: true);
                    return <String, dynamic>{};
                  });
                  break;
                case 'edit':
                  setState(() {
                    selected.clear();
                    reply = null;
                    editing = one;
                    input.text = one.body ?? '';
                    input.selection = TextSelection.collapsed(offset: input.text.length);
                    focus.requestFocus();
                  });
                  break;
                case 'fav':
                  toggleStickerFav(one);
                  break;
                case 'private':
                  clearSel();
                  openChatWithUser(context, one.senderId);
                  break;
                case 'report':
                  clearSel();
                  showGroupReport(context, id, messageId: one.id, title: 'Laporkan pesan');
                  break;
              }
            },
            itemBuilder: (_) => [
              if (mine && !one.isLocal) const PopupMenuItem(value: 'info', child: Text('Info pesan')),
              if (!one.viewOnce) PopupMenuItem(value: 'pin', child: Text(one.pinned ? 'Lepas sematan' : 'Sematkan')),
              if (editable) const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (one.type == 'sticker') const PopupMenuItem(value: 'fav', child: Text('Favorit sticker')),
              if (!mine) const PopupMenuItem(value: 'private', child: Text('Balas secara pribadi')),
              if (!mine) PopupMenuItem(value: 'report', child: Text('Laporkan pesan', style: TextStyle(color: p.bad))),
            ],
          ),
      ],
    );
  }

  /// Pil reaksi melayang di dekat pesan yang dipilih (seperti WhatsApp).
  Widget reactionStrip() {
    final m = selectedMessages.length == 1 ? selectedMessages.first : null;
    if (m == null || m.deleted) return const SizedBox.shrink();
    return Positioned.fill(
      child: ReactionOverlay(
        key: ValueKey('react-${m.id}'),
        areaKey: listAreaKey,
        msgKey: keys[m.id],
        mine: m.senderId == me.id,
        scroll: scroll,
        onPick: (e) {
          clearSel();
          react(m, e);
        },
      ),
    );
  }

  void forward(List<Message> msgs) {
    showForwardDialog(context, source: 'group', groupId: id, ids: msgs.map((x) => x.id).toList());
  }

  // ------------------------------------------------------------ menu grup
  Future<void> patchMine(Map<String, dynamic> body, String msg) async {
    try {
      await app.api.patch('/groups/$id/me', body);
      setState(() {
        if (body.containsKey('muted')) group.muted = body['muted'] == true;
        if (body.containsKey('archived')) group.archived = body['archived'] == true;
      });
      app.toast(msg);
      app.loadChatsNow();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> clearChat() async {
    final ok = await showConfirm(context, 'Bersihkan chat?', 'Semua pesan grup ini dihapus dari perangkat dan akun Anda saja. Anggota lain tidak terpengaruh.', 'Bersihkan', danger: true);
    if (!ok) return;
    try {
      await app.api.delete('/groups/$id/messages');
      setState(() {
        messages = [];
        pinned = [];
        hasMore = false;
      });
      app.loadChatsNow();
      app.toast('Chat dibersihkan.');
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> leaveGroup() async {
    final ok = await showConfirm(context, 'Keluar dari grup?', 'Anda tidak akan menerima pesan dari grup "${group.name}" lagi.', 'Keluar', danger: true);
    if (!ok) return;
    try {
      await app.api.post('/groups/$id/leave');
      app.loadChatsNow();
      app.toast('Anda keluar dari grup.');
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void pinnedList() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal(context).surface,
      builder: (ctx) => SafeArea(
        child: pinned.isEmpty
            ? const SizedBox(height: 220, child: EmptyState(icon: Icons.push_pin_outlined, title: 'Belum ada pesan disematkan', text: 'Sematkan pesan penting lewat menu pesan.'))
            : ListView(
                shrinkWrap: true,
                children: pinned
                    .map((m) => ListTile(
                          title: Text(previewText(m), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${nameOf(m.senderId, m.senderName)} · ${dateTimeText(m.createdAt)}'),
                          onTap: () {
                            Navigator.pop(ctx);
                            jumpTo(m.id);
                          },
                        ))
                    .toList(),
              ),
      ),
    );
  }

  void searchMessages() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pal(context).surface,
      builder: (ctx) => SearchSheet(
        conversationId: id,
        basePath: '/groups/$id/messages',
        onPick: (mid) {
          Navigator.pop(ctx);
          jumpTo(mid);
        },
      ),
    );
  }

  Future<void> openInfo() async {
    final r = await Navigator.of(context).push<String>(MaterialPageRoute<String>(builder: (_) => GroupInfoPage(group: group)));
    if (!mounted) return;
    loadInfo();
    if (r == 'search') searchMessages();
  }

  void chatMenu() {
    showMenuSheet(context, [
      MenuItem(Icons.info_outline, 'Info grup', openInfo),
      MenuItem(Icons.search, 'Cari pesan', searchMessages),
      MenuItem(Icons.push_pin_outlined, 'Pesan disematkan', pinnedList),
      MenuItem(Icons.photo_library_outlined, 'Media, tautan, dokumen',
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SharedMediaPage(groupId: id)))),
      MenuItem(group.muted ? Icons.volume_up_outlined : Icons.volume_off_outlined, group.muted ? 'Aktifkan notifikasi' : 'Bisukan notifikasi',
          () => patchMine({'muted': !group.muted}, group.muted ? 'Notifikasi diaktifkan.' : 'Grup dibisukan.')),
      MenuItem(Icons.archive_outlined, group.archived ? 'Keluarkan dari arsip' : 'Arsipkan grup',
          () => patchMine({'archived': !group.archived}, group.archived ? 'Dikeluarkan dari arsip.' : 'Grup diarsipkan.')),
      MenuItem(Icons.cleaning_services_outlined, 'Bersihkan chat', clearChat),
      MenuItem(Icons.flag_outlined, 'Laporkan grup', () => showGroupReport(context, id), danger: true),
      MenuItem(Icons.exit_to_app, 'Keluar dari grup', leaveGroup, danger: true),
    ]);
  }

  // ------------------------------------------------------------ tampilan
  String subtitleText() {
    final t = app.groupTyping[id];
    if (t != null && t.isNotEmpty) {
      final names = t.values.where((n) => n.isNotEmpty).toList();
      if (names.length == 1) return '${names.first} sedang mengetik…';
      if (names.length == 2) return '${names[0]} dan ${names[1]} sedang mengetik…';
      return '${t.length} orang sedang mengetik…';
    }
    if (members.isEmpty) return '${group.memberCount} anggota';
    final others = members.where((m) => m.user.id != me.id).map((m) => m.user.username).toList();
    others.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['Anda', ...others].join(', ');
  }

  List<String> get memberNames => members.map((m) => m.user.username).toList();

  Widget systemBubble(Message m) {
    final p = pal(context);
    final text = sysText(m, me.id);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: 1.5)),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget unreadDivider() {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 5),
        color: p.accent.withAlpha(36),
        child: Text('$dividerCount PESAN BELUM DIBACA', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: p.accentText)),
      ),
    );
  }

  Widget bubble(Message m, {required bool showName, required bool showAvatar}) {
    final p = pal(context);
    final mine = m.senderId == me.id;
    final isSticker = m.type == 'sticker' && !m.deleted;
    final fg = mine ? const Color(0xFF111111) : p.text;
    final key = keys.putIfAbsent(m.id, () => GlobalKey());
    final sender = memberOf(m.senderId);
    final children = <Widget>[];

    if (!mine && showName) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(nameOf(m.senderId, m.senderName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: senderColor(context, m.senderId))),
          ),
          if (sender != null && (sender.user.isDeveloper || sender.user.isVerified))
            Padding(padding: const EdgeInsets.only(left: 3), child: VerifiedBadge(size: 13, rainbow: sender.user.isDeveloper)),
          if (sender != null && sender.isAdmin)
            Padding(padding: const EdgeInsets.only(left: 8), child: Text('admin', style: TextStyle(fontSize: 10.5, color: p.muted, fontWeight: FontWeight.w700))),
        ]),
      ));
    }

    if (m.deleted) {
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 14, color: p.muted),
        const SizedBox(width: 6),
        Text(m.deletedByAdmin ? 'Pesan ini dihapus oleh admin' : 'Pesan ini telah dihapus', style: TextStyle(fontStyle: FontStyle.italic, color: p.muted)),
      ]));
    } else {
      if (m.forwarded) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.forward, size: 12, color: p.muted),
            Text(' Diteruskan', style: TextStyle(fontSize: 12, color: p.muted, fontStyle: FontStyle.italic)),
          ]),
        ));
      }
      final rt = m.replyTo;
      if (rt != null) {
        children.add(GestureDetector(
          onTap: () => jumpTo(rt.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: rt.senderId == me.id ? p.accent : senderColor(context, rt.senderId), width: 4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nameOf(rt.senderId, rt.senderName),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: rt.senderId == me.id ? p.accentText : senderColor(context, rt.senderId))),
              Text(replyPreview(rt), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13)),
            ]),
          ),
        ));
      }
      children.addAll(mediaOf(m, fg));
      final inviteCode = inviteCodeInText(m.body);
      if (inviteCode != null) children.add(InviteCard(code: inviteCode, fg: fg));
      if ((m.body ?? '').isNotEmpty && !m.viewOnce && ['text', 'image', 'video', 'document', 'audio'].contains(m.type)) {
        children.add(captionUnderMedia(
            m.type,
            GroupText(
              m.body!,
              style: TextStyle(color: fg, fontSize: 15.5),
              linkColor: mine ? const Color(0xFF111111) : p.accentText,
              mentionColor: mine ? const Color(0xFF8A0F25) : p.accentText,
              names: memberNames,
              myName: me.username,
            )));
      }
    }

    final meta = Row(mainAxisSize: MainAxisSize.min, children: [
      if (m.expiresAt != null) Padding(padding: const EdgeInsets.only(right: 3), child: Icon(Icons.timer_outlined, size: 11, color: fg.withAlpha(150))),
      if (m.pinned) Padding(padding: const EdgeInsets.only(right: 3), child: Icon(Icons.push_pin, size: 11, color: fg.withAlpha(150))),
      if (m.editedAt != null && !m.deleted) Text('diedit  ', style: TextStyle(fontSize: 11, color: fg.withAlpha(150))),
      Text(fmtTime(m.createdAt), style: TextStyle(fontSize: 11, color: fg.withAlpha(150))),
      if (mine && !m.deleted) Padding(padding: const EdgeInsets.only(left: 4), child: MsgTick(m, base: fg.withAlpha(150))),
    ]);

    final reactions = m.reactions.isEmpty
        ? null
        : Wrap(
            spacing: 4,
            runSpacing: 4,
            children: m.reactions
                .map((r) => GestureDetector(
                      onTap: () => react(m, r.emoji),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: r.mine ? p.yellow : p.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.line, width: 1.5),
                        ),
                        child: Text('${r.emoji}${r.count > 1 ? ' ${r.count}' : ''}', style: const TextStyle(fontSize: 13, color: Color(0xFF111111))),
                      ),
                    ))
                .toList(),
          );

    final column = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      ...children,
      if (reactions != null) Padding(padding: const EdgeInsets.only(top: 6), child: reactions),
      if (!isSticker)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: ExcludeSemantics(child: IgnorePointer(child: Opacity(opacity: 0, child: meta))),
        ),
    ]);
    final content = isSticker
        ? column
        : Stack(children: [
            column,
            Positioned(right: 0, bottom: 0, child: meta),
          ]);

    final radius = BorderRadius.only(
      topLeft: Radius.circular(!mine && showName ? 5 : 16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 5),
      bottomRight: Radius.circular(mine ? 5 : 16),
    );

    Widget avatarSlot() {
      if (mine) return const SizedBox.shrink();
      if (!showAvatar) return const SizedBox(width: 38);
      final u = sender?.user;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: u != null
            ? Avatar(user: u, size: 28, onTap: () => showProfilePreview(context, u))
            : Avatar(name: m.senderName.isEmpty ? '?' : m.senderName, size: 28),
      );
    }

    final body = GestureDetector(
      onLongPress: () => onMsgLongPress(m),
      onTap: () => onMsgTap(m),
      child: AbsorbPointer(
        absorbing: selecting,
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            padding: isSticker ? EdgeInsets.zero : const EdgeInsets.fromLTRB(10, 8, 10, 6),
            decoration: isSticker
                ? null
                : BoxDecoration(
                    color: mine ? p.bubbleOut : p.bubbleIn,
                    borderRadius: radius,
                    border: Border.all(color: flashId == m.id ? p.accent : p.line, width: flashId == m.id ? 3.5 : 2),
                  ),
            child: content,
          ),
          if (m.buttons.isNotEmpty && !m.deleted) BotButtonsBar(buttons: m.buttons, onTap: runBotButton),
          if (m.state == 'failed')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Gagal. Ketuk untuk kirim ulang', style: TextStyle(color: p.bad, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );

    final isSel = selected.contains(m.id);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: selecting ? () => toggleSel(m) : null,
      child: Container(
        color: isSel ? p.accent.withAlpha(46) : Colors.transparent,
        child: SwipeToReply(
          key: key,
          enabled: !m.deleted && !m.viewOnce && m.state != 'sending' && m.state != 'failed' && group.canSend && !recording && !selecting,
          onReply: () => startReply(m),
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, showName || mine ? 3 : 1, 10, 1),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (mine ? 0.8 : 0.86)),
                child: mine
                    ? body
                    : Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        avatarSlot(),
                        Flexible(child: body),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> mediaOf(Message m, Color fg) {
    final p = pal(context);
    final out = <Widget>[];
    final media = m.media;
    final local = m.localPath;
    // Foto/video sekali lihat: tidak ada pratinjau (alamat media tidak dikirim server); hanya kotak "1" yang bisa diketuk.
    if (m.viewOnce && (m.type == 'image' || m.type == 'video')) {
      return [ViewOnceTile(m: m, mine: m.senderId == me.id, fg: fg, onTap: () => openOnce(m))];
    }
    switch (m.type) {
      case 'image':
        Widget img;
        if (media != null) {
          img = CachedNetworkImage(
            imageUrl: app.api.abs(media.url),
            httpHeaders: app.api.mediaHeaders,
            width: 230,
            fit: BoxFit.cover,
            placeholder: (c, u) => const SizedBox(width: 230, height: 160, child: Spin()),
            errorWidget: (c, u, e) => const SizedBox(width: 230, height: 120, child: Icon(Icons.broken_image)),
          );
        } else if (local != null) {
          img = Image.file(File(local), width: 230, fit: BoxFit.cover);
        } else {
          img = const SizedBox(width: 230, height: 120);
        }
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ImageViewerPage(url: media?.url, localPath: media == null ? local : null))),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
          ),
        ));
        break;
      case 'video':
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: GestureDetector(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => VideoPage(url: media?.url, localPath: media == null ? local : null))),
            child: Container(
              width: 230,
              height: 140,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 54),
            ),
          ),
        ));
        break;
      case 'audio':
        if (media != null || local != null) {
          out.add(Padding(
            padding: EdgeInsets.only(bottom: (m.body ?? '').isNotEmpty ? 6 : 0),
            child: VoicePlayer(
                url: media?.url,
                localPath: media == null ? local : null,
                color: fg,
                name: media?.name,
                sender: m.senderId == me.id ? 'Anda' : nameOf(m.senderId, m.senderName),
                fallbackDur: captionDuration(m.body)),
          ));
        }
        break;
      case 'sticker':
        if (media != null) {
          out.add(CachedNetworkImage(
            imageUrl: app.api.abs(media.url),
            httpHeaders: app.api.mediaHeaders,
            width: 140,
            height: 140,
            fit: BoxFit.contain,
            placeholder: (c, u) => const SizedBox(width: 140, height: 140),
            errorWidget: (c, u, e) => const SizedBox(width: 140, height: 140, child: Icon(Icons.broken_image)),
          ));
        }
        break;
      case 'document':
        final name = media?.name ?? m.localName ?? 'Dokumen';
        final size = media?.size;
        out.add(GestureDetector(
          onTap: media == null ? null : () => openDocument(media),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black.withAlpha(20), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.insert_drive_file, size: 30, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                  if (size != null) Text(fmtSize(size), style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 8),
              Icon(Icons.download, size: 18, color: fg),
            ]),
          ),
        ));
        break;
      case 'location':
        final l = _parseJson(m.body);
        out.add(GestureDetector(
          onTap: () {
            final lat = l['lat'];
            final lng = l['lng'];
            if (lat != null && lng != null) {
              openLink('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng');
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black.withAlpha(20), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.place, size: 30, color: p.accent),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Lokasi', style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
                Text('${l['lat']}, ${l['lng']}', style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ));
        break;
      case 'contact':
        final c = _parseJson(m.body);
        final uid = c['userId'];
        out.add(Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.black.withAlpha(20), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Avatar(name: (c['username'] ?? '?').toString(), size: 34),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((c['username'] ?? '').toString(), style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
              Text('Kontak ZARR CHAT', style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
            if (uid is int && uid != me.id)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton(onPressed: () => openChatWithUser(context, uid), child: const Text('Chat')),
              ),
          ]),
        ));
        break;
      default:
        break;
    }
    return out;
  }

  Map<String, dynamic> _parseJson(String? s) {
    if (s == null) return <String, dynamic>{};
    try {
      return asMap(jsonDecode(s));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Widget messageList() {
    final p = pal(context);
    if (loading && messages.isEmpty) return const Spin();
    if (error != null && messages.isEmpty) {
      return EmptyState(icon: Icons.error_outline, title: 'Gagal memuat pesan', text: error, action: NeoButton('Coba lagi', onPressed: load));
    }
    final kids = <Widget>[];
    if (hasMore) {
      kids.add(Center(child: TextButton(onPressed: older, child: const Text('Muat pesan sebelumnya'))));
    }
    if (messages.isEmpty) {
      kids.add(const EmptyState(icon: Icons.chat_bubble_outline, title: 'Belum ada pesan', text: 'Kirim pesan pertama untuk memulai percakapan grup.'));
    }
    if (group.disappearSeconds > 0) {
      kids.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text('Pesan baru menghilang setelah ${disappearLabel(group.disappearSeconds)}.', style: TextStyle(color: p.muted, fontSize: 12)),
        ),
      ));
    }
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final prev = i > 0 ? messages[i - 1] : null;
      final next = i + 1 < messages.length ? messages[i + 1] : null;
      final newDay = prev == null || !sameDay(prev.createdAt, m.createdAt);
      if (newDay) {
        kids.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: 1.5)),
              child: Text(dayLabel(m.createdAt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ),
        ));
      }
      if (dividerBefore != 0 && m.id == dividerBefore) kids.add(unreadDivider());
      if (m.isSystem) {
        kids.add(systemBubble(m));
        continue;
      }
      final firstInRun = prev == null || newDay || prev.isSystem || prev.senderId != m.senderId;
      final lastInRun = next == null || next.isSystem || next.senderId != m.senderId || !sameDay(next.createdAt, m.createdAt);
      kids.add(bubble(m, showName: firstInRun, showAvatar: lastInRun));
    }
    final empty = messages.isEmpty;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        reverse: true,
        controller: scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: empty ? (constraints.maxHeight - 16).clamp(0.0, double.infinity) : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: empty ? MainAxisAlignment.center : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: kids,
          ),
        ),
      ),
    );
  }

  Widget composer() {
    final p = pal(context);
    if (!group.canSend) {
      return Container(
        padding: const EdgeInsets.all(14),
        color: p.surface2,
        child: SafeArea(
          top: false,
          child: Row(children: [
            const Icon(Icons.lock_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Hanya admin yang dapat mengirim pesan di grup ini.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
          ]),
        ),
      );
    }
    if (recording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        color: p.surface,
        child: SafeArea(
          top: false,
          child: Row(children: [
            IconButton(icon: Icon(Icons.delete_outline, color: p.bad), onPressed: () => stopRec(cancel: true)),
            Icon(Icons.fiber_manual_record, color: p.bad, size: 14),
            const SizedBox(width: 6),
            Text(fmtDur(recSecs), style: const TextStyle(fontWeight: FontWeight.w800)),
            const Expanded(child: Text('  Merekam…')),
            _roundBtn(Icons.send, p.accent, Colors.white, () => stopRec()),
          ]),
        ),
      );
    }
    final bar = editing ?? reply;
    return Container(
      color: p.surface,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          mentionList(),
          if (bar != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              color: p.surface2,
              child: Row(children: [
                Icon(editing != null ? Icons.edit : Icons.reply, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(editing != null ? 'Mengedit pesan' : 'Membalas ${bar.senderId == me.id ? 'diri sendiri' : nameOf(bar.senderId, bar.senderName)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    Text(previewText(bar), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    if (editing != null) input.clear();
                    editing = null;
                    reply = null;
                  }),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                icon: Icon(panelOpen ? Icons.keyboard : Icons.emoji_emotions_outlined),
                onPressed: () {
                  setState(() => panelOpen = !panelOpen);
                  if (panelOpen) {
                    FocusScope.of(context).unfocus();
                  } else {
                    focus.requestFocus();
                  }
                },
              ),
              IconButton(icon: const Icon(Icons.attach_file), onPressed: attachMenu),
              Expanded(
                child: TextField(
                  controller: input,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  onChanged: onTextChanged,
                  onTap: () {
                    if (panelOpen) setState(() => panelOpen = false);
                    updateMention();
                  },
                  textCapitalization: TextCapitalization.sentences,
                  decoration: neoDeco(context, hint: 'Ketik pesan (@ untuk menyebut)').copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                ),
              ),
              const SizedBox(width: 6),
              hasText
                  ? _roundBtn(editing != null ? Icons.check : Icons.send, p.accent, Colors.white, sendText)
                  : _roundBtn(Icons.mic, p.yellow, const Color(0xFF111111), startRec),
            ]),
          ),
          if (panelOpen) SizedBox(height: 260, child: panel()),
        ]),
      ),
    );
  }

  Widget _roundBtn(IconData icon, Color bg, Color fg, VoidCallback onTap) {
    final p = pal(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: p.line, width: 2)),
        child: Icon(icon, color: fg, size: 22),
      ),
    );
  }

  Widget panel() {
    final p = pal(context);
    return Column(children: [
      Row(children: [
        for (final e in [(0, 'Emoji'), (1, 'Sticker')])
          Expanded(
            child: InkWell(
              onTap: () => setState(() => panelTab = e.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: panelTab == e.$1 ? p.yellow : p.surface,
                  border: Border(bottom: BorderSide(color: p.line, width: 2)),
                ),
                child: Center(child: Text(e.$2, style: TextStyle(fontWeight: FontWeight.w800, color: panelTab == e.$1 ? const Color(0xFF111111) : p.text))),
              ),
            ),
          ),
      ]),
      Expanded(
        child: panelTab == 0
            ? GridView.count(
                crossAxisCount: 8,
                children: _emoji
                    .map((e) => InkWell(
                          onTap: () {
                            final sel = input.selection;
                            final t = input.text;
                            final s = sel.isValid ? sel.start : t.length;
                            final en = sel.isValid ? sel.end : t.length;
                            input.value = TextEditingValue(
                              text: t.replaceRange(s, en, e),
                              selection: TextSelection.collapsed(offset: s + e.length),
                            );
                            onTextChanged(e);
                          },
                          child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                        ))
                    .toList(),
              )
            : StickerPanel(onSend: (s) {
                // Ketuk sticker langsung terkirim (panel tetap terbuka agar bisa kirim beberapa sticker).
                sendMessage(type: 'sticker', mediaId: s.mediaId);
              }),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    selected.removeWhere((sid) => !messages.any((m) => m.id == sid)); // pesan yang sudah hilang tidak ikut terpilih
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clearSel();
      },
      child: Scaffold(
        appBar: selecting
            ? selectionBar()
            : zAppBar(
                context,
                titleSpacing: 0,
                title: GestureDetector(
                  onTap: openInfo,
                  behavior: HitTestBehavior.opaque,
                  child: Row(children: [
                    Avatar(url: group.avatarUrl, name: group.name, size: 38, group: true, ringStyle: group.ringStyle),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: app,
                        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(group.name.isEmpty ? 'Grup' : group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                            if (group.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedBadge(size: 17)),
                          ]),
                          Text(subtitleText(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ]),
                      ),
                    ),
                  ]),
                ),
                actions: [
                  IconButton(icon: const Icon(Icons.more_vert), onPressed: chatMenu),
                ],
              ),
        body: WallpaperLayer(
          forChat: true,
          fallback: p.chatBg,
          child: Column(children: [
            if (pinned.isNotEmpty)
              InkWell(
                onTap: pinnedList,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: p.surface2, border: Border(bottom: BorderSide(color: p.line, width: 2))),
                  child: Row(children: [
                    const Icon(Icons.push_pin, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(previewText(pinned.first), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (pinned.length > 1) Text('${pinned.length}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            Expanded(
              child: Stack(key: listAreaKey, fit: StackFit.expand, children: [
                messageList(),
                if (selected.length == 1) reactionStrip(),
              ]),
            ),
            composer(),
          ]),
        ),
      ),
    );
  }
}
