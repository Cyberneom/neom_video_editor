@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart'
    hide ProVideoCraftTrimExporter;
import 'package:neom_video_editor/video_craft/data/video_craft_native_exporter.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

const sourceInfo = VideoCraftNativeMediaInfo(
  width: 720,
  height: 404,
  duration: Duration(seconds: 8),
  audioTrackCount: 1,
  frameRate: 24,
);
const outputInfo = VideoCraftNativeMediaInfo(
  width: 720,
  height: 404,
  duration: Duration(milliseconds: 4075),
  videoDuration: Duration(seconds: 4),
  audioTrackCount: 1,
  frameRate: 24,
);
final mp4Header = Uint8List.fromList([
  0,
  0,
  0,
  16,
  102,
  116,
  121,
  112,
  105,
  115,
  111,
  109,
  0,
  0,
  0,
  0,
]);
VideoCraftRecipe recipe({String title = 'Open Neom'}) => VideoCraftRecipe(
  sourceName: 'fixture.mp4',
  duration: const Duration(seconds: 8),
  frameRate: CraftFrameRate(24, 1),
  inFrame: 24,
  outFrame: 120,
  title: title,
  opacityKeys: const {24: 1, 72: .5, 119: 0},
);

class FakeNativeBackend implements VideoCraftNativeBackend {
  bool supported = true;
  VideoCraftNativeMediaInfo input = sourceInfo;
  VideoCraftNativeMediaInfo output = outputInfo;
  final capabilitiesGate = Completer<void>();
  final metadataGate = Completer<void>();
  final renderGate = Completer<void>();
  final started = Completer<void>();
  bool waitCapabilities = false;
  bool waitMetadata = false;
  bool waitRender = false;
  final controller = StreamController<double>.broadcast(sync: true);
  VideoRenderData? job;
  Map<String, dynamic>? serialized;
  final paths = <String>[];
  final cancelledIds = <String>[];
  String? outputPath;
  @override
  Future<bool> supportsOpacityKeys() async {
    if (waitCapabilities) await capabilitiesGate.future;
    return supported;
  }

  @override
  Future<VideoCraftNativeMediaInfo> metadata(String path) async {
    paths.add(path);
    if (waitMetadata && paths.length == 1) await metadataGate.future;
    return path.endsWith('/rendered.mp4') ? output : input;
  }

  @override
  Stream<double> progress(String taskId) => controller.stream;
  @override
  Future<void> render(String path, VideoRenderData data) async {
    outputPath = path;
    job = data;
    serialized = await data.toAsyncMap();
    started.complete();
    controller.add(.5);
    controller.add(.2);
    controller.add(1);
    if (waitRender) await renderGate.future;
    await File(path).writeAsBytes(mp4Header);
  }

  @override
  Future<void> cancel(String taskId) async {
    cancelledIds.add(taskId);
    // Deliberately return a completed file after cancel, reproducing a native
    // completion race. The exporter must discard these bytes and clean up.
    if (!renderGate.isCompleted) renderGate.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late FakeNativeBackend backend;
  late ProVideoCraftTrimExporter exporter;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('neom-native-test-');
    backend = FakeNativeBackend();
    exporter = ProVideoCraftTrimExporter(
      backend: backend,
      temporaryDirectory: temporary,
      titleRenderer: (title, {required width, required height}) async =>
          Uint8List.fromList([1, 2, 3]),
    );
  });
  tearDown(() async {
    await backend.controller.close();
    await temporary.delete(recursive: true);
  });
  Future<void> clean() async =>
      expect(await temporary.list().toList(), isEmpty);
  VideoCraftSource source() =>
      VideoCraftSource.bytes(Uint8List.fromList([1, 2, 3]));

  test(
    'full recipe reaches native renderer and audio/dimensions survive validation',
    () async {
      final progress = <double>[];
      final result = await exporter.exportWithOptions(
        source(),
        recipe(),
        onProgress: progress.add,
      );
      expect(result, mp4Header);
      expect(backend.job!.enableAudio, isTrue);
      expect(backend.serialized!['neomExactTrim'], isTrue);
      expect(
        (backend.serialized!['videoClips'] as List).single['neomFrameRange'],
        {'inFrame': 24, 'outFrame': 120, 'numerator': 24, 'denominator': 1},
      );
      expect(
        backend.job!.videoSegments!.single.startTime,
        const Duration(seconds: 1),
      );
      expect(
        backend.job!.videoSegments!.single.endTime,
        const Duration(seconds: 5),
      );
      expect(backend.job!.imageLayers!.single.animations.single.opacityKeys, [
        const LayerOpacityKeyframe(0, 1),
        const LayerOpacityKeyframe(48, .5),
        const LayerOpacityKeyframe(95, 0),
      ]);
      expect(progress.last, 1);
      expect(progress, orderedEquals(progress.toList()..sort()));
      await clean();
    },
  );
  test('pre-cancel and old native plugin do not start an export', () async {
    await expectLater(
      exporter.exportWithOptions(
        source(),
        recipe(),
        cancellation: VideoCraftExportCancellation()..cancel(),
      ),
      throwsA(isA<VideoCraftExportCancelled>()),
    );
    backend.supported = false;
    await expectLater(
      exporter.exportTrim(source(), recipe()),
      throwsUnsupportedError,
    );
    expect(backend.job, isNull);
    await clean();
  });
  test(
    'cancellation during capability check prevents input allocation',
    () async {
      backend.waitCapabilities = true;
      final token = VideoCraftExportCancellation();
      final result = exporter.exportWithOptions(
        source(),
        recipe(),
        cancellation: token,
      );
      token.cancel();
      backend.capabilitiesGate.complete();
      await expectLater(result, throwsA(isA<VideoCraftExportCancelled>()));
      expect(backend.paths, isEmpty);
      await clean();
    },
  );
  test(
    'cancellation during metadata prevents rendering and removes copied media',
    () async {
      backend.waitMetadata = true;
      final token = VideoCraftExportCancellation();
      final result = exporter.exportWithOptions(
        source(),
        recipe(),
        cancellation: token,
      );
      while (backend.paths.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      token.cancel();
      backend.metadataGate.complete();
      await expectLater(result, throwsA(isA<VideoCraftExportCancelled>()));
      expect(backend.job, isNull);
      await clean();
    },
  );
  test(
    'cancellation during title rasterization cannot dispatch native work',
    () async {
      final titleStarted = Completer<void>();
      final titleDone = Completer<Uint8List>();
      final renderer = ProVideoCraftTrimExporter(
        backend: backend,
        temporaryDirectory: temporary,
        titleRenderer: (title, {required width, required height}) {
          titleStarted.complete();
          return titleDone.future;
        },
      );
      final token = VideoCraftExportCancellation();
      final result = renderer.exportWithOptions(
        source(),
        recipe(),
        cancellation: token,
      );
      await titleStarted.future;
      token.cancel();
      titleDone.complete(Uint8List(4));
      await expectLater(result, throwsA(isA<VideoCraftExportCancelled>()));
      expect(backend.job, isNull);
      await clean();
    },
  );
  test(
    'active cancel uses the exact job id and never returns late bytes',
    () async {
      backend.waitRender = true;
      final token = VideoCraftExportCancellation();
      final result = exporter.exportWithOptions(
        source(),
        recipe(),
        cancellation: token,
      );
      await backend.started.future;
      token.cancel();
      await expectLater(result, throwsA(isA<VideoCraftExportCancelled>()));
      expect(backend.cancelledIds, [backend.job!.id]);
      await clean();
    },
  );
  test('multiple audio streams are rejected before rendering', () async {
    backend.input = const VideoCraftNativeMediaInfo(
      width: 720,
      height: 404,
      duration: Duration(seconds: 8),
      audioTrackCount: 2,
    );
    await expectLater(
      exporter.exportTrim(source(), recipe()),
      throwsUnsupportedError,
    );
    expect(backend.job, isNull);
    await clean();
  });
  test('silent or resized native output fails and is removed', () async {
    for (final info in [
      const VideoCraftNativeMediaInfo(
        width: 720,
        height: 404,
        duration: Duration(seconds: 4),
        audioTrackCount: 0,
      ),
      const VideoCraftNativeMediaInfo(
        width: 360,
        height: 202,
        duration: Duration(seconds: 4),
        audioTrackCount: 1,
      ),
    ]) {
      // New backend because each render job has its own completion event.
      final badBackend = FakeNativeBackend()..output = info;
      final bad = ProVideoCraftTrimExporter(
        backend: badBackend,
        temporaryDirectory: temporary,
      );
      await expectLater(
        bad.exportTrim(source(), recipe(title: '')),
        throwsStateError,
      );
      await badBackend.controller.close();
      await clean();
    }
  });
  test(
    'container audio padding cannot hide a short or unknown video stream',
    () async {
      for (final videoDuration in [
        const Duration(microseconds: 3958333),
        null,
      ]) {
        final badBackend = FakeNativeBackend()
          ..output = VideoCraftNativeMediaInfo(
            width: 720,
            height: 404,
            duration: const Duration(milliseconds: 4075),
            videoDuration: videoDuration,
            audioTrackCount: 1,
            frameRate: 24,
          );
        final bad = ProVideoCraftTrimExporter(
          backend: badBackend,
          temporaryDirectory: temporary,
        );
        await expectLater(
          bad.exportTrim(source(), recipe(title: '')),
          throwsStateError,
        );
        await badBackend.controller.close();
        await clean();
      }
    },
  );
  test(
    'blank title bypasses rasterization and caller-owned source file survives',
    () async {
      final input = File('${temporary.path}/caller-video.mp4');
      await input.writeAsBytes([1, 2, 3]);
      await exporter.exportTrim(
        VideoCraftSource.uri(input.uri),
        recipe(title: '  '),
      );
      expect(backend.job!.imageLayers, isEmpty);
      expect(await input.readAsBytes(), [1, 2, 3]);
      expect((await temporary.list().toList()).map((file) => file.path), [
        input.path,
      ]);
    },
  );
}
