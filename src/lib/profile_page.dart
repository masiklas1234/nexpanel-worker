import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'change_password_page.dart';
import 'widgets/custom_popup.dart';

class ProfilePage extends StatefulWidget {
  final String username;
  final String password;
  final String role;
  final String expiredDate;
  final String sessionKey;

  const ProfilePage({
    super.key,
    required this.username,
    required this.password,
    required this.role,
    required this.expiredDate,
    required this.sessionKey,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Removed ImagePicker

  // --- TEMA WARNA HITAM PUTIH ---
  final Color bgDark = const Color(0xFFCED4DA);
  final Color primaryPurple = const Color(0xFFFF99AC);
  final Color accentPurple = const Color(0xFFFF99AC);
  final Color primaryWhite = Colors.black87;

  // Glassmorphism Colors
  final Color cardGlass = const Color(0xFFF8F9FA);
  final Color borderGlass = Colors.black12;

  @override
  void initState() {
    super.initState();
  }

  // Memuat gambar dihapus karena sekarang menggunakan asset logo.png

  // Fungsi Sensor Teks
  String _censorText(String text, {bool isPassword = false}) {
    if (text.isEmpty) return "N/A";
    if (isPassword) {
      return "••••••••";
    }
    // Username: Tampilkan 2 huruf depan, sisanya bintang
    if (text.length <= 2) return "${text.substring(0, 1)}••";
    return "${text.substring(0, 2)}${'•' * (text.length - 2)}";
  }

  // Removed _showImageSourceDialog and _pickImage

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: accentPurple),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "My Profile",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          color: bgDark,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // --- AVATAR PROFILE ---
              Center(
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                widget.username,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Orbitron',
                ),
              ),
              Text(
                widget.role.toUpperCase(),
                style: TextStyle(
                  color: accentPurple,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(height: 30),

              // --- INFO GRID (BOXES) ---

              // ROW 1: Username - Password
              Row(
                children: [
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.person_outline,
                      label: "Username",
                      value: _censorText(widget.username),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.lock_outline,
                      label: "Password",
                      value: _censorText(widget.password, isPassword: true),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // ROW 2: Role - Expired Date
              Row(
                children: [
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.verified_user_outlined,
                      label: "Role",
                      value: widget.role.toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.calendar_today_outlined,
                      label: "Expired",
                      value: widget.expiredDate,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // ROW 3: Session Key (Full Width)
              _buildInfoCard(
                icon: Icons.vpn_key,
                label: "Session Key",
                value: "${widget.sessionKey.substring(0, 8)}...",
              ),

              const SizedBox(height: 40),

              // --- CHANGE PASSWORD BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock_reset, color: Colors.black87),
                  label: const Text(
                    "CHANGE PASSWORD",
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 5,
                    shadowColor: primaryPurple.withOpacity(0.5),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangePasswordPage(
                          username: widget.username,
                          sessionKey: widget.sessionKey,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15), // Padding disesuaikan agar muat di grid
      decoration: BoxDecoration(
        color: cardGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6), // Ikon sedikit lebih kecil
                decoration: BoxDecoration(
                  color: primaryPurple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentPurple, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 11, // Font label disesuaikan
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'ShareTechMono',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1, // Batasi 1 baris agar layout tidak rusak
          ),
        ],
      ),
    );
  }
}