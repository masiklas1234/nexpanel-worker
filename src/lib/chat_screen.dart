// ZARR CHAT - layar percakapan.
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
import 'calls.dart';
import 'chats_tab.dart';
import 'groups.dart';
import 'media.dart';
import 'meta_ai.dart';
import 'models.dart';
import 'profile_view.dart';
import 'push.dart';
import 'state.dart';
import 'sticker_editor.dart';
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

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final User peer;
  const ChatScreen({super.key, required this.conversationId, required this.peer});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late User peer = widget.peer;
  List<Message> messages = [];
  List<Message> pinned = [];
  bool hasMore = false;
  bool loading = true;
  bool leaving = false; // layar sedang ditutup karena percakapan dihapus
  String? error;
  bool archived = false;
  bool muted = false;
  int disappear = 0;

  Message? reply;
  Message? editing;
  final TextEditingController input = TextEditingController();
  final FocusNode focus = FocusNode();
  final ScrollController scroll = ScrollController();
  final Map<int, GlobalKey> keys = {};
  final GlobalKey listAreaKey = GlobalKey(); // area daftar pesan (acuan posisi pil reaksi)
  int flashId = 0;
  final Set<int> selected = {}; // id pesan yang dipilih (mode pilih seperti WhatsApp)
  int _localSeq = 0;
  bool hasText = false;
  bool panelOpen = false;
  int panelTab = 0;

  StreamSubscription<SocketEvent>? sub;
  Timer? typingTimer;
  int lastTypingSent = 0;

  // rekam suara
  final AudioRecorder rec = AudioRecorder();
  bool recording = false;
  int recSecs = 0;
  Timer? recTimer;

  int get id => widget.conversationId;
  User get me => app.me!;
  bool get resumed {
    final st = WidgetsBinding.instance.lifecycleState;
    return st == null || st == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.activeChatId = id;
    push.cancelChat(id); // chat dibuka: hapus notifikasi pesannya dari bilah HP
    sub = app.events.listen(onEvent);
    input.addListener(() {
      final h = input.text.trim().isNotEmpty;
      if (h != hasText) setState(() => hasText = h);
    });
    load();
    loadInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (app.activeChatId == id) app.activeChatId = 0;
    sub?.cancel();
    typingTimer?.cancel();
    recTimer?.cancel();
    if (lastTypingSent != 0) app.emitQuiet('typing', {'conversationId': id, 'typing': false});
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

  // ------------------------------------------------------------ data
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = asMap(await app.api.get('/chats/$id/messages?limit=40'));
      final locals = messages.where((m) => m.isLocal).toList();
      messages = asList(r['messages']).map((m) => Message.fromJson(m)).toList()..addAll(locals);
      hasMore = r['hasMore'] == true;
      pinned = asList(r['pinned']).map((m) => Message.fromJson(m)).toList();
      final conv = asMap(r['conversation']);
      archived = conv['archived'] == true;
      muted = conv['muted'] == true;
      disappear = (conv['disappearSeconds'] is int) ? conv['disappearSeconds'] as int : 0;
      peer.merge(User.fromJson(r['peer']));
      if (mounted) setState(() => loading = false);
      markRead();
      app.loadChats();
    } catch (e) {
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
      final r = asMap(await app.api.get('/users/${peer.id}'));
      final u = User.fromJson(r['user']);
      peer.merge(u);
      peer.blockedByMe = u.blockedByMe;
      peer.canMessage = u.canMessage;
      peer.online = u.online;
      peer.lastSeen = u.lastSeen;
      if (mounted) setState(() {});
    } catch (_) {
      // info tambahan; abaikan bila gagal
    }
  }

  Future<void> older() async {
    final first = messages.where((m) => !m.isLocal).toList();
    if (first.isEmpty) return;
    try {
      final r = asMap(await app.api.get('/chats/$id/messages?limit=40&before=${first.first.id}'));
      final more = asList(r['messages']).map((m) => Message.fromJson(m)).toList();
      setState(() {
        messages = [...more, ...messages];
        hasMore = r['hasMore'] == true;
      });
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void markRead() {
    if (!mounted || !resumed) return;
    final unread = messages.any((m) => m.senderId != me.id && m.readAt == null && !m.deleted && !m.isLocal);
    if (!unread) return;
    app.emit('chat:read', {'conversationId': id}).then((_) {
      final now = DateTime.now();
      for (final m in messages) {
        if (m.senderId != me.id) m.readAt ??= now;
      }
      app.loadChats();
      if (mounted) setState(() {});
    }).catchError((Object _) {});
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
      case 'message:new':
        {
          final m = Message.fromJson(d['message']);
          if (m.conversationId != id) return;
          setState(() => upsert(m));
          if (m.senderId != me.id) markRead();
          break;
        }
      case 'ai:stream':
        {
          // Jawaban Meta AI yang sedang diketik (streaming): perbarui isi pesan yang sama.
          if (d['conversationId'] != id) return;
          final i = messages.indexWhere((x) => x.id == d['messageId']);
          if (i < 0) return;
          setState(() => messages[i].body = (d['body'] ?? '').toString());
          break;
        }
      case 'message:updated':
        {
          final m = Message.fromJson(d['message']);
          if (m.conversationId != id) return;
          setState(() {
            upsert(m);
            pinned = messages.where((x) => x.pinned && !x.deleted).toList().reversed.toList();
          });
          break;
        }
      case 'message:removed':
        if (d['conversationId'] != id) return;
        setState(() => messages.removeWhere((m) => m.id == d['id']));
        break;
      case 'message:status':
        {
          if (d['conversationId'] != id) return;
          final ids = asList(d['ids']);
          final now = DateTime.now();
          setState(() {
            for (final x in messages) {
              if (ids.contains(x.id)) {
                x.deliveredAt ??= now;
                if (d['status'] == 'read') x.readAt = now;
              }
            }
          });
          break;
        }
      case 'chat:cleared':
        {
          // Dari perangkat lain (atau perangkat ini): semua pesan dihapus / percakapan dihapus.
          if (d['conversationId'] != id) return;
          if (d['deleted'] == true) {
            if (!leaving) {
              leaving = true;
              Navigator.of(context).maybePop();
            }
          } else {
            setState(() {
              messages.removeWhere((m) => !m.isLocal);
              pinned = [];
              hasMore = false;
              reply = null;
            });
          }
          break;
        }
      case 'chat:updated':
        if (d['conversationId'] != id) return;
        setState(() => disappear = (d['disappearSeconds'] is int) ? d['disappearSeconds'] as int : 0);
        break;
      case 'presence':
        if (d['userId'] == peer.id) {
          setState(() {
            peer.online = d['online'] == true;
            peer.lastSeen = parseDate(d['lastSeen']);
          });
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
      replyTo: rp == null ? null : ReplyRef(id: rp.id, senderId: rp.senderId, type: rp.type, body: rp.body, deleted: false),
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
        'conversationId': id,
        'type': m.type,
        'clientId': m.clientId,
      };
      if (m.body != null && m.body!.isNotEmpty) payload['body'] = m.body;
      if (m.uploadedMediaId != null) payload['mediaId'] = m.uploadedMediaId;
      if (m.replyToId != null) payload['replyToId'] = m.replyToId;
      if (m.viewOnce) payload['viewOnce'] = true;
      final r = await app.emit('message:send', payload);
      final real = Message.fromJson(r['message']);
      if (!mounted) return;
      setState(() {
        final i = messages.indexWhere((x) => identical(x, m) || (x.clientId != null && x.clientId == real.clientId));
        if (i >= 0) {
          messages[i] = real;
        } else {
          upsert(real);
        }
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
      app.emit('message:edit', {'id': ed.id, 'body': t}).catchError((Object e) {
        app.toast(errText(e), error: true);
        return <String, dynamic>{};
      });
      return;
    }
    input.clear();
    stopTyping();
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
      app.emitQuiet('typing', {'conversationId': id, 'typing': true});
    }
    typingTimer?.cancel();
    typingTimer = Timer(const Duration(seconds: 3), stopTyping);
  }

  void stopTyping() {
    typingTimer?.cancel();
    if (lastTypingSent != 0) {
      lastTypingSent = 0;
      app.emitQuiet('typing', {'conversationId': id, 'typing': false});
    }
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
    final r = await showMediaCompose(context, path: path, kind: kind, toName: peer.username);
    if (r == null || !mounted) return;
    sendMessage(type: kind, body: r.caption.isEmpty ? null : r.caption, localPath: path, localName: name, viewOnce: r.viewOnce);
  }

  bool openingOnce = false;

  /// Membuka foto/video sekali lihat dari penerima (hanya bisa 1 kali).
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
      await openViewOnce(context, m: m, group: false, from: peer.username, onOpened: () {
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
      await app.emit('message:react', {'id': m.id, 'emoji': emoji});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Membalas pesan (dipakai oleh geser pesan dan menu "Balas").
  void startReply(Message m) {
    if (m.deleted || m.viewOnce || m.state == 'sending' || m.state == 'failed' || !peer.canMessage || recording) return;
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
    if (m.isLocal) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!selected.remove(m.id)) selected.add(m.id);
    });
  }

  void onMsgLongPress(Message m) {
    if (m.state == 'sending') return;
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

  /// Dialog hapus ala WhatsApp: tombol merah "Hapus untuk semua orang" / "Hapus untuk saya".
  Future<void> deleteSelected() async {
    final sel = selectedMessages;
    if (sel.isEmpty) return;
    final p = pal(context);
    final now = DateTime.now();
    final win = app.cfg?.deleteWindowMin ?? 60;
    final canAll = sel.every((m) => m.senderId == me.id && !m.deleted && now.difference(m.createdAt).inMinutes < win);
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
        await app.emit('message:delete', {'id': m.id, 'scope': choice});
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
        if (one != null && !one.deleted && !one.viewOnce && peer.canMessage)
          IconButton(
            tooltip: 'Balas',
            icon: const Icon(Icons.reply),
            onPressed: () {
              clearSel();
              startReply(one);
            },
          ),
        if (allText)
          IconButton(tooltip: 'Salin', icon: const Icon(Icons.copy), onPressed: copySelected),
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
                case 'pin':
                  final pin = !one.pinned;
                  clearSel();
                  app.emit('message:pin', {'id': one.id, 'pinned': pin}).catchError((Object e) {
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
                case 'report':
                  clearSel();
                  report(one);
                  break;
              }
            },
            itemBuilder: (_) => [
              if (!one.viewOnce) PopupMenuItem(value: 'pin', child: Text(one.pinned ? 'Lepas sematan' : 'Sematkan')),
              if (editable) const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (one.type == 'sticker') const PopupMenuItem(value: 'fav', child: Text('Favorit sticker')),
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
    showForwardDialog(context, source: 'chat', ids: msgs.map((x) => x.id).toList());
  }

  void report(Message? m) {
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
          title: const Text('Laporkan pengguna', style: TextStyle(fontWeight: FontWeight.w900)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m != null
                  ? 'Pesan yang dilaporkan akan dibagikan kepada administrator.'
                  : 'Administrator akan meninjau laporan Anda. Isi chat tidak dibagikan kecuali Anda melaporkan pesan tertentu.'),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: reason,
                isExpanded: true,
                items: reasons.entries.map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setD(() => reason = v ?? 'spam'),
              ),
              TextField(controller: det, maxLength: 500, maxLines: 3, decoration: neoDeco(ctx, hint: 'Detail tambahan (opsional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            TextButton(
              onPressed: () async {
                final body = <String, dynamic>{'reason': reason, 'details': det.text};
                if (m != null) body['messageId'] = m.id;
                Navigator.pop(ctx);
                try {
                  await app.api.post('/users/${peer.id}/report', body);
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

  // ------------------------------------------------------------ menu chat
  Future<void> patchChat(Map<String, dynamic> p, String msg) async {
    try {
      await app.api.patch('/chats/$id', p);
      setState(() {
        if (p.containsKey('muted')) muted = p['muted'] == true;
        if (p.containsKey('archived')) archived = p['archived'] == true;
        if (p.containsKey('disappearSeconds')) disappear = p['disappearSeconds'] as int;
      });
      app.toast(msg);
      app.loadChatsNow();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> toggleBlock() async {
    try {
      if (peer.blockedByMe) {
        await app.api.delete('/users/${peer.id}/block');
        setState(() {
          peer.blockedByMe = false;
          peer.canMessage = true;
        });
        app.toast('Blokir dibuka.');
      } else {
        final ok = await showConfirm(
            context, 'Blokir pengguna?', '${peer.username} tidak akan bisa mengirim pesan atau menelepon Anda.', 'Blokir', danger: true);
        if (!ok) return;
        await app.api.post('/users/${peer.id}/block');
        setState(() {
          peer.blockedByMe = true;
          peer.canMessage = false;
        });
        app.toast('Pengguna diblokir.');
      }
      app.loadChatsNow();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Hapus SEMUA PESAN: isi chat dikosongkan, percakapan (termasuk bot) tetap ada di daftar.
  Future<void> clearMessages() async {
    final ok = await showConfirm(context, 'Hapus semua pesan?', 'Semua pesan di percakapan ini dihapus dari akun Anda. Percakapan tetap ada di daftar chat.', 'Hapus semua', danger: true);
    if (!ok) return;
    try {
      await app.api.post('/chats/$id/clear');
      if (mounted) {
        setState(() {
          messages.removeWhere((m) => !m.isLocal);
          pinned = [];
          hasMore = false;
          reply = null;
        });
      }
      app.loadChatsNow();
      app.toast('Semua pesan dihapus.');
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Hapus PERCAKAPAN: chat (termasuk bot) hilang dari daftar akun ini.
  Future<void> deleteChat() async {
    final ok = await showConfirm(context, 'Hapus percakapan?', 'Percakapan ini beserta seluruh pesannya dihapus dari akun Anda dan hilang dari daftar chat. Pesan baru akan memunculkannya lagi.', 'Hapus', danger: true);
    if (!ok) return;
    try {
      await app.api.delete('/chats/$id');
      app.loadChatsNow();
      app.toast('Percakapan dihapus.');
      final already = leaving;
      leaving = true;
      if (mounted && !already) Navigator.pop(context);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void disappearingMenu() {
    final opts = <int, String>{0: 'Mati', 86400: '24 jam', 604800: '7 hari', 7776000: '90 hari'};
    showMenuSheet(
      context,
      opts.entries
          .map((e) => MenuItem(Icons.timer_outlined, e.value,
              () => patchChat({'disappearSeconds': e.key}, e.key > 0 ? 'Pesan baru akan hilang setelah ${e.value}.' : 'Pesan menghilang dimatikan.'),
              checked: disappear == e.key))
          .toList(),
      title: 'Pesan menghilang',
    );
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
                          subtitle: Text(dateTimeText(m.createdAt)),
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
        onPick: (mid) {
          Navigator.pop(ctx);
          jumpTo(mid);
        },
      ),
    );
  }

  void chatMenu() {
    showMenuSheet(context, [
      MenuItem(Icons.search, 'Cari pesan', searchMessages),
      MenuItem(Icons.push_pin_outlined, 'Pesan disematkan', pinnedList),
      MenuItem(muted ? Icons.volume_up_outlined : Icons.volume_off_outlined, muted ? 'Aktifkan notifikasi' : 'Bisukan notifikasi',
          () => patchChat({'muted': !muted}, muted ? 'Notifikasi diaktifkan.' : 'Percakapan dibisukan.')),
      MenuItem(Icons.archive_outlined, archived ? 'Keluarkan dari arsip' : 'Arsipkan percakapan',
          () => patchChat({'archived': !archived}, archived ? 'Dikeluarkan dari arsip.' : 'Percakapan diarsipkan.')),
      MenuItem(Icons.timer_outlined, 'Pesan menghilang', disappearingMenu),
      if (!peer.isBot) MenuItem(Icons.block, peer.blockedByMe ? 'Buka blokir' : 'Blokir pengguna', toggleBlock, danger: !peer.blockedByMe),
      MenuItem(Icons.flag_outlined, 'Laporkan pengguna', () => report(null), danger: true),
      MenuItem(Icons.cleaning_services_outlined, 'Hapus semua pesan', clearMessages, danger: true),
      MenuItem(Icons.delete_outline, 'Hapus percakapan', deleteChat, danger: true),
    ]);
  }

  void contactInfo() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ContactInfoPage(peer: peer, onToggleBlock: toggleBlock, onReport: () => report(null)),
    ));
  }

  // ------------------------------------------------------------ tampilan
  String statusLine() {
    if (app.typing[id] == true) return peer.isBot && !peer.isMetaAi ? 'sedang memproses…' : 'sedang mengetik…';
    if (peer.isMetaAi) return 'Meta AI • selalu online';
    if (peer.isBot) return 'bot • selalu online';
    if (peer.online) return 'online';
    final ls = peer.lastSeen;
    if (ls != null) {
      final n = DateTime.now();
      if (sameDay(ls, n)) return 'terakhir dilihat hari ini ${fmtTime(ls)}';
      if (sameDay(ls, n.subtract(const Duration(days: 1)))) return 'terakhir dilihat kemarin ${fmtTime(ls)}';
      return 'terakhir dilihat ${listTime(ls)} ${fmtTime(ls)}';
    }
    return '';
  }

  Widget bubble(Message m) {
    final p = pal(context);
    final mine = m.senderId == me.id;
    final isSticker = m.type == 'sticker' && !m.deleted;
    final fg = mine ? const Color(0xFF111111) : p.text;
    final key = keys.putIfAbsent(m.id, () => GlobalKey());
    final children = <Widget>[];

    if (m.deleted) {
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 14, color: p.muted),
        const SizedBox(width: 6),
        Text('Pesan ini telah dihapus', style: TextStyle(fontStyle: FontStyle.italic, color: p.muted)),
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
              border: Border(left: BorderSide(color: p.accent, width: 4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rt.senderId == me.id ? 'Anda' : peer.username, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: p.accentText)),
              Text(replyPreview(rt), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13)),
            ]),
          ),
        ));
      }
      children.addAll(mediaOf(m, fg));
      final inviteCode = inviteCodeInText(m.body);
      if (inviteCode != null) children.add(InviteCard(code: inviteCode, fg: fg));
      if ((m.body ?? '').isNotEmpty && !m.viewOnce && ['text', 'image', 'video', 'document', 'audio'].contains(m.type)) {
        children.add(peer.isMetaAi && !mine && m.type == 'text'
            ? AiText(m.body!, style: TextStyle(color: fg, fontSize: 15.5), linkColor: p.accentText)
            : captionUnderMedia(m.type, LinkText(m.body!, style: TextStyle(color: fg, fontSize: 15.5), linkColor: mine ? const Color(0xFF111111) : p.accentText)));
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

    // Lebar bubble mengikuti isi pesan (bukan selalu penuh). Jam & centang digambar di pojok kanan bawah;
    // salinan tak terlihat (Opacity 0) di bawah isi hanya menyediakan ruang agar bubble tidak lebih sempit dari jam.
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
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 5),
      bottomRight: Radius.circular(mine ? 5 : 16),
    );

    final isSel = selected.contains(m.id);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: selecting ? () => toggleSel(m) : null,
      child: Container(
      color: isSel ? p.accent.withAlpha(46) : Colors.transparent,
      child: SwipeToReply(
      key: key,
      enabled: !m.deleted && !m.viewOnce && m.state != 'sending' && m.state != 'failed' && peer.canMessage && !recording && !selecting,
      onReply: () => startReply(m),
      child: Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          child: GestureDetector(
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
          ),
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
                sender: m.senderId == me.id ? 'Anda' : peer.username,
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
      kids.add(const EmptyState(icon: Icons.chat_bubble_outline, title: 'Belum ada pesan', text: 'Kirim pesan pertama untuk memulai percakapan.'));
    }
    if (disappear > 0) {
      kids.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text('Pesan baru menghilang setelah ${disappear >= 604800 ? '${(disappear / 86400).round()} hari' : '24 jam'}.',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ),
      ));
    }
    DateTime? prev;
    for (final m in messages) {
      if (prev == null || !sameDay(prev, m.createdAt)) {
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
      prev = m.createdAt;
      kids.add(bubble(m));
    }
    // Gelembung respon bot: Meta AI = tiga titik beranimasi, BOT MD = "sedang memproses" + titik.
    if (peer.isBot) kids.add(BotTypingBubble(convId: id, metaAi: peer.isMetaAi));
    final empty = messages.isEmpty;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        reverse: true,
        controller: scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ConstrainedBox(
          // Saat belum ada pesan, tinggi minimal = area tampil agar "Belum ada pesan" berada di tengah.
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
    if (!peer.canMessage) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: p.surface2,
        child: SafeArea(
          top: false,
          child: Row(children: [
            const Icon(Icons.block, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(peer.blockedByMe ? 'Anda memblokir pengguna ini.' : 'Anda tidak dapat mengirim pesan ke pengguna ini.')),
            if (peer.blockedByMe) TextButton(onPressed: toggleBlock, child: const Text('Buka blokir')),
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
          if (bar != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              color: p.surface2,
              child: Row(children: [
                Icon(editing != null ? Icons.edit : Icons.reply, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(editing != null ? 'Mengedit pesan' : 'Membalas ${bar.senderId == me.id ? 'diri sendiri' : peer.username}',
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
                  },
                  textCapitalization: TextCapitalization.sentences,
                  decoration: neoDeco(context, hint: peer.isMetaAi ? 'Tanya Meta AI…' : 'Ketik pesan').copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                ),
              ),
              const SizedBox(width: 6),
              hasText
                  ? _roundBtn(editing != null ? Icons.check : Icons.send, p.accent, Colors.white, sendText)
                  : _roundBtn(Icons.mic, p.yellow, const Color(0xFF111111), startRec),
            ]),
          ),
          if (panelOpen) SizedBox(height: 290, child: panel()),
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
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: panelTab == e.$1 ? p.yellow : p.surface,
                  border: Border(bottom: BorderSide(color: p.line, width: 2)),
                ),
                child: Center(child: Text(e.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: panelTab == e.$1 ? const Color(0xFF111111) : p.text))),
              ),
            ),
          ),
      ]),
      Expanded(
        child: panelTab == 0
            ? GridView.extent(
                maxCrossAxisExtent: 46,
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
                          child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
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
    selected.removeWhere((id) => !messages.any((m) => m.id == id)); // pesan yang sudah hilang tidak ikut terpilih
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selecting) clearSel();
      },
      child: Scaffold(
      appBar: selecting ? selectionBar() : zAppBar(
        context,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: contactInfo,
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            Avatar(user: peer, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: ListenableBuilder(
                listenable: app,
                builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NameWithBadge(peer, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                  Text(statusLine(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ]),
        ),
        actions: [
          if (!peer.isBot) IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => callManager.startCall(peer, 'voice')),
          if (!peer.isBot) IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () => showVideoCallSoon(context)),
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

/// Geser pesan ke kanan untuk membalas (seperti WhatsApp).
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  const SwipeToReply({super.key, required this.child, required this.onReply, this.enabled = true});
  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const double _trigger = 56;
  static const double _maxDx = 80;
  double dx = 0;
  bool dragging = false;
  bool passed = false;

  void _update(DragUpdateDetails d) {
    var next = dx + d.delta.dx;
    if (next < 0) next = 0;
    if (next > _maxDx) next = _maxDx;
    if (!passed && next >= _trigger) {
      passed = true;
      HapticFeedback.lightImpact();
    } else if (passed && next < _trigger) {
      passed = false;
    }
    setState(() {
      dragging = true;
      dx = next;
    });
  }

  void _end([DragEndDetails? d]) {
    final fire = passed && widget.enabled;
    setState(() {
      dragging = false;
      dx = 0;
      passed = false;
    });
    if (fire) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final p = pal(context);
    final progress = (dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => dragging = true),
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(alignment: Alignment.centerLeft, children: [
        Positioned(
          left: 14,
          child: Opacity(
            opacity: progress,
            child: Transform.scale(
              scale: 0.6 + 0.4 * progress,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.surface2, shape: BoxShape.circle, border: Border.all(color: p.line, width: 1.5)),
                child: Icon(Icons.reply, size: 20, color: passed ? p.accentText : p.muted),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: dragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(dx, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}

class SearchSheet extends StatefulWidget {
  final int conversationId;
  final void Function(int) onPick;
  final String? basePath; // bila diisi (mis. /groups/5/messages) dipakai ganti /chats/<id>/messages
  const SearchSheet({super.key, required this.conversationId, required this.onPick, this.basePath});
  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final TextEditingController c = TextEditingController();
  Timer? t;
  List<Message> res = [];
  bool busy = false;
  String? err;

  @override
  void dispose() {
    t?.cancel();
    c.dispose();
    super.dispose();
  }

  void changed(String _) {
    t?.cancel();
    t = Timer(const Duration(milliseconds: 350), run);
  }

  Future<void> run() async {
    final q = c.text.trim();
    if (q.length < 2) {
      setState(() => res = []);
      return;
    }
    setState(() => busy = true);
    try {
      final base = widget.basePath ?? '/chats/${widget.conversationId}/messages';
      final r = asMap(await app.api.get('$base?limit=50&q=${Uri.encodeQueryComponent(q)}'));
      if (!mounted) return;
      setState(() {
        res = asList(r['messages']).map((m) => Message.fromJson(m)).toList().reversed.toList();
        busy = false;
        err = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          err = errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: c,
                autofocus: true,
                onChanged: changed,
                decoration: neoDeco(context, hint: 'Cari di percakapan ini', prefix: const Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: busy
                  ? const Spin()
                  : err != null
                      ? EmptyState(icon: Icons.error_outline, title: 'Gagal mencari', text: err)
                      : res.isEmpty
                          ? const EmptyState(icon: Icons.search_off, title: 'Tidak ada hasil', text: 'Ketik minimal 2 karakter.')
                          : ListView(
                              children: res
                                  .map((m) => ListTile(
                                        title: Text(m.body ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                                        subtitle: Text(dateTimeText(m.createdAt)),
                                        onTap: () => widget.onPick(m.id),
                                      ))
                                  .toList(),
                            ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Panel sticker (favorit + paket). Dipakai di chat dan di saluran.
class StickerPanel extends StatefulWidget {
  final void Function(Sticker) onSend;
  const StickerPanel({super.key, required this.onSend});
  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  List<StickerPack> packs = [];
  List<Sticker> favs = [];
  bool loading = true;
  bool making = false;
  String? err;

  Set<int> get favMedia => favs.map((f) => f.mediaId).toSet();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/stickers'));
      packs = asList(r['packs']).map((p) => StickerPack.fromJson(p)).toList();
      favs = asList(r['favorites']).map((s) => Sticker.fromJson(s)).toList();
      err = null;
    } catch (e) {
      err = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  /// Pilih gambar -> edit (zoom/geser/putar) -> unggah -> masuk ke paket "Sticker saya".
  Future<void> make() async {
    if (making) return;
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
      if (f == null || !mounted) return;
      final edited = await openStickerEditor(context, f.path);
      if (edited == null) return;
      setState(() => making = true);
      final mediaId = await app.api.upload(edited, 'sticker', filename: 'sticker.png');
      int? packId;
      for (final p in packs) {
        if (p.owned && p.name == 'Sticker saya') {
          packId = p.id;
          break;
        }
      }
      if (packId == null) {
        for (final p in packs) {
          if (p.owned) {
            packId = p.id;
            break;
          }
        }
      }
      if (packId == null) {
        final r = asMap(await app.api.post('/stickers/packs', {'name': 'Sticker saya'}));
        packId = r['id'] as int?;
      }
      if (packId == null) throw ApiException('Paket sticker gagal dibuat.');
      await app.api.post('/stickers/packs/$packId/stickers', {'mediaId': mediaId});
      app.toast('Sticker dibuat.');
      await load();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => making = false);
  }

  Future<void> toggleFav(Sticker s, bool isFav) async {
    try {
      if (isFav) {
        await StickerStore.removeFavorite(s.mediaId);
        app.toast('Dihapus dari favorit.');
      } else {
        await StickerStore.addFavorite(s.mediaId);
        app.toast('Ditambahkan ke favorit.');
      }
      await load();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> deleteSticker(Sticker s) async {
    final ok = await showConfirm(context, 'Hapus sticker?', 'Sticker akan dihapus dari koleksi Anda. Pesan yang sudah terkirim tidak berubah.', 'Hapus', danger: true);
    if (!ok) return;
    try {
      await app.api.delete('/stickers/${s.id}');
      await load();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Tahan sticker: kirim / favorit / hapus (seperti WhatsApp).
  void options(Sticker s) {
    final isFav = favMedia.contains(s.mediaId);
    showMenuSheet(
      context,
      [
        MenuItem(Icons.send, 'Kirim sticker', () => widget.onSend(s)),
        MenuItem(isFav ? Icons.star : Icons.star_border, isFav ? 'Hapus dari favorit' : 'Tambahkan ke favorit', () => toggleFav(s, isFav)),
        if (s.owned) MenuItem(Icons.delete_outline, 'Hapus sticker', () => deleteSticker(s), danger: true),
      ],
      header: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: CachedNetworkImage(
          imageUrl: app.api.abs(s.url),
          httpHeaders: app.api.mediaHeaders,
          width: 120,
          height: 120,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// Sel pertama grid (seperti "Buat stiker" di WhatsApp): pilih gambar -> edit -> jadi sticker.
  Widget createTile() {
    final p = pal(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: making ? null : make,
      child: Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line, width: 2)),
        child: Center(
          child: making
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit, size: 20, color: p.text),
                  const SizedBox(height: 2),
                  Text('Buat\nstiker', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, height: 1.1, fontWeight: FontWeight.w800, color: p.text)),
                ]),
        ),
      ),
    );
  }

  // Ukuran sel maksimal 70 dp -> sekitar 6 kolom di HP umumnya (sedang, seperti WhatsApp), bukan 4 kolom yang besar.
  Widget grid(List<Sticker> list, {Widget? lead}) {
    final p = pal(context);
    final fm = favMedia;
    return GridView.extent(
      maxCrossAxisExtent: 70,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        if (lead != null) lead,
        ...list.map((s) => InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => widget.onSend(s),
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  options(s);
                },
                child: Stack(children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: CachedNetworkImage(
                        imageUrl: app.api.abs(s.url),
                        httpHeaders: app.api.mediaHeaders,
                        fit: BoxFit.contain,
                        errorWidget: (c, u, e) => const Icon(Icons.broken_image),
                      ),
                    ),
                  ),
                  if (fm.contains(s.mediaId)) Positioned(right: 2, bottom: 2, child: Icon(Icons.star, size: 12, color: p.yellow)),
                ]),
              )),
      ],
    );
  }

  Widget label(String t, {IconData? icon}) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 5),
      child: Row(children: [
        if (icon != null) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 14, color: p.muted)),
        Text(t, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    if (loading) return const Spin();
    if (err != null) {
      return EmptyState(icon: Icons.error_outline, title: 'Gagal memuat sticker', text: err, action: NeoButton('Coba lagi', onPressed: () {
        setState(() => loading = true);
        load();
      }));
    }
    final nonEmpty = packs.where((pk) => pk.stickers.isNotEmpty).toList();
    var leadUsed = false; // kotak "Buat stiker" hanya muncul sekali, di grid pertama
    Widget? takeLead() {
      if (leadUsed) return null;
      leadUsed = true;
      return createTile();
    }

    return ListView(padding: const EdgeInsets.fromLTRB(8, 6, 8, 12), children: [
      Text('Ketuk untuk kirim • tahan untuk favorit / hapus', style: TextStyle(color: p.muted, fontSize: 10.5)),
      if (favs.isNotEmpty) ...[label('Favorit', icon: Icons.star), grid(favs, lead: takeLead())],
      ...nonEmpty.map((pk) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label('${pk.name}${pk.isPublic ? ' · publik' : ''}'),
            grid(pk.stickers, lead: takeLead()),
          ])),
      if (nonEmpty.isEmpty && favs.isEmpty) ...[
        const SizedBox(height: 8),
        grid(const <Sticker>[], lead: takeLead()),
        Padding(padding: const EdgeInsets.only(top: 12), child: Text('Belum ada sticker. Ketuk "Buat stiker" untuk membuat yang pertama dari gambar sendiri.', style: TextStyle(color: p.muted, fontSize: 12))),
      ],
    ]);
  }
}


/// Gelembung "bot sedang merespon" di dasar daftar pesan.
/// - Meta AI: gelembung berisi tiga titik yang bergerak bergantian.
/// - BOT MD ZARR CHAT: robot kecil + tulisan merah "sedang" + tiga titik.
/// Muncul selama server mengirim event `typing` untuk percakapan ini, hilang otomatis saat selesai.
class BotTypingBubble extends StatefulWidget {
  final int convId;
  final bool metaAi;
  const BotTypingBubble({super.key, required this.convId, required this.metaAi});
  @override
  State<BotTypingBubble> createState() => _BotTypingBubbleState();
}

class _BotTypingBubbleState extends State<BotTypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _running = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _dots(Color base, {double size = 7}) {
    final lift = size * 0.4;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : size * 0.6),
            child: Builder(builder: (context) {
              // Tiap titik naik-turun bergantian (gelombang), titik aktif lebih gelap & sedikit naik.
              final t = (_c.value - i * 0.18) % 1.0;
              final k = t < 0.5 ? (t / 0.5) : (1 - (t - 0.5) / 0.5); // 0..1..0
              return Transform.translate(
                offset: Offset(0, -lift * k),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: base.withAlpha((90 + 165 * k).round())),
                ),
              );
            }),
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
        final on = app.typing[widget.convId] == true;
        if (on && !_running) {
          _running = true;
          _c.repeat();
        } else if (!on && _running) {
          _running = false;
          _c.stop();
        }
        if (!on) return const SizedBox.shrink();
        final dots = _dots(p.muted, size: widget.metaAi ? 7 : 6);
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: widget.metaAi ? 14 : 12, vertical: widget.metaAi ? 10 : 7),
              decoration: BoxDecoration(
                color: p.bubbleIn,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.line, width: 2),
                boxShadow: [BoxShadow(color: p.line, offset: const Offset(2, 2))],
              ),
              child: widget.metaAi
                  ? dots
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🤖', style: TextStyle(fontSize: 15)),
                      const SizedBox(width: 6),
                      const Text(
                        'sedang',
                        style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFFF2455F)),
                      ),
                      const SizedBox(width: 8),
                      dots,
                    ]),
            ),
          ),
        );
      },
    );
  }
}
