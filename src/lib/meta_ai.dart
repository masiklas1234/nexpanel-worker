// ZARR CHAT - ZARR CHAT META AI: tombol bulat logo Meta AI (di atas tombol "+") dan tampilan teks jawaban AI.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'auth.dart';
import 'chats_tab.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

const String kMetaAiAsset = 'assets/images/meta_ai.png';

bool _opening = false;

/// Membuka chat pribadi akun ini dengan Meta AI (dibuat otomatis oleh server pada pembukaan pertama).
Future<void> openMetaAi(BuildContext context) async {
  if (_opening) return;
  _opening = true;
  try {
    final r = asMap(await app.api.get('/meta-ai'));
    final id = r['conversationId'];
    if (id is int) {
      final peer = User.fromJson(r['peer']);
      peer.isBot = true;
      peer.isMetaAi = true;
      peer.isVerified = true;
      peer.online = true;
      openChat(context, id, peer);
    }
  } catch (e) {
    app.toast(errText(e), error: true);
  } finally {
    _opening = false;
  }
}

/// Tombol bulat logo Meta AI + centang biru kecil (seperti WhatsApp), diletakkan di atas tombol "+".
class MetaAiFab extends StatefulWidget {
  const MetaAiFab({super.key});
  @override
  State<MetaAiFab> createState() => _MetaAiFabState();
}

class _MetaAiFabState extends State<MetaAiFab> {
  bool loading = false;

  Future<void> tap() async {
    if (loading) return;
    setState(() => loading = true);
    await openMetaAi(context);
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    const double d = 58;
    return Semantics(
      button: true,
      label: 'Meta AI',
      child: GestureDetector(
        onTap: tap,
        child: SizedBox(
          width: d + 6,
          height: d + 6,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
                border: Border.all(color: p.line, width: 3),
                boxShadow: [BoxShadow(color: p.line, offset: const Offset(3, 3))],
              ),
              child: ClipOval(
                child: loading
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)))
                    : Image.asset(kMetaAiAsset, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface),
                child: const VerifiedBadge(size: 19),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Teks jawaban AI: *tebal*, **tebal**, _miring_, `kode`, blok ```kode```, daftar, judul, dan tautan yang bisa diketuk.
class AiText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  const AiText(this.text, {super.key, required this.style, required this.linkColor});
  @override
  State<AiText> createState() => _AiTextState();
}

class _AiTextState extends State<AiText> {
  final List<TapGestureRecognizer> _recs = [];

  static final RegExp _inline = RegExp(
    r'\*\*(.+?)\*\*|(?<![\w*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\w*])|(?<!\w)__(.+?)__(?!\w)|(?<![\w])_(?![\s_])(.+?)(?<![\s_])_(?!\w)|`([^`\n]+)`|(https?://[^\s<>"]+)',
  );
  static final RegExp _bullet = RegExp(r'^(\s*)[*\-•]\s+');
  static final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*)$');

  void _clear() {
    for (final r in _recs) {
      r.dispose();
    }
    _recs.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  List<InlineSpan> _spans(String line, TextStyle base) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > last) out.add(TextSpan(text: line.substring(last, m.start)));
      final bold = m.group(1) ?? m.group(2) ?? m.group(3);
      final ital = m.group(4);
      final code = m.group(5);
      final url = m.group(6);
      if (bold != null) {
        out.add(TextSpan(children: _spans(bold, base.copyWith(fontWeight: FontWeight.w900)), style: const TextStyle(fontWeight: FontWeight.w900)));
      } else if (ital != null) {
        out.add(TextSpan(text: ital, style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (code != null) {
        out.add(TextSpan(text: code, style: TextStyle(fontFamily: 'monospace', backgroundColor: base.color?.withAlpha(28), fontSize: (base.fontSize ?? 15) - 1)));
      } else if (url != null) {
        var u = url;
        var tail = '';
        while (u.isNotEmpty && '.,;:!?)'.contains(u[u.length - 1])) {
          tail = u[u.length - 1] + tail;
          u = u.substring(0, u.length - 1);
        }
        final rec = TapGestureRecognizer()..onTap = () => openLink(u);
        _recs.add(rec);
        out.add(TextSpan(text: u, recognizer: rec, style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline, fontWeight: FontWeight.w700)));
        if (tail.isNotEmpty) out.add(TextSpan(text: tail));
      }
      last = m.end;
    }
    if (last < line.length) out.add(TextSpan(text: line.substring(last)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final p = pal(context);
    final base = widget.style;
    final blocks = <Widget>[];
    final lines = widget.text.replaceAll('\r\n', '\n').split('\n');
    final para = <InlineSpan>[];

    void flushPara() {
      if (para.isEmpty) return;
      blocks.add(Text.rich(TextSpan(style: base, children: List<InlineSpan>.from(para))));
      para.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final raw = lines[i];
      if (raw.trimLeft().startsWith('```')) {
        flushPara();
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          buf.add(lines[i]);
          i++;
        }
        i++; // tutup ```
        final code = buf.join('\n').trimRight();
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: code));
              app.toast('Kode disalin');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line, width: 1.5)),
              child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', fontSize: (base.fontSize ?? 15) - 2, color: p.text)),
            ),
          ),
        ));
        continue;
      }
      if (raw.trim().isEmpty) {
        flushPara();
        blocks.add(const SizedBox(height: 6));
        i++;
        continue;
      }
      final h = _heading.firstMatch(raw);
      final b = _bullet.firstMatch(raw);
      flushPara();
      if (h != null) {
        blocks.add(Text.rich(TextSpan(style: base.copyWith(fontWeight: FontWeight.w900), children: _spans(h.group(1)!, base))));
      } else if (b != null) {
        final indent = (b.group(1) ?? '').length >= 2 ? 14.0 : 0.0;
        blocks.add(Padding(
          padding: EdgeInsets.only(left: indent),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: base.copyWith(fontWeight: FontWeight.w900)),
            Expanded(child: Text.rich(TextSpan(style: base, children: _spans(raw.substring(b.end), base)))),
          ]),
        ));
      } else {
        blocks.add(Text.rich(TextSpan(style: base, children: _spans(raw, base))));
      }
      i++;
    }
    flushPara();
    while (blocks.isNotEmpty && blocks.last is SizedBox) {
      blocks.removeLast();
    }
    if (blocks.length == 1) return blocks.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: blocks);
  }
}
