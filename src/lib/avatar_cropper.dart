// ZARR CHAT - atur foto profil/grup/saluran seperti WhatsApp: pilih gambar -> geser, zoom, putar di dalam bingkai bulat -> Selesai.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pilih gambar dari galeri lalu buka layar "Atur foto".
/// Mengembalikan path file PNG (persegi 512x512) hasil atur, atau null bila dibatalkan / gagal.
Future<String?> pickAndCropAvatar(BuildContext context, {String title = 'Atur foto'}) async {
  XFile? picked;
  try {
    picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 92);
  } catch (_) {
    app.toast('Tidak dapat membuka galeri.', error: true);
    return null;
  }
  if (picked == null || !context.mounted) return null;
  return cropAvatar(context, picked.path, title: title);
}

/// Membuka layar atur foto untuk file gambar [imagePath].
Future<String?> cropAvatar(BuildContext context, String imagePath, {String title = 'Atur foto'}) {
  return Navigator.of(context).push<String>(MaterialPageRoute<String>(builder: (_) => AvatarCropperPage(imagePath: imagePath, title: title)));
}

/// Menggambar gambar (diputar kelipatan 90 derajat, diperbesar, digeser) di dalam bingkai persegi sisi [side].
/// Dipakai oleh layar atur dan oleh ekspor, sehingga hasil akhir identik dengan yang terlihat.
class _CropMath {
  final int imgW;
  final int imgH;
  final int turns; // 0..3 putaran 90 derajat
  _CropMath(this.imgW, this.imgH, this.turns);

  double get w => (turns.isOdd ? imgH : imgW).toDouble();
  double get h => (turns.isOdd ? imgW : imgH).toDouble();

  /// Skala dasar: gambar persis menutupi bingkai (sisi terpendek = sisi bingkai).
  double base(double side) => side / math.min(w, h);

  /// Geser maksimum agar bingkai selalu terisi gambar (offset dihitung dari tengah bingkai).
  Offset maxOffset(double side, double zoom) {
    final k = base(side) * zoom;
    return Offset(math.max(0.0, (w * k - side) / 2), math.max(0.0, (h * k - side) / 2));
  }

  Offset clamp(Offset o, double side, double zoom) {
    final m = maxOffset(side, zoom);
    return Offset(o.dx.clamp(-m.dx, m.dx).toDouble(), o.dy.clamp(-m.dy, m.dy).toDouble());
  }
}

class _AvatarPainter extends CustomPainter {
  final ui.Image image;
  final int turns;
  final double zoom;
  final Offset offset; // piksel layar dari tengah bingkai
  final double side; // diameter bingkai
  final bool editing;
  final int rev;
  _AvatarPainter(this.image, this.turns, this.zoom, this.offset, this.side, this.rev, {this.editing = true});

  void _content(Canvas canvas, Offset center) {
    final m = _CropMath(image.width, image.height, turns);
    final k = m.base(side) * zoom;
    canvas.save();
    canvas.translate(center.dx + offset.dx, center.dy + offset.dy);
    canvas.rotate(turns * math.pi / 2);
    canvas.scale(k, k);
    canvas.drawImage(image, Offset(-image.width / 2, -image.height / 2), Paint()..filterQuality = FilterQuality.high..isAntiAlias = true);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (!editing) {
      canvas.clipRect(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      _content(canvas, center);
      return;
    }
    // Gambar utuh (terlihat samar di luar lingkaran supaya mudah diposisikan).
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _content(canvas, center);
    canvas.restore();
    // Redam area di luar lingkaran.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: side / 2));
    canvas.drawPath(outside, Paint()..color = const Color(0xB8000000));
    // Lingkaran + garis bantu tipis.
    canvas.drawCircle(center, side / 2, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);
    final guide = Paint()..color = const Color(0x40FFFFFF)..strokeWidth = 1;
    final r = side / 2;
    for (var i = 1; i < 3; i++) {
      final d = -r + side * i / 3;
      final half = math.sqrt(math.max(0.0, r * r - d * d));
      canvas.drawLine(Offset(center.dx + d, center.dy - half), Offset(center.dx + d, center.dy + half), guide);
      canvas.drawLine(Offset(center.dx - half, center.dy + d), Offset(center.dx + half, center.dy + d), guide);
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter old) => old.rev != rev || old.image != image || old.side != side;
}

class AvatarCropperPage extends StatefulWidget {
  final String imagePath;
  final String title;
  const AvatarCropperPage({super.key, required this.imagePath, this.title = 'Atur foto'});
  @override
  State<AvatarCropperPage> createState() => _AvatarCropperPageState();
}

class _AvatarCropperPageState extends State<AvatarCropperPage> {
  static const double _maxZoom = 6;
  static const int _outSize = 512;

  ui.Image? image;
  String? error;
  bool busy = false;

  int turns = 0;
  double zoom = 1;
  Offset offset = Offset.zero;
  int rev = 0;
  double _side = 280;

  double _startZoom = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  Offset _stageCenter = Offset.zero;

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
      if (mounted) setState(() => error = 'Gambar tidak dapat dibuka. Coba pilih gambar lain.');
    }
  }

  _CropMath get _m => _CropMath(image!.width, image!.height, turns);

  void _touch(VoidCallback f) => setState(() {
        f();
        offset = _m.clamp(offset, _side, zoom);
        rev++;
      });

  void _onStart(ScaleStartDetails d) {
    _startZoom = zoom;
    _startOffset = offset;
    _startFocal = d.localFocalPoint;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    if (image == null) return;
    final newZoom = (_startZoom * d.scale).clamp(1.0, _maxZoom).toDouble();
    // Titik gambar yang ada di bawah jari tetap di bawah jari saat zoom + geser.
    final v = (_startFocal - _stageCenter - _startOffset) / _startZoom;
    final next = (d.localFocalPoint - _stageCenter) - v * newZoom;
    _touch(() {
      zoom = newZoom;
      offset = next;
    });
  }

  void _setZoomFromSlider(double v) {
    final ratio = v / zoom;
    _touch(() {
      offset = offset * ratio;
      zoom = v;
    });
  }

  void _rotate() {
    HapticFeedback.selectionClick();
    _touch(() {
      turns = (turns + 3) % 4; // putar ke kiri 90 derajat
      zoom = 1;
      offset = Offset.zero;
    });
  }

  void _reset() => _touch(() {
        turns = 0;
        zoom = 1;
        offset = Offset.zero;
      });

  Future<void> _done() async {
    final im = image;
    if (im == null || busy) return;
    setState(() => busy = true);
    try {
      final out = _outSize.toDouble();
      final ratio = out / _side;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      _AvatarPainter(im, turns, zoom, offset * ratio, out, 0, editing: false).paint(canvas, Size(out, out));
      final pic = rec.endRecording();
      final rendered = await pic.toImage(_outSize, _outSize);
      final bd = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      pic.dispose();
      if (bd == null) throw Exception('encode');
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes), flush: true);
      if (mounted) Navigator.of(context).pop(f.path);
    } catch (_) {
      app.toast('Gagal menyimpan foto. Coba lagi.', error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: zAppBar(
        context,
        text: widget.title,
        actions: [
          IconButton(tooltip: 'Atur ulang', icon: const Icon(Icons.restart_alt), onPressed: image == null ? null : _reset),
        ],
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 16),
                  NeoButton('Kembali', icon: Icons.arrow_back, onPressed: () => Navigator.of(context).pop()),
                ]),
              ),
            )
          : image == null
              ? const Spin()
              : Column(children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final side = math.max(120.0, math.min(c.maxWidth - 32, c.maxHeight - 24));
                      if (side != _side) {
                        _side = side;
                        offset = _m.clamp(offset, _side, zoom);
                      }
                      _stageCenter = Offset(c.maxWidth / 2, c.maxHeight / 2);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _onStart,
                        onScaleUpdate: _onUpdate,
                        child: ClipRect(
                          child: CustomPaint(
                            size: Size(c.maxWidth, c.maxHeight),
                            painter: _AvatarPainter(image!, turns, zoom, offset, _side, rev),
                          ),
                        ),
                      );
                    }),
                  ),
                  Container(
                    color: p.surface,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: SafeArea(
                      top: false,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Geser dan cubit untuk mengatur posisi foto', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 12)),
                        Row(children: [
                          Icon(Icons.zoom_out, size: 20, color: p.text),
                          Expanded(
                            child: Slider(
                              value: zoom.clamp(1.0, _maxZoom).toDouble(),
                              min: 1,
                              max: _maxZoom,
                              activeColor: p.accent,
                              onChanged: _setZoomFromSlider,
                            ),
                          ),
                          Icon(Icons.zoom_in, size: 20, color: p.text),
                          const SizedBox(width: 4),
                          IconButton(tooltip: 'Putar', icon: Icon(Icons.rotate_left, color: p.text), onPressed: _rotate),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: NeoButton('Batal', primary: false, onPressed: busy ? null : () => Navigator.of(context).pop())),
                          const SizedBox(width: 12),
                          Expanded(child: NeoButton('Selesai', icon: Icons.check, busy: busy, onPressed: _done)),
                        ]),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
