import 'package:video_player/video_player.dart';

class VideoCraftResource {
  VideoCraftResource(this.player, this.release);
  final VideoPlayerController player;
  final Future<void> Function() release;
}
