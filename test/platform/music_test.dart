import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/platform/music.dart';

/// The music is two licensed CC0 tracks now, edited into loops by
/// `tool/fetch_music.py` (`docs/07` §4k). Three things about that are easy to
/// get wrong and impossible to notice in a five-second listen, so they are
/// measured here rather than trusted:
///
/// 1. **The loop seam.** A track that fades, or whose end does not meet its
///    start, breathes or ticks every time round — once a minute, forever. The
///    sources did both; the tool trims and wraps the tail over the head.
/// 2. **The level.** The two arrived 10 dB apart, which is heard as the menu
///    shouting and the game whispering.
/// 3. **The key.** The sound effects are a pentatonic set and a line clear is
///    the most frequent sound in the game, so effects in the wrong key clash
///    every single time the player scores. They are tuned to the music, not
///    the other way round.
void main() {
  const rate = 32000;

  /// 16-bit mono PCM, skipping the 44-byte canonical WAV header. The files are
  /// written by Python's `wave` module, which emits exactly that header.
  List<int> samples(String name) {
    final b = File('assets/music/$name').readAsBytesSync();
    final view = ByteData.sublistView(b, 44);
    return [
      for (var i = 0; i + 1 < view.lengthInBytes; i += 2)
        view.getInt16(i, Endian.little),
    ];
  }

  double rms(List<int> xs) =>
      sqrt(xs.fold<double>(0, (a, v) => a + v * v) / xs.length);

  /// Power at one frequency, by Goertzel — a single-bin DFT, which is all that
  /// is wanted here and a great deal less code than an FFT.
  double powerAt(List<int> xs, double freq) {
    final k = 2 * cos(2 * pi * freq / rate);
    var s1 = 0.0;
    var s2 = 0.0;
    for (final v in xs) {
      final s0 = v + k * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    return (s1 * s1 + s2 * s2 - k * s1 * s2) / (xs.length * xs.length);
  }

  /// Energy on a set of pitch classes, over three octaves, as a fraction of
  /// the energy on all twelve.
  double shareOf(List<int> xs, List<int> pitchClasses) {
    double energy(List<int> classes) {
      var sum = 0.0;
      for (final pc in classes) {
        for (final octave in [3, 4, 5]) {
          sum += powerAt(xs, 261.6255 * pow(2, pc / 12 + octave - 4));
        }
      }
      return sum;
    }

    final all = energy(List.generate(12, (i) => i));
    return all == 0 ? 0 : energy(pitchClasses) / all;
  }

  for (final track in MusicTrack.values) {
    final name = track.asset;

    group('${track.name} ($name)', () {
      test('exists and is a mono 32 kHz 16-bit WAV', () {
        // WAV, not MP3, and that is deliberate: neither Android's MediaPlayer
        // nor iOS's AVAudioPlayer loops a compressed file gaplessly — both
        // re-insert the codec's encoder delay at the wrap. See
        // tool/fetch_music.py.
        final f = File('assets/music/$name');
        expect(f.existsSync(), isTrue,
            reason: 'run tool/fetch_music.py to build it');
        final b = f.readAsBytesSync();
        expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
        final view = ByteData.sublistView(b);
        expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
        expect(view.getUint32(24, Endian.little), rate);
        expect(view.getUint16(34, Endian.little), 16);
      });

      test('is long enough not to feel like a loop, small enough to ship', () {
        final seconds = samples(name).length / rate;
        expect(seconds, greaterThan(30),
            reason: 'a short loop announces itself');
        expect(seconds, lessThan(150));
        expect(File('assets/music/$name').lengthSync(), lessThan(8 << 20),
            reason: 'uncompressed, so this is the cost of looping gaplessly');
      });

      test('loops without breathing', () {
        final s = samples(name);
        final half = rate ~/ 2;
        final tail = rms(s.sublist(s.length - half));
        final mid = rms(
            s.sublist(s.length ~/ 2 - half ~/ 2, s.length ~/ 2 + half ~/ 2));

        // The end has to carry the same weight as the body. The menu source
        // dropped 8 dB into a quiet outro and then to silence; looped as
        // downloaded it measured 0.00 here.
        expect(
          tail / mid,
          inInclusiveRange(0.6, 1.6),
          reason: '$name: tail ${tail.round()} against mid ${mid.round()}',
        );
      });

      test('has no discontinuity at the join', () {
        final s = samples(name);
        // Measured against what this track does between any two samples, not
        // against an absolute threshold: at -1 dBFS a 1 kHz tone moves 0.19 of
        // full scale per sample at 32 kHz, so a continuous join on a bright
        // chiptune looks enormous in absolute terms and a silent join on a pad
        // looks perfect. A discontinuity is a jump much larger than its
        // neighbours.
        var local = 0.0;
        for (var i = s.length - 2001; i < s.length - 1; i++) {
          local += (s[i + 1] - s[i]).abs();
        }
        local /= 2000;
        final join = (s.first - s.last).abs() / max(local, 1);
        expect(join, lessThan(4.0),
            reason: '$name: the join is ${join.toStringAsFixed(1)}x the '
                'typical step either side of it');
      });

      test('is loud enough, and matches the other track', () {
        final s = samples(name);
        final peak = s.map((v) => v.abs()).reduce(max) / 32768;
        final level = 20 * (log(rms(s) / 32768) / ln10);
        expect(peak, lessThan(0.95), reason: 'leaves headroom');
        expect(level, greaterThan(-17.0), reason: '$name is $level dBFS');
        expect(level, lessThan(-12.0), reason: '$name is $level dBFS');
      });
    });
  }

  group('the music and the effects agree', () {
    // A major pentatonic: A, B, C#, E, F#. Both tracks centre on A, and
    // tool/make_sfx.py is tuned to the same set, so a line clear is consonant
    // with whatever is playing underneath it.
    const aPentatonic = [9, 11, 1, 4, 6];
    const cPentatonic = [0, 2, 4, 7, 9];

    test('the gameplay track is in the key the effects are tuned to', () {
      final s = samples(MusicTrack.gameplay.asset);
      // Two seconds from the middle, which is where a track is most itself.
      final mid = s.sublist(s.length ~/ 2, s.length ~/ 2 + 2 * rate);
      final a = shareOf(mid, aPentatonic);
      final c = shareOf(mid, cPentatonic);
      expect(a, greaterThan(0.5),
          reason: 'only ${(a * 100).round()}% of its energy is on A pentatonic');
      expect(a, greaterThan(c),
          reason: 'the effects were in C until the music arrived in A');
    });
  });

  group('provenance', () {
    test('every shipped track is recorded with its licence', () {
      // CC0 needs no attribution. This file is not a credits screen — it is
      // the answer to "where did this come from", which gets asked at store
      // submission, long after anyone remembers.
      final sources = File('assets/music/SOURCES.md').readAsStringSync();
      expect(sources, contains('CC0'));
      expect(sources, contains('opengameart.org'));
      for (final track in MusicTrack.values) {
        expect(sources, contains(track.asset), reason: track.asset);
      }
    });

    test('nothing ships in the music folder that nothing plays', () {
      final played = MusicTrack.values.map((t) => t.asset).toSet();
      final onDisk = Directory('assets/music')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.endsWith('.wav'))
          .toSet();
      expect(onDisk, played);
    });
  });

  group('the player', () {
    test('disabled, it still remembers which track belongs here', () async {
      // Otherwise flipping the toggle back on gives silence until the next
      // screen change, which on a menu could be a long time.
      final m = Music(enabled: false);
      await m.play(MusicTrack.menu);
      expect(m.current, MusicTrack.menu);
    });

    test('disabled, nothing it is asked to do throws', () async {
      final m = Music(enabled: false);
      await m.play(MusicTrack.menu);
      await m.play(MusicTrack.gameplay);
      await m.setEnabled(false);
      await m.dispose();
      expect(m.current, isNull);
    });

    test('sits under the effects, without being a setting nobody turns down',
        () {
      // It was 0.34 against tracks mastered to half scale — about 28 dB below
      // full once both are counted — and the first device report called the
      // music "so low". Under the effects is the rule; inaudible was never
      // the rule.
      expect(Music().volume, lessThan(1.0));
      expect(Music().volume, greaterThan(0.6));
    });
  });
}
