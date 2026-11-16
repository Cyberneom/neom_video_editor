import 'dart:typed_data';
import 'package:neom_craft_libs/neom_craft_libs.dart';

/// Source bytes or a URI; no account, upload service or document backend needed.
class VideoCraftSource {
  static final RegExp _controlOrBidiChars = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u0085\u061C\u200B-\u200F\u2028-\u202E\u2060\u2066-\u2069\uFEFF]',
  );

  static String _sanitizeFallbackName(String? candidate) {
    if (candidate == null) return 'video';
    final cleaned = candidate.replaceAll(_controlOrBidiChars, '').trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'video';
    return cleaned.length > 255 ? cleaned.substring(0, 255) : cleaned;
  }

  VideoCraftSource.bytes(
    Uint8List bytes, {
    this.name = 'video.mp4',
    this.frameRate,
  }) : bytes = Uint8List.fromList(bytes),
       uri = null;
  VideoCraftSource.uri(Uri uri, {String? name, this.frameRate})
    : uri = uri,
      bytes = null,
      name = name ?? _sanitizeFallbackName(uri.pathSegments.lastOrNull);
  final Uint8List? bytes;
  final Uri? uri;
  final String name;

  /// Supply the media rate if known. Otherwise the timeline starts at 30fps.
  final CraftFrameRate? frameRate;
}
