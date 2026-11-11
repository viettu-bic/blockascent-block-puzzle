/// Shared screen geometry.
///
/// The board is **above** the tray, always — the thumb drags upward out of the
/// tray so the hand never covers the board (spec §8). Portrait only.
///
/// This is the single source of truth for where everything is: the painter
/// draws from it and the drag controller hit-tests and snaps from it. Two
/// copies of this arithmetic that disagree by a pixel is a game that feels
/// broken in a way nobody can describe.
library;

import 'dart:math' as math;
import 'dart:ui';

class Layout {
  const Layout({
    required this.size,
    required this.cell,
    required this.board,
    required this.gridW,
    required this.gridH,
    required this.tray,
    required this.slots,
  });

  /// The canvas this layout was computed for.
  final Size size;

  /// Side of one board cell, in logical pixels. ~42 at 375pt (spec §8).
  final double cell;

  /// The board rectangle. Square: `board.width == cell * gridW`.
  final Rect board;

  final int gridW;
  final int gridH;

  /// The whole tray strip — the bottom thumb zone.
  final Rect tray;

  /// One rectangle per tray slot, left to right.
  final List<Rect> slots;

  /// Board-space coordinate of a cell's top-left corner.
  Offset originOf(int x, int y) =>
      Offset(board.left + x * cell, board.top + y * cell);

  Rect cellRect(int x, int y) => Rect.fromLTWH(
    board.left + x * cell,
    board.top + y * cell,
    cell,
    cell,
  );
}

/// Height reserved for the tray — the bottom ~150px thumb zone.
const double trayHeight = 150.0;

/// Gap between the board and the tray.
const double boardTrayGap = 14.0;

/// Breathing room at the canvas edges.
const double canvasMargin = 14.0;

/// Compute the layout for a canvas of [width] × [height] holding a
/// [gridW] × [gridH] board.
///
/// The cell size is whichever of the two axes is tighter, so the board is
/// always square and always fits. On a tall phone the width binds and the
/// leftover height becomes extra space above the board; on a short one the
/// height binds and the board is narrower than the screen.
Layout computeLayout(
  double width,
  double height,
  int gridW,
  int gridH, {
  int slotCount = 3,
  double trayH = trayHeight,
}) {
  final availableW = math.max(1.0, width - canvasMargin * 2);
  final availableH = math.max(
    1.0,
    height - trayH - boardTrayGap - canvasMargin * 2,
  );
  final cell = math.min(availableW / gridW, availableH / gridH);

  final boardW = cell * gridW;
  final boardH = cell * gridH;
  final boardLeft = (width - boardW) / 2;

  final tray = Rect.fromLTWH(0, height - trayH, width, trayH);

  // Sit the board directly above the tray and push any leftover height to the
  // TOP, where the HUD lives.
  //
  // Centring the board in the space instead would open a dead gap between the
  // board and the tray, and that gap is exactly the distance a thumb has to
  // travel: the piece floats `liftOffset` above the finger, so the bottom row
  // is only reachable with a thumb still inside the tray if the board's bottom
  // edge is within that offset of it. Widen the gap and the bottom row becomes
  // the hardest cell on the board to fill.
  final boardTop = math.max(
    canvasMargin,
    tray.top - boardTrayGap - boardH,
  );

  // Slots split the tray evenly, inset so a finger landing between two never
  // lifts the wrong piece.
  const slotGap = 10.0;
  final slotW = (width - canvasMargin * 2 - slotGap * (slotCount - 1)) /
      slotCount;
  final slotH = math.min(trayH - 28.0, slotW);
  final slotTop = tray.top + (trayH - slotH) / 2;
  final slots = [
    for (var i = 0; i < slotCount; i++)
      Rect.fromLTWH(
        canvasMargin + i * (slotW + slotGap),
        slotTop,
        slotW,
        slotH,
      ),
  ];

  return Layout(
    size: Size(width, height),
    cell: cell,
    board: Rect.fromLTWH(boardLeft, boardTop, boardW, boardH),
    gridW: gridW,
    gridH: gridH,
    tray: tray,
    slots: slots,
  );
}

bool hitRect(Rect r, double x, double y) =>
    x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;

/// Do two rectangles share any area?
///
/// Used to decide whether the held piece addresses the board at all. Written
/// out rather than using `Rect.overlaps` because the drag rule wants *touching
/// counts*: a piece whose edge is flush with the board's should still produce
/// a ghost.
bool rectsOverlap(Rect a, Rect b) =>
    a.left <= b.right &&
    a.right >= b.left &&
    a.top <= b.bottom &&
    a.bottom >= b.top;
