/// Scoring and the combo multiplier — "rhythm" in the theme's vocabulary.
/// Ported from `reference/ts-core/core/scoring.ts`.
///
/// The multiplier is the real resource: it is built by *consecutive* scoring
/// placements and lost by going dry, which forces the player to run the board
/// hotter than is safe.
///
/// The numbers live in `data/curve.json` under `scoring` (spec §2.8). The
/// defaults on [ScoringConfig] are the same values, so pure-core tests and the
/// simulation harness need no asset bundle.
library;

import 'dart:math' as math;

class ScoringConfig {
  const ScoringConfig({
    this.lineBonusTable = const [0, 10, 25, 45, 70, 100],
    this.multStart = 1.0,
    this.multStep = 0.2,
    this.multCap = 4.0,
    this.patienceMax = 3,
  });

  /// Points for clearing n lines at once, indexed by n. Super-linear, so
  /// multi-line setups pay.
  final List<int> lineBonusTable;
  final double multStart;
  final double multStep;
  final double multCap;

  /// Dry placements tolerated before the multiplier breaks.
  ///
  /// 3 since 2026-11-11, up from 2. At 2 an under-equipped player never got
  /// near the x4.00 cap — measured median peak was x1.60 at 0% unlocks — so
  /// the ceiling was decoration. Raising it hands every player the Patience
  /// card for free, which is paid for in `targetGrowth` (docs/05 §7).
  final int patienceMax;

  static const ScoringConfig defaults = ScoringConfig();

  ScoringConfig copyWith({
    List<int>? lineBonusTable,
    double? multStart,
    double? multStep,
    double? multCap,
    int? patienceMax,
  }) => ScoringConfig(
    lineBonusTable: lineBonusTable ?? this.lineBonusTable,
    multStart: multStart ?? this.multStart,
    multStep: multStep ?? this.multStep,
    multCap: multCap ?? this.multCap,
    patienceMax: patienceMax ?? this.patienceMax,
  );

  int lineBonus(int lines) {
    final i = lines.clamp(0, lineBonusTable.length - 1);
    return lineBonusTable[i];
  }
}

class ScoreState {
  const ScoreState({
    required this.total,
    required this.multiplier,
    required this.patience,
    required this.shields,
  });

  final int total;
  final double multiplier;
  final int patience;

  /// Each shield absorbs one break instead of resetting the multiplier.
  final int shields;

  ScoreState copyWith({
    int? total,
    double? multiplier,
    int? patience,
    int? shields,
  }) => ScoreState(
    total: total ?? this.total,
    multiplier: multiplier ?? this.multiplier,
    patience: patience ?? this.patience,
    shields: shields ?? this.shields,
  );

  @override
  String toString() =>
      'ScoreState(total: $total, x${multiplier.toStringAsFixed(2)}, '
      'patience: $patience, shields: $shields)';
}

ScoreState initialScore({
  int shields = 0,
  ScoringConfig cfg = ScoringConfig.defaults,
  double? multiplier,
  int? patience,
}) => ScoreState(
  total: 0,
  multiplier: multiplier ?? cfg.multStart,
  patience: patience ?? cfg.patienceMax,
  shields: shields,
);

class TurnOutcome {
  const TurnOutcome({
    required this.next,
    required this.gained,
    required this.broke,
    required this.shielded,
    required this.raised,
  });

  final ScoreState next;
  final int gained;

  /// True when the multiplier actually reset this turn (not merely absorbed).
  final bool broke;

  /// True when a shield ate the break.
  final bool shielded;

  /// True when the multiplier rose this turn.
  final bool raised;
}

/// Everything a power can change about one turn's arithmetic.
///
/// Kept as plain data so `lib/core` stays ignorant of the power list: the
/// draft layer aggregates `data/powers.json` into one of these and hands it
/// in. See `lib/core/powers.dart`.
class TurnModifiers {
  const TurnModifiers({
    this.flatBonus = 0,
    this.extraMultOnRow = 0.0,
    this.extraMultOnCol = 0.0,
    this.doubleMultOnMultiLine = false,
    this.freeDryPlacement = false,
    this.multFloor = 0.0,
    this.breakFloor = 0.0,
    this.restoreShieldOnBigClear = false,
    this.rows = 0,
    this.cols = 0,
  });

  static const TurnModifiers none = TurnModifiers();

  /// Added to the pre-multiplier base (Doubleweave: motifs touching the board
  /// edge score +3).
  final int flatBonus;

  /// Weftwise / Warpwise: extra rhythm per row / column completed.
  final double extraMultOnRow;
  final double extraMultOnCol;

  /// Double Pick: clearing 2+ lines at once grants double rhythm.
  final bool doubleMultOnMultiLine;

  /// Temple: this dry placement does not spend patience.
  final bool freeDryPlacement;

  /// Treadle Rhythm: rhythm never falls below this.
  final double multFloor;

  /// Floating Selvage: on a break, rhythm drops to this instead of multStart.
  final double breakFloor;

  /// Mending: clearing 3+ lines at once restores one spent shield.
  final bool restoreShieldOnBigClear;

  /// How many of the cleared lines were rows / columns, for the two rhythm
  /// cards above.
  final int rows;
  final int cols;
}

/// Round half away from zero, matching JavaScript's `Math.round` for the
/// non-negative values this game produces. Dart's `num.round()` already does
/// this; the function exists to make the parity decision explicit at the one
/// place it matters.
int _jsRound(double v) => v.round();

/// Keep the multiplier on a 4-decimal grid.
///
/// The oracle does `+(m + step).toFixed(4)`, which exists so that repeated
/// 0.2 additions do not drift into 1.4000000000000001 and then fail an
/// equality check in the UI or a replay. Reproducing it is required for parity.
double _quantise(double v) => double.parse(v.toStringAsFixed(4));

/// Resolve one placement.
///
/// The **current** multiplier is applied to this turn's points, and only then
/// does a successful clear raise it — so the reward for a combo arrives on the
/// *next* turn. That delay is what makes protecting the multiplier feel like
/// an investment rather than a payout. Do not "fix" it (spec §5.4).
TurnOutcome scoreTurn(
  ScoreState s,
  int cellsPlaced,
  int linesCleared, {
  int cellValue = 1,
  ScoringConfig cfg = ScoringConfig.defaults,
  TurnModifiers mods = TurnModifiers.none,
}) {
  // Lines are where points come from. A placement pays only what the yarn
  // family gives it, and `cellValue` starts at **zero** — see
  // `PowerSet.cellValueFor`.
  final base =
      cellsPlaced * cellValue + cfg.lineBonus(linesCleared) + mods.flatBonus;
  final gained = _jsRound(base * s.multiplier);
  final total = s.total + gained;

  if (linesCleared > 0) {
    var step = cfg.multStep +
        mods.extraMultOnRow * mods.rows +
        mods.extraMultOnCol * mods.cols;
    if (mods.doubleMultOnMultiLine && linesCleared >= 2) step *= 2;

    var shields = s.shields;
    if (mods.restoreShieldOnBigClear && linesCleared >= 3) shields += 1;

    return TurnOutcome(
      next: ScoreState(
        total: total,
        multiplier: math.min(cfg.multCap, _quantise(s.multiplier + step)),
        patience: cfg.patienceMax,
        shields: shields,
      ),
      gained: gained,
      broke: false,
      shielded: false,
      raised: true,
    );
  }

  // Temple: the first dry placement each stage costs no patience.
  if (mods.freeDryPlacement) {
    return TurnOutcome(
      next: s.copyWith(total: total),
      gained: gained,
      broke: false,
      shielded: false,
      raised: false,
    );
  }

  final patience = s.patience - 1;
  if (patience > 0) {
    return TurnOutcome(
      next: ScoreState(
        total: total,
        multiplier: s.multiplier,
        patience: patience,
        shields: s.shields,
      ),
      gained: gained,
      broke: false,
      shielded: false,
      raised: false,
    );
  }

  if (s.shields > 0) {
    return TurnOutcome(
      next: ScoreState(
        total: total,
        multiplier: s.multiplier,
        patience: cfg.patienceMax,
        shields: s.shields - 1,
      ),
      gained: gained,
      broke: false,
      shielded: true,
      raised: false,
    );
  }

  final broken = math.max(
    math.max(mods.breakFloor, mods.multFloor),
    cfg.multStart,
  );
  return TurnOutcome(
    next: ScoreState(
      total: total,
      multiplier: math.min(cfg.multCap, broken),
      patience: cfg.patienceMax,
      shields: 0,
    ),
    gained: gained,
    broke: true,
    shielded: false,
    raised: false,
  );
}
