/// The stage ladder — the run's spine and its second lose condition.
/// Ported from `reference/ts-core/core/run.ts`, plus the 12-stage win
/// condition from `docs/06`.
///
/// Each stage grants a placement allowance and demands a target score. Spend
/// the allowance without reaching the target and the run is over. The board
/// does **not** reset between stages, so the junk left behind by stage 3 is
/// the difficulty of stage 4 — with no timer, that carry-over is the only
/// source of escalation.
///
/// Target growth deliberately outruns allowance growth, so the player cannot
/// grind their way up the ladder: the only way to keep pace is multiplier
/// quality. Runs should end because a build capped out, not because of one bad
/// draw.
library;

import 'dart:math' as math;

import 'scoring.dart';

class CurveConfig {
  const CurveConfig({
    required this.baseTarget,
    required this.targetGrowth,
    required this.baseAllowance,
    required this.allowanceGrowth,
    this.stages = 12,
    this.scoring = ScoringConfig.defaults,
  });

  final int baseTarget;
  final double targetGrowth;
  final int baseAllowance;
  final int allowanceGrowth;

  /// 12. Three acts of four, a fault stage ending each act (docs/06).
  /// Do not extend to 13+: the curve runs away from any build the power pool
  /// can produce.
  final int stages;

  final ScoringConfig scoring;

  /// The values in `data/curve.json`, for pure-core tests and the simulation
  /// harness, which must not depend on an asset bundle.
  static const CurveConfig defaults = CurveConfig(
    baseTarget: 100,
    targetGrowth: 1.25,
    baseAllowance: 20,
    allowanceGrowth: 2,
  );

  CurveConfig copyWith({
    int? baseTarget,
    double? targetGrowth,
    int? baseAllowance,
    int? allowanceGrowth,
    int? stages,
    ScoringConfig? scoring,
  }) => CurveConfig(
    baseTarget: baseTarget ?? this.baseTarget,
    targetGrowth: targetGrowth ?? this.targetGrowth,
    baseAllowance: baseAllowance ?? this.baseAllowance,
    allowanceGrowth: allowanceGrowth ?? this.allowanceGrowth,
    stages: stages ?? this.stages,
    scoring: scoring ?? this.scoring,
  );
}

/// `placing` — in play. `stageClear` — awaiting the draft. `won` — stage 12
/// cleared. `lost` — see [LossReason].
enum RunPhase { placing, stageClear, won, lost }

/// `target` = spent the allowance while short. `jam` = no piece fits anywhere,
/// which the theme calls "the shed won't open".
enum LossReason { target, jam }

/// Everything a power or a fault can change about the ladder itself.
class LadderModifiers {
  const LadderModifiers({
    this.allowanceBonus = 0,
    this.allowanceScale = 1.0,
    this.targetScale = 1.0,
  });

  static const LadderModifiers none = LadderModifiers();

  /// Overtime (+3), Gilt Thread (−2).
  final int allowanceBonus;

  /// Thin Place: allowance ×0.7.
  final double allowanceScale;

  /// Short Bolt (−20%), Bulk Order (+15%), Thin Place (×0.75).
  final double targetScale;
}

class LadderState {
  const LadderState({
    required this.stage,
    required this.target,
    required this.stageScore,
    required this.placementsLeft,
    required this.score,
    required this.phase,
    required this.lossReason,
  });

  final int stage;
  final int target;

  /// Score earned *this stage*; resets each stage. `score.total` is the run
  /// total.
  final int stageScore;
  final int placementsLeft;
  final ScoreState score;
  final RunPhase phase;
  final LossReason? lossReason;

  bool get isOver => phase == RunPhase.lost || phase == RunPhase.won;

  LadderState copyWith({
    int? stage,
    int? target,
    int? stageScore,
    int? placementsLeft,
    ScoreState? score,
    RunPhase? phase,
    LossReason? lossReason,
    bool clearLossReason = false,
  }) => LadderState(
    stage: stage ?? this.stage,
    target: target ?? this.target,
    stageScore: stageScore ?? this.stageScore,
    placementsLeft: placementsLeft ?? this.placementsLeft,
    score: score ?? this.score,
    phase: phase ?? this.phase,
    lossReason: clearLossReason ? null : (lossReason ?? this.lossReason),
  );

  @override
  String toString() =>
      'LadderState(stage: $stage, $stageScore/$target, '
      'left: $placementsLeft, ${phase.name}'
      '${lossReason != null ? ' (${lossReason!.name})' : ''})';
}

int targetFor(
  CurveConfig cfg,
  int stage, {
  LadderModifiers mods = LadderModifiers.none,
}) {
  final raw =
      cfg.baseTarget * math.pow(cfg.targetGrowth, stage - 1) * mods.targetScale;
  return math.max(1, raw.round());
}

int allowanceFor(
  CurveConfig cfg,
  int stage, {
  LadderModifiers mods = LadderModifiers.none,
}) {
  final raw =
      (cfg.baseAllowance + cfg.allowanceGrowth * (stage - 1)) *
          mods.allowanceScale +
      mods.allowanceBonus;
  return math.max(1, raw.round());
}

LadderState startRun(
  CurveConfig cfg, {
  int shields = 0,
  LadderModifiers mods = LadderModifiers.none,
  double? multiplier,
  int? patience,
}) => LadderState(
  stage: 1,
  target: targetFor(cfg, 1, mods: mods),
  stageScore: 0,
  placementsLeft: allowanceFor(cfg, 1, mods: mods),
  score: initialScore(
    shields: shields,
    cfg: cfg.scoring,
    multiplier: multiplier,
    patience: patience,
  ),
  phase: RunPhase.placing,
  lossReason: null,
);

class PlacementOutcome {
  const PlacementOutcome({
    required this.next,
    required this.gained,
    required this.broke,
    required this.shielded,
    required this.raised,
    required this.stageCleared,
    required this.failed,
    required this.won,
  });

  final LadderState next;
  final int gained;
  final bool broke;
  final bool shielded;
  final bool raised;
  final bool stageCleared;
  final bool failed;

  /// Stage 12 cleared — the run is won, and there is no draft after it.
  final bool won;
}

/// Resolve one placement against the ladder.
///
/// Order matters: the target is checked **before** the allowance, so a
/// placement that reaches the target on the very last move clears the stage
/// rather than ending the run (spec §5.5).
PlacementOutcome applyPlacement(
  LadderState s,
  int cellsPlaced,
  int linesCleared, {
  int cellValue = 1,
  CurveConfig cfg = CurveConfig.defaults,
  TurnModifiers mods = TurnModifiers.none,
}) {
  if (s.phase != RunPhase.placing) {
    throw StateError('cannot place during phase "${s.phase.name}"');
  }

  final turn = scoreTurn(
    s.score,
    cellsPlaced,
    linesCleared,
    cellValue: cellValue,
    cfg: cfg.scoring,
    mods: mods,
  );
  final stageScore = s.stageScore + turn.gained;
  final placementsLeft = s.placementsLeft - 1;

  // Reaching the target ends the stage at once. A finish line is a finish
  // line, and forfeiting the unspent placements is the price of the clean
  // board you carry into the next stage.
  if (stageScore >= s.target) {
    final won = s.stage >= cfg.stages;
    return PlacementOutcome(
      next: s.copyWith(
        stageScore: stageScore,
        placementsLeft: placementsLeft,
        score: turn.next,
        phase: won ? RunPhase.won : RunPhase.stageClear,
      ),
      gained: turn.gained,
      broke: turn.broke,
      shielded: turn.shielded,
      raised: turn.raised,
      stageCleared: true,
      failed: false,
      won: won,
    );
  }

  if (placementsLeft <= 0) {
    return PlacementOutcome(
      next: s.copyWith(
        stageScore: stageScore,
        placementsLeft: 0,
        score: turn.next,
        phase: RunPhase.lost,
        lossReason: LossReason.target,
      ),
      gained: turn.gained,
      broke: turn.broke,
      shielded: turn.shielded,
      raised: turn.raised,
      stageCleared: false,
      failed: true,
      won: false,
    );
  }

  return PlacementOutcome(
    next: s.copyWith(
      stageScore: stageScore,
      placementsLeft: placementsLeft,
      score: turn.next,
    ),
    gained: turn.gained,
    broke: turn.broke,
    shielded: turn.shielded,
    raised: turn.raised,
    stageCleared: false,
    failed: false,
    won: false,
  );
}

/// Advance past a cleared stage.
///
/// The multiplier, patience and shields all carry over: they are the player's
/// investment, and resetting them at a stage boundary would punish finishing a
/// stage hot — exactly the play the design wants to reward. Only the allowance
/// and the stage score refresh. The board carries over too (spec §2.7), which
/// is the caller's business, not this function's.
LadderState nextStage(
  LadderState s,
  CurveConfig cfg, {
  LadderModifiers mods = LadderModifiers.none,
  int? shields,
}) {
  if (s.phase != RunPhase.stageClear) {
    throw StateError('cannot advance from phase "${s.phase.name}"');
  }
  final stage = s.stage + 1;
  return LadderState(
    stage: stage,
    target: targetFor(cfg, stage, mods: mods),
    stageScore: 0,
    placementsLeft: allowanceFor(cfg, stage, mods: mods),
    score: shields == null ? s.score : s.score.copyWith(shields: shields),
    phase: RunPhase.placing,
    lossReason: null,
  );
}

/// No rotation of any remaining tray piece fits anywhere. Terminal.
LadderState jam(LadderState s) =>
    s.copyWith(phase: RunPhase.lost, lossReason: LossReason.jam);

/// 0..1, for the target progress bar.
double stageProgress(LadderState s) =>
    s.target == 0 ? 1.0 : math.min(1.0, s.stageScore / s.target);

/// Which act a stage belongs to (1..3) — four stages each.
int actOf(int stage) => ((stage - 1) ~/ 4) + 1;

/// Fault stages sit at 4, 8 and 12: the last stage of each act.
bool isFaultStage(int stage) => stage % 4 == 0;
