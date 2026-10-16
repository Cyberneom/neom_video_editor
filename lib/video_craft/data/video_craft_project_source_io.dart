import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> _collect(Stream<List<int>> stream, int limit) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream.timeout(const Duration(seconds: 30))) {
    if (builder.length + chunk.length > limit) {
      throw const FormatException('Project media exceeds 256 MiB.');
    }
    builder.add(chunk);
  }
  if (builder.isEmpty) {
    throw const FormatException('The video source is empty.');
  }
  return builder.takeBytes();
}

Future<Uint8List> readProjectUri(Uri uri, int limit) async {
  if (uri.scheme == 'file') {
    final file = File.fromUri(uri);
    if (await file.length() > limit) {
      throw const FormatException('Project media exceeds 256 MiB.');
    }
    return _collect(file.openRead(), limit);
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw UnsupportedError(
      'Import this video as a local file before saving a project.',
    );
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 30));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Video source returned HTTP ${response.statusCode}.');
    }
    if (response.contentLength > limit) {
      throw const FormatException('Project media exceeds 256 MiB.');
    }
    return await _collect(response, limit);
  } finally {
    client.close(force: true);
  }
}
