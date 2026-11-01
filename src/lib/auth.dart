// ZARR CHAT - layar pembuka, daftar, masuk, dan lengkapi profil.
import 'dart:io';

import 'package:flutter/material.dart';
import 'avatar_cropper.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'config.dart';
import 'countries.dart';
import 'groups.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

List<Country> _sortedCountries() {
  final l = List<Country>.from(kCountries);
  l.sort((a, b) {
    if (a.iso == 'ID') return -1;
    if (b.iso == 'ID') return 1;
    return a.name.compareTo(b.name);
  });
  return l;
}

Future<void> openLink(String url) async {
  // Tautan undangan grup ZARR CHAT dibuka di dalam aplikasi (halaman "Gabung grup"), bukan di browser.
  final inviteCode = inviteCodeFromUrl(url);
  if (inviteCode != null) {
    openGroupInvite(inviteCode);
    return;
  }
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) app.toast('Tidak dapat membuka tautan.', error: true);
  } catch (_) {
    app.toast('Tidak dapat membuka tautan.', error: true);
  }
}

void showAboutDev(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = pal(ctx);
      return AlertDialog(
        title: const Text('Tentang ZARR CHAT', style: TextStyle(fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/images/logo.png', width: 52, height: 52)),
              const SizedBox(width: 12),
              const Expanded(child: Text('ZARR CHAT\nAplikasi chatting real-time', style: TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 14),
            NeoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Developer', style: TextStyle(color: p.muted, fontSize: 12)),
              const Text(kDevName, style: TextStyle(fontWeight: FontWeight.w900)),
            ])),
            NeoCard(
              onTap: () => openLink('https://t.me/$kDevTelegram'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Telegram', style: TextStyle(color: p.muted, fontSize: 12)),
                const Text('@$kDevTelegram', style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
            ),
            NeoCard(
              onTap: () => openLink('https://www.tiktok.com/@$kDevTikTok'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TikTok', style: TextStyle(color: p.muted, fontSize: 12)),
                const Text('@$kDevTikTok', style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
            ),
            Text(
              'Centang biru di ZARR CHAT adalah verifikasi internal, bukan verifikasi resmi dari WhatsApp, Meta, atau platform lain.',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      );
    },
  );
}

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 88});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: pal(context).line, width: 3),
        boxShadow: [BoxShadow(color: pal(context).line, offset: const Offset(4, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const LogoMark(size: 120),
              const SizedBox(height: 22),
              Text('ZARR CHAT',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: p.text,
                    shadows: [Shadow(color: p.accent, offset: const Offset(3, 4))],
                  )),
              const SizedBox(height: 10),
              Text('Ngobrol, bagikan status, dan telepon teman dalam satu tempat yang rapi dan aman.',
                  textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 15)),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: NeoButton('Daftar Akun', icon: Icons.person_add_alt_1,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen()))),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: NeoButton('Masuk', icon: Icons.login, primary: false,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()))),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => showAboutDev(context), child: const Text('Tentang ZARR CHAT')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pemilih kode negara (daftar + pencarian).
class CountryField extends StatelessWidget {
  final Country value;
  final ValueChanged<Country> onChanged;
  const CountryField({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final c = await showModalBottomSheet<Country>(
          context: context,
          isScrollControlled: true,
          backgroundColor: p.surface,
          builder: (_) => const _CountrySheet(),
        );
        if (c != null) onChanged(c);
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line, width: 2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value.flag, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Text('+${value.dial}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();
  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final List<Country> all = _sortedCountries();
  String q = '';

  @override
  Widget build(BuildContext context) {
    final t = q.trim().toLowerCase();
    final items = t.isEmpty ? all : all.where((c) => c.name.toLowerCase().contains(t) || c.dial.contains(t) || c.iso.toLowerCase() == t).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: neoDeco(context, hint: 'Cari negara atau kode', prefix: const Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => ListTile(
                  leading: Text(items[i].flag, style: const TextStyle(fontSize: 22)),
                  title: Text(items[i].name),
                  trailing: Text('+${items[i].dial}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => Navigator.pop(context, items[i]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String _digitsOf(String raw) => raw.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');

class _PassField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmit;
  const _PassField({required this.controller, required this.hint, this.onSubmit});
  @override
  State<_PassField> createState() => _PassFieldState();
}

class _PassFieldState extends State<_PassField> {
  bool hide = true;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: hide,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: widget.onSubmit,
      decoration: neoDeco(context,
          hint: widget.hint,
          suffix: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide))),
    );
  }
}

class _AuthFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _AuthFrame({required this.title, required this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: zAppBar(context, text: 'ZARR CHAT'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: p.muted)),
            const SizedBox(height: 18),
            ...children,
          ]),
        ),
      ),
    );
  }
}

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
    );

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  Country country = kCountries.firstWhere((c) => c.iso == 'ID', orElse: () => kCountries.first);
  final phone = TextEditingController();
  final name = TextEditingController();
  final pass = TextEditingController();
  final conf = TextEditingController();
  String err = '';
  bool busy = false;

  @override
  void dispose() {
    phone.dispose();
    name.dispose();
    pass.dispose();
    conf.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final digits = _digitsOf(phone.text);
    if (digits.length < 6 || digits.length + country.dial.length > 15) {
      setState(() => err = 'Nomor telepon tidak valid.');
      return;
    }
    final n = name.text.trim();
    if (n.length < 2) {
      setState(() => err = 'Nama minimal 2 karakter.');
      return;
    }
    if (pass.text.length < 6) {
      setState(() => err = 'Kata sandi minimal 6 karakter.');
      return;
    }
    if (pass.text != conf.text) {
      setState(() => err = 'Konfirmasi kata sandi tidak cocok.');
      return;
    }
    setState(() {
      err = '';
      busy = true;
    });
    final nav = Navigator.of(context);
    try {
      final r = await app.api.post('/auth/register', {'phone': '+${country.dial}$digits', 'password': pass.text, 'name': n});
      await app.onAuthenticated(r);
      nav.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return _AuthFrame(
      title: 'Buat Akun Baru',
      subtitle: 'Isi data di bawah untuk mulai menggunakan ZARR CHAT.',
      children: [
        _label('Nomor Telepon'),
        Row(children: [
          CountryField(value: country, onChanged: (c) => setState(() => country = c)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: neoDeco(context, hint: '812 3456 7890'),
            ),
          ),
        ]),
        _label('Nama Tampilan'),
        TextField(controller: name, maxLength: 30, decoration: neoDeco(context, hint: 'Nama yang terlihat oleh pengguna lain')),
        _label('Kata Sandi'),
        _PassField(controller: pass, hint: 'Minimal 6 karakter'),
        _label('Konfirmasi Kata Sandi'),
        _PassField(controller: conf, hint: 'Ulangi kata sandi', onSubmit: (_) => submit()),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err, style: TextStyle(color: p.bad, fontWeight: FontWeight.w700))),
        const SizedBox(height: 18),
        NeoButton('Daftar Sekarang', busy: busy, onPressed: submit),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const LoginScreen())),
            child: const Text('Sudah punya akun? Masuk di sini'),
          ),
        ),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Country country = kCountries.firstWhere((c) => c.iso == 'ID', orElse: () => kCountries.first);
  final phone = TextEditingController();
  final pass = TextEditingController();
  String err = '';
  bool busy = false;

  @override
  void dispose() {
    phone.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final digits = _digitsOf(phone.text);
    if (digits.length < 6 || digits.length + country.dial.length > 15) {
      setState(() => err = 'Nomor telepon tidak valid.');
      return;
    }
    if (pass.text.isEmpty) {
      setState(() => err = 'Masukkan kata sandi Anda.');
      return;
    }
    setState(() {
      err = '';
      busy = true;
    });
    final nav = Navigator.of(context);
    try {
      final r = await app.api.post('/auth/login', {'phone': '+${country.dial}$digits', 'password': pass.text});
      await app.onAuthenticated(r);
      nav.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return _AuthFrame(
      title: 'Selamat Datang Kembali',
      subtitle: 'Masuk dengan nomor telepon dan kata sandi Anda.',
      children: [
        _label('Nomor Telepon'),
        Row(children: [
          CountryField(value: country, onChanged: (c) => setState(() => country = c)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: neoDeco(context, hint: '812 3456 7890'),
            ),
          ),
        ]),
        _label('Kata Sandi'),
        _PassField(controller: pass, hint: 'Kata sandi Anda', onSubmit: (_) => submit()),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err, style: TextStyle(color: p.bad, fontWeight: FontWeight.w700))),
        const SizedBox(height: 18),
        NeoButton('Masuk', busy: busy, onPressed: submit),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const RegisterScreen())),
            child: const Text('Belum punya akun? Daftar di sini'),
          ),
        ),
      ],
    );
  }
}

/// Lengkapi nama + foto bila akun belum punya nama.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final name = TextEditingController();
  String? photoPath;
  String err = '';
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final path = await pickAndCropAvatar(context, title: 'Atur foto profil');
    if (path != null && mounted) setState(() => photoPath = path);
  }

  Future<void> submit() async {
    final n = name.text.trim();
    final ok = RegExp(r"^[\p{L}\p{N}][\p{L}\p{N} ._'-]{1,29}$", unicode: true).hasMatch(n);
    if (!ok) {
      setState(() => err = 'Nama 2–30 karakter, hanya huruf, angka, spasi, titik, garis bawah, atau strip.');
      return;
    }
    setState(() {
      err = '';
      busy = true;
    });
    try {
      final r = asMap(await app.api.post('/auth/profile', {'username': n}));
      app.me = User.fromJson(r['user']);
      if (photoPath != null) {
        try {
          final id = await app.api.upload(photoPath!, 'avatar');
          final r2 = asMap(await app.api.put('/me/avatar', {'mediaId': id}));
          app.me!.avatarUrl = User.fromJson(r2['user']).avatarUrl;
        } catch (e) {
          app.toast('Foto profil belum tersimpan: ${errText(e)}', error: true);
        }
      }
      await app.startApp();
    } catch (e) {
      if (mounted) setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return _AuthFrame(
      title: 'Lengkapi Profil Anda',
      subtitle: 'Pilih nama dan foto yang ingin ditampilkan kepada pengguna lain.',
      children: [
        Center(
          child: GestureDetector(
            onTap: pick,
            child: photoPath == null
                ? const Avatar(name: '?', size: 96)
                : Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.line, width: 2)),
                    child: ClipOval(child: Image.file(File(photoPath!), fit: BoxFit.cover)),
                  ),
          ),
        ),
        Center(child: TextButton.icon(onPressed: pick, icon: const Icon(Icons.photo_camera), label: const Text('Pilih foto profil'))),
        _label('Nama Tampilan'),
        TextField(controller: name, maxLength: 30, decoration: neoDeco(context, hint: 'Contoh: ZARR')),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: TextStyle(color: p.bad, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        NeoButton('Lanjutkan', busy: busy, onPressed: submit),
        const SizedBox(height: 10),
        Center(
          child: TextButton(onPressed: () => app.logout(), child: const Text('Keluar')),
        ),
      ],
    );
  }
}
