@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/video_craft/data/video_craft_project_source_web.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser blob project media read is exact and bounded', () async {
    final bytes = Uint8List.fromList(List.generate(32, (i) => i));
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    try {
      expect(await readProjectUri(Uri.parse(url), 32), bytes);
      await expectLater(
        readProjectUri(Uri.parse(url), 31),
        throwsFormatException,
      );
      await expectLater(
        readProjectUri(Uri.parse('file:///clip.mp4'), 32),
        throwsUnsupportedError,
      );
    } finally {
      web.URL.revokeObjectURL(url);
    }
  });
}
