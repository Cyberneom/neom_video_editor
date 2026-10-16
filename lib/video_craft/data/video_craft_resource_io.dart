import 'dart:io';
import 'package:video_player/video_player.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_resource.dart';

Future<VideoCraftResource> createVideoCraftResource(
  VideoCraftSource source,
) async {
  if (source.bytes != null) {
    final dir = await Directory.systemTemp.createTemp('neom-video-craft-');
    try {
      final extension =
          RegExp(
            r'\.(mp4|mov|webm|mkv|m4v|avi)$',
            caseSensitive: false,
          ).firstMatch(source.name)?.group(1) ??
          'mp4';
      final file = File('${dir.path}/preview.$extension');
      await file.writeAsBytes(source.bytes!, flush: true);
      return VideoCraftResource(VideoPlayerController.file(file), () async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }
  final uri = source.uri!;
  final player = uri.scheme == 'file'
      ? VideoPlayerController.file(File.fromUri(uri))
      : VideoPlayerController.networkUrl(uri);
  return VideoCraftResource(player, () async {});
}
