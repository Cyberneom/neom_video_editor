import 'dart:typed_data';

import '../domain/video_craft_recipe.dart';
import '../domain/video_craft_source.dart';

abstract class VideoCraftTrimExporter {
  bool get isSupported;
  Future<Uint8List> exportTrim(
    VideoCraftSource source,
    VideoCraftRecipe recipe,
  );
}
