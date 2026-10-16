import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';
import 'package:neom_video_editor/video_craft/data/video_craft_recovery.dart';

import 'video_craft_recovery_test.dart' show ControlledStore, project;

class _Preview extends VideoCraftPreviewBackend {
  String? reject;
  int opens = 0;
  @override
  bool isReady = false;
  @override
  bool isPlaying = false;
  @override
  Duration get duration => const Duration(seconds: 8);
  @override
  Duration position = Duration.zero;
  @override
  double get aspectRatio => 16 / 9;
  @override
  String? get error => null;
  @override
  Future<void> open(VideoCraftSource source) async {
    ++opens;
    if (source.name == reject) throw StateError('Decoder rejected source');
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

  void tick(int frame) {
    position = Duration(microseconds: (frame * 1000000 / 24).ceil());
    notifyListeners();
  }

  @override
  Widget buildView(BuildContext context) => const SizedBox.expand();
}

Widget _app(
  ControlledStore store,
  VideoCraftController controller,
  _Preview preview, {
  VideoCraftSource? source,
  String? id = 'qa.video',
  Future<void> Function(Uint8List)? save,
}) => MaterialApp(
  home: Scaffold(
    body: VideoCraftWorkspace(
      workspaceStore: MemoryCraftWorkspaceStore(),
      recoveryStore: store,
      recoveryId: id,
      controller: controller,
      previewBackend: preview,
      source: source,
      onSaveProject: save,
    ),
  ),
);

Future<void> _saveRecovery(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('disabled recovery never reads or writes the injected store', (
    tester,
  ) async {
    final store = ControlledStore(), controller = VideoCraftController();
    await tester.pumpWidget(
      _app(store, controller, _Preview(), source: project().source, id: null),
    );
    await tester.pumpAndSettle();
    controller.setTitle('Private edits');
    await _saveRecovery(tester);
    expect(store.reads, 0);
    expect(store.writes, 0);
    expect(find.byKey(const Key('video-recovery-banner')), findsNothing);
    await _close(tester);
  });

  testWidgets(
    'edit, undo, stable seek and unapplied title recover after restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = ControlledStore(), first = VideoCraftController();
      var hostSaves = 0;
      await tester.pumpWidget(
        _app(
          store,
          first,
          _Preview(),
          source: project().source,
          save: (_) async {
            ++hostSaves;
          },
        ),
      );
      await tester.pumpAndSettle();
      first.setTitle('Keep applied');
      first.setTrim(24, 120);
      first.setTitle('Undo this');
      first.undo();
      first.redo();
      expect(first.recipe!.title, 'Undo this');
      first.undo();
      await tester.enterText(
        find.byKey(const Key('video-timecode-input')),
        '00:00:03:00',
      );
      await _tap(tester, 'video-timecode-go');
      await _tap(tester, 'craft-workspace-tab-animation');
      await tester.enterText(
        find.byKey(const Key('video-title-input')),
        'Draft only',
      );
      await _saveRecovery(tester);
      final committed = VideoCraftRecoveryData.decode(
        (await store.read('qa.video'))!.bytes,
      );
      expect(committed.project.recipe.title, 'Keep applied');
      expect(committed.project.recipe.inFrame, 24);
      expect(committed.project.frame, 72);
      expect(committed.titleDraft, 'Draft only');
      expect(hostSaves, 0);
      await _close(tester);

      final second = VideoCraftController(), preview = _Preview();
      await tester.pumpWidget(_app(store, second, preview));
      await tester.pumpAndSettle();
      expect(second.recipe, isNull);
      expect(preview.opens, 0);
      final writes = store.writes;
      await _saveRecovery(tester);
      expect(store.writes, writes);
      await _tap(tester, 'video-recovery-restore');
      expect(second.recipe!.encode(), committed.project.recipe.encode());
      expect(second.frame, 72);
      expect(second.canUndo, isFalse);
      await _tap(tester, 'craft-workspace-tab-animation');
      final field = tester.widget<TextField>(
        find.byKey(const Key('video-title-input')),
      );
      expect(field.controller!.text, 'Draft only');
      expect(second.recipe!.title, 'Keep applied');
      await _close(tester);
    },
  );

  testWidgets(
    'playback ticks do not autosave every frame; pausing saves cursor',
    (tester) async {
      final store = ControlledStore(),
          controller = VideoCraftController(),
          preview = _Preview();
      await tester.pumpWidget(
        _app(store, controller, preview, source: project().source),
      );
      await tester.pumpAndSettle();
      await _saveRecovery(tester);
      final writes = store.writes;
      await preview.play();
      for (final frame in [20, 30, 40, 50]) {
        preview.tick(frame);
        await _saveRecovery(tester);
      }
      expect(store.writes, writes);
      await controller.pause();
      await _saveRecovery(tester);
      expect(store.writes, writes + 1);
      expect(
        VideoCraftRecoveryData.decode(
          (await store.read('qa.video'))!.bytes,
        ).project.frame,
        50,
      );
      await _close(tester);
    },
  );

  testWidgets(
    'corrupt payload and decoder rejection keep the accepted session',
    (tester) async {
      final store = ControlledStore(),
          controller = VideoCraftController(),
          preview = _Preview();
      final candidate = await store.memory.write(
        'qa.video',
        Uint8List.fromList([1, 2, 3]),
      );
      final initial = VideoCraftSource.bytes(
        project().source.bytes!,
        name: 'initial.mp4',
      );
      await tester.pumpWidget(
        _app(store, controller, preview, source: initial),
      );
      await tester.pumpAndSettle();
      controller.setTitle('Do not replace');
      await _tap(tester, 'video-recovery-restore');
      expect(controller.recipe!.title, 'Do not replace');
      expect((await store.read('qa.video'))!.revision, candidate.revision);
      expect(
        find.textContaining('Invalid video recovery envelope'),
        findsOneWidget,
      );
      await _tap(tester, 'video-recovery-discard');
      await _saveRecovery(tester);
      expect(
        VideoCraftRecoveryData.decode(
          (await store.read('qa.video'))!.bytes,
        ).project.recipe.title,
        'Do not replace',
      );
      await _close(tester);

      final saved = (await store.read('qa.video'))!;
      await store.memory.write(
        'qa.video',
        VideoCraftRecoveryData(project()).encode(),
        expectedRevision: saved.revision,
      );
      final current = VideoCraftController(),
          rejecting = _Preview()..reject = 'fixture.mp4';
      await tester.pumpWidget(_app(store, current, rejecting, source: initial));
      await tester.pumpAndSettle();
      current.setTitle('Current document');
      await _tap(tester, 'video-recovery-restore');
      expect(current.recipe!.title, 'Current document');
      expect(current.recipe!.sourceName, 'initial.mp4');
      expect(find.byKey(const Key('video-recovery-restore')), findsOneWidget);
      expect(find.textContaining('Decoder rejected source'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets(
    'quota is visible and retry commits instead of reporting false success',
    (tester) async {
      final store = ControlledStore()
        ..writeError = const MediaRecoveryException(
          MediaRecoveryErrorCode.quotaExceeded,
        );
      final controller = VideoCraftController();
      await tester.pumpWidget(
        _app(store, controller, _Preview(), source: project().source),
      );
      await tester.pumpAndSettle();
      controller.setTitle('Latest edit');
      await _saveRecovery(tester);
      expect(find.textContaining('quotaExceeded'), findsOneWidget);
      expect(await store.memory.read('qa.video'), isNull);
      expect(find.text('Local recovery saved on this device.'), findsNothing);
      store.writeError = null;
      await _tap(tester, 'video-recovery-retry');
      expect(find.text('Local recovery saved on this device.'), findsOneWidget);
      expect(
        VideoCraftRecoveryData.decode(
          (await store.read('qa.video'))!.bytes,
        ).project.recipe.title,
        'Latest edit',
      );
      await _close(tester);
    },
  );

  testWidgets(
    'another session conflict is visible and retry protects its candidate',
    (tester) async {
      final store = ControlledStore(), controller = VideoCraftController();
      await tester.pumpWidget(
        _app(store, controller, _Preview(), source: project().source),
      );
      await tester.pumpAndSettle();
      await _saveRecovery(tester);
      final saved = (await store.read('qa.video'))!;
      final other = VideoCraftRecoveryData(
        project(title: 'Other session'),
      ).encode();
      await store.memory.write(
        'qa.video',
        other,
        expectedRevision: saved.revision,
      );
      controller.setTitle('Keep my local edit');
      await _saveRecovery(tester);
      expect(find.textContaining('conflict'), findsOneWidget);
      expect(controller.recipe!.title, 'Keep my local edit');
      await _tap(tester, 'video-recovery-retry');
      expect(find.byKey(const Key('video-recovery-restore')), findsOneWidget);
      expect(controller.recipe!.title, 'Keep my local edit');
      expect((await store.read('qa.video'))!.bytes, other);
      await _close(tester);
    },
  );
}
