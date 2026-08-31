import 'config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dashboard_page.dart';
import 'splash_video_page.dart';
import 'widgets/custom_popup.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final userController = TextEditingController();
  final passController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool isLoading = false;
  bool _obscurePassword = true;
  String? androidId;

  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  // --- Palette Warna Professional Blue-Black ---
  static const Color bgMain = Color(0xFFCED4DA);
  static const Color bgSurface = Color(0xFFF8F9FA);
  static const Color bgInput = Color(0xFFFFFFFF);
  static const Color primaryText = Colors.black87;
  static const Color secondaryText = Colors.black54;
  static const Color accentColor = Color(0xFFFF99AC);
  static const Color errorColor = Color(0xFFFF5252);

  @override
  void initState() {
    super.initState();
    _initAnim();
    initLogin();
  }

  void _initAnim() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();
  }

  // --- LOGIC ---
  Future<void> initLogin() async {
    androidId = await getAndroidId();
    final prefs = await SharedPreferences.getInstance();
    final savedUser = prefs.getString("username");
    final savedPass = prefs.getString("password");
    final savedKey = prefs.getString("key");

    if (savedUser != null && savedPass != null && savedKey != null) {
      final uri = Uri.parse(
          "$apiBaseUrl/myInfo?username=$savedUser&password=$savedPass&androidId=$androidId&key=$savedKey");

      try {
        final res = await http.get(uri);
        final data = jsonDecode(res.body);
        if (data['valid'] == true) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SplashVideoPage(
                  nextPage: DashboardPage(
                    username: savedUser,
                    password: savedPass,
                    role: data['role'],
                    sessionKey: data['key'],
                    expiredDate: data['expiredDate'],
                    uid: (data['uid'] ?? '00000000').toString(),
                    listBug: (data['listBug'] as List? ?? [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList(),
                    listDoos: (data['listDDoS'] as List? ?? [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList(),
                    news: (data['news'] as List? ?? [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList(),
                  ),
                ),
              ),
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<String> getAndroidId() async {
    final deviceInfo = DeviceInfoPlugin();
    final android = await deviceInfo.androidInfo;
    return android.id ?? "unknown_device";
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    final username = userController.text.trim();
    final password = passController.text.trim();

    setState(() => isLoading = true);

    try {
      final validate = await http.post(
        Uri.parse("$apiBaseUrl/validate"),
        body: {
          "username": username,
          "password": password,
          "androidId": androidId ?? "unknown_device",
        },
      );

      final validData = jsonDecode(validate.body);

      if (validData['expired'] == true) {
        _showPopup(
          title: "Access Expired",
          message: "Masa akses Anda telah habis.\nSilakan perpanjang akses.",
          showContact: true,
        );
      } else if (validData['valid'] != true) {
        final String errorMsg = (validData['message'] ?? "").toLowerCase();
        if (errorMsg.contains("perangkat") ||
            errorMsg.contains("device") ||
            errorMsg.contains("another")) {
          _showPopup(
            title: "Sesi Aktif",
            message: "Akun ini sedang login di perangkat lain.\nSilakan logout di perangkat lama.",
          );
        } else {
          _showPopup(
            title: "Login Gagal",
            message: "Username atau password salah.",
          );
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        prefs.setString("username", username);
        prefs.setString("password", password);
        prefs.setString("key", validData['key']);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SplashVideoPage(
                nextPage: DashboardPage(
                  username: username,
                  password: password,
                  role: validData['role'],
                  sessionKey: validData['key'],
                  expiredDate: validData['expiredDate'],
                  uid: (validData['uid'] ?? '00000000').toString(),
                  listBug: (validData['listBug'] as List? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList(),
                  listDoos: (validData['listDDoS'] as List? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList(),
                  news: (validData['news'] as List? ?? [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList(),
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      _showPopup(
        title: "Connection Error",
        message: "Gagal terhubung ke server.",
      );
    }

    setState(() => isLoading = false);
  }

  void _showPopup({
    required String title,
    required String message,
    bool showContact = false,
  }) {
    final bool isError = title.toLowerCase().contains("gagal") || 
                         title.toLowerCase().contains("expired") || 
                         title.toLowerCase().contains("error");
                         
    CustomPopup.show(
      context,
      title: title,
      message: message,
      icon: isError ? Icons.error_outline : Icons.info_outline,
      iconColor: isError ? errorColor : accentColor,
      cancelText: showContact ? "Contact Admin" : null,
      onCancel: showContact 
          ? () async {
              await launchUrl(Uri.parse("https://t.me/Z4rrfly"),
                  mode: LaunchMode.externalApplication);
            }
          : null,
      confirmText: "Close",
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    userController.dispose();
    passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgMain,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: bgMain,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 200,
                              height: 200,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 30),
                          const Text(
                            "Welcome Back",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: primaryText,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Please enter your details to sign in",
                            style: TextStyle(
                              fontSize: 15,
                              color: secondaryText,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    SlideTransition(
                      position: _slideAnim,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: userController,
                              label: "Username",
                              hint: "Enter your username",
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              controller: passController,
                              label: "Password",
                              hint: "Enter your password",
                              icon: Icons.lock_outline,
                              isPassword: true,
                            ),
                            const SizedBox(height: 32),
                            _buildButton(),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final url = Uri.parse("https://t.me/Z4rrfly");
                                  try {
                                    await launchUrl(url, mode: LaunchMode.externalApplication);
                                  } catch (_) {
                                    await launchUrl(url, mode: LaunchMode.platformDefault);
                                  }
                                },
                                icon: Icon(Icons.shopping_cart_outlined, size: 20, color: secondaryText),
                                label: const Text(
                                  "No Access? Buy Here",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: primaryText,
                                  backgroundColor: Colors.black.withOpacity(0.03),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: Colors.black.withOpacity(0.05)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            Text(
                              "By continuing, you agree to our Terms of Service",
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.3),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgInput,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        style: const TextStyle(color: primaryText, fontSize: 16),
        cursorColor: accentColor,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: secondaryText, fontSize: 14),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.black.withOpacity(0.2)),
          prefixIcon: Icon(icon, color: secondaryText, size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: secondaryText,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : login,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: const Color(0xFFCED4DA),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFCED4DA)),
                ),
              )
            : const Text(
                "Sign In",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}