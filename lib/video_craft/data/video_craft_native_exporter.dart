import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

import '../domain/video_craft_recipe.dart';
import '../domain/video_craft_source.dart';
import '../rendering/video_craft_title_renderer.dart';
import 'video_craft_export_control.dart';
import 'video_craft_native_render_plan.dart';

/// Metadata kept separate from the plugin's model because the Open Neom patch
/// reports all audio streams (upstream exposes only the first stream's duration).
@immutable
class VideoCraftNativeMediaInfo {
  const VideoCraftNativeMediaInfo({
    required this.width,
    required this.height,
    required this.duration,
    required this.audioTrackCount,
    this.frameRate,
    this.videoDuration,
  });
  final int width;
  final int height;
  final Duration duration;
  final int audioTrackCount;
  final double? frameRate;

  /// Duration of the video stream, independent of AAC padding in the container.
  final Duration? videoDuration;
}

/// Injectable boundary for native integration tests. Rendering must complete or
/// acknowledge cancellation before its Future settles, so cleanup is safe.
abstract class VideoCraftNativeBackend {
  Future<bool> supportsOpacityKeys();
  Future<VideoCraftNativeMediaInfo> metadata(String path);
  Stream<double> progress(String taskId);
  Future<void> render(String outputPath, VideoRenderData data);
  Future<void> cancel(String taskId);
}

class _ProVideoCraftNativeBackend implements VideoCraftNativeBackend {
  const _ProVideoCraftNativeBackend();
  static const _channel = MethodChannel('pro_video_editor');
  @override
  Future<bool> supportsOpacityKeys() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getNeomCapabilities',
      );
      return result?['opacityKeyframes'] == 1 &&
          result?['audioTrackCount'] == true &&
          result?['videoTrackDuration'] == true;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<VideoCraftNativeMediaInfo> metadata(String path) async {
    final map = await _channel.invokeMapMethod<String, dynamic>('getMetadata', {
      'inputPath': path,
      'extension': 'mp4',
    });
    if (map == null || map['audioTrackCount'] is! num) {
      throw StateError('No se pudieron verificar las pistas de audio.');
    }
    return VideoCraftNativeMediaInfo(
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      duration: Duration(
        microseconds: ((map['duration'] as num? ?? 0) * 1000).round(),
      ),
      audioTrackCount: (map['audioTrackCount'] as num).toInt(),
      frameRate: (map['frameRate'] as num?)?.toDouble(),
      videoDuration: map['videoDurationUs'] is num
          ? Duration(microseconds: (map['videoDurationUs'] as num).round())
          : null,
    );
  }

  @override
  Stream<double> progress(String taskId) => ProVideoEditor.instance
      .progressStreamById(taskId)
      .map((event) => event.progress);

  @override
  Future<void> render(String outputPath, VideoRenderData data) async {
    await ProVideoEditor.instance.renderVideoToFile(outputPath, data);
  }

  @override
  Future<void> cancel(String taskId) => ProVideoEditor.instance.cancel(taskId);
}

/// The native plugin reads additional reference packets when a B-frame near
/// the out point depends on them, then restricts the muxed file to this trim.
class _VideoCraftNativeRenderData extends VideoRenderData {
  _VideoCraftNativeRenderData({
    required super.id,
    required super.videoSegments,
    required super.imageLayers,
    required this.plan,
  }) : super(enableAudio: true, shouldOptimizeForNetworkUse: true);
  final VideoCraftNativeRenderPlan plan;

  @override
  Future<Map<String, dynamic>> toAsyncMap() async {
    final map = await super.toAsyncMap();
    return {
      ...map,
      'neomExactTrim': true,
      // AVFoundation can represent the frame boundary exactly. Rounding a
      // fractional duration to microseconds may otherwise generate an extra
      // composition frame. Android continues using its integer-us timestamps.
      'videoClips': [
        for (final clip in map['videoClips'] as List)
          {
            ...clip as Map<String, dynamic>,
            'neomFrameRange': {
              'inFrame': plan.recipe.inFrame,
              'outFrame': plan.recipe.outFrame,
              'numerator': plan.recipe.frameRate.numerator.toInt(),
              'denominator': plan.recipe.frameRate.denominator.toInt(),
            },
          },
      ],
    };
  }
}

typedef VideoCraftNativeTitleRenderer =
    Future<Uint8List> Function(
      String title, {
      required int width,
      required int height,
    });

/// Media3 (Android) / AVFoundation + CoreImage (iOS/macOS) MP4 export.
///
/// The historical class name remains compatible, but exportTrim now includes
/// the complete title/opacity recipe. Requires the versioned Open Neom plugin
/// patch, checked before creating any native render job. Windows/Linux remain
/// unsupported. No server or FFmpeg installation is required.
class ProVideoCraftTrimExporter implements VideoCraftControlledExporter {
  const ProVideoCraftTrimExporter({
    this.backend,
    this.titleRenderer = renderVideoCraftTitle,
    this.temporaryDirectory,
  });

  final VideoCraftNativeBackend? backend;
  final VideoCraftNativeTitleRenderer titleRenderer;

  /// Tests may supply an isolated directory. Production uses the application
  /// process's OS temporary directory. Only this job's generated subfolder is
  /// removed; source files and the caller's directory are never deleted.
  final Directory? temporaryDirectory;
  static int _nextTask = 0;
  static const maxFileBytes = 512 * 1024 * 1024;
  static const maxFramePixels = 8300000;

  @override
  bool get isSupported =>
      backend != null ||
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);
  @override
  bool get includesAnimatedTitles => isSupported;

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
        'La exportación nativa requiere Android, iOS o macOS.',
      );
    }
    final backend = this.backend ?? const _ProVideoCraftNativeBackend();
    onProgress?.call(0);
    final supported = await backend.supportsOpacityKeys();
    token.throwIfCancelled();
    if (!supported) {
      throw UnsupportedError(
        'Falta el motor nativo de Open Neom. Reconstruye la aplicación con '
        'pro_video_editor 1.22.0+neom.1; no basta con hot reload.',
      );
    }
    final folder = await (temporaryDirectory ?? Directory.systemTemp)
        .createTemp('neom-video-export-');
    StreamSubscription<double>? progress;
    VoidCallback? removeCancellation;
    try {
      token.throwIfCancelled();
      final inputPath = await _prepareInput(source, folder, token);
      token.throwIfCancelled();
      final info = await backend.metadata(inputPath);
      token.throwIfCancelled();
      final plan = VideoCraftNativeRenderPlan(recipe);
      _validateInput(info, plan);
      Uint8List? title;
      if (recipe.title.trim().isNotEmpty) {
        title = await titleRenderer(
          recipe.title,
          width: info.width,
          height: info.height,
        );
        token.throwIfCancelled();
      }
      final id = 'neom-${DateTime.now().microsecondsSinceEpoch}-${_nextTask++}';
      final output = File('${folder.path}/rendered.mp4');
      final data = _VideoCraftNativeRenderData(
        id: id,
        plan: plan,
        videoSegments: [
          VideoSegment(
            video: EditorVideo.file(inputPath),
            startTime: plan.startTime,
            endTime: plan.endTime,
          ),
        ],
        // No resolution/bitrate preset: upstream Apple bitrate presets may
        // silently downscale. Native codecs choose quality at source dimensions.
        imageLayers: [
          if (title != null)
            ImageLayer(
              image: EditorLayerImage.memory(title),
              startTime: Duration.zero,
              endTime: plan.duration,
              animations: [plan.opacityAnimation],
            ),
        ],
      );
      var lastProgress = .05;
      onProgress?.call(lastProgress);
      progress = backend
          .progress(id)
          .listen(
            (value) {
              if (token.isCancelled || !value.isFinite) return;
              final next = .05 + value.clamp(0, 1) * .88;
              if (next > lastProgress) {
                lastProgress = next;
                onProgress?.call(next);
              }
            },
            onError: (Object error) {
              // Native completion remains authoritative; losing a progress event must
              // not crash or prematurely release an active encoder's resources.
              debugPrint('Video export progress unavailable: $error');
            },
          );
      token.throwIfCancelled();
      // The plugin synchronously registers its job before its first await. Add
      // the listener after dispatch so pre-dispatch cancellation is also handled.
      final rendering = backend.render(output.path, data);
      removeCancellation = token.addListener(() {
        unawaited(
          backend.cancel(id).catchError((Object error) {
            // Completion can race a last cancel request. Always await rendering
            // below, then discard its result when the token is cancelled.
            debugPrint('Video export cancellation response: $error');
          }),
        );
      });
      await rendering;
      token.throwIfCancelled();
      removeCancellation();
      removeCancellation = null;
      final resultInfo = await backend.metadata(output.path);
      token.throwIfCancelled();
      _validateOutput(info, resultInfo, plan);
      final size = await output.length();
      if (size < 12 || size > maxFileBytes) {
        throw StateError('El MP4 está vacío o supera el límite de 512 MiB.');
      }
      final bytes = await output.readAsBytes();
      token.throwIfCancelled();
      if (String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
        throw StateError('El motor no generó un archivo MP4 válido.');
      }
      onProgress?.call(1);
      return bytes;
    } catch (_) {
      token.throwIfCancelled();
      rethrow;
    } finally {
      removeCancellation?.call();
      await progress?.cancel();
      // The encoder future has settled before reaching this cleanup.
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  }

  static void _validateInput(
    VideoCraftNativeMediaInfo info,
    VideoCraftNativeRenderPlan plan,
  ) {
    if (info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > maxFramePixels) {
      throw UnsupportedError(
        'La exportación admite hasta 8,3 megapíxeles por cuadro (4K UHD).',
      );
    }
    if (info.width.isOdd || info.height.isOdd) {
      throw UnsupportedError(
        'El codificador MP4 requiere dimensiones pares. No se recortará la imagen automáticamente.',
      );
    }
    if (info.audioTrackCount < 0 || info.audioTrackCount > 1) {
      throw UnsupportedError(
        'Se admite una pista de audio. Esta fuente contiene varias o no se pudieron verificar.',
      );
    }
    if (info.duration <= Duration.zero ||
        plan.endTime > info.duration + const Duration(milliseconds: 3)) {
      throw StateError('El recorte excede la duración del vídeo original.');
    }
  }

  static void _validateOutput(
    VideoCraftNativeMediaInfo source,
    VideoCraftNativeMediaInfo result,
    VideoCraftNativeRenderPlan plan,
  ) {
    if (result.width != source.width || result.height != source.height) {
      throw StateError(
        'El codificador cambió la resolución. No se entregó el archivo reducido.',
      );
    }
    if (result.audioTrackCount != source.audioTrackCount) {
      throw StateError(
        'El codificador no conservó la pista de audio. No se entregó un MP4 silencioso.',
      );
    }
    // AAC priming/padding can extend container duration; exact audio sample
    // boundaries are not promised. Large timing errors still fail explicitly.
    final toleranceUs =
        (1000000 / plan.recipe.frameRate.framesPerSecond).ceil() + 120000;
    if ((result.duration - plan.duration).inMicroseconds.abs() > toleranceUs) {
      throw StateError(
        'El MP4 generado no coincide con la duración del recorte.',
      );
    }
    // Container duration can be correct while its video lost a frame: audio
    // padding must not conceal that. Allow timestamp quantization and half a
    // source frame, not a complete missing frame. Independent decoded-frame
    // audits are still necessary; duration alone cannot detect duplicates.
    final videoDuration = result.videoDuration;
    final nominalFps =
        source.frameRate ?? plan.recipe.frameRate.framesPerSecond;
    final videoToleranceUs =
        (500000 / (nominalFps > 0 ? nominalFps : 24)).ceil() + 1000;
    if (videoDuration == null ||
        videoDuration <= Duration.zero ||
        (videoDuration - plan.duration).inMicroseconds.abs() >
            videoToleranceUs) {
      throw StateError(
        'La pista de vídeo no conserva la duración del recorte '
        '(${videoDuration?.inMicroseconds} µs; esperado ${plan.duration.inMicroseconds} µs); '
        'no se entregó el MP4.',
      );
    }
    final originalFps = source.frameRate;
    final resultFps = result.frameRate;
    if (originalFps != null &&
        resultFps != null &&
        originalFps > 0 &&
        (resultFps - originalFps).abs() > .1) {
      throw StateError(
        'El codificador cambió la frecuencia de cuadros del vídeo.',
      );
    }
  }

  static Future<String> _prepareInput(
    VideoCraftSource source,
    Directory folder,
    VideoCraftExportCancellation token,
  ) async {
    final bytes = source.bytes;
    if (bytes != null) {
      if (bytes.isEmpty || bytes.length > maxFileBytes) {
        throw UnsupportedError('El vídeo debe ocupar entre 1 byte y 512 MiB.');
      }
      final file = File('${folder.path}/source.mp4');
      await file.writeAsBytes(bytes);
      token.throwIfCancelled();
      return file.path;
    }
    final uri = source.uri!;
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      final length = await file.length();
      if (length <= 0 || length > maxFileBytes) {
        throw UnsupportedError('El vídeo debe ocupar entre 1 byte y 512 MiB.');
      }
      return file.path;
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw UnsupportedError(
        'Abre un archivo local o una URL HTTP(S) de vídeo.',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    final remove = token.addListener(() => client.close(force: true));
    final file = File('${folder.path}/source.mp4');
    RandomAccessFile? handle;
    try {
      final request = await client.getUrl(uri);
      token.throwIfCancelled();
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'No se pudo descargar el vídeo: HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      if (response.contentLength > maxFileBytes) {
        throw UnsupportedError('El vídeo supera 512 MiB.');
      }
      handle = await file.open(mode: FileMode.write);
      var length = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        token.throwIfCancelled();
        length += chunk.length;
        if (length > maxFileBytes) {
          throw UnsupportedError('El vídeo supera 512 MiB.');
        }
        await handle.writeFrom(chunk);
      }
      if (length == 0) throw StateError('El archivo de vídeo está vacío.');
      return file.path;
    } finally {
      await handle?.close();
      remove();
      client.close(force: true);
    }
  }
}
