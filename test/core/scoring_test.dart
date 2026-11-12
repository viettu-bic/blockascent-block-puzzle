import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/scoring.dart';

/// Ported from `reference/ts-tests/scoring.test.ts`.
void main() {
  const cfg = ScoringConfig.defaults;

  group('lineBonus', () {
    test('is super-linear, so multi-line setups pay', () {
      expect(cfg.lineBonus(0), 0);
      expect(cfg.lineBonus(1), 10);
      expect(cfg.lineBonus(2), 25);
      expect(cfg.lineBonus(3), 45);
      expect(cfg.lineBonus(2), greaterThan(cfg.lineBonus(1) * 2));
      expect(cfg.lineBonus(3), greaterThan(cfg.lineBonus(1) * 3));
    });

    test('clamps beyond the table', () {
      expect(cfg.lineBonus(9), cfg.lineBonus(5));
      expect(cfg.lineBonus(-1), 0);
    });
  });

  group('scoreTurn', () {
    test('applies the CURRENT multiplier, then raises it', () {
      // The reward for a combo lands on the NEXT turn, which is what makes
      // protecting the multiplier feel like an investment.
      final out = scoreTurn(initialScore(), 4, 1);
      expect(out.gained, 14); // (4 cells + 10 bonus) * 1.0
      expect(out.next.multiplier, closeTo(1.2, 1e-9));
      expect(out.next.total, 14);
    });

    test('the spec §9 step-4 exit case: 1 cell + a two-line bonus at x1', () {
      expect(scoreTurn(initialScore(), 1, 2).gained, 26);
    });

    test('compounds across consecutive clears', () {
      var s = initialScore();
      s = scoreTurn(s, 4, 1).next; // -> 1.2
      final second = scoreTurn(s, 4, 1);
      expect(second.gained, (14 * 1.2).round());
      expect(second.next.multiplier, closeTo(1.4, 1e-9));
    });

    test('keeps the multiplier on a 4-decimal grid', () {
      // Repeated 0.2 additions drift into 1.4000000000000001 without the
      // quantisation the oracle does with toFixed(4) — and then an equality
      // check in the UI or a replay silently fails.
      var s = initialScore();
      for (var i = 0; i < 10; i++) {
        s = scoreTurn(s, 1, 1).next;
      }
      expect(s.multiplier, 3.0);
    });

    test('spends patience on a dry placement but keeps the multiplier', () {
      // Starts at FULL patience, so what is measured is "spends one" rather
      // than "happens to have two left". Base patience is 3 since 2026-11-11.
      const s = ScoreState(
        total: 0,
        multiplier: 2,
        patience: 3,
        shields: 0,
      );
      final out = scoreTurn(s, 3, 0);
      expect(out.gained, 6); // 3 cells * 2.0, no bonus
      expect(out.next.multiplier, 2);
      expect(out.next.patience, cfg.patienceMax - 1);
      expect(out.broke, isFalse);
    });

    test('breaks the multiplier once patience runs out', () {
      var s = const ScoreState(
        total: 0,
        multiplier: 2.6,
        patience: 2,
        shields: 0,
      );
      s = scoreTurn(s, 1, 0).next;
      final out = scoreTurn(s, 1, 0);
      expect(out.broke, isTrue);
      expect(out.next.multiplier, cfg.multStart);
      expect(out.next.patience, cfg.patienceMax);
    });

    test('a shield absorbs the break instead of resetting', () {
      var s = const ScoreState(
        total: 0,
        multiplier: 3,
        patience: 2,
        shields: 1,
      );
      s = scoreTurn(s, 1, 0).next;
      final out = scoreTurn(s, 1, 0);
      expect(out.shielded, isTrue);
      expect(out.broke, isFalse);
      expect(out.next.multiplier, 3);
      expect(out.next.shields, 0);
      expect(out.next.patience, cfg.patienceMax);
    });

    test('a clear refills patience', () {
      var s = initialScore();
      s = scoreTurn(s, 1, 0).next;
      expect(s.patience, cfg.patienceMax - 1);
      s = scoreTurn(s, 1, 1).next;
      expect(s.patience, cfg.patienceMax);
    });

    test('never exceeds the cap', () {
      var s = initialScore();
      for (var i = 0; i < 100; i++) {
        s = scoreTurn(s, 1, 1).next;
      }
      expect(s.multiplier, cfg.multCap);
    });

    test('cellValue scales placement points but not the line bonus', () {
      // Yarn cards raise cellValue; the line bonus is deliberately untouched,
      // which is why ~56% of a floor player's score is immune to them.
      expect(scoreTurn(initialScore(), 4, 1, cellValue: 3).gained, 4 * 3 + 10);
    });
  });

  group('power modifiers', () {
    test('Temple: the free dry placement spends no patience', () {
      final out = scoreTurn(
        initialScore(),
        2,
        0,
        mods: const TurnModifiers(freeDryPlacement: true),
      );
      expect(out.next.patience, cfg.patienceMax);
      expect(out.gained, 2);
    });

    test('Weftwise and Warpwise add rhythm per row / column cleared', () {
      final out = scoreTurn(
        initialScore(),
        1,
        2,
        mods: const TurnModifiers(
          extraMultOnRow: 0.2,
          extraMultOnCol: 0.2,
          rows: 1,
          cols: 1,
        ),
      );
      // 0.2 base step + 0.2 row + 0.2 col
      expect(out.next.multiplier, closeTo(1.6, 1e-9));
    });

    test('Double Pick doubles rhythm gain on a 2+ line clear only', () {
      const mods = TurnModifiers(doubleMultOnMultiLine: true);
      expect(
        scoreTurn(initialScore(), 1, 1, mods: mods).next.multiplier,
        closeTo(1.2, 1e-9),
      );
      expect(
        scoreTurn(initialScore(), 1, 2, mods: mods).next.multiplier,
        closeTo(1.4, 1e-9),
      );
    });

    test('Floating Selvage drops rhythm to 2.0 on a break, not 1.0', () {
      var s = const ScoreState(
        total: 0,
        multiplier: 3.4,
        patience: 2,
        shields: 0,
      );
      const mods = TurnModifiers(breakFloor: 2.0);
      s = scoreTurn(s, 1, 0, mods: mods).next;
      final out = scoreTurn(s, 1, 0, mods: mods);
      expect(out.broke, isTrue);
      expect(out.next.multiplier, 2.0);
    });

    test('Treadle Rhythm keeps rhythm off the floor entirely', () {
      var s = const ScoreState(
        total: 0,
        multiplier: 2.0,
        patience: 2,
        shields: 0,
      );
      const mods = TurnModifiers(multFloor: 1.5);
      s = scoreTurn(s, 1, 0, mods: mods).next;
      expect(scoreTurn(s, 1, 0, mods: mods).next.multiplier, 1.5);
    });

    test('Mending restores a spent shield on a 3+ line clear', () {
      final out = scoreTurn(
        const ScoreState(total: 0, multiplier: 1, patience: 2, shields: 0),
        1,
        3,
        mods: const TurnModifiers(restoreShieldOnBigClear: true),
      );
      expect(out.next.shields, 1);
    });

    test('Doubleweave adds its flat bonus before the multiplier', () {
      final out = scoreTurn(
        const ScoreState(total: 0, multiplier: 2, patience: 2, shields: 0),
        1,
        0,
        mods: const TurnModifiers(flatBonus: 3),
      );
      expect(out.gained, (1 + 3) * 2);
    });

    test('Steady Beat raises the cap without changing anything else', () {
      const raised = ScoringConfig(multCap: 5.0);
      var s = initialScore(cfg: raised);
      for (var i = 0; i < 100; i++) {
        s = scoreTurn(s, 1, 1, cfg: raised).next;
      }
      expect(s.multiplier, 5.0);
    });

    test('Mispick: patience 1 means every dry placement breaks', () {
      const hard = ScoringConfig(patienceMax: 1);
      final s = initialScore(cfg: hard, multiplier: 2.0);
      final out = scoreTurn(s, 1, 0, cfg: hard);
      expect(out.broke, isTrue);
      expect(out.next.multiplier, 1.0);
    });
  });
}
