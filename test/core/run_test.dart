import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/core/scoring.dart';

/// Ported from `reference/ts-tests/run.test.ts`, plus the 12-stage win
/// condition from `docs/06`.
void main() {
  const cfg = CurveConfig.defaults;
  const scoring = ScoringConfig.defaults;

  /// Place repeatedly without clearing — the cheapest way to burn allowance.
  LadderState burn(LadderState s, int times) {
    var out = s;
    for (var i = 0; i < times && out.phase == RunPhase.placing; i++) {
      out = applyPlacement(out, 1, 0, cfg: cfg).next;
    }
    return out;
  }

  group('curve', () {
    test('grows the target faster than the allowance', () {
      // The player must not be able to grind up the ladder: more placements
      // per stage has to be outpaced by the score demanded.
      for (var stage = 1; stage <= 8; stage++) {
        final perPlacement = targetFor(cfg, stage) / allowanceFor(cfg, stage);
        final nextPerPlacement =
            targetFor(cfg, stage + 1) / allowanceFor(cfg, stage + 1);
        expect(nextPerPlacement, greaterThan(perPlacement));
      }
    });

    // Pinned to data/curve.json. If you retune, update these deliberately —
    // the point is that a tuning change is never silent.
    test('matches the tuned ladder', () {
      expect(targetFor(cfg, 1), 100);
      expect(targetFor(cfg, 2), 125);
      expect(targetFor(cfg, 3), 156);
      expect(allowanceFor(cfg, 1), 20);
      expect(allowanceFor(cfg, 3), 24);
    });

    test('matches the docs/06 table at every act boundary', () {
      expect(targetFor(cfg, 4), 195);
      expect(allowanceFor(cfg, 4), 26);
      expect(targetFor(cfg, 8), 477);
      expect(allowanceFor(cfg, 8), 34);
      expect(targetFor(cfg, 12), 1164);
      expect(allowanceFor(cfg, 12), 42);
    });

    test('opens with a target a floor player clears comfortably', () {
      // The simulation puts an unassisted player at ~158 per stage. Stage 1 is
      // the tutorial stage: nobody should lose there.
      expect(targetFor(cfg, 1), lessThan(130));
    });

    test('is twelve stages, in three acts of four, faults at 4/8/12', () {
      expect(cfg.stages, 12);
      expect(actOf(1), 1);
      expect(actOf(4), 1);
      expect(actOf(5), 2);
      expect(actOf(8), 2);
      expect(actOf(9), 3);
      expect(actOf(12), 3);
      expect([for (var s = 1; s <= 12; s++) if (isFaultStage(s)) s], [4, 8, 12]);
    });
  });

  group('ladder modifiers', () {
    test('Overtime adds placements; Gilt Thread takes them away', () {
      expect(
        allowanceFor(cfg, 1, mods: const LadderModifiers(allowanceBonus: 3)),
        23,
      );
      expect(
        allowanceFor(cfg, 1, mods: const LadderModifiers(allowanceBonus: -2)),
        18,
      );
    });

    test('Short Bolt cuts remaining targets by 20%', () {
      // Scaled before rounding, so there is exactly one rounding step and
      // 0.8 x 0.8 is not 0.64 plus two accumulated half-cents.
      expect(
        targetFor(cfg, 8, mods: const LadderModifiers(targetScale: 0.8)),
        381,
      );
      expect(targetFor(cfg, 8), 477);
    });

    test('Tight Budget scales both allowance and target', () {
      const thin = LadderModifiers(allowanceScale: 0.7, targetScale: 0.75);
      expect(allowanceFor(cfg, 4, mods: thin), (26 * 0.7).round());
      expect(targetFor(cfg, 4, mods: thin), (195 * 0.75).round());
    });

    test('never produces a zero allowance or a zero target', () {
      const brutal = LadderModifiers(allowanceScale: 0.0, targetScale: 0.0);
      expect(allowanceFor(cfg, 1, mods: brutal), 1);
      expect(targetFor(cfg, 1, mods: brutal), 1);
    });
  });

  group('startRun', () {
    test('opens on stage 1 with a full allowance', () {
      final s = startRun(cfg);
      expect(s.stage, 1);
      expect(s.target, targetFor(cfg, 1));
      expect(s.stageScore, 0);
      expect(s.placementsLeft, allowanceFor(cfg, 1));
      expect(s.phase, RunPhase.placing);
      expect(s.lossReason, isNull);
      expect(s.score.multiplier, scoring.multStart);
    });

    test('honours the meta upgrades that change the opening', () {
      // Starting Combo (x1.2) and Starting Shield are bought
      // with spools, not drafted — see data/economy.json.
      final s = startRun(cfg, shields: 1, multiplier: 1.2);
      expect(s.score.shields, 1);
      expect(s.score.multiplier, 1.2);
    });
  });

  group('applyPlacement', () {
    test('accumulates stage score and spends allowance', () {
      final out = applyPlacement(startRun(cfg), 4, 1, cfg: cfg);
      expect(out.gained, 14);
      expect(out.next.stageScore, 14);
      expect(out.next.score.total, 14);
      expect(out.next.placementsLeft, allowanceFor(cfg, 1) - 1);
      expect(out.next.phase, RunPhase.placing);
    });

    test('clears the stage the moment the target is reached', () {
      final s = startRun(cfg).copyWith(stageScore: targetFor(cfg, 1) - 5);
      final out = applyPlacement(s, 4, 1, cfg: cfg);
      expect(out.stageCleared, isTrue);
      expect(out.failed, isFalse);
      expect(out.next.phase, RunPhase.stageClear);
      // Unspent placements are forfeited, not banked.
      expect(out.next.placementsLeft, greaterThan(0));
    });

    test('loses the run when the allowance runs out short of target', () {
      final s = burn(startRun(cfg), allowanceFor(cfg, 1) - 1);
      expect(s.phase, RunPhase.placing);
      expect(s.placementsLeft, 1);

      final out = applyPlacement(s, 1, 0, cfg: cfg);
      expect(out.failed, isTrue);
      expect(out.next.phase, RunPhase.lost);
      expect(out.next.lossReason, LossReason.target);
      expect(out.next.placementsLeft, 0);
    });

    test(
      'checks the target BEFORE the allowance, so the last placement can '
      'save the run',
      () {
        final s = startRun(cfg).copyWith(
          stageScore: targetFor(cfg, 1) - 14,
          placementsLeft: 1,
        );
        final out = applyPlacement(s, 4, 1, cfg: cfg);
        expect(out.stageCleared, isTrue);
        expect(out.failed, isFalse);
        expect(out.next.phase, RunPhase.stageClear);
      },
    );

    test('refuses to place once the run is not in play', () {
      final lost = jam(startRun(cfg));
      expect(() => applyPlacement(lost, 1, 0, cfg: cfg), throwsStateError);
    });
  });

  group('the win condition', () {
    test('clearing stage 12 wins the run rather than offering a draft', () {
      final s = LadderState(
        stage: 12,
        target: targetFor(cfg, 12),
        stageScore: targetFor(cfg, 12) - 1,
        placementsLeft: 5,
        score: initialScore(),
        phase: RunPhase.placing,
        lossReason: null,
      );
      final out = applyPlacement(s, 4, 1, cfg: cfg);
      expect(out.won, isTrue);
      expect(out.stageCleared, isTrue);
      expect(out.next.phase, RunPhase.won);
      expect(out.next.isOver, isTrue);
      expect(() => nextStage(out.next, cfg), throwsStateError);
    });

    test('clearing stage 11 does not win', () {
      final s = LadderState(
        stage: 11,
        target: 10,
        stageScore: 9,
        placementsLeft: 5,
        score: initialScore(),
        phase: RunPhase.placing,
        lossReason: null,
      );
      final out = applyPlacement(s, 4, 1, cfg: cfg);
      expect(out.won, isFalse);
      expect(out.next.phase, RunPhase.stageClear);
      expect(nextStage(out.next, cfg).stage, 12);
    });
  });

  group('nextStage', () {
    test('raises the target, refreshes the allowance and resets stage score', () {
      final cleared = applyPlacement(
        startRun(cfg).copyWith(stageScore: targetFor(cfg, 1) - 1),
        4,
        1,
        cfg: cfg,
      ).next;
      final s2 = nextStage(cleared, cfg);
      expect(s2.stage, 2);
      expect(s2.target, targetFor(cfg, 2));
      expect(s2.placementsLeft, allowanceFor(cfg, 2));
      expect(s2.stageScore, 0);
      expect(s2.phase, RunPhase.placing);
    });

    test('carries the multiplier across the boundary', () {
      // Finishing a stage hot should pay off, not be confiscated.
      var s = startRun(cfg);
      s = applyPlacement(s, 4, 1, cfg: cfg).next; // multiplier -> 1.2
      s = s.copyWith(stageScore: targetFor(cfg, 1) - 1);
      s = applyPlacement(s, 4, 1, cfg: cfg).next; // stageClear, multiplier 1.4
      expect(s.score.multiplier, closeTo(1.4, 1e-9));

      final s2 = nextStage(s, cfg);
      expect(s2.score.multiplier, closeTo(1.4, 1e-9));
      expect(s2.score.total, s.score.total);
      expect(s2.score.patience, scoring.patienceMax);
    });

    test('refills shields when a power says to', () {
      // Selvage: "gain 1 shield, refilled at each stage start".
      var s = startRun(cfg, shields: 1);
      s = applyPlacement(
        s.copyWith(stageScore: targetFor(cfg, 1) - 1),
        4,
        1,
        cfg: cfg,
      ).next;
      final spent = s.copyWith(score: s.score.copyWith(shields: 0));
      expect(nextStage(spent, cfg, shields: 1).score.shields, 1);
    });

    test('refuses to advance from a stage that was not cleared', () {
      expect(() => nextStage(startRun(cfg), cfg), throwsStateError);
    });
  });

  group('jam', () {
    test('is terminal and distinguishable from falling short', () {
      final s = jam(startRun(cfg));
      expect(s.phase, RunPhase.lost);
      expect(s.lossReason, LossReason.jam);
      expect(s.isOver, isTrue);
    });
  });

  group('stageProgress', () {
    test('reports 0..1 and clamps at the target', () {
      final s = startRun(cfg);
      expect(stageProgress(s), 0);
      expect(
        stageProgress(s.copyWith(stageScore: s.target ~/ 2)),
        closeTo(0.5, 0.01),
      );
      expect(stageProgress(s.copyWith(stageScore: 9999)), 1);
    });
  });
}
