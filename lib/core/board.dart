/// Board occupancy and the placement algorithms, ported from
/// `reference/ts-core/core/board.ts`.
///
/// ## Knots
///
/// The oracle has no knot concept — knots are the fault mechanic defined in
/// `data/faults.json`, added here rather than in a fault layer because a board
/// with zero knots behaves *identically* to the oracle: the "has at least one
/// ordinary cell" guard is satisfied by any full line when nothing is a knot,
/// and the "do not remove knots" loop removes everything. Port parity is
/// therefore unaffected, and there is exactly one implementation of a line
/// clear rather than two that can drift apart.
library;

import 'dart:typed_data';

import 'shapes.dart';
import 'types.dart';

const int defaultSize = 8;

Board createBoard([int w = defaultSize, int h = defaultSize]) =>
    Board.empty(w, h);

Board cloneBoard(Board b) => Board(b.w, b.h, Uint8List.fromList(b.cells));

bool inBounds(Board b, int x, int y) => x >= 0 && y >= 0 && x < b.w && y < b.h;

int cellAt(Board b, int x, int y) {
  if (!inBounds(b, x, y)) return kEmpty;
  return b.cells[y * b.w + x];
}

int countFilled(Board b) {
  var n = 0;
  for (var i = 0; i < b.cells.length; i++) {
    if (b.cells[i] != kEmpty) n++;
  }
  return n;
}

int countKnots(Board b) {
  var n = 0;
  for (var i = 0; i < b.cells.length; i++) {
    if (isKnot(b.cells[i])) n++;
  }
  return n;
}

int countEmpty(Board b) => b.cells.length - countFilled(b);

/// Can `cells` sit with its origin at `(ax, ay)`?
///
/// Every cell must be in bounds and empty — a shape fits entirely or not at
/// all. There is no gravity and no partial placement (spec §2.3).
bool fits(Board b, ShapeCells cells, int ax, int ay) {
  for (final (cx, cy) in cells) {
    final x = ax + cx;
    final y = ay + cy;
    if (x < 0 || y < 0 || x >= b.w || y >= b.h) return false;
    if (b.cells[y * b.w + x] != kEmpty) return false;
  }
  return true;
}

/// Write `cells` onto a copy of the board.
///
/// Does **not** resolve line clears — use [resolvePlacement] for the real
/// move. Assumes [fits] already passed.
Board place(Board b, ShapeCells cells, int ax, int ay, int fill) {
  final next = cloneBoard(b);
  for (final (cx, cy) in cells) {
    next.cells[(ay + cy) * b.w + (ax + cx)] = fill;
  }
  return next;
}

/// Set a single cell. Used by the fault layer (knot injection) and by tools.
Board setCell(Board b, int x, int y, int value) {
  if (!inBounds(b, x, y)) return b;
  final next = cloneBoard(b);
  next.cells[y * b.w + x] = value;
  return next;
}

/// Which rows and columns are completely full right now.
///
/// A line that is full but contains **no ordinary filled cell** does not count:
/// without that guard a row which has become entirely knots is permanently
/// "full", so it re-clears on every placement and pays the line bonus forever.
/// Floats and The Smash can both reach that state in a long stage.
Clears findClears(Board b, [ClearAxes axes = ClearAxes.both]) {
  final rows = <int>[];
  final cols = <int>[];

  if (axes != ClearAxes.colsOnly) {
    for (var y = 0; y < b.h; y++) {
      var full = true;
      var anyYarn = false;
      for (var x = 0; x < b.w; x++) {
        final v = b.cells[y * b.w + x];
        if (v == kEmpty) {
          full = false;
          break;
        }
        if (!isKnot(v)) anyYarn = true;
      }
      if (full && anyYarn) rows.add(y);
    }
  }

  if (axes != ClearAxes.rowsOnly) {
    for (var x = 0; x < b.w; x++) {
      var full = true;
      var anyYarn = false;
      for (var y = 0; y < b.h; y++) {
        final v = b.cells[y * b.w + x];
        if (v == kEmpty) {
          full = false;
          break;
        }
        if (!isKnot(v)) anyYarn = true;
      }
      if (full && anyYarn) cols.add(x);
    }
  }

  return Clears(rows, cols);
}

/// Empty the given rows and columns.
///
/// Cells simply vanish. Nothing falls, nothing compacts, nothing cascades —
/// that absence is the whole point of the genre, and it is why a row and a
/// column completed by the same piece can both score (spec §2.2).
///
/// Knots survive the clear by design: see the library comment.
Board applyClears(Board b, Clears clears) {
  if (clears.isEmpty) return b;
  final next = cloneBoard(b);
  for (final y in clears.rows) {
    for (var x = 0; x < b.w; x++) {
      final i = y * b.w + x;
      if (!isKnot(next.cells[i])) next.cells[i] = kEmpty;
    }
  }
  for (final x in clears.cols) {
    for (var y = 0; y < b.h; y++) {
      final i = y * b.w + x;
      if (!isKnot(next.cells[i])) next.cells[i] = kEmpty;
    }
  }
  return next;
}

/// The full move: land the piece, then remove everything it completed.
PlacementResult resolvePlacement(
  Board b,
  ShapeCells cells,
  int ax,
  int ay,
  int fill, {
  ClearAxes axes = ClearAxes.both,
}) {
  final landed = place(b, cells, ax, ay, fill);
  final clears = findClears(landed, axes);
  return PlacementResult(
    board: applyClears(landed, clears),
    clears: clears,
  );
}

/// What *would* clear if the piece landed here — drives the drag-time preview.
///
/// This is the most important feedback in the game: highlighting the completing
/// rows and columns along their full length is how a player plans a multi-line
/// clear (spec §2.5). Only called when the snap target changes, not per frame,
/// so the clone is cheap.
Clears previewClears(
  Board b,
  ShapeCells cells,
  int ax,
  int ay, {
  ClearAxes axes = ClearAxes.both,
}) =>
    findClears(place(b, cells, ax, ay, 1), axes);

/// Every origin where this rotation fits.
List<Anchor> legalOrigins(Board b, ShapeCells cells) {
  final e = extent(cells);
  final out = <Anchor>[];
  for (var ay = 0; ay <= b.h - e.h; ay++) {
    for (var ax = 0; ax <= b.w - e.w; ax++) {
      if (fits(b, cells, ax, ay)) out.add(Anchor(ax, ay));
    }
  }
  return out;
}

/// Is there any legal move left, across every rotation of every tray shape?
///
/// False means the run is over — the only hard fail state on the board itself,
/// and the one the theme calls "the shed won't open".
///
/// [allowRotation] is false during the Fixed Heddles fault, which disables
/// rotation for a stage: a jam check that considered rotations the player
/// cannot reach would keep a dead board alive.
bool hasAnyLegalMove(
  Board b,
  List<Shape> shapes, {
  bool allowRotation = true,
  List<int>? rotations,
}) {
  for (var i = 0; i < shapes.length; i++) {
    final s = shapes[i];
    final forms = allowRotation
        ? s.rotations
        : [s.rotations[(rotations != null && i < rotations.length
                ? rotations[i]
                : 0) %
            s.rotations.length]];
    for (final form in forms) {
      final e = extent(form);
      for (var ay = 0; ay <= b.h - e.h; ay++) {
        for (var ax = 0; ax <= b.w - e.w; ax++) {
          if (fits(b, form, ax, ay)) return true;
        }
      }
    }
  }
  return false;
}

/// Shrink the board to `w × h`, discarding the cells outside it.
///
/// Tight Reed (`data/faults.json`, act 3) makes the board 7×7 for one stage.
/// The board is genuinely resized rather than ringed with knots: a ring of
/// knots would be an all-knot line and would need the guard, and 7-long lines
/// are the clearer read. Cells in the discarded row and column are lost, which
/// is thematically the reed tightening and the cloth narrowing.
Board resizeBoard(Board b, int w, int h) {
  final next = Board.empty(w, h);
  for (var y = 0; y < h && y < b.h; y++) {
    for (var x = 0; x < w && x < b.w; x++) {
      next.cells[y * w + x] = b.cells[y * b.w + x];
    }
  }
  return next;
}

/// Build a board from ASCII art: `#` ordinary filled, `o` a knot, else empty.
Board boardFromArt(List<String> art) {
  final h = art.length;
  final w = art.first.length;
  final b = createBoard(w, h);
  for (var y = 0; y < h; y++) {
    final row = art[y];
    if (row.length != w) throw ArgumentError('ragged board art');
    for (var x = 0; x < w; x++) {
      if (row[x] == '#') {
        b.cells[y * w + x] = 1;
      } else if (row[x] == 'o') {
        b.cells[y * w + x] = kKnot;
      }
    }
  }
  return b;
}

/// Inverse of [boardFromArt], for readable test failures.
List<String> boardToArt(Board b) {
  final rows = <String>[];
  for (var y = 0; y < b.h; y++) {
    final sb = StringBuffer();
    for (var x = 0; x < b.w; x++) {
      final v = b.cells[y * b.w + x];
      sb.write(v == kEmpty ? '.' : (isKnot(v) ? 'o' : '#'));
    }
    rows.add(sb.toString());
  }
  return rows;
}
