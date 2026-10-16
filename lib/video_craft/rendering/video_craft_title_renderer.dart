import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Shared layout for the preview and the transparent export overlay. All
/// distances scale with the video, independently of the device pixel ratio.
class VideoCraftTitlePainter extends CustomPainter {
  VideoCraftTitlePainter({required this.title});

  final String title;

  @override
  void paint(Canvas canvas, Size size) {
    if (title.trim().isEmpty || size.isEmpty) return;
    final unit = math.min(size.width, size.height);
    final padding = unit * .02;
    final text = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: Colors.white,
          fontSize: unit * .08,
          fontWeight: FontWeight.bold,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 3,
      ellipsis: '…',
    );
    try {
      text.layout(maxWidth: size.width * .8);
      final origin = Offset(
        (size.width - text.width) / 2,
        size.height * .92 - padding - text.height,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx - padding,
          origin.dy - padding,
          text.width + padding * 2,
          text.height + padding * 2,
        ),
        Paint()..color = Colors.black54,
      );
      text.paint(canvas, origin);
    } finally {
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(VideoCraftTitlePainter oldDelegate) =>
      title != oldDelegate.title;
}

/// The opacity animation is applied by the exporter at each source timestamp,
/// rather than baked into this reusable, full-size transparent PNG.
Future<Uint8List> renderVideoCraftTitle(
  String title, {
  required int width,
  required int height,
}) async {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Title canvas dimensions must be positive.');
  }
  final recorder = ui.PictureRecorder();
  VideoCraftTitlePainter(
    title: title,
  ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not render the video title.');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
