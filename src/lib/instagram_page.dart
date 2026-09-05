import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class InstagramDownloaderPage extends StatefulWidget {
  const InstagramDownloaderPage({super.key});

  @override
  State<InstagramDownloaderPage> createState() => _InstagramDownloaderPageState();
}

class _InstagramDownloaderPageState extends State<InstagramDownloaderPage> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  List<dynamic>? _mediaData;
  String? _errorMessage;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  // --- Warna Tema Hitam Putih ---
  final Color primaryDark = const Color(0xFFCED4DA);
  final Color primaryPurple = const Color(0xFFFF99AC);
  final Color accentPurple = const Color(0xFFFF99AC);
  final Color lightPurple = Colors.black54;   // Light Gray highlight
  final Color primaryWhite = Colors.black87;
  final Color accentGrey = Colors.black54;
  final Color cardDark = const Color(0xFFF8F9FA); // Latar kartu dengan tint abu

  @override
  void dispose() {
    _urlController.dispose();
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _downloadInstagram() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = "URL Instagram tidak boleh kosong.";
        _mediaData = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _mediaData = null;
      _videoController?.dispose();
      _chewieController?.dispose();
    });

    final encodedUrl = Uri.encodeComponent(url);
    final apiUrl = Uri.parse("https://api.siputzx.my.id/api/d/igdl?url=$encodedUrl");

    try {
      final response = await http.get(apiUrl);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == true && json['data'] != null) {
          setState(() {
            _mediaData = json['data'];
          });
          _initializeVideoPlayer();
        } else {
          setState(() {
            _errorMessage = "Gagal mengambil data Instagram.";
          });
        }
      } else {
        setState(() {
          _errorMessage = "Gagal terhubung ke server.";
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

  void _initializeVideoPlayer() {
    if (_mediaData != null && _mediaData!.isNotEmpty) {
      final mediaUrl = _mediaData![0]['url'];
      _videoController = VideoPlayerController.networkUrl(Uri.parse(mediaUrl))
        ..initialize().then((_) {
          setState(() {
            _chewieController = ChewieController(
              videoPlayerController: _videoController!,
              autoPlay: true,
              looping: false,
              showControls: true,
              materialProgressColors: ChewieProgressColors(
                playedColor: primaryPurple, // Diubah ke ungu
                handleColor: lightPurple,   // Diubah ke ungu
                backgroundColor: accentGrey.withOpacity(0.3),
                bufferedColor: accentGrey.withOpacity(0.2),
              ),
            );
          });
        });
    }
  }

  Future<void> _shareVideo() async {
    if (_mediaData == null || _mediaData!.isEmpty) return;

    try {
      final mediaUrl = _mediaData![0]['url'];
      final response = await http.get(Uri.parse(mediaUrl));
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await file.writeAsBytes(response.bodyBytes);

      await Share.shareXFiles([XFile(file.path)],
        text: 'Video Instagram',
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

  Widget _buildMediaGrid() {
    if (_mediaData == null) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: _mediaData!.length,
      itemBuilder: (context, index) {
        final media = _mediaData![index];
        final isVideo = media['type'] == 'video';

        return GestureDetector(
          onTap: () {
            if (isVideo) {
              _playVideo(media['url']);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primaryPurple.withOpacity(0.3)), // Diubah ke ungu
              boxShadow: [
                BoxShadow(
                  color: primaryPurple.withOpacity(0.2), // Diubah ke ungu
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                    child: isVideo
                        ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          media['thumbnail'] ?? media['url'],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFCED4DA).withOpacity(0.5),
                            child: Icon(Icons.videocam, color: lightPurple), // Diubah ke ungu
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCED4DA).withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.play_arrow, color: primaryWhite, size: 16),
                          ),
                        ),
                      ],
                    )
                        : Image.network(
                      media['url'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFCED4DA).withOpacity(0.5),
                        child: Icon(Icons.photo, color: lightPurple), // Diubah ke ungu
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isVideo ? Icons.videocam : Icons.photo,
                        color: lightPurple, // Diubah ke ungu
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isVideo ? 'Video' : 'Photo',
                        style: TextStyle(
                          color: primaryWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _playVideo(String videoUrl) {
    _videoController?.dispose();
    _chewieController?.dispose();

    _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
      ..initialize().then((_) {
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoController!,
            autoPlay: true,
            looping: false,
            showControls: true,
            materialProgressColors: ChewieProgressColors(
              playedColor: primaryPurple, // Diubah ke ungu
              handleColor: lightPurple,   // Diubah ke ungu
              backgroundColor: accentGrey.withOpacity(0.3),
              bufferedColor: accentGrey.withOpacity(0.2),
            ),
          );
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryDark,
      appBar: AppBar(
        title: const Text(
          'INSTAGRAM DOWNLOADER',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: primaryDark,
        centerTitle: true,
        elevation: 0,
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
                  border: Border.all(color: primaryPurple.withOpacity(0.3)), // Diubah ke ungu
                  boxShadow: [
                    BoxShadow(
                      color: primaryPurple.withOpacity(0.2), // Diubah ke ungu
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _urlController,
                      style: TextStyle(color: primaryWhite, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Masukkan URL Instagram',
                        labelStyle: TextStyle(color: lightPurple), // Diubah ke ungu
                        hintText: 'Contoh: https://www.instagram.com/reel/xxx/',
                        hintStyle: TextStyle(color: accentGrey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: primaryPurple.withOpacity(0.5)), // Diubah ke ungu
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: lightPurple, width: 2), // Diubah ke ungu
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFCED4DA).withOpacity(0.3),
                        prefixIcon: Icon(Icons.camera_alt, color: lightPurple), // Diubah ke ungu
                        suffixIcon: _isLoading
                            ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Color(0xFFD500F9), // Warna ungu loading
                              strokeWidth: 2,
                            ),
                          ),
                        )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _downloadInstagram,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPurple, // Diubah ke ungu
                          foregroundColor: primaryWhite,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                          shadowColor: primaryPurple.withOpacity(0.5), // Diubah ke ungu
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isLoading ? Icons.hourglass_top : Icons.download, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _isLoading ? 'PROSES...' : 'DOWNLOAD',
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
                    color: Colors.purple.withOpacity(0.1), // Diubah ke ungu transparan
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)), // Diubah ke ungu
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: accentPurple), // Diubah ke ungu
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: accentPurple, fontSize: 14), // Diubah ke ungu
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Video Player (if video is selected)
              if (_chewieController != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardDark,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primaryPurple.withOpacity(0.3)), // Diubah ke ungu
                    boxShadow: [
                      BoxShadow(
                        color: primaryPurple.withOpacity(0.2), // Diubah ke ungu
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Video Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [primaryPurple, accentPurple], // Diubah ke ungu
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow, color: primaryWhite, size: 16),
                            SizedBox(width: 8),
                            Text(
                              "VIDEO PLAYER",
                              style: TextStyle(
                                color: primaryWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Orbitron',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primaryPurple.withOpacity(0.5)), // Diubah ke ungu
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: Chewie(controller: _chewieController!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _shareVideo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentPurple, // Diubah ke ungu
                            foregroundColor: primaryWhite,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            shadowColor: accentPurple.withOpacity(0.5), // Diubah ke ungu
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.share, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'SHARE VIDEO',
                                style: TextStyle(
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

              // Media Grid
              if (_mediaData != null && _chewieController == null)
                Expanded(
                  child: Column(
                    children: [
                      // Grid Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [primaryPurple, accentPurple], // Diubah ke ungu
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library, color: primaryWhite, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              "MEDIA GALLERY (${_mediaData!.length})",
                              style: TextStyle(
                                color: primaryWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Orbitron',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _buildMediaGrid(),
                      ),
                    ],
                  ),
                ),

              // Placeholder ketika belum ada media
              if (_mediaData == null && !_isLoading && _errorMessage == null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 80,
                          color: primaryPurple.withOpacity(0.3), // Diubah ke ungu
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Instagram Downloader',
                          style: TextStyle(
                            color: accentGrey,
                            fontSize: 18,
                            fontFamily: 'Orbitron',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Masukkan URL Instagram Reel, Post, atau Story untuk mendownload media',
                            style: TextStyle(
                              color: accentGrey,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
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