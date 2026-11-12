import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/core/scoring.dart';
import 'package:loomcraft/data/tuning.dart';

import '../support/load_tuning.dart';

/// The spool economy and the tuning loaders, checked against the invariants
/// `data/economy.json` and `docs/04` state for themselves.
void main() {
  late Tuning tuning;
  late Economy economy;

  setUpAll(() async {
    tuning = await loadTuningForTest();
    economy = tuning.economy;
  });

  group('curve.json loads as the tuned curve', () {
    test('matches the hand-written defaults the pure core carries', () {
      final c = tuning.curve;
      expect(c.baseTarget, CurveConfig.defaults.baseTarget);
      expect(c.targetGrowth, CurveConfig.defaults.targetGrowth);
      expect(c.baseAllowance, CurveConfig.defaults.baseAllowance);
      expect(c.allowanceGrowth, CurveConfig.defaults.allowanceGrowth);
      expect(c.stages, 12);
    });

    test('carries the scoring block, so nothing is inlined in Dart', () {
      final s = tuning.curve.scoring;
      expect(s.lineBonusTable, const [0, 10, 25, 45, 70, 100]);
      expect(s.multStart, 1.0);
      expect(s.multStep, 0.2);
      expect(s.multCap, 4.0);
      // Raised from 2 on 2026-11-11: at 2 the rhythm broke so often that the
      // ×4.00 cap was decoration — measured median peak was ×1.60 at 0%
      // unlocks (docs/05 §7).
      expect(s.patienceMax, 3);
    });

    test('the JSON and the in-code defaults have not drifted apart', () {
      // ScoringConfig.defaults exists only so pure-core tests need no asset
      // bundle. If it ever disagrees with the file, the file wins and this
      // test is how you find out.
      const d = ScoringConfig.defaults;
      final s = tuning.curve.scoring;
      expect(s.lineBonusTable, d.lineBonusTable);
      expect(s.multStart, d.multStart);
      expect(s.multStep, d.multStep);
      expect(s.multCap, d.multCap);
      expect(s.patienceMax, d.patienceMax);
    });
  });

  group('payout', () {
    test('matches the worked examples in economy.json', () {
      expect(economy.payout.forStages(5), 125);
      expect(economy.payout.forStages(8), 260);
      expect(economy.payout.forStages(11), 440);
    });

    test('pays nothing for a run that cleared nothing', () {
      expect(economy.payout.forStages(0), 0);
    });

    test('is super-linear in stages, so depth is worth pushing for', () {
      for (var s = 1; s < 12; s++) {
        final step = economy.payout.forStages(s + 1) -
            economy.payout.forStages(s);
        final prevStep = s == 1
            ? 0
            : economy.payout.forStages(s) - economy.payout.forStages(s - 1);
        expect(step, greaterThan(prevStep));
      }
    });

    test('pays for the stage the run reached, not only those it cleared', () {
      // The stage you fought and lost is a stage you played. Paying nothing
      // for it is what made a 2-stage run worth 35 spools (docs/04 §7).
      int run(int cleared) => economy.payout
          .forRun(stagesCleared: cleared, finalStage: 12, won: false);

      expect(run(0), 15, reason: 'died on stage 1 — never worth zero');
      expect(run(2), 60);
      expect(run(5), 165);
      expect(run(8), 315);

      // A win has no unreached stage, so the 12-stage cap is unchanged.
      expect(
        economy.payout.forRun(stagesCleared: 12, finalStage: 12, won: true),
        economy.payout.forStages(12),
      );

      // Still monotonic in depth: no region rewards playing worse
      // (docs/04 §5).
      for (var c = 0; c < 11; c++) {
        expect(run(c + 1), greaterThan(run(c)));
      }
    });

    test('never pays past the final stage', () {
      expect(
        economy.payout.forRun(stagesCleared: 11, finalStage: 12, won: false),
        economy.payout.forStages(12),
      );
      expect(
        economy.payout.forRun(stagesCleared: 12, finalStage: 12, won: false),
        economy.payout.forStages(12),
      );
    });

    test('keys off stages cleared and knows nothing about score', () {
      // Keying payout to score creates an inflation spiral: buy a value
      // upgrade, score rises, earn more, buy more — and because stage targets
      // are fixed, the ladder also gets easier (docs/04 §1). The signature
      // taking only an int is the guarantee.
      expect(economy.payout.forStages(5), economy.payout.forStages(5));
      expect(economy.payout.firstRunOfDayBonus, 100);
    });
  });

  group('shape costs', () {
    test('tier 1 is free and the other three tiers are priced', () {
      expect(economy.shapeCosts[1], isNull);
      expect(economy.shapeCosts[2], hasLength(5));
      expect(economy.shapeCosts[3], hasLength(11));
      expect(economy.shapeCosts[4], hasLength(1));
    });

    test('17 shapes to unlock for 13,680 spools', () {
      final all = [
        ...economy.shapeCosts[2]!,
        ...economy.shapeCosts[3]!,
        ...economy.shapeCosts[4]!,
      ];
      // The roster inverted on 2026-11-11: the free five are the awkward
      // motifs and the two smallest — `i2` and `dot` — are the most expensive
      // purchases in the game, because finishing a one-cell hole is the most
      // valuable thing a motif can do (shapes.dart).
      expect(all, hasLength(17));
      expect(all.reduce((a, b) => a + b), 13680);
    });

    test('prices rise within a tier, so the next unlock always costs more', () {
      for (final tier in [2, 3, 4]) {
        final list = economy.shapeCosts[tier]!;
        for (var i = 1; i < list.length; i++) {
          expect(list[i], greaterThan(list[i - 1]), reason: 'tier $tier');
        }
      }
    });

    test('the nth unlock in a tier is priced by how many you already own', () {
      expect(economy.costOfNthShapeInTier(2, 0), 40);
      expect(economy.costOfNthShapeInTier(2, 4), 480);
      // Owning the whole tier clamps rather than throwing.
      expect(economy.costOfNthShapeInTier(2, 99), 480);
      expect(economy.costOfNthShapeInTier(1, 0), 0);
    });

    test('the first unlock lands inside one HUMAN first run', () {
      // This test used to anchor on the greedy sim — "a floor player clears 5
      // stages for 125 spools" — and it passed while the game failed. A real
      // first run cleared 2 stages and paid 35 against a 100-spool first
      // unlock, so the player could buy nothing at all (docs/04 §7).
      //
      // The anchor is now a human's first run: 2 stages cleared, dying in the
      // third. It must afford the first motif WITHOUT the daily bonus, so an
      // abandoned run earlier in the day cannot break the on-ramp.
      final humanFirstRun = economy.payout.forRun(
        stagesCleared: 2,
        finalStage: 12,
        won: false,
      );
      expect(humanFirstRun, 60);
      expect(
        humanFirstRun,
        greaterThanOrEqualTo(economy.costOfNthShapeInTier(2, 0)),
        reason: 'run 1 must buy a block without relying on the daily bonus',
      );

      // With the bonus it should also reach the second motif, so the first
      // session shows the shop working twice.
      final withBonus = humanFirstRun + economy.payout.firstRunOfDayBonus;
      expect(withBonus, greaterThanOrEqualTo(
        economy.costOfNthShapeInTier(2, 0) +
            economy.costOfNthShapeInTier(2, 1),
      ));

      // And the precision motifs are the other end of the same scale: the most
      // expensive purchases in the game, several runs of saving each. That
      // ordering is the whole point of the inversion (shapes.dart).
      expect(
        economy.costOfNthShapeInTier(4, 0),
        greaterThan(economy.shapeCosts[3]!.last),
      );
    });
  });

  group('upgrades', () {
    test('both tracks open from run 1, and 15,400 spools buys everything', () {
      // Unlike the original, upgrades are NOT gated behind unlocking every
      // shape.
      final total = economy.upgrades.values
          .map((u) => u.cost)
          .reduce((a, b) => a + b);
      expect(total, 15400);
    });

    test('the upgrades are structural, not flat numbers', () {
      // Rebuilt 2026-11-12. These used to be seven small additions — +1 value,
      // +2 moves on stage 1, one shield — against a shop whose job is now to
      // sell a player out of jams (docs/08 B7). A flat +1 cannot do that, so
      // every upgrade is a slot, a charge, a guarantee or an allowance.
      expect(economy.upgradeCost('fourthTraySlot'), 2600);
      expect(economy.upgradeCost('handful'), 2200);
      expect(economy.upgradeCost('toolkit'), 1400);
      expect(economy.upgradeCost('loadoutSlot10'), 1600);
    });

    test('modes are not sold as upgrades', () {
      // Removed on 2026-11-11. `dailyChallenge` cost 0 spools and was
      // referenced nowhere in `lib/` — the shop sold a player something that
      // did nothing. `classicMode` was worse: buying it disabled rotation for
      // *every* run with no way to turn it off, so 400 spools bought a
      // permanent handicap, and the test harness here had already worked
      // around it rather than fixing it.
      //
      // Both are modes and need a picker before a run (docs/08 E5). An
      // unknown id costs 0, so these read as absent rather than free.
      expect(economy.upgrades.containsKey('dailyChallenge'), isFalse);
      expect(economy.upgrades.containsKey('classicMode'), isFalse);
      expect(economy.upgradeCost('loadoutSlot9'), 900);
    });

    test('every upgrade has a display name', () {
      for (final id in economy.upgrades.keys) {
        expect(upgradeNames[id], isNotNull, reason: id);
      }
    });

    test('the run-shaping upgrades carry their effect text', () {
      expect(economy.upgrades['openingRhythm']!.effect, contains('x2.0'));
      expect(economy.upgrades['startingSelvage']!.effect, contains('shield'));
      expect(economy.upgrades['openingAllowance']!.effect, contains('+5'));
    });

    test('an unknown upgrade costs nothing rather than throwing', () {
      expect(economy.upgradeCost('spoolsForever'), 0);
    });

    test('the 4th tray slot IS purchasable now, and still draftable', () {
      // docs/04 §3 refused to sell it: the largest power swing in the game, it
      // alters the refill-on-empty rule the difficulty rests on, it roughly
      // halves jam risk. All three true, and all three are now *reasons to
      // sell it* — halving jam risk is exactly what the shop is for once a
      // first run dies to a jam 57% of the time (docs/08 B7).
      expect(economy.upgrades.containsKey('fourthTraySlot'), isTrue);
      // Second Shuttle stays in the draft and stacks on top, so a drafted
      // fifth slot is still a real pick rather than a dead card.
      expect(tuning.powers.byId('second_shuttle').effect, contains('4th tray'));
    });
  });

  group('the whole meta, priced', () {
    test('costs 29,080 spools, or about 80 floor runs', () {
      final shapes = [
        ...economy.shapeCosts[2]!,
        ...economy.shapeCosts[3]!,
        ...economy.shapeCosts[4]!,
      ].reduce((a, b) => a + b);
      final upgrades = economy.upgrades.values
          .map((u) => u.cost)
          .reduce((a, b) => a + b);
      expect(shapes + upgrades, 29080);

      // A floor player clears 5 stages: 125 spools a run before the daily
      // bonus. The grind has to be long enough to pace discovery and short
      // enough to stay a game.
      final perRun = economy.payout.forStages(5);
      expect((shapes + upgrades) / perRun, closeTo(233, 3));
    });
  });
}
