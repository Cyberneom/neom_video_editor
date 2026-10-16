import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';
import 'video_craft_workspace_test.dart' show FakePreview;

void main() {
  late VideoCraftController controller;
  late FakePreview preview;
  setUp(() {
    controller = VideoCraftController();
    preview = FakePreview()..duration = const Duration(minutes: 12);
  });
  tearDown(() {
    controller.dispose();
    preview.dispose();
  });
  Future<void> mount(WidgetTester tester, {CraftFrameRate? rate}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCraftWorkspace(
            workspaceStore: MemoryCraftWorkspaceStore(),
            controller: controller,
            previewBackend: preview,
            source: VideoCraftSource.bytes(
              Uint8List.fromList([0]),
              frameRate: rate,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> go(
    WidgetTester tester,
    String text, {
    bool submit = false,
  }) async {
    final input = find.byKey(const Key('video-timecode-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, text);
    if (submit) {
      await tester.testTextInput.receiveAction(TextInputAction.go);
    } else {
      final button = find.byKey(const Key('video-timecode-go'));
      await tester.ensureVisible(button);
      await tester.tap(button);
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'absolute and relative timecode seek media without editing recipe',
    (tester) async {
      await mount(tester);
      final recipe = controller.recipe!;
      final encoded = recipe.encode();
      await go(tester, '00:00:01:10', submit: true);
      expect(controller.frame, 40);
      expect(preview.seeks.last, recipe.timeAtFrame(40));
      await go(tester, '+15');
      expect(controller.frame, 55);
      await go(tester, '-1.00');
      expect(controller.frame, 25);
      expect(preview.seeks.last, recipe.timeAtFrame(25));
      expect(identical(controller.recipe, recipe), isTrue);
      expect(controller.recipe!.encode(), encoded);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'invalid and out-of-range destinations preserve transport and selection',
    (tester) async {
      await mount(tester);
      await go(tester, '+75');
      controller.setTrim(controller.frame, controller.recipe!.outFrame);
      final recipe = controller.recipe!;
      final seeks = preview.seeks.length;
      final pauses = preview.pauses;
      for (final text in ['abc', '-100', '00:12:00:00', '99999999', '1:-2']) {
        await go(tester, text);
        expect(controller.frame, 75, reason: text);
        expect(preview.seeks.length, seeks, reason: text);
        expect(preview.pauses, pauses, reason: text);
        expect(identical(controller.recipe, recipe), isTrue);
        expect(find.byKey(const Key('video-status')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('video-status'))).data,
          contains('FormatException'),
        );
      }
      await go(tester, '0');
      expect(controller.frame, 0);
      expect(controller.recipe!.inFrame, 75);
      expect(find.byKey(const Key('video-status')), findsNothing);
    },
  );

  for (final (num, label, omitted, frame) in [
    (30000, '00;01;00;02', '00;01;00;01', 1800),
    (60000, '00;01;00;04', '00;01;00;03', 3600),
  ]) {
    testWidgets(
      '$num/1001 rejects omitted labels and seeks valid drop-frame label',
      (tester) async {
        await mount(tester, rate: CraftFrameRate(num, 1001));
        await go(tester, label);
        expect(controller.frame, frame);
        expect(preview.seeks.last, controller.recipe!.timeAtFrame(frame));
        final seeks = preview.seeks.length;
        await go(tester, omitted);
        expect(controller.frame, frame);
        expect(preview.seeks.length, seeks);
        expect(
          tester.widget<Text>(find.byKey(const Key('video-status'))).data,
          contains('omitted by drop-frame'),
        );
      },
    );
  }
}
