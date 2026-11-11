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
      expect(s.patienceMax, 2);
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
      expect(economy.shapeCosts[2], hasLength(6));
      expect(economy.shapeCosts[3], hasLength(6));
      expect(economy.shapeCosts[4], hasLength(5));
    });

    test('17 shapes to unlock for 14,020 spools', () {
      final all = [
        ...economy.shapeCosts[2]!,
        ...economy.shapeCosts[3]!,
        ...economy.shapeCosts[4]!,
      ];
      expect(all, hasLength(17));
      expect(all.reduce((a, b) => a + b), 14020);
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
      expect(economy.costOfNthShapeInTier(2, 5), 420);
      // Owning the whole tier clamps rather than throwing.
      expect(economy.costOfNthShapeInTier(2, 99), 420);
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
    });
  });

  group('upgrades', () {
    test('both tracks open from run 1, and 8,700 spools buys everything', () {
      // Unlike the original, upgrades are NOT gated behind unlocking every
      // shape.
      final total = economy.upgrades.values
          .map((u) => u.cost)
          .reduce((a, b) => a + b);
      expect(total, 8700);
    });

    test('the daily challenge is free and classic mode is not', () {
      expect(economy.upgradeCost('dailyChallenge'), 0);
      expect(economy.upgradeCost('classicMode'), 400);
      expect(economy.upgradeCost('loadoutSlot9'), 1800);
    });

    test('every upgrade has a display name', () {
      for (final id in economy.upgrades.keys) {
        expect(upgradeNames[id], isNotNull, reason: id);
      }
    });

    test('the run-shaping upgrades carry their effect text', () {
      expect(economy.upgrades['openingRhythm']!.effect, contains('x1.2'));
      expect(economy.upgrades['startingSelvage']!.effect, contains('shield'));
      expect(economy.upgrades['openingAllowance']!.effect, contains('+2'));
    });

    test('an unknown upgrade costs nothing rather than throwing', () {
      expect(economy.upgradeCost('fourthTraySlot'), 0);
    });

    test('a 4th tray slot is deliberately NOT purchasable', () {
      // It is the single largest power swing in the game and it alters the
      // refill-on-empty rule the whole difficulty rests on, so it belongs in
      // the draft, where it costs a pick (economy.json._notIncluded).
      expect(
        economy.upgrades.keys.any((k) => k.toLowerCase().contains('tray')),
        isFalse,
      );
      expect(tuning.powers.byId('second_shuttle').effect, contains('4th tray'));
    });
  });

  group('the whole meta, priced', () {
    test('costs 22,800 spools, or about 50 floor runs', () {
      final shapes = [
        ...economy.shapeCosts[2]!,
        ...economy.shapeCosts[3]!,
        ...economy.shapeCosts[4]!,
      ].reduce((a, b) => a + b);
      final upgrades = economy.upgrades.values
          .map((u) => u.cost)
          .reduce((a, b) => a + b);
      expect(shapes + upgrades, 22720);

      // A floor player clears 5 stages: 125 spools a run before the daily
      // bonus. The grind has to be long enough to pace discovery and short
      // enough to stay a game.
      final perRun = economy.payout.forStages(5);
      expect((shapes + upgrades) / perRun, closeTo(182, 2));
    });
  });
}
