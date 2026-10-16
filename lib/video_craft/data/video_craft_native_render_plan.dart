import 'package:pro_video_editor/pro_video_editor.dart';

import '../domain/video_craft_recipe.dart';

/// Converts source-frame keys into the trimmed output's frame grid. Endpoint
/// keys preserve interpolation from keys outside the selected trim interval.
class VideoCraftNativeRenderPlan {
  VideoCraftNativeRenderPlan(this.recipe) : opacityKeys = _trimKeys(recipe);

  final VideoCraftRecipe recipe;
  final List<LayerOpacityKeyframe> opacityKeys;
  // Native extractors truncate rational timestamps to microseconds. UI seek
  // rounds up instead; reusing that value excludes e.g. frame 25 at 24 fps.
  Duration _nativeTimeAtFrame(int frame) => Duration(
    microseconds:
        (BigInt.from(frame) *
                BigInt.from(1000000) *
                recipe.frameRate.denominator ~/
                recipe.frameRate.numerator)
            .toInt(),
  );
  Duration get startTime => _nativeTimeAtFrame(recipe.inFrame);
  Duration get endTime => _nativeTimeAtFrame(recipe.outFrame);
  Duration get duration => endTime - startTime;
  int get frameCount => recipe.outFrame - recipe.inFrame;

  LayerAnimation get opacityAnimation => LayerAnimation(
    type: LayerAnimationType.opacityKeys,
    phase: AnimationPhase.animateIn,
    duration: duration,
    opacityKeys: opacityKeys,
    frameRateNumerator: recipe.frameRate.numerator.toInt(),
    frameRateDenominator: recipe.frameRate.denominator.toInt(),
  );

  static List<LayerOpacityKeyframe> _trimKeys(VideoCraftRecipe recipe) {
    final lastFrame = recipe.outFrame - 1;
    final frames = <int>{
      recipe.inFrame,
      lastFrame,
      ...recipe.opacityKeys.keys.where(
        (frame) => frame >= recipe.inFrame && frame <= lastFrame,
      ),
    }.toList()..sort();
    return List.unmodifiable([
      for (final frame in frames)
        LayerOpacityKeyframe(frame - recipe.inFrame, recipe.opacityAt(frame)),
    ]);
  }
}
