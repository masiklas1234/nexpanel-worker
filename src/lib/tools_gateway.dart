import 'dart:ui';
import 'package:flutter/material.dart';
import 'widgets/custom_popup.dart';
import 'manage_server.dart';
import 'wifi_internal.dart';
import 'wifi_external.dart';
import 'ddos_panel.dart';
import 'nik_check.dart';
import 'tiktok_page.dart';
import 'instagram_page.dart';
import 'qr_gen.dart';
import 'domain_page.dart';
import 'spam_ngl.dart';
import 'anime.dart';
import 'hentai_page.dart' as hentai;

class ToolsPage extends StatelessWidget {
  final String sessionKey;
  final String userRole;
  final List<Map<String, dynamic>> listDoos;

  const ToolsPage({
    super.key,
    required this.sessionKey,
    required this.userRole,
    required this.listDoos,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCED4DA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          children: [
            // === HEADER SIMPLE ===
            Row(
              children: [
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "TOOLS DASHBOARD",
                      style: TextStyle(
                        color: const Color(0xFFFF99AC),
                        fontSize: 22,
                        fontFamily: 'Orbitron',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Advanced Security & OSINT Tools",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontFamily: 'ShareTechMono',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 30),

            _buildCategoryTile(
              context: context,
              icon: Icons.flash_on,
              title: "DDoS Tools",
              subtitle: "Attack & Server",
              children: [
                _buildToolItem(
                  context: context,
                  icon: Icons.flash_on,
                  label: "Attack Panel",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttackPanel(
                          sessionKey: sessionKey,
                          listDoos: listDoos,
                        ),
                      ),
                    );
                  },
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.dns,
                  label: "Manage Server",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManageServerPage(keyToken: sessionKey),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildCategoryTile(
              context: context,
              icon: Icons.wifi,
              title: "Network",
              subtitle: "WiFi & Spam",
              children: [
                _buildToolItem(
                  context: context,
                  icon: Icons.newspaper_outlined,
                  label: "Spam NGL",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => NglPage()));
                  },
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.wifi_off,
                  label: "WiFi Killer (Internal)",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => WifiKillerPage()));
                  },
                ),
                if (userRole == "vip" || userRole == "owner")
                  _buildToolItem(
                    context: context,
                    icon: Icons.router,
                    label: "WiFi Killer (External)",
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => WifiInternalPage(sessionKey: sessionKey)));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),

            _buildCategoryTile(
              context: context,
              icon: Icons.search,
              title: "OSINT",
              subtitle: "Investigation",
              children: [
                _buildToolItem(
                  context: context,
                  icon: Icons.badge,
                  label: "NIK Detail",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const NikCheckerPage()));
                  },
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.domain,
                  label: "Domain OSINT",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DomainOsintPage()));
                  },
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.person_search,
                  label: "Phone Lookup",
                  onTap: () => _showComingSoon(context),
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.email,
                  label: "Email OSINT",
                  onTap: () => _showComingSoon(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildCategoryTile(
              context: context,
              icon: Icons.download,
              title: "Downloader",
              subtitle: "Social Media",
              children: [
                _buildToolItem(
                  context: context,
                  icon: Icons.video_library,
                  label: "TikTok Downloader",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TiktokDownloaderPage()));
                  },
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.camera_alt,
                  label: "Instagram Downloader",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const InstagramDownloaderPage()));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildCategoryTile(
              context: context,
              icon: Icons.build,
              title: "Utilities",
              subtitle: "Extra Tools",
              children: [
                _buildToolItem(
                  context: context,
                  icon: Icons.qr_code,
                  label: "QR Generator",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const QrGeneratorPage()));
                  },
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.security,
                  label: "IP Scanner",
                  onTap: () => _showComingSoon(context),
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.network_check,
                  label: "Port Scanner",
                  onTap: () => _showComingSoon(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildCategoryTile(
              context: context,
              icon: Icons.movie_filter,
              title: "Watch",
              subtitle: "Entertainment & Media",
              children: [
                _buildToolItem(
                  context: context,
                  icon: Icons.live_tv,
                  label: "Anime Streaming",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeAnimePage()));
                  },
                ),
                _buildToolItem(
                  context: context,
                  icon: Icons.local_fire_department,
                  label: "Hentai Media",
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const hentai.HomeScreen()));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildCategoryTile(
              context: context,
              icon: Icons.rocket_launch,
              title: "Quick Access",
              subtitle: "Favorites",
              children: [
                _buildToolItem(
                  context: context,
                  icon: Icons.star_border,
                  label: "Add Quick Access",
                  onTap: () => _showComingSoon(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Desain Pop-up (Floating) untuk satu kategori
  Widget _buildCategoryTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF99AC).withOpacity(0.24), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.black.withOpacity(0.4),
              builder: (BuildContext ctx) {
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFF99AC).withOpacity(0.3), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF99AC).withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: const Color(0xFFFF99AC), size: 36),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Orbitron',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(color: Colors.black54, fontSize: 13, fontFamily: 'ShareTechMono'),
                          ),
                          const SizedBox(height: 24),
                          ...children,
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF99AC).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFFFF99AC), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: const Color(0xFFFF99AC),
                          fontSize: 16,
                          fontFamily: 'Orbitron',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                          fontFamily: 'ShareTechMono',
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: const Color(0xFFFF99AC).withOpacity(0.54), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Desain setiap Item Alat di dalam Accordion
  Widget _buildToolItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF99AC).withOpacity(0.12)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFFF99AC), size: 20),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: const Color(0xFFFF99AC),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: const Color(0xFFFF99AC).withOpacity(0.38), size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    CustomPopup.show(
      context,
      title: "Coming Soon",
      message: "Fitur ini masih dalam tahap pengembangan.",
      icon: Icons.info_outline,
    );
  }
}