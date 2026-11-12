/// Sound effects.
///
/// A sibling of [Haptics] in every sense: the same events, the same loudness
/// ordering, the same reason for it. A placement that clears nothing is worth
/// zero points (docs/05 §10), so it gets a dull thunk; clearing is the only way
/// to score, so it gets the bright one; and the end of a run — 43% of early
/// deaths are jams — is the second loudest thing in the game.
///
/// ## The assets are generated, not sourced
///
/// `tool/make_sfx.py` synthesises all ten from sine partials and seeded noise,
/// with the Python standard library and nothing else. So there is **no licence,
/// no attribution and no provenance question** on any of it, and regenerating
/// is byte-identical. For a block puzzle that is not a compromise — the palette
/// is short percussive blips and arpeggios, which is what additive synthesis is
/// good at. They sit in C major pentatonic so they read as one family however
/// they overlap.
///
/// ## Why a pool of players
///
/// A single [AudioPlayer] cuts its own sound off to start the next one, and
/// these overlap constantly: a snap tick while a clear is still ringing is the
/// normal case. Four voices cycled round is enough for that and bounded, where
/// a player per call would leak one per placement.
///
/// Every call is **fire and forget and swallows its errors**. A device with no
/// audio route, a test with no platform channel, a codec that will not open —
/// none of that may take a run down for the sake of a sound effect.
library;

import 'package:audioplayers/audioplayers.dart';

import 'audio_session.dart';

class Sfx {
  Sfx({this.enabled = true, this.voices = 4});

  bool enabled;

  /// How many sounds may overlap. Four is enough for a snap tick over a clear
  /// that is still ringing, and bounded where a player per call would leak one
  /// per placement.
  final int voices;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  bool _disposed = false;

  /// Snap ticks fire on every cell the ghost crosses, so they are rate-limited
  /// for the same reason the haptic is: one per crossing is the point, one per
  /// frame is a buzzing mess.
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _tickFloor = Duration(milliseconds: 40);

  /* ---------------- the events ---------------- */

  Future<void> lift() {
    _lastTick = DateTime.now();
    return _play('lift.wav');
  }

  Future<void> snap() {
    final now = DateTime.now();
    if (now.difference(_lastTick) < _tickFloor) return Future<void>.value();
    _lastTick = now;
    return _play('snap.wav');
  }

  Future<void> place() => _play('place.wav');

  /// Two or more lines at once gets its own sound, because the line bonus is
  /// deliberately super-linear and the feedback should say so.
  Future<void> lineClear(int lines) =>
      _play(lines >= 2 ? 'clear_big.wav' : 'clear.wav');

  Future<void> multiplierBreak() => _play('break.wav');

  Future<void> stageClear() => _play('stage.wav');

  Future<void> runEnd() => _play('over.wav');

  Future<void> win() => _play('win.wav');

  Future<void> invalid() => _play('invalid.wav');

  /* ---------------- plumbing ---------------- */

  /// Lazy, so a disabled [Sfx] never constructs a player and never touches a
  /// platform channel. That is what makes it safe in a test.
  AudioPlayer _voice() {
    if (_pool.length < voices) {
      // `setAudioContext` is what stops an effect taking audio focus and
      // silencing the music — see lib/platform/audio_session.dart. It is on
      // the player, not global, so there is no ordering to get wrong.
      final p = AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop)
        ..setAudioContext(gameAudioContext());
      _pool.add(p);
      return p;
    }
    final p = _pool[_next];
    _next = (_next + 1) % voices;
    return p;
  }

  Future<void> _play(String name) async {
    if (!enabled || _disposed) return;
    try {
      await _voice().play(AssetSource('sfx/$name'));
    } catch (_) {
      // Deliberately swallowed — see the class comment.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final p in _pool) {
      try {
        await p.dispose();
      } catch (_) {
        // Nothing useful to do if a player is already gone.
      }
    }
    _pool.clear();
  }
}
