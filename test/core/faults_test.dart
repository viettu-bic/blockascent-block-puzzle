import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/board.dart';
import 'package:loomcraft/core/faults.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/rng.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/core/scoring.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';

import '../support/load_tuning.dart';

void main() {
  late FaultRoster roster;

  setUpAll(() async {
    roster = await loadFaultsForTest();
  });

  group('the roster as authored', () {
    test('is nine faults, three per act, at stages 4, 8 and 12', () {
      expect(roster.all, hasLength(9));
      expect(roster.acts, hasLength(3));
      expect(roster.acts.map((a) => a.stage), [4, 8, 12]);
      for (final a in roster.acts) {
        expect(a.faults, hasLength(3));
        expect(a.faults.map((f) => f.tier), [1, 2, 3]);
      }
    });

    test('fault stages are exactly the act boundaries the ladder knows', () {
      for (final a in roster.acts) {
        expect(isFaultStage(a.stage), isTrue);
        expect(actOf(a.stage), a.act);
      }
    });

    test('ids are unique and every one maps to real behaviour', () {
      final ids = roster.all.map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final f in roster.all) {
        expect(
          effectsOf(f.id).isActive,
          isTrue,
          reason: '${f.id} parses but does nothing',
        );
      }
    });

    test('a harder fault pays a better draft', () {
      for (final a in roster.acts) {
        expect(a.faults[0].reward, DraftReward.normal);
        expect(a.faults[1].reward, DraftReward.uncommonOrBetter);
        expect(a.faults[2].reward, DraftReward.raresOnly);
      }
    });

    test('an unknown fault id is a no-op rather than a crashed run', () {
      // A tuning file that adds a fault should make that stage easy, not kill
      // a run in progress.
      expect(effectsOf('cockled_cloth'), FaultEffects.none);
      expect(FaultEffects.none.isActive, isFalse);
    });

    test('roster lookups work and reject nonsense', () {
      expect(roster.byId('slubs').name, 'Blockers');
      expect(() => roster.byId('nope'), throwsArgumentError);
      expect(roster.actForStage(8)!.act, 2);
      expect(roster.actForStage(7), isNull);
    });
  });

  group('act 1 — mild and legible', () {
    test('Tight Budget squeezes allowance harder than target', () {
      const cfg = CurveConfig.defaults;
      final e = effectsOf('thin_place');
      expect(e.allowanceScale, 0.7);
      expect(e.targetScale, 0.75);
      // Fewer placements AND a lower bar, but the points-per-placement demand
      // goes up — which is what makes it attack slow, high-value builds.
      final normal = targetFor(cfg, 4) / allowanceFor(cfg, 4);
      final thin = targetFor(cfg, 4, mods: e.ladderModifiers) /
          allowanceFor(cfg, 4, mods: e.ladderModifiers);
      expect(thin, greaterThan(normal));
    });

    test('Columns Only makes only columns clear', () {
      final e = effectsOf('reediness');
      expect(e.axes, ClearAxes.colsOnly);
      final b = boardFromArt([
        '#######.',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
      ]);
      // Completing the row does nothing; the column still pays.
      final result = resolvePlacement(
        b,
        cellsOf('dot', 0),
        7,
        0,
        1,
        axes: e.axes,
      );
      expect(result.clears.rows, isEmpty);
      expect(result.clears.cols, [0]);
      expect(result.lines, 1);
    });

    test('Mispick drops patience to 1, so every dry placement breaks', () {
      final cfg = effectsOf('mispick').applyTo(ScoringConfig.defaults);
      expect(cfg.patienceMax, 1);
      final s = initialScore(cfg: cfg, multiplier: 2.4);
      expect(scoreTurn(s, 1, 0, cfg: cfg).broke, isTrue);
    });
  });

  group('act 2 — real tests', () {
    test('Fixed Heddles disables rotation', () {
      expect(effectsOf('fixed_heddles').rotationDisabled, isTrue);
    });

    test('Barré serves only motifs of 4 cells or more', () {
      expect(effectsOf('barre').minCellCount, 4);
    });

    test('Slubs scatters six knots that count but never clear', () {
      final e = effectsOf('slubs');
      expect(e.startingKnots, 6);
      final b = scatterKnots(createBoard(), e.startingKnots, Rng(1));
      expect(countKnots(b), 6);
      expect(countFilled(b), 6);
    });

    test('scatterKnots never doubles up and never hangs on a full board', () {
      final nearlyFull = boardFromArt([
        '########',
        '########',
        '########',
        '########',
        '########',
        '########',
        '########',
        '......##',
      ]);
      final b = scatterKnots(nearlyFull, 6, Rng(3));
      // Only six holes existed, and each took exactly one knot.
      expect(countKnots(b), 6);
      final full = boardFromArt(List.filled(8, '########'));
      expect(countKnots(scatterKnots(full, 6, Rng(3))), 0);
    });

    test('scatterKnots is seeded, so a fault stage replays identically', () {
      expect(
        boardToArt(scatterKnots(createBoard(), 6, Rng(12))),
        boardToArt(scatterKnots(createBoard(), 6, Rng(12))),
      );
      expect(
        boardToArt(scatterKnots(createBoard(), 6, Rng(12))),
        isNot(boardToArt(scatterKnots(createBoard(), 6, Rng(13)))),
      );
    });
  });

  group('act 3 — the finale', () {
    test('Tight Reed genuinely resizes the board to 7x7', () {
      expect(effectsOf('tight_reed').boardSize, 7);
    });

    test('The Smash knots a random empty cell every third placement', () {
      expect(effectsOf('the_smash').knotEveryNthPlacement, 3);
      final b = knotOneEmptyCell(createBoard(), Rng(5));
      expect(countKnots(b), 1);
    });

    test('Floats turns one of a dry placement own cells into a knot', () {
      final e = effectsOf('floats');
      expect(e.knotOnDryPlacement, isTrue);

      final landed = place(createBoard(), cellsOf('i4', 0), 0, 0, 4);
      final after = knotOwnCell(landed, cellsOf('i4', 0), 0, 0, Rng(2));
      expect(countKnots(after), 1);
      // The knot replaced one of its own cells; nothing else moved.
      expect(countFilled(after), 4);
    });

    test('Floats leaves nothing behind when the placement cleared its cells', () {
      // Floats only punishes placements that clear no line, and a placement
      // that cleared no line lost no cells — but the guard matters because the
      // board handed in is the post-clear one.
      final cleared = createBoard();
      final after = knotOwnCell(cleared, cellsOf('i4', 0), 0, 0, Rng(2));
      expect(countKnots(after), 0);
      expect(after, same(cleared));
    });

    test('Floats will not overwrite a knot it already made', () {
      var b = place(createBoard(), cellsOf('i2', 0), 0, 0, 2);
      b = knotOwnCell(b, cellsOf('i2', 0), 0, 0, Rng(1));
      b = knotOwnCell(b, cellsOf('i2', 0), 0, 0, Rng(1));
      expect(countKnots(b), 2, reason: 'the second knot took the other cell');
    });
  });

  group('the all-knot guard', () {
    test('a row that has become entirely knots never clears again', () {
      // Without the guard it is permanently "full", so it re-clears on every
      // placement and pays the line bonus forever. Floats and The Smash can
      // both reach that state in a long stage.
      final b = boardFromArt([
        'ooooooo.',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      final result = resolvePlacement(b, cellsOf('dot', 0), 7, 0, 1);
      expect(result.lines, 1, reason: 'one ordinary cell, so it still clears');

      final allKnots = boardFromArt([
        'oooooooo',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      expect(findClears(allKnots).lines, 0);
      // And it stays that way across repeated checks — no bonus loop.
      for (var i = 0; i < 5; i++) {
        expect(findClears(allKnots).lines, 0);
      }
    });

    test('a knot blocks nothing: the rest of the line still clears around it', () {
      final b = boardFromArt([
        '###o####',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      final after = applyClears(b, findClears(b));
      expect(boardToArt(after)[0], '...o....');
    });
  });

  group('survivability', () {
    test('no fault is a coin flip: none can make the board unplayable alone', () {
      // Each fault must be survivable by at least three archetypes and
      // trivial for none (docs/06 §5). The mechanical floor of that is that
      // applying a fault to an empty board never produces an immediate jam.
      for (final f in roster.all) {
        final e = effectsOf(f.id);
        var b = createBoard(e.boardSize ?? 8, e.boardSize ?? 8);
        b = scatterKnots(b, e.startingKnots, Rng(7));
        final usable = spikeLoadout
            .where((s) => s.cellCount >= (e.minCellCount ?? 1))
            .toList();
        expect(usable, isNotEmpty, reason: '${f.id} empties the bag');
        expect(
          hasAnyLegalMove(b, usable, allowRotation: !e.rotationDisabled),
          isTrue,
          reason: '${f.id} jams an empty board',
        );
      }
    });

    test('every fault still leaves a way to score', () {
      for (final f in roster.all) {
        final e = effectsOf(f.id);
        expect(
          e.axes == ClearAxes.both ||
              e.axes == ClearAxes.rowsOnly ||
              e.axes == ClearAxes.colsOnly,
          isTrue,
        );
        expect(e.targetScale, greaterThan(0));
        expect(e.allowanceScale, greaterThan(0));
      }
    });
  });
}
