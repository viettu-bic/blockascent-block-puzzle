import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/bag.dart';
import 'package:loomcraft/core/rng.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';

void main() {
  group('Bag', () {
    test('rejects an empty loadout', () {
      expect(() => Bag([], Rng(1)), throwsArgumentError);
    });

    test('serves the whole loadout before repeating anything', () {
      // A shuffled bag rather than independent draws: independent draws
      // produce streaks of the same piece that read as unfair.
      final bag = Bag(spikeLoadout, Rng(42));
      final first = [for (var i = 0; i < 11; i++) bag.draw().id];
      expect(first.toSet(), hasLength(11));
      final second = [for (var i = 0; i < 11; i++) bag.draw().id];
      expect(second.toSet(), hasLength(11));
    });

    test('is deterministic for a seed', () {
      final a = [for (final _ in List.filled(30, 0)) 0];
      final bagA = Bag(spikeLoadout, Rng(7));
      final idsA = [for (var i = 0; i < a.length; i++) bagA.draw().id];
      final bagB = Bag(spikeLoadout, Rng(7));
      final idsB = [for (var i = 0; i < a.length; i++) bagB.draw().id];
      expect(idsA, idsB);
      final bagC = Bag(spikeLoadout, Rng(8));
      expect([for (var i = 0; i < a.length; i++) bagC.draw().id], isNot(idsA));
    });

    test('peek shows the next draws without consuming them', () {
      final bag = Bag(spikeLoadout, Rng(3));
      final ahead = bag.peek(3).map((s) => s.id).toList();
      expect([bag.draw().id, bag.draw().id, bag.draw().id], ahead);
    });

    test('peek can look past the end of the current shuffle', () {
      final bag = Bag(tier1, Rng(3));
      final ahead = bag.peek(7).map((s) => s.id).toList();
      expect(ahead, hasLength(7));
      expect([for (var i = 0; i < 7; i++) bag.draw().id], ahead);
    });

    group('drawWhere', () {
      test('Barré: serves only motifs of 4 cells or more', () {
        final bag = Bag(spikeLoadout, Rng(11));
        for (var i = 0; i < 40; i++) {
          final s = bag.drawWhere((s) => s.cellCount >= 4);
          expect(s, isNotNull);
          expect(s!.cellCount, greaterThanOrEqualTo(4));
        }
      });

      test('returns null rather than emptying a bag that cannot comply', () {
        // A fault that empties the bag would be an instant jam, so the caller
        // has to be able to tell "cannot comply" from "here you are".
        final bag = Bag(tier1, Rng(1));
        expect(bag.drawWhere((s) => s.cellCount >= 9), isNull);
        // The bag is still usable.
        expect(bag.draw(), isA<Shape>());
      });

      test('puts rejects back, so nothing is lost from the shuffle', () {
        final bag = Bag(spikeLoadout, Rng(5));
        final big = bag.drawWhere((s) => s.cellCount >= 4)!;
        final rest = [for (var i = 0; i < 10; i++) bag.draw().id];
        expect({big.id, ...rest}, hasLength(11));
      });
    });

    group('cull and favour', () {
      test('Cull removes a motif from the run for good', () {
        final bag = Bag(spikeLoadout, Rng(2));
        expect(bag.cull('dot'), isTrue);
        bag.resetPending();
        expect(bag.loadout.map((s) => s.id), isNot(contains('dot')));
        for (var i = 0; i < 60; i++) {
          expect(bag.draw().id, isNot('dot'));
        }
      });

      test('Cull refuses to empty the bag', () {
        final bag = Bag([shape('dot')], Rng(1));
        expect(bag.cull('dot'), isFalse);
        expect(bag.loadout, hasLength(1));
      });

      test('Cull ignores a motif that is not in the loadout', () {
        final bag = Bag(tier1, Rng(1));
        expect(bag.cull('o3'), isFalse);
      });

      test('Favour doubles a motif, so it comes up twice per shuffle', () {
        final bag = Bag(tier1, Rng(9));
        bag.favour('dot');
        bag.resetPending();
        final cycle = [for (var i = 0; i < 6; i++) bag.draw().id];
        expect(cycle.where((id) => id == 'dot'), hasLength(2));
      });

      test('Favour rejects a motif that is not in the loadout', () {
        expect(() => Bag(tier1, Rng(1)).favour('o3'), throwsArgumentError);
      });
    });
  });

  group('shouldRefill', () {
    test('refills only when ALL slots are empty', () {
      // THE rule the difficulty rests on (spec §2.1). Refilling one slot at a
      // time leaves the player maximum choice forever.
      expect(shouldRefill([null, null, null]), isTrue);
      expect(shouldRefill([const TrayItem('dot'), null, null]), isFalse);
      expect(shouldRefill([null, const TrayItem('dot'), null]), isFalse);
      expect(shouldRefill([null, null, const TrayItem('dot')]), isFalse);
    });

    test('an empty tray list counts as needing a refill', () {
      expect(shouldRefill([]), isTrue);
    });
  });
}
