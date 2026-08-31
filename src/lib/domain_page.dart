import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class DomainOsintPage extends StatefulWidget {
  const DomainOsintPage({super.key});

  @override
  State<DomainOsintPage> createState() => _DomainOsintPageState();
}

class _DomainOsintPageState extends State<DomainOsintPage> {
  final TextEditingController _domainController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _dnsData;
  List<dynamic>? _subdomainsData;
  String? _errorMessage;

  // --- Konstanta Warna Tema (UBAHAN: TEMA HITAM PUTIH) ---
  final Color primaryDark = const Color(0xFFCED4DA);
  final Color primaryWhite = Colors.black87;
  // Menggunakan warna putih
  final Color accentPurple = const Color(0xFFFF99AC);
  // Warna kartu abu-abu gelap
  final Color cardDark = const Color(0xFFF8F9FA);

  Future<void> _checkDomain() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      setState(() {
        _errorMessage = "Domain tidak boleh kosong.";
        _dnsData = null;
        _subdomainsData = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _dnsData = null;
      _subdomainsData = null;
    });

    try {
      // Call both APIs simultaneously
      final dnsResult = await _fetchDnsInfo(domain);
      final subdoResult = await _fetchSubdomains(domain);

      if (dnsResult != null && subdoResult != null) {
        setState(() {
          _dnsData = dnsResult;
          _subdomainsData = subdoResult;
        });
      } else {
        setState(() {
          _errorMessage = "Gagal mengambil data domain.";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Terjadi kesalahan: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchDnsInfo(String domain) async {
    final url = Uri.parse("https://api.siputzx.my.id/api/tools/dns?domain=$domain");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['status'] == true ? json['data'] : null;
    }
    return null;
  }

  Future<List<dynamic>?> _fetchSubdomains(String domain) async {
    final url = Uri.parse("https://api.siputzx.my.id/api/tools/subdomains?domain=$domain");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['status'] == true ? json['data'] : null;
    }
    return null;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label disalin ke clipboard'),
        backgroundColor: cardDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: accentPurple), // Ubah ke ungu
        ),
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentPurple.withOpacity(0.5), width: 1), // Ubah ke ungu
        boxShadow: [
          BoxShadow(
            color: accentPurple.withOpacity(0.2), // Ubah ke ungu
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryDark,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: accentPurple, size: 20), // Ubah ke ungu
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: primaryWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
            ),
          ),
          // Category Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String? value,
    bool showCopyButton = false,
  }) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryWhite.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: primaryWhite.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: primaryWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (showCopyButton)
            IconButton(
              icon: Icon(Icons.copy, color: accentPurple, size: 20), // Ubah ke ungu
              onPressed: () => _copyToClipboard(value, label),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40),
              tooltip: 'Salin $label',
            ),
        ],
      ),
    );
  }

  List<Widget> _buildDnsRecords() {
    if (_dnsData == null || _dnsData!['records'] == null) return [];

    final records = _dnsData!['records'] as Map<String, dynamic>;
    final widgets = <Widget>[];

    // NS Records
    if (records['ns']?['response']?['answer'] != null) {
      final nsRecords = records['ns']!['response']!['answer'] as List;
      if (nsRecords.isNotEmpty) {
        widgets.addAll([
          Text(
            'Name Servers',
            style: TextStyle(
              color: primaryWhite,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...nsRecords.map((record) => _buildInfoRow(
            label: 'NS Record',
            value: record['record']?['target']?.toString(),
            showCopyButton: true,
          )),
          const SizedBox(height: 16),
        ]);
      }
    }

    // SOA Record
    if (records['soa']?['response']?['answer'] != null) {
      final soaRecords = records['soa']!['response']!['answer'] as List;
      if (soaRecords.isNotEmpty) {
        final soa = soaRecords.first['record'];
        widgets.addAll([
          Text(
            'SOA Record',
            style: TextStyle(
              color: primaryWhite,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            label: 'Primary NS',
            value: soa?['host']?.toString(),
            showCopyButton: true,
          ),
          _buildInfoRow(
            label: 'Admin Email',
            value: soa?['admin']?.toString(),
            showCopyButton: true,
          ),
          _buildInfoRow(
            label: 'Serial',
            value: soa?['serial']?.toString(),
          ),
          _buildInfoRow(
            label: 'Refresh',
            value: soa?['refresh']?.toString(),
          ),
          _buildInfoRow(
            label: 'Retry',
            value: soa?['retry']?.toString(),
          ),
          _buildInfoRow(
            label: 'Expire',
            value: soa?['expire']?.toString(),
          ),
          _buildInfoRow(
            label: 'Minimum TTL',
            value: soa?['minimum']?.toString(),
          ),
          const SizedBox(height: 16),
        ]);
      }
    }

    // A Records (if any)
    if (records['a']?['response']?['answer'] != null) {
      final aRecords = records['a']!['response']!['answer'] as List;
      if (aRecords.isNotEmpty) {
        widgets.addAll([
          Text(
            'A Records',
            style: TextStyle(
              color: primaryWhite,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...aRecords.map((record) => _buildInfoRow(
            label: 'A Record',
            value: record['record']?['data']?.toString(),
            showCopyButton: true,
          )),
        ]);
      }
    }

    return widgets;
  }

  List<Widget> _buildSubdomainsList() {
    if (_subdomainsData == null) return [];

    // Clean and filter subdomains
    final cleanSubdomains = _subdomainsData!
        .map((item) => item.toString().split('\n').last.trim())
        .where((subdomain) => subdomain.isNotEmpty && !subdomain.startsWith('*'))
        .toSet() // Remove duplicates
        .toList()
      ..sort();

    return [
      Text(
        'Ditemukan ${cleanSubdomains.length} subdomain',
        style: TextStyle(
          color: primaryWhite.withOpacity(0.7),
          fontSize: 14,
        ),
      ),
      const SizedBox(height: 12),
      ...cleanSubdomains.map((subdomain) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: primaryDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryWhite.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.link, color: accentPurple, size: 16), // Ubah ke ungu
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                subdomain,
                style: TextStyle(
                  color: primaryWhite,
                  fontSize: 14,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.copy, color: accentPurple, size: 18), // Ubah ke ungu
              onPressed: () => _copyToClipboard(subdomain, 'Subdomain'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36),
              tooltip: 'Salin subdomain',
            ),
          ],
        ),
      )).toList(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryDark,
      appBar: AppBar(
        title: const Text(
          'DOMAIN OSINT',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: primaryDark,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Input Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentPurple.withOpacity(0.5)), // Ubah ke ungu
                  boxShadow: [
                    BoxShadow(
                      color: accentPurple.withOpacity(0.2), // Ubah ke ungu
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _domainController,
                      style: TextStyle(color: primaryWhite, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Masukkan Domain',
                        labelStyle: TextStyle(color: primaryWhite.withOpacity(0.7)),
                        hintText: 'Contoh: nullxteam.fun',
                        hintStyle: TextStyle(color: primaryWhite.withOpacity(0.4)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentPurple.withOpacity(0.5)), // Ubah ke ungu
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentPurple, width: 2), // Ubah ke ungu
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: primaryDark,
                        suffixIcon: _isLoading
                            ? Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: accentPurple, // Ubah ke ungu
                              strokeWidth: 2,
                            ),
                          ),
                        )
                            : null,
                      ),
                      onSubmitted: (_) => _checkDomain(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _checkDomain,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentPurple, // Ubah ke ungu
                          foregroundColor: primaryWhite,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isLoading ? Icons.hourglass_top : Icons.search, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _isLoading ? 'MEMPROSES...' : 'CEK DOMAIN',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Orbitron',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentPurple), // Ubah ke ungu
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: accentPurple), // Ubah ke ungu
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: primaryWhite, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Results Section
              if (_dnsData != null || _subdomainsData != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Domain Information
                        if (_dnsData != null)
                          _buildCategoryCard(
                            title: "INFORMASI DOMAIN",
                            icon: Icons.domain,
                            children: [
                              _buildInfoRow(
                                label: "Domain",
                                value: _dnsData!['unicodeDomain']?.toString(),
                                showCopyButton: true,
                              ),
                              _buildInfoRow(
                                label: "Punycode",
                                value: _dnsData!['punycodeDomain']?.toString(),
                                showCopyButton: true,
                              ),
                              ..._buildDnsRecords(),
                            ],
                          ),

                        const SizedBox(height: 16),

                        // Subdomains
                        if (_subdomainsData != null)
                          _buildCategoryCard(
                            title: "SUBDOMAINS",
                            icon: Icons.list,
                            children: _buildSubdomainsList(),
                          ),

                        const SizedBox(height: 16),

                        // Server Information
                        if (_dnsData != null && _dnsData!['records'] != null)
                          _buildCategoryCard(
                            title: "INFORMASI SERVER",
                            icon: Icons.dns,
                            children: [
                              if (_dnsData!['records']['a']?['query']?['server'] != null)
                                _buildInfoRow(
                                  label: "DNS Server",
                                  value: _dnsData!['records']['a']!['query']!['server']!['ip']?.toString(),
                                  showCopyButton: true,
                                ),
                              if (_dnsData!['records']['a']?['query']?['server']?['location'] != null)
                                _buildInfoRow(
                                  label: "Lokasi Server",
                                  value: "Lat: ${_dnsData!['records']['a']!['query']!['server']!['location']!['lat']}, Lon: ${_dnsData!['records']['a']!['query']!['server']!['location']!['lon']}",
                                ),
                            ],
                          ),
                      ],
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