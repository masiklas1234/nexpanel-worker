import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/custom_popup.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  // --- TEMA WARNA HITAM PUTIH (Diperbaiki agar bisa const) ---
  static const Color bgDark = Color(0xFFCED4DA);
  static const Color primaryPurple = const Color(0xFFFF99AC);
  static const Color accentPurple = const Color(0xFFFF99AC);

  static const Color cardGlass = Color(0xFFF8F9FA);
  static const Color borderGlass = Colors.black12;

  Future<void> _launchUrl(BuildContext context, String url) async {
    if (url.isEmpty) return;
    try {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (context.mounted) {
        CustomPopup.show(
          context,
          title: "Gagal",
          message: "Tidak dapat membuka tautan ini.",
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
        );
      }
    }
  }

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
        title: Text(
          "Customer Service",
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header Icon
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primaryPurple.withOpacity(0.2), // Aman di build()
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryPurple.withOpacity(0.4), // Aman di build()
                        blurRadius: 20,
                      )
                    ],
                  ),
                  child: Icon(
                    Icons.support_agent_rounded,
                    size: 60,
                    color: accentPurple,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  "Need Help?",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Contact us through our social media platforms below.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 40),

                // Grid Buttons
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildContactButton(
                            context: context,
                            label: "Telegram",
                            icon: FontAwesomeIcons.telegram,
                            color: Colors.blue,
                            url: "https://t.me/Z4rrfly",
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: _buildContactButton(
                            context: context,
                            label: "WhatsApp",
                            icon: FontAwesomeIcons.whatsapp,
                            color: Colors.green,
                            url: "https://wa.me/6283167662069",
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildContactButton(
                            context: context,
                            label: "TikTok",
                            icon: FontAwesomeIcons.tiktok,
                            color: Colors.black87,
                            url: "https://www.tiktok.com/@rafzzwkwk87",
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: _buildContactButton(
                            context: context,
                            label: "Instagram",
                            icon: FontAwesomeIcons.instagram,
                            color: Colors.pinkAccent,
                            url: "",
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchUrl(context, url),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: cardGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderGlass),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: FaIcon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}