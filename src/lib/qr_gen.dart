import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({super.key});

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  Uint8List? _qrImage;
  String? _errorMessage;

  // --- TEMA WARNA HITAM PUTIH ---
  final Color bgDark = const Color(0xFFCED4DA);     // Background Utama
  final Color cardDark = const Color(0xFFF8F9FA);    // Warna Kartu
  final Color primaryPurple = const Color(0xFFFF99AC);
  final Color accentPurple = const Color(0xFFFF99AC);
  final Color primaryWhite = Colors.black87;
  final Color textGrey = Colors.black54;

  Future<void> _generateQR() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = "Text tidak boleh kosong.";
        _qrImage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _qrImage = null;
    });

    final encodedText = Uri.encodeComponent(text);
    final url = Uri.parse("https://api.siputzx.my.id/api/tools/text2qr?text=$encodedText");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _qrImage = response.bodyBytes;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = "Gagal generate QR Code.";
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

  Future<void> _shareQR() async {
    if (_qrImage == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_code_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(_qrImage!);

      await Share.shareXFiles([XFile(file.path)],
        text: 'QR Code dari: ${_textController.text}',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing: $e', style: TextStyle(color: primaryWhite)),
          backgroundColor: primaryPurple, // Diubah ke ungu
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: Text(
          'QR GENERATOR',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontWeight: FontWeight.bold,
            color: primaryWhite,
          ),
        ),
        backgroundColor: bgDark,
        centerTitle: true,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryWhite),
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
                  border: Border.all(color: primaryPurple.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: primaryPurple.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _textController,
                      style: TextStyle(color: primaryWhite, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Masukkan Text/URL',
                        labelStyle: TextStyle(color: accentPurple),
                        hintText: 'Contoh: https://google.com',
                        hintStyle: TextStyle(color: textGrey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryPurple.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentPurple, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFCED4DA).withOpacity(0.3),
                        suffixIcon: _isLoading
                            ? Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: accentPurple,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                            : null,
                      ),
                      onSubmitted: (_) => _generateQR(),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _generateQR,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPurple,
                          foregroundColor: primaryWhite,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                          shadowColor: primaryPurple.withOpacity(0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isLoading ? Icons.hourglass_top : Icons.qr_code, size: 20, color: primaryWhite),
                            const SizedBox(width: 8),
                            Text(
                              _isLoading ? 'GENERATING...' : 'GENERATE QR',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Orbitron',
                                  color: primaryWhite
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
                    color: primaryPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryPurple.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: accentPurple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: accentPurple, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // QR Result
              if (_qrImage != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardDark,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: primaryPurple.withOpacity(0.3)),
                            boxShadow: [
                              BoxShadow(
                                color: primaryPurple.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // QR Code Container
                              Container(
                                padding: EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: primaryWhite,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: primaryPurple.withOpacity(0.5), width: 2),
                                ),
                                child: Image.memory(_qrImage!),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _shareQR,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentPurple,
                                    foregroundColor: primaryWhite,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 4,
                                    shadowColor: accentPurple.withOpacity(0.5),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.share, size: 20, color: primaryWhite),
                                      SizedBox(width: 8),
                                      Text(
                                        'SHARE QR CODE',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Orbitron',
                                            color: primaryWhite
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Info Text
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: primaryPurple.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: primaryPurple.withOpacity(0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: accentPurple, size: 16),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'QR Code berhasil digenerate!',
                                        style: TextStyle(
                                          color: accentPurple,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
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

              // Placeholder
              if (_qrImage == null && !_isLoading && _errorMessage == null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 80,
                          color: primaryPurple.withOpacity(0.3),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Generate QR Code',
                          style: TextStyle(
                            color: primaryWhite,
                            fontSize: 18,
                            fontFamily: 'Orbitron',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Masukkan text atau URL untuk membuat QR Code',
                          style: TextStyle(
                            color: textGrey,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
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