import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

class FakePreview extends VideoCraftPreviewBackend {
  @override
  bool isReady = false;
  @override
  bool isPlaying = false;
  @override
  Duration duration = const Duration(seconds: 10);
  @override
  Duration position = Duration.zero;
  @override
  double get aspectRatio => 16 / 9;
  @override
  String? get error => null;
  int pauses = 0;
  int plays = 0;
  Completer<void>? seekGate;
  Completer<void>? nextPauseGate;
  final seeks = <Duration>[];
  @override
  Future<void> open(VideoCraftSource source) async {
    isReady = true;
    position = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    await seekGate?.future;
    position = value;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    plays++;
    isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauses++;
    final gate = nextPauseGate;
    nextPauseGate = null;
    await gate?.future;
    isPlaying = false;
    notifyListeners();
  }

  @override
  Widget buildView(BuildContext context) =>
      const ColoredBox(color: Colors.blue, key: Key('real-preview-boundary'));
  void advance(Duration value) {
    position = value;
    notifyListeners();
  }
}

class FakeExporter extends VideoCraftTrimExporter {
  @override
  bool get isSupported => true;
  VideoCraftRecipe? received;
  @override
  Future<Uint8List> exportTrim(
    VideoCraftSource source,
    VideoCraftRecipe recipe,
  ) async {
    received = recipe;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class ControlledExporter extends VideoCraftControlledExporter {
  final gate = Completer<Uint8List>();
  VideoCraftExportCancellation? token;
  VideoCraftRecipe? received;
  @override
  bool get isSupported => true;
  @override
  bool get includesAnimatedTitles => true;
  @override
  Future<Uint8List> exportTrim(
    VideoCraftSource source,
    VideoCraftRecipe recipe,
  ) => exportWithOptions(source, recipe);
  @override
  Future<Uint8List> exportWithOptions(
    VideoCraftSource source,
    VideoCraftRecipe recipe, {
    ValueChanged<double>? onProgress,
    VideoCraftExportCancellation? cancellation,
  }) {
    token = cancellation;
    received = recipe;
    onProgress?.call(.5);
    return gate.future;
  }
}

void main() {
  late VideoCraftController controller;
  late FakePreview preview;
  setUp(() {
    controller = VideoCraftController();
    preview = FakePreview();
  });
  tearDown(() {
    controller.dispose();
    preview.dispose();
  });
  Future<void> mount(
    WidgetTester tester, {
    String sourceName = 'test.mp4',
    Future<void> Function(String)? save,
    Future<String?> Function()? open,
    VideoCraftTrimExporter? exporter,
    Future<void> Function(Uint8List)? export,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCraftWorkspace(
            workspaceStore: MemoryCraftWorkspaceStore(),
            controller: controller,
            previewBackend: preview,
            source: VideoCraftSource.bytes(
              Uint8List.fromList([0]),
              name: sourceName,
            ),
            onSaveRecipe: save,
            onOpenRecipe: open,
            trimExporter: exporter,
            onExportVideo: export,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('source frame seek changes actual backend and trim can undo', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, find.byTooltip('Next frame'));
    expect(preview.seeks.last, const Duration(microseconds: 33334));
    expect(controller.frame, 1);
    await tap(tester, find.text('Set In'));
    expect(controller.recipe!.inFrame, 1);
    await tap(tester, find.byTooltip('Undo'));
    expect(controller.recipe!.inFrame, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'overlay opacity follows real transport updates and host can pause it',
    (tester) async {
      await mount(tester);
      controller.putOpacityKey(0);
      controller.setFrame(60);
      controller.putOpacityKey(1);
      await preview.play();
      preview.advance(const Duration(seconds: 1));
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(find.byKey(const Key('video-title-opacity')))
            .opacity,
        closeTo(.5, 1e-12),
      );
      await controller.pause();
      expect(preview.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'play selection stops at exclusive out and returns to last included frame',
    (tester) async {
      await mount(tester);
      controller.setTrim(30, 60);
      await tap(tester, find.byTooltip('Play selection'));
      expect(preview.seeks.last, const Duration(seconds: 1));
      expect(preview.isPlaying, isTrue);
      preview.advance(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(preview.isPlaying, isFalse);
      expect(controller.frame, 59);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'save captures one recipe snapshot while later edits stay dirty',
    (tester) async {
      final gate = Completer<void>();
      String? saved;
      await mount(
        tester,
        save: (json) {
          saved = json;
          return gate.future;
        },
      );
      await tap(tester, find.text('Save recipe'));
      controller.setTitle('Later title');
      gate.complete();
      await tester.pumpAndSettle();
      expect(VideoCraftRecipe.decode(saved!).title, 'Title');
      expect(
        find.text('Recipe delivered. Later changes are not included.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('trim export invokes supported backend and delivers its bytes', (
    tester,
  ) async {
    final exporter = FakeExporter();
    Uint8List? delivered;
    await mount(
      tester,
      exporter: exporter,
      export: (bytes) async {
        delivered = bytes;
      },
    );
    controller.setTrim(30, 90);
    await tap(tester, find.text('Export trimmed video'));
    expect(exporter.received!.inFrame, 30);
    expect(delivered, [1, 2, 3]);
    expect(
      find.text('Trimmed video delivered. The title overlay is preview only.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('host pause cancels Play waiting for a delayed seek', (
    tester,
  ) async {
    await mount(tester);
    controller.setTrim(30, 60);
    preview.seekGate = Completer<void>();
    await tester.tap(find.byTooltip('Play selection'));
    await tester.pump();
    await controller.pause();
    preview.seekGate!.complete();
    await tester.pumpAndSettle();
    expect(preview.isPlaying, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid recipe callback preserves the active edit session', (
    tester,
  ) async {
    await mount(tester, open: () async => '{');
    controller.setTitle('Keep title');
    final snapshot = controller.recipe;
    await tap(tester, find.text('Open recipe'));
    expect(identical(controller.recipe, snapshot), isTrue);
    expect(find.byKey(const Key('video-status')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'FPS change cancels Play before its asynchronous pause finishes',
    (tester) async {
      await mount(tester);
      controller.setTrim(30, 60);
      final seekGate = Completer<void>();
      preview.seekGate = seekGate;
      await tester.tap(find.byTooltip('Play selection'));
      await tester.pump();
      expect(preview.seeks, isNotEmpty);
      final pauseGate = Completer<void>();
      preview.nextPauseGate = pauseGate;
      await tester.ensureVisible(find.text('60'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('60'));
      await tester.pump();
      seekGate.complete();
      await tester.pumpAndSettle();
      expect(
        preview.plays,
        0,
        reason: 'The old Play must be cancelled before FPS pause resolves',
      );
      pauseGate.complete();
      await tester.pumpAndSettle();
      expect(controller.recipe!.frameRate, CraftFrameRate(60, 1));
      expect(preview.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('export cancels Play before its asynchronous pause finishes', (
    tester,
  ) async {
    final exporter = FakeExporter();
    Uint8List? delivered;
    await mount(
      tester,
      exporter: exporter,
      export: (bytes) async {
        delivered = bytes;
      },
    );
    controller.setTrim(30, 60);
    final seekGate = Completer<void>();
    preview.seekGate = seekGate;
    await tester.tap(find.byTooltip('Play selection'));
    await tester.pump();
    expect(preview.seeks, isNotEmpty);
    final pauseGate = Completer<void>();
    preview.nextPauseGate = pauseGate;
    await tester.ensureVisible(find.text('Export trimmed video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export trimmed video'));
    await tester.pump();
    seekGate.complete();
    await tester.pump();
    expect(
      preview.plays,
      0,
      reason: 'The old Play must be cancelled before export pause resolves',
    );
    expect(exporter.received, isNull);
    pauseGate.complete();
    await tester.pumpAndSettle();
    expect(delivered, [1, 2, 3]);
    expect(preview.isPlaying, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a delayed automatic stop cannot seek a replacement source', (
    tester,
  ) async {
    await mount(tester);
    controller.setTrim(0, 90);
    await preview.play();
    final gate = Completer<void>();
    preview.nextPauseGate = gate;
    preview.advance(const Duration(seconds: 3));
    await tester.pump();
    await mount(tester, sourceName: 'replacement.mp4');
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.recipe!.sourceName, 'replacement.mp4');
    expect(controller.frame, 0);
    expect(preview.seeks, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('complete MP4 reports progress and renders a recipe snapshot', (
    tester,
  ) async {
    final exporter = ControlledExporter();
    Uint8List? delivered;
    await mount(
      tester,
      exporter: exporter,
      export: (bytes) async => delivered = bytes,
    );
    controller.setTitle('Snapshot');
    await tap(tester, find.text('Export MP4'));
    expect(find.text('Exporting MP4: 50%'), findsOneWidget);
    controller.setTitle('Later edit from host');
    expect(exporter.received!.title, 'Snapshot');
    exporter.gate.complete(Uint8List.fromList([1, 2]));
    await tester.pumpAndSettle();
    expect(
      delivered,
      isNull,
      reason: 'Saving requires a fresh user gesture after encoding',
    );
    await tap(tester, find.text('Save rendered MP4'));
    expect(delivered, [1, 2]);
    expect(
      find.text('MP4 delivered with the title and opacity animation.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a cancelled save can retry the rendered result; source replacement releases it',
    (tester) async {
      final exporter = ControlledExporter();
      var saves = 0;
      await mount(
        tester,
        exporter: exporter,
        export: (_) async {
          if (++saves == 1) throw const FormatException('Save cancelled');
        },
      );
      await tap(tester, find.text('Export MP4'));
      exporter.gate.complete(Uint8List.fromList([1, 2]));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Save rendered MP4'));
      expect(find.textContaining('Save cancelled'), findsOneWidget);
      expect(
        find.text('MP4 delivered with the title and opacity animation.'),
        findsNothing,
      );
      await tap(tester, find.text('Save rendered MP4'));
      expect(saves, 2);
      await mount(
        tester,
        sourceName: 'replacement.mp4',
        exporter: exporter,
        export: (_) async => saves++,
      );
      expect(find.text('Save rendered MP4'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'recipe edits invalidate rendered bytes but moving the playhead preserves them',
    (tester) async {
      final exporter = ControlledExporter();
      var saves = 0;
      await mount(tester, exporter: exporter, export: (_) async => saves++);
      controller.setTitle('Rendered title');
      await tap(tester, find.text('Export MP4'));
      exporter.gate.complete(Uint8List.fromList([1, 2]));
      await tester.pumpAndSettle();
      expect(find.text('Save rendered MP4'), findsOneWidget);
      preview.advance(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Save rendered MP4'), findsOneWidget);
      controller.setTitle('Title requiring a new export');
      await tester.pumpAndSettle();
      expect(find.text('Save rendered MP4'), findsNothing);
      expect(saves, 0);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export MP4'),
      );
      expect(button.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancel discards late completed bytes and allows editing again', (
    tester,
  ) async {
    final exporter = ControlledExporter();
    var deliveries = 0;
    await mount(tester, exporter: exporter, export: (_) async => deliveries++);
    await tap(tester, find.text('Export MP4'));
    await tap(tester, find.text('Cancel export'));
    expect(exporter.token!.isCancelled, isTrue);
    exporter.gate.complete(Uint8List.fromList([1]));
    await tester.pumpAndSettle();
    expect(deliveries, 0);
    expect(find.text('Export cancelled.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export MP4'),
    );
    expect(button.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'opening another source cancels an export without delivering stale bytes',
    (tester) async {
      final exporter = ControlledExporter();
      var deliveries = 0;
      await mount(
        tester,
        exporter: exporter,
        export: (_) async => deliveries++,
      );
      await tap(tester, find.text('Export MP4'));
      await mount(
        tester,
        sourceName: 'replacement.mp4',
        exporter: exporter,
        export: (_) async => deliveries++,
      );
      expect(exporter.token!.isCancelled, isTrue);
      exporter.gate.complete(Uint8List.fromList([1]));
      await tester.pumpAndSettle();
      expect(deliveries, 0);
      expect(controller.recipe!.sourceName, 'replacement.mp4');
      expect(
        find.text('MP4 delivered with the title and opacity animation.'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disposing the workspace cancels export and prevents delivery', (
    tester,
  ) async {
    final exporter = ControlledExporter();
    var deliveries = 0;
    await mount(tester, exporter: exporter, export: (_) async => deliveries++);
    await tap(tester, find.text('Export MP4'));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(exporter.token!.isCancelled, isTrue);
    exporter.gate.complete(Uint8List.fromList([1]));
    await tester.pumpAndSettle();
    expect(deliveries, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile 320px and large text can reach both sections without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: VideoCraftWorkspace(
              workspaceStore: MemoryCraftWorkspaceStore(),
              controller: controller,
              previewBackend: preview,
              source: VideoCraftSource.bytes(
                Uint8List.fromList([0]),
                name: 'test.mp4',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Animation'));
      await tester.ensureVisible(find.byKey(const Key('video-title-input')));
      await tester.enterText(
        find.byKey(const Key('video-title-input')),
        'Mobile title',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tap(tester, find.text('Apply title'));
      expect(controller.recipe!.title, 'Mobile title');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
