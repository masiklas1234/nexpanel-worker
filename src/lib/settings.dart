// ZARR CHAT - tab Pengaturan: profil, akun, privasi, notifikasi, keamanan, tampilan, bantuan.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'avatar_cropper.dart';

import 'admin.dart';
import 'audio_storage.dart';
import 'api.dart';
import 'auth.dart';
import 'models.dart';
import 'music.dart';
import 'profile_view.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'wallpaper.dart';
import 'widgets.dart';

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app, music]),
      builder: (context, _) {
        final m = app.me;
        if (m == null) return const SizedBox.shrink();
        return Scaffold(
          appBar: zAppBar(context, text: 'Pengaturan'),
          body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 24), children: [
            NeoCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              padding: const EdgeInsets.all(14),
              color: p.surface,
              onTap: () => _push(context, const ProfilePage()),
              child: Row(children: [
                Avatar(user: m, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    NameWithBadge(m, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 3),
                    Text(m.about, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
                  ]),
                ),
                Icon(Icons.chevron_right, color: p.text),
              ]),
            ),
            const NeoSection('Akun & privasi'),
            NeoTile(icon: Icons.person_outline, title: 'Akun', subtitle: 'Nomor, kata sandi, keluar semua perangkat', onTap: () => _push(context, const AccountPage())),
            NeoTile(icon: Icons.lock_outline, title: 'Privasi', subtitle: 'Terakhir dilihat, tanda dibaca, blokir', onTap: () => _push(context, const PrivacyPage())),
            NeoTile(icon: Icons.security, title: 'Keamanan', subtitle: 'Perangkat yang sedang masuk', onTap: () => _push(context, const SecurityPage())),
            NeoTile(icon: Icons.reply_all_outlined, title: 'Balasan Otomatis', subtitle: m.autoReplyEnabled ? 'Aktif - membalas otomatis saat sibuk' : 'Kirim pesan otomatis saat sibuk', onTap: () => _push(context, const AutoReplyPage())),
            NeoTile(icon: Icons.notifications_none, title: 'Notifikasi', subtitle: 'Pemberitahuan pesan', onTap: () => _push(context, const NotifSettingsPage())),
            NeoTile(icon: Icons.volume_up_outlined, title: 'Audio & Notifikasi', subtitle: 'Volume, suara pesan, getar', onTap: () => _push(context, const AudioNotifPage())),
            NeoTile(icon: Icons.sd_storage_outlined, title: 'Penyimpanan Media', subtitle: 'Unduh otomatis, ukuran, hapus media', onTap: () => _push(context, const MediaStoragePage())),
            const NeoSection('Suara'),
            NeoSwitchTile(
              icon: music.enabled ? Icons.music_note : Icons.music_off,
              title: 'Musik Latar',
              subtitle: music.enabled
                  ? 'Menyala di background sampai kamu matikan'
                  : 'Nyalakan supaya ada musik di background',
              value: music.enabled,
              onChanged: music.busy ? null : (v) => music.setEnabled(v),
            ),
            const NeoSection('Tampilan'),
            NeoTile(icon: Icons.palette_outlined, title: 'Tema', subtitle: 'Terang atau gelap', onTap: () => _push(context, const AppearancePage())),
            NeoTile(
              icon: Icons.diamond_outlined,
              title: 'Tema 3D Premium',
              subtitle: 'Emas, Samudra, Neon, Sakura',
              onTap: () => _push(context, const Theme3DPage()),
            ),
            NeoTile(icon: Icons.account_circle_outlined, title: 'Ring Avatar', subtitle: 'Bingkai foto profil', onTap: () => _push(context, const RingAvatarPage())),
            NeoTile(icon: Icons.wallpaper, title: 'Background & Wallpaper', subtitle: 'Foto latar aplikasi dan wallpaper chat', onTap: () => _push(context, const WallpaperPage())),
            const NeoSection('Bantuan'),
            NeoTile(icon: Icons.help_outline, title: 'Bantuan', subtitle: 'Pertanyaan umum & kebijakan privasi', onTap: () => _push(context, const HelpPage())),
            NeoTile(icon: Icons.code, title: 'Tentang Developer', subtitle: 'Hubungi pembuat aplikasi', onTap: () => showAboutDev(context)),
            if (m.isAdmin) NeoTile(icon: Icons.shield_outlined, title: 'Panel Admin', subtitle: 'Kelola pengguna & laporan', onTap: () => _push(context, const AdminPage())),
            const SizedBox(height: 6),
            NeoTile(
              icon: Icons.logout,
              title: 'Keluar',
              subtitle: 'Keluar dari akun di perangkat ini',
              danger: true,
              onTap: () async {
                if (await showConfirm(context, 'Keluar?', 'Anda akan keluar dari akun di perangkat ini.', 'Keluar', danger: true)) {
                  await app.logout();
                }
              },
            ),
          ]),
        );
      },
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController name = TextEditingController(text: app.me?.username ?? '');
  late final TextEditingController about = TextEditingController(text: app.me?.about ?? '');
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    about.dispose();
    super.dispose();
  }

  Future<void> changePhoto() async {
    try {
      final path = await pickAndCropAvatar(context, title: 'Atur foto profil');
      if (path == null) return;
      final id = await app.api.upload(path, 'avatar', filename: 'avatar.png');
      final r = asMap(await app.api.put('/me/avatar', {'mediaId': id}));
      app.me?.avatarUrl = User.fromJson(r['user']).avatarUrl;
      app.refresh();
      app.toast('Foto profil diperbarui.');
      if (mounted) setState(() {});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  /// Foto sampul (latar belakang profil): pilih dari galeri lalu unggah.
  Future<void> changeCover() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (x == null) return;
      app.toast('Mengunggah foto sampul…');
      final id = await app.api.upload(x.path, 'avatar', filename: 'cover.jpg');
      final r = asMap(await app.api.put('/me/cover', {'mediaId': id}));
      app.me?.coverUrl = User.fromJson(r['user']).coverUrl;
      app.refresh();
      app.toast('Foto sampul diperbarui.');
      if (mounted) setState(() {});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  Future<void> removeCover() async {
    try {
      await app.api.put('/me/cover', {'mediaId': null});
      app.me?.coverUrl = null;
      app.refresh();
      app.toast('Foto sampul dihapus.');
      if (mounted) setState(() {});
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void coverMenu() {
    final has = (app.me?.coverUrl ?? '').isNotEmpty;
    showMenuSheet(context, [
      MenuItem(Icons.photo_library_outlined, 'Pilih dari galeri', changeCover),
      if (has) MenuItem(Icons.delete_outline, 'Hapus foto sampul', removeCover, danger: true),
    ], title: 'Foto sampul');
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await app.saveMe({'username': name.text, 'about': about.text});
      app.toast('Profil disimpan.');
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = app.me;
    return Scaffold(
      appBar: zAppBar(context, text: 'Profil'),
      body: m == null
          ? const SizedBox.shrink()
          : ListView(padding: const EdgeInsets.only(bottom: 20), children: [
              // Foto sampul (latar belakang) + foto profil yang menumpang di bawahnya, seperti WhatsApp Business.
              SizedBox(
                height: 170 + 55,
                child: Stack(children: [
                  Positioned(left: 0, right: 0, top: 0, child: GestureDetector(onTap: coverMenu, child: ProfileCover(url: m.coverUrl, height: 170))),
                  Positioned(
                    right: 12,
                    top: 170 - 48,
                    child: GestureDetector(
                      onTap: coverMenu,
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(color: pal(context).accent, shape: BoxShape.circle, border: Border.all(color: pal(context).line, width: 2)),
                        child: const Icon(Icons.photo_camera, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: changePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
                          child: Stack(children: [
                            Avatar(user: m, size: 110),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: pal(context).accent, shape: BoxShape.circle, border: Border.all(color: pal(context).line, width: 2)),
                                child: const Icon(Icons.photo_camera, color: Colors.white, size: 18),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 10),
              Center(child: Text(m.phone, style: TextStyle(color: pal(context).muted))),
              const SizedBox(height: 18),
              const Text('Nama Tampilan', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(controller: name, maxLength: 30, decoration: neoDeco(context)),
              const Text('Info', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(controller: about, maxLength: 140, decoration: neoDeco(context)),
              const SizedBox(height: 10),
              NeoButton('Simpan perubahan', busy: busy, onPressed: save),
              if (m.isDeveloper || m.isVerified)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: NeoCard(
                    child: Row(children: [
                      VerifiedBadge(size: 22, rainbow: m.isDeveloper),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.isDeveloper ? 'Akun Developer ZARR CHAT.' : 'Akun Anda terverifikasi oleh ZARR CHAT.')),
                    ]),
                  ),
                ),
                ]),
              ),
            ]),
    );
  }
}

/// Balasan Otomatis: bila aktif, orang yang mengirim pesan ke kita otomatis dibalas dengan pesan ini oleh server
/// (juga saat aplikasi ditutup). Bila dimatikan, balasan otomatis berhenti.
class AutoReplyPage extends StatefulWidget {
  const AutoReplyPage({super.key});
  @override
  State<AutoReplyPage> createState() => _AutoReplyPageState();
}

class _AutoReplyPageState extends State<AutoReplyPage> {
  late final TextEditingController msg = TextEditingController(text: app.me?.autoReplyMessage ?? '');
  late bool enabled = app.me?.autoReplyEnabled ?? false;
  bool busy = false;

  @override
  void dispose() {
    msg.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final text = msg.text.trim();
    if (enabled && text.isEmpty) {
      app.toast('Isi pesan balasan dulu sebelum mengaktifkan.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await app.saveMe({'auto_reply_message': text, 'auto_reply_enabled': enabled});
      msg.text = app.me?.autoReplyMessage ?? text;
      app.toast(enabled ? 'Balasan otomatis aktif.' : 'Balasan otomatis dimatikan.');
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: zAppBar(context, text: 'Balasan Otomatis'),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 24), children: [
        NeoSwitchTile(
          icon: Icons.reply_all_outlined,
          title: 'Aktifkan Auto-Reply',
          subtitle: 'Kirim pesan otomatis saat sibuk',
          value: enabled,
          onChanged: busy ? null : (v) => setState(() => enabled = v),
        ),
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: msg,
            maxLength: 500,
            minLines: 4,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: neoDeco(context, label: 'Pesan Balasan', hint: 'Contoh: Maaf ya, aku sedang sibuk.'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Saat aktif, orang yang mengirim pesan ke kamu otomatis dibalas dengan pesan di atas (satu kali tiap 30 menit per percakapan). Matikan saklar lalu tekan Simpan untuk berhenti.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: NeoButton('Simpan', busy: busy, onPressed: save)),
      ]),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final m = app.me;
    return Scaffold(
      appBar: zAppBar(context, text: 'Akun'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        NeoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nomor telepon', style: TextStyle(color: p.muted, fontSize: 12)),
          Text(m?.phone ?? '', style: const TextStyle(fontWeight: FontWeight.w900)),
        ])),
        NeoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bergabung', style: TextStyle(color: p.muted, fontSize: 12)),
          Text(dateTimeText(m?.createdAt), style: const TextStyle(fontWeight: FontWeight.w900)),
        ])),
        NeoCard(onTap: () => _push(context, const ChangePasswordPage()), child: const Text('Ganti Kata Sandi', style: TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(height: 10),
        NeoButton('Keluar dari semua perangkat', danger: true, onPressed: () async {
          if (await showConfirm(context, 'Keluar dari semua perangkat?', 'Semua sesi, termasuk yang ini, akan diakhiri.', 'Keluar semua', danger: true)) {
            await app.logoutAll();
          }
        }),
      ]),
    );
  }
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final oldP = TextEditingController();
  final newP = TextEditingController();
  final conf = TextEditingController();
  String err = '';
  bool busy = false;

  @override
  void dispose() {
    oldP.dispose();
    newP.dispose();
    conf.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (newP.text.length < 6) {
      setState(() => err = 'Kata sandi baru minimal 6 karakter.');
      return;
    }
    if (newP.text != conf.text) {
      setState(() => err = 'Kata sandi baru tidak cocok.');
      return;
    }
    setState(() {
      err = '';
      busy = true;
    });
    try {
      await app.api.post('/auth/change-password', {'oldPassword': oldP.text, 'newPassword': newP.text});
      app.toast('Kata sandi berhasil diubah.');
      oldP.clear();
      newP.clear();
      conf.clear();
    } catch (e) {
      err = errText(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _f(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          TextField(controller: c, obscureText: true, decoration: neoDeco(context)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: zAppBar(context, text: 'Ganti Kata Sandi'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _f('Kata Sandi Lama', oldP),
        _f('Kata Sandi Baru', newP),
        _f('Konfirmasi Kata Sandi Baru', conf),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(err, style: TextStyle(color: pal(context).bad, fontWeight: FontWeight.w700))),
        NeoButton('Simpan Kata Sandi', busy: busy, onPressed: save),
      ]),
    );
  }
}

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});
  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  List<User> blocked = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/blocks'));
      blocked = asList(r['users']).map((u) => User.fromJson(u)).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> save(Map<String, dynamic> patch) async {
    try {
      await app.saveMe(patch);
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final m = app.me!;
    return Scaffold(
      appBar: zAppBar(context, text: 'Privasi'),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 24), children: [
        NeoTile(
          icon: Icons.visibility_outlined,
          title: 'Terakhir dilihat & online',
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: m.privacyLastSeen,
              items: const [
                DropdownMenuItem(value: 'everyone', child: Text('Semua orang')),
                DropdownMenuItem(value: 'contacts', child: Text('Kontak saya')),
                DropdownMenuItem(value: 'nobody', child: Text('Tidak ada')),
              ],
              onChanged: (v) => save({'privacy_last_seen': v ?? 'everyone'}),
            ),
          ),
        ),
        NeoSwitchTile(
          icon: Icons.done_all,
          title: 'Tanda dibaca',
          value: m.readReceipts,
          onChanged: (v) => save({'privacy_read_receipts': v}),
        ),
        NeoTile(
          icon: Icons.donut_large_outlined,
          title: 'Privasi status bawaan',
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: m.privacyStatus,
              items: const [
                DropdownMenuItem(value: 'contacts', child: Text('Kontak saya')),
                DropdownMenuItem(value: 'everyone', child: Text('Semua pengguna')),
                DropdownMenuItem(value: 'selected', child: Text('Dipilih')),
              ],
              onChanged: (v) => save({'privacy_status': v ?? 'contacts'}),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Kontak adalah pengguna yang pernah Anda ajak bertukar pesan.', style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        const NeoSection('Pengguna yang diblokir'),
        if (loading) const Spin(),
        if (!loading && blocked.isEmpty)
          NeoCard(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Tidak ada pengguna yang diblokir.', style: TextStyle(color: p.muted)),
          ),
        ...blocked.map((u) => NeoRow(
              leading: Avatar(user: u, size: 40),
              title: NameWithBadge(u),
              trailing: TextButton(
                onPressed: () async {
                  try {
                    await app.api.delete('/users/${u.id}/block');
                    setState(() => blocked.remove(u));
                    app.toast('Blokir dibuka.');
                  } catch (e) {
                    app.toast(errText(e), error: true);
                  }
                },
                child: const Text('Buka blokir', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            )),
      ]),
    );
  }
}

class NotifSettingsPage extends StatefulWidget {
  const NotifSettingsPage({super.key});
  @override
  State<NotifSettingsPage> createState() => _NotifSettingsPageState();
}

class _NotifSettingsPageState extends State<NotifSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final m = app.me!;
    return Scaffold(
      appBar: zAppBar(context, text: 'Notifikasi'),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 24), children: [
        NeoSwitchTile(
          icon: Icons.notifications_none,
          title: 'Tampilkan isi pesan di pemberitahuan',
          value: m.notifyPreview,
          onChanged: (v) async {
            try {
              await app.saveMe({'notify_preview': v});
            } catch (e) {
              app.toast(errText(e), error: true);
            }
            if (mounted) setState(() {});
          },
        ),
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          color: pal(context).surface2,
          child: Text('Pemberitahuan pesan muncul saat aplikasi sedang dibuka. Notifikasi saat aplikasi tertutup belum tersedia.',
              style: TextStyle(color: pal(context).text, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  List<Map<String, dynamic>> sessions = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = asMap(await app.api.get('/auth/sessions'));
      sessions = asList(r['sessions']).map((s) => asMap(s)).toList();
    } catch (e) {
      error = errText(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: zAppBar(context, text: 'Keamanan'),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 24), children: [
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          color: p.surface2,
          child: Row(children: const [
            Icon(Icons.lock_outline),
            SizedBox(width: 10),
            Expanded(child: Text('Koneksi memakai alamat server yang diatur di aplikasi. Pesan belum terenkripsi end-to-end.')),
          ]),
        ),
        const NeoSection('Perangkat yang masuk'),
        if (loading) const Spin(),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(error!)),
        ...sessions.map((s) {
          final current = s['current'] == true;
          return NeoCard(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(current ? 'Perangkat ini' : 'Perangkat lain', style: const TextStyle(fontWeight: FontWeight.w900)),
              Text((s['userAgent'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
              Text('Aktif terakhir ${dateTimeText(parseDate(s['lastUsedAt']))}', style: TextStyle(color: p.muted, fontSize: 12)),
              if (!current)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: NeoButton('Keluarkan', danger: true, onPressed: () async {
                    try {
                      await app.api.delete('/auth/sessions/${s['id']}');
                      setState(() => sessions.remove(s));
                    } catch (e) {
                      app.toast(errText(e), error: true);
                    }
                  }),
                ),
            ]),
          );
        }),
      ]),
    );
  }
}

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});
  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  @override
  Widget build(BuildContext context) {
    final m = app.me!;
    return Scaffold(
      appBar: zAppBar(context, text: 'Tampilan'),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 24), children: [
        NeoTile(
          icon: Icons.palette_outlined,
          title: 'Tema',
          subtitle: 'Pilih tampilan terang atau gelap',
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: m.theme == 'dark' ? 'dark' : 'light',
              items: const [
                DropdownMenuItem(value: 'light', child: Text('Terang')),
                DropdownMenuItem(value: 'dark', child: Text('Gelap')),
              ],
              onChanged: (v) async {
                try {
                  await app.saveMe({'theme': v ?? 'light'});
                  await themeStore.select(''); // memilih Terang/Gelap = kembali ke Comic 2D
                } catch (e) {
                  app.toast(errText(e), error: true);
                }
                if (mounted) setState(() {});
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// Pengaturan → Tema 3D Premium: pilih Comic 2D (standar) atau salah satu tema 3D.
class Theme3DPage extends StatefulWidget {
  const Theme3DPage({super.key});
  @override
  State<Theme3DPage> createState() => _Theme3DPageState();
}

class _Theme3DPageState extends State<Theme3DPage> {
  Future<void> _pick(Theme3D t) async {
    await themeStore.select(t.id);
    app.toast('Tema ${t.name} dipakai.');
  }

  Future<void> _pickComic() async {
    await themeStore.select('');
    app.toast('Tema Comic 2D dipakai.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, themeStore]),
      builder: (context, _) {
        final p = pal(context);
        final sel = themeStore.selected;
        return Scaffold(
          appBar: zAppBar(context, text: 'Tema 3D Premium'),
          body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 28), children: [
            NeoCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              color: p.surface2,
              child: Row(children: [
                Icon(Icons.workspace_premium, color: p.text),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tema 3D gratis untuk semua akun. Pilih tema favoritmu, langsung berlaku di seluruh aplikasi.',
                    style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                ),
              ]),
            ),
            _ThemeRow(
              name: 'Comic 2D (standar)',
              desc: 'Tema bawaan ZARR CHAT (2D)',
              selected: sel.isEmpty,
              swatches: const [],
              comic: true,
              onTap: _pickComic,
            ),
            for (final t in kThemes3D)
              _ThemeRow(
                name: t.name,
                desc: t.desc,
                selected: sel == t.id,
                swatches: t.swatches,
                onTap: () => _pick(t),
              ),
          ]),
        );
      },
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final String name;
  final String desc;
  final bool selected;
  final bool comic;
  final List<List<Color>> swatches;
  final VoidCallback onTap;
  const _ThemeRow({required this.name, required this.desc, required this.selected, required this.swatches, required this.onTap, this.comic = false});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final Widget trailing;
    if (selected) {
      trailing = Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: Color(0xFF1FAA45), shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 20, color: Colors.white),
      );
    } else {
      trailing = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.muted, width: 2)),
      );
    }
    return NeoCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      onTap: onTap,
      child: Row(children: [
        if (comic)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final c in [const Color(0xFFFFDC35), const Color(0xFFFF3F5D), const Color(0xFF171717)])
              Container(
                width: 22,
                height: 36,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFF111111), width: 2)),
              ),
          ])
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final g in swatches)
              Container(
                width: 22,
                height: 36,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: g),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), offset: Offset(0, 3), blurRadius: 5)],
                ),
              ),
          ]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 3),
            Text(desc, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.25)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }
}

/// Pengaturan → Ring Avatar: pilih bingkai foto profil. Grup dan saluran punya ring sendiri di halaman info masing-masing.
class RingAvatarPage extends StatelessWidget {
  const RingAvatarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ringStore,
      builder: (context, _) {
        final p = pal(context);
        final m = app.me;
        final cur = ringStore.style;
        final curName = kRingStyles.firstWhere((r) => r.id == cur, orElse: () => kRingStyles[1]).name;
        Widget tile(RingStyle r) {
          final sel = r.id == cur;
          return Expanded(
            child: NeoCard(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              color: sel ? p.yellow : null,
              onTap: () {
                ringStore.select(r.id);
                app.toast('Ring ${r.name} dipakai.');
              },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Avatar(user: m, size: 76, ringStyle: r.id),
                const SizedBox(height: 10),
                Text(r.name, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: sel ? const Color(0xFF111111) : p.text)),
              ]),
            ),
          );
        }

        return Scaffold(
          appBar: zAppBar(context, text: 'Ring Avatar', centerTitle: true),
          body: ListView(padding: const EdgeInsets.fromLTRB(8, 14, 8, 28), children: [
            NeoCard(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Column(children: [
                Avatar(user: m, size: 150),
                const SizedBox(height: 14),
                Text(curName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ]),
            ),
            for (var i = 0; i < kRingStyles.length; i += 2)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                tile(kRingStyles[i]),
                if (i + 1 < kRingStyles.length) tile(kRingStyles[i + 1]) else const Expanded(child: SizedBox.shrink()),
              ]),
            NeoCard(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              color: p.surface2,
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Ring ini hanya untuk foto profil pada perangkat ini. Ring grup dan saluran diatur terpisah di info grup/saluran oleh admin.', style: TextStyle(color: p.text, fontSize: 12.5))),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    const faq = [
      ['Bagaimana cara mulai chat?', 'Ketuk tombol di tab Chats, cari nama atau nomor (+62…) pengguna yang sudah mendaftar, lalu pilih namanya.'],
      ['Mengapa panggilan tidak tersambung?', 'Panggilan membutuhkan izin mikrofon/kamera, dan idealnya server TURN. Jika jaringan Anda ketat (NAT/seluler), panggilan bisa gagal tanpa TURN. Penerima juga harus sedang membuka aplikasi.'],
      ['Apa arti centang biru?', 'Verifikasi internal ZARR CHAT oleh administrator, bukan verifikasi resmi WhatsApp atau Meta.'],
      ['Siapa yang bisa melihat status saya?', 'Anda memilih saat membuat status: kontak, semua pengguna, atau orang tertentu.'],
      ['Apakah pesan saya dienkripsi end-to-end?', 'Belum. Pesan disimpan di server.'],
    ];
    return Scaffold(
      appBar: zAppBar(context, text: 'Bantuan'),
      body: ListView(padding: const EdgeInsets.only(top: 14, bottom: 24), children: [
        ...faq.map((f) => NeoCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                title: Text(f[0], style: const TextStyle(fontWeight: FontWeight.w800)),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [Align(alignment: Alignment.centerLeft, child: Text(f[1], style: TextStyle(color: p.muted)))],
              ),
            )),
        const NeoSection('Kebijakan privasi'),
        NeoCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('ZARR CHAT menyimpan nomor telepon, nama, foto profil, pesan, dan media Anda agar layanan berfungsi.', style: TextStyle(color: p.muted)),
        ),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: NeoButton('Hubungi developer', primary: false, onPressed: () => showAboutDev(context))),
      ]),
    );
  }
}
