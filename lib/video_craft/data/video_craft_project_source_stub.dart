import 'dart:typed_data';

Future<Uint8List> readProjectUri(Uri uri, int limit) => Future.error(
  UnsupportedError('Import a local video before saving a project.'),
);
