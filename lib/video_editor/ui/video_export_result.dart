import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fraction/fraction.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';

Future<void> _getImageDimension(
  File file, {
  required void Function(Size) onResult,
}) async {
  if (!file.existsSync()) return;
  final decodedImage = await decodeImageFromList(file.readAsBytesSync());
  try {
    onResult(
      Size(decodedImage.width.toDouble(), decodedImage.height.toDouble()),
    );
  } finally {
    decodedImage.dispose();
  }
}

String _fileMBSize(File file) {
  if (!file.existsSync()) return ' 0.0 MB';
  return ' ${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _safeAspectRatioFraction(double ratio) {
  if (!ratio.isFinite || ratio <= 0) return '0';
  try {
    return Fraction.fromDouble(ratio).reduce().toString();
  } catch (_) {
    return ratio.toStringAsFixed(2);
  }
}

class VideoResultPopup extends StatefulWidget {
  const VideoResultPopup({super.key, required this.video});

  final File video;

  @override
  State<VideoResultPopup> createState() => _VideoResultPopupState();
}

class _VideoResultPopupState extends State<VideoResultPopup> {
  VideoPlayerController? _controller;
  FileImage? _fileImage;
  Size _fileDimension = Size.zero;
  late final bool _isGif =
      path.extension(widget.video.path).toLowerCase() == ".gif";
  late String _fileMbSize;

  @override
  void initState() {
    super.initState();
    if (_isGif) {
      _getImageDimension(
        widget.video,
        onResult: (d) {
          if (mounted) setState(() => _fileDimension = d);
        },
      );
    } else {
      _controller = VideoPlayerController.file(widget.video);
      _controller?.initialize().then((_) {
        if (!mounted) return;
        _fileDimension = _controller?.value.size ?? Size.zero;
        setState(() {});
        _controller?.play();
        _controller?.setLooping(true);
      });
    }
    _fileMbSize = _fileMBSize(widget.video);
  }

  @override
  void dispose() {
    if (_isGif) {
      _fileImage?.evict();
    } else {
      _controller?.pause();
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _fileDimension.aspectRatio;
    final safeRatio = ratio.isFinite && ratio > 0 ? ratio : 1.0;
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Center(
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: [
            AspectRatio(
              aspectRatio: safeRatio,
              child: _isGif
                  ? Image.file(widget.video)
                  : (_controller != null
                        ? VideoPlayer(_controller!)
                        : const SizedBox.shrink()),
            ),
            Positioned(
              bottom: 0,
              child: FileDescription(
                description: {
                  'Video path': widget.video.path,
                  if (!_isGif)
                    'Video duration':
                        '${((_controller?.value.duration.inMilliseconds ?? 0) / 1000).toStringAsFixed(2)}s',
                  'Video ratio': _safeAspectRatioFraction(ratio),
                  'Video dimension': _fileDimension.toString(),
                  'Video size': _fileMbSize,
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoverResultPopup extends StatefulWidget {
  const CoverResultPopup({super.key, required this.cover});

  final File cover;

  @override
  State<CoverResultPopup> createState() => _CoverResultPopupState();
}

class _CoverResultPopupState extends State<CoverResultPopup> {
  late final Uint8List _imagebytes = widget.cover.existsSync()
      ? widget.cover.readAsBytesSync()
      : Uint8List(0);
  Size? _fileDimension;
  late String _fileMbSize;

  @override
  void initState() {
    super.initState();
    _getImageDimension(
      widget.cover,
      onResult: (d) {
        if (mounted) setState(() => _fileDimension = d);
      },
    );
    _fileMbSize = _fileMBSize(widget.cover);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Center(
        child: Stack(
          children: [
            if (_imagebytes.isNotEmpty) Image.memory(_imagebytes),
            Positioned(
              bottom: 0,
              child: FileDescription(
                description: {
                  'Cover path': widget.cover.path,
                  'Cover ratio': _safeAspectRatioFraction(
                    _fileDimension?.aspectRatio ?? 0,
                  ),
                  'Cover dimension': _fileDimension.toString(),
                  'Cover size': _fileMbSize,
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FileDescription extends StatelessWidget {
  const FileDescription({super.key, required this.description});

  final Map<String, String> description;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontSize: 11),
      child: Container(
        width: math.max(0.0, MediaQuery.of(context).size.width - 60),
        padding: const EdgeInsets.all(10),
        color: Colors.black.withValues(alpha: 0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: description.entries
              .map(
                (entry) => Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${entry.key}: ',
                        style: const TextStyle(fontSize: 11),
                      ),
                      TextSpan(
                        text: entry.value,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
