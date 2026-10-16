import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_video_editor/neom_video_editor.dart';

Uint8List media() => Uint8List.fromList([
  0,
  0,
  0,
  24,
  102,
  116,
  121,
  112,
  105,
  115,
  111,
  109,
  0,
  0,
  0,
  0,
  ...List<int>.generate(300, (i) => i % 256),
]);

VideoCraftProject project({String name = 'original.mp4'}) => VideoCraftProject(
  source: VideoCraftSource.bytes(media(), name: name),
  recipe: VideoCraftRecipe(
    sourceName: name,
    duration: const Duration(seconds: 8),
    frameRate: CraftFrameRate(24000, 1001),
    inFrame: 24,
    outFrame: 120,
    title: 'Título · música',
    opacityKeys: const {24: 1, 72: .5, 119: 0},
  ),
  frame: 72,
);

Uint8List rewriteHeader(
  Uint8List bytes,
  void Function(Map<String, dynamic>) change,
) {
  final length = ByteData.sublistView(bytes).getUint32(20);
  final metadata =
      jsonDecode(utf8.decode(bytes.sublist(28, 28 + length)))
          as Map<String, dynamic>;
  change(metadata);
  final header = utf8.encode(jsonEncode(metadata));
  final mediaBytes = bytes.sublist(28 + length, bytes.length - 32);
  final result = Uint8List(28 + header.length + mediaBytes.length + 32);
  result.setRange(0, 28, bytes);
  ByteData.sublistView(result).setUint32(20, header.length);
  result.setRange(28, 28 + header.length, header);
  result.setRange(28 + header.length, result.length - 32, mediaBytes);
  result.setRange(
    result.length - 32,
    result.length,
    sha256.convert(result.sublist(0, result.length - 32)).bytes,
  );
  return result;
}

void main() {
  test('round-trip retains exact media, rational FPS, edits and playhead', () {
    final original = project();
    final encoded = original.encode();
    final decoded = VideoCraftProject.decode(encoded);
    expect(decoded.source.bytes, original.source.bytes);
    expect(decoded.recipe.encode(), original.recipe.encode());
    expect(decoded.source.frameRate, original.recipe.frameRate);
    expect(decoded.frame, 72);
    encoded[encoded.length - 33] ^= 1;
    expect(
      decoded.source.bytes,
      original.source.bytes,
      reason: 'The decoded document owns its source, not the input buffer.',
    );
  });
  test('checksum detects corrupted media, metadata and checksum itself', () {
    final encoded = project().encode();
    for (final index in [28, encoded.length - 33, encoded.length - 1]) {
      final changed = Uint8List.fromList(encoded)..[index] ^= 1;
      expect(() => VideoCraftProject.decode(changed), throwsFormatException);
    }
  });
  test(
    'unsupported versions, trailing data and malicious lengths are rejected before allocation',
    () {
      final encoded = project().encode();
      final futureVersion = Uint8List.fromList(encoded);
      ByteData.sublistView(futureVersion).setUint32(16, 2);
      final hugeHeader = Uint8List.fromList(encoded);
      ByteData.sublistView(hugeHeader).setUint32(20, 0xffffffff);
      final hugeMedia = Uint8List.fromList(encoded);
      ByteData.sublistView(hugeMedia).setUint32(24, 0xffffffff);
      for (final bytes in [
        futureVersion,
        hugeHeader,
        hugeMedia,
        Uint8List.fromList([...encoded, 0]),
        encoded.sublist(0, encoded.length - 1),
      ]) {
        expect(() => VideoCraftProject.decode(bytes), throwsFormatException);
      }
    },
  );
  test(
    'strict project types and recipe bounds survive valid recomputed hashes',
    () {
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (h) => h['version'] = 1.5,
        (h) => h['frame'] = '72',
        (h) => h['frame'] = -1,
        (h) => h['unknown'] = true,
        (h) => h['container'] = 'avi',
        (h) => (h['recipe'] as Map)['outFrame'] = 99999,
        (h) => (h['recipe'] as Map)['sourceName'] = 'bad\u0000name',
      ]) {
        expect(
          () => VideoCraftProject.decode(
            rewriteHeader(project().encode(), mutation),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'URI-only source, arbitrary bytes and wrong source names cannot become projects',
    () {
      final recipe = project().recipe;
      for (final source in [
        VideoCraftSource.uri(
          Uri.parse('https://example.test/video.mp4'),
          name: recipe.sourceName,
        ),
        VideoCraftSource.bytes(
          Uint8List.fromList([1, 2, 3]),
          name: recipe.sourceName,
        ),
        VideoCraftSource.bytes(media(), name: 'other.mp4'),
      ]) {
        expect(
          () => VideoCraftProject(source: source, recipe: recipe),
          throwsFormatException,
        );
      }
    },
  );
}
