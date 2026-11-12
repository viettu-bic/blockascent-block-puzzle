import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/platform/audio_session.dart';

/// The session that fixed "gameplay has no music".
///
/// Every value here is one line of configuration and none of it is visible in
/// the app, which is exactly why it is pinned: the symptom of getting it wrong
/// is silence, and silence is not an error anyone can grep for.
void main() {
  // `configureAudioSession` talks to a platform channel, which needs a
  // binding even to find out that nothing is listening.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the game audio session', () {
    test('asks for no audio focus at all', () {
      // The bug: `audioplayers` defaults to AndroidAudioFocus.gain, so every
      // effect player requested permanent focus and Android dutifully told
      // our own music player it had lost it. One block placed, music gone for
      // the rest of the run.
      expect(gameAudioContext().android.audioFocus, AndroidAudioFocus.none);
    });

    test('presents itself as a game, not as a media player', () {
      expect(gameAudioContext().android.usageType, AndroidUsageType.game);
      expect(gameAudioContext().android.contentType, AndroidContentType.music);
      expect(gameAudioContext().android.stayAwake, isFalse);
    });

    test('is ambient on iOS, so the silent switch works', () {
      // Ambient also means a podcast or a music app keeps playing when the
      // game is opened, which is what anyone expects of a block puzzle.
      expect(gameAudioContext().iOS.category, AVAudioSessionCategory.ambient);
    });

    test('is a value, so nothing has to be awaited before the game starts',
        () {
      // It used to be applied globally with an await at boot, which hung four
      // widget tests at the splash and would have made a device with an
      // unhappy audio stack hang the same way. `Sfx` and `Music` hand it to
      // their own players instead.
      expect(gameAudioContext().android, isA<AudioContextAndroid>());
    });
  });
}
