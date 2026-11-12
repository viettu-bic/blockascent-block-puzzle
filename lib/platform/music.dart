/// Music: two loops, and the rules for when each plays.
///
/// ## What is playing
///
/// Two licensed tracks, both **CC0** from OpenGameArt, chosen for the night
/// sky the game now looks like (`docs/07` §4h) and for sounding digital rather
/// than orchestral:
///
/// - **menu** — *Outer Space Loop* by wipics. Ambient synths, stars and
///   galaxies.
/// - **gameplay** — *Beyond cosmos* by Centurion_of_war, the `sub_31` master:
///   retro spacesynth, the brightest and most chiptune of the three on its
///   page.
///
/// They replaced two generated loops that were correct on paper and awkward in
/// the ear (`docs/07` §4k). `tool/make_music.py` still exists and no longer
/// ships anything.
///
/// Neither source looped as downloaded — one faded out, the other did not meet
/// its own start — so `tool/fetch_music.py` trims each to the part that holds
/// its level and wraps the tail over the head with a crossfade. It also
/// matches their levels, which arrived 10 dB apart, and records the URL,
/// licence and SHA-256 of each source in `assets/music/SOURCES.md`.
///
/// **Both tracks centre on A, and the effects follow them.** `make_sfx.py` was
/// in C major pentatonic, which is a tritone from the menu track — the worst
/// available interval, heard on every line clear, which is the most frequent
/// sound in the game. The effects are tuned to **A major pentatonic** now. The
/// music is the fixed point and the effects move, because retuning ten
/// synthesised blips is a constant in a Python file and retuning a track is
/// not.
///
/// **They ship as WAV, not MP3.** Neither platform loops a compressed file
/// gaplessly — Android's `MediaPlayer` and iOS's `AVAudioPlayer` both
/// re-insert the codec's encoder delay at the wrap — so the trimming and
/// crossfading above would be undone at the last step. 32 kHz mono is the
/// compromise: full bandwidth for a chiptune, about 9 MB for the pair.
///
/// ## Volume
///
/// [volume] sits under the effects, which carry information the music does
/// not. It was 0.34 against tracks mastered to half scale, which measured
/// about 28 dB below full and was reported from a device as "so low" — a
/// setting nobody would ever turn *down*. The tracks are louder now and this
/// is 0.70; the effects still win, which is the only part that was ever the
/// point.
///
/// ## If it goes silent, read `lib/platform/audio_session.dart` first
///
/// Gameplay had no music at all until 2026-11-12, and the cause was not here:
/// every effect player was requesting permanent Android audio focus and
/// stopping this one. Nothing in this file could have shown that.
library;

import 'package:audioplayers/audioplayers.dart';

import 'audio_session.dart';

enum MusicTrack {
  /// During a run.
  gameplay('gameplay.wav'),

  /// Menu, shop, rules, summary — everywhere else.
  menu('menu.wav');

  const MusicTrack(this.asset);

  final String asset;
}

class Music {
  Music({this.enabled = true, this.volume = 0.70});

  bool enabled;

  /// Under the effects, which carry information where this carries none.
  final double volume;

  AudioPlayer? _player;
  MusicTrack? _current;
  bool _disposed = false;

  /// What is playing, or null when nothing is.
  MusicTrack? get current => _current;

  /// Start [track], or do nothing if it is already the one playing.
  ///
  /// The guard matters: this is called from screen transitions, and restarting
  /// the same loop on every rebuild would stutter the music every time the
  /// player opened the shop.
  Future<void> play(MusicTrack track) async {
    if (_disposed) return;
    if (!enabled) {
      // Remember the intent, so flipping the toggle back on starts the right
      // track rather than silence until the next screen change.
      _current = track;
      return;
    }
    if (_current == track && _player != null) return;
    _current = track;
    try {
      final p = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      // Never take audio focus: our own effects would silence this player,
      // which is what "gameplay has no music" was. See audio_session.dart.
      await p.setAudioContext(gameAudioContext());
      // Stop before switching source. Handing a new asset to a player that is
      // already looping is the one call in this class with no guaranteed
      // behaviour across platforms, and a failure here is silent by design
      // (see the catch below) — so it would present as "the other track never
      // starts", which is a long way from its cause.
      await p.stop();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(volume);
      await p.play(AssetSource('music/${track.asset}'));
    } catch (_) {
      // Deliberately swallowed: no audio route, no platform channel, a codec
      // that will not open. Music is the last thing that should end a run.
    }
  }

  /// Turn it on or off without losing which track belongs here.
  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    if (!value) {
      await _stopPlayer();
    } else if (_current != null) {
      final want = _current!;
      _current = null; // force `play` past its no-op guard
      await play(want);
    }
  }

  Future<void> _stopPlayer() async {
    try {
      await _player?.stop();
    } catch (_) {
      // Nothing useful to do.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _player?.dispose();
    } catch (_) {
      // Already gone.
    }
    _player = null;
    _current = null;
  }
}
