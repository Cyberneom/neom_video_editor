//WAITING FOR LIBRARIES TO FIX SOME BUGS WHEN PROCESSING
// import 'dart:io';
//
// // import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
// import 'package:flutter/material.dart';
// import 'package:sint/sint.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:neom_commons/neom_commons.dart';
// import 'package:video_editor/video_editor.dart';
//
// import '../../../../neom_posts.dart';
// import 'video_crop_page.dart';
// import 'video_export_service.dart';
//
// class StatefulVideoEditor extends StatefulWidget {
//   const StatefulVideoEditor({super.key, required this.file});
//
//   final File file;
//
//   @override
//   State<StatefulVideoEditor> createState() => _StatefulVideoEditorState();
// }
//
// class _StatefulVideoEditorState extends State<StatefulVideoEditor> {
//   final _exportingProgress = ValueNotifier<double>(0.0);
//   final _isExporting = ValueNotifier<bool>(false);
//   final double height = 60;
//
//   late final VideoEditorController _controller;
//   File editedVideo = File('');
//   int startTrim = 0;
//   int endTrim = 0;
//   double aspectRatio = 1;
//   bool hasCropChanges = false;
//   bool hasTrimChanges = false;
//   bool hadCropChanges = false;
//   bool hadTrimChanges = false;
//   int maxDurationInSeconds = 0;
//   PostUploadController? uploadController;
//
//   int totalSteps = 0;
//   int completedSteps = 0;
//
//   @override
//   void initState() {
//     super.initState();
//
//     final userController = Sint.find<UserService>();
//     maxDurationInSeconds = userServiceImpl.user.userRole == UserRole.subscriber
//         ? AppConstants.userMaxVideoDurationInSeconds : AppConstants.adminMaxVideoDurationInSeconds;
//
//     if(userServiceImpl.user.isVerified) {
//       maxDurationInSeconds = AppConstants.verifiedMaxVideoDurationInSeconds;
//     }
//
//     editedVideo = widget.file;
//
//     initializeVideoEditorController(editedVideo);
//
//     if (Sint.isRegistered<PostUploadController>()) {
//       uploadController = Sint.find<PostUploadController>();
//     } else {
//       uploadController = PostUploadController();
//       Sint.put(uploadController);
//     }
//   }
//
//   void initializeVideoEditorController(File file) {
//     _controller = VideoEditorController.file(
//         file,
//         minDuration: const Duration(seconds: 1),
//         maxDuration: Duration(seconds: maxDurationInSeconds),
//         trimStyle: TrimSliderStyle(
//           onTrimmedColor: AppColor.bondiBlue,
//           lineColor: AppColor.bondiBlue,
//           iconColor: AppColor.white
//         ),
//     );
//     _controller.initialize()
//         .then((_) {
//           _controller.video.play();
//           Size videoSize = _controller.video.value.size;
//           aspectRatio = videoSize.width / videoSize.height;
//           startTrim = _controller.startTrim.inMilliseconds;
//           endTrim = _controller.endTrim.inMilliseconds;
//           setState(() {});
//         }).catchError((error) {
//           // handle minumum duration bigger than video duration error
//       Navigator.pop(context);
//     }, test: (e) => e is VideoMinDurationError);
//   }
//
//   @override
//   void dispose() async {
//     _exportingProgress.dispose();
//     _isExporting.dispose();
//     _controller.dispose();
//     // ExportService.dispose();
//     super.dispose();
//   }
//
//   void processVideo() async {
//     AppConfig.logger.i('Processing video from path ${_controller.file.path}');
//     File processedVideo = _controller.file;
//
//     if(hasCropChanges && hadTrimChanges) {
//       hasTrimChanges = true;
//     } else if(hasTrimChanges && hadCropChanges) {
//       hasCropChanges = true;
//     } else {
//       processedVideo = File(editedVideo.path);
//     }
//
//
//     _isExporting.value = true;
//
//     _exportingProgress.value = 0;
//     totalSteps = (hasTrimChanges ? 3 : 0) + (hasCropChanges ? 3 : 0);
//     completedSteps = 0;
//
//     await _controller.video.pause();
//
//     String editedClipName = '${uploadController?.profile.name.split(' ').first.toLowerCase()}_gigclip_${DateTime.now().millisecondsSinceEpoch}';
//
//     if(hasTrimChanges) {
//       increaseProgressPercentage();
//
//
//       String trimmedVideoPath = await VideoExportService().trimVideo(
//         videoFile: processedVideo,
//         startValue: startTrim.toDouble(),
//         endValue: endTrim.toDouble(),
//         videoName: '${editedClipName}_trimmed',
//       );
//
//       increaseProgressPercentage();
//       AppConfig.logger.d("Ruta retornada por trimVideo: '$trimmedVideoPath'");
//       AppConfig.logger.d("Existe archivo?: ${File(trimmedVideoPath).existsSync()}");
//
//       if(trimmedVideoPath.isNotEmpty && File(trimmedVideoPath).existsSync()) {
//         processedVideo = File(trimmedVideoPath);
//         AppConfig.logger.i('Video recortado y exportado a ${processedVideo.path}');
//         hasTrimChanges = false;
//         hadTrimChanges = true;
//       } else {
//         AppConfig.logger.e("⛔ Error al exportar video (Trim)");
//         AppUtilities.showSnackBar(message: "Error al exportar el video :(");
//         _isExporting.value = false;
//         return;
//       }
//
//       increaseProgressPercentage();
//     }
//
//     if(hasCropChanges) {
//       increaseProgressPercentage();
//
//       final croppedController = VideoEditorController.file(
//         processedVideo,
//         maxDuration: Duration(seconds: maxDurationInSeconds),
//       );
//
//       await croppedController.initialize();
//
//       // Copia configuración de crop original al nuevo controller
//       croppedController.updateCrop(_controller.minCrop, _controller.maxCrop);
//       croppedController.preferredCropAspectRatio = _controller.preferredCropAspectRatio;
//
//       VideoFFmpegVideoEditorConfig config = VideoFFmpegVideoEditorConfig(croppedController,
//         name: '${editedClipName}_cropped', format: VideoExportFormat.mp4,
//       );
//
//       final FFmpegVideoEditorExecute executeConfig = await config.getExecuteConfig();
//
//       increaseProgressPercentage();
//       bool success = await executeFFmpegCommand(executeConfig);
//
//       croppedController.dispose();
//
//       if(success && executeConfig.outputPath.isNotEmpty && File(executeConfig.outputPath).existsSync()) {
//         AppConfig.logger.i("Tamaño de video ajustado y exportado correctamente en: ${executeConfig.outputPath}");
//         editedVideo = File(executeConfig.outputPath);
//         hasCropChanges = false;
//         hadCropChanges = true;
//       } else {
//         AppConfig.logger.e("⛔ Error al exportar video (Trim)");
//         AppUtilities.showSnackBar(message: "Error al exportar el video :(");
//         _isExporting.value = false;
//         return;
//       }
//       increaseProgressPercentage();
//     } else {
//       editedVideo = File(processedVideo.path);
//     }
//
//     _isExporting.value = false;
//
//     if (await editedVideo.exists() && (await editedVideo.length()) > 0) {
//       uploadController?.setProcessedVideo(XFile(editedVideo.path));
//     } else {
//       AppConfig.logger.e("⛔ Archivo exportado es inválido o vacío.");
//       AppUtilities.showSnackBar(message: "Hubo un error en la exportación.");
//     }
//   }
//
//   void increaseProgressPercentage() {
//     completedSteps++;
//     _exportingProgress.value = completedSteps / totalSteps;
//   }
//
//   Future<bool> executeFFmpegCommand(FFmpegVideoEditorExecute executeConfig) async {
//     final session = await FFmpegKit.execute(executeConfig.command);
//
//     final returnCode = await session.getReturnCode();
//     if (returnCode != null && returnCode.isValueSuccess()) {
//       AppConfig.logger.i('✅ Éxito! Video exportado en ${executeConfig.outputPath}');
//       return true;
//     } else {
//       final logs = await session.getAllLogs();
//       for (var log in logs) {
//         debugPrint(log.getMessage());
//       }
//       AppConfig.logger.e('⛔️ Error al exportar video.');
//       return false;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return WillPopScope(
//       onWillPop: () async {
//         return (await showDialog(
//           context: context,
//           builder: (context) => AlertDialog(
//             backgroundColor: AppColor.getMain(),
//             title: Text(AppConstants.appTitle.tr),
//             content:  Text(AppTranslationConstants.wantToCloseEditor.tr),
//             actions: <Widget>[
//               TextButton(
//                 child: Text(AppTranslationConstants.no.tr,
//                   style: const TextStyle(color: AppColor.white),
//                 ),
//                 onPressed: () => Navigator.of(context).pop(false),
//               ),
//               TextButton(
//                 child: Text(AppTranslationConstants.yes.tr,
//                   style: const TextStyle(color: AppColor.white),
//                 ),
//                 onPressed: () => Navigator.of(context).pop(true),
//               )
//             ],
//           ),
//         )) ?? false;
//       },
//       child: Scaffold(
//         backgroundColor: AppColor.main50,
//         appBar: AppBarChild(
//             title: (AppTranslationConstants.videoEditor.tr),
//             actionWidgets: getAppBarActions()),
//         body: _controller.initialized
//             ? Container(
//             height: AppTheme.fullHeight(context),
//             decoration: AppTheme.appBoxDecoration,
//             child: Column(
//               children: [
//                 SizedBox(
//                   height: AppTheme.fullHeight(context)/2,
//                   child: Stack(
//                     alignment: Alignment.center,
//                     children: [
//                       CropGridViewer.preview(controller: _controller),
//                       AnimatedBuilder(
//                         animation: _controller.video,
//                         builder: (_, __) => AnimatedOpacity(
//                           opacity: _controller.isPlaying ? 0 : 1,
//                           duration: kThemeAnimationDuration,
//                           child: Center(
//                             child: Container(
//                               decoration: BoxDecoration(
//                                   gradient: LinearGradient(
//                                       colors: [
//                                         const Color(0x36FFFFFF).withOpacity(0.1),
//                                         const Color(0x0FFFFFFF).withOpacity(0.1)
//                                       ],
//                                       begin: FractionalOffset.topLeft,
//                                       end: FractionalOffset.bottomRight
//                                   ),
//                                   borderRadius: BorderRadius.circular(50)
//                               ),
//                               child: IconButton(
//                                 icon: Icon(_controller.isPlaying ? Icons.pause : Icons.play_arrow,),
//                                 iconSize: 30,
//                                 color: Colors.white70.withOpacity(0.5),
//                                 onPressed: () => _controller.video.play(),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 Container(
//                   margin: const EdgeInsets.only(top: 10),
//                   child: Column(
//                     children: _trimSlider(),
//                   ),
//                 ),
//                 ValueListenableBuilder(
//                   valueListenable: _isExporting,
//                   builder: (_, bool export, Widget? child) =>
//                       AnimatedSize(
//                         duration: kThemeAnimationDuration,
//                         child: export ? child : null,
//                       ),
//                   child: AlertDialog(
//                     title: ValueListenableBuilder(
//                       valueListenable: _exportingProgress,
//                       builder: (_, double value, __)  {
//                         return TweenAnimationBuilder<double>(
//                           tween: Tween<double>(begin: 0.0, end: value),
//                           duration: const Duration(seconds: 1),
//                           builder: (context, animatedValue, child) {
//                             return Column(
//                               mainAxisSize: MainAxisSize.min,
//                               children: [
//                                 LinearProgressIndicator(
//                                   value: animatedValue,
//                                   backgroundColor: Colors.white30,
//                                   color: Colors.white,
//                                 ),
//                                 const SizedBox(height: 10),
//                                 Text(
//                                   '${AppTranslationConstants.processingVideo.tr} ${(animatedValue * 100).ceil()}%',
//                                   style: const TextStyle(fontSize: 14, color: Colors.white),
//                                 ),
//                               ],
//                             );
//                           },
//                         );
//                       }
//                     ),
//                     backgroundColor: AppColor.bondiBlue,
//                   ),
//                 )
//               ],
//             ),
//         ) : const Center(child: CircularProgressIndicator()),
//       ),
//     );
//   }
//
//   Widget getLeadingAction() {
//     return IconButton(
//       onPressed: () => Navigator.of(context).pop(),
//       icon: const Icon(Icons.close),
//       tooltip: AppTranslationConstants.leaveVideoEditor,
//     );
//   }
//
//   List<Widget> getAppBarActions() {
//     return [
//       Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//         IconButton(
//           onPressed: () {
//             hasCropChanges = true;
//             Navigator.push(context,
//               MaterialPageRoute<void>(
//                 builder: (context) => VideoCropPage(controller: _controller),
//               ),
//             );
//           },
//           icon: const Icon(Icons.crop),
//           tooltip: AppTranslationConstants.openCropPage.tr,
//         ),
//           IconButton(
//             onPressed: () async {
//               if(hasTrimChanges || hasCropChanges) {
//                 processVideo();
//               } else {
//                 uploadController?.setProcessedVideo(XFile(editedVideo.path));
//               }
//
//             },
//             icon: const Icon(Icons.arrow_forward),
//             tooltip: AppTranslationConstants.processVideo.tr,
//           ),
//       ],),
//
//     ];
//   }
//
//   List<Widget> _trimSlider() {
//     return [
//       AnimatedBuilder(
//         animation: Listenable.merge([
//           _controller,
//           _controller.video,
//         ]),
//         builder: (_, __) {
//           final int duration = _controller.videoDuration.inSeconds;
//           final double pos = _controller.trimPosition * duration;
//
//           if(startTrim != _controller.startTrim.inMilliseconds) {
//             startTrim = _controller.startTrim.inMilliseconds;
//             hasTrimChanges = true;
//           }
//
//           if(endTrim != _controller.endTrim.inMilliseconds) {
//             endTrim = _controller.endTrim.inMilliseconds;
//             hasTrimChanges = true;
//           }
//
//           return Container(
//             width: AppTheme.fullWidth(context),
//             padding: const EdgeInsets.symmetric(horizontal: 20),
//             child: Row(
//                 children: [
//                   Text('${AppUtilities.getDurationInMinutes(Duration(seconds: pos.toInt()).inMilliseconds)} / ${AppUtilities.getDurationInMinutes(endTrim)}',),
//                   const Expanded(child: SizedBox()),
//                   AnimatedOpacity(
//                     opacity: _controller.isTrimming ? 1 : 0,
//                     duration: kThemeAnimationDuration,
//                     child: Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Text(AppUtilities.getDurationInMinutes(endTrim-startTrim)),
//                         ]
//                     ),
//                   ),
//                 ]
//             ),
//           );
//         },
//       ),
//       Container(
//         width: AppTheme.fullWidth(context),
//         margin: const EdgeInsets.symmetric(vertical: 10),
//         child: TrimSlider(
//           controller: _controller,
//           horizontalMargin: 10,
//           child: TrimTimeline(
//             controller: _controller,
//             padding: const EdgeInsets.only(top: 10),
//           ),
//         ),
//       )
//     ];
//   }
// }
