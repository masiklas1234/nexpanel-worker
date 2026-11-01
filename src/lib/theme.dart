// ZARR CHAT - tema (kuning, krem, pink, tinta) bergaya neo-brutalist seperti versi web.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ZPalette {
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color divider;
  final Color text;
  final Color muted;
  final Color accent;
  final Color yellow;
  final Color accentText;
  final Color bubbleIn;
  final Color bubbleOut;
  final Color chatBg;
  final Color good;
  final Color bad;
  final Color verified;
  const ZPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.divider,
    required this.text,
    required this.muted,
    required this.accent,
    required this.yellow,
    required this.accentText,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.chatBg,
    required this.good,
    required this.bad,
    required this.verified,
  });

  static const ZPalette light = ZPalette(
    brightness: Brightness.light,
    bg: Color(0xFFFFF9E7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFFF3C4),
    line: Color(0xFF111111),
    divider: Color(0xFFE4D9AE),
    text: Color(0xFF111111),
    muted: Color(0xFF5E5841),
    accent: Color(0xFFFF3F5D),
    yellow: Color(0xFFFFDC35),
    accentText: Color(0xFFC7102F),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFFFFDC35),
    chatBg: Color(0xFFFFF6D6),
    good: Color(0xFF157A31),
    bad: Color(0xFFD4163A),
    verified: Color(0xFF168BD0),
  );

  static const ZPalette dark = ZPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0B0B),
    surface: Color(0xFF171717),
    surface2: Color(0xFF222018),
    line: Color(0xFFF5EDC8),
    divider: Color(0xFF3A3622),
    text: Color(0xFFFFF9E7),
    muted: Color(0xFFBDB48C),
    accent: Color(0xFFFF3F5D),
    yellow: Color(0xFFFFDC35),
    accentText: Color(0xFFFF7088),
    bubbleIn: Color(0xFF232323),
    bubbleOut: Color(0xFFFFDC35),
    chatBg: Color(0xFF101010),
    good: Color(0xFF5FD27C),
    bad: Color(0xFFF0405F),
    verified: Color(0xFF4DB6F5),
  );
}

/// Palet aktif. Tema 3D Premium (bila dipilih; gratis untuk semua akun) menggantikan palet terang/gelap bawaan.
/// Theme.of selalu dipanggil lebih dulu agar widget ikut dibangun ulang saat tema berganti.
ZPalette pal(BuildContext context) {
  final b = Theme.of(context).brightness;
  final a = themeStore.palette;
  if (a != null) return a;
  return b == Brightness.dark ? ZPalette.dark : ZPalette.light;
}

ThemeData buildTheme(Brightness b, {ZPalette? palette}) {
  final p = palette ?? (b == Brightness.dark ? ZPalette.dark : ZPalette.light);
  final scheme = b == Brightness.dark
      ? ColorScheme.dark(
          primary: p.accent,
          onPrimary: Colors.white,
          secondary: p.yellow,
          onSecondary: const Color(0xFF111111),
          surface: p.surface,
          onSurface: p.text,
          error: p.bad,
        )
      : ColorScheme.light(
          primary: p.accent,
          onPrimary: Colors.white,
          secondary: p.yellow,
          onSecondary: const Color(0xFF111111),
          surface: p.surface,
          onSurface: p.text,
          error: p.bad,
        );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.surface,
    dividerColor: p.divider,
    splashFactory: InkRipple.splashFactory,
  );
}

// ============================================================ TEMA 3D PREMIUM

/// Satu tema 3D: id tersimpan di perangkat, palet dipakai seluruh aplikasi.
class Theme3D {
  final String id;
  final String name;
  final String desc;
  final ZPalette palette;
  final List<List<Color>> swatches; // tiap kotak contoh = gradasi atas -> bawah
  final List<Color> cardGradient; // gradasi kartu bergaya 3D
  final Color glow; // warna cahaya/bayangan lembut
  const Theme3D({
    required this.id,
    required this.name,
    required this.desc,
    required this.palette,
    required this.swatches,
    required this.cardGradient,
    required this.glow,
  });
}

const List<Theme3D> kThemes3D = [
  Theme3D(
    id: 'gold',
    name: 'Emas 3D',
    desc: 'Kartu emas timbul di latar hitam pekat',
    palette: ZPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF080602),
      surface: Color(0xFF1B1507),
      surface2: Color(0xFF2B2109),
      line: Color(0xFFB8860B),
      divider: Color(0xFF3D2F0C),
      text: Color(0xFFFFF4D6),
      muted: Color(0xFFCDB677),
      accent: Color(0xFFB36B00),
      yellow: Color(0xFFFFC21A),
      accentText: Color(0xFFFFCB47),
      bubbleIn: Color(0xFF2A210C),
      bubbleOut: Color(0xFFFFD45C),
      chatBg: Color(0xFF0E0A03),
      good: Color(0xFF5FD27C),
      bad: Color(0xFFF0405F),
      verified: Color(0xFF4DB6F5),
    ),
    swatches: [
      [Color(0xFF3A2A00), Color(0xFF000000)],
      [Color(0xFF3B3022), Color(0xFF0F0B07)],
      [Color(0xFF6B4E0A), Color(0xFF2A1E00)],
      [Color(0xFFFFD45C), Color(0xFFFFB400)],
    ],
    cardGradient: [Color(0xFF2E230A), Color(0xFF151004)],
    glow: Color(0xFFFFB400),
  ),
  Theme3D(
    id: 'ocean',
    name: 'Samudra 3D',
    desc: 'Biru laut dalam, kartu menonjol',
    palette: ZPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF020B16),
      surface: Color(0xFF0A2038),
      surface2: Color(0xFF0F2E50),
      line: Color(0xFF2E86C1),
      divider: Color(0xFF123354),
      text: Color(0xFFE6F4FF),
      muted: Color(0xFF8DB7D9),
      accent: Color(0xFF0B6FB8),
      yellow: Color(0xFF4FC3F7),
      accentText: Color(0xFF6CCBFF),
      bubbleIn: Color(0xFF0F2E50),
      bubbleOut: Color(0xFF7FD0FF),
      chatBg: Color(0xFF031322),
      good: Color(0xFF5FD27C),
      bad: Color(0xFFF0405F),
      verified: Color(0xFF4DB6F5),
    ),
    swatches: [
      [Color(0xFF05213C), Color(0xFF000912)],
      [Color(0xFF0B4378), Color(0xFF021B33)],
      [Color(0xFF1479B8), Color(0xFF053A63)],
      [Color(0xFF8EDBFF), Color(0xFF1FB4FF)],
    ],
    cardGradient: [Color(0xFF0E3358), Color(0xFF071A2E)],
    glow: Color(0xFF29B6F6),
  ),
  Theme3D(
    id: 'neon',
    name: 'Neon 3D',
    desc: 'Hijau menyala dengan bayangan dalam',
    palette: ZPalette(
      brightness: Brightness.dark,
      bg: Color(0xFF010A03),
      surface: Color(0xFF07200E),
      surface2: Color(0xFF0C2F16),
      line: Color(0xFF1FA83A),
      divider: Color(0xFF0F3A1B),
      text: Color(0xFFE8FFE9),
      muted: Color(0xFF8FD39A),
      accent: Color(0xFF138A2B),
      yellow: Color(0xFF39FF14),
      accentText: Color(0xFF5CFF7A),
      bubbleIn: Color(0xFF0C2F16),
      bubbleOut: Color(0xFF63FF7E),
      chatBg: Color(0xFF020F05),
      good: Color(0xFF5FD27C),
      bad: Color(0xFFF0405F),
      verified: Color(0xFF4DB6F5),
    ),
    swatches: [
      [Color(0xFF05260F), Color(0xFF000000)],
      [Color(0xFF0A3015), Color(0xFF000A02)],
      [Color(0xFF1B7A38), Color(0xFF052A10)],
      [Color(0xFF6BFF4D), Color(0xFF1FFF00)],
    ],
    cardGradient: [Color(0xFF0D3A1A), Color(0xFF05180A)],
    glow: Color(0xFF39FF14),
  ),
  Theme3D(
    id: 'sakura',
    name: 'Sakura 3D',
    desc: 'Terang merah muda, timbul lembut',
    palette: ZPalette(
      brightness: Brightness.light,
      bg: Color(0xFFFFF0F5),
      surface: Color(0xFFFFFAFC),
      surface2: Color(0xFFFFE0EC),
      line: Color(0xFF7A3B55),
      divider: Color(0xFFF2C6D8),
      text: Color(0xFF3A1626),
      muted: Color(0xFF8A5A70),
      accent: Color(0xFFD81B60),
      yellow: Color(0xFFFFB3CF),
      accentText: Color(0xFFB0124A),
      bubbleIn: Color(0xFFFFFFFF),
      bubbleOut: Color(0xFFFFC1D8),
      chatBg: Color(0xFFFFE9F1),
      good: Color(0xFF157A31),
      bad: Color(0xFFD4163A),
      verified: Color(0xFF168BD0),
    ),
    swatches: [
      [Color(0xFFFFFFFF), Color(0xFFFFE3EE)],
      [Color(0xFFFFB6D3), Color(0xFFFF78AE)],
      [Color(0xFFFFE9F2), Color(0xFFFFB8D2)],
      [Color(0xFF3A3A3A), Color(0xFF0E0E0E)],
    ],
    cardGradient: [Color(0xFFFFFFFF), Color(0xFFFFE4EE)],
    glow: Color(0xFFFF6FA5),
  ),
];

/// Menyimpan pilihan Tema 3D di perangkat. '' = Comic 2D (standar, terang/gelap sesuai pengaturan Tema).
class ThemeStore extends ChangeNotifier {
  String selected = '';
  SharedPreferences? _p;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      final v = _p!.getString('zc_theme3d') ?? '';
      selected = byId(v) == null ? '' : v;
    } catch (_) {
      // tanpa penyimpanan: tetap Comic 2D
    }
  }

  Theme3D? byId(String id) {
    for (final t in kThemes3D) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Tema 3D yang sedang berlaku (null = Comic 2D).
  Theme3D? get active => byId(selected);
  ZPalette? get palette => active?.palette;
  bool get is3d => active != null;

  Future<void> select(String id) async {
    final next = byId(id) == null ? '' : id;
    if (next == selected) return;
    selected = next;
    try {
      await _p?.setString('zc_theme3d', next);
    } catch (_) {}
    notifyListeners();
  }
}

final ThemeStore themeStore = ThemeStore();
