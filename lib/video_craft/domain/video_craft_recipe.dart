import 'dart:convert';

import 'package:neom_effectcraft/neom_effectcraft.dart';
import 'package:neom_filmcraft/neom_filmcraft.dart';

/// A non-destructive editing recipe. The video bytes are never embedded.
class VideoCraftRecipe {
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
        duration.inMicroseconds <= 0 ||
        duration > const Duration(hours: 24) ||
        frameRate.framesPerSecond < 1 ||
        frameRate.framesPerSecond > 240 ||
        frameRate.numerator > BigInt.from(1000000) ||
        frameRate.denominator > BigInt.from(1000000) ||
        inFrame < 0 ||
        outFrame <= inFrame ||
        outFrame > frameCount ||
        title.length > 1000 ||
        opacityKeys.length > 1000 ||
        opacityKeys.entries.any(
          (e) =>
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
      if (json['format'] != 'neom-video-recipe' || json['version'] != 1) {
        throw const FormatException('Unsupported recipe format');
      }
      final rate = json['frameRate'] as Map<String, dynamic>;
      final rawKeys = json['opacityKeys'] as List;
      if (rawKeys.length > 1000) throw const FormatException('Too many keys');
      final keys = <int, double>{};
      for (final raw in rawKeys) {
        final entry = raw as Map<String, dynamic>;
        final frame = entry['frame'] as int;
        if (keys.containsKey(frame)) {
          throw const FormatException('Duplicate key');
        }
        keys[frame] = (entry['value'] as num).toDouble();
      }
      return VideoCraftRecipe(
        sourceName: json['sourceName'] as String,
        duration: Duration(microseconds: json['durationUs'] as int),
        frameRate: CraftFrameRate.fromBigInt(
          BigInt.parse(rate['numerator'] as String),
          BigInt.parse(rate['denominator'] as String),
        ),
        inFrame: json['inFrame'] as int,
        outFrame: json['outFrame'] as int,
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
