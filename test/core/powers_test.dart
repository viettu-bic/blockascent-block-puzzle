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
    test('is 34 cards, 13 of them available from install', () {
      expect(pool.defs, hasLength(34));
      expect(pool.defs.where((d) => d.isInitial), hasLength(13));
    });

    test('the initial thirteen are the docs/05 §3 list, plus Tabby', () {
      expect(
        pool.defs.where((d) => d.isInitial).map((d) => d.id).toSet(),
        {
          'tabby',
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

    test('the ESTIMATED cards still sit in their docs/05 §2 bands', () {
      // This used to assert the mean of every card against 10.9 / 15.8 / 25.5.
      // Those were the means of a set of *guesses*, so the assertion only ever
      // protected the guesses from being re-guessed.
      //
      // Eight cards now carry measured gains (`measured: true`) and they land
      // at 13–48%, which is nowhere near the bands. The bands were calibrated
      // against estimates that turned out to be 2× to 8× wrong in both
      // directions, so they describe the estimating, not the game.
      //
      // What is still worth guarding: the remaining estimates should stay
      // inside the bands their author intended, so a typo or a careless new
      // card is caught. Measured cards are exempt by definition — a
      // measurement cannot be out of band, it can only be inconvenient.
      double meanOf(Rarity r) {
        final xs = pool.defs
            .where((d) => d.rarity == r && !d.gamble && !d.measured)
            .map((d) => d.gain)
            .toList();
        return xs.reduce((a, b) => a + b) / xs.length;
      }

      expect(meanOf(Rarity.common), inInclusiveRange(8, 15));
      expect(meanOf(Rarity.uncommon), inInclusiveRange(15, 25));
      expect(meanOf(Rarity.rare), inInclusiveRange(25, 35));

      // The relationship that makes the rarity tiers mean anything: a first
      // pass had rares at 17.6%, statistically indistinguishable from
      // uncommons, which would have made the whole tier decorative.
      expect(meanOf(Rarity.rare), greaterThan(meanOf(Rarity.uncommon) + 5));
      expect(meanOf(Rarity.uncommon), greaterThan(meanOf(Rarity.common)));
    });

    test('the measured spread is recorded, both ends of it', () {
      final measured = pool.defs.where((d) => d.measured).toList();
      expect(measured, hasLength(8), reason: 'eight cards are measured so far');

      // **The weak end.** Quick Shuttle (3%) and Temple (2%) sit far below the
      // common band, and docs/08 C5 is about exactly that: a card a new player
      // is offered and never wants is a pick they paid for and wasted.
      //
      // Both were strengthened and both were reverted, because each one *on
      // its own* raised the 0%-unlock median from stage 6 to 9–10 and let a
      // 0%-unlock account win the campaign. There is no curve that takes that
      // back — steepening moves all three gates together, and what the buff
      // did was close the 0%-to-100% gap from +6 stages to +2. A weak opening
      // pool turns out to be load-bearing, and the way out is *situational*
      // strength rather than general strength (docs/05 §9).
      //
      // Named rather than asserted away, so the list cannot grow quietly.
      final weak = measured.where((d) => d.gain < 8).map((d) => d.id);
      expect(weak, unorderedEquals(['quick_shuttle', 'temple']));

      // **The strong end.** Two commons measure 48%, above even the rare band
      // and above the ×1.34 growth rate. Not acted on, because single-card
      // marginal gains do not compose: eleven picks at these values would be
      // astronomical, while an 85%-unlock account measurably wins well under
      // half its runs. The three gates are the trustworthy statement about the
      // whole game; this is a per-card ranking.
      final outliers = measured.where((d) => d.gain > 35).map((d) => d.id);
      expect(outliers, unorderedEquals(['standard_yarn', 'selvage']));
    });

    test('the estimates stay under the growth rate they were sized for', () {
      // docs/05 §1 calls this "THE number everything hangs on": targets grow
      // ×1.34 a stage and the player gets one pick a stage, so the average
      // pick must be worth less than +34% or the ladder is infinite.
      //
      // **The measurement says that arithmetic does not hold.** Measured cards
      // run 13–48%, which should make eleven picks unstoppable, and yet an
      // 85%-unlock account wins 20% of its runs and a 0%-unlock account wins
      // none. Single-card marginal gains, measured against a no-build
      // baseline, do not compose — the board fills, the allowance binds, and
      // the second copy of an effect is worth less than the first.
      //
      // So this is an **estimation discipline** check, not a law about the
      // game: the numbers an author invents should stay in the range docs/05
      // §1 aims at. Reachability is measured by the three gates
      // (`test/sim/gates_sim_test.dart`) and nowhere else.
      final gains =
          pool.defs.where((d) => !d.gamble && !d.measured).map((d) => d.gain);
      final mean = gains.reduce((a, b) => a + b) / gains.length;
      expect(mean, lessThan(25));
      expect(mean, inInclusiveRange(15, 21), reason: 'docs/05 §1 aims at 18-20');
    });

    test('no ESTIMATED card exceeds the rare ceiling', () {
      // A measured card can exceed it — two do, see above. An estimate that
      // exceeds it is someone inventing a number stronger than the strongest
      // tier the design has, which is what this catches.
      for (final d in pool.defs.where((d) => !d.measured)) {
        expect(d.gain, lessThanOrEqualTo(35), reason: d.id);
      }
    });
  });

  group('cellValueFor', () {
    test('is ZERO with no cards and no upgrades', () {
      // Placing a block scores nothing on its own as of 2026-11-12 — points
      // come from clearing a row or a column, full stop. Placement scoring is
      // bought or drafted band by band (docs/05 §10).
      expect(PowerSet.empty.cellValueFor(4, 'o2'), 0);
      expect(PowerSet.empty.cellValueFor(1, 'dot'), 0);
      expect(PowerSet.empty.cellValueFor(9, 'o3'), 0);
    });

    test('Tabby turns placement scoring on across every band', () {
      final s = taken(['tabby']);
      expect(s.cellValueFor(1, 'dot'), 1);
      expect(s.cellValueFor(4, 'o2'), 1);
      expect(s.cellValueFor(9, 'o3'), 1);
      // It stacks, and it is the only card that pays every size.
      expect(taken(['tabby', 'tabby']).cellValueFor(4, 'o2'), 2);
    });

    test('Small Block Bonus is +2 a stack, 1- and 2-block pieces only', () {
      final s = taken(['fine_yarn', 'fine_yarn']);
      expect(s.cellValueFor(1, 'dot'), 4);
      expect(s.cellValueFor(2, 'i2'), 4);
      expect(s.cellValueFor(3, 'i3'), 0);
    });

    test('Standard Yarn is +1 per stack to 3- and 4-cell motifs', () {
      final s = taken(['standard_yarn', 'standard_yarn', 'standard_yarn']);
      expect(s.cellValueFor(3, 'i3'), 3);
      expect(s.cellValueFor(4, 'o2'), 3);
      expect(s.cellValueFor(5, 'i5'), 0);
      expect(s.cellValueFor(2, 'i2'), 0);
    });

    test('Heavy Yarn is +1 per stack to 5-cell and larger motifs', () {
      final s = taken(['heavy_yarn']);
      expect(s.cellValueFor(5, 'i5'), 1);
      expect(s.cellValueFor(9, 'o3'), 1);
      expect(s.cellValueFor(4, 'o2'), 0);
    });

    test('Gilt Thread is +2 to every motif, at the cost of placements', () {
      final s = taken(['gilt_thread']);
      expect(s.cellValueFor(1, 'dot'), 2);
      expect(s.cellValueFor(9, 'o3'), 2);
      expect(s.ladderModifiers.allowanceBonus, -2);
    });

    test('Slub Yarn is +3 to the chosen motif only', () {
      final s = PowerSet([const PickedPower('slub_yarn', motifId: 'l3')]);
      expect(s.cellValueFor(3, 'l3'), 3);
      expect(s.cellValueFor(3, 'i3'), 0);
    });

    test('Slub Yarn stacks onto different motifs independently', () {
      final s = PowerSet([
        const PickedPower('slub_yarn', motifId: 'l3'),
        const PickedPower('slub_yarn', motifId: 'l3'),
        const PickedPower('slub_yarn', motifId: 'i3'),
      ]);
      expect(s.cellValueFor(3, 'l3'), 6);
      expect(s.cellValueFor(3, 'i3'), 3);
    });

    test('the bought yarn upgrades add +3 on top of the drafted cards', () {
      final s = taken(['fine_yarn']).withYarn(
        const YarnUpgrades(fineYarn: true, standardYarn: true, heavyYarn: true),
      );
      // base ZERO + Fine Yarn the card (+2 a stack) + Fine Yarn the upgrade
      // (+3). The bought yarns went +1 -> +3, and the base went 1 -> 0, so a
      // yarn is now the thing that turns placement income on for its band
      // rather than a bonus on top of income everybody had (docs/05 §10).
      expect(s.cellValueFor(1, 'dot'), 0 + 2 + 3);
      expect(s.cellValueFor(3, 'i3'), 0 + 3);
      expect(s.cellValueFor(6, 'r23'), 0 + 3);
    });
  });

  group('scoring and ladder modifiers', () {
    test('Quick Shuttle raises the rhythm step by 0.05 a stack', () {
      // It measures **3%** at this value, against a common band of 8–15%: the
      // rhythm breaks often enough that climbing fractionally faster rarely
      // reaches any higher first. 0.10 was tried — it measures 18% — and
      // reverted, because it moved the 0%-unlock median from stage 6 to 9 and
      // let a 0%-unlock account win (docs/05 §9, docs/08 C5).
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
      // Base patience is 3 since 2026-11-11, so the card reads 3 -> 4. Worth
      // re-pricing: +1 on a base of 3 is a smaller relative gain than +1 on a
      // base of 2, and Patience is estimated at +24% on the old base
      // (docs/08 C1).
      expect(cfg.patienceMax, 4);
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

      // It measures **2%**, and the reason is visible in `scoreTurn`: patience
      // already refills to full on *every* clearing placement, so a break
      // takes several dry placements in a row and one free miss a stage barely
      // moves it. The card is not underpriced — it is redundant with a rule
      // the engine already has. Replacing it with a break floor was tried and
      // reverted (docs/05 §9).
      expect(pool.byId('temple').gain, 2);
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
      // 14, not 18. The build takes Standard Yarn, which is +1 a stack to a
      // 4-cell motif — and `cellValue` starts at ZERO now, so a placement is
      // worth 4 × 1 rather than 4 × 2 (docs/05 §10). The 10 is the line bonus,
      // which is where points actually come from.
      expect(out.gained, 4 * 1 + 10);
      // 1.0 + 0.25 (Quick Shuttle's step) + 0.20 (Weftwise on one row).
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

    test('a fresh account unlocks exactly the initial thirteen', () {
      const fresh = Milestones();
      final unlocked = pool.defs.where((d) => fresh.satisfies(d.unlock));
      expect(unlocked, hasLength(13));
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
      // Both of these carry measured gains now (48 and 18), so the sum moves
      // whenever a measurement is refreshed. Read from the pool rather than
      // written as a literal, so this tests the summing and not the numbers.
      expect(
        taken(['standard_yarn', 'overtime']).estimatedGain(pool),
        pool.byId('standard_yarn').gain + pool.byId('overtime').gain,
      );
    });
  });

  group('curve interaction', () {
    test('a full build keeps stage 12 reachable but not trivial', () {
      // **The "x floor capability" arithmetic this test used to assert is
      // retired.** It read: stage 12 asks 7.4x a floor player's 158 points a
      // stage, eleven picks at +19% give 6.8x, so a perfect draft lands just
      // short and the meta covers the rest.
      //
      // Every number in that chain was measured on a player who no longer
      // exists - patience 2, a 13-motif loadout, no draft, no account - and
      // `targetGrowth` has since been re-steepened to 1.32 against a player
      // who has all four. Stage 12 now asks 13.4x that historical floor,
      // which says nothing useful about whether it is reachable.
      //
      // Reachability is measured directly instead, by the three gates in
      // `test/sim/gates_sim_test.dart`: unwinnable at 0% unlocks, won by 38%
      // of runs at 85%, by 75% at 100%. What survives here is the
      // *relationship* that does not depend on any floor estimate.
      const cfg = CurveConfig.defaults;
      final demanded = targetFor(cfg, 12) / 158.0;
      expect(
        demanded,
        greaterThan(7.4),
        reason: 'kept only to catch the historical ratio being read as live',
      );

      // Invariant: targets grow x1.32 a stage and the player gets exactly one
      // pick per stage, so the average pick must be worth less than +32% or
      // the ladder is infinite and runs never end. This is the one piece of
      // the old arithmetic still load-bearing, because it compares two rates
      // rather than a rate against a measured absolute.
      var atTarget = 1.0;
      for (var i = 0; i < 11; i++) {
        atTarget *= 1.19;
      }
      expect(atTarget, closeTo(6.8, 0.1));
      expect(
        1.19,
        lessThan(cfg.targetGrowth),
        reason: 'the average pick must not outrun the curve',
      );

      // The *pool* mean is lower than that target, and deliberately so: the
      // player is offered three and takes one, so the average card *taken* is
      // well above the average card *printed*. Asserting the pool mean against
      // 19% would be comparing the wrong two numbers — but it must still stay
      // under the 25% growth rate, which the test above pins.
      // Estimates only. Including the eight measured cards pulls this to
      // 19.25 and makes it a statement about measurements rather than about
      // the authoring discipline it is here to guard.
      final gains =
          pool.defs.where((d) => !d.gamble && !d.measured).map((d) => d.gain);
      final poolMean = gains.reduce((a, b) => a + b) / gains.length;
      expect(poolMean, lessThan(19));
    });
  });
}
