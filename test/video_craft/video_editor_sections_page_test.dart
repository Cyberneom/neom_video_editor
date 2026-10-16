import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

class _Files extends VideoEditorFileAccess {
  VideoEditorPickedFile? next;
  VideoEditorSaveResult result = VideoEditorSaveResult.saved;
  Uint8List? saved;
  String? name;
  @override
  Future<VideoEditorPickedFile?> open({
    required List<String> extensions,
  }) async => next;
  @override
  Future<VideoEditorSaveResult> save({
    required Uint8List bytes,
    required String name,
    required String extension,
  }) async {
    saved = bytes;
    this.name = name;
    return result;
  }
}

class _Preview extends VideoCraftPreviewBackend {
  @override
  bool isReady = false;
  @override
  bool isPlaying = false;
  @override
  Duration get duration => const Duration(seconds: 10);
  @override
  Duration position = Duration.zero;
  @override
  double get aspectRatio => 16 / 9;
  @override
  String? get error => null;
  VideoCraftSource? source;
  @override
  Future<void> open(VideoCraftSource source) async {
    this.source = source;
    isReady = true;
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
  Future<void> seek(Duration position) async {
    this.position = position;
    notifyListeners();
  }

  @override
  Widget buildView(BuildContext context) => const SizedBox.expand();
}

void main() {
  late _Files files;
  late _Preview preview;
  late VideoCraftController controller;
  setUp(() {
    files = _Files();
    preview = _Preview();
    controller = VideoCraftController();
  });
  tearDown(() {
    controller.dispose();
    preview.dispose();
  });
  Future<void> mount(WidgetTester tester, {bool source = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoEditorSectionsPage(
          files: files,
          controller: controller,
          previewBackend: preview,
          source: source
              ? VideoCraftSource.bytes(
                  Uint8List.fromList([1]),
                  name: 'clip.mp4',
                )
              : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'self-contained picker opens bytes without application services',
    (tester) async {
      files.next = VideoEditorPickedFile(
        'picked.mp4',
        Uint8List.fromList([1, 2, 3]),
      );
      await mount(tester, source: false);
      await tester.tap(find.text('Open video'));
      await tester.pumpAndSettle();
      expect(preview.source!.bytes, [1, 2, 3]);
      expect(controller.recipe!.sourceName, 'picked.mp4');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'save writes UTF-8 JSON, and reopen restores it for the same source',
    (tester) async {
      await mount(tester);
      controller.setTitle('Título 🎬');
      controller.setTrim(30, 90);
      await tester.pump();
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(files.name, 'clip.recipe.json');
      final saved = utf8.decode(files.saved!);
      expect(VideoCraftRecipe.decode(saved).title, 'Título 🎬');
      files.next = VideoEditorPickedFile('clip.recipe.json', files.saved!);
      controller.setTitle('Later');
      await tester.pump();
      await tester.tap(find.text('Open recipe'));
      await tester.pumpAndSettle();
      expect(controller.recipe!.title, 'Título 🎬');
      expect(controller.recipe!.inFrame, 30);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('cancelled save never announces a delivered or saved recipe', (
    tester,
  ) async {
    files.result = VideoEditorSaveResult.cancelled;
    await mount(tester);
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save cancelled.'), findsWidgets);
    expect(find.textContaining('Recipe delivered'), findsNothing);
    expect(find.textContaining('Saved clip'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
