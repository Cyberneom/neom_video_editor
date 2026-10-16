import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../domain/video_craft_recipe.dart';
import '../domain/video_craft_source.dart';
import '../rendering/video_craft_title_renderer.dart';
import 'video_craft_export_control.dart';
import 'video_craft_trim_exporter.dart';

@JS('isSecureContext')
external bool get _isSecureContext;
@JS('VideoEncoder')
external JSAny? get _videoEncoder;
@JS('VideoDecoder')
external JSAny? get _videoDecoder;
@JS('neomVideoExport')
external JSAny? get _backend;
@JS('neomVideoExport.begin')
external JSPromise<JSString> _begin(
  String id,
  JSUint8Array? bytes,
  String? uri,
  String recipe,
);
@JS('neomVideoExport.render')
external JSPromise<JSUint8Array> _render(
  String id,
  JSUint8Array titlePng,
  JSFunction onProgress,
);
@JS('neomVideoExport.cancel')
external void _cancel(String id);
@JS('neomVideoExport.dispose')
external JSPromise<JSAny?> _dispose(String id);

Future<void>? _loading;
int _nextExportId = 0;

Future<void> _loadBackend() =>
    _loading ??= _loadScript().catchError((Object e) {
      _loading = null;
      throw e;
    });

Future<void> _loadScript() async {
  if (_backend != null) return;
  // The engine resolves the asset URL, including an app subdirectory or a
  // configured assetBase. No inline script, blob: CSP exception, or CDN is used.
  final script = web.HTMLScriptElement()
    ..src = ui_web.assetManager.getAssetUrl(
      'packages/neom_video_editor/assets/web/neom_video_export.bundle.js',
    );
  final ready = Completer<void>();
  script.onload = ((web.Event _) {
    if (!ready.isCompleted) ready.complete();
  }).toJS;
  script.onerror = ((web.Event _) {
    if (!ready.isCompleted) {
      ready.completeError(
        StateError(
          'No se pudo cargar el exportador local. Comprueba los assets publicados y que CSP permita scripts desde su origen.',
        ),
      );
    }
  }).toJS;
  web.document.head!.appendChild(script);
  try {
    await ready.future.timeout(const Duration(seconds: 20));
    if (_backend == null) {
      throw StateError('El exportador web no se inicializó.');
    }
  } finally {
    script.remove();
  }
}

VideoCraftTrimExporter createPlatformVideoCraftExporter() =>
    const WebVideoCraftTrimExporter();

/// Offline frame-by-frame H.264/AAC MP4 compositor powered by WebCodecs.
/// Codec support is checked for every input before rendering. Unsupported audio
/// aborts the operation instead of silently creating a muted export.
class WebVideoCraftTrimExporter implements VideoCraftControlledExporter {
  const WebVideoCraftTrimExporter();

  @override
  bool get isSupported =>
      _isSecureContext && _videoEncoder != null && _videoDecoder != null;

  @override
  bool get includesAnimatedTitles => true;

  @override
  Future<Uint8List> exportTrim(
    VideoCraftSource source,
    VideoCraftRecipe recipe,
  ) => exportWithOptions(source, recipe);

  @override
  Future<Uint8List> exportWithOptions(
    VideoCraftSource source,
    VideoCraftRecipe recipe, {
    ValueChanged<double>? onProgress,
    VideoCraftExportCancellation? cancellation,
  }) async {
    final token = cancellation ?? VideoCraftExportCancellation();
    token.throwIfCancelled();
    if (!isSupported) {
      throw UnsupportedError(
        'La exportación MP4 requiere WebCodecs en HTTPS o localhost.',
      );
    }
    await _loadBackend();
    token.throwIfCancelled();
    final id = 'neom-video-${_nextExportId++}';
    final removeListener = token.addListener(() => _cancel(id));
    try {
      onProgress?.call(0);
      final metadataText = await _begin(
        id,
        source.bytes?.toJS,
        source.uri?.toString(),
        recipe.encode(),
      ).toDart;
      token.throwIfCancelled();
      final metadata = jsonDecode(metadataText.toDart) as Map<String, dynamic>;
      final png = recipe.title.trim().isEmpty
          ? Uint8List(0)
          : await renderVideoCraftTitle(
              recipe.title,
              width: metadata['width'] as int,
              height: metadata['height'] as int,
            );
      token.throwIfCancelled();
      final progress = ((JSNumber value) {
        if (!token.isCancelled) onProgress?.call(value.toDartDouble);
      }).toJS;
      final bytes = await _render(id, png.toJS, progress).toDart;
      token.throwIfCancelled();
      return bytes.toDart;
    } catch (error) {
      token.throwIfCancelled();
      rethrow;
    } finally {
      removeListener();
      await _dispose(id).toDart;
    }
  }
}
