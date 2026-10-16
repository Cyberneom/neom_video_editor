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
  Future<void> write(String workspaceId, String value) async {
    writes++;
    await super.write(workspaceId, value);
  }

  CraftWorkspaceLayout get layout => CraftWorkspaceLayout.fromJson(
    jsonDecode(values['neom_video_editor']!) as Map<String, dynamic>,
    panelIds: const ['timing', 'animation'],
  );
}

class _Preview extends FakePreview {
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
  Widget build(BuildContext context) => const ColoredBox(
    key: Key('tab-drag-video-preview'),
    color: Colors.indigo,
  );
}

Finder _tab(String panel) => find.byKey(Key('craft-workspace-tab-drag-$panel'));

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

Future<TestGesture> _hover(
  WidgetTester tester,
  String panel,
  Offset target,
) async {
  await tester.ensureVisible(_tab(panel));
  final start = tester.getCenter(_tab(panel));
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(start + const Offset(0, 24));
  await tester.pump();
  await gesture.moveTo(target);
  await tester.pump(const Duration(milliseconds: 120));
  return gesture;
}

Future<void> _drag(
  WidgetTester tester,
  String panel,
  String target, {
  bool after = false,
}) async {
  await tester.ensureVisible(_tab(target));
  final rect = tester.getRect(_tab(target));
  final point = Offset(after ? rect.right - 4 : rect.left + 4, rect.center.dy);
  final gesture = await _hover(tester, panel, point);
  await gesture.up();
  await _settle(tester);
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
    source = VideoCraftSource.bytes(Uint8List.fromList([0]), name: 'tabs.mp4');
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
    'tab drags preserve playback, draft, MP4 and exact restored order',
    (tester) async {
      viewport(tester);
      final exporter = ControlledExporter();
      Uint8List? delivered;
      await mount(
        tester,
        exporter: exporter,
        save: (bytes) async => delivered = bytes,
      );
      controller.setTitle('One actual document edit');
      await _settle(tester);
      await _tap(tester, find.text('Export MP4'));
      exporter.gate.complete(Uint8List.fromList([5, 6, 7]));
      await _settle(tester);
      await _tap(
        tester,
        find.byKey(const Key('craft-workspace-tab-animation')),
      );
      await tester.enterText(
        find.byKey(const Key('video-title-input')),
        'Unapplied title draft',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      preview.advance(const Duration(seconds: 2));
      await preview.play();
      await _settle(tester);
      final recipe = controller.recipe;
      final frame = controller.frame;
      final opens = preview.opens,
          mounts = preview.mounts,
          pauses = preview.pauses;
      final canvas = tester.element(
        find.byKey(const Key('tab-drag-video-preview')),
      );

      final writes = store.writes;
      await _drag(tester, 'animation', 'timing');
      expect(store.layout.groups.single.panelIds, ['animation', 'timing']);
      expect(store.writes, writes + 1);

      await _tap(tester, find.byKey(const Key('craft-workspace-tab-timing')));
      await _action(tester, store, 'timing', 'split-vertical');
      await _action(tester, store, 'timing', 'float');
      expect(store.layout.dockedGroups.length, 1);
      expect(store.layout.floatingGroups.length, 1);
      await _drag(tester, 'animation', 'timing', after: true);
      expect(
        store.layout.root,
        isNull,
        reason: 'The emptied dock group collapses.',
      );
      expect(store.layout.floatingGroups.single.group.panelIds, [
        'timing',
        'animation',
      ]);

      await _action(tester, store, 'animation', 'dock');
      await _drag(tester, 'timing', 'animation');
      expect(
        store.layout.floatingGroups,
        isEmpty,
        reason: 'The emptied float closes.',
      );
      expect(store.layout.dockedGroups.single.panelIds, [
        'timing',
        'animation',
      ]);
      await _drag(tester, 'animation', 'timing');
      expect(store.layout.dockedGroups.single.panelIds, [
        'animation',
        'timing',
      ]);
      await _action(tester, store, 'animation', 'float');
      await _drag(tester, 'timing', 'animation', after: true);
      expect(store.layout.root, isNull);
      expect(store.layout.floatingGroups.single.group.panelIds, [
        'animation',
        'timing',
      ]);
      await _tap(
        tester,
        find.byKey(const Key('craft-workspace-tab-animation')),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('video-title-input')))
            .controller!
            .text,
        'Unapplied title draft',
      );
      expect(
        identical(
          tester.element(find.byKey(const Key('tab-drag-video-preview'))),
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
      expect(delivered, [5, 6, 7]);
      controller.undo();
      expect(controller.recipe!.title, 'Title');
      expect(controller.canUndo, isFalse);

      final persisted = store.values['neom_video_editor'];
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(store.values['neom_video_editor'], persisted);
      expect(store.layout.root, isNull);
      expect(store.layout.floatingGroups.single.group.panelIds, [
        'animation',
        'timing',
      ]);
      expect(
        tester.getTopLeft(_tab('animation')).dx,
        lessThan(tester.getTopLeft(_tab('timing')).dx),
      );
      expect(find.byKey(const Key('video-title-input')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'invalid drop, pointer cancellation and Escape never write or edit',
    (tester) async {
      viewport(tester);
      await mount(tester);
      final persisted = store.values['neom_video_editor'];
      final writes = store.writes;
      final recipe = controller.recipe;
      final mounts = preview.mounts;
      var gesture = await _hover(tester, 'timing', const Offset(-20, -20));
      expect(
        store.writes,
        writes,
        reason: 'Hover cannot persist a speculative layout.',
      );
      await gesture.up();
      await _settle(tester);
      final target = tester.getRect(_tab('animation'));
      gesture = await _hover(
        tester,
        'timing',
        Offset(target.right - 4, target.center.dy),
      );
      await gesture.cancel();
      await _settle(tester);
      gesture = await _hover(
        tester,
        'timing',
        Offset(target.right - 4, target.center.dy),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await gesture.up();
      await _settle(tester);
      expect(store.writes, writes);
      expect(store.values['neom_video_editor'], persisted);
      expect(identical(controller.recipe, recipe), isTrue);
      expect(controller.canUndo, isFalse);
      expect(preview.mounts, mounts);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
