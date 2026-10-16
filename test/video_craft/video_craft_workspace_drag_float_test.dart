import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_craft_workspace/neom_craft_workspace.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

import 'video_craft_workspace_test.dart' show FakePreview, ControlledExporter;

class _Store extends MemoryCraftWorkspaceStore {
  _Store()
    : super({
        'neom_video_editor': jsonEncode({
          'format': 'open-neom-workspace',
          'schemaVersion': 1,
          'openPanels': ['timing', 'animation'],
          'activePanel': 'timing',
          'panelWidth': 640,
          'sidebarVisible': true,
        }),
      });
  int writes = 0;
  @override
  Future<void> write(String id, String value) async {
    writes++;
    await super.write(id, value);
  }

  CraftWorkspaceLayout get layout => CraftWorkspaceLayout.fromJson(
    jsonDecode(values['neom_video_editor']!) as Map<String, dynamic>,
    panelIds: const ['timing', 'animation'],
  );
}

class _Preview extends FakePreview {
  int opens = 0, mounts = 0;
  @override
  Future<void> open(VideoCraftSource source) async {
    opens++;
    await super.open(source);
  }

  @override
  Widget buildView(BuildContext context) => _View(this);
}

class _View extends StatefulWidget {
  const _View(this.preview);
  final _Preview preview;
  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  @override
  void initState() {
    super.initState();
    widget.preview.mounts++;
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: Key('float-video-preview'), color: Colors.indigo);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

Finder _tab(String panel) => find.byKey(Key('craft-workspace-tab-drag-$panel'));
Offset _point(WidgetTester tester, Offset local) =>
    tester.getTopLeft(find.byKey(const Key('craft-workspace-surface'))) + local;
Rect _visibleFloat(WidgetTester tester, String id) => tester
    .getRect(find.byKey(Key('craft-workspace-floating-$id')))
    .shift(
      -tester.getTopLeft(find.byKey(const Key('craft-workspace-surface'))),
    );
CraftWorkspaceFloating _floating(_Store store, String panel) => store
    .layout
    .floatingGroups
    .firstWhere((f) => f.group.panelIds.contains(panel));

Future<TestGesture> _hover(
  WidgetTester tester,
  _Store store,
  String panel,
  Offset target,
) async {
  await tester.ensureVisible(_tab(panel));
  final id = store.layout.groupForPanel(panel)!.id;
  final visible = tester
      .getRect(_tab(panel))
      .intersect(
        tester.getRect(find.byKey(Key('craft-workspace-tab-strip-$id'))),
      );
  expect(visible.width, greaterThan(0));
  final gesture = await tester.startGesture(
    visible.center,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(visible.center + const Offset(0, 24));
  await tester.pump();
  await gesture.moveTo(target);
  await tester.pump(const Duration(milliseconds: 120));
  return gesture;
}

Future<Rect> _freeDrop(
  WidgetTester tester,
  _Store store,
  String panel,
  Offset local,
) async {
  final writes = store.writes;
  final saved = store.values['neom_video_editor'];
  final gesture = await _hover(tester, store, panel, _point(tester, local));
  final preview = find.byKey(const Key('craft-workspace-float-preview'));
  expect(preview, findsOneWidget);
  final previewRect = tester
      .getRect(preview)
      .shift(
        -tester.getTopLeft(find.byKey(const Key('craft-workspace-surface'))),
      );
  expect(store.writes, writes);
  expect(store.values['neom_video_editor'], saved);
  await gesture.up();
  await _settle(tester);
  expect(store.writes, writes + 1);
  expect(_visibleFloat(tester, _floating(store, panel).group.id), previewRect);
  return previewRect;
}

Future<void> _merge(
  WidgetTester tester,
  _Store store,
  String panel,
  String target,
) async {
  await tester.ensureVisible(_tab(target));
  final rect = tester.getRect(_tab(target));
  final gesture = await _hover(
    tester,
    store,
    panel,
    Offset(rect.right - 4, rect.center.dy),
  );
  await gesture.up();
  await _settle(tester);
}

Future<void> _resize(
  WidgetTester tester,
  _Store store,
  String panel,
  Size size,
) async {
  final id = _floating(store, panel).group.id;
  final current = _visibleFloat(tester, id).size;
  await tester.drag(
    find.byKey(Key('craft-workspace-floating-resize-$id')),
    Offset(size.width - current.width, size.height - current.height),
  );
  await _settle(tester);
  final resized = _visibleFloat(tester, id).size;
  expect(resized.width, closeTo(size.width, .001));
  expect(resized.height, closeTo(size.height, .001));
}

void main() {
  late VideoCraftController controller;
  late _Preview preview;
  late _Store store;
  late VideoCraftSource source;
  setUp(() {
    controller = VideoCraftController();
    preview = _Preview();
    store = _Store();
    source = VideoCraftSource.bytes(Uint8List.fromList([0]), name: 'float.mp4');
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
    await _settle(tester);
  }

  testWidgets(
    'canvas drop floats and redocks video without resetting draft, player or MP4',
    (tester) async {
      viewport(tester);
      final exporter = ControlledExporter();
      Uint8List? delivered;
      await mount(
        tester,
        exporter: exporter,
        save: (bytes) async => delivered = bytes,
      );
      controller.setTitle('Only document edit');
      await _settle(tester);
      await _tap(tester, find.text('Export MP4'));
      exporter.gate.complete(Uint8List.fromList([3, 1, 4]));
      await _settle(tester);
      await _tap(
        tester,
        find.byKey(const Key('craft-workspace-tab-animation')),
      );
      await tester.enterText(
        find.byKey(const Key('video-title-input')),
        'Unapplied floating title',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      preview.advance(const Duration(seconds: 2));
      await preview.play();
      await _settle(tester);
      final recipe = controller.recipe, frame = controller.frame;
      final opens = preview.opens,
          mounts = preview.mounts,
          pauses = preview.pauses;
      final canvas = tester.element(
        find.byKey(const Key('float-video-preview')),
      );
      final initialSize = tester.getSize(
        find.byKey(
          Key(
            'craft-workspace-group-${store.layout.groupForPanel('animation')!.id}',
          ),
        ),
      );
      final created = await _freeDrop(
        tester,
        store,
        'animation',
        const Offset(260, 200),
      );
      expect(created.size, initialSize);
      expect(store.layout.dockedGroups.single.panelIds, ['timing']);
      expect(store.layout.floatingGroups.single.group.panelIds, ['animation']);
      await _resize(tester, store, 'animation', const Size(420, 360));
      await _merge(tester, store, 'animation', 'timing');
      expect(store.layout.floatingGroups, isEmpty);
      expect(store.layout.dockedGroups.single.panelIds, [
        'timing',
        'animation',
      ]);
      await _freeDrop(tester, store, 'animation', const Offset(260, 200));
      await _resize(tester, store, 'animation', const Size(450, 390));
      final id = _floating(store, 'animation').group.id;
      final savedRect = _visibleFloat(tester, id);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('video-title-input')))
            .controller!
            .text,
        'Unapplied floating title',
      );
      expect(
        identical(
          tester.element(find.byKey(const Key('float-video-preview'))),
          canvas,
        ),
        isTrue,
      );
      expect(preview.opens, opens);
      expect(preview.mounts, mounts);
      expect(preview.pauses, pauses);
      expect(preview.isPlaying, isTrue);
      expect(controller.frame, frame);
      expect(identical(controller.recipe, recipe), isTrue);
      await _tap(tester, find.text('Save rendered MP4'));
      expect(delivered, [3, 1, 4]);
      controller.undo();
      expect(controller.recipe!.title, 'Title');
      expect(controller.canUndo, isFalse);
      final saved = store.values['neom_video_editor'];
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(store.values['neom_video_editor'], saved);
      expect(_visibleFloat(tester, id), savedRect);
      expect(store.layout.dockedGroups.single.panelIds, ['timing']);
      expect(find.byKey(const Key('video-title-input')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'sole float relocates and multi-tab float detaches only the dragged tab',
    (tester) async {
      viewport(tester);
      await mount(tester);
      await _freeDrop(tester, store, 'animation', const Offset(260, 200));
      await _resize(tester, store, 'animation', const Size(420, 360));
      final id = _floating(store, 'animation').group.id;
      final beforeMove = _visibleFloat(tester, id);
      final preferredBeforeMove = _floating(store, 'animation').rect;
      final moved = await _freeDrop(
        tester,
        store,
        'animation',
        const Offset(850, 200),
      );
      expect(_floating(store, 'animation').group.id, id);
      expect(moved.topLeft, isNot(beforeMove.topLeft));
      expect(moved.width, closeTo(beforeMove.width, .001));
      expect(moved.height, closeTo(beforeMove.height, .001));
      expect(
        _floating(store, 'animation').rect.width,
        preferredBeforeMove.width,
      );
      expect(
        _floating(store, 'animation').rect.height,
        preferredBeforeMove.height,
      );
      await _merge(tester, store, 'timing', 'animation');
      expect(store.layout.root, isNull);
      expect(store.layout.floatingGroups.single.group.panelIds, [
        'animation',
        'timing',
      ]);
      final sourceRect = _visibleFloat(tester, id);
      final detached = await _freeDrop(
        tester,
        store,
        'timing',
        const Offset(240, 560),
      );
      expect(store.layout.floatingGroups.length, 2);
      expect(_floating(store, 'animation').group.id, id);
      expect(_floating(store, 'animation').group.panelIds, ['animation']);
      expect(_floating(store, 'timing').group.panelIds, ['timing']);
      expect(_floating(store, 'timing').group.id, isNot(id));
      expect(_visibleFloat(tester, id), sourceRect);
      expect(detached.width, closeTo(sourceRect.width, .001));
      expect(detached.height, closeTo(sourceRect.height, .001));
      expect(preview.opens, 1);
      expect(preview.mounts, 1);
      expect(controller.canUndo, isFalse);
      final rects = {
        for (final f in store.layout.floatingGroups)
          f.group.id: _visibleFloat(tester, f.group.id),
      };
      final saved = store.values['neom_video_editor'];
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(store.values['neom_video_editor'], saved);
      for (final entry in rects.entries) {
        expect(_visibleFloat(tester, entry.key), entry.value);
      }
      expect(store.layout.root, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('free-space cancellation, outside drop and headers never write', (
    tester,
  ) async {
    viewport(tester);
    await mount(tester);
    final saved = store.values['neom_video_editor'], writes = store.writes;
    var gesture = await _hover(
      tester,
      store,
      'animation',
      _point(tester, const Offset(260, 200)),
    );
    expect(
      find.byKey(const Key('craft-workspace-float-preview')),
      findsOneWidget,
    );
    await gesture.cancel();
    await _settle(tester);
    gesture = await _hover(
      tester,
      store,
      'animation',
      _point(tester, const Offset(260, 200)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await gesture.up();
    await _settle(tester);
    final id = store.layout.groupForPanel('timing')!.id;
    for (final point in [
      const Offset(-20, -20),
      tester.getCenter(find.byKey(Key('craft-workspace-group-menu-$id'))),
    ]) {
      gesture = await _hover(tester, store, 'animation', point);
      expect(
        find.byKey(const Key('craft-workspace-float-preview')),
        findsNothing,
      );
      await gesture.up();
      await _settle(tester);
    }
    expect(store.writes, writes);
    expect(store.values['neom_video_editor'], saved);
    await _freeDrop(tester, store, 'animation', const Offset(260, 200));
    await _resize(tester, store, 'animation', const Size(420, 360));
    final current = store.values['neom_video_editor'], count = store.writes;
    final floatId = _floating(store, 'animation').group.id;
    gesture = await _hover(
      tester,
      store,
      'timing',
      tester.getCenter(
        find.byKey(Key('craft-workspace-floating-header-$floatId')),
      ),
    );
    expect(
      find.byKey(const Key('craft-workspace-float-preview')),
      findsNothing,
    );
    await gesture.up();
    await _settle(tester);
    expect(store.writes, count);
    expect(store.values['neom_video_editor'], current);
    expect(controller.canUndo, isFalse);
    expect(preview.mounts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
