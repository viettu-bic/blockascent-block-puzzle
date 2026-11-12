/// The draft: 33 cards, one pick per stage cleared, three offered.
///
/// The card list is data (`data/powers.json`); this file is the pure
/// aggregation of a *picked set* into the numbers the rules engine takes —
/// [TurnModifiers], [LadderModifiers], a cell-value function and a handful of
/// flags. Keeping it here rather than in the UI means a build's arithmetic is
/// unit-testable and the simulation can play one.
///
/// ## The number everything hangs on (docs/05 §1)
///
/// Targets grow ×1.25 per stage and the player gets exactly one pick per
/// stage, so the average pick must be worth slightly **less** than +25%
/// capability or the ladder becomes infinite. The pool is built to average
/// +18–20%. Nothing in this file may quietly exceed that; if a card turns out
/// stronger than its `gain`, the fix is the JSON, not the code.
library;

import 'dart:math' as math;

import 'rng.dart';
import 'run.dart';
import 'scoring.dart';
import 'types.dart';

enum Rarity { common, uncommon, rare }

Rarity rarityFromName(String s) => switch (s) {
  'common' => Rarity.common,
  'uncommon' => Rarity.uncommon,
  'rare' => Rarity.rare,
  _ => throw ArgumentError('unknown rarity: $s'),
};

/// One card as it appears in `data/powers.json`.
class PowerDef {
  const PowerDef({
    required this.id,
    required this.family,
    required this.rarity,
    required this.unlock,
    required this.stacks,
    required this.gain,
    required this.effect,
    this.gamble = false,
    this.measured = false,
  });

  final String id;
  final String family;
  final Rarity rarity;

  /// `initial` for the twelve available from install, otherwise a milestone
  /// description from docs/05 §4.
  final String unlock;

  /// How many times this card may be taken in one run.
  final int stacks;

  /// Estimated percentage of per-stage capability, against the measured floor
  /// baseline of ~158 points/stage. These are numbers the simulation must
  /// confirm, not numbers it has confirmed.
  final int gain;
  final String effect;

  /// Trades depth for currency, so it is excluded from the rarity averages.
  final bool gamble;

  /// True when [gain] came out of the simulation rather than out of a guess.
  ///
  /// Worth keeping distinct: the estimates this pool shipped with were wrong by
  /// 2× to 8× in **both** directions, so a reader needs to know which numbers
  /// are evidence. `test/sim/meta_sim.dart`, `measureCard`.
  final bool measured;

  bool get isInitial => unlock == 'initial';

  /// Cards whose effect is a one-off choice resolved at pick time rather than
  /// a standing modifier.
  bool get needsMotifChoice =>
      id == 'slub_yarn' || id == 'cull' || id == 'favour';

  /// Cards the player activates during a stage, rather than passive numbers.
  bool get isTool => const {
    'unpick',
    'rethread',
    'shears',
    'hold',
    'batten',
    'resley',
  }.contains(id);

  @override
  String toString() => 'PowerDef($id)';
}

/// Upgrade names, written as what the card does.
///
/// The ids stay as they are: they are tuning keys shared with
/// `data/powers.json` and save keys in a run in progress.
const Map<String, String> powerNames = {
  'fine_yarn': 'Small Block Bonus',
  'standard_yarn': 'Mid Block Bonus',
  'slub_yarn': 'Favourite Block',
  'heavy_yarn': 'Big Block Bonus',
  'doubleweave': 'Edge Bonus',
  'gilt_thread': 'Golden Blocks',
  'quick_shuttle': 'Faster Combo',
  'weftwise': 'Row Bonus',
  'warpwise': 'Column Bonus',
  'steady_beat': 'Higher Combo Cap',
  'double_pick': 'Double Combo',
  'treadle_rhythm': 'Combo Floor',
  'selvage': 'Shield',
  'tabby': 'Points Per Block',
  'temple': 'Free Miss',
  'patience': 'Extra Patience',
  'floating_selvage': 'Soft Landing',
  'mending': 'Repair',
  'unpick': 'Eraser',
  'rethread': 'Reshuffle',
  'shears': 'Bomb',
  'hold': 'Hold',
  'batten': 'Line Clear',
  'second_shuttle': 'Extra Slot',
  'cull': 'Remove Block',
  'favour': 'Duplicate Block',
  'small_hands': 'Small Block Guarantee',
  'jacquard_card': 'Preview Next',
  'resley': 'Swap Tray',
  'overtime': 'Extra Moves',
  'piecework': 'Bonus Coins',
  'apprentice': 'Extra Choice',
  'short_bolt': 'Lower Targets',
  'bulk_order': 'Big Payout',
};

/// Upgrade families, as shown on a card.
const Map<String, String> powerFamilyNames = {
  'yarn': 'score',
  'rhythm': 'combo',
  'selvage': 'defence',
  'tools': 'tools',
  'draft': 'blocks',
  'commission': 'bonus',
};

String powerFamilyName(String family) => powerFamilyNames[family] ?? family;

String powerName(String id) => powerNames[id] ?? id;

/// Rarity weights by stages cleared, from `powers.json.offer.weights`.
class OfferWeights {
  const OfferWeights({
    required this.upToStage,
    required this.common,
    required this.uncommon,
    required this.rare,
  });

  final int upToStage;
  final int common;
  final int uncommon;
  final int rare;

  int weightOf(Rarity r) => switch (r) {
    Rarity.common => common,
    Rarity.uncommon => uncommon,
    Rarity.rare => rare,
  };
}

class PowerPool {
  const PowerPool({
    required this.defs,
    required this.offerCount,
    required this.weights,
    this.noDuplicateUnlessStackable = true,
  });

  final List<PowerDef> defs;
  final int offerCount;
  final List<OfferWeights> weights;
  final bool noDuplicateUnlessStackable;

  PowerDef byId(String id) => defs.firstWhere(
    (d) => d.id == id,
    orElse: () => throw ArgumentError('unknown power: $id'),
  );

  OfferWeights weightsFor(int stagesCleared) => weights.firstWhere(
    (w) => stagesCleared <= w.upToStage,
    orElse: () => weights.last,
  );
}

/// One card the player has taken, with whatever choice it demanded.
class PickedPower {
  const PickedPower(this.id, {this.motifId});

  final String id;

  /// Slub Yarn (+3 value to one motif), Cull, Favour.
  final String? motifId;

  @override
  String toString() =>
      'PickedPower($id${motifId != null ? ' -> $motifId' : ''})';
}

/// Flat per-cell value bonuses bought with spools rather than drafted
/// (`data/economy.json.upgrades`).
class YarnUpgrades {
  const YarnUpgrades({
    this.fineYarn = false,
    this.standardYarn = false,
    this.heavyYarn = false,
  });

  static const YarnUpgrades none = YarnUpgrades();

  final bool fineYarn; // +1 to 1- and 2-cell motifs
  final bool standardYarn; // +1 to 3- and 4-cell motifs
  final bool heavyYarn; // +1 to 5-cell and larger motifs
}

/// A build: the cards taken so far, reduced to numbers.
///
/// Immutable. [plus] returns a new set, so an undo or a replay is free.
class PowerSet {
  PowerSet(this.picks, {this.yarn = YarnUpgrades.none})
      : _counts = _tally(picks);

  final List<PickedPower> picks;
  final YarnUpgrades yarn;
  final Map<String, int> _counts;

  static const PowerSet empty = PowerSet._empty();

  const PowerSet._empty()
      : picks = const [],
        yarn = YarnUpgrades.none,
        _counts = const {};

  static Map<String, int> _tally(List<PickedPower> picks) {
    final out = <String, int>{};
    for (final p in picks) {
      out[p.id] = (out[p.id] ?? 0) + 1;
    }
    return out;
  }

  PowerSet plus(PickedPower pick) =>
      PowerSet([...picks, pick], yarn: yarn);

  PowerSet withYarn(YarnUpgrades y) => PowerSet(picks, yarn: y);

  int stacksOf(String id) => _counts[id] ?? 0;
  bool has(String id) => _counts.containsKey(id);

  /// Every motif named by a stack of [id] — Slub Yarn can be taken three
  /// times, each on a different motif.
  List<String> motifsFor(String id) => [
    for (final p in picks)
      if (p.id == id && p.motifId != null) p.motifId!,
  ];

  /// Can this card still be offered?
  ///
  /// "A card already owned is only re-offered if it stacks" (docs/05 §2).
  bool canTake(PowerDef def) => stacksOf(def.id) < def.stacks;

  /* ---------------- derived numbers ---------------- */

  /// Per-cell value for a motif of this size and identity.
  /// Points a single cell of a placed motif is worth.
  ///
  /// **Starts at zero.** Placing a block scores nothing on its own as of
  /// 2026-11-12 — points come from clearing a row or a column, full stop. It
  /// used to start at 1, which paid for every placement whether it achieved
  /// anything or not: about 44% of a stage's score for putting a shape down.
  ///
  /// Placement scoring is now something you *buy or draft*, band by band. The
  /// three bought yarns turn it on for their size band permanently, the yarn
  /// cards do it for a run, Slub Yarn does it for one motif you name, and
  /// **Tabby** turns it on across the board. That makes the whole yarn family
  /// an income stream a player opts into rather than a flat bonus everybody
  /// already has, and it is why none of them is dead without the others
  /// (docs/05 §10).
  int cellValueFor(int cellCount, String shapeId) {
    var v = 0;
    // Tabby: every band scores, modestly.
    v += stacksOf('tabby');
    if (cellCount <= 2) {
      v += 2 * stacksOf('fine_yarn');
      if (yarn.fineYarn) v += 3;
    } else if (cellCount <= 4) {
      v += stacksOf('standard_yarn');
      if (yarn.standardYarn) v += 3;
    } else {
      v += stacksOf('heavy_yarn');
      if (yarn.heavyYarn) v += 3;
    }
    v += 2 * stacksOf('gilt_thread');
    v += 3 * motifsFor('slub_yarn').where((id) => id == shapeId).length;
    return v;
  }

  /// Extra tray slots. Second Shuttle is a 4th slot — deliberately a rare
  /// draft card and *not* a permanent upgrade, because it alters the
  /// refill-on-empty rule the whole difficulty rests on
  /// (`economy.json._notIncluded`).
  int get extraTraySlots => stacksOf('second_shuttle');

  int get draftOfferBonus => has('apprentice') ? 1 : 0;

  bool get seesNextRefill => has('jacquard_card');
  bool get guaranteesSmallMotif => has('small_hands');
  bool get hasHold => has('hold');

  /// Shields granted at the start of every stage (Selvage refills).
  int get shieldsPerStage => stacksOf('selvage');

  double get spoolMultiplier => has('bulk_order') ? 1.6 : 1.0;
  int get spoolsPerStageBonus => 25 * stacksOf('piecework');

  ScoringConfig applyTo(ScoringConfig cfg) => cfg.copyWith(
    multStep: cfg.multStep + 0.05 * stacksOf('quick_shuttle'),
    multCap: cfg.multCap + 1.0 * stacksOf('steady_beat'),
    patienceMax: cfg.patienceMax + stacksOf('patience'),
  );

  LadderModifiers get ladderModifiers => LadderModifiers(
    allowanceBonus: 3 * stacksOf('overtime') - 2 * stacksOf('gilt_thread'),
    targetScale: math.pow(0.8, stacksOf('short_bolt')).toDouble() *
        math.pow(1.15, stacksOf('bulk_order')).toDouble(),
  );

  /// Charges a tool starts each stage with. 0 means "not taken".
  ///
  /// Batten is per *run*, not per stage, so it is excluded here and handled by
  /// the controller.
  int chargesPerStage(String id) => switch (id) {
    'unpick' => 2 * stacksOf('unpick'),
    'rethread' => 2 * stacksOf('rethread'),
    'shears' => 1 * stacksOf('shears'),
    'resley' => has('resley') ? 1 : 0,
    _ => 0,
  };

  int get battenChargesPerRun => has('batten') ? 1 : 0;

  /// The modifiers for one turn.
  ///
  /// [rows] / [cols] are the lines this placement completed, [touchesEdge]
  /// whether any of its cells sit on the board boundary, and
  /// **Both of this card family's buffs were tried and reverted on
  /// 2026-11-11, and the reason is the most useful thing C5 produced.**
  ///
  /// Quick Shuttle measured 3% and Temple 2%, both far below their common
  /// band, so both were strengthened: the rhythm step doubled, and Temple
  /// became a break floor. Measured, each one on its own raised the
  /// **0%-unlock median from stage 6 to 9-10** and let a 0%-unlock account
  /// win the campaign. Swept nine growth values from 1.34 to 1.54 and there is
  /// no curve that takes it back: steepening shifts all three gates together,
  /// and what the buff did was **close the gap** between 0% and 100% unlocks
  /// from +6 stages to +2.
  ///
  /// The uncomfortable conclusion: **a weak opening pool is load-bearing.**
  /// Part of what makes a 0%-unlock player weak is that their twelve cards
  /// include duds, and making every starter card generically good removes the
  /// reason to unlock anything. "No wasted picks" and "the shop must matter"
  /// are in direct conflict as long as the fix is *general* strength.
  ///
  /// The way out is **situational** strength: a card that is the right pick in
  /// a specific spot and mediocre on average removes the wasted pick without
  /// raising the floor. That is two new effects and a re-measure, not a tuning
  /// pass, and it is scoped as docs/08 C5.
  ///
  /// [freeDryPlacement] whether Temple's once-per-stage grace is still unused.
  TurnModifiers turnModifiers({
    int rows = 0,
    int cols = 0,
    bool touchesEdge = false,
    bool freeDryPlacement = false,
  }) => TurnModifiers(
    flatBonus: touchesEdge ? 3 * stacksOf('doubleweave') : 0,
    extraMultOnRow: 0.2 * stacksOf('weftwise'),
    extraMultOnCol: 0.2 * stacksOf('warpwise'),
    doubleMultOnMultiLine: has('double_pick'),
    freeDryPlacement: freeDryPlacement && has('temple'),
    multFloor: has('treadle_rhythm') ? 1.5 : 0.0,
    breakFloor: has('floating_selvage') ? 2.0 : 0.0,
    restoreShieldOnBigClear: has('mending'),
    rows: rows,
    cols: cols,
  );

  /// Sum of the pool's own `gain` estimates — a rough read on build strength,
  /// shown on the run summary so a player can see why a run went deep.
  int estimatedGain(PowerPool pool) {
    var total = 0;
    for (final p in picks) {
      total += pool.byId(p.id).gain;
    }
    return total;
  }
}

/// Does any cell of this placement touch the board boundary? (Doubleweave.)
bool placementTouchesEdge(
  ShapeCells cells,
  int ax,
  int ay,
  int boardW,
  int boardH,
) {
  for (final (cx, cy) in cells) {
    final x = ax + cx;
    final y = ay + cy;
    if (x == 0 || y == 0 || x == boardW - 1 || y == boardH - 1) return true;
  }
  return false;
}

/// Which milestones a player has reached, for the 21 unlockable cards.
///
/// Unlocked by milestones, not by spools: milestones pace discovery to skill
/// rather than to grind, and the spool economy is already fully allocated
/// across motifs and upgrades (docs/05 §4).
class Milestones {
  const Milestones({
    this.tier3Owned = 0,
    this.motifsOwned = 5,
    this.bestStage = 0,
    this.bestRhythm = 1.0,
    this.runsFinished = 0,
    this.clearedThreeAtOnce = false,
    this.lostToBrokenRhythm = false,
    this.jammed = false,
    this.spoolsBanked = 0,
  });

  final int tier3Owned;
  final int motifsOwned;
  final int bestStage;
  final double bestRhythm;
  final int runsFinished;
  final bool clearedThreeAtOnce;
  final bool lostToBrokenRhythm;
  final bool jammed;
  final int spoolsBanked;

  bool satisfies(String unlock) => switch (unlock) {
    'initial' => true,
    'own 4 tier-3 motifs' => tier3Owned >= 4,
    'own 10 motifs' => motifsOwned >= 10,
    'clear stage 4' => bestStage >= 4,
    'clear stage 5' => bestStage >= 5,
    'clear stage 6' => bestStage >= 6,
    'clear stage 7' => bestStage >= 7,
    'clear stage 8' => bestStage >= 8,
    'clear stage 9' => bestStage >= 9,
    'clear stage 10' => bestStage >= 10,
    'reach rhythm x3.0' => bestRhythm >= 3.0,
    // No card uses this since Double Pick was re-gated onto "clear stage 7"
    // (docs/05 §8) — a rare behind something that can happen by luck on run 1.
    // Kept because the controller still records it and it is the natural gate
    // for a future line-stacker card.
    'clear 3 lines at once' => clearedThreeAtOnce,
    'lose a run to a broken rhythm' => lostToBrokenRhythm,
    'jam a run' => jammed,
    'finish 5 runs' => runsFinished >= 5,
    'bank 5000 spools' => spoolsBanked >= 5000,
    // An unrecognised milestone must never silently unlock a card.
    _ => false,
  };

  Map<String, dynamic> toJson() => {
    'tier3Owned': tier3Owned,
    'motifsOwned': motifsOwned,
    'bestStage': bestStage,
    'bestRhythm': bestRhythm,
    'runsFinished': runsFinished,
    'clearedThreeAtOnce': clearedThreeAtOnce,
    'lostToBrokenRhythm': lostToBrokenRhythm,
    'jammed': jammed,
    'spoolsBanked': spoolsBanked,
  };

  /// Tolerant field by field, like the account's own loader: a save written by
  /// an older build must not cost a player their unlocks.
  static Milestones fromJson(Map<String, dynamic> j) => Milestones(
    tier3Owned: (j['tier3Owned'] as num?)?.toInt() ?? 0,
    motifsOwned: (j['motifsOwned'] as num?)?.toInt() ?? 0,
    bestStage: (j['bestStage'] as num?)?.toInt() ?? 0,
    bestRhythm: (j['bestRhythm'] as num?)?.toDouble() ?? 1.0,
    runsFinished: (j['runsFinished'] as num?)?.toInt() ?? 0,
    clearedThreeAtOnce: (j['clearedThreeAtOnce'] as bool?) ?? false,
    lostToBrokenRhythm: (j['lostToBrokenRhythm'] as bool?) ?? false,
    jammed: (j['jammed'] as bool?) ?? false,
    spoolsBanked: (j['spoolsBanked'] as num?)?.toInt() ?? 0,
  );

  Milestones copyWith({
    int? tier3Owned,
    int? motifsOwned,
    int? bestStage,
    double? bestRhythm,
    int? runsFinished,
    bool? clearedThreeAtOnce,
    bool? lostToBrokenRhythm,
    bool? jammed,
    int? spoolsBanked,
  }) => Milestones(
    tier3Owned: tier3Owned ?? this.tier3Owned,
    motifsOwned: motifsOwned ?? this.motifsOwned,
    bestStage: bestStage ?? this.bestStage,
    bestRhythm: bestRhythm ?? this.bestRhythm,
    runsFinished: runsFinished ?? this.runsFinished,
    clearedThreeAtOnce: clearedThreeAtOnce ?? this.clearedThreeAtOnce,
    lostToBrokenRhythm: lostToBrokenRhythm ?? this.lostToBrokenRhythm,
    jammed: jammed ?? this.jammed,
    spoolsBanked: spoolsBanked ?? this.spoolsBanked,
  );
}

/// Reward tier for a fault stage draft (`faults.json.rewardTiers`).
enum DraftReward {
  normal,
  uncommonOrBetter,
  raresOnly,
}

/// Offer [count] cards, weighted by rarity and filtered by what is unlocked,
/// already maxed, or excluded by a fault's reward tier.
///
/// Draws from [rng] so a draft is part of the seeded stream and a replay
/// reproduces the same three cards.
List<PowerDef> offerDraft(
  PowerPool pool,
  PowerSet taken,
  Milestones milestones,
  int stagesCleared,
  Rng rng, {
  int? count,
  DraftReward reward = DraftReward.normal,
}) {
  final n = count ?? (pool.offerCount + taken.draftOfferBonus);
  final weights = pool.weightsFor(stagesCleared);

  bool allowedByReward(PowerDef d) => switch (reward) {
    DraftReward.normal => true,
    DraftReward.uncommonOrBetter => d.rarity != Rarity.common,
    DraftReward.raresOnly => d.rarity == Rarity.rare,
  };

  var candidates = pool.defs
      .where((d) => milestones.satisfies(d.unlock))
      .where((d) => !pool.noDuplicateUnlessStackable || taken.canTake(d))
      .where(allowedByReward)
      .toList();

  // A reward tier that leaves nothing to offer must fall back rather than
  // hand the player an empty draft.
  if (candidates.length < n) {
    candidates = pool.defs
        .where((d) => milestones.satisfies(d.unlock))
        .where((d) => taken.canTake(d))
        .toList();
  }

  final out = <PowerDef>[];
  final remaining = List.of(candidates);
  while (out.length < n && remaining.isNotEmpty) {
    // Weighted pick. Rarities with zero weight are still reachable only if
    // nothing else is left, which keeps "no rares before stage 4" honest
    // without ever producing a short draft.
    var totalWeight = 0;
    for (final d in remaining) {
      totalWeight += weights.weightOf(d.rarity);
    }
    PowerDef chosen;
    if (totalWeight <= 0) {
      chosen = remaining[rng.nextInt(remaining.length)];
    } else {
      var roll = rng.nextInt(totalWeight);
      chosen = remaining.first;
      for (final d in remaining) {
        roll -= weights.weightOf(d.rarity);
        if (roll < 0) {
          chosen = d;
          break;
        }
      }
    }
    out.add(chosen);
    remaining.remove(chosen);
  }
  return out;
}
