// ZARR CHAT - klien HTTP ke backend (/api/...). Sesi memakai cookie "zc_sid" yang kita simpan sendiri.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;
  final bool network;
  ApiException(this.message, {this.status, this.code, this.network = false});

  @override
  String toString() => message;
}

/// Pesan ramah untuk error apa pun.
String errText(Object e) {
  if (e is ApiException) return e.message;
  if (e is TimeoutException) return 'Server tidak merespons. Periksa koneksi Anda.';
  return 'Terjadi kesalahan. Coba lagi.';
}

class Api {
  String? token;
  void Function()? onUnauthorized;
  final http.Client _client = http.Client();

  static final RegExp _cookieRe = RegExp(r'zc_sid=([^;,\s]+)');

  String abs(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$kBaseUrl$url';
  }

  /// Header untuk memuat media (gambar/video) yang butuh login.
  Map<String, String> get mediaHeaders => token == null ? <String, String>{} : {'Cookie': 'zc_sid=$token'};

  Map<String, String> get _headers => {
        'X-Requested-With': 'zarr-chat',
        'Accept': 'application/json',
        if (token != null) 'Cookie': 'zc_sid=$token',
      };

  Uri _uri(String path) => Uri.parse('$kBaseUrl/api$path');

  void _captureCookie(http.BaseResponse res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return;
    final m = _cookieRe.firstMatch(raw);
    if (m != null) token = m.group(1);
  }

  dynamic _decode(http.Response res) {
    if (res.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() run, {Duration timeout = const Duration(seconds: 20)}) async {
    http.Response res;
    try {
      res = await run().timeout(timeout);
    } on TimeoutException {
      throw ApiException('Server tidak merespons. Periksa koneksi internet Anda.', network: true);
    } on SocketException {
      throw ApiException('Tidak dapat terhubung ke server. Periksa koneksi internet Anda.', network: true);
    } on http.ClientException {
      throw ApiException('Tidak dapat terhubung ke server. Periksa koneksi internet Anda.', network: true);
    } on HandshakeException {
      throw ApiException('Koneksi aman ke server gagal.', network: true);
    }
    _captureCookie(res);
    final data = _decode(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final map = data is Map ? data : const {};
      final msg = (map['message'] ?? 'Terjadi kesalahan (kode ${res.statusCode}). Coba lagi.').toString();
      final code = map['error']?.toString();
      if (res.statusCode == 401 && code == 'unauthenticated') onUnauthorized?.call();
      throw ApiException(msg, status: res.statusCode, code: code);
    }
    return data;
  }

  Future<dynamic> get(String path) => _send(() => _client.get(_uri(path), headers: _headers));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send(() => _client.post(
        _uri(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body ?? <String, dynamic>{}),
      ));

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _send(() => _client.put(
        _uri(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body ?? <String, dynamic>{}),
      ));

  Future<dynamic> patch(String path, Map<String, dynamic> body) => _send(() => _client.patch(
        _uri(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ));

  Future<dynamic> delete(String path) => _send(() => _client.delete(_uri(path), headers: _headers));

  /// Unggah file ke /api/media. Mengembalikan id media di server.
  Future<int> upload(String filePath, String kind, {String? filename}) async {
    final name = filename ?? filePath.split(Platform.pathSeparator).last;
    final data = await _send(() async {
      final req = http.MultipartRequest('POST', _uri('/media'));
      req.headers.addAll(_headers);
      req.fields['kind'] = kind;
      req.files.add(await http.MultipartFile.fromPath('file', filePath, filename: name));
      final streamed = await _client.send(req);
      return http.Response.fromStream(streamed);
    }, timeout: const Duration(hours: 3)); // file besar (hingga 2 GB) butuh waktu lama di jaringan seluler
    final id = data is Map ? data['id'] : null;
    if (id is! int) throw ApiException('Unggahan gagal. Coba lagi.');
    return id;
  }

  /// Unduh file media (butuh login) langsung ke file [destPath] secara streaming.
  /// Hemat memori sehingga aman untuk file besar (hingga 2 GB).
  Future<void> downloadToFile(String url, String destPath) async {
    final tmp = File('$destPath.part');
    var ok = false;
    try {
      final req = http.Request('GET', Uri.parse(abs(url)));
      req.headers.addAll(mediaHeaders);
      final res = await _client.send(req).timeout(const Duration(minutes: 2));
      if (res.statusCode != 200) throw ApiException('File tidak dapat diunduh.', status: res.statusCode);
      await res.stream.pipe(tmp.openWrite()).timeout(const Duration(hours: 3));
      final dest = File(destPath);
      if (dest.existsSync()) dest.deleteSync();
      await tmp.rename(destPath);
      ok = true;
    } on TimeoutException {
      throw ApiException('Unduhan terlalu lama. Coba lagi.', network: true);
    } on SocketException {
      throw ApiException('Tidak dapat terhubung ke server.', network: true);
    } on http.ClientException {
      throw ApiException('Tidak dapat terhubung ke server.', network: true);
    } finally {
      if (!ok) {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Unduh file media (butuh login) sebagai byte.
  Future<List<int>> download(String url) async {
    try {
      final res = await _client.get(Uri.parse(abs(url)), headers: mediaHeaders).timeout(const Duration(minutes: 5));
      if (res.statusCode != 200) throw ApiException('File tidak dapat diunduh.', status: res.statusCode);
      return res.bodyBytes;
    } on TimeoutException {
      throw ApiException('Unduhan terlalu lama. Coba lagi.', network: true);
    } on SocketException {
      throw ApiException('Tidak dapat terhubung ke server.', network: true);
    } on http.ClientException {
      throw ApiException('Tidak dapat terhubung ke server.', network: true);
    }
  }
}
