import 'dart:convert';

import 'package:neom_effectcraft/neom_effectcraft.dart';
import 'package:neom_filmcraft/neom_filmcraft.dart';

/// A non-destructive editing recipe. The video bytes are never embedded.
class VideoCraftRecipe {
  static final RegExp _forbiddenTextChars = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u0085\u061C\u200B-\u200F\u2028-\u202E\u2060\u2066-\u2069\uFEFF]',
  );
  static final RegExp _positiveBigIntDigits = RegExp(r'^\d{1,24}$');

  static int _requireFiniteInt(Object? v, String field) {
    if (v is! int || !(v as num).isFinite) {
      throw FormatException('Invalid integer field: $field');
    }
    return v;
  }

  VideoCraftRecipe({
    required this.sourceName,
    required this.duration,
    required this.frameRate,
    required this.inFrame,
    required this.outFrame,
    this.title = 'Title',
    Map<int, double> opacityKeys = const {0: 1},
  }) : opacityKeys = Map.unmodifiable(opacityKeys) {
    if (sourceName.isEmpty ||
        sourceName.length > 1024 ||
        sourceName.contains('\u0000') ||
        _forbiddenTextChars.hasMatch(sourceName) ||
        duration.inMicroseconds <= 0 ||
        duration > const Duration(hours: 24) ||
        frameRate.framesPerSecond < 1 ||
        frameRate.framesPerSecond > 240 ||
        frameRate.numerator > BigInt.from(1000000) ||
        frameRate.denominator > BigInt.from(1000000) ||
        !(inFrame as num).isFinite ||
        !(outFrame as num).isFinite ||
        inFrame < 0 ||
        outFrame <= inFrame ||
        outFrame > frameCount ||
        title.length > 1000 ||
        _forbiddenTextChars.hasMatch(title) ||
        opacityKeys.length > 1000 ||
        opacityKeys.entries.any(
          (e) =>
              !(e.key as num).isFinite ||
              e.key < 0 ||
              e.key >= frameCount ||
              !e.value.isFinite ||
              e.value < 0 ||
              e.value > 1,
        )) {
      throw const FormatException('Invalid video recipe or frame range');
    }
  }

  final String sourceName;
  final Duration duration;
  final CraftFrameRate frameRate;
  final int inFrame;

  /// Exclusive end frame, so [inFrame, outFrame) always contains full frames.
  final int outFrame;
  final String title;
  final Map<int, double> opacityKeys;

  int get frameCount => frameRate
      .frameAt(
        CraftTick.fromUnits(
          BigInt.from(duration.inMicroseconds),
          BigInt.from(1000000),
        ),
      )
      .toInt();

  Duration timeAtFrame(int frame) {
    final ticks = frameRate.atFrame(frame).ticks;
    // Round up to microseconds: seeking frame 1 at 30fps must not land in frame 0.
    final micros =
        (ticks * BigInt.from(1000000) +
            CraftTick.ticksPerSecond -
            BigInt.one) ~/
        CraftTick.ticksPerSecond;
    return Duration(microseconds: micros.toInt());
  }

  int frameAtTime(Duration position) => frameRate
      .frameAt(
        CraftTick.fromUnits(
          BigInt.from(position.inMicroseconds),
          BigInt.from(1000000),
        ),
      )
      .toInt()
      .clamp(0, frameCount - 1);

  String timecode(int frame) => FilmTimecode.formatFrames(
    BigInt.from(frame),
    frameRate,
    dropFrame: frameRate.supportsDropFrame,
  );

  double opacityAt(int frame) =>
      (EffectScalarTrack([
                for (final entry in opacityKeys.entries)
                  EffectScalarKeyframe(
                    frameRate.atFrame(entry.key),
                    entry.value,
                  ),
              ]).evaluate(frameRate.atFrame(frame)) ??
              1)
          .clamp(0.0, 1.0);

  VideoCraftRecipe copyWith({
    int? inFrame,
    int? outFrame,
    String? title,
    Map<int, double>? opacityKeys,
  }) => VideoCraftRecipe(
    sourceName: sourceName,
    duration: duration,
    frameRate: frameRate,
    inFrame: inFrame ?? this.inFrame,
    outFrame: outFrame ?? this.outFrame,
    title: title ?? this.title,
    opacityKeys: opacityKeys ?? this.opacityKeys,
  );

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': 'neom-video-recipe',
    'version': 1,
    'sourceName': sourceName,
    'durationUs': duration.inMicroseconds,
    'frameRate': {
      'numerator': frameRate.numerator.toString(),
      'denominator': frameRate.denominator.toString(),
    },
    'inFrame': inFrame,
    'outFrame': outFrame,
    'title': title,
    'opacityKeys': [
      for (final frame in opacityKeys.keys.toList()..sort())
        {'frame': frame, 'value': opacityKeys[frame]},
    ],
  });

  factory VideoCraftRecipe.decode(String text) {
    if (text.length > 1000000) {
      throw const FormatException('Recipe is too large');
    }
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['format'] != 'neom-video-recipe' ||
          _requireFiniteInt(json['version'], 'version') != 1) {
        throw const FormatException('Unsupported recipe format');
      }
      final rate = json['frameRate'] as Map<String, dynamic>;
      final numStr = (rate['numerator'] as String).trim();
      final denStr = (rate['denominator'] as String).trim();
      if (!_positiveBigIntDigits.hasMatch(numStr) ||
          !_positiveBigIntDigits.hasMatch(denStr)) {
        throw const FormatException('Invalid frameRate rational');
      }
      final rawKeys = json['opacityKeys'] as List;
      if (rawKeys.length > 1000) throw const FormatException('Too many keys');
      final keys = <int, double>{};
      for (final raw in rawKeys) {
        final entry = raw as Map<String, dynamic>;
        final frame = _requireFiniteInt(entry['frame'], 'frame');
        if (keys.containsKey(frame)) {
          throw const FormatException('Duplicate key');
        }
        final value = (entry['value'] as num).toDouble();
        if (!value.isFinite) {
          throw const FormatException('Non-finite opacity key');
        }
        keys[frame] = value;
      }
      final durationUs = _requireFiniteInt(json['durationUs'], 'durationUs');
      if (durationUs <= 0 || durationUs > const Duration(hours: 24).inMicroseconds) {
        throw const FormatException('Invalid durationUs');
      }
      return VideoCraftRecipe(
        sourceName: json['sourceName'] as String,
        duration: Duration(microseconds: durationUs),
        frameRate: CraftFrameRate.fromBigInt(
          BigInt.parse(numStr),
          BigInt.parse(denStr),
        ),
        inFrame: _requireFiniteInt(json['inFrame'], 'inFrame'),
        outFrame: _requireFiniteInt(json['outFrame'], 'outFrame'),
        title: json['title'] as String,
        opacityKeys: keys,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid video recipe');
    }
  }
}
