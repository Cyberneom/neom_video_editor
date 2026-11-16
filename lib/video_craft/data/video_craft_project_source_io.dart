import 'dart:io';
import 'dart:typed_data';

import 'video_craft_url_security.dart';

const int _maxProjectRedirects = 3;

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

Future<Uint8List> readProjectUri(
  Uri uri,
  int limit, {
  bool allowLoopbackForTest = false,
}) async {
  if (uri.scheme == 'file') {
    if (uri.authority.isNotEmpty && uri.authority != 'localhost') {
      throw UnsupportedError('UNC network file paths are not permitted.');
    }
    final file = File.fromUri(uri);
    final path = file.path;
    if (isProtectedLocalVideoPath(path)) {
      throw UnsupportedError('Unsafe or protected local video source path.');
    }
    final entityType = await FileSystemEntity.type(path, followLinks: false);
    if (entityType == FileSystemEntityType.link ||
        FileSystemEntity.isLinkSync(file.parent.path)) {
      throw UnsupportedError('Symlinked video project sources are blocked.');
    }
    if (entityType == FileSystemEntityType.file) {
      final resolved = file.resolveSymbolicLinksSync();
      if (isProtectedLocalVideoPath(resolved)) {
        throw UnsupportedError('Symlinked video project sources are blocked.');
      }
    }
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
  final isAllowedLoopbackTest =
      allowLoopbackForTest &&
      (uri.host == '127.0.0.1' || uri.host == 'localhost');
  if (!isAllowedLoopbackTest && !isSafePublicVideoExportUri(uri)) {
    throw UnsupportedError(
      'Video source URL points to a blocked private or local host.',
    );
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    var currentUri = uri;
    HttpClientResponse? response;
    for (var hop = 0; hop <= _maxProjectRedirects; hop++) {
      final request = await client
          .getUrl(currentUri)
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      final candidate = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final status = candidate.statusCode;
      if (status == HttpStatus.movedPermanently ||
          status == HttpStatus.found ||
          status == HttpStatus.seeOther ||
          status == HttpStatus.temporaryRedirect ||
          status == HttpStatus.permanentRedirect) {
        await candidate.drain<void>();
        if (hop == _maxProjectRedirects) {
          throw HttpException(
            'Video source exceeded redirect limit.',
            uri: currentUri,
          );
        }
        final location =
            candidate.headers.value(HttpHeaders.locationHeader)?.trim() ?? '';
        if (location.isEmpty) {
          throw HttpException('Invalid video redirect.', uri: currentUri);
        }
        final nextUri = currentUri.resolve(location);
        if (!isSafePublicVideoExportUri(nextUri)) {
          throw UnsupportedError(
            'Video redirect to a private or local host was blocked.',
          );
        }
        currentUri = nextUri;
        continue;
      }
      response = candidate;
      break;
    }
    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw HttpException(
        'Video source returned HTTP ${response?.statusCode ?? 0}.',
      );
    }
    if (response.contentLength > limit) {
      await response.drain<void>();
      throw const FormatException('Project media exceeds 256 MiB.');
    }
    return await _collect(response, limit);
  } finally {
    client.close(force: true);
  }
}
