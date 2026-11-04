import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:background_downloader/background_downloader.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

const String kBackendBaseUrl =
    'https://virus-all-downloader-backend-virus-4b61.vercel.app';
const String kExtractEndpoint = '$kBackendBaseUrl/api/v1/extract';
const String kGalleryAlbumName = 'VirusDownloader';
const String kAppVersion = 'v2.9 (1.0.8)';

void main() {
  // Note (Proof #6): Catches unhandled Dart async errors only;
  // does NOT intercept native Java/Kotlin/C++ crashes.
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exceptionAsString()}');
      };
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('PlatformDispatcher Error: $error\n$stack');
        return true;
      };
      runApp(const VirusAllDownloaderApp());
    },
    (Object error, StackTrace stack) {
      debugPrint('Zoned Error: $error\n$stack');
    },
  );
}

class VirusAllDownloaderApp extends StatelessWidget {
  const VirusAllDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virus All Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFF7B2CBF),
          surface: Color(0xFF121824),
          error: Color(0xFFFF4D6D),
        ),
        useMaterial3: true,
      ),
      home: const DownloaderHomeScreen(),
    );
  }
}

class ExtractedMedia {
  final String title;
  final String videoUrl;
  final String? thumbnailUrl;
  final String platform;
  final String? durationText;
  final Map<String, String> headers;

  const ExtractedMedia({
    required this.title,
    required this.videoUrl,
    required this.platform,
    this.thumbnailUrl,
    this.durationText,
    this.headers = const {},
  });

  factory ExtractedMedia.fromJson(Map<String, dynamic> raw, String sourceUrl) {
    final Map<String, dynamic> data = (raw['data'] is Map<String, dynamic>)
        ? raw['data'] as Map<String, dynamic>
        : (raw['result'] is Map<String, dynamic>)
            ? raw['result'] as Map<String, dynamic>
            : raw;
    String? resolvedUrl = _firstNonEmptyString(data, [
      'download_url',
      'video_url',
      'url',
      'direct_url',
      'play_url',
      'stream_url',
    ]);
    if ((resolvedUrl == null || resolvedUrl.isEmpty) && data['formats'] is List) {
      final List<dynamic> formats = data['formats'] as List<dynamic>;
      for (final item in formats.reversed) {
        if (item is Map<String, dynamic>) {
          final candidate = _firstNonEmptyString(item, ['url', 'download_url']);
          final vcodec = item['vcodec']?.toString() ?? '';
          if (candidate != null &&
              candidate.startsWith('http') &&
              vcodec != 'none') {
            resolvedUrl = candidate;
            break;
          }
        }
      }
    }
    if (resolvedUrl == null || !resolvedUrl.startsWith('http')) {
      throw const FormatException(
        'Backend response did not contain a valid direct video URL.',
      );
    }
    final Map<String, String> parsedHeaders = {};
    final dynamic rawHeaders = data['http_headers'] ?? data['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key != null && value != null) {
          parsedHeaders[key.toString()] = value.toString();
        }
      });
    }
    final String title = _firstNonEmptyString(data, [
          'title',
          'description',
          'caption',
        ]) ??
        'Virus_Video_${DateTime.now().millisecondsSinceEpoch}';
    final String? thumbnail = _firstNonEmptyString(data, [
      'thumbnail',
      'cover',
      'thumbnail_url',
      'origin_cover',
    ]);
    final String platform = _firstNonEmptyString(data, [
          'platform',
          'extractor',
          'extractor_key',
        ]) ??
        _detectPlatform(sourceUrl);
    String? durationText;
    final dynamic rawDuration = data['duration_string'] ?? data['duration'];
    if (rawDuration is String && rawDuration.trim().isNotEmpty) {
      durationText = rawDuration.trim();
    } else if (rawDuration is num && rawDuration > 0) {
      final int totalSeconds = rawDuration.round();
      final int mins = totalSeconds ~/ 60;
      final int secs = totalSeconds % 60;
      durationText = '$mins:${secs.toString().padLeft(2, '0')}';
    }
    return ExtractedMedia(
      title: title,
      videoUrl: resolvedUrl,
      thumbnailUrl: thumbnail,
      platform: platform.toUpperCase(),
      durationText: durationText,
      headers: parsedHeaders,
    );
  }

  static String? _firstNonEmptyString(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final val = map[key];
      if (val is String && val.trim().isNotEmpty) {
        return val.trim();
      }
    }
    return null;
  }

  static String _detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('tiktok.com')) return 'TIKTOK';
    if (lower.contains('facebook.com') || lower.contains('fb.watch')) {
      return 'FACEBOOK';
    }
    if (lower.contains('instagram.com')) return 'INSTAGRAM';
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return 'YOUTUBE';
    }
    return 'VIDEO';
  }
}

class DownloaderHomeScreen extends StatefulWidget {
  const DownloaderHomeScreen({super.key});

  @override
  State<DownloaderHomeScreen> createState() => _DownloaderHomeScreenState();
}

class _DownloaderHomeScreenState extends State<DownloaderHomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  late final AnimationController _ambientController;
  // Lazily created only when user triggers extraction or download
  Dio? _dio;
  bool _downloaderConfigured = false;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  ExtractedMedia? _extractedMedia;
  bool _isExtracting = false;
  bool _isInitializingPreview = false;
  String? _previewError;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = 'Paste a TikTok, Facebook, Instagram, or YouTube link';
  bool _isErrorStatus = false;

  @override
  void initState() {
    super.initState();
    // Restored 8-second repeating AnimationController (started after Frame 1 renders)
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ambientController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _disposeVideoPlayers();
    _urlController.dispose();
    _dio?.close();
    super.dispose();
  }

  Dio _getDio() {
    return _dio ??= Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 20),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  void _disposeVideoPlayers() {
    final chewie = _chewieController;
    final video = _videoController;
    _chewieController = null;
    _videoController = null;
    chewie?.dispose();
    video?.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final ClipboardData? data =
          await Clipboard.getData(Clipboard.kTextPlain);
      final String text = data?.text?.trim() ?? '';
      if (text.isNotEmpty && mounted) {
        setState(() {
          _urlController.text = text;
        });
      }
    } catch (e) {
      _setStatus('Clipboard access failed: $e', isError: true);
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _isErrorStatus = isError;
    });
  }

  bool _isSupportedUrl(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host.contains('tiktok.com') ||
        host.contains('facebook.com') ||
        host.contains('fb.watch') ||
        host.contains('fb.com') ||
        host.contains('instagram.com') ||
        host.contains('youtube.com') ||
        host.contains('youtu.be');
  }

  Future<void> _extractVideo() async {
    final String rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      _setStatus('Please enter a video link first.', isError: true);
      return;
    }
    if (!_isSupportedUrl(rawUrl)) {
      _setStatus(
        'Supported platforms: TikTok, Facebook, Instagram, YouTube.',
        isError: true,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _disposeVideoPlayers();
    setState(() {
      _isExtracting = true;
      _extractedMedia = null;
      _previewError = null;
      _downloadProgress = 0.0;
      _statusMessage = 'Extracting video via Virus Backend...';
      _isErrorStatus = false;
    });
    try {
      final response = await _getDio().post<Map<String, dynamic>>(
        kExtractEndpoint,
        data: {'url': rawUrl},
      );
      final Map<String, dynamic>? body = response.data;
      if (body == null) {
        throw const FormatException('Empty response from backend server.');
      }
      if (body['status'] == 'error' || body['error'] != null) {
        final errMsg =
            body['detail'] ?? body['error'] ?? body['message'] ?? 'Unknown error';
        throw Exception(errMsg.toString());
      }
      final media = ExtractedMedia.fromJson(body, rawUrl);
      if (!mounted) return;
      setState(() {
        _extractedMedia = media;
        _isExtracting = false;
        _statusMessage = 'Video extracted. Loading live preview...';
        _isErrorStatus = false;
      });
      await _initializePreviewPlayer(media);
    } on DioException catch (e) {
      String detail = e.message ?? 'Network request failed';
      if (e.response?.data is Map) {
        final map = e.response!.data as Map;
        detail = (map['detail'] ?? map['message'] ?? map['error'] ?? detail)
            .toString();
      }
      if (!mounted) return;
      setState(() {
        _isExtracting = false;
      });
      _setStatus('Extraction error: $detail', isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExtracting = false;
      });
      _setStatus('Extraction failed: $e', isError: true);
    }
  }

  Future<void> _initializePreviewPlayer(ExtractedMedia media) async {
    if (!mounted) return;
    setState(() {
      _isInitializingPreview = true;
      _previewError = null;
    });
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(media.videoUrl),
        httpHeaders: media.headers,
      );
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final double aspect = controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : (9 / 16);
      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        aspectRatio: aspect,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Preview unavailable ($errorMessage).\nYou can still download the video below.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          );
        },
      );
      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _isInitializingPreview = false;
        _statusMessage = 'Ready to preview & download.';
        _isErrorStatus = false;
      });
    } catch (e) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _isInitializingPreview = false;
        _previewError =
            'Live preview could not be initialized, but direct download is ready.';
        _statusMessage = 'Ready to download.';
        _isErrorStatus = false;
      });
    }
  }

  Future<void> _ensureDownloaderConfiguredLazy() async {
    if (_downloaderConfigured) return;
    try {
      final status = await FileDownloader().permissions.status(
            PermissionType.notifications,
          );
      if (status != PermissionStatus.granted) {
        await FileDownloader().permissions.request(
              PermissionType.notifications,
            );
      }
      FileDownloader().configureNotification(
        running: const TaskNotification(
          'Virus All Downloader',
          'Downloading {filename}',
        ),
        complete: const TaskNotification(
          'Download Complete',
          'Saved {filename} to VirusDownloader',
        ),
        error: const TaskNotification(
          'Download Failed',
          'Could not download {filename}',
        ),
        progressBar: true,
      );
      _downloaderConfigured = true;
    } catch (e) {
      debugPrint('Lazy notification config warning: $e');
    }
  }

  Future<void> _downloadAndSaveToGallery() async {
    final ExtractedMedia? media = _extractedMedia;
    if (media == null || _isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.01;
      _statusMessage = 'Preparing background download...';
      _isErrorStatus = false;
    });
    String? downloadedFilePath;
    try {
      await _ensureDownloaderConfiguredLazy();
      final String safeBase = media.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final String clippedBase =
          safeBase.length > 40 ? safeBase.substring(0, 40) : safeBase;
      final String filename =
          '${clippedBase.isEmpty ? "virus_video" : clippedBase}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final task = DownloadTask(
        url: media.videoUrl,
        filename: filename,
        headers: media.headers,
        directory: 'virus_downloads',
        baseDirectory: BaseDirectory.applicationDocuments,
        updates: Updates.statusAndProgress,
        allowPause: true,
      );
      final TaskStatusUpdate result = await FileDownloader().download(
        task,
        onProgress: (double progress) {
          if (!mounted) return;
          if (progress >= 0 && progress <= 1.0) {
            setState(() {
              _downloadProgress = progress;
              final pct = (progress * 100).toStringAsFixed(0);
              _statusMessage = 'Downloading in background... $pct%';
            });
          }
        },
        onStatus: (TaskStatus status) {
          if (!mounted) return;
          if (status == TaskStatus.running) {
            setState(() {
              _statusMessage = 'Downloading video...';
            });
          }
        },
      );
      if (result.status != TaskStatus.complete) {
        throw Exception(
          result.exception?.description ??
              'Download ended with status: ${result.status.name}',
        );
      }
      downloadedFilePath = await task.filePath();
      final File downloadedFile = File(downloadedFilePath);
      if (!await downloadedFile.exists() || await downloadedFile.length() == 0) {
        throw Exception('Downloaded file is missing or empty.');
      }
      _setStatus('Saving video to Gallery ($kGalleryAlbumName)...');
      bool hasGalAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasGalAccess) {
        hasGalAccess = await Gal.requestAccess(toAlbum: true);
      }
      if (!hasGalAccess) {
        throw Exception('Gallery permission denied.');
      }
      await Gal.putVideo(downloadedFilePath, album: kGalleryAlbumName);
      if (!mounted) return;
      setState(() {
        _downloadProgress = 1.0;
        _statusMessage =
            'Saved to Gallery album "$kGalleryAlbumName" successfully!';
        _isErrorStatus = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF00F5D4),
          content: Text(
            'Saved to Gallery (Album: VirusDownloader)',
            style: TextStyle(
              color: Color(0xFF080B12),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } catch (e) {
      _setStatus('Download/Save failed: $e', isError: true);
    } finally {
      if (downloadedFilePath != null) {
        try {
          final f = File(downloadedFilePath);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D121D),
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Color(0xFF00F5D4),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VIRUS ALL DOWNLOADER',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'TikTok • Facebook • Instagram • YouTube',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                kAppVersion,
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF00F5D4),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputCard(),
              const SizedBox(height: 14),
              _buildStatusBanner(),
              if (_extractedMedia != null) ...[
                const SizedBox(height: 16),
                _buildMediaPreviewCard(_extractedMedia!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return AnimatedBuilder(
      animation: _ambientController,
      builder: (context, child) {
        final Color borderGlow = Color.lerp(
          const Color(0xFF00F5D4).withValues(alpha: 0.35),
          const Color(0xFF7B2CBF).withValues(alpha: 0.55),
          _ambientController.value,
        )!;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121824),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderGlow, width: 1.2),
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Paste TikTok, FB, IG, or YouTube URL...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF080B12),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF00F5D4)),
              ),
              suffixIcon: IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                onPressed: () {
                  _urlController.clear();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _isExtracting ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _isExtracting ? null : _extractVideo,
                  icon: _isExtracting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF080B12),
                          ),
                        )
                      : const Icon(Icons.bolt_rounded, size: 20),
                  label: Text(
                    _isExtracting ? 'Extracting...' : 'Extract Video',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: const Color(0xFF080B12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final Color borderColor = _isErrorStatus
        ? const Color(0xFFFF4D6D).withValues(alpha: 0.5)
        : const Color(0xFF00F5D4).withValues(alpha: 0.3);
    final Color iconColor =
        _isErrorStatus ? const Color(0xFFFF4D6D) : const Color(0xFF00F5D4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121824),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            _isErrorStatus
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _isErrorStatus
                    ? const Color(0xFFFF8FA3)
                    : Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreviewCard(ExtractedMedia media) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121824),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  media.platform,
                  style: const TextStyle(
                    color: Color(0xFF00F5D4),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (media.durationText != null) ...[
                const SizedBox(width: 8),
                Text(
                  media.durationText!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            media.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 280,
              color: Colors.black,
              child: _buildPreviewContent(media),
            ),
          ),
          if (_previewError != null) ...[
            const SizedBox(height: 8),
            Text(
              _previewError!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          if (_isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _downloadProgress,
                minHeight: 8,
                backgroundColor: Colors.white10,
                color: const Color(0xFF00F5D4),
              ),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _isDownloading ? null : _downloadAndSaveToGallery,
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF080B12),
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 22),
            label: Text(
              _isDownloading
                  ? 'Downloading (${(_downloadProgress * 100).toStringAsFixed(0)}%)...'
                  : 'Download to Gallery (VirusDownloader)',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: const Color(0xFF080B12),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent(ExtractedMedia media) {
    if (_isInitializingPreview) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00F5D4)),
            SizedBox(height: 12),
            Text(
              'Initializing live video preview...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_chewieController != null &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    }
    if (media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty) {
      return Image.network(
        media.thumbnailUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.videocam_rounded, color: Colors.white38, size: 48),
        ),
      );
    }
    return const Center(
      child: Icon(Icons.videocam_rounded, color: Colors.white38, size: 48),
    );
  }
}
