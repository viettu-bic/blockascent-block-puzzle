/// The board widget: a `Listener` over a `CustomPaint`, and nothing else.
///
/// Wrapped in a `RepaintBoundary` so HUD rebuilds do not repaint it (spec §8).
///
/// Animation budget: a 4-line clear completes in **under 400ms** — clear flash
/// 120ms, piece settle 90ms. The OS reduce-motion setting is honoured by
/// skipping straight to the finished state, which is correct here because
/// every animation in this file is decorative: the board is already updated
/// when the flash begins.
library;

import 'package:flutter/material.dart';

import '../core/board.dart';
import '../core/shapes.dart';
import '../core/types.dart';
import '../game/run_controller.dart';
import '../input/drag_controller.dart';
import '../render/board_painter.dart';
import '../render/layout.dart';
import '../render/theme.dart';

const Duration clearFlash = Duration(milliseconds: 120);
const Duration pieceSettle = Duration(milliseconds: 90);

class BoardWidget extends StatefulWidget {
  const BoardWidget({
    super.key,
    required this.controller,
    required this.palette,
  });

  final RunController controller;
  final LoomPalette palette;

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget>
    with TickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: clearFlash,
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: pieceSettle,
    value: 1,
  );

  late DragController _drag;
  Layout? _layout;

  int? _heldSlot;
  Offset? _heldCentre;
  Anchor? _anchor;
  GhostState _ghost = GhostState.none;
  Clears _preview = const Clears.none();
  Clears _flashing = const Clears.none();
  int _lastTick = 0;

  RunController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _lastTick = c.placementTick;
    c.addListener(_onControllerChanged);
    _drag = DragController(
      deps: DragDeps(
        layout: () => _layout!,
        pieceCells: _cellsForSlot,
      ),
      handlers: DragHandlers(
        onLift: _onLift,
        onUpdate: _onUpdate,
        onCommit: _onCommit,
        onTap: _onTap,
        onCancel: _onCancel,
      ),
    );
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    _flash.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (c.placementTick == _lastTick) return;
    _lastTick = c.placementTick;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    _flashing = c.lastClears;
    if (reduceMotion) {
      _flash.value = 1;
      _settle.value = 1;
      setState(() => _flashing = const Clears.none());
      return;
    }
    _settle.forward(from: 0);
    if (_flashing.isNotEmpty) {
      _flash.forward(from: 0).then((_) {
        if (mounted) setState(() => _flashing = const Clears.none());
      });
    }
  }

  /* ---------------- drag plumbing ---------------- */

  /// The tray plus the hold slot. The hold slot is a placeable position but is
  /// deliberately **not** part of the tray the refill rule inspects.
  List<TrayItem?> get _slots => [
    ...c.tray,
    if (c.powers.hasHold) c.holdItem,
  ];

  ShapeCells? _cellsForSlot(int slot) {
    final items = _slots;
    if (slot < 0 || slot >= items.length) return null;
    final item = items[slot];
    return item == null ? null : cellsOf(item.shapeId, item.rotation);
  }

  void _onLift(int slot) {
    widget.controller.haptics.lift();
    setState(() => _heldSlot = slot);
  }

  void _onUpdate(int slot, Offset centre, Anchor? anchor) {
    final item = _slots[slot];
    if (item == null) return;

    GhostState ghost;
    var preview = const Clears.none();
    if (anchor == null) {
      ghost = GhostState.none;
    } else if (!c.canPlace(item, anchor)) {
      ghost = GhostState.invalid;
    } else {
      preview = c.previewFor(item, anchor);
      ghost = preview.isNotEmpty ? GhostState.willClear : GhostState.valid;
    }

    if (anchor != _anchor) widget.controller.haptics.snap();

    setState(() {
      _heldCentre = centre;
      _anchor = anchor;
      _ghost = ghost;
      _preview = preview;
    });
  }

  void _onCommit(int slot, Anchor? anchor) {
    // An invalid release never consumes the piece: it simply goes back to its
    // slot (spec §2.6).
    final placed = anchor != null && c.place(slot, anchor);
    if (!placed) widget.controller.haptics.invalid();
    _clearHeld();
  }

  void _onTap(int slot) {
    c.rotate(slot);
    _clearHeld();
  }

  void _onCancel(int slot) => _clearHeld();

  void _clearHeld() {
    setState(() {
      _heldSlot = null;
      _heldCentre = null;
      _anchor = null;
      _ghost = GhostState.none;
      _preview = const Clears.none();
    });
  }

  /* ---------------- tool aiming ---------------- */

  bool _handleToolTap(Offset local) {
    if (c.aiming == ToolAim.none) return false;
    final l = _layout!;
    if (!l.board.contains(local)) {
      c.cancelAim();
      return true;
    }
    final x = ((local.dx - l.board.left) / l.cell).floor();
    final y = ((local.dy - l.board.top) / l.cell).floor();
    c.applyToolAt(x, y);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final l = computeLayout(
          constraints.maxWidth,
          constraints.maxHeight,
          c.board.w,
          c.board.h,
          slotCount: _slots.length,
        );
        _layout = l;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_handleToolTap(e.localPosition)) return;
            if (c.phase != GamePhase.placing) return;
            _drag.onPointerDown(e);
          },
          onPointerMove: _drag.onPointerMove,
          onPointerUp: _drag.onPointerUp,
          onPointerCancel: _drag.onPointerCancel,
          // The board is a CustomPainter, so it is invisible to assistive
          // tech by default. This will not make the game playable with a
          // screen reader — placing a piece is a drag on a grid — but it does
          // mean the board announces what is on it instead of nothing at all.
          child: Semantics(
            label: _boardSummary(),
            child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_flash, _settle]),
              builder: (context, _) => CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: BoardPainter(
                  BoardView(
                    board: c.board,
                    layout: l,
                    palette: widget.palette,
                    tray: _slots,
                    heldSlot: _heldSlot,
                    heldCentre: _heldCentre,
                    anchor: _anchor,
                    ghost: _ghost,
                    previewClears: _preview,
                    clearAnimation: _flashing.isEmpty
                        ? null
                        : ClearAnimation(
                            clears: _flashing,
                            t: _flash.value,
                          ),
                    settleT: _settle.value,
                    settleCells: c.lastPlacedCells,
                    rotationDisabled: c.rotationDisabled,
                  ),
                ),
              ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _boardSummary() {
    final filled = countFilled(c.board);
    final total = c.board.w * c.board.h;
    final knots = countKnots(c.board);
    final pieces = _slots
        .whereType<TrayItem>()
        .map((t) => shapeName(t.shapeId))
        .join(', ');
    return 'Board ${c.board.w} by ${c.board.h}, '
        '$filled of $total cells filled'
        '${knots > 0 ? ', $knots blockers' : ''}. '
        '${pieces.isEmpty ? 'Tray empty' : 'In the tray: $pieces'}.';
  }
}
