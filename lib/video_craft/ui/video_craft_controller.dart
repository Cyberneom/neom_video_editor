import 'package:flutter/foundation.dart';
import 'package:neom_craft_libs/neom_craft_libs.dart';
import '../domain/video_craft_recipe.dart';

/// Editing state only. Video transport is attached by the workspace.
class VideoCraftController extends ChangeNotifier {
  VideoCraftRecipe? _recipe;
  final _undo = <VideoCraftRecipe>[];
  final _redo = <VideoCraftRecipe>[];
  int _frame = 0;
  Duration _position = Duration.zero;
  Future<void> Function()? _pause;
  VideoCraftRecipe? get recipe => _recipe;
  int get frame => _frame;

  /// Source time is retained across edits, including frame-rate undo/redo.
  Duration get position => _position;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  double get opacity => _recipe?.opacityAt(_frame) ?? 1;
  Future<void> pause() async {
    await _pause?.call();
  }

  void attachPause(Future<void> Function()? callback) {
    _pause = callback;
  }

  void clearMedia() {
    _recipe = null;
    _undo.clear();
    _redo.clear();
    _frame = 0;
    _position = Duration.zero;
    notifyListeners();
  }

  void attachMedia({
    required String name,
    required Duration duration,
    CraftFrameRate? frameRate,
  }) {
    final rate = frameRate ?? CraftFrameRate(30, 1);
    final count = rate
        .frameAt(
          CraftTick.fromUnits(
            BigInt.from(duration.inMicroseconds),
            BigInt.from(1000000),
          ),
        )
        .toInt();
    final next = VideoCraftRecipe(
      sourceName: name,
      duration: duration,
      frameRate: rate,
      inFrame: 0,
      outFrame: count,
    );
    _recipe = next;
    _undo.clear();
    _redo.clear();
    _frame = 0;
    _position = Duration.zero;
    notifyListeners();
  }

  void _commit(VideoCraftRecipe next) {
    final old = _recipe;
    if (old == null || old.encode() == next.encode()) return;
    _undo.add(old);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    _recipe = next;
    _frame = next.frameAtTime(_position);
    notifyListeners();
  }

  void setPosition(Duration position) {
    _position = position;
    final next = _recipe?.frameAtTime(position) ?? 0;
    if (next == _frame) return;
    _frame = next;
    notifyListeners();
  }

  void setFrame(int frame) {
    final r = _recipe;
    if (r == null) return;
    _frame = frame.clamp(0, r.frameCount - 1);
    _position = r.timeAtFrame(_frame);
    notifyListeners();
  }

  void setTrim(int start, int end) {
    if (_recipe != null) {
      _commit(_recipe!.copyWith(inFrame: start, outFrame: end));
    }
  }

  void setTitle(String title) {
    if (_recipe != null) _commit(_recipe!.copyWith(title: title));
  }

  void putOpacityKey(double value) {
    final r = _recipe;
    if (r != null) {
      _commit(r.copyWith(opacityKeys: {...r.opacityKeys, frame: value}));
    }
  }

  void removeOpacityKey() {
    final r = _recipe;
    if (r != null) {
      _commit(r.copyWith(opacityKeys: {...r.opacityKeys}..remove(frame)));
    }
  }

  /// Frame-rate changes preserve source-time positions, rather than renumbering
  /// the old frame indices at a new speed.
  void setFrameRate(CraftFrameRate rate) {
    final r = _recipe;
    if (r == null || rate == r.frameRate) return;
    int convert(int frame) => rate.frameAt(r.frameRate.atFrame(frame)).toInt();
    final count = rate
        .frameAt(
          CraftTick.fromUnits(
            BigInt.from(r.duration.inMicroseconds),
            BigInt.from(1000000),
          ),
        )
        .toInt();
    final start = convert(r.inFrame).clamp(0, count - 1);
    final end = convert(r.outFrame).clamp(start + 1, count);
    final keys = <int, double>{
      for (final e in r.opacityKeys.entries)
        convert(e.key).clamp(0, count - 1): e.value,
    };
    _commit(
      VideoCraftRecipe(
        sourceName: r.sourceName,
        duration: r.duration,
        frameRate: rate,
        inFrame: start,
        outFrame: end,
        title: r.title,
        opacityKeys: keys,
      ),
    );
  }

  /// Atomically installs an already validated self-contained project. History
  /// belongs to the previous document and must never cross this boundary.
  void restoreProject(VideoCraftRecipe recipe, {required int frame}) {
    if (frame < 0 || frame >= recipe.frameCount) {
      throw const FormatException('Invalid project playhead.');
    }
    _recipe = recipe;
    _undo.clear();
    _redo.clear();
    _frame = frame;
    _position = recipe.timeAtFrame(frame);
    notifyListeners();
  }

  void loadRecipe(String text) {
    final next = VideoCraftRecipe.decode(text);
    final current = _recipe;
    if (current == null ||
        next.sourceName != current.sourceName ||
        next.duration != current.duration) {
      throw const FormatException('Open the matching source video first');
    }
    _commit(next);
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_recipe!);
    _recipe = _undo.removeLast();
    _frame = _recipe!.frameAtTime(_position);
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_recipe!);
    _recipe = _redo.removeLast();
    _frame = _recipe!.frameAtTime(_position);
    notifyListeners();
  }
}
