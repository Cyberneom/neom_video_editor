import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

class _DelayedPreview extends VideoCraftPreviewBackend {
  Completer<void>? nextOpenGate;
  final openedNames = <String>[];
  @override
  bool isReady = false;
  @override
  bool isPlaying = false;
  @override
  Duration get duration => const Duration(seconds: 4);
  @override
  Duration position = Duration.zero;
  @override
  double get aspectRatio => 16 / 9;
  @override
  String? get error => null;

  @override
  Future<void> open(VideoCraftSource source) async {
    openedNames.add(source.name);
    final gate = nextOpenGate;
    nextOpenGate = null;
    await gate?.future;
    isReady = true;
    position = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    notifyListeners();
  }

  @override
  Widget buildView(BuildContext context) => const SizedBox.expand();
}

VideoCraftSource _source(String name) =>
    VideoCraftSource.bytes(Uint8List.fromList([1]), name: name);

Widget _app({
  required VideoCraftController controller,
  required _DelayedPreview preview,
  VideoCraftSource? source,
  required Future<VideoCraftSource?> Function() pick,
}) => MaterialApp(
  home: Scaffold(
    body: VideoCraftWorkspace(
      workspaceStore: MemoryCraftWorkspaceStore(),
      key: const Key('source-races-workspace'),
      controller: controller,
      previewBackend: preview,
      source: source,
      onPickSource: pick,
    ),
  ),
);

void main() {
  for (final mode in ['controller', 'backend', 'both']) {
    testWidgets(
      'rebind $mode during pending open with null source releases busy state',
      (tester) async {
        final firstController = VideoCraftController();
        final replacementController = VideoCraftController();
        final firstPreview = _DelayedPreview();
        final replacementPreview = _DelayedPreview();
        final pendingOpen = Completer<void>();
        firstPreview.nextOpenGate = pendingOpen;
        final fresh = _source('fresh.mp4');
        Future<VideoCraftSource?> pick() async => fresh;
        await tester.pumpWidget(
          _app(
            controller: firstController,
            preview: firstPreview,
            source: _source('pending.mp4'),
            pick: pick,
          ),
        );
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        final controller = mode == 'backend'
            ? firstController
            : replacementController;
        final preview = mode == 'controller'
            ? firstPreview
            : replacementPreview;
        await tester.pumpWidget(
          _app(controller: controller, preview: preview, pick: pick),
        );
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('video-open')))
              .onPressed,
          isNotNull,
        );

        pendingOpen.complete();
        await tester.pumpAndSettle();
        expect(
          controller.recipe,
          isNull,
          reason: 'The retired open must not attach to the rebound controller.',
        );
        await tester.tap(find.byKey(const Key('video-open')));
        await tester.pumpAndSettle();
        expect(controller.recipe!.sourceName, 'fresh.mp4');
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        firstController.dispose();
        replacementController.dispose();
        firstPreview.dispose();
        replacementPreview.dispose();
      },
    );
  }

  testWidgets(
    'late file picker result cannot replace a newer source from the host',
    (tester) async {
      final controller = VideoCraftController();
      final preview = _DelayedPreview();
      final picker = Completer<VideoCraftSource?>();
      Future<VideoCraftSource?> pick() => picker.future;
      await tester.pumpWidget(
        _app(
          controller: controller,
          preview: preview,
          source: _source('first.mp4'),
          pick: pick,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('video-open')));
      await tester.pump();
      await tester.pumpWidget(
        _app(
          controller: controller,
          preview: preview,
          source: _source('replacement.mp4'),
          pick: pick,
        ),
      );
      await tester.pumpAndSettle();
      picker.complete(_source('stale-picker.mp4'));
      await tester.pumpAndSettle();
      expect(controller.recipe!.sourceName, 'replacement.mp4');
      expect(preview.openedNames, ['first.mp4', 'replacement.mp4']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      preview.dispose();
    },
  );
}
