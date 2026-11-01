// ZARR CHAT - foto profil & info kontak (mengikuti kebiasaan WhatsApp).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'calls.dart';
import 'chats_tab.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Banner foto sampul profil (latar belakang di belakang foto profil, seperti WhatsApp Business).
/// Tanpa foto: latar warna tema.
class ProfileCover extends StatelessWidget {
  final String? url;
  final double height;
  final double radius;
  const ProfileCover({super.key, this.url, this.height = 170, this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final u = url;
    final has = u != null && u.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: has
            ? CachedNetworkImage(
                imageUrl: app.api.abs(u),
                httpHeaders: app.api.mediaHeaders,
                fit: BoxFit.cover,
                placeholder: (c, _) => Container(color: p.surface2),
                errorWidget: (c, _, __) => Container(color: p.surface2),
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.yellow, p.accent]),
                ),
              ),
      ),
    );
  }
}

/// Foto profil layar penuh (cubit untuk zoom).
class ProfilePhotoPage extends StatelessWidget {
  final User user;
  const ProfilePhotoPage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final src = user.avatarUrl;
    final has = src != null && src.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(user.username, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: has
            ? InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: CachedNetworkImage(
                  imageUrl: app.api.abs(src),
                  httpHeaders: app.api.mediaHeaders,
                  fit: BoxFit.contain,
                  placeholder: (c, u) => const Spin(),
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image, color: Colors.white, size: 64),
                ),
              )
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Avatar(user: user, size: 160),
                const SizedBox(height: 16),
                const Text('Belum ada foto profil', style: TextStyle(color: Colors.white70)),
              ]),
      ),
    );
  }
}

void openProfilePhoto(BuildContext context, User user) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfilePhotoPage(user: user)));
}

/// Pratinjau kecil saat foto di daftar chat diketuk: foto persegi + nama + tombol cepat (seperti WhatsApp).
Future<void> showProfilePreview(BuildContext context, User user, {int? conversationId}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = pal(ctx);
      final src = user.avatarUrl;
      final has = src != null && src.isNotEmpty;
      final side = (MediaQuery.of(ctx).size.width - 96).clamp(200.0, 320.0);
      Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Icon(icon, color: p.accentText, semanticLabel: label),
              ),
            ),
          );
      return Dialog(
        backgroundColor: p.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: p.line, width: 2)),
        clipBehavior: Clip.antiAlias,
        // Lebar kartu = lebar foto persegi: tidak ada bidang kosong di kiri/kanan foto, tombol aksi ikut selebar foto.
        child: SizedBox(
          width: side,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              openProfilePhoto(context, user);
            },
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(fit: StackFit.expand, children: [
                if (has)
                  CachedNetworkImage(
                    imageUrl: app.api.abs(src),
                    httpHeaders: app.api.mediaHeaders,
                    fit: BoxFit.cover,
                    placeholder: (c, u) => Container(color: p.yellow),
                    errorWidget: (c, u, e) => Container(color: p.yellow, child: const Icon(Icons.broken_image)),
                  )
                else
                  Container(
                    color: p.yellow,
                    alignment: Alignment.center,
                    child: Text(
                      user.username.trim().isEmpty ? '?' : String.fromCharCodes([user.username.trim().runes.first]).toUpperCase(),
                      style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w900, color: Color(0xFF111111)),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xB3000000), Color(0x00000000)]),
                    ),
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                      child: NameWithBadge(user, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line, width: 2))),
            child: Row(children: [
              action(Icons.chat_outlined, 'Pesan', () {
                Navigator.pop(ctx);
                if (conversationId != null) {
                  openChat(context, conversationId, user);
                } else {
                  openChatWithUser(context, user.id);
                }
              }),
              action(Icons.call_outlined, 'Telepon', () {
                Navigator.pop(ctx);
                callManager.startCall(user, 'voice');
              }),
              action(Icons.videocam_outlined, 'Video', () {
                Navigator.pop(ctx);
                showVideoCallSoon(context);
              }),
              action(Icons.info_outline, 'Info', () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ContactInfoPage(peer: user)));
              }),
            ]),
          ),
        ]),
        ),
      );
    },
  );
}

/// Halaman info kontak penuh (seperti WhatsApp): foto besar, nama, info, tombol cepat, blokir & laporkan.
class ContactInfoPage extends StatefulWidget {
  final User peer;
  final Future<void> Function()? onToggleBlock;
  final void Function()? onReport;
  const ContactInfoPage({super.key, required this.peer, this.onToggleBlock, this.onReport});
  @override
  State<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends State<ContactInfoPage> {
  User get u => widget.peer;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  /// Daftar chat tidak membawa foto sampul: ambil profil lengkapnya sekali saat halaman dibuka.
  Future<void> _loadCover() async {
    try {
      final r = asMap(await app.api.get('/users/${u.id}'));
      final c = User.fromJson(r['user']).coverUrl;
      if (mounted && c != u.coverUrl) setState(() => u.coverUrl = c);
    } catch (_) {
      // tanpa sampul: tampilan biasa
    }
  }

  Widget _quick(IconData icon, String label, VoidCallback onTap) {
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

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final about = u.about.trim();
    return Scaffold(
      appBar: zAppBar(context, text: 'Info kontak'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (u.coverUrl != null && u.coverUrl!.isNotEmpty)
          SizedBox(
            height: 150 + 70,
            child: Stack(children: [
              Positioned(left: 0, right: 0, top: 0, child: ProfileCover(url: u.coverUrl, height: 150, radius: 16)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
                    child: Avatar(user: u, size: 140, onTap: () => openProfilePhoto(context, u)),
                  ),
                ),
              ),
            ]),
          )
        else
          Center(child: Avatar(user: u, size: 140, onTap: () => openProfilePhoto(context, u))),
        const SizedBox(height: 12),
        Center(child: NameWithBadge(u, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
        if (u.isDeveloper || u.isVerified)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text(u.isDeveloper ? 'Akun Developer ZARR CHAT' : 'Terverifikasi oleh ZARR CHAT', style: TextStyle(color: p.muted, fontSize: 12)),
            ),
          ),
        const SizedBox(height: 12),
        NeoCard(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            _quick(Icons.call_outlined, 'Suara', () => callManager.startCall(u, 'voice')),
            _quick(Icons.videocam_outlined, 'Video', () => showVideoCallSoon(context)),
          ]),
        ),
        NeoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Info', style: TextStyle(color: p.muted, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 6),
            Text(about.isEmpty ? 'Tidak ada info.' : about, style: const TextStyle(fontSize: 16)),
          ]),
        ),
        if (widget.onToggleBlock != null)
          NeoCard(
            onTap: () async {
              await widget.onToggleBlock!();
              if (mounted) setState(() {});
            },
            child: Row(children: [
              Icon(Icons.block, color: u.blockedByMe ? p.good : p.bad),
              const SizedBox(width: 12),
              Text(u.blockedByMe ? 'Buka blokir ${u.username}' : 'Blokir ${u.username}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: u.blockedByMe ? p.good : p.bad)),
            ]),
          ),
        if (widget.onReport != null)
          NeoCard(
            onTap: widget.onReport,
            child: Row(children: [
              Icon(Icons.thumb_down_alt_outlined, color: p.bad),
              const SizedBox(width: 12),
              Text('Laporkan ${u.username}', style: TextStyle(fontWeight: FontWeight.w800, color: p.bad)),
            ]),
          ),
      ]),
    );
  }
}
