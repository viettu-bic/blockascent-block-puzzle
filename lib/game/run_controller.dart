/// The run controller: the one impure place where the pure rules engine, the
/// draft, the faults and persistence meet.
///
/// `lib/core` is a seeded state machine that knows nothing about any of this.
/// This file owns the *sequencing* — whose turn it is, which screen is up,
/// when to save — and delegates every rule to core. If a rule is implemented
/// here rather than there, it cannot be simulated, replayed or verified, so
/// the test for whether code belongs in this file is: "is it about order, or
/// about arithmetic?"
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/bag.dart';
import '../core/board.dart';
import '../core/faults.dart';
import '../core/powers.dart';
import '../core/rng.dart';
import '../core/run.dart';
import '../core/scoring.dart';
import '../core/shapes.dart';
import '../core/types.dart';
import '../data/tuning.dart';
import '../platform/haptics.dart';
import '../platform/sfx.dart';
import '../platform/storage.dart';
import 'account.dart';

/// What the player is being asked for right now.
enum GamePhase {
  /// The act's three faults are announced when the act begins, so the player
  /// can draft toward the one they chose (`faults.json._placement`).
  faultChoice,

  placing,

  /// Clearing a stage lets you draft one of three.
  draft,

  /// A picked card needs a motif named (Slub Yarn, Cull, Favour).
  motifChoice,

  lost,
  won,
}

/// A tool awaiting a target on the board.
enum ToolAim { none, unpick, shears, battenRow, battenCol }

const int baseTraySlots = 3;

/// One line of the run log, shown on the summary screen.
class RunEvent {
  const RunEvent(this.stage, this.text);
  final int stage;
  final String text;
}

class RunController extends ChangeNotifier {
  RunController({
    required this.tuning,
    required this.account,
    required this.storage,
    required this.haptics,
    Sfx? sfx,
    int Function()? seedSource,
  })  : sfx = sfx ?? Sfx(enabled: false),
        _seedSource = seedSource ?? randomSeed;

  final Tuning tuning;
  final Account account;
  final Storage storage;
  final Haptics haptics;

  /// Defaults to a **silent** instance, so a test or a tool that does not pass
  /// one never constructs an `AudioPlayer` and never reaches a platform
  /// channel (see `Sfx`).
  final Sfx sfx;
  final int Function() _seedSource;

  /* ---------------- run state ---------------- */

  late int seed;
  late Rng _rng;
  late Bag _bag;
  late Board board;
  late LadderState ladder;
  late PowerSet powers;

  /// The tray. Length is [slotCount]; [holdItem] is deliberately not part of
  /// it, because the refill rule must not see it.
  List<TrayItem?> tray = [];
  TrayItem? holdItem;

  GamePhase phase = GamePhase.faultChoice;

  /// The fault chosen for the current act, and the one in force right now.
  final Map<int, String> chosenFaultByAct = {};
  FaultEffects faultEffects = FaultEffects.none;
  FaultDef? activeFault;

  /// **All** of the act's faults, including the ones that cannot be chosen
  /// yet — those are in [lockedFaultIds].
  ///
  /// They used to be filtered out entirely, so a player had no idea the harder
  /// ones existed. Showing a locked option greyed out is the whole point of
  /// having a ladder: it is a thing to work toward rather than a surprise two
  /// runs later (docs/06 §6a).
  List<FaultDef> faultOptions = [];

  /// Fault ids shown but not selectable.
  Set<String> lockedFaultIds = {};
  List<PowerDef> draftOptions = [];
  PowerDef? pendingMotifCard;

  final Map<String, int> toolCharges = {};
  int battenCharges = 0;
  ToolAim aiming = ToolAim.none;

  /// Bumped every time a patience pip is spent, and every time the combo
  /// actually breaks.
  ///
  /// Ticks rather than values, because the HUD has to animate the *event* and
  /// both numbers also move at a stage boundary, where nothing was lost. The
  /// combo break was previously announced by nothing but the hero number
  /// reading smaller the next time the player happened to look at it
  /// (UX review 4.3).
  int patienceLossTick = 0;
  int comboBreakTick = 0;

  /// The empty cells on a board that has jammed.
  ///
  /// A jam is 43% of early deaths and the loss screen named neither the rule
  /// nor the place: "No moves left" over a hidden board. These are painted
  /// warn-coloured for two seconds before the summary, which is the one moment
  /// the player actively wants to know why (UX review 5).
  List<Coord> jamCells = const [];

  /// The very first run on this install, which is arranged to teach rather
  /// than to be fair — see [_arrangeOpeningLesson].
  bool _tutorialRun = false;
  bool get tutorialRun => _tutorialRun;

  /// Where the opening block goes on that first run. Cleared by the first
  /// placement, whether or not the player took the hint.
  ({int slot, Anchor anchor})? openingHint;


  int _placementsThisStage = 0;
  int _stagesCleared = 0;
  int _spoolsEarned = 0;
  bool _templeSpentThisStage = false;
  bool _firstRunOfDay = false;

  /// The milestones the **draft pool** is built from, snapshotted at
  /// [begin] and held for the whole run.
  ///
  /// Reading `account.milestones` live made milestone cards unlock *mid-run*:
  /// clearing stage 7 put Second Shuttle into the very next draft of the run
  /// that earned it. Measured, a 0%-unlock account was drafting Treadle
  /// Rhythm, Batten and Second Shuttle — so "0% unlocks" did not mean the
  /// initial twelve, it meant most of the pool as soon as a run went deep.
  ///
  /// Two reasons that is wrong, and the second is the design one:
  ///
  /// - It is a snowball. The strongest cards arrive exactly when the player is
  ///   already winning, which widens the gap a run is meant to close.
  /// - A run's pool should be knowable at the start. docs/06 §6 makes this
  ///   argument for faults — a constraint you can see four stages out is
  ///   something you draft toward, one sprung on you is something that happens
  ///   to you — and a card pool is the same claim about the same player.
  ///
  /// Milestones earned during a run are still recorded on the account; they
  /// simply take effect from the **next** run.
  late Milestones _poolMilestones;
  final List<RunEvent> log = [];

  /// The lines the last placement cleared, and a counter that changes on
  /// every placement. The renderer watches the counter rather than diffing the
  /// board, so a placement that clears nothing still ends the previous flash.
  Clears lastClears = const Clears.none();
  int placementTick = 0;

  /// Absolute board coordinates of the cells the last placement landed on, for
  /// the settle animation. Cells a clear then removed are included: the
  /// renderer skips whatever is no longer filled, which is cheaper than
  /// recomputing the survivors here.
  List<Coord> lastPlacedCells = const [];

  /// Set when the run ends, so the summary can show what the death paid.
  int get spoolsEarned => _spoolsEarned;
  int get stagesCleared => _stagesCleared;
  bool get firstRunOfDay => _firstRunOfDay;
  List<Shape> get nextRefillPeek =>
      powers.seesNextRefill ? _bag.peek(slotCount) : const [];

  /// The motifs actually in this run's bag right now.
  ///
  /// NOT the account's loadout: Cull removes motifs from the bag for the rest
  /// of the run and Favour adds duplicates, so a chooser built from the
  /// account would offer a motif that is no longer there — and Favour on a
  /// culled motif is an error, not a no-op.
  List<Shape> get bagLoadout {
    final seen = <String>{};
    return [
      for (final s in _bag.loadout)
        if (seen.add(s.id)) s,
    ];
  }

  /* ---------------- derived ---------------- */

  int get slotCount =>
      baseTraySlots + powers.extraTraySlots + account.extraTraySlots;

  int get boardSize => faultEffects.boardSize ?? defaultSize;

  ScoringConfig get scoring =>
      faultEffects.applyTo(powers.applyTo(tuning.curve.scoring));

  CurveConfig get curve => tuning.curve.copyWith(scoring: scoring);

  LadderModifiers get ladderMods {
    final p = powers.ladderModifiers;
    final f = faultEffects.ladderModifiers;
    return LadderModifiers(
      // Every stage, not just the first: see Account.openingAllowanceBonus.
      allowanceBonus: p.allowanceBonus + account.openingAllowanceBonus,
      allowanceScale: f.allowanceScale,
      targetScale: p.targetScale * f.targetScale,
    );
  }

  bool get rotationDisabled =>
      faultEffects.rotationDisabled || account.hasUpgrade('classicMode');

  /// Every shape still sitting in the tray or the hold slot, for the jam check.
  List<Shape> get _liveShapes => [
    for (final item in [...tray, holdItem])
      if (item != null) shape(item.shapeId),
  ];

  List<int> get _liveRotations => [
    for (final item in [...tray, holdItem])
      if (item != null) item.rotation,
  ];

  /* ---------------- starting and restoring ---------------- */

  /// Start a fresh run.
  ///
  /// Named `begin` rather than `startRun` so it cannot shadow core's
  /// `startRun()` at the one call site that needs the real thing.
  void begin({int? withSeed}) {
    seed = withSeed ?? _seedSource();
    _rng = Rng(seed);
    powers = PowerSet(const [], yarn: account.yarnUpgrades);
    _bag = Bag(account.loadoutShapes(), _rng);
    board = createBoard();
    tray = List<TrayItem?>.filled(baseTraySlots, null);
    holdItem = null;
    chosenFaultByAct.clear();
    toolCharges.clear();
    battenCharges = 0;
    aiming = ToolAim.none;
    _templeSpentThisStage = false;
    _placementsThisStage = 0;
    _stagesCleared = 0;
    _spoolsEarned = 0;
    draftOptions = [];
    pendingMotifCard = null;
    jamCells = const [];
    openingHint = null;
    log.clear();

    // Before `runsStarted` is incremented below: this is the first run this
    // install has ever started.
    _tutorialRun = account.runsStarted == 0;

    // The draft pool is fixed for the whole run: see [_poolMilestones].
    _poolMilestones = account.milestones;

    // The daily bonus is *earned by finishing*, not by starting. Writing
    // `lastPlayedDay` here meant an abandoned or restarted run spent the
    // bonus before a single placement, so the run the player thought was
    // their first paid 35 spools instead of 135. It is committed in
    // [_endRun] instead (docs/04 §7).
    _firstRunOfDay = account.lastPlayedDay != _today();
    account.runsStarted++;

    ladder = _freshLadder();
    _offerFaultsForAct(1);
    notifyListeners();
    _save();
  }

  LadderState _freshLadder() {
    // The fault for stage 4 is not chosen yet, so stage 1's numbers use the
    // powers-only modifiers. Faults never touch a stage other than their own.
    return startRun(
      curve,
      shields: account.openingShields + powers.shieldsPerStage,
      mods: LadderModifiers(
        allowanceBonus: account.openingAllowanceBonus,
      ),
      multiplier: account.openingMultiplier,
    );
  }

  /// Announce the act's **unlocked** faults. The player picks one now and it
  /// lands on the act's last stage, so there is time to draft toward it.
  ///
  /// A fresh account sees only tier 1; clearing it opens tier 2, and so on
  /// ([unlockedFaults]). So this is one option on a first run and grows to
  /// three — which is why nothing here may assume a length of 3.
  void _offerFaultsForAct(int act) {
    final a = tuning.faults.acts.firstWhere(
      (x) => x.act == act,
      orElse: () => tuning.faults.acts.last,
    );
    final unlocked =
        unlockedFaults(a, account.faultsCleared).map((f) => f.id).toSet();
    faultOptions = a.faults;
    lockedFaultIds = {
      for (final f in a.faults)
        if (!unlocked.contains(f.id)) f.id,
    };
    phase = GamePhase.faultChoice;

    // A screen with one answer is not a question (UX review 3.1).
    //
    // On a fresh account exactly one fault per act is unlocked, so the first
    // thing the game ever asked — before a single block had been placed —
    // was which of three defects the player wanted on level 4, with two of the
    // three greyed out. This skips straight into the level and takes the one
    // option; the screen comes back the moment there is genuinely something to
    // choose between.
    //
    // This does not narrow anything (invariant 5): the locked options are
    // locked either way, and the player still meets the chosen fault on the
    // act's last level. What it removes is the asking.
    final selectable = [
      for (final f in a.faults)
        if (!lockedFaultIds.contains(f.id)) f.id,
    ];
    if (selectable.length == 1) _takeFault(selectable.single);
  }

  /// Bank the fault just beaten, which is what opens the next tier.
  ///
  /// Called from both the stage-clear and the win paths: stage 12 *is* an act-3
  /// fault stage, so a winning run would otherwise never record the hardest
  /// fault it cleared.
  void _recordFaultCleared() {
    final id = activeFault?.id;
    if (id != null) account.faultsCleared.add(id);
  }

  /// The fault that has to be cleared before [id] can be chosen, or null when
  /// [id] is already available.
  FaultDef? unlockedBy(String id) {
    final a = tuning.faults.acts.firstWhere(
      (x) => x.faults.any((f) => f.id == id),
      orElse: () => tuning.faults.acts.first,
    );
    return faultUnlockedBy(a, id);
  }

  void chooseFault(String faultId) {
    // Nothing to choose unless the game is asking. Without this, a caller that
    // chooses unconditionally after `begin` would restart stage 1 on the runs
    // where the sole option was taken automatically.
    if (phase != GamePhase.faultChoice) return;
    // A locked option is shown, so it can be tapped — refuse it here rather
    // than trusting the overlay to disable it.
    if (lockedFaultIds.contains(faultId)) return;
    _takeFault(faultId);
    notifyListeners();
    _save();
  }

  /// Commit a fault and start the act's levels. Shared by the player's choice
  /// and by the sole-option case, so the two cannot drift.
  void _takeFault(String faultId) {
    final act = actOf(ladder.stage);
    chosenFaultByAct[act] = faultId;
    faultOptions = [];
    lockedFaultIds = {};
    phase = GamePhase.placing;
    _beginStage();
  }

  /* ---------------- the stage ---------------- */

  /// Apply whatever the new stage needs before the first placement: the
  /// fault, if this is a fault stage, then the tray.
  void _beginStage() {
    _templeSpentThisStage = false;
    _placementsThisStage = 0;

    final faultId = chosenFaultByAct[actOf(ladder.stage)];
    if (isFaultStage(ladder.stage) && faultId != null) {
      activeFault = tuning.faults.byId(faultId);
      faultEffects = effectsOf(faultId);
      log.add(RunEvent(ladder.stage, 'Challenge: ${activeFault!.name}'));

      if (faultEffects.boardSize != null) {
        board = resizeBoard(
          board,
          faultEffects.boardSize!,
          faultEffects.boardSize!,
        );
      }
      if (faultEffects.startingKnots > 0) {
        board = scatterKnots(board, faultEffects.startingKnots, _rng);
      }
    } else {
      activeFault = null;
      faultEffects = FaultEffects.none;
      if (board.w != defaultSize) {
        // The cloth widens again once the reed is loosened. Cells lost to
        // Tight Reed stay lost; the board does not reset (spec §2.7).
        board = resizeBoard(board, defaultSize, defaultSize);
      }
    }

    // Recompute the stage's own numbers now that the fault — or its absence —
    // is known.
    //
    // This has to run on EVERY stage, not just a fault stage. `_advanceStage`
    // computes the target and allowance while the *previous* stage's fault is
    // still in force, so without this the stage after a fault inherits its
    // scaling: stage 5 would silently keep Thin Place's x0.7 allowance.
    ladder = ladder.copyWith(
      target: targetFor(curve, ladder.stage, mods: ladderMods),
      placementsLeft: allowanceFor(curve, ladder.stage, mods: ladderMods),
    );

    // Tool charges refresh per stage; Batten is per run and is set at pick
    // time instead.
    for (final id in ['unpick', 'rethread', 'shears', 'resley']) {
      final n = powers.chargesPerStage(id) +
          (account.toolChargesPerStage[id] ?? 0);
      if (n > 0) toolCharges[id] = n;
    }

    // Selvage refills at each stage start.
    final refillShields = account.openingShields + powers.shieldsPerStage;
    if (refillShields > ladder.score.shields) {
      ladder = ladder.copyWith(
        score: ladder.score.copyWith(shields: refillShields),
      );
    }

    // Combo Floor: every stage opens at the bought multiplier or better, so a
    // break does not follow the player across a stage boundary. Carried here
    // rather than only into `startRun`, which is what makes it a change to how
    // a run feels instead of a one-off number (Account.openingMultiplier).
    final floor = account.openingMultiplier;
    if (floor != null && ladder.score.multiplier < floor) {
      ladder = ladder.copyWith(
        score: ladder.score.copyWith(multiplier: floor),
      );
    }

    _ensureTray();
    if (_tutorialRun && ladder.stage == 1) _arrangeOpeningLesson();
    _checkJam();
  }

  /// Arrange level 1 of the very first run so the opening move clears a
  /// column.
  ///
  /// **This replaces the tutorial page that used to open itself** (UX review
  /// 1.1). That page was ~200 words with its button below the fold, shown to
  /// someone who had not yet seen a board, and the rule it most needed to
  /// teach — both axes clear — is one a player can simply be shown. So
  /// column 0 starts filled except for the cells the first tray block covers,
  /// and [openingHint] says where it goes.
  ///
  /// Only ever on the first run, and only on level 1: a pre-filled board is a
  /// head start, and a head start the player keeps getting is a different
  /// game. The filled cells score nothing themselves (placing never does),
  /// so what the player banks is one line bonus at x1.00 — the same thing
  /// they would have got by finding the move on their own.
  ///
  /// Deterministic, not random: it reads the tray the seed already produced
  /// and fills around it, so the run stays replayable from its seed.
  void _arrangeOpeningLesson() {
    final slot = tray.indexWhere((t) => t != null);
    if (slot < 0) return;
    final item = tray[slot]!;
    final cells = cellsOf(item.shapeId, item.rotation);
    final e = extent(cells);
    if (e.w > board.w || e.h > board.h) return;

    // Bottom-left, which is where a thumb already is.
    final ax = 0;
    final ay = board.h - e.h;

    // The rows of column 0 the block itself will cover.
    final covered = {
      for (final (cx, cy) in cells)
        if (cx == 0) ay + cy,
    };
    if (covered.isEmpty) return;

    var b = board;
    for (var y = 0; y < board.h; y++) {
      if (covered.contains(y)) continue;
      // Two sizes rather than one, so the column reads as cloth somebody wove
      // rather than as a painted stripe.
      b = setCell(b, 0, y, y.isEven ? 3 : 4);
    }
    board = b;

    // Only claim the hint if the move is actually legal — a shape whose
    // left column is not contiguous could still collide.
    if (fits(board, cells, ax, ay)) {
      openingHint = (slot: slot, anchor: Anchor(ax, ay));
    } else {
      board = createBoard(board.w, board.h);
    }
  }

  /// Refill only when **all** slots are empty. This single rule is where the
  /// difficulty lives (spec §2.1).
  void _ensureTray() {
    if (tray.length != slotCount) {
      final old = tray;
      tray = List<TrayItem?>.filled(slotCount, null);
      for (var i = 0; i < old.length && i < slotCount; i++) {
        tray[i] = old[i];
      }
    }
    if (!shouldRefill(tray)) return;
    _refill();
  }

  void _refill() {
    final drawn = <Shape>[];
    for (var i = 0; i < slotCount; i++) {
      drawn.add(_drawOne());
    }

    // Small Hands: every refill contains at least one motif of 3 cells or
    // fewer. Swaps the largest for a small one rather than redrawing, so the
    // guarantee costs no extra RNG draws and stays replayable.
    if ((powers.guaranteesSmallMotif || account.guaranteesSmallMotif) &&
        !drawn.any((s) => s.cellCount <= 3)) {
      final small = _bag.drawWhere((s) => s.cellCount <= 3);
      if (small != null) {
        var worst = 0;
        for (var i = 1; i < drawn.length; i++) {
          if (drawn[i].cellCount > drawn[worst].cellCount) worst = i;
        }
        drawn[worst] = small;
      }
    }

    for (var i = 0; i < slotCount; i++) {
      tray[i] = TrayItem(drawn[i].id, 0);
    }
  }

  Shape _drawOne() {
    final min = faultEffects.minCellCount;
    if (min != null) {
      // Barré: the bag serves only motifs of 4 cells or more. A loadout that
      // cannot comply falls back to an ordinary draw rather than jamming.
      final s = _bag.drawWhere((s) => s.cellCount >= min);
      if (s != null) return s;
    }
    return _bag.draw();
  }

  void _checkJam() {
    if (phase != GamePhase.placing) return;
    if (hasAnyLegalMove(
      board,
      _liveShapes,
      allowRotation: !rotationDisabled,
      rotations: _liveRotations,
    )) {
      return;
    }
    // "The shed won't open" — nothing can pass.
    //
    // Name the gaps before the summary covers them. Every empty cell on a
    // jammed board is, by definition, one no block fits, so there is no
    // heuristic here to be wrong about.
    jamCells = [
      for (var y = 0; y < board.h; y++)
        for (var x = 0; x < board.w; x++)
          if (cellAt(board, x, y) == kEmpty) (x, y),
    ];
    account.jamsSeen++;
    ladder = jam(ladder);
    _endRun();
  }

  /* ---------------- placement ---------------- */

  bool canPlace(TrayItem item, Anchor a) =>
      fits(board, cellsOf(item.shapeId, item.rotation), a.x, a.y);

  Clears previewFor(TrayItem item, Anchor a) => previewClears(
    board,
    cellsOf(item.shapeId, item.rotation),
    a.x,
    a.y,
    axes: faultEffects.axes,
  );

  /// Rotate a tray (or hold) slot one step forward through its distinct
  /// rotations. Tap-only (spec §7.6).
  void rotate(int slot) {
    if (rotationDisabled) {
      haptics.invalid();
      sfx.invalid();
      return;
    }
    final item = _itemAt(slot);
    if (item == null) return;
    _setItem(slot, item.withRotation(nextRotation(item.shapeId, item.rotation)));
    haptics.snap();
    sfx.snap();
    notifyListeners();
  }

  TrayItem? _itemAt(int slot) =>
      slot >= tray.length ? holdItem : tray[slot];

  void _setItem(int slot, TrayItem? item) {
    if (slot >= tray.length) {
      holdItem = item;
    } else {
      tray[slot] = item;
    }
  }

  /// Commit a placement. Returns false when nothing happened, in which case
  /// **the piece is not consumed** (spec §2.6).
  bool place(int slot, Anchor a) {
    if (phase != GamePhase.placing) return false;
    final item = _itemAt(slot);
    if (item == null) return false;
    final cells = cellsOf(item.shapeId, item.rotation);
    if (!fits(board, cells, a.x, a.y)) {
      haptics.invalid();
      sfx.invalid();
      return false;
    }

    final s = shape(item.shapeId);
    final result = resolvePlacement(
      board,
      cells,
      a.x,
      a.y,
      s.cellCount,
      axes: faultEffects.axes,
    );
    board = result.board;
    _setItem(slot, null);
    _placementsThisStage++;
    lastClears = result.clears;
    lastPlacedCells = [for (final (cx, cy) in cells) (a.x + cx, a.y + cy)];
    placementTick++;

    final mods = powers.turnModifiers(
      rows: result.clears.rows.length,
      cols: result.clears.cols.length,
      touchesEdge: placementTouchesEdge(cells, a.x, a.y, boardSize, boardSize),
      freeDryPlacement: result.lines == 0 && !_templeSpentThisStage,
    );
    if (mods.freeDryPlacement) _templeSpentThisStage = true;

    final patienceBefore = ladder.score.patience;
    final outcome = applyPlacement(
      ladder,
      s.cellCount,
      result.lines,
      cellValue: powers.cellValueFor(s.cellCount, s.id),
      cfg: curve,
      mods: mods,
    );
    ladder = outcome.next;
    if (ladder.score.patience < patienceBefore) patienceLossTick++;
    if (outcome.broke) comboBreakTick++;

    // The lesson is over the moment the player places anything, taken or not.
    openingHint = null;

    _applyKnotFaults(result, cells, a);
    _recordMilestones(result, outcome);

    if (result.lines > 0) {
      haptics.lineClear();
      sfx.lineClear(result.lines);
    } else {
      haptics.place();
      sfx.place();
    }
    if (outcome.broke) {
      haptics.multiplierBreak();
      sfx.multiplierBreak();
    }

    if (outcome.won) {
      _onWin();
    } else if (outcome.stageCleared) {
      _onStageCleared();
    } else if (outcome.failed) {
      log.add(RunEvent(ladder.stage, 'Out of moves'));
      _endRun();
    } else {
      _ensureTray();
      _checkJam();
    }

    notifyListeners();
    _save();
    return true;
  }

  void _applyKnotFaults(
    PlacementResult result,
    ShapeCells cells,
    Anchor a,
  ) {
    final every = faultEffects.knotEveryNthPlacement;
    if (every != null && _placementsThisStage % every == 0) {
      board = knotOneEmptyCell(board, _rng);
    }
    if (faultEffects.knotOnDryPlacement && result.lines == 0) {
      board = knotOwnCell(board, cells, a.x, a.y, _rng);
    }
  }

  void _recordMilestones(PlacementResult result, PlacementOutcome outcome) {
    var m = account.milestones;
    if (result.lines >= 3) m = m.copyWith(clearedThreeAtOnce: true);
    if (ladder.score.multiplier > m.bestRhythm) {
      m = m.copyWith(bestRhythm: ladder.score.multiplier);
    }
    account.milestones = m;
  }

  /* ---------------- stage boundaries ---------------- */

  void _onStageCleared() {
    _stagesCleared++;
    _recordFaultCleared();
    log.add(
      RunEvent(ladder.stage, 'Level ${ladder.stage} complete'),
    );
    haptics.stageClear();
    sfx.stageClear();
    if (ladder.score.multiplier > account.milestones.bestRhythm) {
      account.milestones = account.milestones.copyWith(
        bestRhythm: ladder.score.multiplier,
      );
    }
    if (_stagesCleared > account.milestones.bestStage) {
      account.milestones =
          account.milestones.copyWith(bestStage: _stagesCleared);
    }
    account.refreshOwnershipMilestones();

    // A fault stage pays a better draft the harder the fault was.
    final reward = activeFault?.reward ?? DraftReward.normal;
    draftOptions = offerDraft(
      tuning.powers,
      powers,
      _poolMilestones,
      _stagesCleared,
      _rng,
      reward: reward,
    );
    phase = draftOptions.isEmpty ? GamePhase.placing : GamePhase.draft;
    if (draftOptions.isEmpty) _advanceStage();
  }

  /// Take a draft card. Cards needing a motif named park in [GamePhase.motifChoice].
  void takeDraftCard(PowerDef def) {
    if (phase != GamePhase.draft) return;
    if (def.needsMotifChoice) {
      pendingMotifCard = def;
      phase = GamePhase.motifChoice;
      notifyListeners();
      return;
    }
    _applyCard(PickedPower(def.id));
  }

  /// Skip the draft. Legal, occasionally correct, and never forced on the
  /// player by an empty offer.
  void skipDraft() {
    if (phase != GamePhase.draft) return;
    draftOptions = [];
    _advanceStage();
    notifyListeners();
    _save();
  }

  void chooseMotifForCard(String shapeId) {
    final def = pendingMotifCard;
    if (def == null) return;
    _applyCard(PickedPower(def.id, motifId: shapeId));
  }

  void _applyCard(PickedPower pick) {
    powers = powers.plus(pick);
    log.add(RunEvent(ladder.stage, 'Took ${powerName(pick.id)}'));

    switch (pick.id) {
      case 'cull':
        if (pick.motifId != null && _bag.cull(pick.motifId!)) {
          _bag.resetPending();
        }
      case 'favour':
        // Guarded rather than trusted: a stale chooser, or a restored run
        // whose save predates a Cull, could name a motif the bag no longer
        // has, and Bag.favour treats that as a programmer error.
        if (pick.motifId != null &&
            _bag.loadout.any((s) => s.id == pick.motifId)) {
          _bag.favour(pick.motifId!);
          _bag.resetPending();
        }
      case 'batten':
        battenCharges = powers.battenChargesPerRun;
      case 'second_shuttle':
        // A 4th slot takes effect at the next refill, not mid-tray: filling it
        // immediately would hand out a free piece.
        break;
      default:
        break;
    }

    pendingMotifCard = null;
    draftOptions = [];
    _advanceStage();
    notifyListeners();
    _save();
  }

  void _advanceStage() {
    final wasAct = actOf(ladder.stage);
    ladder = nextStage(
      ladder,
      curve,
      mods: ladderMods,
      shields: account.openingShields + powers.shieldsPerStage,
    );
    final nowAct = actOf(ladder.stage);

    // Recompute with the new stage's own modifiers, since ladderMods depends
    // on the stage (the opening-allowance upgrade only applies to stage 1).
    ladder = ladder.copyWith(
      target: targetFor(curve, ladder.stage, mods: ladderMods),
      placementsLeft: allowanceFor(curve, ladder.stage, mods: ladderMods),
    );

    if (nowAct != wasAct && !chosenFaultByAct.containsKey(nowAct)) {
      _offerFaultsForAct(nowAct);
      // The stage still has to be set up; it happens when the fault is chosen.
      notifyListeners();
      return;
    }

    phase = GamePhase.placing;
    _beginStage();
  }

  /* ---------------- tools ---------------- */

  bool hasTool(String id) => (toolCharges[id] ?? 0) > 0;

  void aimTool(String id) {
    if (phase != GamePhase.placing) return;
    aiming = switch (id) {
      'unpick' => ToolAim.unpick,
      'shears' => ToolAim.shears,
      _ => ToolAim.none,
    };
    notifyListeners();
  }

  void cancelAim() {
    aiming = ToolAim.none;
    notifyListeners();
  }

  /// Nothing in the tray fits as it stands, but something fits turned.
  ///
  /// Rotation is tap-only and announced by three small pips under a tray
  /// block, which nothing anywhere explains. A player who has not guessed it
  /// reads this board as a jam and stops (UX review 4.1).
  bool get needsRotation {
    if (phase != GamePhase.placing || rotationDisabled) return false;
    final shapes = _liveShapes;
    if (shapes.isEmpty) return false;
    if (hasAnyLegalMove(
      board,
      shapes,
      allowRotation: false,
      rotations: _liveRotations,
    )) {
      return false;
    }
    return hasAnyLegalMove(board, shapes);
  }

  /// Apply an aimed tool at a board cell.
  void applyToolAt(int x, int y) {
    if (!inBounds(board, x, y)) return;
    switch (aiming) {
      case ToolAim.unpick:
        if (!_spend('unpick')) return;
        // Unpick removes one cell — including a knot, which is the only
        // in-run answer to one (`faults.json.knot.removableBy`).
        board = setCell(board, x, y, kEmpty);
      case ToolAim.shears:
        if (!_spend('shears')) return;
        var b = board;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            b = setCell(b, x + dx, y + dy, kEmpty);
          }
        }
        board = b;
      case ToolAim.battenRow:
        if (battenCharges <= 0) return;
        battenCharges--;
        board = applyClears(board, Clears([y], const []));
      case ToolAim.battenCol:
        if (battenCharges <= 0) return;
        battenCharges--;
        board = applyClears(board, Clears(const [], [x]));
      case ToolAim.none:
        return;
    }
    aiming = ToolAim.none;
    haptics.place();
    sfx.place();
    // A tool can open the board back up, so the jam check has to run again —
    // and a tool that clears a line deliberately does **not** score, because
    // a scoring tool would be a second, cheaper source of rhythm.
    _checkJam();
    notifyListeners();
    _save();
  }

  void aimBatten({required bool row}) {
    if (battenCharges <= 0) return;
    aiming = row ? ToolAim.battenRow : ToolAim.battenCol;
    notifyListeners();
  }

  /// Re-thread: reroll the tray.
  void rethread() {
    if (!_spend('rethread')) return;
    tray = List<TrayItem?>.filled(slotCount, null);
    _refill();
    haptics.snap();
    sfx.snap();
    _checkJam();
    notifyListeners();
    _save();
  }

  /// Resley: once per stage, replace the entire tray — the same action as
  /// Re-thread but on its own, rarer budget.
  void resley() {
    if (!_spend('resley')) return;
    tray = List<TrayItem?>.filled(slotCount, null);
    _refill();
    haptics.snap();
    sfx.snap();
    _checkJam();
    notifyListeners();
    _save();
  }

  /// Hold: set one motif aside indefinitely.
  void holdPiece(int slot) {
    if (!powers.hasHold || holdItem != null) return;
    if (slot >= tray.length) return;
    final item = tray[slot];
    if (item == null) return;
    holdItem = item;
    tray[slot] = null;
    // Deliberately does NOT refill: holding is not a way to draw a fourth
    // piece, and letting it refill would quietly undo the refill-on-empty rule.
    _ensureTray();
    notifyListeners();
    _save();
  }

  /// The player has acknowledged "Tap a block to rotate it"; never show it
  /// again on this install.
  void markRotateHintSeen() {
    if (account.seenRotateHint) return;
    account.seenRotateHint = true;
    _saveAccount();
    notifyListeners();
  }

  bool _spend(String id) {
    final n = toolCharges[id] ?? 0;
    if (n <= 0) return false;
    toolCharges[id] = n - 1;
    return true;
  }

  /* ---------------- ending ---------------- */

  void _onWin() {
    _stagesCleared++;
    _recordFaultCleared();
    haptics.win();
    sfx.win();
    log.add(RunEvent(ladder.stage, 'You win!'));
    account.wins++;
    if (_stagesCleared > account.milestones.bestStage) {
      account.milestones =
          account.milestones.copyWith(bestStage: _stagesCleared);
    }
    _endRun();
  }

  void _endRun() {
    phase = ladder.phase == RunPhase.won ? GamePhase.won : GamePhase.lost;
    // A loss used to end in silence while a combo break got a full buzz. A
    // jam is 43% of early deaths and the moment that most needs to register.
    if (phase == GamePhase.lost) {
      haptics.runEnd();
      sfx.runEnd();
    }

    // Payout keys off STAGES, never score (docs/04 §1) — and pays for every
    // stage the run REACHED, so the stage you fought and lost is worth
    // something (docs/04 §7).
    final won = ladder.phase == RunPhase.won;
    final base = tuning.economy.payout.forRun(
      stagesCleared: _stagesCleared,
      finalStage: curve.stages,
      won: won,
    );
    final piecework = powers.spoolsPerStageBonus * _stagesCleared;
    _spoolsEarned = ((base + piecework) * powers.spoolMultiplier).round() +
        (_firstRunOfDay ? tuning.economy.payout.firstRunOfDayBonus : 0);

    // Spend the daily bonus now that a run has actually been finished.
    account.lastPlayedDay = _today();

    account.spools += _spoolsEarned;
    account.milestones = account.milestones.copyWith(
      runsFinished: account.milestones.runsFinished + 1,
      jammed: account.milestones.jammed ||
          ladder.lossReason == LossReason.jam,
      // "Lose a run to a broken rhythm": the run ended short of target while
      // the multiplier was back on the floor.
      lostToBrokenRhythm: account.milestones.lostToBrokenRhythm ||
          (ladder.lossReason == LossReason.target &&
              ladder.score.multiplier <= scoring.multStart),
    );
    account.bestRunTotal = math.max(account.bestRunTotal, ladder.score.total);
    account.refreshOwnershipMilestones();

    storage.delete(runKey);
    _saveAccount();
  }

  /// The headline on the summary.
  ///
  /// "Out of moves" was true and useless: it named the mechanism and not the
  /// margin, and a run that ended three points short reads identically to one
  /// that ended three hundred short (UX review 5.1).
  String get lossHeadline => switch (ladder.lossReason) {
    LossReason.jam => 'No moves left',
    LossReason.target => _pointsShort > 0
        ? '$_pointsShort ${_pointsShort == 1 ? 'point' : 'points'} short'
        : 'Out of moves',
    null => 'You win!',
  };

  int get _pointsShort => ladder.target - ladder.stageScore;

  /// Whether the summary should print how close the level came. A jam can
  /// happen at any score, so the margin says nothing there.
  bool get lossWasOnScore => ladder.lossReason == LossReason.target;

  /* ---------------- persistence ---------------- */

  void _save() {
    if (phase == GamePhase.lost || phase == GamePhase.won) return;
    storage.write(runKey, toJson());
    _saveAccount();
  }

  void _saveAccount() => storage.write(accountKey, account.toJson());

  /// Autosave after every placement (spec §8). Phone games get interrupted;
  /// losing a run to a phone call is unforgivable.
  ///
  /// The board is saved as cell values; the RNG as seed plus cursor, which is
  /// what makes the stream resumable without storing its internal state.
  Map<String, dynamic> toJson() => {
    'seed': seed,
    'cursor': _rng.cursor,
    'board': {'w': board.w, 'h': board.h, 'cells': board.cells.toList()},
    'pending': _bag.pendingIds,
    'tray': [
      for (final t in tray)
        if (t == null) null else {'id': t.shapeId, 'r': t.rotation},
    ],
    'hold': holdItem == null
        ? null
        : {'id': holdItem!.shapeId, 'r': holdItem!.rotation},
    'ladder': {
      'stage': ladder.stage,
      'target': ladder.target,
      'stageScore': ladder.stageScore,
      'placementsLeft': ladder.placementsLeft,
      'total': ladder.score.total,
      'multiplier': ladder.score.multiplier,
      'patience': ladder.score.patience,
      'shields': ladder.score.shields,
      'phase': ladder.phase.name,
    },
    'picks': [
      for (final p in powers.picks) {'id': p.id, 'motif': p.motifId},
    ],
    'faults': {
      for (final e in chosenFaultByAct.entries) e.key.toString(): e.value,
    },
    'phase': phase.name,
    'tools': toolCharges,
    'batten': battenCharges,
    'placementsThisStage': _placementsThisStage,
    'temple': _templeSpentThisStage,
    'stagesCleared': _stagesCleared,
    'firstRunOfDay': _firstRunOfDay,
    // Serialised rather than re-read from the account on restore, or resuming
    // a run would hand it every milestone earned since it started.
    'poolMilestones': _poolMilestones.toJson(),
    'log': [
      for (final e in log) {'stage': e.stage, 'text': e.text},
    ],
  };

  /// True when a run was restored.
  ///
  /// A save that cannot be read is dropped rather than half-applied: a
  /// half-restored run is worse than a lost one, because the player cannot
  /// tell what is wrong.
  Future<bool> restore() async {
    final j = await storage.read(runKey);
    if (j == null) return false;
    try {
      _restoreFrom(j);
      notifyListeners();
      return true;
    } on Object {
      await storage.delete(runKey);
      return false;
    }
  }

  void _restoreFrom(Map<String, dynamic> j) {
    seed = (j['seed'] as num).toInt();
    _rng = Rng(seed, (j['cursor'] as num).toInt());

    powers = PowerSet(
      [
        for (final p in j['picks'] as List)
          PickedPower(
            (p as Map<String, dynamic>)['id'] as String,
            motifId: p['motif'] as String?,
          ),
      ],
      yarn: account.yarnUpgrades,
    );

    // The bag's *loadout* is rebuilt from the account with Cull and Favour
    // replayed from the picks above, but its remaining shuffle has to be
    // restored explicitly: how much of the current shuffle is left is state
    // the RNG cursor does not capture (see Bag.pendingIds).
    _bag = Bag(account.loadoutShapes(), _rng);
    for (final pick in powers.picks) {
      if (pick.motifId == null) continue;
      if (pick.id == 'cull') _bag.cull(pick.motifId!);
      if (pick.id == 'favour') _bag.favour(pick.motifId!);
    }
    _bag.restorePending([
      for (final id in (j['pending'] as List?) ?? const []) id as String,
    ]);

    final b = j['board'] as Map<String, dynamic>;
    board = createBoard((b['w'] as num).toInt(), (b['h'] as num).toInt());
    final cells = b['cells'] as List;
    for (var i = 0; i < cells.length && i < board.cells.length; i++) {
      board.cells[i] = (cells[i] as num).toInt();
    }

    tray = [
      for (final t in j['tray'] as List)
        t == null
            ? null
            : TrayItem(
                (t as Map<String, dynamic>)['id'] as String,
                (t['r'] as num).toInt(),
              ),
    ];
    final hold = j['hold'] as Map<String, dynamic>?;
    holdItem = hold == null
        ? null
        : TrayItem(hold['id'] as String, (hold['r'] as num).toInt());

    chosenFaultByAct.clear();
    (j['faults'] as Map<String, dynamic>).forEach((k, v) {
      chosenFaultByAct[int.parse(k)] = v as String;
    });

    final l = j['ladder'] as Map<String, dynamic>;
    ladder = LadderState(
      stage: (l['stage'] as num).toInt(),
      target: (l['target'] as num).toInt(),
      stageScore: (l['stageScore'] as num).toInt(),
      placementsLeft: (l['placementsLeft'] as num).toInt(),
      score: ScoreState(
        total: (l['total'] as num).toInt(),
        multiplier: (l['multiplier'] as num).toDouble(),
        patience: (l['patience'] as num).toInt(),
        shields: (l['shields'] as num).toInt(),
      ),
      phase: RunPhase.values.firstWhere((p) => p.name == l['phase']),
      lossReason: null,
    );

    final faultId = chosenFaultByAct[actOf(ladder.stage)];
    if (isFaultStage(ladder.stage) && faultId != null) {
      activeFault = tuning.faults.byId(faultId);
      faultEffects = effectsOf(faultId);
    } else {
      activeFault = null;
      faultEffects = FaultEffects.none;
    }

    toolCharges
      ..clear()
      ..addAll({
        for (final e in (j['tools'] as Map<String, dynamic>).entries)
          e.key: (e.value as num).toInt(),
      });
    battenCharges = (j['batten'] as num?)?.toInt() ?? 0;
    _placementsThisStage = (j['placementsThisStage'] as num?)?.toInt() ?? 0;
    _stagesCleared = (j['stagesCleared'] as num?)?.toInt() ?? 0;
    _templeSpentThisStage = (j['temple'] as bool?) ?? false;
    _firstRunOfDay = (j['firstRunOfDay'] as bool?) ?? false;
    final pool = j['poolMilestones'] as Map<String, dynamic>?;
    // A save from a build that predates the snapshot falls back to the
    // account, which is the old behaviour — wrong, but not a crash, and only
    // for runs already in progress at upgrade time.
    _poolMilestones =
        pool == null ? account.milestones : Milestones.fromJson(pool);
    log
      ..clear()
      ..addAll([
        for (final e in (j['log'] as List?) ?? const [])
          RunEvent(
            ((e as Map<String, dynamic>)['stage'] as num).toInt(),
            e['text'] as String,
          ),
      ]);

    phase = GamePhase.values.firstWhere(
      (p) => p.name == j['phase'],
      orElse: () => GamePhase.placing,
    );
    if (phase == GamePhase.faultChoice) {
      _offerFaultsForAct(actOf(ladder.stage));
    } else if (phase == GamePhase.draft) {
      draftOptions = offerDraft(
        tuning.powers,
        powers,
        _poolMilestones,
        _stagesCleared,
        Rng(seed, _rng.cursor),
        reward: activeFault?.reward ?? DraftReward.normal,
      );
    }
    aiming = ToolAim.none;
  }

  /* ---------------- test seams ---------------- */

  /// Run the stage-setup path directly.
  ///
  /// Exposed because the fault behaviours only fire at stages 4, 8 and 12, and
  /// a test that had to *play* to stage 12 to check Tight Reed would be slow,
  /// flaky and dependent on the auto-player's skill.
  @visibleForTesting
  void startStageForTest() => _beginStage();

  @visibleForTesting
  void checkJamForTest() => _checkJam();

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }
}
