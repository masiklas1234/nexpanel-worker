import 'config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WifiInternalPage extends StatefulWidget {
  final String sessionKey;
  const WifiInternalPage({super.key, required this.sessionKey});

  @override
  State<WifiInternalPage> createState() => _WifiInternalPageState();
}

class _WifiInternalPageState extends State<WifiInternalPage> {
  String publicIp = "-";
  String region = "-";
  String asn = "-";
  bool isVpn = false;
  bool isLoading = true;
  bool isAttacking = false;

  // --- Warna Tema Hitam Ungu ---
  final Color primaryDark = const Color(0xFFCED4DA);
  final Color primaryWhite = Colors.black87;
  final Color accentPurple = const Color(0xFFFF99AC);
  final Color cardDark = const Color(0xFFF8F9FA); // Card background (dark)

  @override
  void initState() {
    super.initState();
    _loadPublicInfo();
  }

  Future<void> _loadPublicInfo() async {
    setState(() {
      isLoading = true;
    });

    try {
      final ipRes = await http.get(Uri.parse("https://api.ipify.org?format=json"));
      final ipJson = jsonDecode(ipRes.body);
      final ip = ipJson['ip'];

      final infoRes = await http.get(Uri.parse("http://ip-api.com/json/$ip?fields=as,regionName,status,query"));
      final info = jsonDecode(infoRes.body);

      final asnRaw = (info['as'] as String).toLowerCase();
      final isBlockedAsn = asnRaw.contains("vpn") ||
          asnRaw.contains("cloud") ||
          asnRaw.contains("digitalocean") ||
          asnRaw.contains("aws") ||
          asnRaw.contains("google");

      setState(() {
        publicIp = ip;
        region = info['regionName'] ?? "-";
        asn = info['as'] ?? "-";
        isVpn = isBlockedAsn;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        publicIp = region = asn = "Error";
        isLoading = false;
      });
    }
  }

  Future<void> _attackTarget() async {
    setState(() => isAttacking = true);
    final url = Uri.parse(
        "$apiBaseUrl/killWifi?key=${widget.sessionKey}&target=$publicIp&duration=120");
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        _showAlert("✅ Attack Sent", "WiFi attack sent to $publicIp");
      } else {
        _showAlert("❌ Failed", "Server rejected request.");
      }
    } catch (e) {
      _showAlert("Error", "Network error: $e");
    } finally {
      setState(() => isAttacking = false);
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accentPurple.withOpacity(0.3)), // Ubah ke ungu
        ),
        title: Text(title,
            style: TextStyle(color: accentPurple, fontFamily: 'Orbitron')), // Ubah ke ungu
        content: Text(message,
            style: TextStyle(color: primaryWhite)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: accentPurple)), // Ubah ke ungu
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String title, String value, IconData icon) {
    return Card(
      color: cardDark,
      shadowColor: accentPurple.withOpacity(0.5), // Ubah ke ungu
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accentPurple.withOpacity(0.2)), // Ubah ke ungu
      ),
      child: ListTile(
        leading: Icon(icon, color: accentPurple), // Ubah ke ungu
        title: Text(title,
            style: TextStyle(
                color: primaryWhite,
                fontWeight: FontWeight.bold,
                fontFamily: "Orbitron")),
        subtitle: Text(value,
            style: TextStyle(color: primaryWhite, fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryDark,
      appBar: AppBar(
        title: Text("📡 WiFi Killer ( Internal )",
            style: TextStyle(fontFamily: 'Orbitron', color: primaryWhite)),
        backgroundColor: primaryDark,
        elevation: 6,
        iconTheme: IconThemeData(color: primaryWhite),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFFCED4DA), const Color(0xFFCED4DA)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isLoading
              ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF99AC))) // Ubah warna loader ke ungu
              : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("🎯 System Information",
                  style: TextStyle(
                      fontSize: 20,
                      color: primaryWhite,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Orbitron')),
              const SizedBox(height: 12),

              // Info Cards
              _infoCard("IP Address", publicIp, Icons.language),
              _infoCard("Region", region, Icons.map),
              _infoCard("ASN", asn, Icons.storage),

              const SizedBox(height: 20),

              if (isVpn)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple[900], // Ubah background peringatan ke ungu gelap
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentPurple), // Ubah border ke ungu
                  ),
                  child: Text(
                    "⚠️ Target berasal dari VPN/Hosting.\nSerangan dibatalkan.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: primaryWhite,
                        fontFamily: 'ShareTechMono'),
                  ),
                ),

              if (!isVpn)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: isAttacking ? null : _attackTarget,
                    icon: Icon(Icons.wifi_off, color: primaryWhite),
                    label: Text(
                      isAttacking ? "ATTACKING..." : "START KILL",
                      style: const TextStyle(
                          fontFamily: 'Orbitron',
                          fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentPurple, // Ubah tombol ke ungu
                      foregroundColor: primaryWhite,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 10,
                      shadowColor: accentPurple.withOpacity(0.5), // Ubah shadow ke ungu
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}