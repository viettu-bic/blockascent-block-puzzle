import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/board.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';

/// Ported from `reference/ts-tests/board.test.ts`, plus the knot cases for the
/// fault mechanic in `data/faults.json`.
void main() {
  final dot = cellsOf('dot', 0);
  final o2 = cellsOf('o2', 0);
  final i4 = cellsOf('i4', 0);

  group('fits', () {
    test('accepts an empty in-bounds placement', () {
      final b = createBoard();
      expect(fits(b, o2, 0, 0), isTrue);
      expect(fits(b, o2, 6, 6), isTrue);
    });

    test('rejects anything hanging off an edge', () {
      final b = createBoard();
      expect(fits(b, o2, 7, 0), isFalse);
      expect(fits(b, o2, 0, 7), isFalse);
      expect(fits(b, dot, -1, 0), isFalse);
      expect(fits(b, dot, 8, 0), isFalse);
    });

    test('rejects overlap — a shape fits entirely or not at all', () {
      final b = place(createBoard(), dot, 1, 1, 1);
      expect(fits(b, o2, 0, 0), isFalse);
      expect(fits(b, o2, 2, 2), isTrue);
    });

    test('rejects a 2-wide shape in a 1-wide gap', () {
      final b = boardFromArt([
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '#.#.#.#.',
      ]);
      expect(fits(b, o2, 1, 6), isFalse);
      expect(fits(b, dot, 1, 7), isTrue);
    });

    test('treats a knot as occupied', () {
      final b = boardFromArt([
        'o.......',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      expect(fits(b, dot, 0, 0), isFalse);
      expect(fits(b, dot, 1, 0), isTrue);
    });
  });

  group('place', () {
    test('writes the fill value and leaves the source board untouched', () {
      final a = createBoard();
      final b = place(a, o2, 2, 3, 4);
      expect(cellAt(b, 2, 3), 4);
      expect(cellAt(b, 3, 4), 4);
      expect(countFilled(b), 4);
      expect(countFilled(a), 0);
    });

    test('cellAt is 0 outside the board rather than throwing', () {
      final b = createBoard();
      expect(cellAt(b, -1, 0), 0);
      expect(cellAt(b, 0, 99), 0);
    });
  });

  group('findClears', () {
    test('finds full rows and full columns', () {
      final b = boardFromArt([
        '########',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
      ]);
      expect(findClears(b), const Clears([0], [0]));
    });

    test('finds nothing on a board with a hole in every line', () {
      final b = boardFromArt([
        '#######.',
        '#######.',
        '#######.',
        '#######.',
        '#######.',
        '#######.',
        '#######.',
        '........',
      ]);
      expect(findClears(b), const Clears.none());
    });

    test('counts a knot toward completing a line', () {
      final b = boardFromArt([
        '#######o',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      expect(findClears(b).rows, [0]);
    });

    test('refuses to clear a line made entirely of knots', () {
      // Without this guard an all-knot row is permanently "full", so it
      // re-clears on every placement and pays the line bonus forever. Floats
      // and The Smash can both reach that state in a long stage.
      final b = boardFromArt([
        'oooooooo',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      expect(findClears(b), const Clears.none());
    });

    test('Columns Only clears columns only; full rows do nothing', () {
      final b = boardFromArt([
        '########',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
        '#.......',
      ]);
      expect(findClears(b, ClearAxes.colsOnly), const Clears([], [0]));
      expect(findClears(b, ClearAxes.rowsOnly), const Clears([0], []));
    });
  });

  group('applyClears', () {
    test('empties lines without any gravity, compaction or cascade', () {
      final b = boardFromArt([
        '########',
        '#.......',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      final after = applyClears(b, findClears(b));

      // Row 0 goes. The lone cell at (0,1) stays exactly where it was.
      expect(boardToArt(after)[0], '........');
      expect(cellAt(after, 0, 1), 1);
      expect(countFilled(after), 1);
    });

    test('returns the same board instance when nothing clears', () {
      final b = createBoard();
      expect(applyClears(b, const Clears.none()), same(b));
    });

    test('leaves knots behind when the line they completed clears', () {
      final b = boardFromArt([
        '######o#',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      final after = applyClears(b, findClears(b));
      expect(boardToArt(after)[0], '......o.');
      expect(countKnots(after), 1);
    });
  });

  group('resolvePlacement', () {
    test('clears a row and a column completed by the same piece', () {
      final b = boardFromArt([
        '#######.',
        '.......#',
        '.......#',
        '.......#',
        '.......#',
        '.......#',
        '.......#',
        '.......#',
      ]);
      final result = resolvePlacement(b, dot, 7, 0, 1);

      expect(result.clears, const Clears([0], [7]));
      expect(result.lines, 2);
      // Both lines were the only occupied cells, so the board comes back empty.
      expect(countFilled(result.board), 0);
    });

    test('leaves the piece on the board when nothing completes', () {
      final result = resolvePlacement(createBoard(), i4, 0, 0, 4);
      expect(result.lines, 0);
      expect(countFilled(result.board), 4);
      expect(cellAt(result.board, 3, 0), 4);
    });
  });

  group('previewClears', () {
    test('reports what would clear without mutating the board', () {
      final b = boardFromArt([
        '....####',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
      ]);
      expect(previewClears(b, i4, 0, 0), const Clears([0], []));
      expect(countFilled(b), 4);
    });
  });

  group('hasAnyLegalMove', () {
    test('is false on a full board', () {
      final b = boardFromArt(List.filled(8, '########'));
      expect(hasAnyLegalMove(b, [shape('dot')]), isFalse);
    });

    test('is true when a single hole can take a dot', () {
      final art = List.filled(8, '########');
      art[4] = '###.####';
      final b = boardFromArt(art);
      expect(hasAnyLegalMove(b, [shape('dot')]), isTrue);
      expect(hasAnyLegalMove(b, [shape('o2')]), isFalse);
    });

    test('considers every rotation, so an I4 fits a vertical corridor', () {
      final b = boardFromArt([
        '#######.',
        '#######.',
        '#######.',
        '#######.',
        '########',
        '########',
        '########',
        '########',
      ]);
      // No horizontal run of 4 anywhere, but column 7 has a vertical one.
      expect(hasAnyLegalMove(b, [shape('i4')]), isTrue);
    });

    test('ignores rotations the player cannot reach under Fixed Heddles', () {
      final b = boardFromArt([
        '#######.',
        '#######.',
        '#######.',
        '#######.',
        '########',
        '########',
        '########',
        '########',
      ]);
      // Rotation is disabled, and the held form is horizontal: dead board.
      expect(
        hasAnyLegalMove(b, [shape('i4')], allowRotation: false, rotations: [0]),
        isFalse,
      );
      expect(
        hasAnyLegalMove(b, [shape('i4')], allowRotation: false, rotations: [1]),
        isTrue,
      );
    });

    test('is false for an empty shape list', () {
      expect(hasAnyLegalMove(createBoard(), []), isFalse);
    });
  });

  group('legalOrigins', () {
    test('enumerates every origin on an empty board', () {
      final b = createBoard();
      expect(legalOrigins(b, dot), hasLength(64));
      expect(legalOrigins(b, o2), hasLength(49));
      expect(legalOrigins(b, i4), hasLength(5 * 8));
    });
  });

  group('resizeBoard', () {
    test('Tight Reed narrows the cloth and discards the outer row/column', () {
      final b = boardFromArt([
        '.......#',
        '........',
        '........',
        '........',
        '........',
        '........',
        '........',
        '#.......',
      ]);
      final tight = resizeBoard(b, 7, 7);
      expect(tight.w, 7);
      expect(tight.h, 7);
      // Both filled cells lived in the discarded column 7 / row 7.
      expect(countFilled(tight), 0);
      // A 7-long row is now a full line.
      final full = boardFromArt(['#######', ...List.filled(6, '.......')]);
      expect(findClears(full).rows, [0]);
    });
  });

  group('art round-trip', () {
    test('boardToArt is the inverse of boardFromArt', () {
      const art = [
        '#.o.....',
        '........',
        '...##...',
        '........',
        '........',
        '........',
        'o.......',
        '.......#',
      ];
      expect(boardToArt(boardFromArt(art)), art);
    });

    test('rejects ragged art', () {
      expect(() => boardFromArt(['##', '#']), throwsArgumentError);
    });
  });

  group('setCell', () {
    test('writes one cell immutably and ignores out-of-bounds', () {
      final b = createBoard();
      final withKnot = setCell(b, 3, 3, kKnot);
      expect(cellAt(withKnot, 3, 3), kKnot);
      expect(countFilled(b), 0);
      expect(setCell(b, -1, 0, kKnot), same(b));
    });
  });
}
