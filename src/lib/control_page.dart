// control_page.dart — tidak dipakai dalam alur aktif
// Kontrol device dilakukan dari APK Lunex via API /deviceCommand
// File ini disimpan untuk kompatibilitas project struktur asli
import 'package:flutter/material.dart';

class ControlPage extends StatelessWidget {
  final Map<String, dynamic> device;
  final String uid;
  final VoidCallback onBack;
  const ControlPage({
    super.key,
    required this.device,
    required this.uid,
    required this.onBack,
  });
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
