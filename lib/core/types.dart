/// Core data model.
///
/// Nothing in `lib/core` may import `dart:ui`, `package:flutter` or any
/// platform API (spec §3). It is a pure, deterministic, seeded state machine,
/// and that constraint is what buys daily challenges, replays,
/// server-verifiable scores and the simulation harness — all for free, later.
library;

import 'dart:typed_data';

/// A cell offset within a shape, or an absolute board coordinate.
typedef Coord = (int x, int y);

/// The filled cells of one rotation of a shape, normalised so min x and min y
/// are both 0.
typedef ShapeCells = List<Coord>;

/// The empty cell.
const int kEmpty = 0;

/// Cell values at or above this are *knots* — the fault mechanic from
/// `data/faults.json`.
///
/// A knot is a filled cell that **counts** toward completing a row or column
/// but is **not** removed when that line clears. Blocking the clear instead
/// would make a single knot kill a row and a column outright, turning the
/// fault into a coin flip; counting-but-persisting makes it a creeping tax on
/// board space — obstructive, survivable, and it still rewards clearing around
/// it.
const int kKnot = 100;

bool isKnot(int cell) => cell >= kKnot;

/// Ordinary yarn: a filled cell that is not a knot.
bool isYarn(int cell) => cell != kEmpty && cell < kKnot;

/// Board occupancy.
///
/// `cells[y * w + x]` is 0 for empty, [kKnot] for a knot, otherwise the
/// `cellCount` of the shape that filled it (1..9) — which is all the renderer
/// needs for colour. Colour keys off **cell count, not shape identity**: that
/// is both the visual design (size reads as a yarn weight) and the trade-dress
/// defence (spec §11).
///
/// An 8×8 board is 64 bytes. Copy it freely.
class Board {
  Board(this.w, this.h, this.cells);

  Board.empty(this.w, this.h) : cells = Uint8List(w * h);

  final int w;
  final int h;
  final Uint8List cells;

  int get length => cells.length;
}

/// Row and column indices that are completely full.
class Clears {
  const Clears(this.rows, this.cols);

  const Clears.none() : rows = const [], cols = const [];

  final List<int> rows;
  final List<int> cols;

  int get lines => rows.length + cols.length;
  bool get isEmpty => rows.isEmpty && cols.isEmpty;
  bool get isNotEmpty => !isEmpty;

  @override
  String toString() => 'Clears(rows: $rows, cols: $cols)';

  @override
  bool operator ==(Object other) =>
      other is Clears &&
      _sameList(rows, other.rows) &&
      _sameList(cols, other.cols);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(rows),
    Object.hashAll(cols),
  );

  static bool _sameList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Which axes may clear this stage.
///
/// Reediness (`data/faults.json`, act 1) makes only columns clear; completed
/// rows do nothing. The default, [ClearAxes.both], is the game.
enum ClearAxes { both, rowsOnly, colsOnly }

class PlacementResult {
  const PlacementResult({
    required this.board,
    required this.clears,
  });

  /// Board after the piece landed **and** any completed lines were removed.
  final Board board;
  final Clears clears;

  /// Total lines cleared — `clears.rows.length + clears.cols.length`.
  int get lines => clears.lines;
}

class Shape {
  const Shape({
    required this.id,
    required this.tier,
    required this.cellCount,
    required this.rotations,
  });

  final String id;

  /// 1..4 — the meta-progression unlock tier.
  final int tier;

  /// Number of filled cells. Also the render colour key.
  final int cellCount;

  /// **Distinct** rotations only: a 2×2 square has 1, an I-piece 2, an L 4.
  final List<ShapeCells> rotations;

  @override
  String toString() => 'Shape($id)';
}

/// One tray slot: a shape plus which of its rotations is currently showing.
class TrayItem {
  const TrayItem(this.shapeId, [this.rotation = 0]);

  final String shapeId;
  final int rotation;

  TrayItem withRotation(int r) => TrayItem(shapeId, r);

  @override
  String toString() => 'TrayItem($shapeId@$rotation)';

  @override
  bool operator ==(Object other) =>
      other is TrayItem &&
      other.shapeId == shapeId &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(shapeId, rotation);
}

/// A board-space origin for a held piece.
class Anchor {
  const Anchor(this.x, this.y);

  final int x;
  final int y;

  @override
  String toString() => 'Anchor($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is Anchor && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
