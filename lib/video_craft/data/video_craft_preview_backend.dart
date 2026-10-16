import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_resource.dart';
import 'video_craft_resource_stub.dart'
    if (dart.library.io) 'video_craft_resource_io.dart'
    if (dart.library.js_interop) 'video_craft_resource_web.dart';

/// A real transport boundary; tests and hosts may supply another player.
abstract class VideoCraftPreviewBackend extends ChangeNotifier {
  bool get isReady;
  bool get isPlaying;
  Duration get duration;
  Duration get position;
  double get aspectRatio;
  String? get error;
  Future<void> open(VideoCraftSource source);
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();
  Widget buildView(BuildContext context);
}

class VideoPlayerCraftBackend extends VideoCraftPreviewBackend {
  VideoPlayerCraftBackend({
    @visibleForTesting
    Future<VideoCraftResource> Function(VideoCraftSource)? resourceFactory,
  }) : _resourceFactory = resourceFactory ?? createVideoCraftResource;
  final Future<VideoCraftResource> Function(VideoCraftSource) _resourceFactory;
  VideoCraftResource? _resource;
  int _generation = 0;
  bool _disposed = false;
  String? _error;
  VideoPlayerController? get _player => _resource?.player;
  @override
  bool get isReady => _player?.value.isInitialized ?? false;
  @override
  bool get isPlaying => _player?.value.isPlaying ?? false;
  @override
  Duration get duration => _player?.value.duration ?? Duration.zero;
  @override
  Duration get position => _player?.value.position ?? Duration.zero;
  @override
  double get aspectRatio => _player?.value.aspectRatio ?? 16 / 9;
  @override
  String? get error => _error ?? _player?.value.errorDescription;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _release(VideoCraftResource? resource) async {
    if (resource == null) return;
    resource.player.removeListener(_changed);
    try {
      await resource.player.dispose();
    } catch (_) {
      /* Best-effort retired player cleanup. */
    }
    try {
      await resource.release();
    } catch (_) {
      /* Never invalidate a newly loaded session. */
    }
  }

  @override
  Future<void> open(VideoCraftSource source) async {
    final generation = ++_generation;
    VideoCraftResource? candidate;
    await pause();
    try {
      candidate = await _resourceFactory(source);
      await candidate.player.initialize();
      if (_disposed || generation != _generation) {
        await _release(candidate);
        return;
      }
      final previous = _resource;
      _resource = candidate;
      _error = null;
      candidate.player.addListener(_changed);
      await _release(previous);
      _changed();
    } catch (e) {
      if (candidate != _resource) await _release(candidate);
      if (!_disposed && generation == _generation) {
        _error = e.toString();
        _changed();
      }
      rethrow;
    }
  }

  @override
  Future<void> seek(Duration position) async {
    // video_player_web (and native method-channel players) quantize seeks to
    // milliseconds. Rounding down a frame boundary selects the previous frame.
    // Keep exact ticks in the recipe/export; only preview gets this <1ms offset.
    final micros = position.inMicroseconds;
    final milliseconds = micros <= 0 ? 0 : (micros + 999) ~/ 1000;
    await _player?.seekTo(Duration(milliseconds: milliseconds));
  }

  @override
  Future<void> play() async {
    await _player?.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Widget buildView(BuildContext context) =>
      isReady ? VideoPlayer(_player!) : const SizedBox.shrink();
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    final old = _resource;
    _resource = null;
    // dispose has no asynchronous Flutter contract; cleanup still owns the
    // previous player/temp resource and cannot touch a later source.
    _release(old).catchError((Object _) {});
    super.dispose();
  }
}
