import 'config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class ChangePasswordPage extends StatefulWidget {
  final String username;
  final String sessionKey;

  const ChangePasswordPage({
    super.key,
    required this.username,
    required this.sessionKey,
  });

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final oldPassCtrl = TextEditingController();
  final newPassCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();

  bool isLoading = false;
  bool _obscurePassword = true; // <--- State untuk toggle visibility (sesuai snippet)

  // --- TEMA WARNA ---
  final Color bgDark = const Color(0xFFCED4DA); // Background utama
  final Color bgSecondary = const Color(0xFFF8F9FA); // Background Solid Input
  final Color accentColor = const Color(0xFFFF99AC);
  final Color primaryWhite = Colors.black87;
  final Color textGrey = Colors.black54;

  Future<void> _changePassword() async {
    final oldPass = oldPassCtrl.text.trim();
    final newPass = newPassCtrl.text.trim();
    final confirmPass = confirmPassCtrl.text.trim();

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      _showMessage("Semua field harus diisi.");
      return;
    }

    if (newPass != confirmPass) {
      _showMessage("Password baru tidak cocok dengan konfirmasi.");
      return;
    }

    setState(() => isLoading = true);

    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/changepass"),
        body: {
          "username": widget.username,
          "oldPass": oldPass,
          "newPass": newPass,
          "sessionKey": widget.sessionKey,
        },
      );

      final data = jsonDecode(res.body);

      if (data['success'] == true) {
        _showMessage("Password berhasil diubah!", isSuccess: true);
        oldPassCtrl.clear();
        newPassCtrl.clear();
        confirmPassCtrl.clear();
      } else {
        _showMessage(data['message'] ?? "Gagal mengubah password");
      }
    } catch (e) {
      _showMessage("Koneksi error: $e");
    }

    setState(() => isLoading = false);
  }

  void _showMessage(String msg, {bool isSuccess = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: accentColor.withOpacity(0.3), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isSuccess ? Colors.green : accentColor).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSuccess ? Icons.check_circle_outline : Icons.info_outline,
                color: isSuccess ? Colors.green : accentColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isSuccess ? "Sukses" : "Peringatan",
              style: TextStyle(
                color: primaryWhite,
                fontWeight: FontWeight.w900,
                fontFamily: 'Orbitron',
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(msg, style: TextStyle(color: textGrey, fontSize: 14)),
        actions: [
          Center(
            child: SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  "OK",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET INPUT (SESUAI REQUEST) ---
  Widget _buildInput(TextEditingController controller, String label, IconData icon, [bool isPassword = false]) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: TextFormField(
          controller: controller,
          obscureText: isPassword ? _obscurePassword : false,
          style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'ShareTechMono'),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.normal, fontFamily: 'sans-serif'),
            prefixIcon: Icon(icon, color: accentColor, size: 22),
            filled: false,
            fillColor: Colors.transparent,
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.black54,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            )
                : null,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: accentColor),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          "CHANGE PASSWORD",
          style: TextStyle(
            color: primaryWhite,
            fontFamily: 'Orbitron',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20),

            // Header Icon
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgSecondary,
                  border: Border.all(color: accentColor.withOpacity(0.3), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Icon(Icons.lock_reset, color: accentColor, size: 50),
              ),
            ),
            SizedBox(height: 20),

            Center(
              child: Text(
                "SECURITY UPDATE",
                style: TextStyle(
                  color: primaryWhite,
                  fontSize: 22,
                  fontFamily: 'Orbitron',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                "Masukkan password lama dan baru.",
                style: TextStyle(
                  color: textGrey,
                  fontFamily: 'ShareTechMono',
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Form Inputs Container
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgSecondary,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accentColor.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                children: [
                  _buildInput(oldPassCtrl, "Old Password", Icons.lock_outline, true),
                  _buildInput(newPassCtrl, "New Password", Icons.vpn_key, true),
                  _buildInput(confirmPassCtrl, "Confirm Password", Icons.enhanced_encryption, true),
                  const SizedBox(height: 24),
                  
                  // Button
                  Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: isLoading
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        "UPDATE PASSWORD",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Orbitron',
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}