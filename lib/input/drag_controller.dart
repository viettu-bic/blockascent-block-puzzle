/// The drag controller, ported from `reference/ts-core/dragController.ts`.
///
/// This is the file that decides whether the game is playable, so the rules it
/// encodes are spelled out rather than tuned by feel alone (spec §7):
///
///  1. The piece renders [liftOffset] px **above** the finger. The finger must
///     never cover the piece being placed — this is the most common failure in
///     clones of this genre.
///  2. Snapping is computed from the **offset piece**, never from the touch
///     point.
///  3. Sticky snap: once a target is chosen it is held until the piece drifts
///     more than [stickyCells] away, which kills ghost flicker at cell borders.
///  4. An invalid release never consumes the piece.
///  5. Tap (small movement, short duration) rotates instead of placing.
///
/// Budget real time here and **test on a physical device early** — a mouse
/// will lie to you about every rule above.
library;

import 'dart:ui' show Offset, Rect;

import 'package:flutter/gestures.dart'
    show PointerCancelEvent, PointerDownEvent, PointerMoveEvent, PointerUpEvent;

import '../core/shapes.dart';
import '../core/types.dart';
import '../render/layout.dart';

/// Logical px the held piece floats above the finger.
const double liftOffset = 56.0;

/// Movement under this (logical px) still counts as a tap.
const double tapMovePx = 10.0;

/// Duration under this (ms) still counts as a tap.
const int tapMs = 250;

/// Hysteresis for sticky snap, in cells.
const double stickyCells = 0.6;

/// Where would this piece land, given the floating piece centre?
///
/// Pure, so the snap rule — the thing the drag feel actually rests on — is
/// unit-testable without a widget tree or a device.
///
/// Returns null when the held piece does not overlap the board at all. Because
/// the piece floats above the finger, a thumb resting in the tray can still
/// address the bottom row — which is the point.
Anchor? resolveAnchor(
  Layout layout,
  ShapeCells cells,
  double cx,
  double cy,
  Anchor? previous,
) {
  final cell = layout.cell;
  final e = extent(cells);

  final pieceW = e.w * cell;
  final pieceH = e.h * cell;
  final tlx = cx - pieceW / 2;
  final tly = cy - pieceH / 2;

  if (!rectsOverlap(
    Rect.fromLTWH(tlx, tly, pieceW, pieceH),
    layout.board,
  )) {
    return null;
  }

  final fx = (tlx - layout.board.left) / cell;
  final fy = (tly - layout.board.top) / cell;

  final maxX = layout.gridW - e.w;
  final maxY = layout.gridH - e.h;
  if (maxX < 0 || maxY < 0) return null;

  // Sticky snap: hold the previous target while the piece is still near it.
  // Without this the ghost flickers at cell borders and the game feels cheap.
  if (previous != null &&
      (fx - previous.x).abs() < stickyCells &&
      (fy - previous.y).abs() < stickyCells) {
    return previous;
  }

  return Anchor(
    fx.round().clamp(0, maxX),
    fy.round().clamp(0, maxY),
  );
}

/// Which tray slot is under this canvas-local point, if any.
int? traySlotAt(Layout layout, double x, double y) {
  for (var i = 0; i < layout.slots.length; i++) {
    if (hitRect(layout.slots[i], x, y)) return i;
  }
  return null;
}

/// The floating piece centre for a touch point: [liftOffset] above the finger.
Offset floatCentre(Offset touch) => Offset(touch.dx, touch.dy - liftOffset);

/// What the controller needs to know about the game it is driving.
class DragDeps {
  const DragDeps({required this.layout, required this.pieceCells});

  final Layout Function() layout;

  /// Cells of the piece in a tray slot, or null when the slot is spent.
  final ShapeCells? Function(int slot) pieceCells;
}

class DragHandlers {
  const DragHandlers({
    required this.onLift,
    required this.onUpdate,
    required this.onCommit,
    required this.onTap,
    required this.onCancel,
  });

  final void Function(int slot) onLift;
  final void Function(int slot, Offset centre, Anchor? anchor) onUpdate;

  /// Released over the board. A null anchor means nowhere valid — **do not
  /// consume the piece.**
  final void Function(int slot, Anchor? anchor) onCommit;

  /// Released in place: rotate this slot.
  final void Function(int slot) onTap;

  /// Interrupted (incoming call, notification pull-down). Put the piece back.
  final void Function(int slot) onCancel;
}

class _DragState {
  _DragState({
    required this.slot,
    required this.pointer,
    required this.start,
    required this.startMs,
    required this.anchor,
  });

  final int slot;
  final int pointer;
  final Offset start;
  final int startMs;
  bool moved = false;
  Anchor? anchor;
}

/// Raw-pointer drag state machine.
///
/// Driven by a `Listener` rather than a `GestureDetector`: the game needs
/// `onPointerDown/Move/Up/Cancel` without gesture-arena delay, because a
/// 100ms wait before the piece lifts is felt as lag even though no frame was
/// dropped.
///
/// [now] is injectable so the tap-versus-drag timing is testable without
/// sleeping.
class DragController {
  DragController({
    required this.deps,
    required this.handlers,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final DragDeps deps;
  final DragHandlers handlers;
  final int Function() _now;

  _DragState? _drag;

  bool get isDragging => _drag != null;
  int? get draggingSlot => _drag?.slot;
  Anchor? get anchor => _drag?.anchor;

  void onPointerDown(PointerDownEvent e) {
    if (_drag != null) return;
    final layout = deps.layout();
    final slot = traySlotAt(layout, e.localPosition.dx, e.localPosition.dy);
    if (slot == null) return;
    final cells = deps.pieceCells(slot);
    if (cells == null) return;

    final centre = floatCentre(e.localPosition);
    _drag = _DragState(
      slot: slot,
      pointer: e.pointer,
      start: e.localPosition,
      startMs: _now(),
      anchor: resolveAnchor(layout, cells, centre.dx, centre.dy, null),
    );
    handlers.onLift(slot);
    handlers.onUpdate(slot, centre, _drag!.anchor);
  }

  void onPointerMove(PointerMoveEvent e) {
    final drag = _drag;
    if (drag == null || e.pointer != drag.pointer) return;
    final cells = deps.pieceCells(drag.slot);
    if (cells == null) return;

    final p = e.localPosition;
    if (!drag.moved && (p - drag.start).distance > tapMovePx) {
      drag.moved = true;
    }

    final centre = floatCentre(p);
    drag.anchor = resolveAnchor(
      deps.layout(),
      cells,
      centre.dx,
      centre.dy,
      drag.anchor,
    );
    handlers.onUpdate(drag.slot, centre, drag.anchor);
  }

  void onPointerUp(PointerUpEvent e) {
    final drag = _drag;
    if (drag == null || e.pointer != drag.pointer) return;
    _drag = null;

    final isTap = !drag.moved && _now() - drag.startMs < tapMs;
    if (isTap) {
      handlers.onTap(drag.slot);
    } else {
      handlers.onCommit(drag.slot, drag.anchor);
    }
  }

  void onPointerCancel(PointerCancelEvent e) {
    final drag = _drag;
    if (drag == null || e.pointer != drag.pointer) return;
    _drag = null;
    handlers.onCancel(drag.slot);
  }

  /// Abandon the drag without committing — used when the game state changes
  /// under the finger (a stage ends, a tool is activated).
  void abort() {
    final drag = _drag;
    if (drag == null) return;
    _drag = null;
    handlers.onCancel(drag.slot);
  }
}
