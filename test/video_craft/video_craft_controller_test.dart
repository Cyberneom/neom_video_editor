import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

void main() {
  late VideoCraftController controller;
  setUp(() {
    controller = VideoCraftController()
      ..attachMedia(
        name: 'test.mp4',
        duration: const Duration(seconds: 10),
        frameRate: CraftFrameRate(30, 1),
      );
  });
  tearDown(() => controller.dispose());

  test(
    'fractional-rate boundaries survive microsecond transport without losing a frame',
    () {
      controller.setFrameRate(CraftFrameRate(30000, 1001));
      final recipe = controller.recipe!;
      for (final frame in [0, 1, 29, 30, 298]) {
        expect(recipe.frameAtTime(recipe.timeAtFrame(frame)), frame);
      }
      expect(recipe.timeAtFrame(30), const Duration(milliseconds: 1001));
      expect(recipe.timecode(30), '00;00;01;00');
    },
  );

  test(
    'half-open trim is undoable and invalid changes preserve session/history',
    () {
      controller.setTrim(30, 90);
      final before = controller.recipe;
      expect(() => controller.setTrim(90, 90), throwsFormatException);
      expect(identical(controller.recipe, before), isTrue);
      expect(controller.recipe!.timeAtFrame(90), const Duration(seconds: 3));
      controller.undo();
      expect(controller.recipe!.outFrame, 300);
      controller.redo();
      expect(controller.recipe!.inFrame, 30);
      expect(controller.recipe!.outFrame, 90);
    },
  );

  test(
    'Effectcraft opacity evaluates at the same source frame as playback',
    () {
      controller.putOpacityKey(0);
      controller.setFrame(60);
      controller.putOpacityKey(1);
      controller.setPosition(const Duration(seconds: 1));
      expect(controller.frame, 30);
      expect(controller.opacity, closeTo(.5, 1e-12));
      controller.undo();
      expect(controller.opacity, 0);
    },
  );

  test(
    'recipe round-trip restores edits as one undo and embeds no media bytes',
    () {
      controller.setTrim(10, 100);
      controller.setTitle('Título ✨');
      controller.putOpacityKey(.25);
      final saved = controller.recipe!.encode();
      controller.setTitle('Changed');
      controller.loadRecipe(saved);
      expect(controller.recipe!.title, 'Título ✨');
      expect(controller.recipe!.opacityAt(0), .25);
      expect(jsonDecode(saved)['format'], 'neom-video-recipe');
      expect(saved, isNot(contains('byteArray')));
      controller.undo();
      expect(controller.recipe!.title, 'Changed');
    },
  );

  test('invalid or mismatched recipe cannot erase current edits', () {
    controller.setTitle('Keep me');
    final snapshot = controller.recipe;
    for (final json in [
      '{',
      snapshot!.encode().replaceAll('test.mp4', 'other.mp4'),
      snapshot.encode().replaceAll('"version": 1', '"version": 2'),
      jsonEncode(
        (jsonDecode(snapshot.encode()) as Map<String, dynamic>)
          ..['opacityKeys'] = [
            {'frame': 0, 'value': -1},
          ],
      ),
    ]) {
      expect(() => controller.loadRecipe(json), throwsFormatException);
      expect(identical(snapshot, controller.recipe), isTrue);
    }
  });

  test('frame-rate changes preserve time and undo restores original rate', () {
    controller.setTrim(30, 90);
    controller.setFrame(60);
    controller.putOpacityKey(.2);
    controller.setFrameRate(CraftFrameRate(60, 1));
    expect(controller.recipe!.inFrame, 60);
    expect(controller.recipe!.outFrame, 180);
    expect(controller.recipe!.opacityKeys[120], .2);
    expect(controller.frame, 120);
    controller.undo();
    expect(controller.recipe!.frameRate, CraftFrameRate(30, 1));
  });

  test('undo and redo FPS preserve paused source time, not frame number', () {
    controller.setPosition(const Duration(milliseconds: 1020));
    expect(controller.frame, 30);
    controller.setFrameRate(CraftFrameRate(60, 1));
    expect(controller.frame, 61);
    controller.undo();
    expect(controller.frame, 30);
    expect(controller.position, const Duration(milliseconds: 1020));
    controller.redo();
    expect(controller.frame, 61);
    expect(controller.position, const Duration(milliseconds: 1020));
  });

  test(
    'replacing source clears undo so old recipes cannot apply to a new video',
    () {
      controller.setTitle('Old clip');
      controller.attachMedia(
        name: 'new.mp4',
        duration: const Duration(seconds: 2),
      );
      expect(controller.canUndo, isFalse);
      expect(controller.recipe!.sourceName, 'new.mp4');
      expect(controller.recipe!.outFrame, 60);
    },
  );
}
