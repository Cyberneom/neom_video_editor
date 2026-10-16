import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';
import 'package:neom_video_editor/video_craft/data/video_craft_resource.dart';
import 'package:video_player/video_player.dart';

class _Player extends VideoPlayerController {
  _Player() : super.networkUrl(Uri.parse('https://example.invalid/test.mp4'));
  Duration? lastSeek;
  @override
  Future<void> initialize() async {
    value = const VideoPlayerValue(
      duration: Duration(seconds: 8),
      isInitialized: true,
      size: Size(720, 405),
    );
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {
    lastSeek = position;
  }
}

void main() {
  test(
    'preview rounds up at plugin millisecond boundary while recipe stays exact',
    () async {
      final player = _Player();
      var released = false;
      final backend = VideoPlayerCraftBackend(
        resourceFactory: (_) async => VideoCraftResource(player, () async {
          released = true;
        }),
      );
      await backend.open(VideoCraftSource.bytes(Uint8List(1)));
      final controller = VideoCraftController()
        ..attachMedia(
          name: 'test.mp4',
          duration: const Duration(seconds: 8),
          frameRate: CraftFrameRate(24, 1),
        );
      final recipe = controller.recipe!;
      final exact = recipe.timeAtFrame(95);
      expect(exact, const Duration(microseconds: 3958334));
      await backend.seek(exact);
      expect(player.lastSeek, const Duration(milliseconds: 3959));
      expect(recipe.frameAtTime(player.lastSeek!), 95);
      expect(recipe.timeAtFrame(95), exact);
      await backend.seek(const Duration(seconds: 1));
      expect(player.lastSeek, const Duration(seconds: 1));
      controller.dispose();
      backend.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(released, isTrue);
    },
  );
}
