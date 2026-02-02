//WAITING FOR LIBRARIES TO FIX SOME BUGS WHEN PROCESSING
// import 'package:flutter/material.dart';
// import 'package:sint/sint.dart';
// import 'package:neom_commons/core/utils/app_color.dart';
// import 'package:neom_commons/core/utils/constants/app_constants.dart';
// import 'package:neom_commons/core/utils/constants/app_page_id_constants.dart';
// import 'package:video_trimmer/video_trimmer.dart';
//
// import '../../../neom_posts.dart';
//
// class TrimmerView extends StatelessWidget {
//   const TrimmerView({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     return SintBuilder<PostUploadController>(
//       id: AppPageIdConstants.upload,
//       init: PostUploadController(),
//       builder: (_) => Obx(()=>Center(
//         child: Container(
//           color: Colors.black,
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: <Widget>[
//               Stack(
//                 alignment: Alignment.center,
//                 children: [
//                   VideoViewer(trimmer: _.trimmer.value),
//                   Center(
//                     child: Container(
//                       decoration: BoxDecoration(
//                         gradient: LinearGradient(
//                           colors: [
//                             const Color(0x36FFFFFF).withOpacity(0.1),
//                             const Color(0x0FFFFFFF).withOpacity(0.1),
//                           ],
//                           begin: FractionalOffset.topLeft,
//                           end: FractionalOffset.bottomRight,
//                         ),
//                         borderRadius: BorderRadius.circular(50),
//                       ),
//                       child: IconButton(
//                         icon: Icon(_.isPlaying.value ? Icons.pause : Icons.play_arrow),
//                         iconSize: 30,
//                         color: Colors.white70.withOpacity(0.5),
//                         onPressed: () async {
//                           await _.playPauseVideo();
//                         },
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//               Container(
//                 height: 50.0,
//                 width: MediaQuery.of(context).size.width,
//                 child: Obx(()=>TrimViewer(
//                   trimmer: _.trimmer.value,
//                   viewerHeight: 50.0,
//                   viewerWidth: MediaQuery.of(context).size.width,
//                   maxVideoLength: const Duration(seconds: AppConstants.maxVideoDurationInSeconds),
//                   onChangeStart: (value) => _.setTrimmedStart(value),
//                   onChangeEnd: (value) => _.setTrimmedEnd(value),
//                   onChangePlaybackState: (value) => _.setIsPlaying(value),
//                   durationTextStyle: TextStyle(fontSize: 12, color: AppColor.white),
//                 ),),
//               ),
//               ElevatedButton(
//                 onPressed: _.isUploading.value ? null : () async {
//                   await _.saveVideo();
//                 },
//                 child: Text("SAVE"),
//               ),
//             ],
//           ),
//         ),
//       ),),
//     );
//   }
// }
