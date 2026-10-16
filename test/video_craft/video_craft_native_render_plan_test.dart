import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';
import 'package:neom_video_editor/video_craft/data/video_craft_native_render_plan.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

VideoCraftRecipe recipe({
  int start = 24,
  int end = 120,
  Map<int, double> keys = const {0: 0, 48: 1, 144: 0},
}) => VideoCraftRecipe(
  sourceName: 'fixture.mp4',
  duration: const Duration(seconds: 8),
  frameRate: CraftFrameRate(24, 1),
  inFrame: start,
  outFrame: end,
  opacityKeys: keys,
);

void main() {
  test('trim shifts source keys and interpolates both boundary endpoints', () {
    final source = recipe();
    final plan = VideoCraftNativeRenderPlan(source);
    expect(plan.startTime, const Duration(seconds: 1));
    expect(plan.endTime, const Duration(seconds: 5));
    expect(plan.frameCount, 96);
    expect(plan.opacityKeys.map((e) => e.frame), [0, 24, 95]);
    expect(plan.opacityKeys.first.opacity, .5);
    expect(plan.opacityKeys[1].opacity, 1);
    expect(plan.opacityKeys.last.opacity, closeTo(25 / 96, 1e-10));
    // Compare the actual serialized plugin curve at every exported frame,
    // including a changing direction and keys before/after the selection.
    final native = LayerAnimation.fromMap(plan.opacityAnimation.toMap());
    for (var frame = 0; frame < plan.frameCount; frame++) {
      final rightIndex = native.opacityKeys.indexWhere(
        (key) => key.frame >= frame,
      );
      final right = native.opacityKeys[rightIndex];
      final left = native.opacityKeys[rightIndex == 0 ? 0 : rightIndex - 1];
      final value = left.frame == right.frame
          ? right.opacity
          : left.opacity +
                (right.opacity - left.opacity) *
                    (frame - left.frame) /
                    (right.frame - left.frame);
      expect(value, closeTo(source.opacityAt(frame + source.inFrame), 1e-10));
    }
  });
  test('one-frame trim produces one valid constant key', () {
    final plan = VideoCraftNativeRenderPlan(recipe(start: 48, end: 49));
    expect(plan.opacityKeys, [const LayerOpacityKeyframe(0, 1)]);
    expect(plan.opacityAnimation.toMap()['opacityKeys'], [
      {'frame': 0, 'opacity': 1.0},
    ]);
  });
  test(
    'native timestamps retain boundary frames truncated by the extractor',
    () {
      final plan = VideoCraftNativeRenderPlan(recipe(start: 25, end: 119));
      expect(plan.startTime.inMicroseconds, 1041666);
      expect(plan.endTime.inMicroseconds, 4958333);
      expect(plan.duration.inMicroseconds, 3916667);
      expect(plan.frameCount, 94);
      // UI seek deliberately uses the opposite rounding direction.
      expect(plan.recipe.timeAtFrame(25).inMicroseconds, 1041667);
    },
  );
  test('empty and endpoint-clamped curves preserve their semantics', () {
    expect(
      VideoCraftNativeRenderPlan(
        recipe(keys: {}),
      ).opacityKeys.map((key) => key.opacity),
      [1, 1],
    );
    expect(
      VideoCraftNativeRenderPlan(
        recipe(keys: {150: .3}),
      ).opacityKeys.map((key) => key.opacity),
      [.3, .3],
    );
  });
  test('fractional frame rate crosses native channel as an exact rational', () {
    final source = VideoCraftRecipe(
      sourceName: 'ntsc.mp4',
      duration: const Duration(seconds: 8),
      frameRate: CraftFrameRate(30000, 1001),
      inFrame: 30,
      outFrame: 120,
      opacityKeys: const {0: 1, 120: 0},
    );
    final plan = VideoCraftNativeRenderPlan(source);
    expect(plan.duration, const Duration(milliseconds: 3003));
    final map = plan.opacityAnimation.toMap();
    expect(map['frameRateNumerator'], 30000);
    expect(map['frameRateDenominator'], 1001);
    expect(map['type'], 'opacityKeys');
  });
  test(
    'invalid opacity keys cannot silently become an opaque native overlay',
    () {
      for (final keys in [
        <LayerOpacityKeyframe>[],
        [const LayerOpacityKeyframe(1, .5), const LayerOpacityKeyframe(1, 1)],
        [const LayerOpacityKeyframe(-1, .5)],
        [const LayerOpacityKeyframe(0, double.nan)],
        [const LayerOpacityKeyframe(0, 1.5)],
      ]) {
        final animation = LayerAnimation(
          type: LayerAnimationType.opacityKeys,
          phase: AnimationPhase.animateIn,
          duration: const Duration(seconds: 1),
          opacityKeys: keys,
        );
        expect(animation.toMap, throwsArgumentError);
      }
    },
  );
}
