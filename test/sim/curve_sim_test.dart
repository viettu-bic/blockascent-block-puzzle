import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/bag.dart';
import 'package:loomcraft/core/board.dart';
import 'package:loomcraft/core/rng.dart';
import 'package:loomcraft/core/scoring.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';

import 'greedy.dart';

/// **Gate #2: port parity** (spec §10).
///
/// Ported from `reference/ts-tests/curve.sim.test.ts`. A greedy auto-player
/// plays 120 seeded runs; the exit criterion is that the Dart simulation
/// reproduces the TypeScript histogram from the same seeds — with the current
/// curve, a median of stage 6, a median run total near 1,118, and 0% jam
/// deaths.
///
/// Without this check, a subtle difference in the RNG or in rounding changes
/// the game silently and nobody notices for a month.
///
/// ## Why the ladder is unbounded here
///
/// The oracle predates the 12-stage win condition, so its ladder runs until
/// the player dies. To keep the histogram directly comparable this harness
/// plays [unbounded]. The final test in this file then replays the same seeds
/// on the real 12-stage curve and asserts the two agree — i.e. that the win
/// cap never binds for a floor player, which is also the docs/06 §3 claim that
/// a 0%-unlock run is unwinnable.
void main() {
  const runs = 120;
  const traySlots = 3;

  /// The curve the **oracle** played: `data/curve.json` with the 12-stage cap
  /// lifted, and `patienceMax` pinned back to 2.
  ///
  /// Patience went to 3 on 2026-11-11 (docs/05 §7). The TypeScript oracle in
  /// `reference/` predates that and will never be re-run, so comparing against
  /// it means playing the rules it played. This gate exists to catch a silent
  /// RNG or rounding difference in the **engine** — pinning a tuning value it
  /// was measured at is what keeps it answering that question instead of
  /// re-answering "did someone change the tuning", which the gates test does
  /// deliberately and loudly.
  /// Every tuning value is pinned here rather than inherited from
  /// `CurveConfig.defaults`. Inheriting is what broke this gate the first time
  /// the curve was re-steepened: the oracle played x1.25 with patience 2, so
  /// reading the live numbers made the parity check compare two different
  /// games and report an engine fault that did not exist.
  final oracleScoring = ScoringConfig.defaults.copyWith(patienceMax: 2);
  final oracleCurve = CurveConfig(
    baseTarget: 100,
    targetGrowth: 1.25,
    baseAllowance: 20,
    allowanceGrowth: 2,
    scoring: oracleScoring,
  );
  final unbounded = oracleCurve.copyWith(stages: 1 << 30);

  /// The eleven motifs the oracle drew from, pinned by id.
  ///
  /// It used to read `spikeLoadout`, which is `tier1 + tier2` — and the roster
  /// inverted on 2026-11-11, so that list is now nine different motifs. Same
  /// lesson as pinning the curve above: a parity gate has to play the rules
  /// the oracle played, or it reports an engine fault every time the design
  /// moves.
  final oracleLoadout = [
    for (final id in [
      'dot', 'i2', 'i3', 'o2', 'l3', 'i4', 't4', 's4', 'z4', 'j4', 'l4',
    ])
      shape(id),
  ];

  RunReport playOne(int seed, CurveConfig cfg) {
    final rng = Rng(seed);
    final bag = Bag(oracleLoadout, rng);
    var board = createBoard();
    var tray = <TrayItem?>[];
    var ladder = startRun(cfg);
    var placements = 0;
    var lines = 0;
    var peakMultiplier = 1.0;

    void refill() {
      tray = [
        for (var i = 0; i < traySlots; i++) TrayItem(bag.draw().id, 0),
      ];
    }

    refill();

    // Hard cap: a bug that makes the ladder unloseable must fail the test, not
    // hang it.
    for (var guard = 0; guard < 5000; guard++) {
      final move = bestMove(board, tray);
      if (move == null) {
        ladder = jam(ladder);
        break;
      }

      final result = resolvePlacement(
        board,
        move.cells,
        move.ax,
        move.ay,
        move.cells.length,
      );
      board = result.board;
      tray[move.slot] = null;
      placements++;

      final outcome = applyPlacement(
        ladder,
        move.cells.length,
        result.lines,
        cfg: cfg,
      );
      ladder = outcome.next;
      lines += result.lines;
      if (ladder.score.multiplier > peakMultiplier) {
        peakMultiplier = ladder.score.multiplier;
      }

      if (shouldRefill(tray)) refill();
      if (outcome.failed) break;
      if (outcome.won) break;
      if (outcome.stageCleared) ladder = nextStage(ladder, cfg);
    }

    return RunReport(
      stage: ladder.stage,
      total: ladder.score.total,
      placements: placements,
      reason: ladder.lossReason ?? LossReason.target,
      won: ladder.phase == RunPhase.won,
      lastStageScore: ladder.stageScore,
      lastTarget: ladder.target,
      lines: lines,
      peakMultiplier: peakMultiplier,
    );
  }

  late List<RunReport> reports;
  late List<int> stages;

  setUpAll(() {
    reports = [for (var i = 1; i <= runs; i++) playOne(i, unbounded)];
    stages = [for (final r in reports) r.stage]..sort();
  });

  test('reproduces the TypeScript histogram from the same seeds', () {
    final jams = reports.where((r) => r.reason == LossReason.jam).length;
    final totals = [for (final r in reports) r.total]..sort();
    final placements = [for (final r in reports) r.placements]..sort();
    final peaks = [for (final r in reports) r.peakMultiplier]..sort();
    final lineCounts = [for (final r in reports) r.lines]..sort();

    final histogram = <int, int>{};
    for (final s in stages) {
      histogram[s] = (histogram[s] ?? 0) + 1;
    }

    // ignore: avoid_print
    print([
      '',
      'curve: target ${unbounded.baseTarget} x${unbounded.targetGrowth}  '
          'allowance ${unbounded.baseAllowance} +${unbounded.allowanceGrowth}',
      '$runs greedy runs — stage reached:',
      '  p10 ${_q(stages, 0.1)}  median ${_q(stages, 0.5)}  '
          'p90 ${_q(stages, 0.9)}  max ${stages.last}',
      '  died to target ${runs - jams}  ·  died to jam $jams',
      for (final e in (histogram.entries.toList()
            ..sort((a, b) => a.key - b.key)))
        '  stage ${e.key.toString().padLeft(2)}  ${'#' * e.value} ${e.value}',
      '  median placements ${_q(placements, 0.5)}',
      '  score reached in the stage that killed the run:',
      '    p10 ${_q([for (final r in reports) r.lastStageScore]..sort(), 0.1)}'
          '  median ${_q([for (final r in reports) r.lastStageScore]..sort(), 0.5)}'
          '  p90 ${_q([for (final r in reports) r.lastStageScore]..sort(), 0.9)}',
      '  run total (drives the economy — see docs/04):',
      '    p10 ${_q(totals, 0.1)}  median ${_q(totals, 0.5)}  '
          'p90 ${_q(totals, 0.9)}',
      '  median lines cleared ${_q(lineCounts, 0.5)}',
      '  median peak multiplier ${_q(peaks, 0.5).toStringAsFixed(2)}',
      '',
    ].join('\n'));

    // ---- The parity gate: the documented TypeScript result, pinned. -------
    // README and spec §10: median stage 6, median run total ~1,118, 0% jams.
    expect(_q(stages, 0.5), 6, reason: 'median stage must match the oracle');
    expect(_q(totals, 0.5), closeTo(1118, 60), reason: 'median run total');
    expect(
      reports.where((r) => r.reason == LossReason.jam),
      isEmpty,
      reason: 'the oracle reports 0% jam deaths on this curve',
    );
    expect(_q(placements, 0.5), closeTo(124, 12), reason: 'docs/04 anchor');
    // docs/05 §1: "the floor player's rhythm peaks at only x2.0 because it
    // keeps breaking". Measured here as exactly 2.00.
    //
    // NOTE a documentation conflict: `data/curve.json`'s `_evidence` note says
    // the greedy player "peaks at x1.60". That number does not reproduce — not
    // in this port and, since every other figure in the same note matches to
    // the unit (median stage 6, median total 1,118, 124 placements), not in
    // the oracle either. Treat the curve.json note as stale and docs/05 as
    // correct; it is a comment, so nothing reads it at runtime.
    expect(_q(peaks, 0.5), closeTo(2.0, 1e-9));

    // ---- The oracle's own assertions, ported verbatim. --------------------
    expect(reports, hasLength(runs));
    expect(stages.every((s) => s >= 1), isTrue);

    // Falling short of the target is the designed death. If much of the field
    // dies to a jam instead, the targets are too soft and the board is doing
    // the work the curve should be doing.
    expect(jams, lessThan(runs * 0.5));

    // Nobody should lose on stage 1. It is the tutorial stage and a floor
    // player clears it with ~60% headroom.
    expect(stages.first, greaterThanOrEqualTo(2));

    // ...but a player with no build should not run away with the ladder
    // either. This greedy has no lookahead, so a human should do better.
    expect(_q(stages, 0.5), greaterThanOrEqualTo(4));
    expect(_q(stages, 0.5), lessThanOrEqualTo(8));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('the same seed replays identically — determinism is load-bearing', () {
    // Daily challenges, shareable runs and server-verifiable scores all rest
    // on this. If it ever fails, something has reached for a clock or a
    // hash-ordered collection.
    final a = playOne(77, unbounded);
    final b = playOne(77, unbounded);
    expect(a.stage, b.stage);
    expect(a.total, b.total);
    expect(a.placements, b.placements);
    expect(a.lines, b.lines);
  });

  test('a 0%-unlock floor player cannot win, so the win cap never binds', () {
    // docs/06 §3: at 0% unlocks the campaign must be unwinnable. That is also
    // what makes the histogram above comparable to the oracle's unbounded
    // ladder — if a greedy run ever reached stage 12 the two would diverge on
    // the tail, and this test is the tripwire for that.
    expect(stages.last, lessThan(12));
    final capped = [for (var i = 1; i <= runs; i++) playOne(i, oracleCurve)];
    expect(capped.where((r) => r.won), isEmpty);
    for (var i = 0; i < runs; i++) {
      expect(capped[i].stage, reports[i].stage, reason: 'seed ${i + 1}');
      expect(capped[i].total, reports[i].total, reason: 'seed ${i + 1}');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

class RunReport {
  const RunReport({
    required this.stage,
    required this.total,
    required this.placements,
    required this.reason,
    required this.won,
    required this.lastStageScore,
    required this.lastTarget,
    required this.lines,
    required this.peakMultiplier,
  });

  final int stage;
  final int total;
  final int placements;
  final LossReason reason;
  final bool won;

  /// Score reached in the stage that killed the run, and the target it missed.
  final int lastStageScore;
  final int lastTarget;
  final int lines;
  final double peakMultiplier;
}

T _q<T>(List<T> sorted, double q) =>
    sorted[(sorted.length * q).floor().clamp(0, sorted.length - 1)];
