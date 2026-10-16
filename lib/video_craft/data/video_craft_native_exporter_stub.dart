import 'package:flutter/foundation.dart';

import '../domain/video_craft_recipe.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_export_control.dart';

/// Compatibility type for callers explicitly choosing the native backend.
/// Web clients should use createVideoCraftExporter() for the WebCodecs backend.
class ProVideoCraftTrimExporter implements VideoCraftControlledExporter {
  const ProVideoCraftTrimExporter();
  @override
  bool get isSupported => false;
  @override
  bool get includesAnimatedTitles => false;
  @override
  Future<Uint8List> exportTrim(
    VideoCraftSource source,
    VideoCraftRecipe recipe,
  ) => exportWithOptions(source, recipe);
  @override
  Future<Uint8List> exportWithOptions(
    VideoCraftSource source,
    VideoCraftRecipe recipe, {
    ValueChanged<double>? onProgress,
    VideoCraftExportCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    throw UnsupportedError('El exportador nativo no está disponible en web.');
  }
}
