import 'dart:typed_data';

Future<Uint8List> readProjectUri(
  Uri uri,
  int limit, {
  bool allowLoopbackForTest = false,
}) => Future.error(
  UnsupportedError('Import a local video before saving a project.'),
);
