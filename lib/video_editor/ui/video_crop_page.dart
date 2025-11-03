import 'package:flutter/material.dart';
import 'package:fraction/fraction.dart';
import 'package:get/get.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/ui/theme/app_theme.dart';
import 'package:neom_commons/ui/widgets/appbar_child.dart';
import 'package:neom_commons/utils/constants/translations/app_translation_constants.dart';
import 'package:video_editor/video_editor.dart';

import '../utils/constants/video_editor_translation_constants.dart';

class VideoCropPage extends StatelessWidget {
  const VideoCropPage({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.main50,
      appBar: AppBarChild(title: VideoEditorTranslationConstants.clipEditor.tr),
      body: Container(
        decoration: AppTheme.appBoxDecoration,
        child: Column(
          children: [
            Expanded(
              child: CropGridViewer.edit(
                controller: controller,
                rotateCropArea: false,
                margin: EdgeInsets.zero,
              )
            ),
            const SizedBox(height: 10),
            Divider(),
            AppTheme.heightSpace20,
            AnimatedBuilder(
              animation: controller,
              builder: (_, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildCropAspectButtons(),
                  const SizedBox(height: 10),
                  buildCropSizeButtons(context),
                  const SizedBox(height: 10),
                  buildFooterButtons(context)
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Row buildCropSizeButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        /// _buildCropButton(context, null),
        _buildCropButton(context, 1.toFraction()),
        _buildCropButton(context, Fraction.fromString("9/16")),
        _buildCropButton(context, Fraction.fromString("3/4")),
      ],
    );
  }

  Row buildCropAspectButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconAction(
          Icons.rotate_left,
          onTap: () => controller.rotate90Degrees(RotateDirection.left),
        ),
        const SizedBox(width: 10),
        _iconAction(
          controller.preferredCropAspectRatio != null &&
              controller.preferredCropAspectRatio! < 1
              ? Icons.panorama_vertical_select_rounded
              : Icons.panorama_vertical_rounded,
          onTap: () => controller.preferredCropAspectRatio =
              controller.preferredCropAspectRatio
                  ?.toFraction().inverse().toDouble(),
        ),
        const SizedBox(width: 10),
        _iconAction(
          controller.preferredCropAspectRatio != null &&
              controller.preferredCropAspectRatio! > 1
              ? Icons.panorama_horizontal_select_rounded
              : Icons.panorama_horizontal_rounded,
          onTap: () => controller.preferredCropAspectRatio =
              controller.preferredCropAspectRatio
                  ?.toFraction().inverse().toDouble(),),
        const SizedBox(width: 10),
        _iconAction(
          Icons.rotate_right,
          onTap: () => controller.rotate90Degrees(RotateDirection.right),
        ),
      ],
    );
  }

  Padding buildFooterButtons(BuildContext context) {
    return Padding(
                    padding: const EdgeInsets.only(left: 10, right: 10, bottom: 20),
                    child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        AppTranslationConstants.cancel.tr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: AppColor.bondiBlue,
                      ),
                      onPressed: () {
                        controller.applyCacheCrop();
                        Navigator.pop(context);
                      },
                      child: Text(
                        AppTranslationConstants.done.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                );
  }

  Widget _iconAction(IconData icon, {required VoidCallback onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColor.main75,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );

  Widget _buildCropButton(BuildContext context, Fraction? f) {
    bool selected = controller.preferredCropAspectRatio == f?.toDouble();
    String label = f == null
        ? AppTranslationConstants.loose.tr.capitalizeFirst
        : '${f.numerator}:${f.denominator}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        selectedColor: AppColor.bondiBlue,
        backgroundColor: AppColor.main75,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
        ),
        onSelected: (_) {
          controller.preferredCropAspectRatio = f?.toDouble();
          _adjustCropToMax();
          // controller.updateCropToAspectRatio(); // Esto ajusta automáticamente al máximo
        },
      ),
    );
  }

  void _adjustCropToMax() {
    final aspectRatio = controller.preferredCropAspectRatio;

    if (aspectRatio == null) return;

    final videoSize = controller.video.value.size;
    final videoWidth = videoSize.width;
    final videoHeight = videoSize.height;

    double newWidth, newHeight;

    if (videoWidth / videoHeight > aspectRatio) {
      newHeight = videoHeight;
      newWidth = newHeight * aspectRatio;
    } else {
      newWidth = videoWidth;
      newHeight = newWidth / aspectRatio;
    }

    final x = (videoWidth - newWidth) / 2;
    final y = (videoHeight - newHeight) / 2;

    final minOffset = Offset(x / videoWidth, y / videoHeight);
    final maxOffset = Offset((x + newWidth) / videoWidth, (y + newHeight) / videoHeight);

    controller.updateCrop(minOffset, maxOffset);
  }

}
