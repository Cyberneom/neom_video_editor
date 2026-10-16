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
  Widget buildView(BuildContext context) => _PreviewView(this);
}

class _PreviewView extends StatefulWidget {
  const _PreviewView(this.preview);
  final _Preview preview;
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
      const ColoredBox(key: Key('edge-video-preview'), color: Colors.indigo);
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

Future<void> _action(
  WidgetTester tester,
  _Store store,
  String panel,
  String action,
) async {
  final id = store.layout.groupForPanel(panel)!.id;
  await _tap(tester, find.byKey(Key('craft-workspace-group-menu-$id')));
  await _tap(tester, find.byKey(Key('craft-workspace-action-$id-$action')));
}

Offset _edge(Rect body, String edge) => switch (edge) {
  'left' => Offset(body.left + body.width * .02, body.center.dy),
  'right' => Offset(body.right - body.width * .02, body.center.dy),
  'top' => Offset(body.center.dx, body.top + body.height * .02),
  'bottom' => Offset(body.center.dx, body.bottom - body.height * .02),
  _ => throw ArgumentError.value(edge),
};

Future<TestGesture> _hover(
  WidgetTester tester,
  _Store store,
  String source,
  Offset target,
) async {
  final tab = find.byKey(Key('craft-workspace-tab-drag-$source'));
  await tester.ensureVisible(tab);
  final sourceId = store.layout.groupForPanel(source)!.id;
  final visible = tester
      .getRect(tab)
      .intersect(
        tester.getRect(find.byKey(Key('craft-workspace-tab-strip-$sourceId'))),
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

Future<TestGesture> _hoverEdge(
  WidgetTester tester,
  _Store store,
  String source,
  String target,
  String edge, {
  bool preview = true,
}) async {
  final id = store.layout.groupForPanel(target)!.id;
  final body = tester.getRect(
    find.byKey(Key('craft-workspace-group-body-$id')),
  );
  final group = tester.getRect(find.byKey(Key('craft-workspace-group-$id')));
  final writes = store.writes;
  final saved = store.values['neom_video_editor'];
  final gesture = await _hover(tester, store, source, _edge(body, edge));
  final indicator = find.byKey(Key('craft-workspace-edge-preview-$id-$edge'));
  expect(indicator, preview ? findsOneWidget : findsNothing);
  if (preview) {
    final rect = tester.getRect(indicator);
    final expected = switch (edge) {
      'left' => Rect.fromLTRB(
        group.left,
        group.top,
        group.center.dx,
        group.bottom,
      ),
      'right' => Rect.fromLTRB(
        group.center.dx,
        group.top,
        group.right,
        group.bottom,
      ),
      'top' => Rect.fromLTRB(
        group.left,
        group.top,
        group.right,
        group.center.dy,
      ),
      _ => Rect.fromLTRB(
        group.left,
        group.center.dy,
        group.right,
        group.bottom,
      ),
    };
    expect(rect.left, closeTo(expected.left, 1));
    expect(rect.top, closeTo(expected.top, 1));
    expect(rect.width, closeTo(expected.width, 1));
    expect(rect.height, closeTo(expected.height, 1));
  }
  expect(
    store.writes,
    writes,
    reason: 'Edge preview must not persist a speculative tree.',
  );
  expect(store.values['neom_video_editor'], saved);
  return gesture;
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
    source = VideoCraftSource.bytes(Uint8List.fromList([0]), name: 'edge.mp4');
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

  for (final edge in ['left', 'right', 'top', 'bottom']) {
    testWidgets(
      '$edge edge splits from dock and float preserve playback and MP4',
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
        exporter.gate.complete(Uint8List.fromList([4, 2, 8]));
        await _settle(tester);
        await _tap(
          tester,
          find.byKey(const Key('craft-workspace-tab-animation')),
        );
        await tester.enterText(
          find.byKey(const Key('video-title-input')),
          'Draft across edge splits',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        preview.advance(const Duration(seconds: 3));
        await preview.play();
        await _settle(tester);
        final recipe = controller.recipe;
        final frame = controller.frame;
        final opens = preview.opens,
            mounts = preview.mounts,
            pauses = preview.pauses;
        final canvas = tester.element(
          find.byKey(const Key('edge-video-preview')),
        );

        final writes = store.writes;
        var gesture = await _hoverEdge(
          tester,
          store,
          'animation',
          'timing',
          edge,
        );
        await gesture.up();
        await _settle(tester);
        expect(store.writes, writes + 1);
        final horizontal = edge == 'left' || edge == 'right';
        final before = edge == 'left' || edge == 'top';
        final first = store.layout.root as CraftWorkspaceSplit;
        expect(
          first.axis,
          horizontal
              ? CraftWorkspaceAxis.horizontal
              : CraftWorkspaceAxis.vertical,
        );
        expect(first.ratio, .5);
        expect((first.first as CraftWorkspaceGroup).panelIds, [
          before ? 'animation' : 'timing',
        ]);
        expect((first.second as CraftWorkspaceGroup).panelIds, [
          before ? 'timing' : 'animation',
        ]);

        await _action(tester, store, 'animation', 'float');
        final floatingId = store.layout.groupForPanel('animation')!.id;
        await tester.drag(
          find.byKey(Key('craft-workspace-floating-header-$floatingId')),
          const Offset(-720, 100),
        );
        await _settle(tester);
        gesture = await _hoverEdge(tester, store, 'animation', 'timing', edge);
        await gesture.up();
        await _settle(tester);
        expect(store.layout.floatingGroups, isEmpty);
        final split = store.layout.root as CraftWorkspaceSplit;
        expect(split.axis, first.axis);
        expect((split.first as CraftWorkspaceGroup).panelIds, [
          before ? 'animation' : 'timing',
        ]);
        expect((split.second as CraftWorkspaceGroup).panelIds, [
          before ? 'timing' : 'animation',
        ]);
        await tester.drag(
          find.byKey(Key('craft-workspace-split-${split.id}')),
          horizontal ? const Offset(45, 0) : const Offset(0, 65),
        );
        await _settle(tester);
        final savedRatio = (store.layout.root as CraftWorkspaceSplit).ratio;
        expect(savedRatio, greaterThan(.5));
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('video-title-input')))
              .controller!
              .text,
          'Draft across edge splits',
        );
        expect(
          identical(
            tester.element(find.byKey(const Key('edge-video-preview'))),
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
        expect(delivered, [4, 2, 8]);
        controller.undo();
        expect(controller.recipe!.title, 'Title');
        expect(controller.canUndo, isFalse);

        final persisted = store.values['neom_video_editor'];
        final ids = store.layout.dockedGroups.map((g) => g.panelIds).toList();
        await tester.pumpWidget(const SizedBox.shrink());
        await mount(tester);
        expect(store.values['neom_video_editor'], persisted);
        expect((store.layout.root as CraftWorkspaceSplit).ratio, savedRatio);
        expect(store.layout.dockedGroups.map((g) => g.panelIds).toList(), ids);
        expect(find.byKey(const Key('video-animation-scroll')), findsOneWidget);
        expect(find.byKey(const Key('video-timing-scroll')), findsOneWidget);
        final a = tester.getRect(
          find.byKey(const Key('video-animation-scroll')),
        );
        final t = tester.getRect(find.byKey(const Key('video-timing-scroll')));
        expect(horizontal ? a.left < t.left : a.top < t.top, before);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'cancelled edge proposals and outside-workspace drops never write',
    (tester) async {
      viewport(tester);
      await mount(tester);
      final saved = store.values['neom_video_editor'];
      final writes = store.writes;
      final recipe = controller.recipe;
      var gesture = await _hoverEdge(
        tester,
        store,
        'animation',
        'timing',
        'left',
      );
      await gesture.cancel();
      await _settle(tester);
      gesture = await _hoverEdge(
        tester,
        store,
        'animation',
        'timing',
        'bottom',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await gesture.up();
      await _settle(tester);
      gesture = await _hover(
        tester,
        store,
        'animation',
        const Offset(-20, -20),
      );
      await gesture.up();
      await _settle(tester);
      expect(store.writes, writes);
      expect(store.values['neom_video_editor'], saved);
      expect(identical(controller.recipe, recipe), isTrue);
      expect(controller.canUndo, isFalse);
      expect(preview.mounts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'floating destination edges merge tabs without creating a split',
    (tester) async {
      viewport(tester);
      await mount(tester);
      await _tap(
        tester,
        find.byKey(const Key('craft-workspace-tab-animation')),
      );
      await _action(tester, store, 'animation', 'float');
      final id = store.layout.groupForPanel('animation')!.id;
      await tester.drag(
        find.byKey(Key('craft-workspace-floating-header-$id')),
        const Offset(-720, 100),
      );
      await _settle(tester);
      final gesture = await _hoverEdge(
        tester,
        store,
        'timing',
        'animation',
        'left',
        preview: false,
      );
      await gesture.up();
      await _settle(tester);
      expect(store.layout.root, isNull);
      expect(store.layout.floatingGroups.single.group.panelIds, [
        'animation',
        'timing',
      ]);
      expect(store.layout.groups.length, 1);
      expect(controller.canUndo, isFalse);
      expect(preview.mounts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
