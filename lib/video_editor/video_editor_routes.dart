import 'package:sint/sint.dart';

import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'package:neom_core/ui/deferred_loader.dart';

import 'ui/video_editor_page.dart' deferred as vidEditor;

class VideoEditorRoutes {

  static final List<SintPage<dynamic>> routes = [
    SintPage(
      name: AppRouteConstants.videoEditor,
      page: () => DeferredLoader(vidEditor.loadLibrary, () => vidEditor.VideoEditorPage(file: null)), ///IMPROVE Page with Getx Controller
      transition: Transition.fade,
    ),
  ];

}
