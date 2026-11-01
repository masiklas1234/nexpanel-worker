// ZARR CHAT - model data (cermin DTO dari backend).

/// Server menyimpan waktu sebagai teks ISO-8601 UTC. Beberapa kolom lama bisa tanpa "Z"
/// ("2026-10-24 01:46:00"); itu juga UTC, jadi kita paksa dibaca sebagai UTC.
DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  var s = v.toString().trim();
  if (s.isEmpty) return null;
  final naive = RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(\.\d+)?$');
  if (naive.hasMatch(s)) s = '${s.replaceFirst(' ', 'T')}Z';
  final d = DateTime.tryParse(s);
  return d?.toLocal();
}

int _int(dynamic v, [int d = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? d;
}

bool _bool(dynamic v) => v == true || v == 1 || v == '1';

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

List<dynamic> asList(dynamic v) => v is List ? v : <dynamic>[];

class User {
  final int id;
  String username;
  String about;
  String? avatarUrl;
  String? coverUrl; // foto sampul / latar belakang profil (hanya terisi di profil lengkap)
  bool isVerified;
  bool isDeveloper; // akun developer: centang warna-warni (rainbow)
  bool isBot; // BOT MD ZARR CHAT / META AI (akun bot resmi bercentang biru)
  bool isMetaAi; // ZARR CHAT META AI (asisten AI, dibuka dari tombol logo Meta AI)
  // Hanya untuk akun sendiri
  String phone;
  String role;
  DateTime? createdAt;
  String theme;
  bool notifyPreview;
  String privacyLastSeen;
  String privacyStatus;
  bool readReceipts;
  bool autoReplyEnabled; // Balasan Otomatis (hanya akun sendiri)
  String autoReplyMessage;
  // Hanya untuk /users/:id
  bool blockedByMe;
  bool canMessage;
  bool online;
  DateTime? lastSeen;

  User({
    required this.id,
    this.username = '',
    this.about = '',
    this.avatarUrl,
    this.coverUrl,
    this.isVerified = false,
    this.isDeveloper = false,
    this.isBot = false,
    this.isMetaAi = false,
    this.phone = '',
    this.role = 'user',
    this.createdAt,
    this.theme = 'system',
    this.notifyPreview = true,
    this.privacyLastSeen = 'everyone',
    this.privacyStatus = 'contacts',
    this.readReceipts = true,
    this.autoReplyEnabled = false,
    this.autoReplyMessage = '',
    this.blockedByMe = false,
    this.canMessage = true,
    this.online = false,
    this.lastSeen,
  });

  factory User.fromJson(dynamic raw) {
    final j = asMap(raw);
    final priv = asMap(j['privacy']);
    return User(
      id: _int(j['id']),
      username: (j['username'] ?? '').toString(),
      about: (j['about'] ?? '').toString(),
      avatarUrl: j['avatarUrl'] as String?,
      coverUrl: j['coverUrl'] as String?,
      isVerified: _bool(j['isVerified']),
      isDeveloper: _bool(j['isDeveloper']) || j['role'] == 'developer',
      isBot: _bool(j['isBot']),
      isMetaAi: _bool(j['isMetaAi']),
      phone: (j['phone'] ?? '').toString(),
      role: (j['role'] ?? 'user').toString(),
      createdAt: parseDate(j['createdAt']),
      theme: (j['theme'] ?? 'system').toString(),
      notifyPreview: j.containsKey('notifyPreview') ? _bool(j['notifyPreview']) : true,
      privacyLastSeen: (priv['lastSeen'] ?? 'everyone').toString(),
      privacyStatus: (priv['status'] ?? 'contacts').toString(),
      readReceipts: priv.containsKey('readReceipts') ? _bool(priv['readReceipts']) : true,
      autoReplyEnabled: _bool(asMap(j['autoReply'])['enabled']),
      autoReplyMessage: (asMap(j['autoReply'])['message'] ?? '').toString(),
      blockedByMe: _bool(j['blockedByMe']),
      canMessage: j.containsKey('canMessage') ? _bool(j['canMessage']) : true,
      online: _bool(j['online']),
      lastSeen: parseDate(j['lastSeen']),
    );
  }

  /// Menyalin data terbaru dari [o] (dipakai saat profil/lawan bicara diperbarui).
  void merge(User o) {
    username = o.username.isNotEmpty ? o.username : username;
    about = o.about;
    avatarUrl = o.avatarUrl;
    isVerified = o.isVerified;
    isDeveloper = o.isDeveloper;
    isBot = o.isBot || isBot;
    isMetaAi = o.isMetaAi || isMetaAi;
  }

  bool get isAdmin => role == 'admin' || role == 'superadmin' || role == 'developer';
}

class Media {
  final int id;
  final String kind;
  final String mime;
  final int size;
  final String? name;
  final String url;
  Media({required this.id, required this.kind, required this.mime, required this.size, this.name, required this.url});

  factory Media.fromJson(dynamic raw) {
    final j = asMap(raw);
    return Media(
      id: _int(j['id']),
      kind: (j['kind'] ?? '').toString(),
      mime: (j['mime'] ?? '').toString(),
      size: _int(j['size']),
      name: j['name'] as String?,
      url: (j['url'] ?? '').toString(),
    );
  }
}

class ReplyRef {
  final int id;
  final int senderId;
  final String type;
  final String? body;
  final bool deleted;
  final String senderName; // hanya terisi untuk pesan grup
  ReplyRef({required this.id, required this.senderId, required this.type, this.body, this.deleted = false, this.senderName = ''});

  factory ReplyRef.fromJson(dynamic raw) {
    final j = asMap(raw);
    return ReplyRef(
      id: _int(j['id']),
      senderId: _int(j['senderId']),
      type: (j['type'] ?? 'text').toString(),
      body: j['body'] as String?,
      deleted: _bool(j['deleted']),
      senderName: (j['senderName'] ?? '').toString(),
    );
  }
}

/// Tombol menu di bawah pesan bot. [cmd] dikirim sebagai pesan bila diketuk; bila [ask] true, perintah hanya diisikan ke kolom ketik
/// (karena butuh tambahan seperti judul lagu atau tautan).
class BotButton {
  final String label;
  final String cmd;
  final bool ask;
  const BotButton({required this.label, required this.cmd, this.ask = false});

  factory BotButton.fromJson(dynamic raw) {
    final j = asMap(raw);
    return BotButton(label: (j['label'] ?? '').toString(), cmd: (j['cmd'] ?? '').toString(), ask: _bool(j['ask']));
  }
}

class Reaction {
  final String emoji;
  final int count;
  final bool mine;
  Reaction({required this.emoji, required this.count, required this.mine});
}

class Message {
  int id;
  String? clientId;
  int conversationId;
  int senderId;
  String type;
  String? body;
  Media? media;
  ReplyRef? replyTo;
  bool forwarded;
  bool pinned;
  DateTime createdAt;
  DateTime? deliveredAt;
  DateTime? readAt;
  DateTime? editedAt;
  bool deleted;
  DateTime? expiresAt;
  List<Reaction> reactions;
  List<BotButton> buttons; // tombol menu (hanya pesan dari bot)

  // Foto/video sekali lihat (view once). Alamat media & keterangan sengaja tidak dikirim server di daftar pesan.
  bool viewOnce;
  String? viewOnceState; // 'new' | 'opened' | 'expired'
  int viewCount; // grup: jumlah anggota yang sudah membuka (hanya terisi untuk pengirim)

  // Khusus pesan grup
  String senderName;
  bool deletedByAdmin;
  Map<String, dynamic>? sys; // pemberitahuan sistem: {event, actor, targets, extra}

  // Status lokal (pesan yang belum dikonfirmasi server)
  String? state; // 'sending' | 'failed' | null
  String? localPath;
  String? localName;
  int? replyToId;
  int? uploadedMediaId; // id media di server (hasil unggah, atau id sticker)

  Message({
    required this.id,
    this.clientId,
    required this.conversationId,
    required this.senderId,
    required this.type,
    this.body,
    this.media,
    this.replyTo,
    this.forwarded = false,
    this.pinned = false,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.editedAt,
    this.deleted = false,
    this.expiresAt,
    this.reactions = const [],
    this.buttons = const [],
    this.viewOnce = false,
    this.viewOnceState,
    this.viewCount = 0,
    this.senderName = '',
    this.deletedByAdmin = false,
    this.sys,
    this.state,
    this.localPath,
    this.localName,
    this.replyToId,
    this.uploadedMediaId,
  });

  factory Message.fromJson(dynamic raw) {
    final j = asMap(raw);
    return Message(
      id: _int(j['id']),
      clientId: j['clientId'] as String?,
      conversationId: _int(j['conversationId']),
      senderId: _int(j['senderId']),
      type: (j['type'] ?? 'text').toString(),
      body: j['body'] as String?,
      media: j['media'] == null ? null : Media.fromJson(j['media']),
      replyTo: j['replyTo'] == null ? null : ReplyRef.fromJson(j['replyTo']),
      forwarded: _bool(j['forwarded']),
      pinned: _bool(j['pinned']),
      createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
      deliveredAt: parseDate(j['deliveredAt']),
      readAt: parseDate(j['readAt']),
      editedAt: parseDate(j['editedAt']),
      deleted: _bool(j['deleted']),
      expiresAt: parseDate(j['expiresAt']),
      reactions: asList(j['reactions'])
          .map((r) => asMap(r))
          .map((r) => Reaction(emoji: (r['emoji'] ?? '').toString(), count: _int(r['count'], 1), mine: _bool(r['mine'])))
          .toList(),
      buttons: asList(j['buttons']).map((b) => BotButton.fromJson(b)).where((b) => b.label.isNotEmpty && b.cmd.isNotEmpty).toList(),
      viewOnce: _bool(j['viewOnce']),
      viewOnceState: j['viewOnceState'] as String?,
      viewCount: _int(j['viewCount']),
      senderName: (j['senderName'] ?? '').toString(),
      deletedByAdmin: _bool(j['deletedByAdmin']),
      sys: j['sys'] is Map ? asMap(j['sys']) : null,
    );
  }

  bool get isLocal => state != null;
  bool get isSystem => type == 'system';
}

class ChatItem {
  final int id;
  User peer;
  Message? last;
  int unread;
  bool archived;
  bool muted;
  int disappearSeconds;
  ChatItem({
    required this.id,
    required this.peer,
    this.last,
    this.unread = 0,
    this.archived = false,
    this.muted = false,
    this.disappearSeconds = 0,
  });

  factory ChatItem.fromJson(dynamic raw) {
    final j = asMap(raw);
    return ChatItem(
      id: _int(j['id']),
      peer: User.fromJson(j['peer']),
      last: j['lastMessage'] == null ? null : Message.fromJson(j['lastMessage']),
      unread: _int(j['unread']),
      archived: _bool(j['archived']),
      muted: _bool(j['muted']),
      disappearSeconds: _int(j['disappearSeconds']),
    );
  }
}

/// Anggota grup beserta perannya dan resi (terkirim/dibaca) untuk menghitung centang pesan.
class GroupMember {
  final User user;
  String role; // 'admin' | 'member'
  bool isOwner;
  DateTime? joinedAt;
  int lastRead;
  int lastDelivered;
  GroupMember({required this.user, this.role = 'member', this.isOwner = false, this.joinedAt, this.lastRead = 0, this.lastDelivered = 0});

  bool get isAdmin => role == 'admin';

  factory GroupMember.fromJson(dynamic raw) {
    final j = asMap(raw);
    return GroupMember(
      user: User.fromJson(j),
      role: (j['groupRole'] ?? 'member').toString(),
      isOwner: _bool(j['isOwner']),
      joinedAt: parseDate(j['joinedAt']),
      lastRead: _int(j['lastRead']),
      lastDelivered: _int(j['lastDelivered']),
    );
  }
}

/// Grup chat (seperti grup WhatsApp).
class GroupItem {
  final int id;
  String name;
  String description;
  String? avatarUrl;
  int ownerId;
  int memberCount;
  String myRole;
  bool isOwner;
  bool muted;
  bool archived;
  int unread;
  Message? last;
  String sendMode; // 'all' | 'admins'
  String editInfo; // 'all' | 'admins'
  String addMembers; // 'all' | 'admins'
  bool canSend;
  bool canEditInfo;
  bool canAddMembers;
  int disappearSeconds;
  int lastReadId;
  String? inviteCode;
  String creatorName;
  bool isVerified; // centang biru: hanya diberikan lewat Menu Owner
  String ringStyle; // Ring Avatar milik grup ini (diatur admin)
  DateTime? createdAt;

  GroupItem({
    required this.id,
    this.name = '',
    this.description = '',
    this.avatarUrl,
    this.ownerId = 0,
    this.memberCount = 0,
    this.myRole = 'member',
    this.isOwner = false,
    this.muted = false,
    this.archived = false,
    this.unread = 0,
    this.last,
    this.sendMode = 'all',
    this.editInfo = 'all',
    this.addMembers = 'all',
    this.canSend = true,
    this.canEditInfo = true,
    this.canAddMembers = true,
    this.disappearSeconds = 0,
    this.lastReadId = 0,
    this.inviteCode,
    this.creatorName = '',
    this.isVerified = false,
    this.ringStyle = 'comic',
    this.createdAt,
  });

  bool get isAdmin => myRole == 'admin';
  DateTime get activityTime => last?.createdAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory GroupItem.fromJson(dynamic raw) {
    final j = asMap(raw);
    return GroupItem(
      id: _int(j['id']),
      name: (j['name'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      avatarUrl: j['avatarUrl'] as String?,
      ownerId: _int(j['ownerId']),
      memberCount: _int(j['memberCount']),
      myRole: (j['myRole'] ?? 'member').toString(),
      isOwner: _bool(j['isOwner']),
      muted: _bool(j['muted']),
      archived: _bool(j['archived']),
      unread: _int(j['unread']),
      last: j['lastMessage'] == null ? null : Message.fromJson(j['lastMessage']),
      sendMode: (j['sendMode'] ?? 'all').toString(),
      editInfo: (j['editInfo'] ?? 'all').toString(),
      addMembers: (j['addMembers'] ?? 'all').toString(),
      canSend: j.containsKey('canSend') ? _bool(j['canSend']) : true,
      canEditInfo: j.containsKey('canEditInfo') ? _bool(j['canEditInfo']) : true,
      canAddMembers: j.containsKey('canAddMembers') ? _bool(j['canAddMembers']) : true,
      disappearSeconds: _int(j['disappearSeconds']),
      lastReadId: _int(j['lastReadId']),
      inviteCode: j['inviteCode'] as String?,
      creatorName: (j['creatorName'] ?? '').toString(),
      isVerified: _bool(j['isVerified']),
      ringStyle: (j['ringStyle'] ?? 'comic').toString(),
      createdAt: parseDate(j['createdAt']),
    );
  }

  /// Menyalin info terbaru (tanpa menimpa pesan terakhir / jumlah belum dibaca dari daftar).
  void merge(GroupItem o) {
    name = o.name;
    description = o.description;
    avatarUrl = o.avatarUrl;
    ownerId = o.ownerId;
    memberCount = o.memberCount;
    myRole = o.myRole;
    isOwner = o.isOwner;
    muted = o.muted;
    archived = o.archived;
    sendMode = o.sendMode;
    editInfo = o.editInfo;
    addMembers = o.addMembers;
    canSend = o.canSend;
    canEditInfo = o.canEditInfo;
    canAddMembers = o.canAddMembers;
    disappearSeconds = o.disappearSeconds;
    lastReadId = o.lastReadId;
    inviteCode = o.inviteCode;
    isVerified = o.isVerified;
    ringStyle = o.ringStyle;
    if (o.creatorName.isNotEmpty) creatorName = o.creatorName;
    createdAt = o.createdAt ?? createdAt;
  }
}

class StatusItem {
  final int id;
  final String type;
  final String? body;
  final String? bgColor;
  final String? mediaUrl;
  final String privacy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  bool viewed;
  int viewCount;
  StatusItem({
    required this.id,
    required this.type,
    this.body,
    this.bgColor,
    this.mediaUrl,
    this.privacy = 'contacts',
    required this.createdAt,
    this.expiresAt,
    this.viewed = false,
    this.viewCount = 0,
  });

  factory StatusItem.fromJson(dynamic raw) {
    final j = asMap(raw);
    return StatusItem(
      id: _int(j['id']),
      type: (j['type'] ?? 'text').toString(),
      body: j['body'] as String?,
      bgColor: j['bgColor'] as String?,
      mediaUrl: j['mediaUrl'] as String?,
      privacy: (j['privacy'] ?? 'contacts').toString(),
      createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
      expiresAt: parseDate(j['expiresAt']),
      viewed: _bool(j['viewed']),
      viewCount: _int(j['viewCount']),
    );
  }
}

class StatusGroup {
  final User user;
  final List<StatusItem> statuses;
  final bool allViewed;
  StatusGroup({required this.user, required this.statuses, required this.allViewed});
}

class CallRecord {
  final int id;
  final String type;
  final String status;
  final String direction;
  final DateTime createdAt;
  final int durationSec;
  final User peer;
  CallRecord({
    required this.id,
    required this.type,
    required this.status,
    required this.direction,
    required this.createdAt,
    required this.durationSec,
    required this.peer,
  });

  factory CallRecord.fromJson(dynamic raw) {
    final j = asMap(raw);
    return CallRecord(
      id: _int(j['id']),
      type: (j['type'] ?? 'voice').toString(),
      status: (j['status'] ?? '').toString(),
      direction: (j['direction'] ?? 'outgoing').toString(),
      createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
      durationSec: _int(j['durationSec']),
      peer: User.fromJson(j['peer']),
    );
  }
}

class Announcement {
  final int id;
  final String title;
  final String body;
  Announcement({required this.id, required this.title, required this.body});
  factory Announcement.fromJson(dynamic raw) {
    final j = asMap(raw);
    return Announcement(id: _int(j['id']), title: (j['title'] ?? '').toString(), body: (j['body'] ?? '').toString());
  }
}

class NotificationItem {
  final int id;
  final String title;
  final String? body;
  final bool read;
  final DateTime createdAt;
  NotificationItem({required this.id, required this.title, this.body, required this.read, required this.createdAt});
  factory NotificationItem.fromJson(dynamic raw) {
    final j = asMap(raw);
    return NotificationItem(
      id: _int(j['id']),
      title: (j['title'] ?? '').toString(),
      body: j['body'] as String?,
      read: _bool(j['read']),
      createdAt: parseDate(j['createdAt']) ?? DateTime.now(),
    );
  }
}

class Sticker {
  final int id;
  final int mediaId;
  final String url;
  final bool owned; // sticker milik sendiri (boleh dihapus)
  Sticker({required this.id, required this.mediaId, required this.url, this.owned = false});
  factory Sticker.fromJson(dynamic raw) {
    final j = asMap(raw);
    return Sticker(id: _int(j['id']), mediaId: _int(j['mediaId']), url: (j['url'] ?? '').toString(), owned: _bool(j['owned']));
  }
}

class StickerPack {
  final int id;
  final String name;
  final bool isPublic;
  final bool owned;
  final List<Sticker> stickers;
  StickerPack({required this.id, required this.name, required this.isPublic, required this.owned, required this.stickers});
  factory StickerPack.fromJson(dynamic raw) {
    final j = asMap(raw);
    return StickerPack(
      id: _int(j['id']),
      name: (j['name'] ?? '').toString(),
      isPublic: _bool(j['isPublic']),
      owned: _bool(j['owned']),
      stickers: asList(j['stickers']).map((s) => Sticker.fromJson(s)).toList(),
    );
  }
}

/// Konfigurasi dari GET /api/config.
class AppConfig {
  final List<Map<String, dynamic>> iceServers;
  final bool turnConfigured;
  final int maxUploadMb;
  final int editWindowMin;
  final int deleteWindowMin;
  final List<Announcement> announcements;
  AppConfig({
    required this.iceServers,
    required this.turnConfigured,
    required this.maxUploadMb,
    required this.editWindowMin,
    required this.deleteWindowMin,
    required this.announcements,
  });

  factory AppConfig.fromJson(dynamic raw) {
    final j = asMap(raw);
    final ice = <Map<String, dynamic>>[];
    for (final s in asList(j['iceServers'])) {
      final m = asMap(s);
      final urls = m['urls'];
      final entry = <String, dynamic>{
        'urls': urls is List ? urls.map((e) => e.toString()).toList() : urls.toString(),
      };
      if (m['username'] != null) entry['username'] = m['username'].toString();
      if (m['credential'] != null) entry['credential'] = m['credential'].toString();
      ice.add(entry);
    }
    return AppConfig(
      iceServers: ice,
      turnConfigured: _bool(j['turnConfigured']),
      maxUploadMb: _int(j['maxUploadMb'], 2048),
      editWindowMin: _int(j['editWindowMin'], 15),
      deleteWindowMin: _int(j['deleteWindowMin'], 60),
      announcements: asList(j['announcements']).map((a) => Announcement.fromJson(a)).toList(),
    );
  }
}
