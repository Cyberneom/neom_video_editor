import 'dart:io';

// import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:easy_video_editor/easy_video_editor.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/ui/theme/app_theme.dart';
import 'package:neom_commons/ui/widgets/appbar_child.dart';
import 'package:neom_commons/utils/app_utilities.dart';
import 'package:neom_commons/utils/constants/translations/app_translation_constants.dart';
import 'package:neom_commons/utils/constants/translations/common_translation_constants.dart';
import 'package:neom_commons/utils/datetime_utilities.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/domain/use_cases/media_upload_service.dart';
import 'package:neom_core/domain/use_cases/user_service.dart';
import 'package:neom_core/utils/constants/core_constants.dart';
import 'package:neom_core/utils/enums/user_role.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_editor/video_editor.dart';

import '../utils/constants/video_editor_translation_constants.dart';
import 'video_crop_page.dart';

class VideoEditorPage extends StatefulWidget {

  const VideoEditorPage({super.key, required this.file});
  final File? file;

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  final _exportingProgress = ValueNotifier<double>(0.0);
  final _isExporting = ValueNotifier<bool>(false);
  final double height = 60;

  final userServiceImpl = Get.find<UserService>();
  final mediaUploadServiceImpl = Get.find<MediaUploadService>();

  late final VideoEditorController _controller;

  File originalVideo = File('');
  File editedVideo = File('');
  int startTrim = 0;
  int endTrim = 0;
  double aspectRatio = 1;
  bool hasCropChanges = false;
  bool hasTrimChanges = false;
  bool hadCropChanges = false;
  bool hadTrimChanges = false;
  int maxDurationInSeconds = 0;

  int totalSteps = 0;
  int completedSteps = 0;

  @override
  void initState() {
    super.initState();


    maxDurationInSeconds = userServiceImpl.user.userRole == UserRole.subscriber
        ? CoreConstants.userMaxVideoDurationInSeconds : CoreConstants.adminMaxVideoDurationInSeconds;

    if(userServiceImpl.user.isVerified) {
      maxDurationInSeconds = CoreConstants.verifiedMaxVideoDurationInSeconds;
    }

    if(widget.file != null) {
      originalVideo = widget.file!;
      editedVideo = widget.file!;
      initializeVideoEditorController(editedVideo);
    }
  }

  void initializeVideoEditorController(File file) {
    _controller = VideoEditorController.file(
        file,
        minDuration: const Duration(seconds: 1),
        maxDuration: Duration(seconds: maxDurationInSeconds),
        trimStyle: TrimSliderStyle(
          onTrimmedColor: AppColor.bondiBlue,
          lineColor: AppColor.bondiBlue,
          iconColor: AppColor.white
        ),
    );
    _controller.initialize()
        .then((_) {
          _controller.video.play();
          Size videoSize = _controller.video.value.size;
          aspectRatio = videoSize.width / videoSize.height;
          startTrim = _controller.startTrim.inMilliseconds;
          endTrim = _controller.endTrim.inMilliseconds;
          setState(() {});
        }).catchError((error) {
          // handle minumum duration bigger than video duration error
      Navigator.pop(context);
    }, test: (e) => e is VideoMinDurationError);
  }

  @override
  void dispose() async {
    _exportingProgress.dispose();
    _isExporting.dispose();
    _controller.dispose();
    // ExportService.dispose();
    super.dispose();
  }

  Future<void> processVideo() async {
    AppConfig.logger.i('Processing video from path ${_controller.file.path}');

    File? processedVideo = _controller.file;
    String editedClipName = '${userServiceImpl.profile.name.split(' ').first.toLowerCase()}_${AppProperties.getClipName}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await _controller.video.pause();

      if(hasCropChanges && hadTrimChanges) {
        hasTrimChanges = true;
      } else if(hasTrimChanges && hadCropChanges) {
        hasCropChanges = true;
      } else {
        processedVideo = File(editedVideo.path);
      }

      _isExporting.value = true;
      _exportingProgress.value = 0;
      totalSteps = (hasTrimChanges ? 3 : 0) + (hasCropChanges ? 3 : 0);
      completedSteps = 0;

      final fixedRatio = getAspectRatioEnum(aspectRatio);

      if (hasTrimChanges && hasCropChanges) {
        increaseProgressPercentage();
        processedVideo = await trimAndCropVideoViaBuilder(
            originalVideo.path, editedClipName, startTrim, endTrim, fixedRatio
        );
        increaseProgressPercentage();
      } else if (hasTrimChanges) {
        increaseProgressPercentage();
        final Directory tempDir = await getTemporaryDirectory();
        String processedVideoPath = await VideoEditorBuilder(videoPath: originalVideo.path)
            .trim(startTimeMs: startTrim, endTimeMs: endTrim)
            .export(outputPath: '${tempDir.path}/${editedClipName}_trimmed.mp4') ?? '';
        processedVideo = File(processedVideoPath);
        increaseProgressPercentage();
      } else if (hasCropChanges) {
        increaseProgressPercentage();
        processedVideo = await cropVideoViaBuilder(
            processedVideo.path, editedClipName, fixedRatio
        );
        increaseProgressPercentage();
      }

      // if(hasTrimChanges) {
      //   increaseProgressPercentage();
      //   processedVideo = await trimVideo(originalVideo.path, editedClipName);
      //   increaseProgressPercentage();
      // }
      //
      // if(hasCropChanges && (processedVideo?.path.isNotEmpty ?? false)) {
      //   increaseProgressPercentage();
      //   processedVideo = await cropVideoViaBuilder(processedVideo?.path ?? '', editedClipName);
      //   increaseProgressPercentage();
      // }

      if(processedVideo != null) editedVideo = processedVideo;
      _isExporting.value = false;

      if (editedVideo.path.isNotEmpty) {
        mediaUploadServiceImpl.setProcessedVideo(editedVideo);
      } else {
        AppConfig.logger.e("⛔ Archivo exportado es inválido o vacío.");
        AppUtilities.showSnackBar(message: "Hubo un error en la exportación.");
      }
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }
  }

  void increaseProgressPercentage() {
    completedSteps++;
    _exportingProgress.value = completedSteps / totalSteps;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        return (await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColor.getMain(),
            title: Text(AppProperties.getAppName()),
            content:  Text(CommonTranslationConstants.wantToCloseEditor.tr),
            actions: <Widget>[
              TextButton(
                child: Text(AppTranslationConstants.no.tr,
                  style: const TextStyle(color: AppColor.white),
                ),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: Text(AppTranslationConstants.yes.tr,
                  style: const TextStyle(color: AppColor.white),
                ),
                onPressed: () => Navigator.of(context).pop(true),
              )
            ],
          ),
        )) ?? false;
      },
      child: Scaffold(
        backgroundColor: AppColor.main50,
        appBar: AppBarChild(
            title: (VideoEditorTranslationConstants.videoEditor.tr),
            actionWidgets: getAppBarActions()),
        body: _controller.initialized
            ? Container(
            height: AppTheme.fullHeight(context),
            decoration: AppTheme.appBoxDecoration,
            child: Column(
              children: [
                SizedBox(
                  height: AppTheme.fullHeight(context)/2,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CropGridViewer.preview(controller: _controller),
                      AnimatedBuilder(
                        animation: _controller.video,
                        builder: (_, __) => AnimatedOpacity(
                          opacity: _controller.isPlaying ? 0 : 1,
                          duration: kThemeAnimationDuration,
                          child: Center(
                            child: Container(
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [
                                        const Color(0x36FFFFFF).withOpacity(0.1),
                                        const Color(0x0FFFFFFF).withOpacity(0.1)
                                      ],
                                      begin: FractionalOffset.topLeft,
                                      end: FractionalOffset.bottomRight
                                  ),
                                  borderRadius: BorderRadius.circular(50)
                              ),
                              child: IconButton(
                                icon: Icon(_controller.isPlaying ? Icons.pause : Icons.play_arrow,),
                                iconSize: 30,
                                color: Colors.white70.withOpacity(0.5),
                                onPressed: () => _controller.video.play(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  child: Column(
                    children: _trimSlider(),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _isExporting,
                  builder: (_, bool export, Widget? child) =>
                      AnimatedSize(
                        duration: kThemeAnimationDuration,
                        child: export ? child : null,
                      ),
                  child: AlertDialog(
                    title: ValueListenableBuilder(
                      valueListenable: _exportingProgress,
                      builder: (_, double value, __)  {
                        return TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: value),
                          duration: const Duration(seconds: 1),
                          builder: (context, animatedValue, child) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LinearProgressIndicator(
                                  value: animatedValue,
                                  backgroundColor: Colors.white30,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${CommonTranslationConstants.processingVideo.tr} ${(animatedValue * 100).ceil()}%',
                                  style: const TextStyle(fontSize: 14, color: Colors.white),
                                ),
                              ],
                            );
                          },
                        );
                      }
                    ),
                    backgroundColor: AppColor.bondiBlue,
                  ),
                )
              ],
            ),
        ) : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget getLeadingAction() {
    return IconButton(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.close),
      tooltip: VideoEditorTranslationConstants.leaveVideoEditor,
    );
  }

  List<Widget> getAppBarActions() {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
        IconButton(
          onPressed: () {
            hasCropChanges = true;
            Navigator.push(context,
              MaterialPageRoute<void>(
                builder: (context) => VideoCropPage(controller: _controller),
              ),
            );
          },
          icon: const Icon(Icons.crop),
          tooltip: CommonTranslationConstants.openCropPage.tr,
        ),
          IconButton(
            onPressed: () async {
              if(hasTrimChanges || hasCropChanges) {
                processVideo();
              } else {
                if(editedVideo.existsSync()) {
                  mediaUploadServiceImpl.setProcessedVideo(editedVideo);
                } else {
                  mediaUploadServiceImpl.setProcessedVideo(originalVideo);
                }
              }
            },
            icon: const Icon(Icons.arrow_forward),
            tooltip: CommonTranslationConstants.processVideo.tr,
          ),
      ],),

    ];
  }

  List<Widget> _trimSlider() {
    return [
      AnimatedBuilder(
        animation: Listenable.merge([
          _controller,
          _controller.video,
        ]),
        builder: (_, __) {
          final int duration = _controller.videoDuration.inSeconds;
          final double pos = _controller.trimPosition * duration;

          if(startTrim != _controller.startTrim.inMilliseconds) {
            startTrim = _controller.startTrim.inMilliseconds;
            hasTrimChanges = true;
          }

          if(endTrim != _controller.endTrim.inMilliseconds) {
            endTrim = _controller.endTrim.inMilliseconds;
            hasTrimChanges = true;
          }

          return Container(
            width: AppTheme.fullWidth(context),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
                children: [
                  Text('${DateTimeUtilities.getDurationInMinutes(Duration(seconds: pos.toInt()).inMilliseconds)} / ${DateTimeUtilities.getDurationInMinutes(endTrim)}',),
                  const Expanded(child: SizedBox()),
                  AnimatedOpacity(
                    opacity: _controller.isTrimming ? 1 : 0,
                    duration: kThemeAnimationDuration,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateTimeUtilities.getDurationInMinutes(endTrim-startTrim)),
                        ]
                    ),
                  ),
                ]
            ),
          );
        },
      ),
      Container(
        width: AppTheme.fullWidth(context),
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: TrimSlider(
          controller: _controller,
          horizontalMargin: 10,
          child: TrimTimeline(
            controller: _controller,
            padding: const EdgeInsets.only(top: 10),
          ),
        ),
      )
    ];
  }

  VideoAspectRatio getAspectRatioEnum(double aspectRatio) {
    if ((aspectRatio - (16 / 9)).abs() < 0.1) {
      return VideoAspectRatio.ratio16x9;
    } else if ((aspectRatio - (4 / 3)).abs() < 0.1) {
      return VideoAspectRatio.ratio4x3;
    } else if ((aspectRatio - 1.0).abs() < 0.1) {
      return VideoAspectRatio.ratio1x1;
    } else if ((aspectRatio - (9 / 16)).abs() < 0.1) {
      return VideoAspectRatio.ratio9x16;
    } else if ((aspectRatio - (3 / 4)).abs() < 0.1) {
      return VideoAspectRatio.ratio3x4;
    } else {
      // Valor predeterminado en caso de no coincidir exactamente
      return VideoAspectRatio.ratio16x9;
    }
  }

  Future<File?> trimVideo(String videoPath, String videoName) async {
    String trimmedVideoPath = '';
    VideoAspectRatio videoAspectRatio =  getAspectRatioEnum(aspectRatio);
    final editor = VideoEditorBuilder(videoPath: videoPath)
        .trim(startTimeMs: startTrim, endTimeMs: endTrim)
        .crop(aspectRatio: videoAspectRatio);

    final Directory tempDir = await getTemporaryDirectory();

    trimmedVideoPath = await editor.export(
      outputPath: '${tempDir.path}/${videoName}_trimmed.mp4',
      onProgress: (progress) {
        // Progress ranges from 0.0 to 1.0 (0% to 100%)
        AppConfig.logger.d('Export progress: ${(progress * 100).toStringAsFixed(1)}%');
        // Update UI with progress information
        // e.g., setState(() => exportProgress = progress);
      },
    ) ?? '';

    AppConfig.logger.d("Ruta retornada por trimVideo: '$trimmedVideoPath'");
    AppConfig.logger.d("¿Existe archivo?: ${File(trimmedVideoPath).existsSync()}");

    if(trimmedVideoPath.isNotEmpty && File(trimmedVideoPath).existsSync()) {
      AppConfig.logger.i('Video recortado y exportado a $videoPath');
      hasTrimChanges = false;
      hadTrimChanges = true;
      return File(trimmedVideoPath);
    } else {
      AppConfig.logger.e("⛔ Error al exportar video (Trim)");
      AppUtilities.showSnackBar(message: "Error al exportar el video :(");
      _isExporting.value = false;
      return null;
    }
  }

  /// Recorta el video según el aspect ratio fijo
  Future<File?> cropVideoViaBuilder(
      String videoPath,
      String videoName,
      VideoAspectRatio fixedRatio,
      ) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/${videoName}_cropped.mp4';

    final builder = VideoEditorBuilder(videoPath: videoPath)
    // Sólo crop, sin volver a ffmpeg_kit
        .crop(aspectRatio: fixedRatio);

    final resultPath = await builder.export(
      outputPath: outputPath,
      // opcional: onProgress para barra de progreso
      onProgress: (p) => debugPrint('Crop progress ${(p * 100).ceil()}%'),
    );

    if (resultPath?.isNotEmpty == true && File(resultPath!).existsSync()) {
      return File(resultPath);
    } else {
      debugPrint('🚨 Error al exportar crop, path vacío o no existe');
      return null;
    }
  }
  /// Hace trim _y_ crop de una vez, si lo necesitas
  Future<File?> trimAndCropVideoViaBuilder(
      String videoPath,
      String videoName,
      int startMs,
      int endMs,
      VideoAspectRatio fixedRatio,
      ) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/${videoName}_trimmed_cropped.mp4';

    final builder = VideoEditorBuilder(videoPath: videoPath)
        .trim(startTimeMs: startMs, endTimeMs: endMs)
        .crop(aspectRatio: fixedRatio);

    final resultPath = await builder.export(
      outputPath: outputPath,
      onProgress: (p) => debugPrint('Trim+Crop progress ${(p * 100).ceil()}%'),
    );

    if (resultPath?.isNotEmpty == true && File(resultPath!).existsSync()) {
      return File(resultPath);
    } else {
      debugPrint('🚨 Error al exportar trim+crop');
      return null;
    }
  }

  // Future<File?> cropVideo(String videoPath, String videoName) async {
  //   final croppedController = VideoEditorController.file(
  //     File(videoPath),
  //     maxDuration: Duration(seconds: maxDurationInSeconds),
  //   );
  //
  //   await croppedController.initialize();
  //
  //   // Copia configuración de crop original al nuevo controller
  //   croppedController.updateCrop(_controller.minCrop, _controller.maxCrop);
  //   croppedController.preferredCropAspectRatio = _controller.preferredCropAspectRatio;
  //
  //   VideoFFmpegVideoEditorConfig config = VideoFFmpegVideoEditorConfig(
  //     croppedController,
  //     name: '${videoName}_cropped',
  //     format: VideoExportFormat.mp4,
  //   );
  //
  //   final FFmpegVideoEditorExecute executeConfig = await config.getExecuteConfig();
  //   // Run FFmpeg command to actually produce the file
  //   final session = await FFmpegKit.execute(executeConfig.command);
  //   final returnCode = await session.getReturnCode();
  //   croppedController.dispose();
  //
  //   if(ReturnCode.isSuccess(returnCode) && executeConfig.outputPath.isNotEmpty) {
  //     final outputFile = File(executeConfig.outputPath);
  //     if (await outputFile.exists()) {
  //       AppConfig.logger.i('Crop succeeded: ${outputFile.path}');
  //       hasCropChanges = false;
  //       hadCropChanges = true;
  //       return outputFile;
  //     } else {
  //       AppConfig.logger.e('Cropped file not found after ffmpeg execution: ${outputFile.path}');
  //     }
  //   } else {
  //     AppConfig.logger.e("⛔ Error al exportar video (Trim)");
  //     AppUtilities.showSnackBar(message: "Error al exportar el video :(");
  //     _isExporting.value = false;
  //     return null;
  //   }
  //
  // }

}
