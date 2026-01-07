import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:just_audio/just_audio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';

class TrimScreen extends StatefulWidget {
  const TrimScreen({Key? key}) : super(key: key);

  @override
  State<TrimScreen> createState() => _TrimScreenState();
}

class _TrimScreenState extends State<TrimScreen> {
  String? _filePath;
  bool _isVideo = false;
  Duration _duration = Duration.zero;
  double _startPos = 0.0;
  double _endPos = 1.0;

  VideoPlayerController? _videoController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  final PlayerController _waveController = PlayerController();
  double _zoom = 1.0;

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // Request Android 13 media permissions if needed via native MethodChannel
    if (Platform.isAndroid) {
      try {
        final granted = await const MethodChannel(
          'com.example.mega_cut/permissions',
        ).invokeMethod<bool>('requestAndroid13Permissions');
        if (granted == null || granted == false) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Media permission is required to pick files'),
            ),
          );
          return;
        }
      } on PlatformException {
        // fallback to storage permission
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to pick files'),
            ),
          );
          return;
        }
      }

      // On Android 11+ it's preferable to request manage external storage when needed
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'mp4', 'mov', 'mkv'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    final ext = path.split('.').last.toLowerCase();
    final isVideo = ['mp4', 'mov', 'mkv', 'webm'].contains(ext);

    setState(() {
      _filePath = path;
      _isVideo = isVideo;
      _duration = Duration.zero;
      _startPos = 0.0;
      _endPos = 1.0;
    });

    if (isVideo) {
      _videoController?.dispose();
      _videoController = VideoPlayerController.file(File(path));
      await _videoController!.initialize();
      setState(() {
        _duration = _videoController!.value.duration;
      });
    } else {
      await _audioPlayer.setFilePath(path);
      final d = _audioPlayer.duration ?? Duration.zero;
      setState(() {
        _duration = d;
      });
      await _waveController.preparePlayer(path: path);
    }
  }

  Future<void> _trim() async {
    if (_filePath == null) return;
    final totalMs = _duration.inMilliseconds;
    final startMs = (_startPos * totalMs).round();
    final endMs = (_endPos * totalMs).round();

    final docs = await getTemporaryDirectory();
    final outPath =
        '${docs.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}${_isVideo ? '.mp4' : '.mp3'}';

    final startSec = (startMs / 1000.0);
    final durationSec = ((endMs - startMs) / 1000.0);

    final cmd = _isVideo
        ? "-y -i '$_filePath' -ss $startSec -t $durationSec -c copy '$outPath'"
        : "-y -i '$_filePath' -ss $startSec -t $durationSec -acodec copy '$outPath'";

    await FFmpegKit.executeAsync(cmd, (session) async {
      final returnCode = await session.getReturnCode();
      if (returnCode != null && returnCode.isValueSuccess()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Trim completed: $outPath')));
        await _offerSave(outPath);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trim failed')));
      }
    });
  }

  Future<void> _offerSave(String srcPath) async {
    if (!Platform.isAndroid) {
      await Share.shareXFiles([XFile(srcPath)]);
      return;
    }

    try {
      final filename = p.basename(srcPath);
      final downloads = '/storage/emulated/0/Download';
      final dest = '$downloads/$filename';
      final out = await File(srcPath).copy(dest);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to Downloads: ${out.path}')),
      );
    } catch (e) {
      // fallback to share
      await Share.shareXFiles([XFile(srcPath)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1;
    final startMs = (_startPos * totalMs).round();
    final endMs = (_endPos * totalMs).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Trim Media')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Pick audio or video'),
            ),
            const SizedBox(height: 12),
            if (_filePath == null)
              const Text('No file selected')
            else
              Text('File: ${_filePath!.split('/').last}'),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: _filePath == null
                    ? const Text('Waveform will appear here')
                    : _isVideo
                    ? _videoController != null &&
                              _videoController!.value.isInitialized
                          ? AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            )
                          : const CircularProgressIndicator()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final waveformWidth = constraints.maxWidth * _zoom;
                          return Column(
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Stack(
                                  children: [
                                    AudioFileWaveforms(
                                      size: Size(waveformWidth, 160),
                                      playerController: _waveController,
                                      enableSeekGesture: true,
                                    ),
                                    // selection handles overlay
                                    Positioned(
                                      top: 0,
                                      left: (_startPos * waveformWidth).clamp(
                                        0.0,
                                        waveformWidth - 8.0,
                                      ),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onHorizontalDragUpdate: (d) {
                                          setState(() {
                                            final rel =
                                                (d.globalPosition.dx - 16) /
                                                waveformWidth;
                                            _startPos = (_startPos + rel).clamp(
                                              0.0,
                                              _endPos,
                                            );
                                          });
                                        },
                                        child: Container(
                                          width: 8,
                                          height: 160,
                                          color: Colors.blueAccent.withOpacity(
                                            0.8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      left: (_endPos * waveformWidth - 8).clamp(
                                        0.0,
                                        waveformWidth - 8.0,
                                      ),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onHorizontalDragUpdate: (d) {
                                          setState(() {
                                            final rel =
                                                (d.globalPosition.dx - 16) /
                                                waveformWidth;
                                            _endPos = (_endPos + rel).clamp(
                                              _startPos,
                                              1.0,
                                            );
                                          });
                                        },
                                        child: Container(
                                          width: 8,
                                          height: 160,
                                          color: Colors.redAccent.withOpacity(
                                            0.8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Zoom'),
                                  Expanded(
                                    child: Slider(
                                      value: _zoom,
                                      min: 1.0,
                                      max: 5.0,
                                      divisions: 8,
                                      label: '${_zoom.toStringAsFixed(1)}x',
                                      onChanged: (v) =>
                                          setState(() => _zoom = v),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${Duration(milliseconds: startMs)} — ${Duration(milliseconds: endMs)}',
            ),
            RangeSlider(
              values: RangeValues(_startPos, _endPos),
              onChanged: (r) => setState(() {
                _startPos = r.start;
                _endPos = r.end;
              }),
              min: 0.0,
              max: 1.0,
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _trim,
                    icon: const Icon(Icons.cut),
                    label: const Text('Trim'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (_filePath == null) return;
                    if (_isVideo) {
                      if (_videoController == null) return;
                      if (_videoController!.value.isPlaying) {
                        _videoController!.pause();
                      } else {
                        _videoController!.play();
                      }
                      setState(() {});
                    } else {
                      if (_audioPlayer.playing) {
                        await _audioPlayer.pause();
                      } else {
                        await _audioPlayer.seek(
                          Duration(milliseconds: (_startPos * totalMs).round()),
                        );
                        await _audioPlayer.play();
                      }
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Preview'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
