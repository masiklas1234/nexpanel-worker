import 'config.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class InfoPage extends StatefulWidget {
  final String sessionKey;

  const InfoPage({super.key, required this.sessionKey});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> with TickerProviderStateMixin {
  bool isLoading = true;

  bool isApiOnline = false;
  int apiPingMs = 0;
  Color apiStatusColor = Colors.black54;
  String apiStatusText = "Checking...";
  Timer? _pingTimer;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  final Color bgDark = const Color(0xFFCED4DA);
  final Color cardBg = const Color(0xFFF8F9FA);
  final Color borderLight = const Color(0xFFFF99AC);
  final Color textMain = Colors.black87;
  final Color textSub = Colors.black54;

  final List<Map<String, dynamic>> rulesList = [
    {
      "title": "NO ACCOUNT BARTERING",
      "icon": Icons.swap_horizontal_circle_outlined,
      "desc": "Akun eksklusif LU:NΞX Project tidak boleh ditukar dengan barang, jasa, atau akun lain dalam bentuk apa pun. Pelanggaran log akan terpantau."
    },
    {
      "title": "STRICTLY PERSONAL USE",
      "icon": Icons.person_off_outlined,
      "desc": "Setiap akun terenkripsi untuk satu pengguna dan hanya boleh diakses oleh pemilik perangkat yang mendaftar (terikat Device ID)."
    },
    {
      "title": "RESELLING PROHIBITED",
      "icon": Icons.money_off_csred_outlined,
      "desc": "Member reguler dilarang memperjualbelikan akun. Akses penjualan eksklusif milik role berwenang (Partner, Owner, atau Reseller)."
    },
    {
      "title": "ILLEGAL DURATION SALES",
      "icon": Icons.timer_off_outlined,
      "desc": "Sangat dilarang membagi atau menjual akses eceran (harian, mingguan, trial) yang mengelabui skema periode resmi."
    },
    {
      "title": "PRICE DUMPING BAN",
      "icon": Icons.trending_down_rounded,
      "desc": "Dilarang keras merusak standar harga pasar (banting harga) di bawah kesepakatan jaminan keamanan platform kami."
    },
  ];

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    
    _fetchServerInfo();
    _startApiPingLoop();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _fetchServerInfo() async {
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/getServerInfo?key=${widget.sessionKey}'));
      if (mounted) setState(() => isLoading = false);
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _startApiPingLoop() {
    _checkApiPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkApiPing());
  }

  Future<void> _checkApiPing() async {
    final start = DateTime.now();
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/ping?key=${widget.sessionKey}')).timeout(const Duration(seconds: 3));
      final duration = DateTime.now().difference(start).inMilliseconds;

      if (res.statusCode == 200 && mounted) {
        setState(() {
          isApiOnline = true;
          apiPingMs = duration;
          if (duration < 200) {
            apiStatusColor = const Color(0xFF00E676);
          } else if (duration < 500) {
            apiStatusColor = const Color(0xFFFFD54F);
          } else {
            apiStatusColor = const Color(0xFFFF8A65);
          }
          apiStatusText = "Sys.Online :: ${duration}ms";
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          isApiOnline = false;
          apiPingMs = 0;
          apiStatusColor = const Color(0xFFD32F2F);
          apiStatusText = "Sys.Offline :: DEST";
        });
      }
    }
  }

  Widget _buildStatusHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: apiStatusColor.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: apiStatusColor,
                  boxShadow: [
                    BoxShadow(
                      color: apiStatusColor.withOpacity(_glowAnimation.value * 0.6),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              apiStatusText.toUpperCase(),
              style: TextStyle(
                color: apiStatusColor == Colors.black54 ? textMain : apiStatusColor,
                fontFamily: 'ShareTechMono',
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
          ),
          Icon(Icons.memory, color: textSub.withOpacity(0.5), size: 20),
        ],
      ),
    );
  }

  Widget _buildPenaltyBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 30),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFD32F2F).withOpacity(0.15),
            const Color(0xFFCED4DA),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD32F2F).withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF5350), size: 28),
              const SizedBox(width: 10),
              const Text(
                "VIOLATION PENALTY",
                style: TextStyle(
                  color: Color(0xFFEF5350),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Orbitron',
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "Jika pengguna terdeteksi melanggar salah satu protokol kerahasiaan & aturan di atas secara sengaja:",
            style: TextStyle(color: Colors.black87, fontSize: 13, fontFamily: 'ShareTechMono'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFD32F2F).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEF5350).withOpacity(0.4)),
            ),
            child: const Text(
              "AKUN AKAN DIHAPUS PERMANEN",
              style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "TIDAK ADA PENGEMBALIAN SALDO ATAU KOMPENSASI.",
            style: TextStyle(
              color: const Color(0xFFEF5350).withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'ShareTechMono'
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(int index, Map<String, dynamic> rule) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: const Color(0xFFFF99AC),
          collapsedIconColor: const Color(0xFFFF99AC).withOpacity(0.54),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF99AC).withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF99AC).withOpacity(0.12)),
            ),
            child: Icon(rule['icon'], color: const Color(0xFFFF99AC), size: 24),
          ),
          title: Text(
            rule['title'],
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'Orbitron',
              letterSpacing: 1.0,
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 4),
              width: double.infinity,
              child: Text(
                rule['desc'],
                style: TextStyle(
                  color: textSub,
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'ShareTechMono',
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: bgDark,
        body: const Center(
          child: CircularProgressIndicator(color: const Color(0xFFFF99AC)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: bgDark,
              elevation: 0,
              pinned: true,
              automaticallyImplyLeading: false,
              expandedHeight: 80,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                title: const Text(
                  "EULA & SYSTEM INFO",
                  style: TextStyle(
                    color: Colors.black87,
                    fontFamily: 'Orbitron',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    fontSize: 16,
                  ),
                ),
                centerTitle: false,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildStatusHeader(),
                  
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16, top: 8),
                    child: Text(
                      "USER PROTOCOLS",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                        fontFamily: 'Orbitron'
                      ),
                    ),
                  ),
                  
                  ...rulesList.asMap().entries.map((e) => _buildRuleCard(e.key, e.value)).toList(),
                  
                  _buildPenaltyBox(),
                  
                  Center(
                    child: Column(
                      children: [
                        const Icon(Icons.shield_moon_rounded, color: Colors.black26, size: 30),
                        const SizedBox(height: 12),
                        const Text(
                          "Peraturan ini dibuat semata-mata untuk menjaga keamanan, kenyamanan, dan kestabilan ekosistem server LU:NΞX Project. Dengan mengakses aplikasi, Anda secara otomatis menyetujui seluruh protokol di atas.",
                          style: TextStyle(
                            color: Colors.black38,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            fontFamily: 'ShareTechMono',
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 3,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}