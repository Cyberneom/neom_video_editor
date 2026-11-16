import 'dart:io';

import 'package:neom_core/ui/deferred_loader.dart';
import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'package:neom_core/utils/platform/core_io.dart' as core_io;
import 'package:sint/sint.dart';

import 'ui/video_editor_page.dart' deferred as vidEditor;

class VideoEditorRoutes {
  static Object? _safeRouteArguments() {
    try {
      return Sint.arguments;
    } catch (_) {
      return null;
    }
  }

  static File? _fileFromArguments() {
    final args = _safeRouteArguments();
    if (args is File) return args;
    if (args is core_io.File && args.path.isNotEmpty) return File(args.path);
    if (args is List && args.isNotEmpty) {
      final first = args.first;
      if (first is File) return first;
      if (first is core_io.File && first.path.isNotEmpty) {
        return File(first.path);
      }
    }
    return null;
  }

  static final List<SintPage<dynamic>> routes = [
    SintPage(
      name: AppRouteConstants.videoEditor,
      page: () {
        final file = _fileFromArguments();
        return DeferredLoader(
          vidEditor.loadLibrary,
          () => vidEditor.VideoEditorPage(file: file),
        );
      },
      transition: Transition.fade,
    ),
  ];
}
