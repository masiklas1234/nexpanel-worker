import 'config.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'widgets/custom_popup.dart';

class OwnerPage extends StatefulWidget {
  final String sessionKey;
  final String username;

  const OwnerPage({
    super.key,
    required this.sessionKey,
    required this.username,
  });

  @override
  State<OwnerPage> createState() => _OwnerPageState();
}

class _OwnerPageState extends State<OwnerPage> {
  late String sessionKey;
  List<dynamic> fullUserList = [];
  List<dynamic> filteredList = [];

  final List<String> roleOptions = ['moderator', 'partner', 'admin', 'reseller', 'vip', 'member'];
  String selectedRole = 'member'; 

  int currentPage = 1;
  int itemsPerPage = 25;

  final createUsernameController = TextEditingController();
  final createPasswordController = TextEditingController();
  final createDayController = TextEditingController();
  final deleteController = TextEditingController();
  final editUsernameController = TextEditingController();
  final editDayController = TextEditingController();

  String newUserRole = 'member';
  bool isLoading = false;

  final Color bgDark = const Color(0xFFCED4DA);
  final Color primaryPurple = const Color(0xFFFF99AC);
  final Color accentPurple = const Color(0xFFFF99AC);
  final Color primaryWhite = Colors.black87;
  final Color textGrey = Colors.black54;

  @override
  void initState() {
    super.initState();
    sessionKey = widget.sessionKey;
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/listUsers?key=$sessionKey'));
      final data = jsonDecode(res.body);
      if (data['valid'] == true && data['authorized'] == true) {
        fullUserList = data['users'] ?? [];
        _filterAndPaginate();
      } else {
        _alert("Info", data['message'] ?? 'Gagal memuat user.');
      }
    } catch (_) {
      _alert("Error", "Gagal terhubung ke server.");
    }
    setState(() => isLoading = false);
  }

  void _filterAndPaginate() {
    setState(() {
      currentPage = 1;
      filteredList = fullUserList.where((u) => u['role'] == selectedRole).toList();
    });
  }

  List<dynamic> _getCurrentPageData() {
    final start = (currentPage - 1) * itemsPerPage;
    final end = (start + itemsPerPage);
    return filteredList.sublist(start, end > filteredList.length ? filteredList.length : end);
  }

  int get totalPages => (filteredList.length / itemsPerPage).ceil();

  Future<void> _deleteUser() async {
    final username = deleteController.text.trim();
    if (username.isEmpty) {
      _alert("Peringatan", "Masukkan username yang ingin dihapus.");
      return;
    }
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/deleteUser?key=$sessionKey&username=$username'));
      final data = jsonDecode(res.body);
      if (data['deleted'] == true) {
        _alert("Sukses", "User berhasil dihapus.");
        deleteController.clear();
        _fetchUsers();
      } else {
        _alert("Gagal", data['message'] ?? 'Gagal menghapus user.');
      }
    } catch (_) {
      _alert("Error", "Gagal menghubungi server.");
    }
    setState(() => isLoading = false);
  }

  Future<void> _createAccount() async {
    final u = createUsernameController.text.trim();
    final p = createPasswordController.text.trim();
    final d = createDayController.text.trim();
    if (u.isEmpty || p.isEmpty || d.isEmpty) {
      _alert("Peringatan", "Semua field wajib diisi.");
      return;
    }
    setState(() => isLoading = true);
    try {
      final url = Uri.parse('$apiBaseUrl/userAdd?key=$sessionKey&username=$u&password=$p&day=$d&role=$newUserRole');
      final res = await http.get(url);
      final data = jsonDecode(res.body);
      if (data['created'] == true) {
        _alert("Sukses", "Akun berhasil dibuat sebagai ${newUserRole.toUpperCase()}.");
        createUsernameController.clear();
        createPasswordController.clear();
        createDayController.clear();
        newUserRole = 'member';
        _fetchUsers();
      } else {
        _alert("Gagal", data['message'] ?? 'Gagal membuat akun.');
      }
    } catch (_) {
      _alert("Error", "Gagal menghubungi server.");
    }
    setState(() => isLoading = false);
  }

  Future<void> _editUser() async {
    final u = editUsernameController.text.trim();
    final d = editDayController.text.trim();
    if (u.isEmpty || d.isEmpty) {
      _alert("Peringatan", "Semua field wajib diisi.");
      return;
    }
    setState(() => isLoading = true);
    try {
      final url = Uri.parse('$apiBaseUrl/editUser?key=$sessionKey&username=$u&addDays=$d');
      final res = await http.get(url);
      final data = jsonDecode(res.body);
      if (data['edited'] == true) {
        _alert("Sukses", "Durasi berhasil diperbarui.");
        editUsernameController.clear();
        editDayController.clear();
        _fetchUsers();
      } else {
        _alert("Gagal", data['message'] ?? 'Gagal mengubah durasi.');
      }
    } catch (_) {
      _alert("Error", "Gagal menghubungi server.");
    }
    setState(() => isLoading = false);
  }

  void _alert(String title, String message) {
    CustomPopup.show(
      context,
      title: title,
      message: message,
      icon: title.toLowerCase().contains("sukses") ? Icons.check_circle_outline : Icons.info_outline,
    );
  }

  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType type = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: type,
        style: TextStyle(color: primaryWhite),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: textGrey, fontSize: 13),
          prefixIcon: Icon(icon, color: accentPurple, size: 20),
          filled: true,
          fillColor: const Color(0xFFF8F9FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accentPurple, width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  void _showCreateAccountPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
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
                  border: Border.all(color: accentPurple.withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: accentPurple.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(FontAwesomeIcons.userPlus, color: accentPurple, size: 30),
                      ),
                      const SizedBox(height: 16),
                      Text("CREATE ACCOUNT", style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Orbitron')),
                      const SizedBox(height: 24),
                      _buildInput(label: "Username", controller: createUsernameController, icon: FontAwesomeIcons.user),
                      _buildInput(label: "Password", controller: createPasswordController, icon: FontAwesomeIcons.lock),
                      _buildInput(label: "Durasi (Hari)", controller: createDayController, icon: FontAwesomeIcons.calendarDay, type: TextInputType.number),
                      
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        margin: EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black.withOpacity(0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: newUserRole,
                            dropdownColor: const Color(0xFFF8F9FA),
                            style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.bold),
                            icon: Icon(Icons.keyboard_arrow_down, color: accentPurple),
                            items: roleOptions.map((role) {
                              return DropdownMenuItem(value: role, child: Text(role.toUpperCase()));
                            }).toList(),
                            onChanged: (val) => setModalState(() => newUserRole = val ?? 'member'),
                          ),
                        ),
                      ),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _createAccount();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentPurple,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text("CREATE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  void _showExtendDurationPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accentPurple.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(FontAwesomeIcons.clock, color: Colors.blue, size: 30),
                ),
                const SizedBox(height: 16),
                Text("ADD DURATION", style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Orbitron')),
                const SizedBox(height: 24),
                _buildInput(label: "Username Target", controller: editUsernameController, icon: FontAwesomeIcons.userEdit),
                _buildInput(label: "Tambah Hari", controller: editDayController, icon: FontAwesomeIcons.calendarPlus, type: TextInputType.number),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _editUser();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text("ADD DAYS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(FontAwesomeIcons.userSlash, color: Colors.redAccent, size: 30),
                ),
                const SizedBox(height: 16),
                Text("DELETE ACCOUNT", style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Orbitron')),
                const SizedBox(height: 24),
                _buildInput(label: "Username Target", controller: deleteController, icon: FontAwesomeIcons.user),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteUser();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopButton({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Orbitron'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserItem(Map user) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentPurple.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: accentPurple, size: 24),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['username'], style: TextStyle(color: primaryWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 4),
                Text("ROLE: ${user['role'].toString().toUpperCase()} | EXP: ${user['expiredDate']}", style: TextStyle(color: textGrey, fontSize: 12, fontFamily: 'ShareTechMono')),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {
              deleteController.text = user['username'];
              _showDeleteAccountPopup();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    if (totalPages <= 1) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: List.generate(totalPages, (index) {
        final page = index + 1;
        final isSelected = currentPage == page;
        return InkWell(
          onTap: () => setState(() => currentPage = page),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? accentPurple : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? accentPurple : Colors.black.withOpacity(0.1)),
            ),
            child: Text("$page", style: TextStyle(color: isSelected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: isLoading && fullUserList.isEmpty
            ? Center(child: CircularProgressIndicator(color: accentPurple))
            : SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Icon(Icons.workspace_premium, color: accentPurple, size: 36),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "OWNER PANEL",
                              style: TextStyle(color: primaryWhite, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Orbitron'),
                            ),
                            Text(
                              "Management Dashboard",
                              style: TextStyle(color: textGrey, fontSize: 13, fontFamily: 'ShareTechMono'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // 3 Buttons Row
                    Row(
                      children: [
                        _buildTopButton(title: "BUAT\nAKUN", icon: FontAwesomeIcons.userPlus, color: accentPurple, onTap: _showCreateAccountPopup),
                        const SizedBox(width: 12),
                        _buildTopButton(title: "ADD\nDURASI", icon: FontAwesomeIcons.clock, color: Colors.blue, onTap: _showExtendDurationPopup),
                        const SizedBox(width: 12),
                        _buildTopButton(title: "HAPUS\nAKUN", icon: FontAwesomeIcons.userSlash, color: Colors.redAccent, onTap: _showDeleteAccountPopup),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // User List Section
                    Text(
                      "USER DIRECTORY",
                      style: TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Orbitron', letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 16),
                    
                    // Role Filter Dropdown
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedRole,
                          dropdownColor: const Color(0xFFF8F9FA),
                          isExpanded: true,
                          style: TextStyle(color: primaryWhite, fontSize: 15, fontWeight: FontWeight.bold),
                          icon: Icon(Icons.keyboard_arrow_down, color: accentPurple),
                          items: roleOptions.map((role) {
                            return DropdownMenuItem(value: role, child: Text(role.toUpperCase()));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                selectedRole = val;
                                _filterAndPaginate();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (isLoading && fullUserList.isNotEmpty)
                      Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: accentPurple))),
                    
                    if (filteredList.isEmpty && !isLoading)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text("Belum ada user di kategori ini.", style: TextStyle(color: textGrey)),
                        ),
                      ),

                    ..._getCurrentPageData().map((u) => _buildUserItem(u)).toList(),
                    
                    const SizedBox(height: 20),
                    Center(child: _buildPagination()),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}