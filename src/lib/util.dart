// ZARR CHAT - fungsi bantu: format waktu, ukuran, teks pratinjau, warna.
import 'package:flutter/material.dart';

import 'models.dart';

const List<String> _bulan = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String dayLabel(DateTime d) {
  final n = DateTime.now();
  if (sameDay(d, n)) return 'Hari ini';
  if (sameDay(d, n.subtract(const Duration(days: 1)))) return 'Kemarin';
  return '${d.day} ${_bulan[d.month - 1]} ${d.year}';
}

String listTime(DateTime d) {
  final n = DateTime.now();
  if (sameDay(d, n)) return fmtTime(d);
  if (sameDay(d, n.subtract(const Duration(days: 1)))) return 'Kemarin';
  return '${two(d.day)}/${two(d.month)}/${two(d.year % 100)}';
}

String dateTimeText(DateTime? d) {
  if (d == null) return '';
  return '${d.day} ${_bulan[d.month - 1]} ${d.year}, ${fmtTime(d)}';
}

String fmtSize(int n) {
  if (n > 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
  final kb = (n / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
}

String fmtDur(int s) => '${two(s ~/ 60)}:${two(s % 60)}';

String previewText(Message? m) {
  if (m == null) return '';
  if (m.deleted) return 'Pesan ini dihapus';
  if (m.type == 'text') return m.body ?? '';
  if (m.viewOnce && (m.type == 'image' || m.type == 'video')) return m.type == 'video' ? 'Video sekali lihat' : 'Foto sekali lihat';
  String label;
  switch (m.type) {
    case 'image':
      label = 'Foto';
      break;
    case 'video':
      label = 'Video';
      break;
    case 'audio':
      label = 'Pesan suara';
      break;
    case 'document':
      label = (m.media != null && (m.media!.name ?? '').isNotEmpty) ? m.media!.name! : 'Dokumen';
      break;
    case 'sticker':
      label = 'Sticker';
      break;
    case 'location':
      label = 'Lokasi';
      break;
    case 'contact':
      label = 'Kontak';
      break;
    case 'system':
      return '';
    default:
      label = '';
  }
  final body = m.body ?? '';
  if (body.isNotEmpty && m.type != 'location' && m.type != 'contact') return '$label: $body';
  return label;
}

String replyPreview(ReplyRef r) {
  if (r.deleted) return 'Pesan dihapus';
  const labels = {
    'image': 'Foto',
    'video': 'Video',
    'audio': 'Pesan suara',
    'document': 'Dokumen',
    'sticker': 'Sticker',
    'location': 'Lokasi',
    'contact': 'Kontak',
  };
  if (r.type == 'text') return r.body ?? '';
  final l = labels[r.type] ?? '';
  final b = r.body ?? '';
  return b.isNotEmpty ? '$l: $b' : l;
}

Color hexColor(String? hex, Color fallback) {
  if (hex == null) return fallback;
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return fallback;
  return Color(0xFF000000 | v);
}

String newClientId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = (DateTime.now().millisecondsSinceEpoch * 7919 % 1679616).toRadixString(36);
  return 'c$t$r';
}

/// Teks batas ukuran file, mis. 2048 -> "2 GB", 25 -> "25 MB".
String maxSizeText(int mb) {
  if (mb >= 1024) {
    final g = mb / 1024;
    return g == g.roundToDouble() ? '${g.round()} GB' : '${g.toStringAsFixed(1)} GB';
  }
  return '$mb MB';
}
