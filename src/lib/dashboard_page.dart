import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

// Import halaman lain
import 'nik_check.dart';
import 'admin_page.dart';
import 'owner_page.dart';
import 'home_page.dart';
import 'seller_page.dart';
import 'change_password_page.dart';
import 'tools_gateway.dart';
import 'login_page.dart';
import 'bug_sender.dart';
import 'contact_page.dart';
import 'profile_page.dart';
import 'riwayat_page.dart';
import 'info_page.dart';
import 'partner_page.dart';
import 'moderator_page.dart';
import 'widgets/custom_popup.dart';

class DashboardPage extends StatefulWidget {
  final String username;
  final String password;
  final String role;
  final String expiredDate;
  final String sessionKey;
  final List<Map<String, dynamic>> listBug;
  final List<Map<String, dynamic>> listDoos;
  final List<dynamic> news;

  const DashboardPage({
    super.key,
    required this.username,
    required this.password,
    required this.role,
    required this.expiredDate,
    required this.listBug,
    required this.listDoos,
    required this.sessionKey,
    required this.news,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late WebSocketChannel channel;

  // --- State Variabel ---
  late String sessionKey;
  late String username;
  late String password;
  late String role;
  late String expiredDate;
  late List<Map<String, dynamic>> listBug;
  late List<Map<String, dynamic>> listDoos;
  late List<dynamic> newsList;

  String androidId = "unknown";
  File? _profileImage;

  int _bottomNavIndex = 0;
  Widget _selectedPage = const Placeholder();

  int onlineUsers = 0;
  int activeConnections = 0;

  // --- Variabel Banner/News ---
  late PageController _newsPageController;
  double _currentNewsPage = 0.0; 
  Timer? _newsTimer;
  VideoPlayerController? _videoController;

  // --- TEMA WARNA BIRU HITAM (BLUE-BLACK DEEP) ---
  static const Color bgMain = Color(0xFFCED4DA);
  static const Color bgSurface = Color(0xFFFFFFFF);
  static const Color bgCard = Color(0xFFF8F9FA);
  static const Color textMain = Colors.black87;
  static const Color textSub = Colors.black54; // BlueGrey 400
  static const Color accentWhite = Color(0xFFFF99AC); // Cyan Accent
  static const Color borderLight = Color(0xFFFF99AC);
  static const Color borderGlass = Color(0xFFFF99AC); // Bright borders for buttons

  @override
  void initState() {
    super.initState();
    
    sessionKey = widget.sessionKey;
    username = widget.username;
    password = widget.password;
    role = widget.role;
    expiredDate = widget.expiredDate;
    listBug = widget.listBug;
    listDoos = widget.listDoos;
    newsList = widget.news;

    _videoController = VideoPlayerController.asset('assets/videos/bug.mp4')
      ..initialize().then((_) {
        setState(() {});
        _videoController?.setVolume(1.0); // Enable sound
        _videoController?.setLooping(true);
        _videoController?.play();
      });

    // Pastikan Banner di-init SEBELUM halaman dibangun
    _initNewsBanner();
    _selectedPage = _buildNewsPage();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    _initAndroidIdAndConnect();
    _loadProfileImage();
  }

  void _initNewsBanner() {
    _newsPageController = PageController(
      initialPage: 0,
      viewportFraction: 0.9,
    );

    // Listener ini akan memperbarui posisi untuk auto scroll (tanpa setState)
    _newsPageController.addListener(() {
      if (_newsPageController.hasClients && _newsPageController.page != null) {
        _currentNewsPage = _newsPageController.page!;
      }
    });

    if (newsList.isNotEmpty) {
      _newsTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
        if (_newsPageController.hasClients) {
          int targetIndex = (_currentNewsPage + 1).round() % newsList.length;
          _newsPageController.animateToPage(
            targetIndex,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('profile_image_$username');
    if (imagePath != null && imagePath.isNotEmpty) {
      setState(() {
        _profileImage = File(imagePath);
      });
    }
  }

  Future<void> _initAndroidIdAndConnect() async {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    androidId = deviceInfo.id;
    _connectToWebSocket();
  }

  void _connectToWebSocket() {
    channel = WebSocketChannel.connect(
      Uri.parse('wss://ws-pxp.darkverse.my.id'),
    );
    channel.sink.add(
      jsonEncode({
        "type": "validate",
        "key": sessionKey,
        "androidId": androidId,
      }),
    );
    channel.sink.add(jsonEncode({"type": "stats"}));

    channel.stream.listen((event) {
      final data = jsonDecode(event);
      if (data['type'] == 'myInfo') {
        if (data['valid'] == false) {
          if (data['reason'] == 'androidIdMismatch') {
            _handleInvalidSession("Your account has logged on another device.");
          } else if (data['reason'] == 'keyInvalid') {
            _handleInvalidSession("Key is not valid. Please login again.");
          }
        }
      }
      if (data['type'] == 'stats') {
        setState(() {
          onlineUsers = data['onlineUsers'] ?? 0;
          activeConnections = data['activeConnections'] ?? 0;
        });
      }
    });
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception("Could not launch $uri");
    }
  }

  void _handleInvalidSession(String message) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    CustomPopup.show(
      context,
      title: "Session Expired",
      message: message,
      icon: Icons.error_outline,
      iconColor: Colors.redAccent,
      confirmText: "OK",
      onConfirm: () {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      },
    );
  }

  void _onBottomNavTapped(int index) {
    if (index == 1) {
      _showWhatsAppMenu();
      return;
    }
    setState(() {
      _bottomNavIndex = index;
      if (index == 0) {
        _selectedPage = _buildNewsPage();
      } else if (index == 2) {
        _selectedPage = InfoPage(sessionKey: sessionKey);
      } else if (index == 3) {
        _selectedPage = ToolsPage(
          sessionKey: sessionKey,
          userRole: role,
          listDoos: listDoos,
        );
      }
    });
  }

  void _showWhatsAppMenu() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(FontAwesomeIcons.whatsapp, size: 36, color: Color(0xFF25D366)),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "WHATSAPP TOOLS",
                    style: TextStyle(
                      color: Colors.black87,
                      fontFamily: 'Orbitron',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Choose an action to perform",
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  _buildWhatsAppOption(
                    icon: Icons.bug_report,
                    color: Colors.redAccent,
                    title: "WhatsApp Crash",
                    subtitle: "Send payloads & crash codes",
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _bottomNavIndex = 1;
                        _selectedPage = HomePage(
                          username: username,
                          password: password,
                          listBug: listBug,
                          role: role,
                          expiredDate: expiredDate,
                          sessionKey: sessionKey,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildWhatsAppOption(
                    icon: Icons.devices,
                    color: Colors.greenAccent,
                    title: "Manage Sender",
                    subtitle: "Pair devices & manage sessions",
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => BugSenderPage(sessionKey: sessionKey, username: username, role: role)));
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWhatsAppOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontFamily: 'ShareTechMono',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.black26, size: 14),
          ],
        ),
      ),
    );
  }

  void _onSidebarTabSelected(int index) {
    setState(() {
      if (index == 1) {
        _selectedPage = SellerPage(keyToken: sessionKey);
      } else if (index == 2) {
        _selectedPage = AdminPage(sessionKey: sessionKey);
      } else if (index == 3) {
        _selectedPage = OwnerPage(sessionKey: sessionKey, username: username);
      } else if (index == 4) {
        _selectedPage = PartnerPage(sessionKey: sessionKey, username: username);
      } else if (index == 5) {
        _selectedPage = ModeratorPage(
          sessionKey: sessionKey,
          username: username,
        );
      }
    });
    Navigator.pop(context);
  }

  Widget _buildNewsPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),

          // INFO PANEL WITH VIDEO BACKGROUND
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderLight, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video Background
                    if (_videoController != null && _videoController!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    else
                      Container(color: Colors.black87),
                    
                    // Transparent Dark Overlay
                    Container(
                      color: Colors.black.withOpacity(0.4),
                    ),

                    // Content Box (Glassmorphism inside)
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Welcome Back,", style: TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'ShareTechMono')),
                          Text(
                            "Hai, ${username.toUpperCase()}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Orbitron', letterSpacing: 1.0)
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Status Account:", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.shield, color: accentWhite, size: 14),
                                    const SizedBox(width: 6),
                                    Text("Role: ${role.toUpperCase()}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.timer, color: accentWhite, size: 14),
                                    const SizedBox(width: 6),
                                    Text("Expired: $expiredDate", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 30),

          // JOIN CHANNEL (Moved Above News)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("COMMUNITY HUB", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Orbitron', letterSpacing: 1.2)),
                const SizedBox(height: 6),
                const Text("Stay connected with the LU:NΞX Project community. Get real-time updates, access exclusive payloads, and participate in discussions with other members.", style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 55,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: accentWhite.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: const Icon(FontAwesomeIcons.telegram, color: Colors.white, size: 20),
                    label: const Text("Join Telegram Channel", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentWhite, 
                      shadowColor: Colors.transparent, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _openUrl("https://t.me/InformationZarr"),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),

          // NEWS SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LATEST UPDATES", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Orbitron', letterSpacing: 1.2)),
                const SizedBox(height: 6),
                const Text("Keep yourself informed about recent system maintenance, newly added tools, and important announcements from the administration.", style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 180,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Stack(
              children: [
                PageView.builder(
                  controller: _newsPageController,
                  itemCount: newsList.length,
                  itemBuilder: (context, index) {
                    final item = newsList[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: bgCard,
                        border: Border.all(color: borderLight, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (item['image'] != null &&
                                item['image'].toString().isNotEmpty)
                              NewsMedia(url: item['image']),
                            if (item['image'] == null)
                               Container(color: bgCard, child: const Icon(Icons.newspaper, color: textSub, size: 50)),
                            
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withOpacity(0.8),
                                    Colors.transparent,
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 30,
                              left: 20,
                              right: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title'] ?? 'No Title',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['desc'] ?? '',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                
                // --- EXPANDING DOTS (Efek Geser Membesar) ---
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _newsPageController,
                    builder: (context, child) {
                      double currentNewsPage = 0.0;
                      if (_newsPageController.hasClients && _newsPageController.page != null) {
                        currentNewsPage = _newsPageController.page!;
                      } else {
                        currentNewsPage = _currentNewsPage;
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(newsList.length, (index) {
                          // Hitung jarak antara halaman scroll saat ini dengan index titik
                          double diff = (index - currentNewsPage).abs();
                          
                          // Atur Ukuran: 
                          // Jika aktif (diff = 0), width = 25.
                          // Jika pasif (diff >= 1), width = 5.
                          // Di antaranya, interpolasi ukuran.
                          double width = 5.0;
                          double opacity = 0.3;

                          if (diff < 1) {
                            width = 25.0 - (diff * 20.0); // 25 -> 5
                            opacity = 1.0 - (diff * 0.7);  // 1.0 -> 0.3
                          }

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            width: width, // Width berubah saat digeser
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(opacity),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 100), // Added padding for floating bottom nav
        ],
      ),
    );
  }

  Widget _buildCustomDrawer() {
    return Drawer(
      backgroundColor: bgMain,
      width: MediaQuery.of(context).size.width * 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 180,
            decoration: const BoxDecoration(color: bgMain),
            child: SafeArea(
              child: Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: bgMain,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  if (role == "reseller") _buildDrawerMenuItem(icon: Icons.storefront, label: "Seller Page", onTap: () => _onSidebarTabSelected(1)),
                  if (role == "admin") _buildDrawerMenuItem(icon: Icons.admin_panel_settings, label: "Admin Page", onTap: () => _onSidebarTabSelected(2)),
                  if (role == "partner") _buildDrawerMenuItem(icon: FontAwesomeIcons.handshake, label: "Partner Page", onTap: () => _onSidebarTabSelected(4)),
                  if (role == "moderator") _buildDrawerMenuItem(icon: FontAwesomeIcons.userShield, label: "Moderator Page", onTap: () => _onSidebarTabSelected(5)),
                  if (role == "owner") _buildDrawerMenuItem(icon: Icons.workspace_premium, label: "Owner Page", onTap: () => _onSidebarTabSelected(3)),
                  _buildDrawerMenuItem(icon: Icons.history_rounded, label: "Riwayat Aktivitas", onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => RiwayatPage(sessionKey: sessionKey, role: role))); }),
                  const SizedBox(height: 20),
                  _buildDrawerMenuItem(icon: Icons.logout, label: "Log Out", isLogout: true, onTap: () async { Navigator.pop(context); final prefs = await SharedPreferences.getInstance(); await prefs.clear(); if (!mounted) return; Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false); }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerMenuItem({required IconData icon, required String label, required VoidCallback onTap, bool isLogout = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isLogout ? Colors.redAccent : Colors.transparent, 
        borderRadius: BorderRadius.circular(12), 
        boxShadow: isLogout ? [BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)] : null,
      ),
      child: ListTile(
        leading: Icon(icon, color: isLogout ? Colors.white : textSub, size: 22),
        title: Text(label, style: TextStyle(color: isLogout ? Colors.white : textMain, fontWeight: FontWeight.bold, fontSize: 15)),
        trailing: Icon(Icons.arrow_forward_ios, color: isLogout ? Colors.white70 : const Color(0xFF555555), size: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgMain,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("LU:NΞX Project", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Orbitron', letterSpacing: 2.0)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(icon: const Icon(Icons.headset_mic_outlined, color: Colors.black87), tooltip: 'Customer Service', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactPage()))),
          IconButton(icon: const Icon(FontAwesomeIcons.userCircle, color: Colors.black87), tooltip: 'My Profile', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(username: username, password: password, role: role, expiredDate: expiredDate, sessionKey: sessionKey)))),
        ],
      ),
      drawer: _buildCustomDrawer(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(color: bgMain),
        child: SafeArea(child: FadeTransition(opacity: _animation, child: _selectedPage)),
      ),
      extendBody: true,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9), // Glassmorphism-ish
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BottomNavigationBar(
                elevation: 0,
                backgroundColor: Colors.transparent,
                selectedItemColor: Colors.black87,
                unselectedItemColor: textSub,
                currentIndex: _bottomNavIndex,
                onTap: _onBottomNavTapped,
                showSelectedLabels: false,
                showUnselectedLabels: false,
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: "Home"),
                  BottomNavigationBarItem(icon: Icon(FontAwesomeIcons.whatsapp), label: "WhatsApp"),
                  BottomNavigationBarItem(icon: Icon(Icons.notifications_none), activeIcon: Icon(Icons.notifications), label: "Info"),
                  BottomNavigationBarItem(icon: Icon(Icons.build_circle_outlined), activeIcon: Icon(Icons.build_circle), label: "Tools"),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _newsTimer?.cancel();
    _newsPageController.dispose();
    channel.sink.close(status.goingAway);
    _controller.dispose();
    super.dispose();
  }
}

class NewsMedia extends StatelessWidget {
  final String url;
  const NewsMedia({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.endsWith(".mp4") || url.endsWith(".webm") || url.endsWith(".mov")) {
      return Container(color: Colors.black, child: const Center(child: Icon(Icons.videocam_off, color: Colors.grey, size: 50)));
    }
    return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1C1C1E), child: const Center(child: Icon(Icons.broken_image, color: Colors.grey))));
  }
}