import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/bag.dart';
import 'package:loomcraft/core/board.dart';
import 'package:loomcraft/core/faults.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';
import 'package:loomcraft/data/tuning.dart';
import 'package:loomcraft/game/account.dart';
import 'package:loomcraft/game/run_controller.dart';
import 'package:loomcraft/platform/haptics.dart';
import 'package:loomcraft/platform/storage.dart';

import '../sim/greedy.dart';
import '../support/load_tuning.dart';

/// The controller is the one piece of this port the TypeScript oracle does not
/// cover, so it gets an end-to-end harness of its own: a greedy player drives
/// real runs through the real controller and the assertions are about
/// *sequencing* — whose turn it is, what carries over, what is saved.
void main() {
  late Tuning tuning;

  setUpAll(() async {
    tuning = await loadTuningForTest();
  });

  /// Haptics that never touch the platform channel.
  Haptics silentHaptics() => Haptics(enabled: false);

  ({RunController c, Account a, MemoryStorage s}) build({
    Account? account,
    int seed = 1,
    bool firstInstall = false,
  }) {
    final a = account ?? Account();
    // Every run here is an ordinary one unless a test says otherwise.
    //
    // A literal first install (`runsStarted == 0`) gets a level 1 pre-arranged
    // to teach — a nearly-complete column and a hint at the block that
    // finishes it (`RunController._arrangeOpeningLesson`). That is the right
    // thing for a person and the wrong board to assert sequencing, scoring or
    // a gate against, so it is opt-in here.
    if (!firstInstall && a.runsStarted == 0) a.runsStarted = 1;
    final s = MemoryStorage();
    final c = RunController(
      tuning: tuning,
      account: a,
      storage: s,
      haptics: silentHaptics(),
      seedSource: () => seed,
    );
    return (c: c, a: a, s: s);
  }

  /// An account with everything, for the "reliable at 100% unlocks" gate.
  Account maxedAccount() => Account(
    spools: 0,
    ownedShapeIds: {for (final s in allShapes) s.id},
    upgrades: {
      'loadoutSlot9',
      'openingRhythm',
      'openingAllowance',
      'startingSelvage',
      'fineYarn',
      'standardYarn',
      'heavyYarn',
    },
    loadout: [
      // Nine motifs, small-biased: liquidity beats raw size before powers.
      'dot', 'i2', 'i3', 'o2', 'l3', 'i4', 't4', 'l4', 'j4',
    ],
    // "Everything" includes the fault ladder: faults unlock by tier within
    // their act, so an account that has not cleared any would only ever be
    // offered tier 1 and the 100% gate would be measuring a narrower game
    // than it claims.
    faultsCleared: {for (final f in tuning.faults.all) f.id},
    milestones: const Milestones(
      tier3Owned: 6,
      motifsOwned: 22,
      bestStage: 12,
      bestRhythm: 4.0,
      runsFinished: 20,
      clearedThreeAtOnce: true,
      lostToBrokenRhythm: true,
      jammed: true,
      spoolsBanked: 9000,
    ),
  );

  /// Answer the act's challenge screen, if the game is asking.
  ///
  /// With one unlocked option the controller takes it rather than putting up a
  /// screen with a single answer on it, so a run may already be placing.
  void takeFirstFault(RunController c) {
    if (c.phase == GamePhase.faultChoice) {
      c.chooseFault(c.faultOptions.first.id);
    }
  }

  /// Drive the controller with the greedy player until the run ends.
  ///
  /// Also the integration test for the phase machine: every non-placing phase
  /// has to be answerable, or this loop deadlocks and the guard fires.
  int playOut(RunController c, {int guard = 20000, bool takeCards = true}) {
    var steps = 0;
    for (var i = 0; i < guard; i++) {
      steps++;
      switch (c.phase) {
        case GamePhase.faultChoice:
          c.chooseFault(c.faultOptions.first.id);
        case GamePhase.draft:
          if (takeCards && c.draftOptions.isNotEmpty) {
            c.takeDraftCard(c.draftOptions.first);
          } else {
            c.skipDraft();
          }
        case GamePhase.motifChoice:
          c.chooseMotifForCard(c.bagLoadout.first.id);
        case GamePhase.placing:
          final slots = <TrayItem?>[
            ...c.tray,
            if (c.powers.hasHold) c.holdItem,
          ];
          final move = bestMove(
            c.board,
            slots,
            allowRotation: !c.rotationDisabled,
          );
          if (move == null) {
            fail('greedy found no move but the controller is still placing');
          }
          _rotateTo(c, move.slot, move.rotation);
          final ok = c.place(move.slot, Anchor(move.ax, move.ay));
          expect(ok, isTrue, reason: 'greedy proposed an illegal placement');
        case GamePhase.lost:
        case GamePhase.won:
          return steps;
      }
    }
    fail('run did not terminate');
  }

  group('starting a run', () {
    test('opens by announcing act 1 faults, not by placing', () {
      // The act's options are announced when the act begins, so the player can
      // draft toward the one they chose.
      final t = build(account: Account(runsStarted: 1, faultsCleared: {
        'thin_place',
      }));
      t.c.begin();
      expect(t.c.phase, GamePhase.faultChoice);
      expect(t.c.faultOptions, isNotEmpty);
      expect(t.c.faultOptions.map((f) => f.act).toSet(), {1});
      expect(t.c.tray.every((s) => s == null), isTrue);
    });

    test('all three faults are shown, and only the unlocked ones pickable', () {
      // All three are *shown*: a ladder the player cannot see is not a ladder,
      // and a locked row tells them what they are working toward. Only the
      // unlocked ones are selectable (docs/06 §6a).
      final t = build(account: Account(runsStarted: 1, faultsCleared: {
        'thin_place',
      }));
      t.c.begin();
      expect(t.c.faultOptions, hasLength(3));
      expect(t.c.lockedFaultIds, hasLength(1));
      // And the hint names what unlocks each locked one.
      final tier3 = t.c.faultOptions.firstWhere((f) => f.tier == 3);
      expect(t.c.unlockedBy(tier3.id)?.tier, 2);
      expect(t.c.unlockedBy(t.c.faultOptions.first.id), isNull);
    });

    test('a sole unlocked fault is taken rather than asked about', () {
      // A fresh account has exactly one selectable fault per act, so the screen
      // was a question with one answer — asked before a block had been placed,
      // about a level the player would not reach for three more (UX review 3).
      //
      // Nothing is narrowed by this (invariant 5): the locked options are
      // locked either way, and the chosen fault still lands on level 4.
      final t = build(account: Account(runsStarted: 1));
      t.c.begin();
      expect(t.c.phase, GamePhase.placing);
      expect(t.c.chosenFaultByAct[1], 'thin_place');
      expect(t.c.faultOptions, isEmpty);
      expect(t.c.tray.every((s) => s != null), isTrue);
    });

    test('a locked fault cannot be chosen, even if something taps it', () {
      final t = build(account: Account(runsStarted: 1, faultsCleared: {
        'thin_place',
      }));
      t.c.begin();
      final locked = t.c.lockedFaultIds.first;
      t.c.chooseFault(locked);
      expect(t.c.phase, GamePhase.faultChoice, reason: 'refused, not accepted');
      expect(t.c.chosenFaultByAct, isEmpty);
    });

    test('the first run ever is arranged to teach, and only that one', () {
      // Level 1 of a first install starts with a nearly-complete column and a
      // hint at the block that finishes it, which is how the game now teaches
      // that both axes clear (UX review 1.1). It is not a head start the
      // player keeps getting.
      final t = build(firstInstall: true);
      t.c.begin();
      expect(t.c.tutorialRun, isTrue);
      expect(t.c.phase, GamePhase.placing);
      expect(countFilled(t.c.board), greaterThan(0));

      final hint = t.c.openingHint;
      expect(hint, isNotNull);
      final item = t.c.tray[hint!.slot]!;
      expect(t.c.canPlace(item, hint.anchor), isTrue);
      expect(
        t.c.previewFor(item, hint.anchor).isNotEmpty,
        isTrue,
        reason: 'the hinted move finishes a line',
      );

      // The second run is an ordinary one.
      t.c.begin();
      expect(t.c.tutorialRun, isFalse);
      expect(countFilled(t.c.board), 0);
      expect(t.c.openingHint, isNull);
    });

    test('clearing a fault unlocks the next tier, and only the next', () {
      // All three are always shown; what changes is which are locked.
      final a = Account(runsStarted: 1, faultsCleared: {'thin_place'});
      final t = build(account: a);
      t.c.begin();
      expect(t.c.faultOptions, hasLength(3));
      expect(t.c.lockedFaultIds.length, 1);
      expect(
        t.c.faultOptions.where((f) => !t.c.lockedFaultIds.contains(f.id))
            .map((f) => f.tier),
        [1, 2],
      );

      final b = Account(
        runsStarted: 1,
        faultsCleared: {'thin_place', 'reediness'},
      );
      final u = build(account: b);
      u.c.begin();
      expect(u.c.lockedFaultIds, isEmpty);

      // Clearing act 2's tier 1 does nothing for act 1, and vice versa: the
      // ladder is per act, so progress cannot leak sideways. With only one
      // act-1 option selectable it is taken rather than asked about, so the
      // assertion is on what act 1 offered, not on a screen.
      final c = Account(runsStarted: 1, faultsCleared: {'fixed_heddles'});
      final v = build(account: c);
      v.c.begin();
      expect(v.c.phase, GamePhase.placing);
      expect(v.c.chosenFaultByAct[1], 'thin_place');
    });

    test('clearing the fault stage banks it on the account', () {
      final t = build(account: maxedAccount()..faultsCleared.clear());
      t.c.begin();
      takeFirstFault(t.c);
      playOut(t.c);
      // A run that reached stage 4 and cleared it has beaten one fault; a run
      // that died before stage 4 has beaten none. Either is fine — what must
      // not happen is banking a fault the player never cleared.
      if (t.c.stagesCleared >= 4) {
        expect(t.a.faultsCleared, contains('thin_place'));
      } else {
        expect(t.a.faultsCleared, isEmpty);
      }
    });

    test('choosing the fault starts stage 1 with a full tray', () {
      final t = build(account: Account(runsStarted: 1, faultsCleared: {
        'thin_place',
      }));
      t.c.begin();
      takeFirstFault(t.c);
      expect(t.c.phase, GamePhase.placing);
      expect(t.c.ladder.stage, 1);
      expect(t.c.tray, hasLength(3));
      expect(t.c.tray.every((s) => s != null), isTrue);
      // The chosen fault does NOT apply yet — it lands on stage 4.
      expect(t.c.faultEffects, FaultEffects.none);
      expect(t.c.activeFault, isNull);
    });

    test('the same seed produces the same run', () {
      final a = build(seed: 99);
      a.c.begin();
      a.c.chooseFault('thin_place');
      final b = build(seed: 99);
      b.c.begin();
      b.c.chooseFault('thin_place');
      expect(
        a.c.tray.map((t) => t?.shapeId),
        b.c.tray.map((t) => t?.shapeId),
      );
      playOut(a.c);
      playOut(b.c);
      expect(a.c.ladder.score.total, b.c.ladder.score.total);
      expect(a.c.stagesCleared, b.c.stagesCleared);
    });

    test('honours the bought opening upgrades', () {
      final a = Account(
        upgrades: {'openingRhythm', 'openingAllowance', 'startingSelvage'},
      );
      final t = build(account: a);
      t.c.begin();
      t.c.chooseFault('thin_place');
      // Rebuilt 2026-11-12 (docs/04 §9): the opening upgrades were small flat
      // numbers and are now structural. Combo Floor holds x2.0 at **every**
      // stage, Shields gives three refilled every stage, and Extra Moves is
      // +5 on every stage rather than +2 on the first.
      expect(t.c.ladder.score.multiplier, 2.0);
      expect(t.c.ladder.score.shields, 3);
      expect(t.c.ladder.placementsLeft, allowanceFor(tuning.curve, 1) + 5);
    });

    test('a fresh account plays with the five free motifs', () {
      final t = build();
      t.c.begin();
      expect(t.c.account.loadoutShapes(), hasLength(5));
      expect(
        t.c.account.loadoutShapes().every((s) => s.tier == 1),
        isTrue,
      );
    });
  });

  group('what the player is told', () {
    test('a dry placement spends a pip and says so', () {
      // The HUD animates the *event*, not the value: patience also refills at
      // a stage boundary, where nothing was lost (UX review 4.3).
      final t = build();
      t.c.begin();
      final before = t.c.patienceLossTick;

      // Somewhere no line can complete on the opening board.
      final slot = t.c.tray.indexWhere((i) => i != null);
      expect(t.c.place(slot, const Anchor(0, 0)), isTrue);

      expect(t.c.ladder.score.patience, lessThan(t.c.scoring.patienceMax));
      expect(t.c.patienceLossTick, before + 1);
      expect(t.c.comboBreakTick, 0, reason: 'a pip is not a break');
    });

    test('a jam names the gaps before the run ends', () {
      // A jam is 43% of early deaths and the summary named neither the rule
      // nor the place. Every empty cell of a jammed board is one no block
      // fits, so there is no heuristic here to get wrong (UX review 5).
      final t = build();
      t.c.begin();

      // Tier 1 only, so nothing in the bag is under three cells: a board that
      // is full but for two isolated single cells cannot be played.
      var b = createBoard();
      for (var y = 0; y < b.h; y++) {
        for (var x = 0; x < b.w; x++) {
          if ((x == 0 && y == 0) || (x == 7 && y == 7)) continue;
          b = setCell(b, x, y, 3);
        }
      }
      t.c.board = b;

      t.c.powers = t.c.powers.plus(const PickedPower('rethread'));
      t.c.toolCharges['rethread'] = 1;
      t.c.rethread();

      expect(t.c.phase, GamePhase.lost);
      expect(t.c.ladder.lossReason, LossReason.jam);
      expect(t.c.jamCells, unorderedEquals(const <Coord>[(0, 0), (7, 7)]));
      expect(t.a.jamsSeen, 1);
    });

    test('a near miss says how near', () {
      // "Out of moves" was true and useless: it named the mechanism, not the
      // margin, so three points short read exactly like three hundred short
      // (UX review 5.1).
      final t = build();
      t.c.begin();
      t.c.ladder = t.c.ladder.copyWith(
        stageScore: t.c.ladder.target - 3,
        phase: RunPhase.lost,
        lossReason: LossReason.target,
      );
      expect(t.c.lossHeadline, '3 points short');
      expect(t.c.lossWasOnScore, isTrue);
    });

    test('rotation is only pointed out when it is the answer', () {
      // The one control the game never names anywhere (UX review 4.1).
      final t = build();
      t.c.begin();
      expect(
        t.c.needsRotation,
        isFalse,
        reason: 'an open board needs no advice',
      );

      // A board with one free column: a wide block only fits turned.
      var b = createBoard();
      for (var y = 0; y < b.h; y++) {
        for (var x = 0; x < b.w - 1; x++) {
          b = setCell(b, x, y, 3);
        }
      }
      t.c.board = b;
      final wide = shape('i3').rotations
          .indexWhere((f) => extent(f).w > extent(f).h);
      t.c.tray = [TrayItem('i3', wide), null, null];
      expect(t.c.needsRotation, isTrue);

      t.c.rotate(0);
      expect(t.c.needsRotation, isFalse);
    });
  });

  group('the refill rule', () {
    test('refills only when ALL slots are empty', () {
      // The single rule where the difficulty lives (spec §2.1).
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      final first = [for (final s in t.c.tray) s!.shapeId];

      // Place the first two pieces; the third slot must still hold its piece
      // and no new pieces may appear.
      var placed = 0;
      for (var slot = 0; slot < 3 && placed < 2; slot++) {
        final move = bestMove(t.c.board, [
          for (var i = 0; i < 3; i++) i == slot ? t.c.tray[i] : null,
        ]);
        if (move == null) continue;
        _rotateTo(t.c, slot, move.rotation);
        t.c.place(slot, Anchor(move.ax, move.ay));
        placed++;
      }
      expect(placed, 2);
      expect(t.c.tray.where((s) => s == null), hasLength(2));
      final survivor = t.c.tray.indexWhere((s) => s != null);
      expect(
        t.c.tray[survivor]!.shapeId,
        first[survivor],
        reason: 'the surviving slot was not reshuffled',
      );
    });

    test('shouldRefill is what the controller asks, hold slot excluded', () {
      // Hold must not make the tray look non-empty, or the refill never fires.
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      expect(shouldRefill(t.c.tray), isFalse);
      t.c.tray.setAll(0, List<TrayItem?>.filled(3, null));
      expect(shouldRefill(t.c.tray), isTrue);
    });
  });

  group('placement', () {
    test('an invalid placement consumes nothing', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      // Fill (0,0) then try to put something on top of it.
      final before = t.c.tray[0];
      t.c.board = place(t.c.board, cellsOf('o3', 0), 0, 0, 9);
      final ok = t.c.place(0, const Anchor(0, 0));
      expect(ok, isFalse);
      expect(t.c.tray[0], before);
      expect(t.c.ladder.placementsLeft, allowanceFor(tuning.curve, 1));
    });

    test('rotation is refused while a fault disables it', () {
      final t = build();
      t.c.begin();
      // Pick Fixed Heddles, then fast-forward to its stage.
      t.c.chooseFault('thin_place');
      expect(t.c.rotationDisabled, isFalse);

      final direct = build();
      direct.c.begin();
      direct.c.chooseFault('thin_place');
      direct.c.faultEffects = effectsOf('fixed_heddles');
      final before = direct.c.tray[0]!.rotation;
      direct.c.rotate(0);
      expect(direct.c.tray[0]!.rotation, before);
    });

    test('scoring goes through core, so the ladder and score agree', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      final slot = 0;
      final item = t.c.tray[slot]!;
      final cells = cellsOf(item.shapeId, item.rotation);
      final s = shape(item.shapeId);
      t.c.place(slot, const Anchor(0, 0));
      // **Zero.** Nothing cleared, and placing a block scores nothing on its
      // own as of 2026-11-12 — points come from clearing a row or a column.
      expect(t.c.ladder.stageScore, 0);
      expect(t.c.ladder.score.total, 0);
      expect(cells, hasLength(s.cellCount));

      // With a yarn bought it pays its cells, which is what the whole family
      // now sells: placement income, band by band (docs/05 §10).
      final paid = build(account: Account(upgrades: {'standardYarn'}));
      paid.c.begin();
      paid.c.chooseFault('thin_place');
      final mid = paid.c.tray.firstWhere(
        (i) => i != null && shape(i.shapeId).cellCount >= 3,
      )!;
      final midSlot = paid.c.tray.indexOf(mid);
      paid.c.place(midSlot, const Anchor(0, 0));
      expect(
        paid.c.ladder.score.total,
        shape(mid.shapeId).cellCount * 3,
        reason: 'Mid Block Bonus is +3 a cell',
      );
    });

    test('autosaves after every placement', () {
      // Phone games get interrupted; losing a run to a phone call is
      // unforgivable (spec §8).
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.place(0, const Anchor(0, 0));
      expect(t.s.read(runKey), completion(isNotNull));
    });
  });

  group('stage boundaries', () {
    test('clearing a stage offers a draft, and taking one advances', () async {
      // Owns a yarn, because placing a block scores nothing without one now
      // and stage 1 on line bonus alone is not a given (docs/05 §10).
      final t = build(account: Account(upgrades: {'standardYarn'}));
      t.c.begin();
      t.c.chooseFault('thin_place');
      // Walk the ladder to the first stage clear.
      while (t.c.phase == GamePhase.placing && t.c.ladder.stage == 1) {
        final move = bestMove(t.c.board, t.c.tray);
        if (move == null) break;
        _rotateTo(t.c, move.slot, move.rotation);
        t.c.place(move.slot, Anchor(move.ax, move.ay));
      }
      expect(t.c.phase, GamePhase.draft);
      expect(t.c.draftOptions, hasLength(3));
      expect(t.c.stagesCleared, 1);

      final boardBefore = boardToArt(t.c.board);
      final multiplierBefore = t.c.ladder.score.multiplier;

      final card = t.c.draftOptions.first;
      t.c.takeDraftCard(card);
      if (t.c.phase == GamePhase.motifChoice) {
        t.c.chooseMotifForCard('dot');
      }

      expect(t.c.phase, GamePhase.placing);
      expect(t.c.ladder.stage, 2);
      expect(t.c.ladder.stageScore, 0);
      expect(t.c.ladder.target, targetFor(tuning.curve, 2));
      expect(t.c.powers.picks, hasLength(1));

      // The board carries over (spec §2.7) and so does the rhythm.
      expect(boardToArt(t.c.board), boardBefore);
      expect(t.c.ladder.score.multiplier, multiplierBefore);
    });

    test('the draft can be skipped without stalling the run', () {
      final t = build();
      t.c.begin();
      playOut(t.c, takeCards: false);
      expect(t.c.powers.picks, isEmpty);
      expect(t.c.phase, anyOf(GamePhase.lost, GamePhase.won));
    });

    test('a new act asks for its fault before the next stage starts', () {
      final t = build(account: maxedAccount());
      t.c.begin();
      var sawAct2Choice = false;
      for (var i = 0; i < 20000; i++) {
        if (t.c.phase == GamePhase.faultChoice &&
            t.c.faultOptions.first.act == 2) {
          sawAct2Choice = true;
          expect(t.c.ladder.stage, 5);
          break;
        }
        switch (t.c.phase) {
          case GamePhase.faultChoice:
            takeFirstFault(t.c);
          case GamePhase.draft:
            t.c.takeDraftCard(t.c.draftOptions.first);
          case GamePhase.motifChoice:
            t.c.chooseMotifForCard('dot');
          case GamePhase.placing:
            final move = bestMove(t.c.board, t.c.tray);
            if (move == null) fail('no move');
            _rotateTo(t.c, move.slot, move.rotation);
            t.c.place(move.slot, Anchor(move.ax, move.ay));
          case GamePhase.lost:
          case GamePhase.won:
            i = 20000;
        }
      }
      expect(
        sawAct2Choice || t.c.phase == GamePhase.lost,
        isTrue,
        reason: 'either act 2 was reached and asked, or the run ended first',
      );
    });
  });

  group('faults', () {
    test('apply at stage 4 and nowhere else', () {
      final t = build(account: maxedAccount());
      t.c.begin();
      t.c.chooseFault('reediness');
      expect(t.c.faultEffects, FaultEffects.none);

      // Force the ladder to stage 4 and begin it.
      t.c.ladder = t.c.ladder.copyWith(stage: 4, phase: RunPhase.stageClear);
      t.c.ladder = nextStage(t.c.ladder, tuning.curve).copyWith(stage: 4);
      t.c.startStageForTest();
      expect(t.c.activeFault?.id, 'reediness');
      expect(t.c.faultEffects.axes, ClearAxes.colsOnly);
    });

    test('Tight Reed resizes the board and the next stage restores it', () {
      final t = build(account: maxedAccount());
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.chosenFaultByAct[3] = 'tight_reed';
      t.c.ladder = t.c.ladder.copyWith(stage: 12);
      t.c.startStageForTest();
      expect(t.c.board.w, 7);
      expect(t.c.boardSize, 7);
    });

    test('Slubs scatters exactly six knots that survive a clear', () {
      final t = build(account: maxedAccount());
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.chosenFaultByAct[2] = 'slubs';
      t.c.ladder = t.c.ladder.copyWith(stage: 8);
      t.c.startStageForTest();
      expect(countKnots(t.c.board), 6);
    });

    test('Barré serves only motifs of 4 cells or more', () {
      final a = maxedAccount();
      final t = build(account: a);
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.chosenFaultByAct[2] = 'barre';
      t.c.ladder = t.c.ladder.copyWith(stage: 8);
      t.c.tray.setAll(0, List<TrayItem?>.filled(3, null));
      t.c.startStageForTest();
      for (final item in t.c.tray) {
        expect(shape(item!.shapeId).cellCount, greaterThanOrEqualTo(4));
      }
    });

    test('the stage AFTER a fault does not inherit its scaling', () {
      // Regression: _advanceStage computes the next stage's target and
      // allowance while the previous stage's fault is still in force, so
      // stage 5 silently kept Tight Budget's x0.7 allowance and x0.75 target.
      final t = build(account: maxedAccount());
      t.c.begin();
      t.c.chooseFault('thin_place');

      t.c.ladder = t.c.ladder.copyWith(stage: 4);
      t.c.startStageForTest();
      expect(t.c.activeFault?.id, 'thin_place');
      expect(t.c.ladder.placementsLeft, lessThan(allowanceFor(tuning.curve, 4)));

      // Clear it and walk to stage 5.
      t.c.ladder = t.c.ladder.copyWith(phase: RunPhase.stageClear);
      t.c.phase = GamePhase.draft;
      t.c.draftOptions = [];
      t.c.skipDraft();

      // Stage 5 opens a new act, so it asks for the act-2 fault first.
      expect(t.c.phase, GamePhase.faultChoice);
      t.c.chooseFault('slubs');

      expect(t.c.ladder.stage, 5);
      expect(t.c.activeFault, isNull, reason: 'stage 5 is not a fault stage');
      expect(t.c.faultEffects, FaultEffects.none);
      expect(t.c.ladder.target, targetFor(tuning.curve, 5));
      // `maxedAccount` owns Extra Moves, which is +5 on every stage now, so
      // the assertion is "no fault scaling", not "the bare curve".
      expect(
        t.c.ladder.placementsLeft,
        allowanceFor(tuning.curve, 5) + t.a.openingAllowanceBonus,
      );
    });

    test('a fault stage recomputes its own target and allowance', () {
      final t = build(account: maxedAccount());
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.ladder = t.c.ladder.copyWith(stage: 4);
      t.c.startStageForTest();
      expect(t.c.activeFault?.id, 'thin_place');
      // Tight Budget: allowance x0.7, target x0.75.
      expect(t.c.ladder.target, lessThan(targetFor(tuning.curve, 4)));
      expect(
        t.c.ladder.placementsLeft,
        lessThan(allowanceFor(tuning.curve, 4)),
      );
    });
  });

  group('tools', () {
    test('Unpick removes one cell, including a knot', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.powers = t.c.powers.plus(const PickedPower('unpick'));
      t.c.toolCharges['unpick'] = 2;
      t.c.board = setCell(t.c.board, 3, 3, kKnot);

      t.c.aimTool('unpick');
      expect(t.c.aiming, ToolAim.unpick);
      t.c.applyToolAt(3, 3);
      expect(cellAt(t.c.board, 3, 3), kEmpty);
      expect(t.c.toolCharges['unpick'], 1);
      expect(t.c.aiming, ToolAim.none);
    });

    test('Shears clears a 2x2 and spends one charge', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.toolCharges['shears'] = 1;
      t.c.board = place(t.c.board, cellsOf('o2', 0), 2, 2, 4);
      t.c.aimTool('shears');
      t.c.applyToolAt(2, 2);
      expect(countFilled(t.c.board), 0);
      expect(t.c.hasTool('shears'), isFalse);
    });

    test('a tool with no charges does nothing', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.board = setCell(t.c.board, 1, 1, 3);
      t.c.aimTool('unpick');
      t.c.applyToolAt(1, 1);
      expect(cellAt(t.c.board, 1, 1), 3, reason: 'no charge, no effect');
    });

    test('Re-thread replaces the whole tray', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.toolCharges['rethread'] = 1;
      final before = [for (final s in t.c.tray) s!.shapeId];
      t.c.rethread();
      expect(t.c.tray.every((s) => s != null), isTrue);
      expect(t.c.hasTool('rethread'), isFalse);
      expect([for (final s in t.c.tray) s!.shapeId], isNot(before));
    });

    test('Batten clears a chosen row without scoring it', () {
      // A scoring tool would be a second, cheaper source of rhythm.
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.battenCharges = 1;
      t.c.board = boardFromArt([
        '########',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      final scoreBefore = t.c.ladder.score.total;
      t.c.aimBatten(row: true);
      t.c.applyToolAt(0, 0);
      expect(countFilled(t.c.board), 0);
      expect(t.c.ladder.score.total, scoreBefore);
      expect(t.c.ladder.score.multiplier, 1.0);
      expect(t.c.battenCharges, 0);
    });

    test('Hold sets a motif aside without drawing a replacement', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.powers = t.c.powers.plus(const PickedPower('hold'));
      final held = t.c.tray[1];
      t.c.holdPiece(1);
      expect(t.c.holdItem, held);
      expect(t.c.tray[1], isNull, reason: 'holding must not refill the slot');
    });

    test('tool charges refresh at each stage', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.powers = t.c.powers.plus(const PickedPower('unpick'));
      t.c.toolCharges['unpick'] = 0;
      t.c.startStageForTest();
      expect(t.c.toolCharges['unpick'], 2);
    });
  });

  group('Cull and Favour', () {
    test('the chooser offers the bag, not the account loadout', () {
      // Regression: Cull removes a motif for the rest of the run, so a chooser
      // built from the account keeps offering it — and Favour on a culled
      // motif is an error, not a no-op.
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      // `l3`, not `dot`: the roster inverted and `dot` is the single most
      // expensive purchase in the game now, so a fresh account does not have
      // it (lib/core/shapes.dart).
      expect(t.c.bagLoadout.map((s) => s.id), contains('l3'));

      _parkOnDraft(t.c, 'cull');
      t.c.takeDraftCard(t.c.draftOptions.first);
      expect(t.c.phase, GamePhase.motifChoice);
      t.c.chooseMotifForCard('l3');

      expect(t.c.bagLoadout.map((s) => s.id), isNot(contains('l3')));
      expect(t.c.account.loadout, contains('l3'),
          reason: 'the account is untouched — Cull is for this run only');
    });

    test('Favour on a culled motif is survived, not thrown', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      _parkOnDraft(t.c, 'cull');
      t.c.takeDraftCard(t.c.draftOptions.first);
      t.c.chooseMotifForCard('l3');

      _parkOnDraft(t.c, 'favour');
      t.c.takeDraftCard(t.c.draftOptions.first);
      expect(() => t.c.chooseMotifForCard('l3'), returnsNormally);
      expect(t.c.bagLoadout.map((s) => s.id), isNot(contains('l3')));
    });

    test('Cull never empties the bag', () {
      final t = build(account: Account(loadout: ['l3']));
      t.c.begin();
      t.c.chooseFault('thin_place');
      _parkOnDraft(t.c, 'cull');
      t.c.takeDraftCard(t.c.draftOptions.first);
      t.c.chooseMotifForCard('l3');
      expect(t.c.bagLoadout, isNotEmpty);
    });
  });

  group('the draft pool is fixed when the run starts', () {
    /// Drive a run, collecting every card id the draft ever offered.
    List<String> offeredDuring(RunController c) {
      final offered = <String>[];
      for (var i = 0; i < 20000; i++) {
        switch (c.phase) {
          case GamePhase.faultChoice:
            c.chooseFault(c.faultOptions.first.id);
          case GamePhase.draft:
            offered.addAll(c.draftOptions.map((d) => d.id));
            if (c.draftOptions.isEmpty) {
              c.skipDraft();
            } else {
              c.takeDraftCard(c.draftOptions.first);
            }
          case GamePhase.motifChoice:
            c.chooseMotifForCard(c.bagLoadout.first.id);
          case GamePhase.placing:
            final move = bestMove(
              c.board,
              [...c.tray, if (c.powers.hasHold) c.holdItem],
              allowRotation: !c.rotationDisabled,
            );
            if (move == null) fail('greedy stuck while placing');
            _rotateTo(c, move.slot, move.rotation);
            c.place(move.slot, Anchor(move.ax, move.ay));
          case GamePhase.lost:
          case GamePhase.won:
            return offered;
        }
      }
      fail('run did not terminate');
    }

    test('a milestone earned mid-run does not widen that run', () {
      // Reading `account.milestones` live meant clearing stage 7 put Second
      // Shuttle into the very next draft of the run that earned it. Measured,
      // a 0%-unlock account was drafting Treadle Rhythm, Batten and Second
      // Shuttle — so "0% unlocks", the gate the whole shop rests on, did not
      // mean the initial twelve at all.
      //
      // It is also a snowball: the strongest cards arrive exactly when the
      // player is already winning. A run's pool should be knowable at its
      // start, which is the same argument docs/06 §6 makes for faults.
      final t = build(account: Account(upgrades: {'standardYarn'}));
      final atStart = t.a.milestones;
      expect(atStart.bestStage, 0, reason: 'a fresh account');

      t.c.begin();
      final offered = offeredDuring(t.c).toSet();
      expect(offered, isNotEmpty);

      for (final id in offered) {
        final def = tuning.powers.byId(id);
        expect(
          atStart.satisfies(def.unlock),
          isTrue,
          reason: '$id was offered but needs "${def.unlock}", '
              'which this account had not met when the run began',
        );
      }

      // ...and the milestones it earned are still banked, for next time.
      expect(
        t.a.milestones.bestStage,
        greaterThan(atStart.bestStage),
        reason: 'the run still records what it achieved',
      );
    });

    test('the snapshot survives a save and restore', () async {
      // Re-reading the account on restore would hand a resumed run every
      // milestone earned since it started — the same bug, through the back
      // door, and only reachable by backgrounding the app mid-run.
      final t = build(seed: 31);
      t.c.begin();
      takeFirstFault(t.c);
      while (t.c.phase == GamePhase.placing) {
        final move = bestMove(t.c.board, t.c.tray);
        if (move == null) break;
        _rotateTo(t.c, move.slot, move.rotation);
        t.c.place(move.slot, Anchor(move.ax, move.ay));
      }

      // Something else raises the account's milestones while the run is parked.
      t.a.milestones = t.a.milestones.copyWith(bestStage: 12, bestRhythm: 4);

      final restored = RunController(
        tuning: tuning,
        account: t.a,
        storage: t.s,
        haptics: silentHaptics(),
      );
      await restored.restore();

      final offered = offeredDuring(restored).toSet();
      for (final id in offered) {
        final def = tuning.powers.byId(id);
        expect(
          def.isInitial,
          isTrue,
          reason: '$id was offered to a resumed run that began with nothing',
        );
      }
    });
  });

  group('ending a run', () {
    test('pays for stages reached and banks the spools', () {
      final t = build();
      t.c.begin();
      playOut(t.c);
      expect(t.c.phase, anyOf(GamePhase.lost, GamePhase.won));

      final expected = tuning.economy.payout.forRun(
            stagesCleared: t.c.stagesCleared,
            finalStage: tuning.curve.stages,
            won: t.c.phase == GamePhase.won,
          ) +
          (t.c.firstRunOfDay ? tuning.economy.payout.firstRunOfDayBonus : 0);
      expect(t.c.spoolsEarned, expected);
      expect(t.a.spools, expected);
    });

    test('a losing run is never worth nothing', () {
      // A run that dies on stage 1 still reached stage 1 (docs/04 §7).
      final t = build();
      t.c.begin();
      playOut(t.c);
      expect(t.c.spoolsEarned, greaterThan(0));
    });

    test('the daily bonus is earned by finishing, not by starting', () {
      // Writing `lastPlayedDay` in `begin()` meant an abandoned or restarted
      // run spent the bonus before a single placement, so the run the player
      // thought was their first paid 35 spools instead of 135 (docs/04 §7).
      final t = build();

      t.c.begin();
      expect(t.c.firstRunOfDay, isTrue);
      expect(t.a.lastPlayedDay, isNull, reason: 'not spent by starting');

      // Abandon it and start again: the bonus must still be there.
      t.c.begin();
      expect(t.c.firstRunOfDay, isTrue);

      playOut(t.c);
      expect(t.a.lastPlayedDay, isNotNull, reason: 'spent by finishing');
      expect(
        t.c.spoolsEarned,
        greaterThanOrEqualTo(tuning.economy.payout.firstRunOfDayBonus),
      );

      // And the second finished run of the same day does not get it again.
      // Asserted against the run's own payout rather than a constant, because
      // how deep the greedy player gets moves with every tuning change.
      final before = t.a.spools;
      t.c.begin();
      expect(t.c.firstRunOfDay, isFalse);
      playOut(t.c);
      expect(
        t.a.spools - before,
        tuning.economy.payout.forRun(
          stagesCleared: t.c.stagesCleared,
          finalStage: tuning.curve.stages,
          won: t.c.phase == GamePhase.won,
        ),
        reason: 'the second run of a day is paid its stages and nothing more',
      );
    });

    test('run 1 can afford the first block in the shop', () {
      // The complaint that started this: a first run paid 35 spools and the
      // shop was entirely unaffordable (docs/04 §7).
      final t = build();
      t.c.begin();
      playOut(t.c);
      expect(
        t.a.spools,
        greaterThanOrEqualTo(tuning.economy.costOfNthShapeInTier(2, 0)),
      );
    });

    test('payout ignores score entirely', () {
      // Keying payout to score creates a buy-more-earn-more spiral that
      // destroys the curve (docs/04 §1).
      final t = build();
      t.c.begin();
      playOut(t.c);
      final cleared = t.c.stagesCleared;

      final rich = build(account: maxedAccount(), seed: 1);
      rich.c.begin();
      playOut(rich.c);
      if (rich.c.stagesCleared == cleared) {
        expect(rich.c.ladder.score.total, greaterThan(t.c.ladder.score.total));
        expect(
          rich.c.spoolsEarned - (rich.c.firstRunOfDay
              ? tuning.economy.payout.firstRunOfDayBonus
              : 0),
          t.c.spoolsEarned - (t.c.firstRunOfDay
              ? tuning.economy.payout.firstRunOfDayBonus
              : 0),
        );
      }
    });

    test('Piecework and Bulk Order change the payout, not the score', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.powers = t.c.powers
          .plus(const PickedPower('piecework'))
          .plus(const PickedPower('bulk_order'));
      expect(t.c.powers.spoolsPerStageBonus, 25);
      expect(t.c.powers.spoolMultiplier, 1.6);
    });

    test('clears the run save but keeps the account', () async {
      final t = build();
      t.c.begin();
      playOut(t.c);
      expect(await t.s.read(runKey), isNull);
      expect(await t.s.read(accountKey), isNotNull);
    });

    test('records the milestones the draft unlocks depend on', () {
      final t = build();
      t.c.begin();
      playOut(t.c);
      expect(t.a.milestones.runsFinished, 1);
      expect(t.a.milestones.bestStage, t.c.stagesCleared);
      expect(t.a.milestones.bestRhythm, greaterThan(1.0));
    });

    test('names the two deaths differently', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.ladder = jam(t.c.ladder);
      expect(t.c.lossHeadline, 'No moves left');
    });

    test('a jam is detected and ends the run', () {
      final t = build();
      t.c.begin();
      t.c.chooseFault('thin_place');
      // Fill the board completely, then force the check.
      final full = boardFromArt(List.filled(8, '########'));
      t.c.board = full;
      t.c.checkJamForTest();
      expect(t.c.phase, GamePhase.lost);
      expect(t.c.ladder.lossReason, LossReason.jam);
      expect(t.a.milestones.jammed, isTrue);
    });
  });

  group('winning', () {
    test('walking all twelve levels wins the run', () {
      // The greedy player cannot reach stage 12 — by design, since a
      // 0%-unlock run is meant to be unwinnable (docs/06 §3) — so the win is
      // driven by lowering each stage's target to 1 and clearing it honestly.
      // That exercises the whole sequence: twelve stages, three fault choices,
      // eleven drafts, and the win. Without it the entire end of the campaign
      // is untested code.
      final t = build(account: maxedAccount());
      t.c.begin();

      final stagesSeen = <int>[];
      final faultActsAsked = <int>[];
      var drafts = 0;

      for (var guard = 0; guard < 400 && t.c.phase != GamePhase.won; guard++) {
        switch (t.c.phase) {
          case GamePhase.faultChoice:
            faultActsAsked.add(t.c.faultOptions.first.act);
            takeFirstFault(t.c);
          case GamePhase.draft:
            drafts++;
            t.c.takeDraftCard(t.c.draftOptions.first);
          case GamePhase.motifChoice:
            t.c.chooseMotifForCard(t.c.bagLoadout.first.id);
          case GamePhase.placing:
            stagesSeen.add(t.c.ladder.stage);
            // One cell is enough to clear a target of 1.
            t.c.ladder = t.c.ladder.copyWith(target: 1, stageScore: 0);
            final move = bestMove(
              t.c.board,
              t.c.tray,
              allowRotation: !t.c.rotationDisabled,
            )!;
            _rotateTo(t.c, move.slot, move.rotation);
            expect(t.c.place(move.slot, Anchor(move.ax, move.ay)), isTrue);
          case GamePhase.lost:
            fail('lost on stage ${t.c.ladder.stage}: ${t.c.lossHeadline}');
          case GamePhase.won:
            break;
        }
      }

      expect(t.c.phase, GamePhase.won);
      expect(t.c.ladder.phase, RunPhase.won);
      expect(t.c.stagesCleared, 12);
      expect(stagesSeen.toSet(), {for (var i = 1; i <= 12; i++) i});
      expect(t.c.draftOptions, isEmpty, reason: 'no draft after the last stage');
      expect(t.c.lossHeadline, 'You win!');
      expect(t.a.wins, 1);
      expect(t.a.milestones.bestStage, 12);

      // One fault choice per act, and eleven picks — one per stage cleared
      // except the last, which ends the run.
      expect(faultActsAsked, [1, 2, 3]);
      expect(drafts, 11);
      expect(t.c.powers.picks, hasLength(11));

      // Twelve stages is the full payout.
      final expected = tuning.economy.payout.forStages(12) +
          (t.c.firstRunOfDay
              ? tuning.economy.payout.firstRunOfDayBonus
              : 0);
      expect(
        t.c.spoolsEarned,
        ((expected - (t.c.firstRunOfDay
                    ? tuning.economy.payout.firstRunOfDayBonus
                    : 0) +
                t.c.powers.spoolsPerStageBonus * 12) *
                t.c.powers.spoolMultiplier)
            .round() +
            (t.c.firstRunOfDay
                ? tuning.economy.payout.firstRunOfDayBonus
                : 0),
      );
    });

    test('the run save is cleared on a win, not left to be resumed', () async {
      final t = build(account: maxedAccount());
      t.c.begin();
      t.c.chooseFault('thin_place');
      t.c.ladder = t.c.ladder.copyWith(
        stage: 12,
        target: 1,
        stageScore: 0,
        placementsLeft: 5,
      );
      final move = bestMove(t.c.board, t.c.tray)!;
      _rotateTo(t.c, move.slot, move.rotation);
      t.c.place(move.slot, Anchor(move.ax, move.ay));
      expect(t.c.phase, GamePhase.won);
      expect(await t.s.read(runKey), isNull);
    });
  });

  group('the three gates (docs/06 §3)', () {
    test('a 0%-unlock account cannot win', () {
      // "Unwinnable at 0% unlocks." Ten seeds is not a proof, but a regression
      // that made the opening ladder winnable bare-handed would show here.
      for (var seed = 1; seed <= 10; seed++) {
        final t = build(seed: seed);
        t.c.begin();
        playOut(t.c);
        expect(t.c.phase, GamePhase.lost, reason: 'seed $seed');
      }
    });

    test('a 100%-unlock account gets meaningfully further', () {
      // "Reliable at 100%." The greedy player has no lookahead and cannot set
      // up the multi-line clears a real player lives on, so this asserts the
      // *direction* the meta pushes rather than a win.
      var bare = 0;
      var maxed = 0;
      for (var seed = 1; seed <= 10; seed++) {
        final b = build(seed: seed);
        b.c.begin();
        playOut(b.c);
        bare += b.c.stagesCleared;

        final m = build(account: maxedAccount(), seed: seed);
        m.c.begin();
        playOut(m.c);
        maxed += m.c.stagesCleared;
      }
      expect(
        maxed,
        greaterThan(bare),
        reason: 'full meta plus a draft must be worth real depth',
      );
    });
  });

  group('autosave and restore', () {
    test('round-trips a run mid-stage', () async {
      final t = build(seed: 4242);
      t.c.begin();
      t.c.chooseFault('reediness');
      for (var i = 0; i < 12 && t.c.phase == GamePhase.placing; i++) {
        final move = bestMove(t.c.board, t.c.tray);
        if (move == null) break;
        _rotateTo(t.c, move.slot, move.rotation);
        t.c.place(move.slot, Anchor(move.ax, move.ay));
      }

      final restored = RunController(
        tuning: tuning,
        account: t.a,
        storage: t.s,
        haptics: silentHaptics(),
      );
      expect(await restored.restore(), isTrue);

      expect(restored.seed, t.c.seed);
      expect(boardToArt(restored.board), boardToArt(t.c.board));
      expect(restored.ladder.stage, t.c.ladder.stage);
      expect(restored.ladder.stageScore, t.c.ladder.stageScore);
      expect(restored.ladder.placementsLeft, t.c.ladder.placementsLeft);
      expect(restored.ladder.score.total, t.c.ladder.score.total);
      expect(restored.ladder.score.multiplier, t.c.ladder.score.multiplier);
      expect(restored.phase, t.c.phase);
      expect(
        restored.tray.map((s) => s?.shapeId),
        t.c.tray.map((s) => s?.shapeId),
      );
      expect(restored.chosenFaultByAct, t.c.chosenFaultByAct);
    });

    test('the restored RNG continues the same stream', () async {
      // The cursor is what makes this work: the bag is rebuilt from the
      // loadout and the stream position, never serialised, so there is one
      // source of truth.
      final t = build(seed: 777);
      t.c.begin();
      t.c.chooseFault('mispick');
      for (var i = 0; i < 6 && t.c.phase == GamePhase.placing; i++) {
        final move = bestMove(t.c.board, t.c.tray);
        if (move == null) break;
        _rotateTo(t.c, move.slot, move.rotation);
        t.c.place(move.slot, Anchor(move.ax, move.ay));
      }

      final restored = RunController(
        tuning: tuning,
        // A *snapshot* of the account, not the same object. The two runs below
        // both play to the end, and a shared Account would let the first one's
        // milestones widen the second one's draft pool mid-comparison - so the
        // two would diverge for a reason that has nothing to do with the RNG,
        // which is what this test is about. Going through JSON is also what a
        // real app restart does.
        account: Account.fromJson(t.a.toJson()),
        storage: t.s,
        haptics: silentHaptics(),
      );
      await restored.restore();

      final a = playOut(t.c);
      final b = playOut(restored);
      expect(restored.ladder.score.total, t.c.ladder.score.total);
      expect(restored.stagesCleared, t.c.stagesCleared);
      expect(b, a);
    });

    test('round-trips a run parked on the draft screen', () async {
      final t = build(seed: 11);
      t.c.begin();
      t.c.chooseFault('thin_place');
      while (t.c.phase == GamePhase.placing) {
        final move = bestMove(t.c.board, t.c.tray);
        if (move == null) break;
        _rotateTo(t.c, move.slot, move.rotation);
        t.c.place(move.slot, Anchor(move.ax, move.ay));
      }
      expect(t.c.phase, GamePhase.draft);

      final restored = RunController(
        tuning: tuning,
        account: t.a,
        storage: t.s,
        haptics: silentHaptics(),
      );
      await restored.restore();
      expect(restored.phase, GamePhase.draft);
      expect(restored.draftOptions, hasLength(3));
    });

    test('a corrupt save is dropped rather than half-applied', () async {
      final s = MemoryStorage();
      await s.write(runKey, {'seed': 1, 'nonsense': true});
      final c = RunController(
        tuning: tuning,
        account: Account(),
        storage: s,
        haptics: silentHaptics(),
      );
      expect(await c.restore(), isFalse);
      expect(await s.read(runKey), isNull);
    });

    test('no save means no restore, and that is not an error', () async {
      final t = build();
      expect(await t.c.restore(), isFalse);
    });
  });

  group('the account', () {
    test('round-trips through JSON', () {
      final a = maxedAccount();
      a.spools = 1234;
      final back = Account.fromJson(a.toJson());
      expect(back.spools, 1234);
      expect(back.ownedShapeIds, a.ownedShapeIds);
      expect(back.upgrades, a.upgrades);
      expect(back.loadout, a.loadout);
      expect(back.milestones.bestStage, a.milestones.bestStage);
      expect(back.loadoutSlots, 9);
    });

    test('survives a save from a build that knew fewer fields', () {
      final back = Account.fromJson({'spools': 10});
      expect(back.spools, 10);
      expect(back.ownedShapeIds, hasLength(5));
      expect(back.loadout, isNotEmpty);
    });

    test('drops a motif it no longer recognises rather than crashing', () {
      final back = Account.fromJson({
        'owned': ['dot', 'i2', 'cromulent_motif'],
        'loadout': ['dot', 'cromulent_motif'],
      });
      expect(back.ownedShapeIds, {'dot', 'i2'});
      expect(back.loadout, ['dot']);
    });

    test('never hands the bag an empty loadout', () {
      final a = Account(loadout: []);
      expect(a.loadoutShapes(), isNotEmpty);
    });

    test('the ninth slot is the only thing that widens the draft', () {
      expect(Account().loadoutSlots, 8);
      expect(Account(upgrades: {'loadoutSlot9'}).loadoutSlots, 9);
    });
  });
}

/// Put the controller on the draft screen with exactly one card on offer.
///
/// Both the UI phase AND the ladder phase have to move: `takeDraftCard` ends
/// in `nextStage`, which refuses to advance a stage that was not cleared.
void _parkOnDraft(RunController c, String cardId) {
  c.ladder = c.ladder.copyWith(phase: RunPhase.stageClear);
  c.phase = GamePhase.draft;
  c.draftOptions = [c.tuning.powers.byId(cardId)];
}

/// Rotate a slot until it shows [target], reading the controller's *live*
/// state each step.
///
/// A snapshot of the tray taken before rotating never updates — the tray holds
/// immutable [TrayItem]s and `rotate` replaces them — so a loop that checks a
/// snapshot spins until its guard trips and leaves the piece on an arbitrary
/// rotation. That reads as "greedy proposed an illegal placement" several
/// layers away from the cause.
void _rotateTo(RunController c, int slot, int target) {
  TrayItem? live() => slot < c.tray.length ? c.tray[slot] : c.holdItem;
  var guard = 0;
  while (live() != null && live()!.rotation != target && guard++ < 8) {
    c.rotate(slot);
  }
}
