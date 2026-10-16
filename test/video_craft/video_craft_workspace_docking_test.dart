import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_craft_workspace/neom_craft_workspace.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

import 'video_craft_workspace_test.dart' show FakePreview, ControlledExporter;

class _DockingPreview extends FakePreview {
  int opens = 0;
  int mounts = 0;

  @override
  Future<void> open(VideoCraftSource source) async {
    opens++;
    await super.open(source);
  }

  @override
  Widget buildView(BuildContext context) => _PreviewView(this);
}

class _PreviewView extends StatefulWidget {
  const _PreviewView(this.preview);
  final _DockingPreview preview;

  @override
  State<_PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<_PreviewView> {
  @override
  void initState() {
    super.initState();
    widget.preview.mounts++;
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: Key('docking-video-preview'), color: Colors.indigo);
}

CraftWorkspaceLayout _layout(MemoryCraftWorkspaceStore store) =>
    CraftWorkspaceLayout.fromJson(
      jsonDecode(store.values['neom_video_editor']!) as Map<String, dynamic>,
      panelIds: const ['timing', 'animation'],
    );

Rect _surfaceRect(WidgetTester tester, Finder floating) => tester
    .getRect(floating)
    .shift(
      -tester.getTopLeft(find.byKey(const Key('craft-workspace-surface'))),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _action(
  WidgetTester tester,
  MemoryCraftWorkspaceStore store,
  String panel,
  String label,
) async {
  final group = _layout(store).groupForPanel(panel)!;
  await _tap(tester, find.byKey(Key('craft-workspace-group-menu-${group.id}')));
  final action = switch (label) {
    'Dividir lado a lado' => 'split-horizontal',
    'Dividir arriba y abajo' => 'split-vertical',
    'Convertir en ventana flotante' => 'float',
    'Acoplar al inspector' => 'dock',
    _ => throw ArgumentError.value(label),
  };
  await _tap(
    tester,
    find.byKey(Key('craft-workspace-action-${group.id}-$action')),
  );
}

void main() {
  late VideoCraftController controller;
  late _DockingPreview preview;
  late MemoryCraftWorkspaceStore store;
  late VideoCraftSource source;

  setUp(() {
    controller = VideoCraftController();
    preview = _DockingPreview();
    store = MemoryCraftWorkspaceStore();
    source = VideoCraftSource.bytes(
      Uint8List.fromList([0]),
      name: 'docking.mp4',
    );
  });

  tearDown(() {
    controller.dispose();
    preview.dispose();
  });

  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> mount(
    WidgetTester tester, {
    ControlledExporter? exporter,
    Future<void> Function(Uint8List)? save,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCraftWorkspace(
            controller: controller,
            previewBackend: preview,
            source: source,
            workspaceStore: store,
            trimExporter: exporter,
            onExportVideo: save,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (action, horizontal) in [
    ('Dividir lado a lado', true),
    ('Dividir arriba y abajo', false),
  ]) {
    testWidgets('$action and floating preserve playback, drafts and history', (
      tester,
    ) async {
      viewport(tester);
      await mount(tester);
      controller.setTitle('One document edit');
      preview.advance(const Duration(seconds: 2));
      await preview.play();
      await tester.pumpAndSettle();
      final recipe = controller.recipe;
      final opens = preview.opens, mounts = preview.mounts;
      final pauses = preview.pauses, frame = controller.frame;
      await _tap(
        tester,
        find.byKey(const Key('craft-workspace-tab-animation')),
      );
      await tester.enterText(
        find.byKey(const Key('video-title-input')),
        'Draft survives docking',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _action(tester, store, 'animation', action);
      expect(_layout(store).dockedGroups.length, 2);
      expect(find.byKey(const Key('video-timing-scroll')), findsOneWidget);
      expect(find.byKey(const Key('video-animation-scroll')), findsOneWidget);
      final timing = tester.getRect(
        find.byKey(const Key('video-timing-scroll')),
      );
      final animation = tester.getRect(
        find.byKey(const Key('video-animation-scroll')),
      );
      if (horizontal) {
        expect(timing.left, isNot(closeTo(animation.left, 2)));
        expect(timing.top, closeTo(animation.top, 2));
      } else {
        expect(timing.top, isNot(closeTo(animation.top, 2)));
        expect(timing.left, closeTo(animation.left, 2));
      }
      await _action(
        tester,
        store,
        'animation',
        'Convertir en ventana flotante',
      );
      final groupId = _layout(store).groupForPanel('animation')!.id;
      final floating = find.byKey(Key('craft-workspace-floating-$groupId'));
      final before = tester.getRect(floating);
      await tester.drag(
        find.byKey(Key('craft-workspace-floating-header-$groupId')),
        const Offset(-100, 60),
      );
      await tester.pumpAndSettle();
      final moved = tester.getRect(floating);
      expect(moved.topLeft, isNot(before.topLeft));
      await tester.drag(
        find.byKey(Key('craft-workspace-floating-resize-$groupId')),
        const Offset(70, 50),
      );
      await tester.pumpAndSettle();
      final resized = tester.getRect(floating);
      expect(resized.width, greaterThan(moved.width));
      expect(resized.height, greaterThan(moved.height));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('video-title-input')))
            .controller!
            .text,
        'Draft survives docking',
      );
      await _action(tester, store, 'animation', 'Acoplar al inspector');
      expect(_layout(store).floatingGroups, isEmpty);
      expect(find.byKey(const Key('video-title-input')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('video-title-input')))
            .controller!
            .text,
        'Draft survives docking',
      );
      expect(find.byKey(const Key('docking-video-preview')), findsOneWidget);
      expect(preview.opens, opens);
      expect(preview.mounts, mounts);
      expect(preview.pauses, pauses);
      expect(preview.isPlaying, isTrue);
      expect(controller.frame, frame);
      expect(identical(controller.recipe, recipe), isTrue);
      controller.undo();
      expect(controller.recipe!.title, 'Title');
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('floating layout restores and docking retains prepared MP4', (
    tester,
  ) async {
    viewport(tester);
    final exporter = ControlledExporter();
    Uint8List? delivered;
    await mount(
      tester,
      exporter: exporter,
      save: (bytes) async => delivered = bytes,
    );
    await _tap(tester, find.text('Export MP4'));
    exporter.gate.complete(Uint8List.fromList([7, 8, 9]));
    await tester.pumpAndSettle();
    final recipe = controller.recipe;
    await _tap(tester, find.byKey(const Key('craft-workspace-tab-animation')));
    await _action(tester, store, 'animation', 'Dividir arriba y abajo');
    await _action(tester, store, 'animation', 'Convertir en ventana flotante');
    final groupId = _layout(store).groupForPanel('animation')!.id;
    await tester.drag(
      find.byKey(Key('craft-workspace-floating-header-$groupId')),
      const Offset(-90, 50),
    );
    await tester.pumpAndSettle();
    final savedRect = _surfaceRect(
      tester,
      find.byKey(Key('craft-workspace-floating-$groupId')),
    );
    expect(find.text('Save rendered MP4'), findsOneWidget);
    await _tap(tester, find.text('Save rendered MP4'));
    expect(delivered, [7, 8, 9]);
    expect(identical(controller.recipe, recipe), isTrue);
    expect(controller.canUndo, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester);
    final restoredRect = _surfaceRect(
      tester,
      find.byKey(Key('craft-workspace-floating-$groupId')),
    );
    expect(restoredRect, savedRect);
    expect(find.byKey(const Key('video-title-input')), findsOneWidget);
    expect(find.byKey(const Key('video-timing-scroll')), findsOneWidget);
    await _action(tester, store, 'animation', 'Acoplar al inspector');
    expect(_layout(store).floatingGroups, isEmpty);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
