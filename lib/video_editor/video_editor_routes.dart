import 'package:sint/sint.dart';

import 'package:neom_core/utils/constants/app_route_constants.dart';

import 'ui/video_editor_page.dart';

class VideoEditorRoutes {

  static final List<SintPage<dynamic>> routes = [
    SintPage(
      name: AppRouteConstants.videoEditor,
      page: () => const VideoEditorPage(file: null), ///IMPROVE Page with Getx Controller
      transition: Transition.fade,
    ),
  ];

}
