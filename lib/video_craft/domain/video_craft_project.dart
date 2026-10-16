import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'video_craft_recipe.dart';
import 'video_craft_source.dart';

/// Portable, self-contained editing document. Original compressed media bytes
/// are embedded, not re-encoded; the recipe remains independently versioned.
/// SHA-256 detects corruption, not the identity/authenticity of an author.
class VideoCraftProject {
  VideoCraftProject({required this.source, required this.recipe, int? frame})
    : frame = frame ?? recipe.inFrame {
    final bytes = source.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > maxMediaBytes) {
      throw const FormatException(
        'A project requires video bytes up to 256 MiB.',
      );
    }
    if (source.name != recipe.sourceName ||
        source.name.contains('\u0000') ||
        this.frame < 0 ||
        this.frame >= recipe.frameCount) {
      throw const FormatException(
        'Project source, recipe or playhead is invalid.',
      );
    }
    _containerKind(bytes);
  }

  static const extension = 'neomvideoproject';
  static const maxMediaBytes = 256 * 1024 * 1024;
  static const maxHeaderBytes = 1024 * 1024;
  static const maxProjectBytes = maxMediaBytes + maxHeaderBytes + 64;
  static const _prefixLength = 28;
  static final _magic = ascii.encode('NEOMVIDPROJECT\r\n'); // 16 bytes
  final VideoCraftSource source;
  final VideoCraftRecipe recipe;
  final int frame;

  Uint8List encode() {
    final media = source.bytes!;
    final header = utf8.encode(
      jsonEncode({
        'format': 'neom-video-project',
        'version': 1,
        'container': _containerKind(media),
        'recipe': jsonDecode(recipe.encode()),
        'frame': frame,
      }),
    );
    if (header.length > maxHeaderBytes) {
      throw const FormatException('Project metadata exceeds 1 MiB.');
    }
    final result = Uint8List(_prefixLength + header.length + media.length + 32);
    result.setRange(0, _magic.length, _magic);
    final prefix = ByteData.sublistView(result);
    prefix.setUint32(16, 1);
    prefix.setUint32(20, header.length);
    prefix.setUint32(24, media.length);
    result.setRange(_prefixLength, _prefixLength + header.length, header);
    result.setRange(_prefixLength + header.length, result.length - 32, media);
    result.setRange(
      result.length - 32,
      result.length,
      sha256
          .convert(Uint8List.sublistView(result, 0, result.length - 32))
          .bytes,
    );
    return result;
  }

  factory VideoCraftProject.decode(Uint8List bytes) {
    if (bytes.length < _prefixLength + 32 || bytes.length > maxProjectBytes) {
      throw const FormatException('Project is empty, truncated or too large.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('This is not a Neom video project.');
      }
    }
    final prefix = ByteData.sublistView(bytes);
    if (prefix.getUint32(16) != 1) {
      throw const FormatException('Unsupported video project version.');
    }
    final headerLength = prefix.getUint32(20);
    final mediaLength = prefix.getUint32(24);
    if (headerLength == 0 ||
        headerLength > maxHeaderBytes ||
        mediaLength == 0 ||
        mediaLength > maxMediaBytes ||
        bytes.length != _prefixLength + headerLength + mediaLength + 32) {
      throw const FormatException('Invalid project lengths or trailing data.');
    }
    final actual = sha256
        .convert(Uint8List.sublistView(bytes, 0, bytes.length - 32))
        .bytes;
    var mismatch = 0;
    for (var i = 0; i < 32; i++) {
      mismatch |= actual[i] ^ bytes[bytes.length - 32 + i];
    }
    if (mismatch != 0) {
      throw const FormatException('Project integrity check failed (SHA-256).');
    }
    try {
      final header =
          jsonDecode(
                utf8.decode(
                  Uint8List.sublistView(
                    bytes,
                    _prefixLength,
                    _prefixLength + headerLength,
                  ),
                ),
              )
              as Map<String, dynamic>;
      const keys = {'format', 'version', 'container', 'recipe', 'frame'};
      if (header.keys.toSet().difference(keys).isNotEmpty ||
          !header.keys.toSet().containsAll(keys) ||
          header['format'] != 'neom-video-project' ||
          header['version'] is! int ||
          header['version'] != 1 ||
          header['frame'] is! int ||
          header['recipe'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid project metadata or version.');
      }
      final media = Uint8List.sublistView(
        bytes,
        _prefixLength + headerLength,
        bytes.length - 32,
      );
      if (header['container'] != _containerKind(media)) {
        throw const FormatException('Project media container does not match.');
      }
      final recipeMetadata = header['recipe'] as Map<String, dynamic>;
      if (recipeMetadata['version'] is! int) {
        throw const FormatException('Invalid recipe version.');
      }
      final recipe = VideoCraftRecipe.decode(jsonEncode(recipeMetadata));
      return VideoCraftProject(
        source: VideoCraftSource.bytes(
          media,
          name: recipe.sourceName,
          frameRate: recipe.frameRate,
        ),
        recipe: recipe,
        frame: header['frame'] as int,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid video project metadata.');
    }
  }

  static String _containerKind(Uint8List bytes) {
    if (bytes.length >= 12) {
      final atom = String.fromCharCodes(bytes.sublist(4, 8));
      if (const {
        'ftyp',
        'moov',
        'mdat',
        'wide',
        'free',
        'skip',
      }.contains(atom)) {
        return 'iso-bmff';
      }
      if (String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'AVI ') {
        return 'avi';
      }
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return 'ebml';
    }
    throw const FormatException(
      'Projects support MP4/MOV, WebM/MKV or AVI media.',
    );
  }
}
