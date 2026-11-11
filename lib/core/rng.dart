/// Seeded PRNG (mulberry32), ported from `reference/ts-core/core/rng.ts`.
///
/// Deterministic and replayable: `Rng(seed, cursor)` reconstructs the exact
/// stream position, which is what buys daily challenges with a fixed seed,
/// shareable runs and server-verifiable scores later.
///
/// ## Why every mask is here
///
/// JavaScript coerces to 32 bits at *each* bitwise operation and `Math.imul`
/// returns a 32-bit product. Dart's ints are 64-bit on native (and
/// BigInt-backed on web), so each of those coercions has to be written out as
/// `& 0xFFFFFFFF` — including the intermediate `t + _mul32(...)`, which is an
/// addition rather than a bitwise op and therefore the one most likely to be
/// missed. Drop a single mask and the stream silently diverges: the game still
/// plays, and every seeded feature is quietly broken.
///
/// `test/core/rng_test.dart` pins the stream to golden vectors (spec §5.3).
/// Nothing downstream is trustworthy until those pass.
library;

const int _mask32 = 0xFFFFFFFF;

class Rng {
  Rng(this.seed, [int cursor = 0]) : _state = seed & _mask32 {
    for (var i = 0; i < cursor; i++) {
      next();
    }
  }

  final int seed;

  /// How many values have been drawn. Persist this with the seed to resume a
  /// stream mid-run.
  int cursor = 0;

  int _state;

  /// `Math.imul`: the low 32 bits of the product, interpreted as unsigned.
  static int _mul32(int a, int b) => (a * b) & _mask32;

  /// Next float in [0, 1).
  double next() {
    cursor++;
    _state = (_state + 0x6D2B79F5) & _mask32;
    var t = _state;
    t = _mul32(t ^ (t >>> 15), t | 1);
    t = (t ^ ((t + _mul32(t ^ (t >>> 7), t | 61)) & _mask32)) & _mask32;
    return ((t ^ (t >>> 14)) & _mask32) / 4294967296.0;
  }

  /// Integer in [0, n).
  int nextInt(int n) => (next() * n).floor();

  /// Fisher-Yates, in place, descending — the same direction as the oracle, so
  /// the same seed produces the same permutation.
  List<T> shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final a = items[i];
      items[i] = items[j];
      items[j] = a;
    }
    return items;
  }

  /// Pick one element. Does not mutate.
  T pick<T>(List<T> items) => items[nextInt(items.length)];
}

/// A seed worth showing to a player: short, typeable, copy-pasteable.
int randomSeed() => DateTime.now().microsecondsSinceEpoch & _mask32;
