//WAITING FOR LIBRARIES TO FIX SOME BUGS WHEN PROCESSING
// import 'dart:async';
// import 'dart:io';
// import 'package:neom_commons/core/utils/app_utilities.dart';
// import 'package:video_trimmer/video_trimmer.dart';
//
// class VideoExportService {
//   final Trimmer _trimmer = Trimmer();
//
//   // Future<String> trimMyVideo({required File videoFile,
//   //     required double startValue,
//   //     required double endValue,
//   //     // required String outputPath,
//   //     required String videoName}) async {
//   //   final Trimmer trimmer = Trimmer();
//   //
//   //   // Assuming you have a File instance of a video
//   //
//   //   String trimmedVideoPath = '';
//   //
//   //   try {
//   //     // Trim video from 2 seconds to 8 seconds
//   //     File trimmedVideo = await trimmer.trimVideo(
//   //       file: videoFile,
//   //       startMs: startValue.toInt(),  // 2 seconds
//   //       endMs: endValue.toInt(),    // 8 seconds
//   //     );
//   //
//   //     trimmedVideoPath = trimmedVideo.path;
//   //     print('Trimmed video saved to: ${trimmedVideo.path}');
//   //   } catch (e) {
//   //     print('Error trimming video: $e');
//   //   }
//   //
//   //   return trimmedVideoPath;
//   // }
//
//   Future<String> trimVideo({
//     required File videoFile,
//     required double startValue,
//     required double endValue,
//     // required String outputPath,
//     required String videoName,
//   }) async {
//
//     final Completer<String> completer = Completer();
//
//     try {
//       await _trimmer.loadVideo(videoFile: videoFile);
//
//       await _trimmer.saveTrimmedVideo(
//         startValue: startValue,
//         endValue: endValue,
//         videoFileName: videoName,
//         outputFormat: FileFormat.mp4,
//         onSave: (path) {
//           if (path != null) {
//             AppConfig.logger.d("✅ Video guardado en: $path");
//             completer.complete(path);
//           } else {
//             AppConfig.logger.e("⛔️ La ruta de guardado retornada es nula.");
//             completer.complete('');
//           }
//
//           // if(path != null) outputPath = path;
//           // AppConfig.logger.d("Video guardado en: $outputPath");
//         },
//       );
//
//       return completer.future;
//     } catch (e) {
//       AppConfig.logger.e("Error recortando el video: $e");
//       return '';
//     }
//   }
// }
