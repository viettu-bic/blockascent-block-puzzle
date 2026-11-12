import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/shapes.dart';

/// Ported from `reference/ts-tests/shapes.test.ts`.
void main() {
  group('rotations', () {
    // Deduplicating rotations is a feel requirement: tapping a square should
    // visibly do nothing rather than cycle four identical states.
    const expected = <String, int>{
      'dot': 1, 'o2': 1, 'x5': 1, 'o3': 1,
      'i2': 2, 'i3': 2, 'i4': 2, 'i5': 2, 's4': 2, 'z4': 2,
      'r23': 2, 'r24': 2, 'z5': 2,
      'l3': 4, 't4': 4, 'j4': 4, 'l4': 4, 'u5': 4, 'p5': 4, 't5': 4,
      'w5': 4, 'f5': 4,
    };

    expected.forEach((id, count) {
      test('$id has $count distinct rotations', () {
        expect(shape(id).rotations, hasLength(count));
      });
    });

    test('the expectation table covers the whole roster', () {
      expect(expected.keys.toSet(), allShapes.map((s) => s.id).toSet());
      expect(allShapes, hasLength(22));
    });

    test('normalises every rotation to the origin', () {
      for (final s in allShapes) {
        for (final rotation in s.rotations) {
          expect(rotation.map((c) => c.$1).reduce((a, b) => a < b ? a : b), 0);
          expect(rotation.map((c) => c.$2).reduce((a, b) => a < b ? a : b), 0);
        }
      }
    });

    test('preserves cell count across rotations', () {
      for (final s in allShapes) {
        for (final rotation in s.rotations) {
          expect(rotation, hasLength(s.cellCount));
        }
      }
    });

    test('every rotation is in canonical row-major order', () {
      // normalise() sorts, so two equal shapes always produce equal keys —
      // which is what the dedupe and the no-duplicate-polyomino check rely on.
      for (final s in allShapes) {
        for (final rotation in s.rotations) {
          expect(shapeKey(rotation), shapeKey(normalise(rotation)));
        }
      }
    });

    test('cycles rotations and wraps', () {
      expect(nextRotation('dot', 0), 0);
      expect(nextRotation('i4', 0), 1);
      expect(nextRotation('i4', 1), 0);
      expect(nextRotation('t4', 3), 0);
    });

    test('rotating an I4 four times returns the original cells', () {
      var r = 0;
      for (var i = 0; i < 4; i++) {
        r = nextRotation('i4', r);
      }
      expect(shapeKey(cellsOf('i4', r)), shapeKey(cellsOf('i4', 0)));
    });

    test('four clockwise rotations return every shape to its start', () {
      for (final s in allShapes) {
        var cells = s.rotations.first;
        for (var i = 0; i < 4; i++) {
          cells = rotateCw(cells);
        }
        expect(shapeKey(cells), shapeKey(s.rotations.first), reason: s.id);
      }
    });

    test('cellsOf wraps out-of-range rotation indices', () {
      expect(shapeKey(cellsOf('i4', 5)), shapeKey(cellsOf('i4', 1)));
      expect(shapeKey(cellsOf('o2', 3)), shapeKey(cellsOf('o2', 0)));
    });
  });

  group('roster', () {
    test('has unique ids', () {
      final ids = allShapes.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('has no duplicate polyominoes across tiers', () {
      // The O-tetromino IS the 2x2 square and the I-tetromino IS the 1x4, so a
      // naive roster double-lists them and the draw bag silently skews small.
      final canonical = allShapes.map((s) {
        final keys = s.rotations.map(shapeKey).toList()..sort();
        return keys.first;
      }).toList();
      expect(canonical.toSet(), hasLength(allShapes.length));
    });

    test('fits every shape inside an 8x8 board', () {
      for (final s in allShapes) {
        for (final rotation in s.rotations) {
          final e = extent(rotation);
          expect(e.w, lessThanOrEqualTo(8));
          expect(e.h, lessThanOrEqualTo(8));
        }
      }
    });

    test('fits every shape inside the 7x7 Tight Reed board', () {
      // The act-3 fault genuinely resizes the board. A motif that cannot fit
      // on 7x7 at any rotation would make that stage unplayable for anyone
      // holding it.
      for (final s in allShapes) {
        final best = s.rotations
            .map(extent)
            .where((e) => e.w <= 7 && e.h <= 7)
            .length;
        expect(best, greaterThan(0), reason: s.id);
      }
    });

    test('tier membership matches the roster table', () {
      // The roster inverted on 2026-11-11: free = the awkward motifs, and
      // tier 4 is the two SMALLEST in the game because finishing a one-cell
      // hole is the most valuable thing a motif can do. A tier is a price
      // band, not a size band (shapes.dart).
      expect(tier1, hasLength(5));
      expect(tier2, hasLength(5));
      expect(tier3, hasLength(11));
      expect(tier4, hasLength(1));
      for (final (i, group) in [tier1, tier2, tier3, tier4].indexed) {
        for (final s in group) {
          expect(s.tier, i + 1, reason: s.id);
        }
      }
    });

    test('spike loadout is tiers 1 and 2 only', () {
      expect(spikeLoadout, hasLength(10));
      expect(spikeLoadout.every((s) => s.tier <= 2), isTrue);
    });

    test('cellCount matches the art', () {
      expect(shape('dot').cellCount, 1);
      expect(shape('o2').cellCount, 4);
      expect(shape('r24').cellCount, 8);
      expect(shape('o3').cellCount, 9);
    });

    test('every motif has a display name that is not its id', () {
      for (final s in allShapes) {
        expect(shapeName(s.id), isNot(s.id), reason: s.id);
      }
    });

    test('shape() rejects an unknown id', () {
      expect(() => shape('nope'), throwsArgumentError);
    });
  });

  group('extent', () {
    test('measures the bounding box', () {
      expect(extent(cellsOf('dot', 0)), (w: 1, h: 1));
      expect(extent(cellsOf('i4', 0)), (w: 4, h: 1));
      expect(extent(cellsOf('i4', 1)), (w: 1, h: 4));
      expect(extent(cellsOf('o3', 0)), (w: 3, h: 3));
    });
  });

  group('art round-trip', () {
    test('parse then render reproduces the source art', () {
      expect(shapeToArt(cellsOf('l3', 0)), ['#.', '##']);
      expect(shapeToArt(cellsOf('t4', 0)), ['###', '.#.']);
      expect(shapeToArt(cellsOf('f5', 0)), ['.##', '##.', '.#.']);
    });

    test('rejects art with no filled cells', () {
      expect(() => parseArt(['..', '..']), throwsArgumentError);
    });
  });
}
