import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/video_craft/rendering/video_craft_title_renderer.dart';

void main() {
  testWidgets('title PNG uses source dimensions and a transparent background', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final png = await renderVideoCraftTitle(
        'OPEN NEOM',
        width: 720,
        height: 404,
      );
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      try {
        expect(frame.image.width, 720);
        expect(frame.image.height, 404);
        final bytes = (await frame.image.toByteData())!.buffer.asUint8List();
        expect(bytes[3], 0);
        var visible = 0;
        for (var y = 0; y < 404; y++) {
          for (var x = 0; x < 720; x++) {
            final alpha = bytes[(y * 720 + x) * 4 + 3];
            if (y < 200 || y >= 373) expect(alpha, 0);
            if (alpha > 0) visible++;
          }
        }
        expect(visible, greaterThan(1000));
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('an empty title is completely transparent', (tester) async {
    await tester.runAsync(() async {
      final png = await renderVideoCraftTitle('', width: 48, height: 32);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      try {
        final bytes = (await frame.image.toByteData())!.buffer.asUint8List();
        expect(bytes.every((value) => value == 0), isTrue);
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    });
  });
}
