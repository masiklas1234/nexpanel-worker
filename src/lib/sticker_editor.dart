// ZARR CHAT - editor sticker: zoom, geser, putar, balik, pilih latar, lalu ekspor PNG 512x512.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Membuka editor. Mengembalikan path file PNG hasil edit, atau null bila dibatalkan.
Future<String?> openStickerEditor(BuildContext context, String imagePath) {
  return Navigator.of(context).push<String>(MaterialPageRoute<String>(builder: (_) => StickerEditorPage(imagePath: imagePath)));
}

class _Tx {
  double scale = 1; // 1 = gambar muat utuh di dalam bingkai
  double rotation = 0; // radian
  Offset offset = Offset.zero; // dalam satuan ukuran bingkai (0.5 = setengah bingkai)
  bool flip = false;
  Color? bg; // null = transparan
}

/// Menggambar gambar + bingkai. Dipakai oleh layar edit dan oleh ekspor sehingga hasilnya identik.
class _StickerPainter extends CustomPainter {
  final ui.Image image;
  final _Tx tx;
  final double crop; // sisi bingkai (px)
  final bool editing;
  final Color dim;
  final Color border;
  final int rev; // naik setiap perubahan agar repaint
  _StickerPainter(this.image, this.tx, this.crop, this.rev, {this.editing = true, this.dim = const Color(0xB3000000), this.border = Colors.white});

  void _content(Canvas canvas, Offset center) {
    canvas.save();
    canvas.translate(center.dx + tx.offset.dx * crop, center.dy + tx.offset.dy * crop);
    canvas.rotate(tx.rotation);
    final base = crop / math.max(image.width, image.height);
    final k = base * tx.scale;
    canvas.scale(tx.flip ? -k : k, k);
    canvas.drawImage(image, Offset(-image.width / 2, -image.height / 2), Paint()..filterQuality = FilterQuality.high..isAntiAlias = true);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final frame = Rect.fromCenter(center: center, width: crop, height: crop);
    if (!editing) {
      // Ekspor: hanya isi bingkai.
      canvas.clipRect(frame);
      if (tx.bg != null) canvas.drawRect(frame, Paint()..color = tx.bg!);
      _content(canvas, center);
      return;
    }
    // Latar kotak-kotak (tanda transparan) atau warna latar.
    canvas.save();
    canvas.clipRect(frame);
    if (tx.bg != null) {
      canvas.drawRect(frame, Paint()..color = tx.bg!);
    } else {
      const cell = 14.0;
      final a = Paint()..color = const Color(0xFF3A3A3A);
      final b = Paint()..color = const Color(0xFF2A2A2A);
      for (var y = 0; y * cell < crop; y++) {
        for (var x = 0; x * cell < crop; x++) {
          canvas.drawRect(Rect.fromLTWH(frame.left + x * cell, frame.top + y * cell, cell, cell), (x + y) % 2 == 0 ? a : b);
        }
      }
    }
    canvas.restore();
    // Gambar utuh (terlihat samar di luar bingkai agar mudah diposisikan).
    _content(canvas, center);
    // Redam area di luar bingkai.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frame);
    canvas.drawPath(outside, Paint()..color = dim);
    // Bingkai + garis bantu 3x3.
    canvas.drawRect(frame, Paint()..color = border..style = PaintingStyle.stroke..strokeWidth = 2.5);
    final guide = Paint()..color = const Color(0x55FFFFFF)..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final d = crop * i / 3;
      canvas.drawLine(Offset(frame.left + d, frame.top), Offset(frame.left + d, frame.bottom), guide);
      canvas.drawLine(Offset(frame.left, frame.top + d), Offset(frame.right, frame.top + d), guide);
    }
    // Sudut tebal.
    final corner = Paint()..color = border..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.square;
    const l = 22.0;
    for (final c in [frame.topLeft, frame.topRight, frame.bottomLeft, frame.bottomRight]) {
      final sx = c.dx == frame.left ? 1.0 : -1.0;
      final sy = c.dy == frame.top ? 1.0 : -1.0;
      canvas.drawLine(c, c + Offset(sx * l, 0), corner);
      canvas.drawLine(c, c + Offset(0, sy * l), corner);
    }
  }

  @override
  bool shouldRepaint(covariant _StickerPainter old) => old.rev != rev || old.image != image || old.crop != crop;
}

class StickerEditorPage extends StatefulWidget {
  final String imagePath;
  const StickerEditorPage({super.key, required this.imagePath});
  @override
  State<StickerEditorPage> createState() => _StickerEditorPageState();
}

class _StickerEditorPageState extends State<StickerEditorPage> {
  static const double _minScale = 0.2;
  static const double _maxScale = 8;

  ui.Image? image;
  String? error;
  bool busy = false;
  final _Tx tx = _Tx();
  int rev = 0;

  double _startScale = 1;
  double _startRot = 0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _cropSide = 300;

  static const List<(String, Color?)> _bgs = [
    ('Transparan', null),
    ('Putih', Colors.white),
    ('Hitam', Colors.black),
    ('Kuning', Color(0xFFFFDC35)),
    ('Pink', Color(0xFFFF3F5D)),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => image = frame.image);
    } catch (_) {
      if (mounted) setState(() => error = 'Gambar tidak dapat dibuka.');
    }
  }

  void _touch(VoidCallback f) => setState(() {
        f();
        rev++;
      });

  double get _fillScale {
    final im = image;
    if (im == null) return 1;
    return math.max(im.width, im.height) / math.min(im.width, im.height);
  }

  void _onStart(ScaleStartDetails d) {
    _startScale = tx.scale;
    _startRot = tx.rotation;
    _startOffset = tx.offset;
    _startFocal = d.focalPoint;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    _touch(() {
      tx.scale = (_startScale * d.scale).clamp(_minScale, _maxScale);
      tx.rotation = _startRot + d.rotation;
      tx.offset = _startOffset + (d.focalPoint - _startFocal) / _cropSide;
    });
  }

  void _reset() => _touch(() {
        tx.scale = 1;
        tx.rotation = 0;
        tx.offset = Offset.zero;
        tx.flip = false;
      });

  void _rotate90() => _touch(() {
        tx.rotation -= math.pi / 2;
        // rapikan agar tetap kelipatan 90° bila sebelumnya sudah lurus
        final q = (tx.rotation / (math.pi / 2)).roundToDouble();
        if ((tx.rotation - q * math.pi / 2).abs() < 0.2) tx.rotation = q * math.pi / 2;
      });

  Future<void> _done() async {
    final im = image;
    if (im == null || busy) return;
    setState(() => busy = true);
    try {
      List<int>? bytes;
      // Batas server untuk sticker 1 MB: turunkan ukuran bila PNG terlalu besar.
      for (final side in const [512, 448, 384, 320, 256]) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        final s = side.toDouble();
        _StickerPainter(im, tx, s, 0, editing: false).paint(canvas, Size(s, s));
        final pic = rec.endRecording();
        final out = await pic.toImage(side, side);
        final bd = await out.toByteData(format: ui.ImageByteFormat.png);
        out.dispose();
        pic.dispose();
        if (bd == null) continue;
        final b = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
        bytes = b;
        if (b.length <= 900 * 1024) break;
      }
      if (bytes == null) throw Exception('encode');
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/sticker_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes, flush: true);
      if (mounted) Navigator.of(context).pop(f.path);
    } catch (_) {
      app.toast('Gagal membuat sticker. Coba lagi.', error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    const ink = Color(0xFF111111);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: zAppBar(
        context,
        text: 'Edit sticker',
        actions: [
          IconButton(tooltip: 'Atur ulang', icon: const Icon(Icons.restart_alt), onPressed: image == null ? null : _reset),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!, style: const TextStyle(color: Colors.white)))
          : image == null
              ? const Spin()
              : Column(children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      _cropSide = math.min(c.maxWidth - 32, c.maxHeight - 16).clamp(120.0, 520.0);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _onStart,
                        onScaleUpdate: _onUpdate,
                        child: ClipRect(
                          child: CustomPaint(
                            size: Size(c.maxWidth, c.maxHeight),
                            painter: _StickerPainter(image!, tx, _cropSide, rev),
                          ),
                        ),
                      );
                    }),
                  ),
                  Container(
                    color: p.surface,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SafeArea(
                      top: false,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Cubit untuk zoom • geser untuk memindah • putar dengan dua jari',
                            textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12)),
                        Row(children: [
                          const Icon(Icons.zoom_out, size: 20),
                          Expanded(
                            child: Slider(
                              value: tx.scale.clamp(_minScale, 4.0),
                              min: _minScale,
                              max: 4,
                              activeColor: p.accent,
                              onChanged: (v) => _touch(() => tx.scale = v),
                            ),
                          ),
                          const Icon(Icons.zoom_in, size: 20),
                        ]),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          _tool(Icons.rotate_left, 'Putar', _rotate90),
                          _tool(Icons.flip, 'Balik', () => _touch(() => tx.flip = !tx.flip)),
                          _tool(Icons.fit_screen, 'Pas', () => _touch(() {
                                tx.scale = 1;
                                tx.offset = Offset.zero;
                              })),
                          _tool(Icons.crop_square, 'Penuh', () => _touch(() {
                                tx.scale = _fillScale;
                                tx.offset = Offset.zero;
                              })),
                        ]),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 38,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final b in _bgs)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(b.$1, style: TextStyle(fontWeight: FontWeight.w800, color: tx.bg == b.$2 ? ink : p.text)),
                                  avatar: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: b.$2 ?? Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: p.line, width: 1.5),
                                    ),
                                    child: b.$2 == null ? const Icon(Icons.block, size: 12) : null,
                                  ),
                                  selected: tx.bg == b.$2,
                                  selectedColor: p.yellow,
                                  backgroundColor: p.surface,
                                  side: BorderSide(color: p.line, width: 1.5),
                                  showCheckmark: false,
                                  onSelected: (_) => _touch(() => tx.bg = b.$2),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: NeoButton('Buat sticker', icon: Icons.check, busy: busy, onPressed: _done)),
                      ]),
                    ),
                  ),
                ]),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) {
    final p = pal(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: p.text),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
        ]),
      ),
    );
  }
}
