import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'video_craft_origin_web.dart';
import 'video_craft_url_security.dart';

bool _isAllowedHttpSourceUri(Uri uri, {required bool allowLoopbackForTest}) {
  if (isSafePublicVideoExportUri(uri)) return true;
  if (!allowLoopbackForTest) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  final host = uri.host.trim().toLowerCase();
  return uri.userInfo.isEmpty &&
      (host == 'localhost' || host == '127.0.0.1' || host == '::1');
}

Future<Uint8List> readProjectUri(
  Uri uri,
  int limit, {
  bool allowLoopbackForTest = false,
}) async {
  final scheme = uri.scheme.toLowerCase();
  if (!const {'http', 'https', 'blob'}.contains(scheme)) {
    throw UnsupportedError(
      'Import a browser-selected video before saving a project.',
    );
  }
  if (scheme == 'blob' && !isSameOriginBlobUri(uri)) {
    throw UnsupportedError(
      'Blob video source must belong to the current web origin.',
    );
  }
  if ((scheme == 'http' || scheme == 'https') &&
      !_isAllowedHttpSourceUri(
        uri,
        allowLoopbackForTest: allowLoopbackForTest,
      )) {
    throw UnsupportedError(
      'Video source URL points to a blocked private or local host.',
    );
  }
  final abort = web.AbortController();
  final timeout = Timer(const Duration(seconds: 60), () => abort.abort());
  web.ReadableStreamDefaultReader? reader;
  try {
    final init = scheme == 'blob'
        ? web.RequestInit(signal: abort.signal)
        : web.RequestInit(
            signal: abort.signal,
            credentials: 'omit',
            referrerPolicy: 'no-referrer',
          );
    final response = await web.window
        .fetch(uri.toString().toJS, init)
        .toDart;
    if (scheme != 'blob' && response.url.isNotEmpty) {
      final finalUri = Uri.tryParse(response.url);
      if (finalUri == null ||
          !_isAllowedHttpSourceUri(
            finalUri,
            allowLoopbackForTest: allowLoopbackForTest,
          )) {
        throw UnsupportedError(
          'Video redirect to a private or local host was blocked.',
        );
      }
    }
    if (!response.ok) {
      throw StateError('Video source returned HTTP ${response.status}.');
    }
    final declaredLength = int.tryParse(
      response.headers.get('content-length') ?? '',
    );
    if (declaredLength != null && declaredLength > limit) {
      throw const FormatException('Project media exceeds 256 MiB.');
    }
    final body = response.body;
    if (body == null) throw const FormatException('The video source is empty.');
    reader = body.getReader() as web.ReadableStreamDefaultReader;
    final builder = BytesBuilder(copy: false);
    while (true) {
      final part = await reader.read().toDart;
      if (part.done) break;
      final bytes = (part.value as JSUint8Array).toDart;
      if (builder.length + bytes.length > limit) {
        throw const FormatException('Project media exceeds 256 MiB.');
      }
      builder.add(bytes);
    }
    if (builder.isEmpty) {
      throw const FormatException('The video source is empty.');
    }
    return builder.takeBytes();
  } finally {
    timeout.cancel();
    abort.abort();
    try {
      await reader?.cancel().toDart;
    } catch (_) {}
    reader?.releaseLock();
  }
}
