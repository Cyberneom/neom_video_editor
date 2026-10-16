@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/video_craft/data/video_craft_project_source_io.dart';

void main() {
  test(
    'local project media read is exact and rejects oversized or empty files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'neom-project-reader-',
      );
      final file = File('${directory.path}/video.mp4');
      try {
        final bytes = Uint8List.fromList(List.generate(32, (i) => i));
        await file.writeAsBytes(bytes);
        expect(await readProjectUri(file.uri, 32), bytes);
        await expectLater(readProjectUri(file.uri, 31), throwsFormatException);
        await file.writeAsBytes([]);
        await expectLater(readProjectUri(file.uri, 32), throwsFormatException);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test('HTTP project media is bounded even without Content-Length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(List.generate(32, (i) => i));
      await request.response.close();
    });
    final uri = Uri.parse('http://127.0.0.1:${server.port}/video.mp4');
    try {
      expect(await readProjectUri(uri, 32), List.generate(32, (i) => i));
      await expectLater(readProjectUri(uri, 31), throwsFormatException);
      await expectLater(
        readProjectUri(Uri.parse('ftp://localhost/clip.mp4'), 32),
        throwsUnsupportedError,
      );
    } finally {
      await server.close(force: true);
    }
  });
}
