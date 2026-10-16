import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

void main() {
  test('cancel notifies pending work once and late work cannot start', () {
    final token = VideoCraftExportCancellation();
    var calls = 0;
    token.addListener(() => calls++);
    token.cancel();
    token.cancel();
    expect(calls, 1);
    token.addListener(() => calls++);
    expect(calls, 2);
    expect(token.throwIfCancelled, throwsA(isA<VideoCraftExportCancelled>()));
  });

  test('completed work unsubscribes from subsequent cancellation', () {
    final token = VideoCraftExportCancellation();
    var calls = 0;
    final unsubscribe = token.addListener(() => calls++);
    unsubscribe();
    token.cancel();
    expect(calls, 0);
  });

  test(
    'web factory rejects a cancelled export before loading a media asset',
    () async {
      if (!kIsWeb) return;
      final exporter = createVideoCraftTrimExporter();
      expect(exporter, isA<VideoCraftControlledExporter>());
      final controlled = exporter as VideoCraftControlledExporter;
      expect(controlled.includesAnimatedTitles, isTrue);
      final token = VideoCraftExportCancellation()..cancel();
      final recipe = VideoCraftRecipe(
        sourceName: 'cancelled.mp4',
        duration: const Duration(seconds: 1),
        frameRate: CraftFrameRate(24, 1),
        inFrame: 0,
        outFrame: 24,
      );
      await expectLater(
        controlled.exportWithOptions(
          VideoCraftSource.bytes(Uint8List(0)),
          recipe,
          cancellation: token,
        ),
        throwsA(isA<VideoCraftExportCancelled>()),
      );
    },
  );
}
