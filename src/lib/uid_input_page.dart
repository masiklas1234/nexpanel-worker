import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'overlay_permission_page.dart';
import 'webview_page.dart'; // ← jika sudah pernah register, langsung WebView

class UidInputPage extends StatefulWidget {
  const UidInputPage({super.key});

  @override
  State<UidInputPage> createState() => _UidInputPageState();
}

class _UidInputPageState extends State<UidInputPage> {
  static const String _apiBase = 'http://hanz-cpanel-private.pteroq.biz.id:11643';
  static const Color yellow = Color(0xFFFFCC00);

  final _ctrl  = TextEditingController();
  final _focus = FocusNode();

  bool    _loading  = false;
  String? _errorMsg;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submitUID() async {
    _focus.unfocus();
    final uid = _ctrl.text.trim();

    if (uid.isEmpty) { setState(() => _errorMsg = 'UID tidak boleh kosong!'); return; }
    if (uid.length != 8) { setState(() => _errorMsg = 'UID harus tepat 8 digit!'); return; }

    setState(() { _loading = true; _errorMsg = null; });

    try {
      final res = await http.get(
        Uri.parse('$_apiBase/checkUID?uid=$uid'),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        if (data['valid'] == true) {
          // Simpan UID
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('nex_uid', uid);
          await prefs.setString('nex_username', (data['username'] ?? '').toString());

          if (!mounted) return;

          // Cek apakah HP ini sudah pernah register (ada deviceId tersimpan)
          final deviceId = prefs.getString('nex_device_id') ?? '';

          if (deviceId.isNotEmpty) {
            // Sudah pernah register → langsung buka WebView
            // Tidak perlu overlay permission lagi
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => WebViewPage(uid: uid)),
            );
          } else {
            // Belum pernah register → ke OverlayPermissionPage
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => OverlayPermissionPage(uid: uid)),
            );
          }
        } else {
          final reason = (data['reason'] ?? '').toString();
          String msg;
          switch (reason) {
            case 'expired':   msg = 'UID sudah expired! Perpanjang terlebih dahulu.'; break;
            case 'not_found': msg = 'UID tidak ditemukan. Periksa kembali.'; break;
            case 'no_uid':    msg = 'UID tidak boleh kosong!'; break;
            default:          msg = 'UID tidak valid. Coba lagi.';
          }
          setState(() => _errorMsg = msg);
        }
      } else {
        setState(() => _errorMsg = 'Server error (${res.statusCode}). Coba lagi.');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.toString().contains('TimeoutException')
          ? 'Koneksi timeout. Periksa internet.'
          : 'Tidak dapat konek ke server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: yellow, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.phone_android,
                      color: Colors.black, size: 48),
                ),
                const SizedBox(height: 24),
                const Text('NEX PANEL',
                    style: TextStyle(
                      color: Colors.white, fontSize: 28,
                      fontWeight: FontWeight.bold, letterSpacing: 4,
                      fontFamily: 'monospace',
                    )),
                const SizedBox(height: 6),
                const Text('Device Control System',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
                const SizedBox(height: 40),

                // Input box
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: yellow.withOpacity(0.3), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Input UID',
                          style: TextStyle(color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Masukkan UID 8 digit untuk melanjutkan',
                          style: TextStyle(color: Colors.white60, fontSize: 13)),
                      const SizedBox(height: 20),

                      TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitUID(),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace',
                          fontSize: 22, letterSpacing: 4,
                        ),
                        decoration: InputDecoration(
                          hintText: '',
                          hintStyle: const TextStyle(
                              color: Colors.white24, letterSpacing: 4),
                          counterText: '',
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: yellow, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          errorText: _errorMsg,
                          errorStyle: const TextStyle(color: Colors.redAccent),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: yellow,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _loading ? null : _submitUID,
                          child: _loading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2))
                              : const Text('MASUK',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15,
                                    letterSpacing: 2, fontFamily: 'monospace',
                                  )),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
