import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'dart:ui';

class AttackPage extends StatefulWidget {
  final String username;
  final String password;
  final String sessionKey;
  final List<Map<String, dynamic>> listBug;
  final String role;
  final String expiredDate;

  const AttackPage({
    super.key,
    required this.username,
    required this.password,
    required this.sessionKey,
    required this.listBug,
    required this.role,
    required this.expiredDate,
  });

  @override
  State<AttackPage> createState() => _AttackPageState();
}

class _AttackPageState extends State<AttackPage> with TickerProviderStateMixin {
  final targetController = TextEditingController();
  static const String baseUrl = "http://elainakurumiipanel.xtxintax.my.id:2012";

  // Animation controllers
  late AnimationController _buttonController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _glowController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _glowAnimation;

  // Video controllers
  late VideoPlayerController _videoController;
  bool _videoInitialized = false;
  bool _videoError = false;

  // State variables
  String selectedBugId = "";
  bool _isSending = false;
  bool _isSuccess = false;
  int _activeStep = 0;

  // COLOR THEME: Abu-abu Menyala (Bright Gray)
  final Color _themeColor = const Color(0xFFD6D6D6);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeVideoController();
    _setDefaultBug();
    _startAnimations();
  }

  void _initializeAnimations() {
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  void _startAnimations() {
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _slideController.forward();
    });
  }

  void _setDefaultBug() {
    if (widget.listBug.isNotEmpty) {
      selectedBugId = widget.listBug[0]['bug_id'];
    }
  }

  void _initializeVideoController() {
    try {
      _videoController = VideoPlayerController.asset('assets/videos/banner.mp4')
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _videoInitialized = true;
            });
            _videoController.setLooping(true);
            _videoController.play();
            _videoController.setVolume(0);
          }
        }).catchError((error) {
          print('Video initialization error: $error');
          if (mounted) {
            setState(() {
              _videoError = true;
            });
          }
        });
    } catch (e) {
      print('Video controller creation error: $e');
      if (mounted) {
        setState(() {
          _videoError = true;
        });
      }
    }
  }

  String? formatPhoneNumber(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('0') || cleaned.length < 8) return null;
    return cleaned;
  }

  Future<void> _sendBug() async {
    if (_isSending) return;

    setState(() {
      _isSending = true;
      _activeStep = 1;
    });

    _buttonController.forward().then((_) {
      _buttonController.reverse();
    });

    final rawInput = targetController.text.trim();
    final target = formatPhoneNumber(rawInput);
    final key = widget.sessionKey;

    if (target == null || key.isEmpty) {
      _showAlert("❌ Invalid Number", "Gunakan nomor internasional (misal: +62, 1, 44), bukan 08xxx.");
      setState(() {
        _isSending = false;
        _activeStep = 0;
      });
      return;
    }

    try {
      final res = await http.get(Uri.parse("$baseUrl/api/whatsapp/sendBug?key=$key&target=$target&bug=$selectedBugId"));
      final data = jsonDecode(res.body);

      if (data["cooldown"] == true) {
        _showAlert("⏳ Cooldown", "Tunggu beberapa saat sebelum mengirim lagi.");
      } else if (data["senderOn"] == false) {
        _showAlert("⚠️ Gagal", "Gagal mengirim bug. Sender Kosong, Hubungi Seller.");
      } else if (data["valid"] == false) {
        _showAlert("❌ Key Invalid", "Session key tidak valid. Silakan login ulang.");
      } else if (data["sended"] == false) {
        _showAlert("⚠️ Gagal", "Gagal mengirim bug. Mungkin server sedang maintenance.");
      } else {
        setState(() {
          _activeStep = 2;
          _isSuccess = true;
        });
        _showSuccessPopup(target);
      }
    } catch (_) {
      _showAlert("❌ Error", "Terjadi kesalahan. Coba lagi.");
    } finally {
      setState(() {
        _isSending = false;
        if (!_isSuccess) _activeStep = 0;
      });
    }
  }

  void _showSuccessPopup(String target) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SuccessVideoDialog(
        target: target,
        onDismiss: () {
          Navigator.of(context).pop();
          setState(() {
            _isSuccess = false;
            _activeStep = 0;
          });
        },
      ),
    );
  }

  void _showAlert(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _themeColor.withOpacity(0.3), width: 1),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontFamily: 'Orbitron')),
        content: Text(msg, style: const TextStyle(color: Colors.white70, fontFamily: 'ShareTechMono')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: _themeColor)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Animated background
          _buildAnimatedBackground(),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.black.withOpacity(0.85),
                  Colors.black,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // User info header with glassmorphism
                        _buildUserInfoHeader(),

                        const SizedBox(height: 20),

                        // Progress indicator
                        _buildProgressIndicator(),

                        const SizedBox(height: 20),

                        // Main content cards
                        _buildTargetInputCard(),

                        const SizedBox(height: 14),

                        _buildPayloadTypeCard(),

                        const SizedBox(height: 20),

                        _buildStatusIndicators(),

                        const SizedBox(height: 20),

                        _buildSendButton(),

                        const SizedBox(height: 14),

                        _buildFooterInfo(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return _videoInitialized && !_videoError
        ? SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoController.value.size.width,
          height: _videoController.value.size.height,
          child: VideoPlayer(_videoController),
        ),
      ),
    )
        : Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0A0A0A),
            Color(0xFF121212),
            Color(0xFF1A1A1A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Animated particles with gray theme
          ...List.generate(15, (index) {
            final size = (index % 5 + 1) * 2.0;
            final opacity = (index % 5 + 1) / 10.0;
            return AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return Positioned(
                  left: (index * 73.0) % MediaQuery.of(context).size.width,
                  top: (index * 137.0) % MediaQuery.of(context).size.height,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: _themeColor.withOpacity(opacity * _glowAnimation.value),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          _buildStepIndicator(0, "Input", FontAwesomeIcons.edit),
          _buildProgressLine(),
          _buildStepIndicator(1, "Process", FontAwesomeIcons.cogs),
          _buildProgressLine(),
          _buildStepIndicator(2, "Complete", FontAwesomeIcons.checkCircle),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, IconData icon) {
    final isActive = _activeStep >= step;
    final isCurrent = _activeStep == step;

    return Expanded(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? (isCurrent
                  ? _themeColor.withOpacity(0.2)
                  : _themeColor.withOpacity(0.2))
                  : Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? (isCurrent
                    ? _themeColor.withOpacity(0.5)
                    : _themeColor.withOpacity(0.5))
                    : Colors.white.withOpacity(0.2),
                width: 2,
              ),
              boxShadow: isCurrent
                  ? [
                BoxShadow(
                  color: _themeColor.withOpacity(0.2 * _glowAnimation.value),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive
                  ? (isCurrent ? Colors.white : _themeColor)
                  : Colors.white.withOpacity(0.4),
              size: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive
                  ? (isCurrent ? Colors.white : _themeColor)
                  : Colors.white.withOpacity(0.4),
              fontSize: 11,
              fontFamily: 'Orbitron',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressLine() {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _activeStep > 0
                ? [_themeColor, _themeColor.withOpacity(0.3)]
                : [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.1)],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // User avatar with glow effect
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              return Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _themeColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _themeColor.withOpacity(0.3 * _glowAnimation.value),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _themeColor.withOpacity(0.1 * _glowAnimation.value),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  FontAwesomeIcons.userShield,
                  color: _themeColor,
                  size: 20,
                ),
              );
            },
          ),

          const SizedBox(width: 14),

          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Orbitron',
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getRoleColor().withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _getRoleColor().withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    widget.role.toUpperCase(),
                    style: TextStyle(
                      color: _getRoleColor(),
                      fontSize: 11,
                      fontFamily: 'ShareTechMono',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expiry date
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  FontAwesomeIcons.calendarAlt,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(height: 2),
                Text(
                  "EXP",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 9,
                    fontFamily: 'ShareTechMono',
                  ),
                ),
                Text(
                  widget.expiredDate,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'ShareTechMono',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor() {
    switch (widget.role.toLowerCase()) {
      case 'owner':
        return Colors.red;
      case 'high owner':
        return Colors.red;
      case 'vip':
        return Colors.amber;
      case 'reseller':
        return Colors.blue;
      default:
        return _themeColor;
    }
  }

  Widget _buildTargetInputCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  FontAwesomeIcons.phone,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Target Number",
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Orbitron',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: targetController,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: "e.g. +62xxxxxxxxx",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _themeColor, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FontAwesomeIcons.globe,
                  color: Colors.white70,
                  size: 16,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Use international format without 0 or +",
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
              fontFamily: 'ShareTechMono',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadTypeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  FontAwesomeIcons.whatsapp,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Bug Type",
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Orbitron',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: Colors.black.withOpacity(0.9),
                value: selectedBugId,
                isExpanded: true,
                iconEnabledColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: widget.listBug.map((bug) {
                  return DropdownMenuItem<String>(
                    value: bug['bug_id'],
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _themeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              FontAwesomeIcons.virus,
                              color: _themeColor,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  bug['bug_name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (bug['description'] != null)
                                  Text(
                                    bug['description'],
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 11,
                                      height: 1.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedBugId = value!;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                FontAwesomeIcons.infoCircle,
                color: Colors.white.withOpacity(0.5),
                size: 12,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Select the appropriate bug type for maximum effectiveness",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontFamily: 'ShareTechMono',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildStatusIndicators() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "System Status",
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Orbitron',
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statusIndicator(
                icon: FontAwesomeIcons.server,
                label: "Server",
                isOnline: true,
              ),
              _statusIndicator(
                icon: FontAwesomeIcons.shieldAlt,
                label: "Security",
                isOnline: true,
              ),
              _statusIndicator(
                icon: FontAwesomeIcons.database,
                label: "Database",
                isOnline: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusIndicator({required IconData icon, required String label, required bool isOnline}) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isOnline
                    ? Colors.white.withOpacity(0.1 + 0.1 * _glowAnimation.value)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOnline
                      ? Colors.white.withOpacity(0.3 + 0.2 * _glowAnimation.value)
                      : Colors.white.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: isOnline
                    ? [
                  BoxShadow(
                    color: _themeColor.withOpacity(0.1 * _glowAnimation.value),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
                    : null,
              ),
              child: Icon(
                icon,
                color: isOnline ? Colors.white : Colors.white70,
                size: 20,
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 11,
            fontFamily: 'ShareTechMono',
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 50,
          height: 3,
          decoration: BoxDecoration(
            color: isOnline ? _themeColor : Colors.red.withOpacity(0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildSendButton() {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _themeColor.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _themeColor.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ElevatedButton.icon(
              icon: _isSending
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : const Icon(FontAwesomeIcons.paperPlane, color: Colors.white, size: 18),
              label: Text(
                _isSending ? "SENDING..." : "SEND BUG",
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Orbitron',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isSending ? null : _sendBug,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooterInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            FontAwesomeIcons.exclamationTriangle,
            color: Colors.white.withOpacity(0.5),
            size: 14,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Use this tool responsibly. We are not responsible for any misuse.",
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
                fontFamily: 'ShareTechMono',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _buttonController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _glowController.dispose();
    _videoController.dispose();
    targetController.dispose();
    super.dispose();
  }
}

// Custom success dialog with video
class SuccessVideoDialog extends StatefulWidget {
  final String target;
  final VoidCallback onDismiss;

  const SuccessVideoDialog({
    super.key,
    required this.target,
    required this.onDismiss,
  });

  @override
  State<SuccessVideoDialog> createState() => _SuccessVideoDialogState();
}

class _SuccessVideoDialogState extends State<SuccessVideoDialog> with TickerProviderStateMixin {
  late VideoPlayerController _successVideoController;
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _glowController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  bool _showSuccessInfo = false;
  bool _videoError = false;
  bool _videoInitialized = false;

  // COLOR THEME: Abu-abu Menyala
  final Color _themeColor = const Color(0xFFD6D6D6);

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _initializeSuccessVideo();
  }

  void _initializeSuccessVideo() {
    try {
      _successVideoController = VideoPlayerController.asset('assets/videos/splash.mp4')
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _videoInitialized = true;
            });
            _successVideoController.play();

            // Listen for video completion
            _successVideoController.addListener(() {
              if (_successVideoController.value.position >= _successVideoController.value.duration) {
                _showSuccessMessage();
              }
            });
          }
        }).catchError((error) {
          print('Success video error: $error');
          if (mounted) {
            setState(() {
              _videoError = true;
            });
            // Show success message immediately if video fails
            Future.delayed(const Duration(milliseconds: 500), () {
              _showSuccessMessage();
            });
          }
        });
    } catch (e) {
      print('Video controller error: $e');
      if (mounted) {
        setState(() {
          _videoError = true;
        });
        // Show success message immediately if video fails
        Future.delayed(const Duration(milliseconds: 500), () {
          _showSuccessMessage();
        });
      }
    }
  }

  void _showSuccessMessage() {
    if (mounted) {
      setState(() {
        _showSuccessInfo = true;
      });
      _fadeController.forward();
      _scaleController.forward();
    }
  }

  @override
  void dispose() {
    _successVideoController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.9;
    final dialogHeight = screenSize.height * 0.45;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _themeColor.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _themeColor.withOpacity(0.1),
                blurRadius: 15,
                spreadRadius: 3,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Video or fallback
              if (!_showSuccessInfo)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _videoInitialized && !_videoError
                      ? SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _successVideoController.value.size.width,
                        height: _successVideoController.value.size.height,
                        child: VideoPlayer(_successVideoController),
                      ),
                    ),
                  )
                      : Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black,
                          _themeColor.withOpacity(0.1),
                          Colors.black,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _glowController,
                            builder: (context, child) {
                              return Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: _themeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: _themeColor.withOpacity(0.3 * _glowAnimation.value),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _themeColor.withOpacity(0.2 * _glowAnimation.value),
                                      blurRadius: 15,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  FontAwesomeIcons.check,
                                  color: _themeColor,
                                  size: 50,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "SUCCESS",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Orbitron',
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Success info overlay
              if (_showSuccessInfo)
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.9),
                            Colors.black.withOpacity(0.95),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _glowController,
                            builder: (context, child) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _themeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: _themeColor.withOpacity(0.3 * _glowAnimation.value),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _themeColor.withOpacity(0.2 * _glowAnimation.value),
                                      blurRadius: 15,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  FontAwesomeIcons.checkDouble,
                                  color: _themeColor,
                                  size: 36,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "Attack Successful!",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Orbitron',
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Bug successfully sent to ${widget.target}",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                              fontFamily: 'ShareTechMono',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: widget.onDismiss,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _themeColor.withOpacity(0.1),
                              foregroundColor: _themeColor,
                              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                                side: BorderSide(
                                  color: _themeColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: const Text(
                              "DONE",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Orbitron',
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
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
}