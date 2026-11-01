// ZARR CHAT - Background aplikasi & wallpaper chat (6 bawaan + foto dari galeri). Belum diatur = tampilan bawaan.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

class WpPreset {
  final String name;
  final String asset;
  const WpPreset(this.name, this.asset);
}

const List<WpPreset> kWallpaperPresets = [
  WpPreset('Neon Live', 'assets/wallpapers/wp1.jpg'),
  WpPreset('Malam Kota', 'assets/wallpapers/wp2.jpg'),
  WpPreset('Senja', 'assets/wallpapers/wp3.jpg'),
  WpPreset('Padang Kabut', 'assets/wallpapers/wp4.jpg'),
  WpPreset('Monokrom', 'assets/wallpapers/wp5.jpg'),
  WpPreset('Malaikat Gelap', 'assets/wallpapers/wp6.jpg'),
];

/// Nilai pilihan: '' = bawaan, 'asset:<path>' = bawaan aplikasi, 'file:<path>' = foto dari galeri.
class WallpaperStore extends ChangeNotifier {
  SharedPreferences? _p;
  String chat = '';
  String appBg = '';
  double chatDim = 0.12; // peredup wallpaper chat (hitam)
  double appVeil = 0.72; // kabut krem di atas background aplikasi agar tulisan tetap jelas
  String customChat = ''; // foto galeri terakhir untuk chat
  String customApp = '';

  bool get hasApp => appBg.isNotEmpty;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      chat = _valid(_p!.getString('wp_chat') ?? '');
      appBg = _valid(_p!.getString('wp_app') ?? '');
      customChat = _valid(_p!.getString('wp_custom_chat') ?? '');
      customApp = _valid(_p!.getString('wp_custom_app') ?? '');
      chatDim = (_p!.getDouble('wp_chat_dim') ?? 0.12).clamp(0.0, 0.7).toDouble();
      appVeil = (_p!.getDouble('wp_app_veil') ?? 0.72).clamp(0.3, 0.95).toDouble();
    } catch (_) {
      // tanpa penyimpanan: tetap bawaan
    }
  }

  // File galeri yang sudah hilang dianggap belum diatur.
  String _valid(String v) {
    if (v.startsWith('file:') && !File(v.substring(5)).existsSync()) return '';
    return v;
  }

  ImageProvider? provider(String v) {
    if (v.startsWith('asset:')) return AssetImage(v.substring(6));
    if (v.startsWith('file:')) return FileImage(File(v.substring(5)));
    return null;
  }

  Future<void> _save(String k, String v) async {
    try {
      await _p?.setString(k, v);
    } catch (_) {}
  }

  Future<void> select(bool forChat, String v) async {
    if (forChat) {
      chat = v;
      await _save('wp_chat', v);
    } else {
      appBg = v;
      await _save('wp_app', v);
    }
    notifyListeners();
  }

  Future<void> setDim(bool forChat, double v) async {
    try {
      if (forChat) {
        chatDim = v;
        await _p?.setDouble('wp_chat_dim', v);
      } else {
        appVeil = v;
        await _p?.setDouble('wp_app_veil', v);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Pilih foto dari galeri, simpan salinannya di penyimpanan aplikasi, lalu langsung dipakai.
  Future<void> pickCustom(bool forChat) async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 3200, imageQuality: 88);
      if (f == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final wd = Directory('${dir.path}/wallpapers');
      if (!wd.existsSync()) wd.createSync(recursive: true);
      final dot = f.path.lastIndexOf('.');
      final ext = dot > f.path.lastIndexOf('/') && f.path.length - dot <= 5 ? f.path.substring(dot).toLowerCase() : '.jpg';
      final dest = '${wd.path}/${forChat ? 'chat' : 'app'}_${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(f.path).copy(dest);
      final old = forChat ? customChat : customApp;
      if (old.startsWith('file:')) {
        try {
          File(old.substring(5)).deleteSync();
        } catch (_) {}
      }
      final v = 'file:$dest';
      if (forChat) {
        customChat = v;
        await _save('wp_custom_chat', v);
      } else {
        customApp = v;
        await _save('wp_custom_app', v);
      }
      await select(forChat, v);
      app.toast('Foto dipasang.');
    } catch (_) {
      app.toast('Tidak dapat memakai foto ini.', error: true);
    }
  }
}

final WallpaperStore wallpaper = WallpaperStore();

/// Lapisan latar. Bila belum diatur: [fallback] (atau tanpa latar bila fallback null).
class WallpaperLayer extends StatelessWidget {
  final bool forChat;
  final Color? fallback;
  final Widget child;
  const WallpaperLayer({super.key, required this.forChat, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wallpaper,
      builder: (context, _) {
        final v = forChat ? wallpaper.chat : wallpaper.appBg;
        final img = wallpaper.provider(v);
        if (img == null) return fallback == null ? child : Container(color: fallback, child: child);
        final veil = forChat
            ? Colors.black.withAlpha((wallpaper.chatDim * 255).round())
            : pal(context).bg.withAlpha((wallpaper.appVeil * 255).round());
        return Stack(fit: StackFit.expand, children: [
          Image(
            image: img,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (c, e, s) => ColoredBox(color: fallback ?? pal(c).bg),
          ),
          ColoredBox(color: veil),
          child,
        ]);
      },
    );
  }
}

/// Pengaturan → Background & Wallpaper.
class WallpaperPage extends StatelessWidget {
  const WallpaperPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: zAppBar(context, text: 'Background & Wallpaper', centerTitle: true),
      body: ListenableBuilder(
        listenable: wallpaper,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
          _section(context, 'Background aplikasi', 'Tampil di semua layar. Belum dipilih = polos bawaan.', false),
          _section(context, 'Wallpaper chat', 'Latar di dalam percakapan. Belum dipilih = bawaan.', true),
          NeoCard(
            margin: const EdgeInsets.only(top: 22),
            color: p.surface2,
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Foto dari galeri disimpan di perangkat ini saja.', style: TextStyle(color: p.text, fontSize: 12.5))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String sub, bool forChat) {
    final p = pal(context);
    final cur = forChat ? wallpaper.chat : wallpaper.appBg;
    final custom = forChat ? wallpaper.customChat : wallpaper.customApp;
    final tiles = <Widget>[
      _Tile(
        selected: cur.isEmpty,
        onTap: () => wallpaper.select(forChat, ''),
        child: Container(
          color: forChat ? p.chatBg : p.bg,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.format_paint_outlined, color: p.text),
            const SizedBox(height: 6),
            Text(forChat ? 'Bawaan' : 'Polos bawaan', style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
          ]),
        ),
      ),
      _Tile(
        selected: false,
        onTap: () => wallpaper.pickCustom(forChat),
        child: Container(
          color: p.yellow,
          alignment: Alignment.center,
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF111111), size: 34),
            SizedBox(height: 8),
            Text('Upload foto', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111111))),
            Text('dari galeri', style: TextStyle(fontSize: 12, color: Color(0xFF111111))),
          ]),
        ),
      ),
      if (custom.isNotEmpty)
        _Tile(
          selected: cur == custom,
          onTap: () => wallpaper.select(forChat, custom),
          label: 'Foto saya',
          child: Image(
            image: ResizeImage(FileImage(File(custom.substring(5))), width: 500),
            fit: BoxFit.cover,
            errorBuilder: (c, e, st) => const Center(child: Icon(Icons.broken_image)),
          ),
        ),
      for (final w in kWallpaperPresets)
        _Tile(
          selected: cur == 'asset:${w.asset}',
          onTap: () => wallpaper.select(forChat, 'asset:${w.asset}'),
          label: w.name,
          child: Image.asset(w.asset, fit: BoxFit.cover, cacheWidth: 500),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      NeoCard(
        margin: const EdgeInsets.only(top: 18, bottom: 14),
        color: p.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: p.text)),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(color: p.text, fontSize: 12.5)),
        ]),
      ),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.9,
        children: tiles,
      ),
      if (cur.isNotEmpty)
        NeoCard(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          child: Row(children: [
            Icon(forChat ? Icons.brightness_6_outlined : Icons.blur_on, size: 20, color: p.text),
            const SizedBox(width: 6),
            Text(forChat ? 'Redupkan' : 'Kabut', style: const TextStyle(fontWeight: FontWeight.w800)),
            Expanded(
              child: Slider(
                value: forChat ? wallpaper.chatDim : wallpaper.appVeil,
                min: forChat ? 0 : 0.3,
                max: forChat ? 0.7 : 0.95,
                activeColor: p.accent,
                onChanged: (v) => wallpaper.setDim(forChat, v),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? label;
  const _Tile({required this.selected, required this.onTap, required this.child, this.label});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final border = selected ? p.accent : p.line;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: selected ? 4 : 3),
          boxShadow: [BoxShadow(color: p.line, offset: const Offset(4, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            child,
            if (label != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)]),
                  ),
                  child: Text(label!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            if (selected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
