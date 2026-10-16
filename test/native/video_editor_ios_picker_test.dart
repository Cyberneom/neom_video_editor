@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/video_craft/ui/video_editor_sections_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final calls = <MethodCall>[];
  var filename = 'saved.NEOMVIDEOPROJECT';
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return [
            {
              'name': filename,
              'size': 1,
              'bytes': Uint8List.fromList([7]),
            },
          ];
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  const files = PlatformVideoEditorFileAccess();
  test(
    'iOS project and recipe selectors allow custom extensions and JSON',
    () async {
      for (final extension in ['neomvideoproject', 'neomvideo', 'json']) {
        filename = 'Saved.${extension.toUpperCase()}';
        final extensions = extension == 'neomvideoproject'
            ? ['neomvideoproject']
            : ['neomvideo', 'json'];
        expect((await files.open(extensions: extensions))!.bytes, [7]);
        expect(calls.last.method, 'any');
        expect(calls.last.arguments['allowedExtensions'], isNull);
      }
      filename = 'different.mp4';
      await expectLater(
        files.open(extensions: ['neomvideoproject']),
        throwsFormatException,
      );
    },
  );
  test('iOS videos and macOS projects retain their native filters', () async {
    await files.open(extensions: ['mp4', 'mov']);
    expect(calls.last.method, 'custom');
    expect(calls.last.arguments['allowedExtensions'], ['mp4', 'mov']);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await files.open(extensions: ['neomvideoproject']);
    expect(calls.last.method, 'custom');
    expect(calls.last.arguments['allowedExtensions'], ['neomvideoproject']);
  });
}
