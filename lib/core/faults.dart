/// Fault stages — this design's bosses. Three per act, offered as a choice of
/// three at the act's start, sitting at stages 4, 8 and 12.
///
/// The roster is data (`data/faults.json`); this file is the pure translation
/// of one chosen fault into the rule changes the engine already understands.
/// Every fault is expressed as a value on [FaultEffects], never as a special
/// case inside the placement path — which is why an act-3 fault cannot break
/// act 1.
///
/// Each should be survivable by at least three archetypes and trivial for
/// none (docs/06 §5).
library;

import 'board.dart';
import 'powers.dart';
import 'rng.dart';
import 'run.dart';
import 'scoring.dart';
import 'types.dart';

class FaultDef {
  const FaultDef({
    required this.id,
    required this.name,
    required this.tier,
    required this.rule,
    required this.attacks,
    required this.act,
    required this.stage,
  });

  final String id;
  final String name;

  /// 1..3 within the act. Also the draft reward tier for clearing it.
  final int tier;
  final String rule;
  final String attacks;
  final int act;
  final int stage;

  /// `faults.json.rewardTiers`: a harder fault pays a better draft.
  DraftReward get reward => switch (tier) {
    1 => DraftReward.normal,
    2 => DraftReward.uncommonOrBetter,
    _ => DraftReward.raresOnly,
  };

  @override
  String toString() => 'FaultDef($id)';
}

class FaultAct {
  const FaultAct({
    required this.act,
    required this.stage,
    required this.name,
    required this.faults,
  });

  final int act;
  final int stage;
  final String name;
  final List<FaultDef> faults;
}

class FaultRoster {
  const FaultRoster(this.acts);

  final List<FaultAct> acts;

  List<FaultDef> get all => [for (final a in acts) ...a.faults];

  FaultAct? actForStage(int stage) {
    for (final a in acts) {
      if (a.stage == stage) return a;
    }
    return null;
  }

  FaultDef byId(String id) => all.firstWhere(
    (f) => f.id == id,
    orElse: () => throw ArgumentError('unknown fault: $id'),
  );
}

/// Everything a fault can change about one stage.
///
/// The default value of every field is "the game as normal", so a stage with
/// no fault constructs [FaultEffects.none] and nothing downstream branches.
class FaultEffects {
  const FaultEffects({
    this.axes = ClearAxes.both,
    this.allowanceScale = 1.0,
    this.targetScale = 1.0,
    this.patienceOverride,
    this.rotationDisabled = false,
    this.minCellCount,
    this.boardSize,
    this.startingKnots = 0,
    this.knotEveryNthPlacement,
    this.knotOnDryPlacement = false,
  });

  static const FaultEffects none = FaultEffects();

  /// Reediness: only columns clear this stage.
  final ClearAxes axes;

  /// Thin Place: allowance ×0.7, target ×0.75.
  final double allowanceScale;
  final double targetScale;

  /// Mispick: patience reduced to 1.
  final int? patienceOverride;

  /// Fixed Heddles: rotation disabled for this stage.
  final bool rotationDisabled;

  /// Barré: the bag serves only motifs of this many cells or more.
  final int? minCellCount;

  /// Tight Reed: the board is this wide and tall for this stage.
  final int? boardSize;

  /// Slubs: this many knots are scattered on the board at stage start.
  final int startingKnots;

  /// The Smash: every nth placement, a random empty cell becomes a knot.
  final int? knotEveryNthPlacement;

  /// Floats: any placement that clears no line leaves one of its own cells as
  /// a knot.
  final bool knotOnDryPlacement;

  bool get isActive => this != FaultEffects.none;

  LadderModifiers get ladderModifiers => LadderModifiers(
    allowanceScale: allowanceScale,
    targetScale: targetScale,
  );

  ScoringConfig applyTo(ScoringConfig cfg) => patienceOverride == null
      ? cfg
      : cfg.copyWith(patienceMax: patienceOverride);

  @override
  bool operator ==(Object other) =>
      other is FaultEffects &&
      other.axes == axes &&
      other.allowanceScale == allowanceScale &&
      other.targetScale == targetScale &&
      other.patienceOverride == patienceOverride &&
      other.rotationDisabled == rotationDisabled &&
      other.minCellCount == minCellCount &&
      other.boardSize == boardSize &&
      other.startingKnots == startingKnots &&
      other.knotEveryNthPlacement == knotEveryNthPlacement &&
      other.knotOnDryPlacement == knotOnDryPlacement;

  @override
  int get hashCode => Object.hash(
    axes,
    allowanceScale,
    targetScale,
    patienceOverride,
    rotationDisabled,
    minCellCount,
    boardSize,
    startingKnots,
    knotEveryNthPlacement,
    knotOnDryPlacement,
  );
}

/// The nine faults, by id. Each line is one row of `data/faults.json`.
///
/// This switch is the only place a fault id becomes behaviour. An id with no
/// case returns [FaultEffects.none] rather than throwing: a tuning file that
/// adds a fault should make that stage *easy*, not crash a run in progress.
FaultEffects effectsOf(String faultId) => switch (faultId) {
  // Act 1 — mild and legible. Their job is to teach what a fault IS.
  'thin_place' => const FaultEffects(allowanceScale: 0.7, targetScale: 0.75),
  'reediness' => const FaultEffects(axes: ClearAxes.colsOnly),
  'mispick' => const FaultEffects(patienceOverride: 1),

  // Act 2 — real tests. Each invalidates one archetype's main plan.
  'fixed_heddles' => const FaultEffects(rotationDisabled: true),
  'barre' => const FaultEffects(minCellCount: 4),
  'slubs' => const FaultEffects(startingKnots: 6),

  // Act 3 — the finale.
  'tight_reed' => const FaultEffects(boardSize: 7),
  'the_smash' => const FaultEffects(knotEveryNthPlacement: 3),
  'floats' => const FaultEffects(knotOnDryPlacement: true),

  _ => FaultEffects.none,
};

/// Scatter [count] knots on empty cells, drawing from the run's seeded stream.
///
/// Refuses to knot a cell that is already occupied, and gives up rather than
/// looping forever on a nearly full board — six knots on a board with four
/// holes left would otherwise hang the run.
Board scatterKnots(Board b, int count, Rng rng) {
  final empties = <int>[];
  for (var i = 0; i < b.cells.length; i++) {
    if (b.cells[i] == kEmpty) empties.add(i);
  }
  if (empties.isEmpty || count <= 0) return b;
  rng.shuffle(empties);
  final next = cloneBoard(b);
  for (var i = 0; i < count && i < empties.length; i++) {
    next.cells[empties[i]] = kKnot;
  }
  return next;
}

/// Turn one random empty cell into a knot (The Smash).
Board knotOneEmptyCell(Board b, Rng rng) => scatterKnots(b, 1, rng);

/// Turn one of a just-placed piece's own cells into a knot (Floats).
///
/// Picks from the cells that actually survived the placement — after a clear
/// that removed some of them there may be none left, in which case the board
/// is returned untouched. That is correct: Floats only punishes placements
/// that cleared nothing, and a placement that cleared nothing lost no cells.
Board knotOwnCell(Board b, ShapeCells cells, int ax, int ay, Rng rng) {
  final own = <int>[];
  for (final (cx, cy) in cells) {
    final x = ax + cx;
    final y = ay + cy;
    if (inBounds(b, x, y) && isYarn(b.cells[y * b.w + x])) {
      own.add(y * b.w + x);
    }
  }
  if (own.isEmpty) return b;
  final next = cloneBoard(b);
  next.cells[own[rng.nextInt(own.length)]] = kKnot;
  return next;
}
