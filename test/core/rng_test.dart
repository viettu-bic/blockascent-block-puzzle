import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/rng.dart';

/// Gate #1 (spec §5.3 and §9). These vectors come from the proven TypeScript
/// mulberry32 in `reference/ts-core/core/rng.ts`. If they do not match to
/// 1e-15, the port of every seeded system below is worthless — stop and fix
/// the masking before reading any other failure in this suite.
void main() {
  group('golden vectors', () {
    test('Rng(12345).next() reproduces the JS stream', () {
      const expected = <double>[
        0.97972826776094735,
        0.30675226449966431,
        0.48420542152598500,
        0.81793441250920296,
        0.50942836934700608,
        0.34747186047025025,
        0.07375754183158278,
        0.76639646734111011,
        0.99682643939740956,
        0.82502248510718346,
      ];

      final rng = Rng(12345);
      for (var i = 0; i < expected.length; i++) {
        expect(rng.next(), closeTo(expected[i], 1e-15), reason: 'draw $i');
      }
    });

    test('Rng(12345).nextInt(11) reproduces the JS stream', () {
      final rng = Rng(12345);
      final got = List.generate(12, (_) => rng.nextInt(11));
      expect(got, [10, 3, 5, 8, 5, 3, 0, 8, 10, 9, 5, 10]);
    });

    test('Rng(7).shuffle([0..10]) reproduces the JS permutation', () {
      final got = Rng(7).shuffle(List<int>.generate(11, (i) => i));
      expect(got, [6, 4, 1, 9, 7, 2, 3, 5, 8, 10, 0]);
    });

    test('a cursor reconstructs the stream position exactly', () {
      // The 6th value of the seed-12345 stream, reached by replay rather than
      // by storing state. This is what makes a run resumable and a replay
      // verifiable.
      expect(Rng(12345, 5).next(), closeTo(0.34747186047025025, 1e-15));
    });
  });

  group('contract', () {
    test('next() stays in [0, 1) across a long stream', () {
      final rng = Rng(99);
      for (var i = 0; i < 20000; i++) {
        final v = rng.next();
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThan(1.0));
      }
    });

    test('cursor counts draws, including those made by nextInt and shuffle', () {
      final rng = Rng(1);
      expect(rng.cursor, 0);
      rng.next();
      rng.nextInt(10);
      expect(rng.cursor, 2);
      rng.shuffle(List<int>.generate(5, (i) => i)); // 4 draws
      expect(rng.cursor, 6);
    });

    test('nextInt is in range and never returns n', () {
      final rng = Rng(4242);
      for (var i = 0; i < 5000; i++) {
        final v = rng.nextInt(7);
        expect(v, inInclusiveRange(0, 6));
      }
    });

    test('the seed is masked to 32 bits, so a huge seed is still stable', () {
      expect(Rng(0x1FFFFFFFF).next(), closeTo(Rng(0xFFFFFFFF).next(), 0));
    });

    test('shuffle is a permutation, not a resampling', () {
      final got = Rng(31337).shuffle(List<int>.generate(50, (i) => i));
      expect(got.toSet().length, 50);
    });

    test('two Rngs with the same seed agree; different seeds diverge', () {
      final a = List.generate(20, (_) => 0.0);
      final ra = Rng(555);
      for (var i = 0; i < 20; i++) {
        a[i] = ra.next();
      }
      final rb = Rng(555);
      for (var i = 0; i < 20; i++) {
        expect(rb.next(), a[i]);
      }
      expect(Rng(556).next(), isNot(a[0]));
    });
  });
}
