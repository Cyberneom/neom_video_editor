import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

Uint8List _media() => Uint8List.fromList([
  0,
  0,
  0,
  24,
  102,
  116,
  121,
  112,
  105,
  115,
  111,
  109,
  ...List.generate(128, (i) => i),
]);
VideoCraftSource _source(String name) => VideoCraftSource.bytes(
  _media(),
  name: name,
  frameRate: CraftFrameRate(24, 1),
);
VideoCraftProject _project({String name = 'saved.mp4', int seconds = 8}) =>
    VideoCraftProject(
      source: _source(name),
      recipe: VideoCraftRecipe(
        sourceName: name,
        duration: Duration(seconds: seconds),
        frameRate: CraftFrameRate(24, 1),
        inFrame: 24,
        outFrame: 120,
        title: 'Proyecto musical',
        opacityKeys: const {24: 1, 72: .5, 119: 0},
      ),
      frame: 72,
    );

class _Preview extends VideoCraftPreviewBackend {
  String? reject;
  final opened = <String>[];
  VideoCraftSource? source;
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
    opened.add(source.name);
    if (source.name == reject) throw StateError('Decoder rejected source');
    this.source = source;
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

Widget _app(
  VideoCraftController controller,
  _Preview preview, {
  VideoCraftSource? source,
  Future<Uint8List?> Function()? open,
  Future<void> Function(Uint8List)? save,
  bool active = true,
}) => MaterialApp(
  home: Scaffold(
    body: VideoCraftWorkspace(
      workspaceStore: MemoryCraftWorkspaceStore(),
      key: const Key('project-workspace'),
      controller: controller,
      previewBackend: preview,
      source: source,
      onOpenProject: open,
      onSaveProject: save,
      active: active,
    ),
  ),
);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'save and reopen in a fresh editor restores media, edits and frame',
    (tester) async {
      final first = VideoCraftController(), second = VideoCraftController();
      final p1 = _Preview(), p2 = _Preview();
      Uint8List? saved;
      await tester.pumpWidget(
        _app(
          first,
          p1,
          source: _source('original.mp4'),
          save: (bytes) async {
            saved = bytes;
          },
        ),
      );
      await tester.pumpAndSettle();
      first.setTitle('Título editado');
      first.setTrim(24, 120);
      first.setFrame(72);
      first.putOpacityKey(.35);
      final recipe = first.recipe!.encode();
      await tester.pump();
      await _tap(tester, 'video-save-project');
      expect(saved, isNotNull);
      expect(VideoCraftProject.decode(saved!).source.bytes, _media());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(second, p2, open: () async => saved));
      await tester.pumpAndSettle();
      expect(second.recipe, isNull);
      await _tap(tester, 'video-open-project');
      expect(second.recipe!.encode(), recipe);
      expect(second.frame, 72);
      expect(second.canUndo, isFalse);
      expect(p2.source!.bytes, _media());
      expect(p2.position, const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
      p1.dispose();
      p2.dispose();
    },
  );

  for (final failure in ['corrupt', 'decoder', 'duration']) {
    testWidgets(
      '$failure project leaves the current recipe, media and undo usable',
      (tester) async {
        final controller = VideoCraftController(), preview = _Preview();
        final project = _project(seconds: failure == 'duration' ? 9 : 8);
        final bytes = project.encode();
        if (failure == 'corrupt') bytes[bytes.length - 1] ^= 1;
        if (failure == 'decoder') preview.reject = 'saved.mp4';
        await tester.pumpWidget(
          _app(
            controller,
            preview,
            source: _source('current.mp4'),
            open: () async => bytes,
          ),
        );
        await tester.pumpAndSettle();
        controller.setTitle('Unsaved work');
        controller.setFrame(48);
        final before = controller.recipe!.encode();
        await tester.pump();
        await _tap(tester, 'video-open-project');
        expect(controller.recipe!.encode(), before);
        expect(controller.frame, 48);
        expect(controller.canUndo, isTrue);
        expect(preview.source!.name, 'current.mp4');
        if (failure == 'corrupt') expect(preview.opened, ['current.mp4']);
        expect(find.byKey(const Key('video-status')), findsOneWidget);
        controller.undo();
        expect(controller.recipe!.title, 'Title');
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        preview.dispose();
      },
    );
  }

  testWidgets('late project picker cannot replace a newer host source', (
    tester,
  ) async {
    final controller = VideoCraftController(), preview = _Preview();
    final picker = Completer<Uint8List?>();
    Future<Uint8List?> open() => picker.future;
    await tester.pumpWidget(
      _app(controller, preview, source: _source('first.mp4'), open: open),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('video-open-project')));
    await tester.pump();
    await tester.pumpWidget(
      _app(controller, preview, source: _source('newer.mp4'), open: open),
    );
    await tester.pumpAndSettle();
    picker.complete(_project().encode());
    await tester.pumpAndSettle();
    expect(controller.recipe!.sourceName, 'newer.mp4');
    expect(preview.opened, ['first.mp4', 'newer.mp4']);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    preview.dispose();
  });

  testWidgets(
    'Ctrl/Cmd+S save the focused active workspace; inactive does not save',
    (tester) async {
      final controller = VideoCraftController(), preview = _Preview();
      final source = _source('keys.mp4');
      var saves = 0;
      Future<void> save(Uint8List bytes) async {
        saves++;
      }

      await tester.pumpWidget(
        _app(controller, preview, source: source, save: save),
      );
      await tester.pumpAndSettle();
      Future<void> shortcut(LogicalKeyboardKey modifier) async {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
      }

      await shortcut(LogicalKeyboardKey.controlLeft);
      await shortcut(LogicalKeyboardKey.metaLeft);
      expect(saves, 2);
      await tester.pumpWidget(
        _app(controller, preview, source: source, save: save, active: false),
      );
      await tester.pumpAndSettle();
      await shortcut(LogicalKeyboardKey.controlLeft);
      await shortcut(LogicalKeyboardKey.metaLeft);
      expect(saves, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      preview.dispose();
    },
  );

  testWidgets('cancelled project save leaves edits available for retry', (
    tester,
  ) async {
    final controller = VideoCraftController(), preview = _Preview();
    var calls = 0;
    Uint8List? delivered;
    await tester.pumpWidget(
      _app(
        controller,
        preview,
        source: _source('retry.mp4'),
        save: (bytes) async {
          if (++calls == 1) throw StateError('Save cancelled');
          delivered = bytes;
        },
      ),
    );
    await tester.pumpAndSettle();
    controller.setTitle('Keep me');
    await tester.pump();
    await _tap(tester, 'video-save-project');
    expect(delivered, isNull);
    expect(controller.recipe!.title, 'Keep me');
    expect(find.textContaining('Save cancelled'), findsOneWidget);
    await _tap(tester, 'video-save-project');
    expect(VideoCraftProject.decode(delivered!).recipe.title, 'Keep me');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    preview.dispose();
  });
}
