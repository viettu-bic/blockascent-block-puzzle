import 'package:loomcraft/core/board.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';

/// A deliberately simple greedy player, ported from
/// `reference/ts-tests/support/greedy.ts`.
///
/// It is not meant to play well — it is meant to play *consistently*, so that
/// a change to the tuning numbers shows up as a change in how far runs get.
/// Treat its results as a floor on human performance, not a prediction of it:
/// it has no lookahead, so it cannot set up the multi-line clears a real
/// player lives on.
///
/// **The iteration order is load-bearing.** Candidates are scored with a
/// strictly-greater comparison, so ties go to whichever is visited first. The
/// loops below must stay in the oracle's order — slot, then rotation, then ay,
/// then ax — or the two implementations pick different equally-good moves and
/// the histograms diverge for a reason that has nothing to do with the RNG.
class Move {
  const Move({
    required this.slot,
    required this.rotation,
    required this.ax,
    required this.ay,
    required this.cells,
    required this.lines,
  });

  final int slot;
  final int rotation;
  final int ax;
  final int ay;
  final ShapeCells cells;
  final int lines;
}

/// How much of this piece's perimeter touches a wall or an existing block.
int contact(Board board, ShapeCells cells, int ax, int ay) {
  final own = <int>{for (final (cx, cy) in cells) (ay + cy) * board.w + (ax + cx)};
  var n = 0;
  const deltas = <Coord>[(1, 0), (-1, 0), (0, 1), (0, -1)];
  for (final (cx, cy) in cells) {
    final x = ax + cx;
    final y = ay + cy;
    for (final (dx, dy) in deltas) {
      final nx = x + dx;
      final ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= board.w || ny >= board.h) {
        n++;
      } else if (!own.contains(ny * board.w + nx) && cellAt(board, nx, ny) != 0) {
        n++;
      }
    }
  }
  return n;
}

/// Clears dominate; after that, pack tightly against what is already there and
/// leave as little on the board as possible.
/// [allowRotation] is false under the Fixed Heddles fault. The oracle has no
/// faults, so it defaults to true and port parity is untouched; without it the
/// auto-player picks a rotation it cannot reach and the placement is refused.
Move? bestMove(
  Board board,
  List<TrayItem?> tray, {
  bool allowRotation = true,
}) {
  Move? best;
  var bestScore = double.negativeInfinity;

  for (var slot = 0; slot < tray.length; slot++) {
    final item = tray[slot];
    if (item == null) continue;
    final s = shape(item.shapeId);

    final forms = allowRotation
        ? [for (var r = 0; r < s.rotations.length; r++) r]
        : [item.rotation % s.rotations.length];
    for (final rotation in forms) {
      final cells = cellsOf(item.shapeId, rotation);
      final e = extent(cells);
      for (var ay = 0; ay <= board.h - e.h; ay++) {
        for (var ax = 0; ax <= board.w - e.w; ax++) {
          if (!fits(board, cells, ax, ay)) continue;
          final result = resolvePlacement(board, cells, ax, ay, cells.length);
          final score = result.lines * 10000 +
              contact(board, cells, ax, ay) * 30 -
              countFilled(result.board) * 4;
          if (score > bestScore) {
            bestScore = score.toDouble();
            best = Move(
              slot: slot,
              rotation: rotation,
              ax: ax,
              ay: ay,
              cells: cells,
              lines: result.lines,
            );
          }
        }
      }
    }
  }

  return best;
}
