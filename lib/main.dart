import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

// LOOK ONLY: header, hero + orb, cards, buttons and background glows are
// ported from the GPT-6 starter's look. Everything else is unchanged:
// same backend, same extract/download logic, same live preview player,
// same gallery save, same icon. No bug fixes in this change.

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
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B14),
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF63E6FF),
          secondary: Color(0xFF9B7BFF),
          surface: Color(0xFF151B2A),
        ),
        useMaterial3: true,
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

// Starter look: static cyan/purple theme (no per-platform accents).
const Map<String, String> _platformLabels = {
  'tiktok': 'TIKTOK',
  'youtube': 'YOUTUBE',
  'facebook': 'FACEBOOK',
  'instagram': 'INSTAGRAM',
};

const Map<String, String> _platformHints = {
  'tiktok': 'Paste TikTok link...',
  'youtube': 'Paste YouTube link...',
  'facebook': 'Paste Facebook link...',
  'instagram': 'Paste Instagram link...',
};

const Map<String, IconData> _platformIcons = {
  'tiktok': Icons.music_note_rounded,
  'youtube': Icons.play_circle_fill_rounded,
  'facebook': Icons.facebook_rounded,
  'instagram': Icons.camera_alt_rounded,
};

class VirusHomeDashboard extends StatefulWidget {
  const VirusHomeDashboard({super.key});

  @override
  State<VirusHomeDashboard> createState() => _VirusHomeDashboardState();
}

class _VirusHomeDashboardState extends State<VirusHomeDashboard>
    with SingleTickerProviderStateMixin {
  // Vercel backend (live): FastAPI + yt-dlp on Vercel serverless
  static const String _backendUrl = 'https://virus-all-downloader-backend-virus-4b61.vercel.app';

  final TextEditingController _urlController = TextEditingController();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: _backendUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  late final AnimationController _orbController;
  String _selectedPlatform = 'tiktok';
  bool _isExtracting = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _consoleLog = 'SYSTEM ONLINE // READY FOR TARGET URL';

  MediaMetadata? _media;
  VideoPlayerController? _vidController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _orbController.dispose();
    _cleanupPlayer();
    _urlController.dispose();
    super.dispose();
  }

  void _cleanupPlayer() {
    _chewieController?.dispose();
    _vidController?.dispose();
    _chewieController = null;
    _vidController = null;
  }

  String? _detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('tiktok')) return 'tiktok';
    if (u.contains('youtu')) return 'youtube';
    if (u.contains('instagram')) return 'instagram';
    if (u.contains('facebook') || u.contains('fb.watch')) return 'facebook';
    return null;
  }

  Future<void> _extractStream(String targetUrl) async {
    targetUrl = targetUrl.trim();
    if (targetUrl.isEmpty || _isExtracting) return;

    final detected = _detectPlatform(targetUrl);
    FocusScope.of(context).unfocus();
    setState(() {
      _isExtracting = true;
      if (detected != null) _selectedPlatform = detected;
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
          playedColor: const Color(0xFF69E2FF),
          handleColor: const Color(0xFF63E6FF),
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
      );

      setState(() {
        _media = metadata;
        _vidController = vCtrl;
        _chewieController = cCtrl;
        _isExtracting = false;
        final p = metadata.platform.toLowerCase();
        if (_platformLabels.containsKey(p)) _selectedPlatform = p;
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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _urlController.text = data.text!.trim();
      await _extractStream(_urlController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B14),
      body: Stack(
        children: [
          const _BackgroundGlow(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 30),
                  _hero(),
                  const SizedBox(height: 26),
                  _platformPicker(),
                  const SizedBox(height: 18),
                  _inputCard(),
                  const SizedBox(height: 18),
                  _extractButton(),
                  const SizedBox(height: 12),
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
                  if (_media != null && _chewieController != null) _previewCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFF65E9FF), Color(0xFF9474FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF55CFFF).withOpacity(.25),
                blurRadius: 20,
              ),
            ],
          ),
          child: const Icon(Icons.bolt_rounded, color: Color(0xFF07101B), size: 27),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VIRUS', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2.2,
            )),
            Text('ALL DOWNLOADER', style: TextStyle(
              fontSize: 9, color: Color(0xFF8D9AB1), letterSpacing: 2.1,
            )),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.045),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(.08)),
          ),
          child: const Icon(Icons.tune_rounded, color: Color(0xFFB6C4D9), size: 19),
        ),
      ],
    );
  }

  Widget _hero() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Your video.', style: TextStyle(
                fontSize: 32, height: 1.05, fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
              )),
              Text('One tap away.', style: TextStyle(
                fontSize: 32, height: 1.12, fontWeight: FontWeight.w800,
                letterSpacing: -1.2, color: Color(0xFF6DE5FF),
              )),
              SizedBox(height: 10),
              Text('Paste a link. Preview it. Save it.',
                style: TextStyle(color: Color(0xFF98A5BB), fontSize: 13)),
            ],
          ),
        ),
        SizedBox(
          width: 105,
          height: 105,
          child: AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) => Transform.rotate(
              angle: _orbController.value * 6.28318,
              child: child,
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFF65E9FF), Color(0xFF8A78FF),
                    Color(0xFFFF79B7), Color(0xFF65E9FF),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7D76FF).withOpacity(.22),
                    blurRadius: 34, spreadRadius: 2,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFF293B59), Color(0xFF101728)],
                    ),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                    size: 48, color: Color(0xFFB5F5FF)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _platformPicker() {
    final choices = ['tiktok', 'youtube', 'facebook', 'instagram'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: choices.map((key) {
        final selected = key == _selectedPlatform;
        return GestureDetector(
          onTap: () => setState(() => _selectedPlatform = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? const Color(0xFF273B58)
                  : const Color(0xFF121A29),
              border: Border.all(
                color: selected
                    ? const Color(0xFF69DFFB).withOpacity(.7)
                    : Colors.white.withOpacity(.07),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_platformIcons[key], size: 15,
                color: selected ? const Color(0xFF75E8FF) : const Color(0xFF8B9AB2)),
              const SizedBox(width: 6),
              Text(_platformLabels[key]!, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF9AA8BD),
              )),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _inputCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF151D2D).withOpacity(.92),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0xFF8194B8).withOpacity(.17)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.22),
            blurRadius: 25, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VIDEO LINK', style: TextStyle(
            color: Color(0xFF8191AC), fontSize: 10,
            letterSpacing: 1.7, fontWeight: FontWeight.w700,
          )),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.link_rounded, color: Color(0xFF69DFFB)),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) {
                    if (!_isExtracting) _extractStream(_urlController.text);
                  },
                  decoration: InputDecoration(
                    hintText: _platformHints[_selectedPlatform],
                    hintStyle: const TextStyle(color: Color(0xFF68758D), fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: _isExtracting ? null : _pasteFromClipboard,
                child: const Text('PASTE', style: TextStyle(
                  color: Color(0xFF70E5FF), fontWeight: FontWeight.w800,
                  fontSize: 11,
                )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _extractButton() {
    return GestureDetector(
      onTap: _isExtracting ? null : () => _extractStream(_urlController.text),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: const LinearGradient(
            colors: [Color(0xFF65E8FF), Color(0xFF8B83FF), Color(0xFFBD79F5)],
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFF777BFF).withOpacity(.25),
              blurRadius: 22, offset: const Offset(0, 9)),
          ],
        ),
        child: Center(
          child: _isExtracting
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFF101626),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                      color: Color(0xFF101626), size: 19),
                    SizedBox(width: 9),
                    Text('EXTRACT', style: TextStyle(
                      color: Color(0xFF101626), fontWeight: FontWeight.w900,
                      letterSpacing: 1.4, fontSize: 13,
                    )),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _previewCard() {
    final media = _media!;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF141C2B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF7F8FB0).withOpacity(.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_rounded,
              color: Color(0xFF72E5B0), size: 17),
            const SizedBox(width: 7),
            const Text('VIDEO FOUND', style: TextStyle(
              color: Color(0xFF72E5B0), fontSize: 10,
              letterSpacing: 1.5, fontWeight: FontWeight.w800,
            )),
            const Spacer(),
            Text(media.platform.toUpperCase(), style: const TextStyle(
              color: Color(0xFF9AA8C0), fontSize: 10,
              letterSpacing: 1,
            )),
          ]),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: _vidController!.value.aspectRatio,
              child: Chewie(controller: _chewieController!),
            ),
          ),
          const SizedBox(height: 15),
          Text(media.title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (media.author.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text('@${media.author}', style: const TextStyle(
              color: Color(0xFF8998B0), fontSize: 12)),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _infoChip('Platform', media.platform.toUpperCase()),
            _infoChip('Resolution', media.resolution),
          ]),
          const SizedBox(height: 17),
          if (_isDownloading) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Downloading...', style: TextStyle(
                color: Color(0xFFB6C4D9), fontSize: 12)),
              Text('${(_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Color(0xFF6DE5FF),
                  fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 7,
                backgroundColor: const Color(0xFF2B3548),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF69E2FF)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isDownloading ? null : _executeDownload,
              icon: const Icon(Icons.download_rounded),
              label: Text(_isDownloading ? 'SAVING TO GALLERY...' : 'DOWNLOAD (${media.resolution})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF70E5FF),
                foregroundColor: const Color(0xFF09121F),
                disabledBackgroundColor: const Color(0xFF42536B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF202B3E),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text('$label: $value', style: const TextStyle(
        color: Color(0xFFB9C7DA), fontSize: 11)),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(children: [
        Positioned(
          top: -130, right: -110,
          child: Container(
            width: 300, height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF624DCE).withOpacity(.23),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        Positioned(
          top: 340, left: -170,
          child: Container(
            width: 320, height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF16BFD4).withOpacity(.12),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
