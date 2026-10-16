import 'dart:typed_data';
import 'package:neom_craft_libs/neom_craft_libs.dart';

/// Source bytes or a URI; no account, upload service or document backend needed.
class VideoCraftSource {
  VideoCraftSource.bytes(
    Uint8List bytes, {
    this.name = 'video.mp4',
    this.frameRate,
  }) : bytes = Uint8List.fromList(bytes),
       uri = null;
  VideoCraftSource.uri(Uri uri, {String? name, this.frameRate})
    : uri = uri,
      bytes = null,
      name = name ?? uri.pathSegments.lastOrNull ?? 'video';
  final Uint8List? bytes;
  final Uri? uri;
  final String name;

  /// Supply the media rate if known. Otherwise the timeline starts at 30fps.
  final CraftFrameRate? frameRate;
}
