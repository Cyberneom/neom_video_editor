import 'dart:js_interop';
import 'package:video_player/video_player.dart';
import '../domain/video_craft_source.dart';
import 'video_craft_resource.dart';

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
  final url = bytes == null
      ? source.uri!.toString()
      : _createObjectUrl(_Blob(<JSAny>[bytes.toJS].toJS));
  return VideoCraftResource(
    VideoPlayerController.networkUrl(Uri.parse(url)),
    () async {
      if (bytes != null) _revokeObjectUrl(url);
    },
  );
}
