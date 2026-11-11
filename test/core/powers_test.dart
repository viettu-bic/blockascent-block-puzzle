import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/rng.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/core/scoring.dart';
import 'package:loomcraft/core/shapes.dart';

import '../support/load_tuning.dart';

void main() {
  late PowerPool pool;

  setUpAll(() async {
    pool = (await loadTuningForTest()).powers;
  });

  PowerSet taken(List<String> ids, {String? motif}) =>
      PowerSet([for (final id in ids) PickedPower(id, motifId: motif)]);

  group('the pool as authored', () {
    test('is 33 cards, 12 of them available from install', () {
      expect(pool.defs, hasLength(33));
      expect(pool.defs.where((d) => d.isInitial), hasLength(12));
    });

    test('the initial twelve are the docs/05 §3 list', () {
      expect(
        pool.defs.where((d) => d.isInitial).map((d) => d.id).toSet(),
        {
          'fine_yarn',
          'standard_yarn',
          'slub_yarn',
          'quick_shuttle',
          'weftwise',
          'selvage',
          'temple',
          'unpick',
          'rethread',
          'cull',
          'favour',
          'overtime',
        },
      );
    });

    test('a new player meets every family within the initial twelve', () {
      final families = pool.defs
          .where((d) => d.isInitial)
          .map((d) => d.family)
          .toSet();
      expect(families, pool.defs.map((d) => d.family).toSet());
    });

    test('every card has a display name and a non-zero stack count', () {
      for (final d in pool.defs) {
        expect(powerName(d.id), isNot(d.id), reason: d.id);
        expect(d.stacks, greaterThan(0), reason: d.id);
      }
    });

    test('ids are unique', () {
      final ids = pool.defs.map((d) => d.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('rarity gain bands match the docs/05 §2 calibration', () {
      // Commons 8-15%, uncommons 15-25%, rares 25-35%, as built averaging
      // 10.9 / 15.8 / 25.5. Gambles are excluded: Bulk Order's gain is
      // negative by design because it trades depth for currency.
      double meanOf(Rarity r) {
        final xs = pool.defs
            .where((d) => d.rarity == r && !d.gamble)
            .map((d) => d.gain)
            .toList();
        return xs.reduce((a, b) => a + b) / xs.length;
      }

      expect(meanOf(Rarity.common), closeTo(10.9, 0.5));
      expect(meanOf(Rarity.uncommon), closeTo(15.8, 0.5));
      expect(meanOf(Rarity.rare), closeTo(25.5, 0.5));

      // The relationship that makes the rarity tiers mean anything: a first
      // pass had rares at 17.6%, statistically indistinguishable from
      // uncommons, which would have made the whole tier decorative.
      expect(meanOf(Rarity.rare), greaterThan(meanOf(Rarity.uncommon) + 5));
      expect(meanOf(Rarity.uncommon), greaterThan(meanOf(Rarity.common)));
    });

    test('the average pick is worth less than the 25% target growth', () {
      // THE number everything hangs on (docs/05 §1). If the average pick ever
      // exceeds +25%, the ladder becomes infinite and runs never end.
      final gains = pool.defs.where((d) => !d.gamble).map((d) => d.gain);
      final mean = gains.reduce((a, b) => a + b) / gains.length;
      expect(mean, lessThan(25));
      expect(mean, inInclusiveRange(15, 21), reason: 'docs/05 §1 aims at 18-20');
    });

    test('no single card exceeds the rare ceiling', () {
      for (final d in pool.defs) {
        expect(d.gain, lessThanOrEqualTo(35), reason: d.id);
      }
    });
  });

  group('cellValueFor', () {
    test('is 1 with no cards and no upgrades', () {
      expect(PowerSet.empty.cellValueFor(4, 'o2'), 1);
    });

    test('Small Block Bonus is +2 a stack, 1- and 2-block pieces only', () {
      final s = taken(['fine_yarn', 'fine_yarn']);
      expect(s.cellValueFor(1, 'dot'), 5);
      expect(s.cellValueFor(2, 'i2'), 5);
      expect(s.cellValueFor(3, 'i3'), 1);
    });

    test('Standard Yarn is +1 per stack to 3- and 4-cell motifs', () {
      final s = taken(['standard_yarn', 'standard_yarn', 'standard_yarn']);
      expect(s.cellValueFor(3, 'i3'), 4);
      expect(s.cellValueFor(4, 'o2'), 4);
      expect(s.cellValueFor(5, 'i5'), 1);
      expect(s.cellValueFor(2, 'i2'), 1);
    });

    test('Heavy Yarn is +1 per stack to 5-cell and larger motifs', () {
      final s = taken(['heavy_yarn']);
      expect(s.cellValueFor(5, 'i5'), 2);
      expect(s.cellValueFor(9, 'o3'), 2);
      expect(s.cellValueFor(4, 'o2'), 1);
    });

    test('Gilt Thread is +2 to every motif, at the cost of placements', () {
      final s = taken(['gilt_thread']);
      expect(s.cellValueFor(1, 'dot'), 3);
      expect(s.cellValueFor(9, 'o3'), 3);
      expect(s.ladderModifiers.allowanceBonus, -2);
    });

    test('Slub Yarn is +3 to the chosen motif only', () {
      final s = PowerSet([const PickedPower('slub_yarn', motifId: 'l3')]);
      expect(s.cellValueFor(3, 'l3'), 4);
      expect(s.cellValueFor(3, 'i3'), 1);
    });

    test('Slub Yarn stacks onto different motifs independently', () {
      final s = PowerSet([
        const PickedPower('slub_yarn', motifId: 'l3'),
        const PickedPower('slub_yarn', motifId: 'l3'),
        const PickedPower('slub_yarn', motifId: 'i3'),
      ]);
      expect(s.cellValueFor(3, 'l3'), 7);
      expect(s.cellValueFor(3, 'i3'), 4);
    });

    test('the bought yarn upgrades add +1 on top of the drafted cards', () {
      final s = taken(['fine_yarn']).withYarn(
        const YarnUpgrades(fineYarn: true, standardYarn: true, heavyYarn: true),
      );
      expect(s.cellValueFor(1, 'dot'), 1 + 2 + 1);
      expect(s.cellValueFor(3, 'i3'), 2);
      expect(s.cellValueFor(6, 'r23'), 2);
    });
  });

  group('scoring and ladder modifiers', () {
    test('Quick Shuttle raises the rhythm step by 0.05 a stack', () {
      final cfg = taken(['quick_shuttle']).applyTo(ScoringConfig.defaults);
      expect(cfg.multStep, closeTo(0.25, 1e-9));
      expect(
        taken(['quick_shuttle', 'quick_shuttle', 'quick_shuttle'])
            .applyTo(ScoringConfig.defaults)
            .multStep,
        closeTo(0.35, 1e-9),
      );
    });

    test('Steady Beat raises the cap and Patience the patience', () {
      final cfg = taken([
        'steady_beat',
        'patience',
      ]).applyTo(ScoringConfig.defaults);
      expect(cfg.multCap, 5.0);
      expect(cfg.patienceMax, 3);
    });

    test('Overtime adds 3 placements a stack', () {
      expect(taken(['overtime', 'overtime']).ladderModifiers.allowanceBonus, 6);
    });

    test('Short Bolt and Bulk Order compose multiplicatively', () {
      expect(
        taken(['short_bolt']).ladderModifiers.targetScale,
        closeTo(0.8, 1e-9),
      );
      expect(
        taken(['short_bolt', 'bulk_order']).ladderModifiers.targetScale,
        closeTo(0.92, 1e-9),
      );
      expect(taken(['bulk_order']).spoolMultiplier, 1.6);
    });

    test('Piecework pays per stage cleared without touching power', () {
      final s = taken(['piecework', 'piecework']);
      expect(s.spoolsPerStageBonus, 50);
      expect(s.ladderModifiers.allowanceBonus, 0);
      expect(pool.byId('piecework').gain, 0);
    });

    test('turn modifiers wire each rhythm card to the right axis', () {
      final s = taken(['weftwise', 'warpwise', 'double_pick']);
      final mods = s.turnModifiers(rows: 1, cols: 2);
      expect(mods.extraMultOnRow, closeTo(0.2, 1e-9));
      expect(mods.extraMultOnCol, closeTo(0.2, 1e-9));
      expect(mods.doubleMultOnMultiLine, isTrue);
      expect(mods.rows, 1);
      expect(mods.cols, 2);
    });

    test('Doubleweave only pays when the motif touches an edge', () {
      final s = taken(['doubleweave']);
      expect(s.turnModifiers(touchesEdge: true).flatBonus, 3);
      expect(s.turnModifiers(touchesEdge: false).flatBonus, 0);
    });

    test('Temple grants its grace only while it is unspent', () {
      final s = taken(['temple']);
      expect(s.turnModifiers(freeDryPlacement: true).freeDryPlacement, isTrue);
      expect(s.turnModifiers(freeDryPlacement: false).freeDryPlacement, isFalse);
      // And not at all without the card.
      expect(
        PowerSet.empty.turnModifiers(freeDryPlacement: true).freeDryPlacement,
        isFalse,
      );
    });

    test('tool charges refresh per stage, Batten per run', () {
      final s = taken(['unpick', 'unpick', 'rethread', 'shears', 'batten']);
      expect(s.chargesPerStage('unpick'), 4);
      expect(s.chargesPerStage('rethread'), 2);
      expect(s.chargesPerStage('shears'), 1);
      expect(s.chargesPerStage('resley'), 0);
      expect(s.battenChargesPerRun, 1);
    });

    test('Second Shuttle is the only source of a 4th tray slot', () {
      expect(PowerSet.empty.extraTraySlots, 0);
      expect(taken(['second_shuttle']).extraTraySlots, 1);
      expect(pool.byId('second_shuttle').rarity, Rarity.rare);
    });

    test('a whole build composes without any card cancelling another', () {
      final s = taken([
        'standard_yarn',
        'quick_shuttle',
        'weftwise',
        'selvage',
        'overtime',
        'treadle_rhythm',
      ]);
      final cfg = s.applyTo(ScoringConfig.defaults);
      final out = scoreTurn(
        initialScore(shields: s.shieldsPerStage, cfg: cfg),
        4,
        1,
        cellValue: s.cellValueFor(4, 'o2'),
        cfg: cfg,
        mods: s.turnModifiers(rows: 1),
      );
      expect(out.gained, 4 * 2 + 10);
      expect(out.next.multiplier, closeTo(1.45, 1e-9));
      expect(out.next.shields, 1);
    });
  });

  group('stacking rules', () {
    test('a card already owned is only re-offered if it stacks', () {
      final temple = pool.byId('temple'); // stacks: 1
      expect(PowerSet.empty.canTake(temple), isTrue);
      expect(taken(['temple']).canTake(temple), isFalse);

      final fine = pool.byId('fine_yarn'); // stacks: 3
      expect(taken(['fine_yarn', 'fine_yarn']).canTake(fine), isTrue);
      expect(
        taken(['fine_yarn', 'fine_yarn', 'fine_yarn']).canTake(fine),
        isFalse,
      );
    });

    test('plus() is immutable, so an undo or a replay is free', () {
      final a = taken(['overtime']);
      final b = a.plus(const PickedPower('overtime'));
      expect(a.stacksOf('overtime'), 1);
      expect(b.stacksOf('overtime'), 2);
    });
  });

  group('milestones', () {
    test('every unlock string in the JSON is one this code understands', () {
      // A milestone this switch does not recognise would silently lock a card
      // out of the game forever, which is exactly the kind of bug nobody sees.
      const generous = Milestones(
        tier3Owned: 99,
        motifsOwned: 99,
        bestStage: 99,
        bestRhythm: 99,
        runsFinished: 99,
        clearedThreeAtOnce: true,
        lostToBrokenRhythm: true,
        jammed: true,
        spoolsBanked: 999999,
      );
      for (final d in pool.defs) {
        expect(generous.satisfies(d.unlock), isTrue, reason: d.unlock);
      }
    });

    test('a fresh account unlocks exactly the initial twelve', () {
      const fresh = Milestones();
      final unlocked = pool.defs.where((d) => fresh.satisfies(d.unlock));
      expect(unlocked, hasLength(12));
      expect(unlocked.every((d) => d.isInitial), isTrue);
    });

    test('an unrecognised milestone never unlocks anything', () {
      expect(const Milestones().satisfies('befriend a loom'), isFalse);
    });
  });

  group('offerDraft', () {
    test('offers three distinct cards', () {
      final offer = offerDraft(
        pool,
        PowerSet.empty,
        const Milestones(),
        1,
        Rng(1),
      );
      expect(offer, hasLength(3));
      expect(offer.map((d) => d.id).toSet(), hasLength(3));
    });

    test('Apprentice makes every draft four options', () {
      final offer = offerDraft(
        pool,
        taken(['apprentice']),
        const Milestones(bestStage: 6),
        6,
        Rng(1),
      );
      expect(offer, hasLength(4));
    });

    test('never offers a locked card', () {
      for (var seed = 1; seed <= 60; seed++) {
        final offer = offerDraft(
          pool,
          PowerSet.empty,
          const Milestones(),
          1,
          Rng(seed),
        );
        expect(offer.every((d) => d.isInitial), isTrue);
      }
    });

    test('never offers a card the player has already maxed', () {
      final maxed = taken(['temple']);
      for (var seed = 1; seed <= 60; seed++) {
        final offer = offerDraft(
          pool,
          maxed,
          const Milestones(),
          1,
          Rng(seed),
        );
        expect(offer.map((d) => d.id), isNot(contains('temple')));
      }
    });

    test('no rares in the opening stages', () {
      // The first three picks should teach the systems, not define the run.
      for (var seed = 1; seed <= 120; seed++) {
        final offer = offerDraft(
          pool,
          PowerSet.empty,
          const Milestones(bestStage: 12, motifsOwned: 22, tier3Owned: 6),
          3,
          Rng(seed),
        );
        expect(
          offer.any((d) => d.rarity == Rarity.rare),
          isFalse,
          reason: 'seed $seed',
        );
      }
    });

    test('rares do appear once the weights allow them', () {
      var sawRare = false;
      for (var seed = 1; seed <= 200 && !sawRare; seed++) {
        final offer = offerDraft(
          pool,
          PowerSet.empty,
          const Milestones(
            bestStage: 12,
            motifsOwned: 22,
            tier3Owned: 6,
            runsFinished: 9,
            clearedThreeAtOnce: true,
            lostToBrokenRhythm: true,
            jammed: true,
            bestRhythm: 3.5,
            spoolsBanked: 6000,
          ),
          9,
          Rng(seed),
        );
        sawRare = offer.any((d) => d.rarity == Rarity.rare);
      }
      expect(sawRare, isTrue);
    });

    test('a fault reward tier restricts the offer', () {
      final milestones = const Milestones(
        bestStage: 12,
        motifsOwned: 22,
        tier3Owned: 6,
        runsFinished: 9,
        clearedThreeAtOnce: true,
        lostToBrokenRhythm: true,
        jammed: true,
        bestRhythm: 3.5,
        spoolsBanked: 6000,
      );
      final better = offerDraft(
        pool,
        PowerSet.empty,
        milestones,
        8,
        Rng(4),
        reward: DraftReward.uncommonOrBetter,
      );
      expect(better.every((d) => d.rarity != Rarity.common), isTrue);

      final rares = offerDraft(
        pool,
        PowerSet.empty,
        milestones,
        12,
        Rng(4),
        reward: DraftReward.raresOnly,
      );
      expect(rares.every((d) => d.rarity == Rarity.rare), isTrue);
    });

    test('falls back rather than handing the player a short draft', () {
      // Only the initial twelve are unlocked, so "rares only" cannot be
      // honoured — a fault reward must never produce an empty draft screen.
      final offer = offerDraft(
        pool,
        PowerSet.empty,
        const Milestones(),
        4,
        Rng(2),
        reward: DraftReward.raresOnly,
      );
      expect(offer, hasLength(3));
    });

    test('is deterministic for a seed, so a replay shows the same three', () {
      final a = offerDraft(pool, PowerSet.empty, const Milestones(), 2, Rng(9));
      final b = offerDraft(pool, PowerSet.empty, const Milestones(), 2, Rng(9));
      expect(a.map((d) => d.id), b.map((d) => d.id));
    });

    test('still offers something when almost everything is maxed', () {
      var set = PowerSet.empty;
      for (final d in pool.defs.where((d) => d.isInitial)) {
        for (var i = 0; i < d.stacks; i++) {
          set = set.plus(PickedPower(d.id));
        }
      }
      final offer = offerDraft(pool, set, const Milestones(), 3, Rng(1));
      expect(offer, isEmpty, reason: 'nothing left is legitimately empty');
    });
  });

  group('placementTouchesEdge', () {
    test('detects every boundary and nothing in the middle', () {
      final dot = cellsOf('dot', 0);
      expect(placementTouchesEdge(dot, 0, 3, 8, 8), isTrue);
      expect(placementTouchesEdge(dot, 7, 3, 8, 8), isTrue);
      expect(placementTouchesEdge(dot, 3, 0, 8, 8), isTrue);
      expect(placementTouchesEdge(dot, 3, 7, 8, 8), isTrue);
      expect(placementTouchesEdge(dot, 3, 3, 8, 8), isFalse);
    });

    test('a long motif counts if any one cell reaches the edge', () {
      expect(placementTouchesEdge(cellsOf('i4', 0), 4, 3, 8, 8), isTrue);
      expect(placementTouchesEdge(cellsOf('i4', 0), 3, 3, 8, 8), isFalse);
    });
  });

  group('estimatedGain', () {
    test('sums the pool estimates for the run summary', () {
      expect(taken(['standard_yarn', 'overtime']).estimatedGain(pool), 18 + 15);
    });
  });

  group('curve interaction', () {
    test('a full build keeps stage 12 reachable but not trivial', () {
      // docs/06 §2: eleven picks compounding at the pool's target average of
      // +19% give 6.8x, so a perfect draft on perfect play lands just short of
      // the 7.4x the finish line asks. The remaining gap is what the meta is
      // for.
      const cfg = CurveConfig.defaults;
      final floorCapability = 158.0;
      final demanded = targetFor(cfg, 12) / floorCapability;
      expect(demanded, closeTo(7.4, 0.1));

      // Eleven picks compounding at the pool's *target* average of +19% give
      // 6.8x, so a perfect draft on perfect play lands just short of the
      // finish line. That near-miss is the whole design: the remaining gap is
      // what the meta is for.
      var atTarget = 1.0;
      for (var i = 0; i < 11; i++) {
        atTarget *= 1.19;
      }
      expect(atTarget, closeTo(6.8, 0.1));
      expect(atTarget, lessThan(demanded), reason: 'a perfect draft falls short');
      expect(atTarget, greaterThan(demanded * 0.85), reason: 'but only just');

      // The *pool* mean is lower than that target, and deliberately so: the
      // player is offered three and takes one, so the average card *taken* is
      // well above the average card *printed*. Asserting the pool mean against
      // 19% would be comparing the wrong two numbers — but it must still stay
      // under the 25% growth rate, which the test above pins.
      final gains = pool.defs.where((d) => !d.gamble).map((d) => d.gain);
      final poolMean = gains.reduce((a, b) => a + b) / gains.length;
      expect(poolMean, lessThan(19));
    });
  });
}
