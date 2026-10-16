import 'package:flutter/foundation.dart';

import '../domain/video_craft_recipe.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_export_contract.dart';

/// Optional export contract for backends that render the complete recipe.
abstract class VideoCraftControlledExporter implements VideoCraftTrimExporter {
  bool get includesAnimatedTitles;

  Future<Uint8List> exportWithOptions(
    VideoCraftSource source,
    VideoCraftRecipe recipe, {
    ValueChanged<double>? onProgress,
    VideoCraftExportCancellation? cancellation,
  });
}

/// One token per export. Cancellation never yields a partial MP4 as a result.
class VideoCraftExportCancellation {
  bool _cancelled = false;
  final _listeners = <VoidCallback>{};
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  /// Returns an unsubscribe callback. Already-cancelled tokens notify at once.
  VoidCallback addListener(VoidCallback listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_cancelled) throw const VideoCraftExportCancelled();
  }
}

class VideoCraftExportCancelled implements Exception {
  const VideoCraftExportCancelled();
  @override
  String toString() => 'Exportación cancelada';
}
