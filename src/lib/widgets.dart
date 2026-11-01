// ZARR CHAT - komponen UI yang dipakai berulang.
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart' show errText;
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'wallpaper.dart';

// ============================================================ RING AVATAR

class RingStyle {
  final String id;
  final String name;
  const RingStyle(this.id, this.name);
}

const List<RingStyle> kRingStyles = [
  RingStyle('polos', 'Polos'),
  RingStyle('comic', 'Comic'),
  RingStyle('duo', 'Duo Merah'),
  RingStyle('halftone', 'Halftone'),
  RingStyle('speed', 'Speed Line'),
  RingStyle('pow', 'POW!'),
];

/// Pilihan Ring Avatar FOTO PROFIL (tersimpan di perangkat). Grup dan saluran punya ring sendiri-sendiri (disimpan di server).
class RingStore extends ChangeNotifier {
  String style = 'comic';
  SharedPreferences? _p;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      final v = _p!.getString('zc_ring') ?? 'comic';
      style = kRingStyles.any((r) => r.id == v) ? v : 'comic';
    } catch (_) {
      // tanpa penyimpanan: tetap bawaan
    }
  }

  Future<void> select(String id) async {
    if (!kRingStyles.any((r) => r.id == id) || id == style) return;
    style = id;
    try {
      await _p?.setString('zc_ring', id);
    } catch (_) {}
    notifyListeners();
  }
}

final RingStore ringStore = RingStore();

/// Bingkai ring di sekeliling foto bulat. [box] = ukuran luar; [plain] = diameter foto untuk gaya Polos.
class RingFrame extends StatelessWidget {
  final double box;
  final double plain;
  final String? styleOverride;
  final Widget Function(double diameter) photo;
  const RingFrame({super.key, required this.box, required this.plain, required this.photo, this.styleOverride});

  static double _factor(String st) {
    switch (st) {
      case 'pow':
        return 0.58;
      case 'polos':
        return 1;
      default:
        return 0.8;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ringStore,
      builder: (context, _) {
        final p = pal(context);
        final st = styleOverride ?? ringStore.style;
        final d = st == 'polos' ? plain : box * _factor(st);
        return SizedBox(
          width: box,
          height: box,
          child: CustomPaint(
            painter: _RingPainter(st, p.line, p.yellow, p.accent, p.surface),
            child: Center(child: ClipOval(child: SizedBox(width: d, height: d, child: photo(d)))),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final String style;
  final Color ink;
  final Color yellow;
  final Color red;
  final Color light;
  _RingPainter(this.style, this.ink, this.yellow, this.red, this.light);

  @override
  void paint(Canvas canvas, Size size) {
    if (style == 'polos') return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final rm = r * 0.94; // radius utama; sisanya untuk bayangan keras
    final o = r * 0.06;
    Paint fill(Color col) => Paint()..color = col..style = PaintingStyle.fill..isAntiAlias = true;
    Paint stroke(Color col, double w) => Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = w..isAntiAlias = true;

    if (style == 'pow') {
      const n = 12;
      Path star(Offset ctr, double ro, double ri) {
        final path = Path();
        for (var i = 0; i < n * 2; i++) {
          final rad = i.isEven ? ro : ri;
          final a = -math.pi / 2 + i * math.pi / n;
          final pt = Offset(ctr.dx + rad * math.cos(a), ctr.dy + rad * math.sin(a));
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        return path..close();
      }

      canvas.drawPath(star(c.translate(o, o), rm, rm * 0.78), fill(ink));
      final sp = star(c, rm, rm * 0.78);
      canvas.drawPath(sp, fill(yellow));
      canvas.drawPath(sp, stroke(ink, math.max(1.4, r * 0.05))..strokeJoin = StrokeJoin.miter);
      canvas.drawCircle(c, r * 0.58 + r * 0.06, fill(ink));
      return;
    }

    // Gaya lingkaran: bayangan keras + cincin tinta, lalu hiasan sesuai gaya.
    canvas.drawCircle(c.translate(o, o), rm, fill(ink));
    canvas.drawCircle(c, rm, fill(ink));
    switch (style) {
      case 'comic':
        canvas.drawCircle(c, rm - r * 0.085, stroke(yellow, r * 0.045));
        break;
      case 'duo':
        canvas.drawCircle(c, rm - r * 0.06, stroke(red, r * 0.04));
        canvas.drawCircle(c, rm - r * 0.105, stroke(light, r * 0.022));
        break;
      case 'halftone':
        {
        final rr = rm - r * 0.08;
        canvas.drawCircle(c, rr, stroke(yellow, r * 0.05));
        for (var i = 0; i < 16; i++) {
          final a = i * 2 * math.pi / 16;
          canvas.drawCircle(Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a)), math.max(0.8, r * 0.022), fill(red));
        }
        }
        break;
      case 'speed':
        {
        final rr = rm - r * 0.08;
        final rect = Rect.fromCircle(center: c, radius: rr);
        final paint = stroke(light, math.max(1, r * 0.032));
        const n = 20;
        for (var i = 0; i < n; i++) {
          canvas.drawArc(rect, i * 2 * math.pi / n, 2 * math.pi / n * 0.55, false, paint);
        }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.style != style || o.ink != ink || o.yellow != yellow || o.red != red || o.light != light;
}

/// Halaman pilih Ring Avatar untuk satu grup atau saluran. [onSave] menyimpan ke server.
class RingPickerPage extends StatefulWidget {
  final String title;
  final String note;
  final String initial;
  final Widget Function(double size, String style) preview;
  final Future<void> Function(String id) onSave;
  const RingPickerPage({super.key, required this.title, required this.note, required this.initial, required this.preview, required this.onSave});
  @override
  State<RingPickerPage> createState() => _RingPickerPageState();
}

class _RingPickerPageState extends State<RingPickerPage> {
  late String cur = kRingStyles.any((r) => r.id == widget.initial) ? widget.initial : 'comic';
  bool busy = false;

  Future<void> pick(RingStyle r) async {
    if (busy || r.id == cur) return;
    setState(() => busy = true);
    try {
      await widget.onSave(r.id);
      cur = r.id;
      app.toast('Ring ${r.name} dipakai.');
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final curName = kRingStyles.firstWhere((r) => r.id == cur, orElse: () => kRingStyles[1]).name;
    Widget tile(RingStyle r) {
      final sel = r.id == cur;
      return Expanded(
        child: NeoCard(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 14),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          color: sel ? p.yellow : null,
          onTap: () => pick(r),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            widget.preview(76, r.id),
            const SizedBox(height: 10),
            Text(r.name, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: sel ? const Color(0xFF111111) : p.text)),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: zAppBar(context, text: widget.title, centerTitle: true),
      body: ListView(padding: const EdgeInsets.fromLTRB(8, 14, 8, 28), children: [
        NeoCard(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 14),
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(children: [
            widget.preview(150, cur),
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
            Expanded(child: Text(widget.note, style: TextStyle(color: p.text, fontSize: 12.5))),
          ]),
        ),
      ]),
    );
  }
}

/// Foto profil bulat; bila tidak ada foto tampil huruf pertama nama.
class Avatar extends StatelessWidget {
  final User? user;
  final String? url;
  final String name;
  final double size;
  final Color? ring;
  final VoidCallback? onTap; // bila diisi, foto bisa diketuk (mis. buka pratinjau profil)
  final bool group; // true = tanpa foto tampil ikon grup (bukan huruf pertama)
  final String? ringStyle; // pratinjau gaya ring tertentu (halaman Ring Avatar)
  const Avatar({super.key, this.user, this.url, this.name = '?', this.size = 48, this.ring, this.onTap, this.group = false, this.ringStyle});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final u = user;
    final src = u != null ? u.avatarUrl : url;
    final label = (u != null ? u.username : name).trim();
    final initial = label.isEmpty ? '?' : String.fromCharCodes([label.runes.first]).toUpperCase();

    Widget photo(double d) {
      final fallback = Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        color: p.yellow,
        child: group
            ? Icon(Icons.groups, size: d * 0.56, color: const Color(0xFF111111))
            : Text(initial, style: TextStyle(fontSize: d * 0.42, fontWeight: FontWeight.w900, color: const Color(0xFF111111))),
      );
      if (src == null || src.isEmpty) return fallback;
      return CachedNetworkImage(
        imageUrl: app.api.abs(src),
        httpHeaders: app.api.mediaHeaders,
        width: d,
        height: d,
        fit: BoxFit.cover,
        placeholder: (c, u2) => fallback,
        errorWidget: (c, u2, e) => fallback,
      );
    }

    final Widget box;
    if (ring != null) {
      // Cincin warna (status/panggilan) tetap seperti semula.
      box = Container(
        width: size + 4,
        height: size + 4,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 3)),
        child: ClipOval(child: photo(size)),
      );
    } else {
      box = RingFrame(box: size + 4, plain: size, photo: photo, styleOverride: ringStyle ?? (group ? 'comic' : null));
    }
    if (onTap == null) return box;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: box);
  }
}

// ============================================================ REAKSI PESAN (gaya WhatsApp)

const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
const List<String> kAllReactions = [
  '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😅', '😉', '🙂', '🙃', '😴', '😭', '😢', '😡', '🤯', '😱', '🥳',
  '🥰', '😇', '🤗', '🙄', '😬', '😏', '🤝', '👍', '👎', '👏', '🙌', '🙏', '💪', '👀', '🔥', '✨', '🎉', '💯', '❤️', '🧡',
  '💛', '💚', '💙', '💜', '🖤', '💔', '⭐', '✅', '❌', '❓', '❗', '🎵', '📷', '📍', '🍕', '🍔', '☕', '🍰', '🎂', '🎁',
  '🌹', '🌞', '🌙', '⚽', '🎮', '🚗', '✈️', '🏠', '📱', '💻',
];

/// Semua emoji untuk reaksi (tombol "+").
Future<void> showReactionPicker(BuildContext context, ValueChanged<String> onPick) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal(context).surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: GridView.count(
          crossAxisCount: 8,
          shrinkWrap: true,
          children: [
            for (final e in kAllReactions)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(ctx);
                  onPick(e);
                },
                child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Pil reaksi melayang di dekat pesan yang dipilih (di atasnya; di bawahnya bila tidak muat), seperti WhatsApp.
/// Harus ditaruh di dalam Stack area daftar pesan ([areaKey]); posisi mengikuti gulir daftar.
class ReactionOverlay extends StatelessWidget {
  final GlobalKey areaKey;
  final GlobalKey? msgKey;
  final bool mine;
  final ScrollController scroll;
  final ValueChanged<String> onPick;
  const ReactionOverlay({super.key, required this.areaKey, required this.msgKey, required this.mine, required this.scroll, required this.onPick});

  static const double _h = 54;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, _) {
        final p = pal(context);
        double top = 8;
        final area = areaKey.currentContext?.findRenderObject();
        final box = msgKey?.currentContext?.findRenderObject();
        if (area is RenderBox && box is RenderBox && area.hasSize && box.hasSize && box.attached && area.attached) {
          final off = box.localToGlobal(Offset.zero, ancestor: area);
          top = off.dy - _h - 2;
          if (top < 4) top = off.dy + box.size.height + 2;
          final maxTop = math.max(4.0, area.size.height - _h - 4);
          top = top.clamp(4.0, maxTop).toDouble();
        }
        return Stack(children: [
          Positioned(
            top: top,
            left: mine ? null : 10,
            right: mine ? 10 : null,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.7, end: 1),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              builder: (c, v, child) => Opacity(opacity: v.clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: v, alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: child)),
              child: Material(
                color: p.surface,
                elevation: 8,
                shadowColor: Colors.black,
                shape: StadiumBorder(side: BorderSide(color: p.line, width: 2)),
                child: SizedBox(
                  height: _h,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final e in kQuickReactions)
                        InkResponse(
                          radius: 24,
                          onTap: () => onPick(e),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text(e, style: const TextStyle(fontSize: 28))),
                        ),
                      const SizedBox(width: 2),
                      InkResponse(
                        onTap: () => showReactionPicker(context, onPick),
                        child: Container(
                          width: 34,
                          height: 34,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(color: p.surface2, shape: BoxShape.circle, border: Border.all(color: p.line, width: 1.5)),
                          child: Icon(Icons.add, size: 22, color: p.text),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  final double size;
  final bool rainbow; // true = centang warna-warni untuk akun developer
  const VerifiedBadge({super.key, this.size = 16, this.rainbow = false});

  static const List<Color> _rainbow = [
    Color(0xFFFF3B30), // merah
    Color(0xFFFF9500), // oranye
    Color(0xFFFFD60A), // kuning
    Color(0xFF34C759), // hijau
    Color(0xFF0A84FF), // biru
    Color(0xFFAF52DE), // ungu
  ];

  @override
  Widget build(BuildContext context) {
    if (!rainbow) return Icon(Icons.verified, size: size, color: pal(context).verified);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect r) => const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _rainbow).createShader(r),
      child: Icon(Icons.verified, size: size, color: Colors.white),
    );
  }
}

class NameWithBadge extends StatelessWidget {
  final User user;
  final TextStyle? style;
  const NameWithBadge(this.user, {super.key, this.style});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style ?? const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      if (user.isDeveloper || user.isVerified) Padding(padding: const EdgeInsets.only(left: 4), child: VerifiedBadge(rainbow: user.isDeveloper)),
    ]);
  }
}

class Spin extends StatelessWidget {
  final String? label;
  const Spin({super.key, this.label});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: pal(context).accent),
          if (label != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(label!)),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.text, this.action});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: p.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(text!, textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Tombol bergaya ZARR: tepi tinta tebal.
class NeoButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool busy;
  const NeoButton(this.label, {super.key, this.icon, this.onPressed, this.primary = true, this.danger = false, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final Color bg = danger ? p.bad : (primary ? p.accent : p.surface);
    final Color fg = (danger || primary) ? Colors.white : p.text;
    final enabled = onPressed != null && !busy;
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withAlpha(128),
        disabledForegroundColor: fg.withAlpha(180),
        elevation: 0,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide(color: p.line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (busy)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
        else if (icon != null)
          Icon(icon, size: 18),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ]),
    );
  }
}

InputDecoration neoDeco(BuildContext context, {String? hint, String? label, Widget? suffix, Widget? prefix}) {
  final p = pal(context);
  OutlineInputBorder b(Color c, double w) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    labelText: label,
    filled: true,
    fillColor: p.surface,
    suffixIcon: suffix,
    prefixIcon: prefix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: b(p.line, 2),
    enabledBorder: b(p.line, 2),
    focusedBorder: b(p.accent, 2.5),
    errorBorder: b(p.bad, 2),
    focusedErrorBorder: b(p.bad, 2.5),
  );
}

/// Bilah atas kuning dengan garis tinta di bawahnya.
PreferredSizeWidget zAppBar(BuildContext context, {Widget? title, String? text, List<Widget>? actions, Widget? leading, double? titleSpacing, bool? centerTitle}) {
  final p = pal(context);
  return AppBar(
    backgroundColor: p.yellow,
    foregroundColor: const Color(0xFF111111),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: leading,
    titleSpacing: titleSpacing,
    centerTitle: centerTitle,
    title: title ?? Text(text ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
    actions: actions,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(3),
      child: Container(height: 3, color: p.line),
    ),
  );
}

Future<bool> showConfirm(BuildContext context, String title, String text, String okLabel, {bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel,
              style: TextStyle(fontWeight: FontWeight.w900, color: danger ? pal(ctx).bad : pal(ctx).accentText)),
        ),
      ],
    ),
  );
  return r == true;
}

/// Video call belum tersedia: tampilkan dialog "Coming Soon" (panggilan suara tidak terpengaruh).
Future<void> showVideoCallSoon(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = pal(ctx);
      return Dialog(
        backgroundColor: p.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: p.line, width: 2.5)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.yellow, shape: BoxShape.circle, border: Border.all(color: p.line, width: 2.5)),
              child: const Icon(Icons.videocam, size: 32, color: Color(0xFF111111)),
            ),
            const SizedBox(height: 16),
            const Text('Video Call', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.line, width: 2)),
              child: const Text('Coming Soon', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ),
            const SizedBox(height: 14),
            Text('Fitur ini masih dalam tahap pengembangan.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 15, height: 1.35)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: NeoButton('OK', onPressed: () => Navigator.pop(ctx))),
          ]),
        ),
      );
    },
  );
}

class MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool checked;
  MenuItem(this.icon, this.label, this.onTap, {this.danger = false, this.checked = false});
}

Future<void> showMenuSheet(BuildContext context, List<MenuItem> items, {String? title, Widget? header}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: pal(context).line, width: 2),
    ),
    builder: (ctx) {
      final p = pal(ctx);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(width: 44, height: 5, decoration: BoxDecoration(color: p.divider, borderRadius: BorderRadius.circular(3))),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              ),
            if (header != null) header,
            ...items.map((it) => ListTile(
                  leading: Icon(it.checked ? Icons.check_circle : it.icon, color: it.danger ? p.bad : (it.checked ? p.good : p.text)),
                  title: Text(it.label, style: TextStyle(fontWeight: FontWeight.w700, color: it.danger ? p.bad : p.text)),
                  onTap: () {
                    Navigator.pop(ctx);
                    it.onTap();
                  },
                )),
            const SizedBox(height: 8),
          ]),
        ),
      );
    },
  );
}

/// Kotak bergaya ZARR: tepi tinta tebal + bayangan keras (seperti kartu neo-brutalist).
/// Latar kartu selalu solid sehingga tetap jelas di atas wallpaper / background foto.
class NeoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double radius;
  const NeoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.onTap,
    this.onLongPress,
    this.color,
    this.radius = 16,
  });
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final t3 = themeStore.active;
    if (t3 != null) {
      // Tema 3D Premium: kartu bergradasi dengan bayangan lembut berlapis (kesan timbul).
      final dark = p.brightness == Brightness.dark;
      return Padding(
        padding: margin,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: color == null ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: t3.cardGradient) : null,
            color: color,
            border: Border.all(color: p.line.withAlpha(dark ? 190 : 150), width: 1.6),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(dark ? 170 : 55), offset: const Offset(0, 6), blurRadius: 12),
              BoxShadow(color: t3.glow.withAlpha(dark ? 38 : 60), offset: const Offset(0, 2), blurRadius: 16),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(padding: padding, child: SizedBox(width: double.infinity, child: child)),
            ),
          ),
        ),
      );
    }
    // Di atas background foto (mode terang) tepi hitam kartu menyatu dengan foto gelap:
    // beri garis luar putih tipis agar kartu dan tombol tampak jelas.
    final halo = wallpaper.hasApp && p.brightness == Brightness.light;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: halo
              ? [
                  const BoxShadow(color: Color(0xF2FFFFFF), spreadRadius: 2.5),
                  BoxShadow(color: p.line, offset: const Offset(3, 3), spreadRadius: 1),
                ]
              : [BoxShadow(color: p.line, offset: const Offset(3, 3))],
        ),
        child: Material(
          color: color ?? p.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: p.line, width: 2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(padding: padding, child: SizedBox(width: double.infinity, child: child)),
          ),
        ),
      ),
    );
  }
}

/// Satu baris menu/pengaturan: ikon dalam kotak bertepi + judul + keterangan + (panah / kontrol).
class NeoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final Color? iconBg;
  const NeoTile({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.danger = false, this.iconBg});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final Color fg = danger ? p.bad : p.text;
    return NeoCard(
      onTap: onTap,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconBg ?? (danger ? p.bad.withAlpha(36) : p.yellow),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line, width: 2),
          ),
          child: Icon(icon, size: 24, color: danger ? p.bad : (iconBg == null ? const Color(0xFF111111) : p.text)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: fg)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.25))),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!] else if (onTap != null && !danger) Icon(Icons.chevron_right, color: p.text),
      ]),
    );
  }
}

/// Saklar bergaya ZARR (trek kuning, jempol tinta, tepi tebal).
class NeoSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const NeoSwitch({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Switch(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF111111) : p.line),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.yellow : p.surface),
      trackOutlineColor: WidgetStateProperty.all(p.line),
      trackOutlineWidth: WidgetStateProperty.all(2.5),
    );
  }
}

/// [NeoTile] dengan saklar di kanan; seluruh baris bisa diketuk.
class NeoSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const NeoSwitchTile({super.key, required this.icon, required this.title, this.subtitle, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    return NeoTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: NeoSwitch(value: value, onChanged: onChanged),
    );
  }
}

/// Judul bagian (PRIVASI, SUARA, …) berupa label bertepi supaya tetap terbaca di atas wallpaper.
class NeoSection extends StatelessWidget {
  final String text;
  const NeoSection(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line, width: 2),
          ),
          child: Text(text.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.6, color: p.text)),
        ),
      ),
    );
  }
}

/// Baris daftar (chat / kontak / panggilan) berupa kartu bertepi hitam.
class NeoRow extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  const NeoRow({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.onLongPress, this.color});
  @override
  Widget build(BuildContext context) {
    return NeoCard(
      onTap: onTap,
      onLongPress: onLongPress,
      color: color,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 11),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            title,
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3), child: subtitle),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: pal(context).muted)),
      );
}

// ============================================================ TOMBOL MENU BOT

/// Deretan tombol di bawah pesan BOT MD ZARR CHAT (menu, aksi cepat). Diketuk = kirim perintahnya (atau isi ke kolom ketik).
class BotButtonsBar extends StatelessWidget {
  final List<BotButton> buttons;
  final void Function(BotButton) onTap;
  const BotButtonsBar({super.key, required this.buttons, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: buttons
            .map((b) => Material(
                  color: p.yellow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onTap(b),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.line, width: 2),
                      ),
                      child: Text(b.label, style: const TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// Avatar dengan lencana centang hijau saat barisnya dipilih (mode pilih seperti WhatsApp).
Widget selectableAvatar(BuildContext context, Widget avatar, bool selected) {
  if (!selected) return avatar;
  final p = pal(context);
  return Stack(clipBehavior: Clip.none, children: [
    avatar,
    Positioned(
      right: -3,
      bottom: -3,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: p.good, shape: BoxShape.circle, border: Border.all(color: p.line, width: 2)),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      ),
    ),
  ]);
}
