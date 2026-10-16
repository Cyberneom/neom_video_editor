import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:neom_media_recovery/neom_media_recovery.dart';

import '../domain/video_craft_project.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_project_source.dart';

/// Reads URI-backed media once per accepted source identity. Only compressed
/// source bytes are cached; exports and decoded frames never enter recovery.
class VideoCraftRecoverySourceCache {
  VideoCraftRecoverySourceCache({this.reader = readVideoCraftProjectSource});
  final Future<Uint8List> Function(VideoCraftSource) reader;
  VideoCraftSource? _source;
  Future<VideoCraftSource>? _media;

  void clear() {
    _source = null;
    _media = null;
  }

  Future<VideoCraftSource> resolve(VideoCraftSource source) {
    if (identical(source, _source) && _media != null) return _media!;
    _source = source;
    late final Future<VideoCraftSource> future;
    future =
        Future<VideoCraftSource>.sync(() async {
          final bytes = source.bytes ?? await reader(source);
          return VideoCraftSource.bytes(
            bytes,
            name: source.name,
            frameRate: source.frameRate,
          );
        }).catchError((Object error, StackTrace stack) {
          if (identical(source, _source) && identical(_media, future)) {
            _media = null;
          }
          Error.throwWithStackTrace(error, stack);
        });
    _media = future;
    return future;
  }
}

/// Recovery-only envelope. The embedded portable project stays unchanged;
/// an unapplied title draft remains a draft when the session is recovered.
class VideoCraftRecoveryData {
  VideoCraftRecoveryData(this.project, {this.titleDraft});
  final VideoCraftProject project;
  final String? titleDraft;
  static final _magic = ascii.encode('NEOMVIDRECOVERY\n');
  static const _maxMetadataBytes = 8192;

  Uint8List encode() {
    if (titleDraft != null && titleDraft!.length > 1000) {
      throw const FormatException('Recovery title exceeds 1000 characters.');
    }
    final metadata = utf8.encode(
      jsonEncode({'version': 1, 'titleDraft': titleDraft}),
    );
    final media = project.encode();
    final prefix = _magic.length + 4;
    final result = Uint8List(prefix + metadata.length + media.length);
    result.setRange(0, _magic.length, _magic);
    ByteData.sublistView(result).setUint32(_magic.length, metadata.length);
    result.setRange(prefix, prefix + metadata.length, metadata);
    result.setRange(prefix + metadata.length, result.length, media);
    return result;
  }

  factory VideoCraftRecoveryData.decode(Uint8List bytes) {
    final prefix = _magic.length + 4;
    if (bytes.length < prefix ||
        bytes.length >
            VideoCraftProject.maxProjectBytes + prefix + _maxMetadataBytes ||
        !listEquals(bytes.sublist(0, _magic.length), _magic)) {
      throw const FormatException('Invalid video recovery envelope.');
    }
    final length = ByteData.sublistView(bytes).getUint32(_magic.length);
    if (length == 0 ||
        length > _maxMetadataBytes ||
        prefix + length >= bytes.length) {
      throw const FormatException('Invalid video recovery metadata length.');
    }
    final metadata = jsonDecode(
      utf8.decode(bytes.sublist(prefix, prefix + length)),
    );
    if (metadata is! Map<String, dynamic> ||
        metadata.length != 2 ||
        metadata['version'] is! int ||
        metadata['version'] != 1 ||
        !metadata.containsKey('titleDraft') ||
        (metadata['titleDraft'] != null &&
            (metadata['titleDraft'] is! String ||
                (metadata['titleDraft'] as String).length > 1000))) {
      throw const FormatException('Unsupported video recovery metadata.');
    }
    return VideoCraftRecoveryData(
      VideoCraftProject.decode(Uint8List.sublistView(bytes, prefix + length)),
      titleDraft: metadata['titleDraft'] as String?,
    );
  }
}

/// Serializes debounced snapshots, retaining the last successful revision.
/// Loading/choosing an existing recovery blocks writes. A conflict blocks writes
/// until a fresh read and a deliberate restore/discard decision.
class VideoCraftRecoverySession extends ChangeNotifier {
  VideoCraftRecoverySession(
    this.store,
    this.key, {
    this.debounce = const Duration(milliseconds: 800),
  });
  final MediaRecoveryStore store;
  final String key;
  final Duration debounce;
  MediaRecoverySnapshot? candidate;
  Object? error;
  bool loading = true, blocked = true, saving = false, dirty = false;
  DateTime? savedAt;
  String? _storedRevision;
  Timer? _timer;
  Future<Uint8List> Function()? _builder;
  int _request = 0, _readGeneration = 0;
  bool _disposed = false;
  Future<void>? _running;
  String? get discardRevision =>
      candidate?.revision ??
      (error is MediaRecoveryException
          ? (error as MediaRecoveryException).revision
          : null);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> read() async {
    final generation = ++_readGeneration;
    _timer?.cancel();
    loading = true;
    blocked = true;
    error = null;
    _changed();
    try {
      final found = await store.read(key);
      if (_disposed || generation != _readGeneration) return;
      candidate = found;
      _storedRevision = found?.revision;
      blocked = found != null;
    } catch (exception) {
      if (_disposed || generation != _readGeneration) return;
      error = exception;
    } finally {
      if (!_disposed && generation == _readGeneration) {
        loading = false;
        _changed();
        if (!blocked && dirty) _arm();
      }
    }
  }

  void schedule(Future<Uint8List> Function() builder) {
    if (_disposed) return;
    _builder = builder;
    ++_request;
    dirty = true;
    _changed();
    if (!blocked && error == null) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  /// An old source being read asynchronously must not overwrite a newer open.
  void invalidatePending() {
    _timer?.cancel();
    ++_request;
    _builder = null;
    dirty = false;
  }

  Future<void> flush() {
    _timer?.cancel();
    if (_disposed || blocked || error != null || !dirty) return Future.value();
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    saving = true;
    _changed();
    try {
      while (!_disposed && !blocked && dirty && _builder != null) {
        final request = _request, builder = _builder!;
        Uint8List bytes;
        try {
          bytes = await builder();
        } catch (_) {
          if (request != _request) continue;
          rethrow;
        }
        if (_disposed) return;
        if (request != _request) continue;
        final committed = await store.write(
          key,
          bytes,
          expectedRevision: _storedRevision,
        );
        // Even a superseded in-flight commit advances our CAS revision. Never
        // claim the latest edit is durable until that edit's commit completes.
        _storedRevision = committed.revision;
        if (request == _request) {
          dirty = false;
          savedAt = committed.updatedAt;
        }
      }
    } catch (exception) {
      if (!_disposed) {
        error = exception;
        if (exception is MediaRecoveryConflictException) blocked = true;
      }
    } finally {
      saving = false;
      _changed();
    }
  }

  void reportError(Object exception) {
    error = exception;
    _changed();
  }

  void acceptRecovery() {
    invalidatePending();
    candidate = null;
    blocked = false;
    error = null;
    _changed();
  }

  Future<void> discard() async {
    final revision = discardRevision;
    if (revision == null || loading) return;
    loading = true;
    _changed();
    try {
      await store.delete(key, expectedRevision: revision);
      if (_disposed) return;
      _storedRevision = null;
      candidate = null;
      blocked = false;
      error = null;
      savedAt = null;
    } catch (exception) {
      if (!_disposed) error = exception;
    } finally {
      loading = false;
      _changed();
      if (!_disposed && !blocked && dirty) _arm();
    }
  }

  Future<void> retry() async {
    if (blocked) {
      await read();
    } else {
      error = null;
      _changed();
      await flush();
    }
  }

  Future<void> finish() async {
    await flush();
    dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    ++_readGeneration;
    super.dispose();
  }
}
