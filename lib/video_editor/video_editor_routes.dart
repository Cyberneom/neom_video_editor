import 'dart:io';

import 'package:neom_core/ui/deferred_loader.dart';
import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'package:sint/sint.dart';

import 'ui/video_editor_page.dart' deferred as vidEditor;

class VideoEditorRoutes {

  /// Callers (`MediaUploadController`) navigate here with the picked video as
  /// `arguments: [File(...)]`. The page takes the file through its constructor,
  /// so the route has to unwrap the arguments — passing `null` opened the
  /// editor with no video loaded.
  ///
  /// `dart:io` here is deliberate: the editor is IO-only, which is why hosts
  /// mount these routes behind a `!kIsWeb` guard.
  static File? _fileFromArguments() {
    final args = Sint.arguments;
    if (args is File) return args;
    if (args is List && args.isNotEmpty && args.first is File) {
      return args.first as File;
    }
    return null;
  }

  static final List<SintPage<dynamic>> routes = [
    SintPage(
      name: AppRouteConstants.videoEditor,
      page: () {
        final file = _fileFromArguments();
        return DeferredLoader(vidEditor.loadLibrary,
            () => vidEditor.VideoEditorPage(file: file));
      },
      transition: Transition.fade,
    ),
  ];

}
