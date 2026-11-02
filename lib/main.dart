import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FileDownloader().configureNotification(
    running: const TaskNotification('Virus Engine Active', 'Downloading {filename}'),
    complete: const TaskNotification('Download Finished', 'Saved to Gallery: {filename}'),
    error: const TaskNotification('Download Failed', 'Error saving {filename}'),
    progressBar: true,
  );
  runApp(const VirusDownloaderApp());
}

class VirusDownloaderApp extends StatelessWidget {
  const VirusDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virus All Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF05070B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF0D121D),
        ),
        textTheme: GoogleFonts.jetBrainsMonoTextTheme(ThemeData.dark().textTheme),
      ),
      home: const VirusHomeDashboard(),
    );
  }
}

class MediaMetadata {
  final String platform;
  final String id;
  final String title;
  final String author;
  final String resolution;
  final bool isWatermarked;
  final String videoUrl;
  final String proxyDownloadUrl;

  MediaMetadata({
    required this.platform,
    required this.id,
    required this.title,
    required this.author,
    required this.resolution,
    required this.isWatermarked,
    required this.videoUrl,
    required this.proxyDownloadUrl,
  });

  factory MediaMetadata.fromJson(Map<String, dynamic> json) {
    return MediaMetadata(
      platform: json['platform'] ?? 'unknown',
      id: json['id'] ?? '0',
      title: json['title'] ?? 'Untitled Stream',
      author: json['author'] ?? 'unknown',
      resolution: json['resolution'] ?? '1080x1920',
      isWatermarked: json['is_watermarked'] ?? false,
      videoUrl: json['video_url'] ?? '',
      proxyDownloadUrl: json['proxy_download_url'] ?? '',
    );
  }
}

class VirusHomeDashboard extends StatefulWidget {
  const VirusHomeDashboard({super.key});

  @override
  State<VirusHomeDashboard> createState() => _VirusHomeDashboardState();
}

class _VirusHomeDashboardState extends State<VirusHomeDashboard> {
  // Vercel backend (live): FastAPI + yt-dlp on Vercel serverless
  static const String _backendUrl = 'https://virus-all-downloader-backend-virus-4b61.vercel.app';

  final TextEditingController _tiktokController = TextEditingController();
  final TextEditingController _youtubeController = TextEditingController();
  final TextEditingController _fbController = TextEditingController();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: _backendUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  bool _isExtracting = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _consoleLog = 'SYSTEM ONLINE // READY FOR TARGET URL';

  MediaMetadata? _media;
  VideoPlayerController? _vidController;
  ChewieController? _chewieController;

  @override
  void dispose() {
    _cleanupPlayer();
    _tiktokController.dispose();
    _youtubeController.dispose();
    _fbController.dispose();
    super.dispose();
  }

  void _cleanupPlayer() {
    _chewieController?.dispose();
    _vidController?.dispose();
    _chewieController = null;
    _vidController = null;
  }

  Future<void> _extractStream(String targetUrl) async {
    targetUrl = targetUrl.trim();
    if (targetUrl.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isExtracting = true;
      _consoleLog = 'BYPASSING PLATFORM FILTERS & EXTRACTING 1080P...';
      _media = null;
    });
    _cleanupPlayer();

    try {
      final response = await _dio.post(
        '/api/v1/extract',
        data: {'url': targetUrl, 'prefer_codec': 'h264'},
      );

      final metadata = MediaMetadata.fromJson(response.data);

      final vCtrl = VideoPlayerController.networkUrl(Uri.parse(metadata.proxyDownloadUrl));
      await vCtrl.initialize();

      final cCtrl = ChewieController(
        videoPlayerController: vCtrl,
        autoPlay: true,
        looping: true,
        aspectRatio: vCtrl.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF00FF88),
          handleColor: const Color(0xFF00E5FF),
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
      );

      setState(() {
        _media = metadata;
        _vidController = vCtrl;
        _chewieController = cCtrl;
        _isExtracting = false;
        _consoleLog = 'STREAM SECURED // RESOLUTION: ${metadata.resolution}';
      });
    } on DioException catch (e) {
      setState(() {
        _isExtracting = false;
        _consoleLog = 'ERROR: ${e.response?.data?['detail'] ?? e.message}';
      });
    } catch (e) {
      setState(() {
        _isExtracting = false;
        _consoleLog = 'CRITICAL EXCEPTION: $e';
      });
    }
  }

  Future<void> _executeDownload() async {
    final item = _media;
    if (item == null || _isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _consoleLog = 'INITIALIZING BACKGROUND STREAM TRANSFER...';
    });

    final fileName = 'virus_${item.platform}_${item.id}.mp4';
    final task = DownloadTask(
      url: item.proxyDownloadUrl,
      filename: fileName,
      baseDirectory: BaseDirectory.temporary,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
    );

    final result = await FileDownloader().download(
      task,
      onProgress: (progress) {
        if (mounted && progress >= 0) {
          setState(() => _downloadProgress = progress);
        }
      },
    );

    if (result.status == TaskStatus.complete) {
      try {
        final filePath = await task.filePath();
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) await Gal.requestAccess(toAlbum: true);

        await Gal.putVideo(filePath, album: 'VirusDownloader');

        final tmpFile = File(filePath);
        if (await tmpFile.exists()) await tmpFile.delete();

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _consoleLog = 'SUCCESS: SAVED TO GALLERY [ALBUM: VirusDownloader]';
          });
        }
      } catch (err) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _consoleLog = 'GALLERY ERROR: $err';
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _consoleLog = 'DOWNLOAD FAILED: ${result.status.name.toUpperCase()}';
        });
      }
    }
  }

  Future<void> _pasteFromClipboard(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      controller.text = data.text!.trim();
      await _extractStream(controller.text);
    }
  }

  // One download box per platform: TikTok / YouTube / Facebook.
  Widget _platformBox({
    required String label,
    required Color accent,
    required Color buttonTextColor,
    required TextEditingController controller,
    required String hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D121D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              const Text(
                'VIDEO DOWNLOAD',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) {
                    if (!_isExtracting) _extractStream(controller.text);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Auto-Paste',
                icon: Icon(Icons.paste_rounded, color: accent),
                onPressed: _isExtracting ? null : () => _pasteFromClipboard(controller),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: buttonTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _isExtracting ? null : () => _extractStream(controller.text),
                child: _isExtracting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: buttonTextColor),
                      )
                    : const Text('EXTRACT', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Color(0xFF00FF88),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'VIRUS // ALL DOWNLOADER',
              style: TextStyle(
                color: Color(0xFF00FF88),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                fontSize: 15,
              ),
            ),
          ],
        ),
        actions: const [
          Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text(
                'NO-ADS • PRO',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // TikTok download box
              _platformBox(
                label: 'TIKTOK',
                accent: const Color(0xFF00E5FF),
                buttonTextColor: Colors.black,
                controller: _tiktokController,
                hint: 'Paste TikTok link...',
              ),

              const SizedBox(height: 12),

              // YouTube download box
              _platformBox(
                label: 'YOUTUBE',
                accent: const Color(0xFFFF0033),
                buttonTextColor: Colors.white,
                controller: _youtubeController,
                hint: 'Paste YouTube link...',
              ),

              const SizedBox(height: 12),

              // Facebook download box
              _platformBox(
                label: 'FACEBOOK',
                accent: const Color(0xFF1877F2),
                buttonTextColor: Colors.white,
                controller: _fbController,
                hint: 'Paste Facebook link...',
              ),

              const SizedBox(height: 12),

              // Console Terminal Status
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF090D14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  '> $_consoleLog',
                  style: const TextStyle(color: Color(0xFF00FF88), fontSize: 11),
                ),
              ),

              const SizedBox(height: 16),

              // Video Preview Card + 1-Click Action Button
              if (_media != null && _chewieController != null) ...[
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D121D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '@${_media!.author}',
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FF88).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_media!.platform.toUpperCase()} • ${_media!.resolution} • CLEAN HD',
                              style: const TextStyle(
                                color: Color(0xFF00FF88),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _media!.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 12),

                      // Interactive Live Preview Player
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: _vidController!.value.aspectRatio,
                          child: Chewie(controller: _chewieController!),
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_isDownloading) ...[
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.white10,
                          color: const Color(0xFF00FF88),
                          minHeight: 6,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'DOWNLOADING: ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 1-Click Save Button
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF88),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 22),
                          label: Text(
                            _isDownloading
                                ? 'SAVING TO GALLERY...'
                                : '1-CLICK DOWNLOAD FULL HD (${_media!.resolution})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          onPressed: _isDownloading ? null : _executeDownload,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
