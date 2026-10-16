import 'package:audioplayers/audioplayers.dart';

/// In-app cues for the two timers.
///
/// These play only while the app is on screen — once it is backgrounded the
/// alert comes from the notification channel instead, which carries its own
/// copy of the same sound (see NotificationService).
class AudioService {
  /// Rest between exercises is over.
  static const _restAsset = 'sounds/modern_ding.mp3';

  /// A timed set (plank, carry, hold) has run out.
  static const _setAsset = 'sounds/sweet_text.mp3';

  /// One player per cue, reused across plays. Creating a fresh AudioPlayer per
  /// sound leaks native handles on Android when fired repeatedly.
  static final AudioPlayer _restPlayer = AudioPlayer();
  static final AudioPlayer _setPlayer = AudioPlayer();

  static Future<void> _play(AudioPlayer player, String asset) async {
    try {
      // Restart from the beginning if the previous play is still running,
      // rather than overlapping two copies.
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // A missing asset or a busy audio focus should never take down a workout.
    }
  }

  /// Rest timer finished.
  static void playRestOverSound() => _play(_restPlayer, _restAsset);

  /// Per-set countdown finished.
  static void playSetOverSound() => _play(_setPlayer, _setAsset);

  /// Kept for call sites that just want "the timer is done" cue.
  static void playTimerSound() => playRestOverSound();

  static Future<void> dispose() async {
    await _restPlayer.dispose();
    await _setPlayer.dispose();
  }
}
