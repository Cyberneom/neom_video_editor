import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<Uint8List> readProjectUri(Uri uri, int limit) async {
  if (!const {'http', 'https', 'blob'}.contains(uri.scheme)) {
    throw UnsupportedError(
      'Import a browser-selected video before saving a project.',
    );
  }
  final abort = web.AbortController();
  final timeout = Timer(const Duration(seconds: 60), () => abort.abort());
  web.ReadableStreamDefaultReader? reader;
  try {
    final response = await web.window
        .fetch(uri.toString().toJS, web.RequestInit(signal: abort.signal))
        .toDart;
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
