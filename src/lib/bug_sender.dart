import 'config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class BugSenderPage extends StatefulWidget {
  final String sessionKey;
  final String username;
  final String role;

  const BugSenderPage({
    super.key,
    required this.sessionKey,
    required this.username,
    required this.role,
  });

  @override
  State<BugSenderPage> createState() => _BugSenderPageState();
}

class _BugSenderPageState extends State<BugSenderPage> with TickerProviderStateMixin {
  List<dynamic> senderList = [];
  bool isLoading = false;
  bool isRefreshing = false;
  String? errorMessage;

  // --- TEMA WARNA HITAM OSINT ---
  final Color bgDark = const Color(0xFFCED4DA);
  final Color cardBg = const Color(0xFFF8F9FA);
  final Color borderLight = const Color(0xFFFF99AC);
  final Color textMain = Colors.black87;
  final Color textSub = Colors.black54;
  
  // Aksen Hijau Neon & Merah (Terminal Vibe)
  final Color accentGreen = const Color(0xFFFF99AC);
  final Color dangerRed = const Color(0xFFFF5252);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _fetchSenders();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchSenders() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse("$apiBaseUrl/mySender?key=${widget.sessionKey}"),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["valid"] == true) {
          if (mounted) {
            setState(() {
              senderList = data["connections"] ?? [];
            });
          }
        } else {
          if (mounted) setState(() => errorMessage = data["message"] ?? "Failed to fetch senders");
        }
      } else {
        if (mounted) setState(() => errorMessage = "Server error: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => errorMessage = "Connection failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isRefreshing = false;
        });
      }
    }
  }

  Future<void> _refreshSenders() async {
    setState(() => isRefreshing = true);
    await _fetchSenders();
    // Refresh stats juga agar PRIVATE/GLOBAL count update
    try {
      final statsRes = await http.get(
        Uri.parse("$apiBaseUrl/getSenderStats?key=${widget.sessionKey}"),
      );
      if (statsRes.statusCode == 200) {
        final data = jsonDecode(statsRes.body);
        if (mounted && data["valid"] == true) {
          setState(() {
            // Update count di home jika ada callback
          });
        }
      }
    } catch (_) {}
  }

  void _showAddSenderDialog() {
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderLight, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: accentGreen.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(Icons.add_link_rounded, color: accentGreen, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              "NEW SENDER",
              style: TextStyle(color: Colors.black87, fontFamily: 'Orbitron', fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Masukkan nomor WhatsApp target yang ingin dihubungkan sebagai Sender Node.", style: TextStyle(color: textSub, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: textMain, fontFamily: 'ShareTechMono'),
              decoration: InputDecoration(
                labelText: "Phone Number",
                labelStyle: TextStyle(color: textSub, fontFamily: 'ShareTechMono'),
                hintText: "628xxx...",
                hintStyle: TextStyle(color: Colors.black38),
                prefixIcon: Icon(Icons.phone_android, color: accentGreen),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accentGreen, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL", style: TextStyle(color: textSub, fontFamily: 'Orbitron', fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentGreen,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 5,
              shadowColor: accentGreen.withOpacity(0.5),
            ),
            onPressed: () async {
              final number = phoneController.text.trim();
              if (number.isEmpty) {
                _showSnackBar("Number cannot be empty", isError: true);
                return;
              }
              Navigator.pop(context);
              await _addSender(number);
            },
            child: const Text("GENERATE PAIRING", style: TextStyle(fontFamily: 'Orbitron', fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Future<void> _addSender(String number) async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse("$apiBaseUrl/getPairing?key=${widget.sessionKey}&number=$number"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["valid"] == true) {
          _showPairingCodeDialog(number, data['pairingCode']);
          _showSnackBar("Pairing sequence generated!", isError: false);
        } else {
          _showSnackBar(data['message'] ?? "Pairing failed", isError: true);
        }
      } else {
        _showSnackBar("Server Error: ${response.statusCode}", isError: true);
      }
    } catch (e) {
      _showSnackBar("Connection Fault: $e", isError: true);
    } finally {
      setState(() => isLoading = false);
      _fetchSenders();
    }
  }

  void _showPairingCodeDialog(String number, String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accentGreen.withOpacity(0.5), width: 1.5),
        ),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentGreen.withOpacity(0.1),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: accentGreen.withOpacity(0.2), blurRadius: 20)],
              ),
              child: Icon(Icons.qr_code_scanner_rounded, color: accentGreen, size: 40),
            ),
            const SizedBox(height: 16),
            const Text("PAIRING REQUIRED", style: TextStyle(color: Colors.black87, fontFamily: 'Orbitron', fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.5)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("TARGET: $number", style: TextStyle(color: textSub, fontFamily: 'ShareTechMono', fontSize: 13)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentGreen, width: 2),
                boxShadow: [BoxShadow(color: accentGreen.withOpacity(0.2), blurRadius: 20, spreadRadius: -5)],
              ),
              child: Center(
                child: Text(
                  code,
                  style: TextStyle(
                    color: accentGreen,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    fontFamily: 'ShareTechMono',
                    shadows: [Shadow(color: accentGreen, blurRadius: 10)],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton.icon(
                icon: Icon(Icons.copy_all, color: accentGreen, size: 18),
                label: Text("COPY TO CLIPBOARD", style: TextStyle(color: accentGreen, fontFamily: 'Orbitron', fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accentGreen.withOpacity(0.5), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  _showSnackBar("Sequence copied to clipboard!", isError: false);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _fetchSenders();
            },
            child: Text("CLOSE & REFRESH", style: TextStyle(color: textSub, fontFamily: 'Orbitron', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSender(String senderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: dangerRed.withOpacity(0.5), width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: dangerRed),
            const SizedBox(width: 12),
            const Text("PURGE NODE", style: TextStyle(color: Colors.black87, fontFamily: 'Orbitron', fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Apakah Anda yakin ingin menghapus Sender Node ini selamanya? Proses ini tidak dapat dibatalkan.",
          style: TextStyle(color: textSub, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("CANCEL", style: TextStyle(color: textSub, fontFamily: 'Orbitron', fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerRed,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 5,
              shadowColor: dangerRed.withOpacity(0.4),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("PURGE", style: TextStyle(fontFamily: 'Orbitron', fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => isLoading = true);
      try {
        final response = await http.delete(Uri.parse("$apiBaseUrl/deleteSender?key=${widget.sessionKey}&id=$senderId"));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data["valid"] == true) {
            _showSnackBar("Node purged successfully.", isError: false);
            _fetchSenders();
          } else {
            _showSnackBar(data["message"] ?? "Failed to purge node", isError: true);
          }
        } else {
          _showSnackBar("Server error: ${response.statusCode}", isError: true);
        }
      } catch (e) {
        _showSnackBar("Connection failed: $e", isError: true);
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.black, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'ShareTechMono'))),
          ],
        ),
        backgroundColor: isError ? dangerRed : accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildSenderCard(Map<String, dynamic> sender, int index) {
    final name = sender['sessionName'] ?? 'WhatsApp Sender';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Icon(Icons.hub_outlined, color: textMain, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          fontFamily: 'Orbitron',
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "NODE ID: ${sender['id']?.toString().substring(0, 8) ?? 'UNKNOWN'}",
                        style: TextStyle(
                          color: textSub,
                          fontSize: 11,
                          fontFamily: 'ShareTechMono',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accentGreen.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accentGreen,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: accentGreen.withOpacity(_pulseAnimation.value), blurRadius: 4, spreadRadius: 1)],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "ONLINE",
                        style: TextStyle(
                          color: accentGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'ShareTechMono',
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            width: double.infinity,
            color: borderLight,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.sync, size: 16, color: textSub),
                    label: Text("SYNC", style: TextStyle(fontFamily: 'Orbitron', fontWeight: FontWeight.bold, fontSize: 12, color: textSub)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.transparent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _refreshSenders(),
                  ),
                ),
                Container(width: 1, height: 20, color: borderLight),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.delete_outline, size: 16, color: dangerRed),
                    label: Text("PURGE", style: TextStyle(fontFamily: 'Orbitron', fontWeight: FontWeight.bold, fontSize: 12, color: dangerRed)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.transparent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _deleteSender(sender['id']),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.02),
                shape: BoxShape.circle,
                border: Border.all(color: borderLight, width: 2),
                boxShadow: [BoxShadow(color: accentGreen.withOpacity(0.05), blurRadius: 40)],
              ),
              child: Icon(Icons.router_outlined, color: Colors.black26, size: 60),
            ),
            const SizedBox(height: 30),
            const Text(
              "NO ACTIVE NODES",
              style: TextStyle(color: Colors.black87, fontSize: 18, fontFamily: 'Orbitron', fontWeight: FontWeight.w900, letterSpacing: 2.0),
            ),
            const SizedBox(height: 12),
            Text(
              "Sistem tidak mendeteksi koneksi pengirim. Tambahkan WhatsApp node pertama Anda.",
              style: TextStyle(color: textSub, fontSize: 12, fontFamily: 'ShareTechMono', height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_link_rounded, color: Colors.black),
                label: const Text("INITIALIZE SENDER", style: TextStyle(color: Colors.black, fontFamily: 'Orbitron', fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentGreen,
                  shadowColor: accentGreen.withOpacity(0.4),
                  elevation: 10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _showAddSenderDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, color: dangerRed, size: 60),
            const SizedBox(height: 24),
            const Text(
              "CONNECTION FAULT",
              style: TextStyle(color: Colors.black87, fontSize: 18, fontFamily: 'Orbitron', fontWeight: FontWeight.w900, letterSpacing: 2.0),
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage ?? "Unknown connection error occurred",
              style: TextStyle(color: textSub, fontSize: 12, fontFamily: 'ShareTechMono'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("RETRY CONNECTION", style: TextStyle(fontFamily: 'Orbitron', fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: borderLight, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _fetchSenders,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderLight),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "SENDER NODES",
                          style: TextStyle(
                            color: Colors.black87,
                            fontFamily: 'Orbitron',
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Device Management System",
                          style: TextStyle(
                            color: textSub,
                            fontFamily: 'ShareTechMono',
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderLight),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.sync_rounded, color: isLoading ? textSub : accentGreen, size: 22),
                      onPressed: isLoading ? null : _refreshSenders,
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: isLoading && senderList.isEmpty
                  ? Center(child: CircularProgressIndicator(color: accentGreen))
                  : errorMessage != null && senderList.isEmpty
                  ? _buildErrorState()
                  : senderList.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                color: Colors.black,
                backgroundColor: accentGreen,
                onRefresh: _refreshSenders,
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 16, bottom: 100),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: senderList.length,
                  itemBuilder: (context, index) => _buildSenderCard(Map<String, dynamic>.from(senderList[index]), index),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: senderList.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showAddSenderDialog,
              backgroundColor: accentGreen,
              elevation: 8,
              icon: const Icon(Icons.add_link_rounded, color: Colors.black),
              label: const Text(
                "NEW NODE",
                style: TextStyle(color: Colors.black, fontFamily: 'Orbitron', fontWeight: FontWeight.w900),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}