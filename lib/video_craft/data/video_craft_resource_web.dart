import 'dart:js_interop';
import 'package:video_player/video_player.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_origin_web.dart';
import 'video_craft_resource.dart';
import 'video_craft_url_security.dart';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts);
}
@JS('URL.createObjectURL')
external String _createObjectUrl(_Blob blob);
@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

Future<VideoCraftResource> createVideoCraftResource(
  VideoCraftSource source,
) async {
  final bytes = source.bytes;
  final String url;
  if (bytes == null) {
    final uri = source.uri;
    if (uri == null) {
      throw const FormatException('Video source requires bytes or a valid URI.');
    }
    final scheme = uri.scheme.toLowerCase();
    final allowed = scheme == 'blob'
        ? isSameOriginBlobUri(uri)
        : ((scheme == 'http' || scheme == 'https') &&
              isSafePublicVideoExportUri(uri));
    if (!allowed) {
      throw UnsupportedError(
        'Video preview URI uses a blocked scheme, host, or cross-origin blob.',
      );
    }
    url = uri.toString();
  } else {
    url = _createObjectUrl(_Blob(<JSAny>[bytes.toJS].toJS));
  }
  return VideoCraftResource(
    VideoPlayerController.networkUrl(Uri.parse(url)),
    () async {
      if (bytes != null) _revokeObjectUrl(url);
    },
  );
}
