import 'video_craft_exporter_native.dart'
    if (dart.library.js_interop) 'video_craft_exporter_web.dart'
    as platform;
import 'video_craft_trim_exporter.dart';

VideoCraftTrimExporter createVideoCraftTrimExporter() =>
    platform.createPlatformVideoCraftExporter();
