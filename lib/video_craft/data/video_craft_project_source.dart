import 'dart:typed_data';

import '../domain/video_craft_project.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_project_source_stub.dart'
    if (dart.library.io) 'video_craft_project_source_io.dart'
    if (dart.library.js_interop) 'video_craft_project_source_web.dart'
    as platform;

/// Loads only the selected source, never references from the project header.
Future<Uint8List> readVideoCraftProjectSource(VideoCraftSource source) async {
  if (source.bytes case final bytes?) {
    if (bytes.isEmpty || bytes.length > VideoCraftProject.maxMediaBytes) {
      throw const FormatException(
        'Project media must be between 1 byte and 256 MiB.',
      );
    }
    return Uint8List.fromList(bytes);
  }
  return platform.readProjectUri(source.uri!, VideoCraftProject.maxMediaBytes);
}
