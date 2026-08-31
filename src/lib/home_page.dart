import 'config.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'widgets/custom_popup.dart';

class HomePage extends StatefulWidget {
  final String username;
  final String password;
  final String sessionKey;
  final List<Map<String, dynamic>> listBug;
  final String role;
  final String expiredDate;

  const HomePage({
    super.key,
    required this.username,
    required this.password,
    required this.sessionKey,
    required this.listBug,
    required this.role,
    required this.expiredDate,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final targetController = TextEditingController();
  late AnimationController _pulseController;
  String selectedBugId = "";
  VideoPlayerController? _videoController;

  // --- State Baru: Mode Target ---
  String _selectedBugMode = "number"; // 'number' atau 'group'

  // --- State Baru: Mode Sender ---
  String _senderMode = "private"; // 'private' atau 'global'
  int _privateSenderCount = 0;
  int _globalSenderCount = 0;

  bool _isSending = false;

  // Bug list lokal — bisa di-refresh dari API tanpa harus logout
  late List<Map<String, dynamic>> _localBugList;

  // --- Tema Warna Biru Hitam (Sleek Dark Blue Scheme) ---
  final Color primaryBg = const Color(0xFFCED4DA);
  final Color cardBg = const Color(0xFFF8F9FA);
  final Color sectionBg = const Color(0xFFFFFFFF);
  final Color borderColor = const Color(0xFFFF99AC);
  final Color accentWhite = const Color(0xFFFF99AC);
  final Color textGrey = Colors.black54;

  @override
  void initState() {
    super.initState();

    _videoController = VideoPlayerController.asset('assets/videos/bug.mp4')
      ..initialize().then((_) {
        setState(() {});
        _videoController?.setVolume(1.0);
        _videoController?.setLooping(true);
        _videoController?.play();
      });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Init bug list lokal dari widget, lalu refresh dari API
    _localBugList = List<Map<String, dynamic>>.from(widget.listBug);

    // Filter bug default
    if (_localBugList.isNotEmpty) {
      final initialBugs = _getFilteredBugs();
      if (initialBugs.isNotEmpty) {
        selectedBugId = initialBugs[0]['bug_id'];
      }
    }

    _fetchSenderStats();
    _refreshBugList(); // refresh dari API saat halaman dibuka
  }

  // --- FUNGSI: Refresh Bug List dari API ---
  Future<void> _refreshBugList() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/getBugs?key=${widget.sessionKey}"),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['valid'] == true && data['bugs'] != null) {
          final newBugs = (data['bugs'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          setState(() {
            _localBugList = newBugs;
            // Reset selectedBugId kalau bug yang dipilih sudah tidak ada
            final filtered = _getFilteredBugs();
            if (!filtered.any((b) => b['bug_id'] == selectedBugId)) {
              selectedBugId = filtered.isNotEmpty ? filtered[0]['bug_id'] : "";
            }
          });
        }
      }
    } catch (_) {
      // Gagal refresh — pakai data dari login, tidak masalah
    }
  }

  // --- FUNGSI: Filter Bug ---
  List<Map<String, dynamic>> _getFilteredBugs() {
    if (_selectedBugMode == "group") {
      return _localBugList.where((b) => b['type'] == 'group').toList();
    } else {
      return _localBugList.where((b) => b['type'] == 'wa' || b['type'] == null).toList();
    }
  }

  // --- FUNGSI: Ambil Statistik Sender ---
  Future<void> _fetchSenderStats() async {
    try {
      final res = await http.get(Uri.parse(
          "$apiBaseUrl/getSenderStats?key=${widget.sessionKey}"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['valid'] == true) {
          setState(() {
            _privateSenderCount = data['private'] ?? 0;
            _globalSenderCount = data['global'] ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching sender stats: $e");
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pulseController.dispose();
    targetController.dispose();
    super.dispose();
  }

  String? formatPhoneNumber(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^\d]'), '');
    // Harus minimal 8 digit dan dimulai dengan digit
    if (cleaned.isEmpty || cleaned.length < 8) return null;
    return cleaned;
  }

  bool isValidGroupLink(String input) {
    return input.contains('chat.whatsapp.com') && input.contains('https://');
  }

  Future<void> _sendBug() async {
    final rawInput = targetController.text.trim();
    final key = widget.sessionKey;

    if (_selectedBugMode == "number") {
      final target = formatPhoneNumber(rawInput);
      if (target == null || key.isEmpty) {
        _showAlert("Invalid Number", "Gunakan nomor internasional (misal: +62, 1, 44), bukan 08xxx.");
        return;
      }
    } else {
      if (!isValidGroupLink(rawInput)) {
        _showAlert("Invalid Link", "Masukkan link group WA yang valid (contoh: https://chat.whatsapp.com/...).");
        return;
      }
    }

    final currentBugs = _getFilteredBugs();
    if (!currentBugs.any((b) => b['bug_id'] == selectedBugId)) {
      if (currentBugs.isNotEmpty) {
        setState(() {
          selectedBugId = currentBugs[0]['bug_id'];
        });
      } else {
        _showAlert("Error", "Tidak ada bug tersedia untuk mode ini.");
        return;
      }
    }

    setState(() {
      _isSending = true;
    });

    final effectiveSenderMode = (widget.role == 'owner' || widget.role == 'vip') 
        ? _senderMode 
        : 'private';

    try {
      final res = await http.get(Uri.parse(
          "$apiBaseUrl/sendBug?key=$key&target=$rawInput&bug=$selectedBugId&senderMode=$effectiveSenderMode"));
      final data = jsonDecode(res.body);

      if (data["cooldown"] == true) {
        _showAlert("⏳ Cooldown", "Tunggu beberapa saat sebelum mengirim lagi.");
      } else if (data["valid"] == false) {
        _showAlert("❌ Key Invalid", "Sesi Anda tidak valid. Silakan login ulang.");
      } else if (data["sended"] == false) {
        _showAlert("⚠️ Gagal", "Server sedang maintenance atau terjadi kegagalan.");
      } else {
        _showAlert("✅ Berhasil", "Bug sukses dikirim ke target!");
        targetController.clear();
        _fetchSenderStats();
      }
    } catch (_) {
      _showAlert("❌ Error", "Terjadi kesalahan pada sistem. Coba lagi nanti.");
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _showAlert(String title, String msg) {
    if (!mounted) return;
    CustomPopup.show(
      context,
      title: title,
      message: msg,
      icon: title.contains("✅") ? Icons.check_circle_outline : Icons.error_outline,
      iconColor: title.contains("✅") ? Colors.green : Colors.redAccent,
      confirmText: "Close",
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
        gradient: LinearGradient(
          colors: [
            Colors.redAccent.withOpacity(0.1),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
            ),
            child: const Icon(Icons.bug_report_outlined, color: Colors.redAccent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "WHATSAPP CRASH",
                  style: TextStyle(
                    color: Colors.black87,
                    fontFamily: 'Orbitron',
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Advanced Payload Injection Tool",
                  style: TextStyle(
                    color: textGrey,
                    fontFamily: 'ShareTechMono',
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionButton({required String title, required String value, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: sectionBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: accentWhite, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'ShareTechMono')),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_right_rounded, color: Colors.black54, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupOption({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.black26, size: 14),
          ],
        ),
      ),
    );
  }

  void _showTargetTypePopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "PILIH TARGET",
                  style: TextStyle(
                    color: Colors.black87,
                    fontFamily: 'Orbitron',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 20),
                _buildPopupOption(
                  icon: Icons.phone_android_rounded,
                  color: accentWhite,
                  title: "BUG NOMOR",
                  onTap: () {
                    // Set mode dulu di luar setState agar _getFilteredBugs baca nilai baru
                    _selectedBugMode = "number";
                    targetController.clear();
                    final newBugs = _localBugList
                        .where((b) => b['type'] == 'wa' || b['type'] == null)
                        .toList();
                    setState(() {
                      selectedBugId = newBugs.isNotEmpty ? newBugs[0]['bug_id'] : "";
                    });
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
                _buildPopupOption(
                  icon: Icons.group_add,
                  color: accentWhite,
                  title: "BUG GROUP",
                  onTap: () {
                    // Set mode dulu di luar setState agar _getFilteredBugs baca nilai baru
                    _selectedBugMode = "group";
                    targetController.clear();
                    final newBugs = _localBugList
                        .where((b) => b['type'] == 'group')
                        .toList();
                    setState(() {
                      selectedBugId = newBugs.isNotEmpty ? newBugs[0]['bug_id'] : "";
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSenderTypePopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "PILIH SENDER",
                  style: TextStyle(
                    color: Colors.black87,
                    fontFamily: 'Orbitron',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 20),
                _buildPopupOption(
                  icon: Icons.person_outline,
                  color: accentWhite,
                  title: "PRIVATE ($_privateSenderCount Active)",
                  onTap: () {
                    setState(() => _senderMode = 'private');
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
                _buildPopupOption(
                  icon: Icons.public,
                  color: accentWhite,
                  title: "GLOBAL ($_globalSenderCount Active)",
                  onTap: () {
                    setState(() => _senderMode = 'global');
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildInputPanel() {
    final availableBugs = _getFilteredBugs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSelectionButton(
          title: "TARGET TYPE",
          value: _selectedBugMode == "number" ? "BUG NOMOR" : "BUG GROUP",
          icon: _selectedBugMode == "number" ? Icons.phone_android_rounded : Icons.group_add,
          onTap: _showTargetTypePopup,
        ),
        const SizedBox(height: 16),

        if (widget.role == 'owner' || widget.role == 'vip') ...[
          _buildSelectionButton(
            title: "SENDER MODE",
            value: _senderMode == 'private' ? "PRIVATE SENDER" : "GLOBAL SENDER",
            icon: _senderMode == 'private' ? Icons.person_outline : Icons.public,
            onTap: _showSenderTypePopup,
          ),
          const SizedBox(height: 24),
        ],
        
        // LABEL INPUT TARGET
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            _selectedBugMode == "number" ? "TARGET NUMBER" : "WHATSAPP GROUP LINK",
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              fontFamily: 'Orbitron',
              letterSpacing: 1.5,
            ),
          ),
        ),
        
        // TEXTFIELD TARGET
        TextField(
          controller: targetController,
          style: const TextStyle(color: Colors.black87, fontSize: 16),
          cursorColor: accentWhite,
          keyboardType: _selectedBugMode == "number" ? TextInputType.phone : TextInputType.url,
          decoration: InputDecoration(
            hintText: _selectedBugMode == "number"
                ? "e.g. +628xxxxxxxx"
                : "e.g. https://chat.whatsapp.com/...",
            hintStyle: TextStyle(color: textGrey.withOpacity(0.5)),
            filled: true,
            fillColor: sectionBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black87, width: 1.5),
            ),
            prefixIcon: Icon(
              _selectedBugMode == "number" ? Icons.phone_android_rounded : Icons.link,
              color: textGrey,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          ),
        ),

        const SizedBox(height: 24),

        if (availableBugs.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              "SELECT PAYLOAD BUG",
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFamily: 'Orbitron',
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            decoration: BoxDecoration(
              color: sectionBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: sectionBg,
                value: selectedBugId.isNotEmpty ? selectedBugId : null,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54),
                iconSize: 28,
                style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'ShareTechMono'),
                items: availableBugs.map((bug) {
                  return DropdownMenuItem<String>(
                    value: bug['bug_id'],
                    child: Row(
                      children: [
                        Icon(Icons.bug_report, color: accentWhite, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(bug['bug_name'])),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedBugId = value ?? "";
                  });
                },
              ),
            ),
          ),
        ] else ...[
           const Center(
             child: Padding(
               padding: EdgeInsets.all(16.0),
               child: Text("No payload available for this mode.", style: TextStyle(color: Colors.black54)),
             )
           )
        ]
      ],
    );
  }

  Widget _buildSendButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black38),
            color: Colors.black12,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05 * _pulseController.value),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isSending ? null : _sendBug,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            child: _isSending
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.black87,
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rocket_launch_outlined, color: Colors.black87, size: 20),
                      SizedBox(width: 12),
                      Text(
                        "LAUNCH ATTACK",
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 2,
                          fontFamily: 'Orbitron',
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopHeader(),
              const SizedBox(height: 20),
              
              if (_videoController != null && _videoController!.value.isInitialized)
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              _buildInputPanel(),
              const SizedBox(height: 30),
              
              _buildSendButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}