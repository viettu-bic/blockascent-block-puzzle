/// The audio session — and the bug that made it necessary.
///
/// ## Why gameplay had no music
///
/// Reported from a device, 2026-11-12: *"on main gameplay no background music
/// plays at all"*, while the menu loop played normally.
///
/// `audioplayers` defaults every player to **`AndroidAudioFocus.gain`**, which
/// is a request for permanent audio focus: "this app is now the sole source of
/// audio". Android grants it and then tells every other focus listener it has
/// lost focus — *including listeners in the same app*. `Sfx` holds four
/// players and fires one on every snap, lift, place and clear, so the first
/// block placed in a run took the focus away from the music player, which
/// stopped and never came back.
///
/// That is exactly the observed shape of it. The menu fires almost no effects,
/// so the loop there survived; gameplay fires one within a second or two of
/// the run starting, so it did not. It also explains why nothing was ever
/// logged: losing focus is not an error, it is the system doing as it was
/// asked.
///
/// So the game asks for **no focus at all**. It is background music and short
/// blips on top of a puzzle; it is not a music player and has no business
/// stopping one.
///
/// ## What this also buys
///
/// On iOS the category is `ambient`, which means two things players expect of
/// a casual game and get from almost nothing else:
///
/// - the **ring/silent switch silences it**, which is the behaviour anyone who
///   opens a game on a bus is relying on, and
/// - **other apps keep playing** — a podcast, a music app — rather than being
///   cut off because a block puzzle was opened.
///
/// `ambient` is non-mixable-interrupting by definition, so no explicit
/// `mixWithOthers` option is needed; the category's own assertion in
/// `audioplayers` would reject it anyway.
///
/// ## Applied per player, not globally
///
/// `AudioPlayer.global.setAudioContext` exists and would be tidier, but it is
/// an `await` on a platform channel that has to land before the first player
/// is built — which means boot waits on audio, and a boot that waits on audio
/// is a boot that can hang on a device whose audio stack is unhappy. It also
/// made four widget tests sit for ever at the splash.
///
/// So [gameAudioContext] is a plain value and the two owners — `Sfx` when it
/// builds a voice, `Music` when it starts a track — hand it to their own
/// players. Deterministic, no ordering to get wrong, and nothing to await
/// before the game can start.
library;

import 'package:audioplayers/audioplayers.dart';

/// The session the game wants: never take focus, never interrupt, obey the
/// silent switch.
///
/// A plain value with no platform call in it, so
/// `test/platform/audio_session_test.dart` can assert the part that actually
/// matters — the focus mode — without a device.
AudioContext gameAudioContext() => AudioContext(
  android: const AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.game,
    // The fix. Anything else and our own effects mute our own music.
    audioFocus: AndroidAudioFocus.none,
  ),
  iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
);
