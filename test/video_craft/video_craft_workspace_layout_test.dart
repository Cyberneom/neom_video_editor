import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

import 'video_craft_workspace_test.dart'
    show FakePreview, FakeExporter, ControlledExporter;

class _MountAwarePreview extends FakePreview {
  int opens = 0;
  int viewMounts = 0;

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
  final _MountAwarePreview preview;

  @override
  State<_PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<_PreviewView> {
  @override
  void initState() {
    super.initState();
    widget.preview.viewMounts++;
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.blue, key: Key('stable-video-preview'));
}

void main() {
  late VideoCraftController controller;
  late _MountAwarePreview preview;
  late MemoryCraftWorkspaceStore store;
  late VideoCraftSource source;

  setUp(() {
    controller = VideoCraftController();
    preview = _MountAwarePreview();
    store = MemoryCraftWorkspaceStore();
    source = VideoCraftSource.bytes(
      Uint8List.fromList([0]),
      name: 'layout.mp4',
    );
  });

  tearDown(() {
    controller.dispose();
    preview.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCraftWorkspace(
            controller: controller,
            previewBackend: preview,
            source: source,
            workspaceStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'desktop resize and inspector switches preserve media, recipe and undo',
    (tester) async {
      size(tester, const Size(1200, 850));
      await mount(tester);
      controller.setTitle('Only document edit');
      preview.advance(const Duration(seconds: 2));
      await preview.play();
      await tester.pumpAndSettle();
      final recipe = controller.recipe!;
      final opens = preview.opens, mounts = preview.viewMounts;
      final pauses = preview.pauses, frame = controller.frame;
      final divider = find.byKey(const Key('craft-workspace-divider'));
      final before = tester.getCenter(divider);
      await tester.drag(divider, const Offset(-90, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(divider).dx, lessThan(before.dx));
      await tap(tester, 'craft-workspace-tab-animation');
      expect(find.byKey(const Key('video-title-input')), findsOneWidget);
      await tap(tester, 'craft-workspace-toggle-sidebar');
      expect(find.byKey(const Key('stable-video-preview')), findsOneWidget);
      await tap(tester, 'craft-workspace-toggle-sidebar');
      await tap(tester, 'craft-workspace-tab-timing');
      expect(identical(controller.recipe, recipe), isTrue);
      expect(controller.frame, frame);
      expect(preview.opens, opens);
      expect(preview.viewMounts, mounts);
      expect(preview.pauses, pauses);
      expect(preview.isPlaying, isTrue);
      controller.undo();
      expect(controller.recipe!.title, 'Title');
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('width, active panel and visibility survive fresh workspace', (
    tester,
  ) async {
    size(tester, const Size(1200, 850));
    await mount(tester);
    final divider = find.byKey(const Key('craft-workspace-divider'));
    await tester.drag(divider, const Offset(-90, 0));
    await tester.pumpAndSettle();
    final savedPosition = tester.getCenter(divider).dx;
    await tap(tester, 'craft-workspace-tab-animation');
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester);
    expect(tester.getCenter(divider).dx, closeTo(savedPosition, 1));
    expect(find.byKey(const Key('video-title-input')), findsOneWidget);
    expect(controller.canUndo, isFalse);
    await tap(tester, 'craft-workspace-toggle-sidebar');
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester);
    expect(divider, findsNothing);
    await tap(tester, 'craft-workspace-toggle-sidebar');
    expect(find.byKey(const Key('video-title-input')), findsOneWidget);
    expect(tester.getCenter(divider).dx, closeTo(savedPosition, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    '390px stacked layout and desktop transition retain preview and drafts',
    (tester) async {
      size(tester, const Size(1200, 850));
      await mount(tester);
      await tap(tester, 'craft-workspace-tab-animation');
      await tester.enterText(
        find.byKey(const Key('video-title-input')),
        'Uncommitted inspector draft',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final recipe = controller.recipe!;
      final opens = preview.opens, mounts = preview.viewMounts;
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final canvas = tester.getRect(
        find.byKey(const Key('video-canvas-scroll')),
      );
      final inspector = tester.getRect(
        find.byKey(const Key('video-animation-scroll')),
      );
      expect(inspector.top, greaterThanOrEqualTo(canvas.bottom));
      expect(
        find.byKey(const Key('craft-workspace-divider')),
        findsNothing,
        reason: 'The compact inspector has a bounded height, not a width drag.',
      );
      await tap(tester, 'craft-workspace-tab-timing');
      await tap(tester, 'craft-workspace-tab-animation');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('video-title-input')))
            .controller!
            .text,
        'Uncommitted inspector draft',
      );
      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpAndSettle();
      expect(preview.opens, opens);
      expect(preview.viewMounts, mounts);
      expect(identical(controller.recipe, recipe), isTrue);
      expect(controller.canUndo, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final viewport in [const Size(900, 560), const Size(390, 640)]) {
    testWidgets(
      'short ${viewport.width.toInt()}px viewport keeps timecode and transport reachable above navigation',
      (tester) async {
        size(tester, viewport);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Media host'),
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(24),
                  child: SizedBox(height: 24),
                ),
              ),
              bottomNavigationBar: NavigationBar(
                key: const Key('host-navigation'),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.image),
                    label: 'Image',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.movie),
                    label: 'Video',
                  ),
                ],
              ),
              body: VideoCraftWorkspace(
                controller: controller,
                previewBackend: preview,
                source: source,
                workspaceStore: store,
                recoveryId: 'short-layout',
                recoveryStore: MemoryMediaRecoveryStore(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final canvas = find.byKey(const Key('video-canvas-scroll'));
        final canvasRect = tester.getRect(canvas);
        final previewRect = tester.getRect(
          find.byKey(const Key('video-preview-viewport')),
        );
        expect(
          previewRect.height,
          lessThanOrEqualTo((canvasRect.height - 220).clamp(72, 360) + .01),
        );
        final opens = preview.opens, mounts = preview.viewMounts;
        final recipe = controller.recipe;

        // A real scroll exposes the bottom controls in the short canvas; they
        // remain inside its clip and above the host's bottom navigation.
        await tester.drag(canvas, const Offset(0, -600));
        await tester.pumpAndSettle();
        final input = find.byKey(const Key('video-timecode-input'));
        final go = find.byKey(const Key('video-timecode-go'));
        await tester.ensureVisible(input);
        await tester.pumpAndSettle();
        await tester.enterText(input, controller.recipe!.timecode(5));
        await tester.pumpAndSettle();
        expect(go.hitTestable(), findsOneWidget);
        expect(tester.getRect(go).bottom, lessThanOrEqualTo(canvasRect.bottom));
        expect(
          tester.getRect(go).bottom,
          lessThan(
            tester.getRect(find.byKey(const Key('host-navigation'))).top,
          ),
        );
        await tester.tap(go);
        await tester.pumpAndSettle();
        expect(controller.frame, 5);
        expect(preview.seeks.last, recipe!.timeAtFrame(5));

        FocusManager.instance.primaryFocus?.unfocus();
        final next = find.byTooltip('Next frame');
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(controller.frame, 6);
        final play = find.byTooltip('Play selection');
        await tester.ensureVisible(play);
        await tester.pumpAndSettle();
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(preview.isPlaying, isTrue);
        expect(preview.opens, opens);
        expect(preview.viewMounts, mounts);
        expect(identical(controller.recipe, recipe), isTrue);
        expect(controller.canUndo, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('export remains available with the animation inspector active', (
    tester,
  ) async {
    size(tester, const Size(1200, 850));
    final exporter = FakeExporter();
    Uint8List? delivered;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCraftWorkspace(
            controller: controller,
            previewBackend: preview,
            source: source,
            workspaceStore: store,
            trimExporter: exporter,
            onExportVideo: (bytes) async => delivered = bytes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'craft-workspace-tab-animation');
    controller.setTitle('Export from animation');
    await tester.pumpAndSettle();
    final export = find.text('Export trimmed video');
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(exporter.received!.title, 'Export from animation');
    expect(delivered, [1, 2, 3]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'layout changes retain the prepared MP4 and its recipe snapshot',
    (tester) async {
      size(tester, const Size(1200, 850));
      final exporter = ControlledExporter();
      Uint8List? delivered;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoCraftWorkspace(
              controller: controller,
              previewBackend: preview,
              source: source,
              workspaceStore: store,
              trimExporter: exporter,
              onExportVideo: (bytes) async => delivered = bytes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final recipe = controller.recipe;
      await tester.ensureVisible(find.text('Export MP4'));
      await tester.tap(find.text('Export MP4'));
      await tester.pumpAndSettle();
      exporter.gate.complete(Uint8List.fromList([4, 5, 6]));
      await tester.pumpAndSettle();
      await tap(tester, 'craft-workspace-tab-animation');
      await tester.drag(
        find.byKey(const Key('craft-workspace-divider')),
        const Offset(-70, 0),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'craft-workspace-toggle-sidebar');
      final save = find.text('Save rendered MP4');
      expect(save, findsOneWidget);
      expect(identical(controller.recipe, recipe), isTrue);
      expect(identical(exporter.received, recipe), isTrue);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(delivered, [4, 5, 6]);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
