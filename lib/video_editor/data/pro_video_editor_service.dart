import 'dart:typed_data';
import 'dart:ui';

import 'package:neom_core/app_config.dart';
import 'package:neom_core/utils/neom_error_logger.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

/// Service wrapper for pro_video_editor advanced features:
/// - Render with trim, merging, volume control
/// - Thumbnail generation
/// - Metadata extraction
class ProVideoEditorService {

  /// Render a video with trim and optional volume control.
  /// Returns the rendered video bytes.
  Future<Uint8List?> renderVideo({
    required String videoPath,
    Duration? startTime,
    Duration? endTime,
    double? volume,
  }) async {
    try {
      final segment = VideoSegment(
        video: EditorVideo.file(videoPath),
        startTime: startTime,
        endTime: endTime,
        volume: volume,
      );

      final data = VideoRenderData(
        videoSegments: [segment],
      );

      final result = await ProVideoEditor.instance.renderVideo(data);
      AppConfig.logger.i('Pro video render complete: ${result.length} bytes');
      return result;
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st,
          module: 'neom_video_editor', operation: 'renderVideo');
      return null;
    }
  }

  /// Render a video to a file path (recommended for large videos).
  Future<bool> renderVideoToFile({
    required String videoPath,
    required String outputPath,
    Duration? startTime,
    Duration? endTime,
    double? volume,
  }) async {
    try {
      final segment = VideoSegment(
        video: EditorVideo.file(videoPath),
        startTime: startTime,
        endTime: endTime,
        volume: volume,
      );

      final data = VideoRenderData(
        videoSegments: [segment],
      );

      await ProVideoEditor.instance.renderVideoToFile(outputPath, data);
      AppConfig.logger.i('Pro video rendered to file: $outputPath');
      return true;
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st,
          module: 'neom_video_editor', operation: 'renderVideoToFile');
      return false;
    }
  }

  /// Merge multiple video files into one.
  Future<Uint8List?> mergeVideos(List<String> videoPaths) async {
    try {
      final segments = videoPaths.map((path) => VideoSegment(
        video: EditorVideo.file(path),
      )).toList();

      final data = VideoRenderData(videoSegments: segments);
      final result = await ProVideoEditor.instance.renderVideo(data);
      AppConfig.logger.i('Videos merged: ${result.length} bytes');
      return result;
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st,
          module: 'neom_video_editor', operation: 'mergeVideos');
      return null;
    }
  }

  /// Generate a thumbnail from a video at a specific position.
  Future<Uint8List?> generateThumbnail(String videoPath, {
    Duration position = Duration.zero,
    Size outputSize = const Size(320, 240),
  }) async {
    try {
      final configs = ThumbnailConfigs(
        video: EditorVideo.file(videoPath),
        outputSize: outputSize,
        timestamps: [position],
      );

      final thumbnails = await ProVideoEditor.instance.getThumbnails(configs);
      if (thumbnails.isNotEmpty) {
        return thumbnails.first;
      }
      return null;
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st,
          module: 'neom_video_editor', operation: 'generateThumbnail');
      return null;
    }
  }

  /// Get video metadata (duration, resolution, etc.).
  Future<VideoMetadata?> getVideoMetadata(String videoPath) async {
    try {
      return await ProVideoEditor.instance.getMetadata(
        EditorVideo.file(videoPath),
      );
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st,
          module: 'neom_video_editor', operation: 'getVideoMetadata');
      return null;
    }
  }

  /// Listen to render progress updates.
  Stream<ProgressModel> get progressStream =>
      ProVideoEditor.instance.progressStream;
}
