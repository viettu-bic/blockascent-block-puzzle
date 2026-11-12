import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/platform/sfx.dart';

/// Sound has one failure mode that no amount of listening on one device will
/// catch reliably: a name that does not match a file. The result is silence,
/// and `Sfx` swallows its errors by design — a missing sound must never take a
/// run down — so a typo is invisible at runtime.
///
/// So the inventory is the test. Every sound `Sfx` can ask for has to exist, be
/// a real WAV, and be short enough to belong in a game that fires some of them
/// tens of times a stage.
void main() {
  /// Every asset `lib/platform/sfx.dart` plays, with the loudness ordering the
  /// design intends. Kept here deliberately: this list *is* the contract.
  const sounds = <String>[
    'snap.wav',
    'lift.wav',
    'place.wav',
    'clear.wav',
    'clear_big.wav',
    'break.wav',
    'stage.wav',
    'win.wav',
    'over.wav',
    'invalid.wav',
  ];

  group('the assets', () {
    test('every sound Sfx asks for exists', () {
      for (final name in sounds) {
        expect(
          File('assets/sfx/$name').existsSync(),
          isTrue,
          reason: 'assets/sfx/$name is missing — run tool/make_sfx.py',
        );
      }
    });

    test('nothing in the folder is unused, and nothing is unlisted', () {
      final onDisk = Directory('assets/sfx')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.wav'))
          .toSet();
      expect(
        onDisk,
        unorderedEquals(sounds),
        reason: 'a file nobody plays is dead weight in the bundle, and a name '
            'with no file is silence',
      );
    });

    test('each one is a real mono 22 kHz WAV', () {
      for (final name in sounds) {
        final b = File('assets/sfx/$name').readAsBytesSync();
        expect(b.length, greaterThan(44), reason: '$name is header-only');
        expect(
          String.fromCharCodes(b.sublist(0, 4)),
          'RIFF',
          reason: '$name is not a RIFF container',
        );
        expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE', reason: name);

        final view = ByteData.sublistView(b);
        expect(view.getUint16(22, Endian.little), 1, reason: '$name: mono');
        expect(
          view.getUint32(24, Endian.little),
          22050,
          reason: '$name: 22 kHz',
        );
        expect(view.getUint16(34, Endian.little), 16, reason: '$name: 16-bit');
      }
    });

    test('they are short, and the ticks are the shortest', () {
      int ms(String name) {
        final b = File('assets/sfx/$name').readAsBytesSync();
        // 16-bit mono at 22050: two bytes a frame, 44-byte header.
        return ((b.length - 44) / 2 / 22050 * 1000).round();
      }

      // Nothing may be long enough to still be playing over the next
      // placement — except the three that are followed by a screen rather
      // than by another move: a level clear opens the draft, and a win or a
      // loss opens the summary. Those have nothing to collide with.
      const standalone = {'stage.wav', 'win.wav', 'over.wav'};
      for (final name in sounds) {
        final limit = standalone.contains(name) ? 1000 : 500;
        expect(ms(name), lessThanOrEqualTo(limit), reason: name);
      }

      // The ticks fire on every cell the ghost crosses.
      expect(ms('snap.wav'), lessThan(30));
      expect(ms('lift.wav'), lessThan(60));

      // A clear should outlast a placement: one scores, the other does not.
      expect(ms('clear.wav'), greaterThan(ms('place.wav')));
      expect(ms('clear_big.wav'), greaterThan(ms('clear.wav')));
    });
  });

  group('disabled is genuinely inert', () {
    test('no call touches a player, so it is safe with no audio channel', () {
      // This is what lets every widget test construct one. If `Sfx` ever
      // built its pool eagerly, the whole UI suite would start failing on a
      // MissingPluginException.
      final s = Sfx(enabled: false);
      expect(
        () async {
          await s.lift();
          await s.snap();
          await s.place();
          await s.lineClear(1);
          await s.lineClear(3);
          await s.multiplierBreak();
          await s.stageClear();
          await s.runEnd();
          await s.win();
          await s.invalid();
          await s.dispose();
        },
        returnsNormally,
      );
    });

    test('a disposed instance stays quiet even if re-enabled', () async {
      final s = Sfx(enabled: false);
      await s.dispose();
      s.enabled = true;
      await s.place();
      // Nothing to assert but the absence of a throw: the guard is that
      // `_disposed` is checked before any player is reached.
      expect(true, isTrue);
    });
  });
}
