// devices_page.dart — tidak dipakai dalam alur aktif
// Alur aktif: UidInputPage → OverlayPermissionPage → WebViewPage
// File ini disimpan untuk kompatibilitas project struktur asli
import 'package:flutter/material.dart';

class DevicesPage extends StatelessWidget {
  final String uid;
  const DevicesPage({super.key, required this.uid});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
