/// One `CustomPainter` for board + tray + ghost + floating piece.
///
/// Flutter widgets do the HUD, menus, shop and draft — those are lists and
/// forms, not a game (spec §8). No game engine: this is turn-based with 64
/// cells and no physics, so one painter and a `Listener` is the whole
/// renderer.
///
/// ## The repaint contract
///
/// [shouldRepaint] compares an immutable [BoardView] snapshot and returns
/// false when nothing changed. The board is static between placements, and an
/// idle board must burn no GPU. The static chrome — the frame, the chart grid
/// and the empty cells — is pre-recorded into a `ui.Picture` and replayed with
/// `drawPicture`, so it costs one draw call however complex it gets.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/shapes.dart';
import '../core/types.dart';
import 'layout.dart';
import 'theme.dart';
import 'starfield.dart';

/// How the ghost reads. Each state must be distinguishable **without relying
/// on colour alone** (spec §7.5), so each also carries a shape cue: a plain
/// outline, full-length bands, or diagonal hatching.
enum GhostState { none, valid, willClear, invalid }

/// A line being cleared, mid-animation.
class ClearAnimation {
  const ClearAnimation({required this.clears, required this.t});

  final Clears clears;

  /// 0..1. Clear flash is 120ms, so a 4-line clear completes well inside the
  /// 400ms budget (spec §8).
  final double t;
}

/// An immutable snapshot of everything the painter draws.
///
/// Value equality is the whole point: it is what lets [shouldRepaint] answer
/// "nothing changed" cheaply and honestly.
@immutable
class BoardView {
  const BoardView({
    required this.board,
    required this.layout,
    required this.palette,
    required this.tray,
    this.heldSlot,
    this.heldCentre,
    this.anchor,
    this.ghost = GhostState.none,
    this.previewClears = const Clears.none(),
    this.clearAnimation,
    this.settleT = 1.0,
    this.settleCells = const [],
    this.rotationDisabled = false,
    this.toolTarget,
  });

  final Board board;
  final Layout layout;
  final LoomPalette palette;
  final List<TrayItem?> tray;

  /// The slot being dragged, if any — its tray rendering is suppressed.
  final int? heldSlot;

  /// Centre of the floating piece: `liftOffset` **above** the finger.
  final Offset? heldCentre;

  final Anchor? anchor;
  final GhostState ghost;

  /// Rows and columns the current snap target would complete. Highlighting
  /// these along their **full length** is the most important feedback in the
  /// game — it is how a player plans a multi-line clear (spec §2.5).
  final Clears previewClears;

  final ClearAnimation? clearAnimation;

  /// 0..1 settle animation for the piece that just landed (90ms).
  final double settleT;

  /// Board coordinates the last placement landed on. Cells here that are no
  /// longer filled were taken by a clear and are simply skipped.
  final List<Coord> settleCells;

  /// Fixed Heddles: shown as a struck-through rotation hint on tray pieces.
  final bool rotationDisabled;

  /// A cell or 2×2 area a tool is aimed at (Unpick, Shears).
  final Anchor? toolTarget;

  @override
  bool operator ==(Object other) =>
      other is BoardView &&
      other.board == board &&
      other.layout.size == layout.size &&
      other.layout.cell == layout.cell &&
      other.palette == palette &&
      _sameTray(other.tray, tray) &&
      other.heldSlot == heldSlot &&
      other.heldCentre == heldCentre &&
      other.anchor == anchor &&
      other.ghost == ghost &&
      other.previewClears == previewClears &&
      other.clearAnimation?.t == clearAnimation?.t &&
      other.clearAnimation?.clears == clearAnimation?.clears &&
      other.settleT == settleT &&
      other.settleCells.length == settleCells.length &&
      other.rotationDisabled == rotationDisabled &&
      other.toolTarget == toolTarget;

  @override
  int get hashCode => Object.hash(
    board,
    layout.size,
    heldSlot,
    heldCentre,
    anchor,
    ghost,
    previewClears,
    clearAnimation?.t,
    settleT,
    rotationDisabled,
    toolTarget,
    Object.hashAll(tray),
  );

  static bool _sameTray(List<TrayItem?> a, List<TrayItem?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class BoardPainter extends CustomPainter {
  BoardPainter(this.view);

  final BoardView view;

  /// The frame and the sky behind it, recorded once per layout size.
  static ui.Picture? _chrome;
  static Size? _chromeSize;
  static LoomPalette? _chromePalette;
  static int? _chromeGrid;

  LoomPalette get p => view.palette;
  Layout get l => view.layout;

  double get _radius => l.cell * 0.18;

  @override
  void paint(Canvas canvas, Size size) {
    _paintChrome(canvas, size);
    _paintPreviewBands(canvas);
    _paintCells(canvas);
    _paintGhost(canvas);
    _paintClearFlash(canvas);
    _paintTray(canvas);
    _paintHeldPiece(canvas);
  }

  /* ---------------- static chrome ---------------- */

  void _paintChrome(Canvas canvas, Size size) {
    if (_chrome == null ||
        _chromeSize != size ||
        _chromePalette != p ||
        _chromeGrid != l.gridW * 100 + l.gridH) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);

      // No background fill. The sky is one layer per *screen*, not one per
      // canvas: `SkyBackground` paints it behind the whole game screen, and
      // this canvas only covers the part below the HUD. Filling it here would
      // put a second nebula and a second star field in the lower two thirds
      // of the screen, with a seam across the middle where the two gradients
      // met.
      final canvasRect = Offset.zero & size;

      // The frame: a recessed panel behind the board.
      final frame = l.board.inflate(canvasMargin * 0.6);
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(frame, Radius.circular(_radius * 2)));
      c.drawRect(frame, Paint()..color = p.frame);
      c.restore();

      // The graticule, over the whole canvas and on the board's own pitch, so
      // the rows and columns the game clears run on past the board and into
      // the sky. It is drawn after the frame and before the cells, which means
      // it survives only where nothing is placed on top of it — the margins
      // and the sky — and that is exactly where structure is allowed to read.
      paintChartGrid(
        c,
        canvasRect,
        line: p.weaveLine,
        spacing: l.cell,
        origin: l.board.topLeft,
      );

      // Empty cells. These never change, so they belong in the chrome rather
      // than in the per-frame pass.
      //
      // Stroked, not just filled. On a device the light board was a flat
      // sheet: an empty cell differs from the frame behind it by about
      // 1.3:1, which is enough to tint it and not enough to draw a grid. The
      // outline makes the cell boundaries legible at any fill contrast, and
      // it is what a reed actually looks like.
      final empty = Paint()..color = p.emptyCell;
      final emptyEdge = Paint()
        ..color = p.gridLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var y = 0; y < l.gridH; y++) {
        for (var x = 0; x < l.gridW; x++) {
          final rr = RRect.fromRectAndRadius(
            l.cellRect(x, y).deflate(1.5),
            Radius.circular(_radius),
          );
          c.drawRRect(rr, empty);
          c.drawRRect(rr, emptyEdge);
        }
      }

      // The tray trough.
      c.drawRRect(
        RRect.fromRectAndRadius(l.tray.deflate(6), const Radius.circular(16)),
        Paint()..color = p.boardBackground,
      );

      _chrome = recorder.endRecording();
      _chromeSize = size;
      _chromePalette = p;
      _chromeGrid = l.gridW * 100 + l.gridH;
    }
    canvas.drawPicture(_chrome!);
  }

  /* ---------------- board ---------------- */

  void _paintCells(Canvas canvas) {
    final b = view.board;
    for (var y = 0; y < b.h; y++) {
      for (var x = 0; x < b.w; x++) {
        final v = b.cells[y * b.w + x];
        if (v == kEmpty) continue;
        if (isKnot(v)) {
          _paintKnot(canvas, l.cellRect(x, y));
        } else {
          _paintYarnCell(
            canvas,
            l.cellRect(x, y),
            v,
            scale: _settleScale(x, y),
          );
        }
      }
    }
  }

  /// The beat: a cell that just landed starts slightly small and settles.
  ///
  /// Scale rather than translate, because nothing in this game falls — a cell
  /// that slid into place would be claiming a gravity the board does not have.
  double _settleScale(int x, int y) {
    if (view.settleT >= 1 || view.settleCells.isEmpty) return 1;
    for (final (cx, cy) in view.settleCells) {
      if (cx == x && cy == y) {
        return 0.86 + 0.14 * Curves.easeOutBack.transform(view.settleT);
      }
    }
    return 1;
  }

  void _paintYarnCell(
    Canvas canvas,
    Rect r,
    int cellCount, {
    double alpha = 1,
    double scale = 1,
  }) {
    final colour = p.yarnFor(cellCount);
    final rect = scale == 1
        ? r.deflate(1.5)
        : Rect.fromCenter(
            center: r.center,
            width: (r.width - 3) * scale,
            height: (r.height - 3) * scale,
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(_radius)),
      Paint()..color = colour.withValues(alpha: alpha),
    );
    // A single top-left highlight reads as a face catching the light and
    // gives the flat colour a direction, at one extra draw call per cell.
    // It is the only shading a cell gets: everything else about the sky
    // stays outside the board, because a 42px cell is flat colour or it is
    // nothing (docs/03 §4).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.34),
        Radius.circular(_radius),
      ),
      Paint()..color = p.highlight.withValues(alpha: p.highlight.a * alpha),
    );
  }

  /// A blocker reads as a blocker, not as a block: no highlight, a muted
  /// colour, and a ring drawn on it so it is legible without relying on hue.
  ///
  /// The ring is a dark nebula — a patch of sky with nothing behind it. It
  /// replaced a drawn cross with the theme, and the two rules it has to keep
  /// are unchanged: no hue-only encoding (spec §7.5), and `knotMark` against
  /// `knot` at 3:1, which `test/render/palette_test.dart` measures.
  void _paintKnot(Canvas canvas, Rect r) {
    final rect = r.deflate(1.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(_radius)),
      Paint()..color = p.knot,
    );
    canvas.drawCircle(
      rect.center,
      rect.width * 0.29,
      Paint()
        ..color = p.knotMark
        ..style = PaintingStyle.stroke
        ..strokeWidth = l.cell * 0.09,
    );
    canvas.drawCircle(
      rect.center,
      rect.width * 0.085,
      Paint()..color = p.knotMark,
    );
  }

  /* ---------------- preview, ghost, clear ---------------- */

  /// Full-length bands down every row and column the snap target completes.
  void _paintPreviewBands(Canvas canvas) {
    final c = view.previewClears;
    if (c.isEmpty || view.ghost == GhostState.invalid) return;
    final paint = Paint()..color = p.accent.withValues(alpha: 0.22);
    final edge = Paint()
      ..color = p.accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final y in c.rows) {
      final r = Rect.fromLTWH(
        l.board.left,
        l.board.top + y * l.cell,
        l.board.width,
        l.cell,
      ).deflate(1);
      canvas.drawRect(r, paint);
      canvas.drawRect(r, edge);
    }
    for (final x in c.cols) {
      final r = Rect.fromLTWH(
        l.board.left + x * l.cell,
        l.board.top,
        l.cell,
        l.board.height,
      ).deflate(1);
      canvas.drawRect(r, paint);
      canvas.drawRect(r, edge);
    }
  }

  void _paintGhost(Canvas canvas) {
    final a = view.anchor;
    final slot = view.heldSlot;
    if (a == null || slot == null || view.ghost == GhostState.none) return;
    final item = view.tray[slot];
    if (item == null) return;
    final cells = cellsOf(item.shapeId, item.rotation);
    final shapeDef = shape(item.shapeId);

    for (final (cx, cy) in cells) {
      final r = l.cellRect(a.x + cx, a.y + cy).deflate(1.5);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(_radius));

      switch (view.ghost) {
        case GhostState.valid:
          canvas.drawRRect(
            rr,
            Paint()
              ..color = p.yarnFor(shapeDef.cellCount).withValues(alpha: 0.30),
          );
          canvas.drawRRect(
            rr,
            Paint()
              ..color = p.yarnFor(shapeDef.cellCount)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        case GhostState.willClear:
          canvas.drawRRect(
            rr,
            Paint()
              ..color = p.yarnFor(shapeDef.cellCount).withValues(alpha: 0.55),
          );
          canvas.drawRRect(
            rr,
            Paint()
              ..color = p.ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        case GhostState.invalid:
          canvas.drawRRect(rr, Paint()..color = p.warn.withValues(alpha: 0.18));
          _hatch(canvas, r);
          canvas.drawRRect(
            rr,
            Paint()
              ..color = p.warn
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        case GhostState.none:
          break;
      }
    }
  }

  /// Diagonal hatching — the non-colour half of the invalid cue.
  void _hatch(Canvas canvas, Rect r) {
    canvas.save();
    canvas.clipRect(r);
    final paint = Paint()
      ..color = p.warn.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    for (var d = -r.height; d < r.width; d += 6) {
      canvas.drawLine(
        Offset(r.left + d, r.top),
        Offset(r.left + d + r.height, r.bottom),
        paint,
      );
    }
    canvas.restore();
  }

  /// The beat-and-roll: a fast wipe along each clearing line, not a
  /// simulation.
  void _paintClearFlash(Canvas canvas) {
    final anim = view.clearAnimation;
    if (anim == null) return;
    final t = anim.t.clamp(0.0, 1.0);
    final fade = 1.0 - t;
    final paint = Paint()..color = p.ink.withValues(alpha: 0.75 * fade);

    for (final y in anim.clears.rows) {
      final full = Rect.fromLTWH(
        l.board.left,
        l.board.top + y * l.cell,
        l.board.width,
        l.cell,
      );
      canvas.drawRect(
        Rect.fromLTWH(full.left, full.top, full.width * t, full.height),
        paint,
      );
    }
    for (final x in anim.clears.cols) {
      final full = Rect.fromLTWH(
        l.board.left + x * l.cell,
        l.board.top,
        l.cell,
        l.board.height,
      );
      canvas.drawRect(
        Rect.fromLTWH(full.left, full.top, full.width, full.height * t),
        paint,
      );
    }
  }

  /* ---------------- tray and held piece ---------------- */

  void _paintTray(Canvas canvas) {
    for (var i = 0; i < view.tray.length && i < l.slots.length; i++) {
      final item = view.tray[i];
      if (item == null) continue;
      if (i == view.heldSlot) continue;
      _paintPieceInRect(canvas, l.slots[i], item);
    }
  }

  /// Draw a tray piece in its slot, centred.
  ///
  /// Scaled to fit, but with a **cap on the cell size**. Scaling purely to fit
  /// made a 1-block piece fill its whole slot, so the smallest piece in the
  /// game read as the largest — on a device it looked like a big square next
  /// to two small ones. Capping the unit keeps relative size honest: a piece
  /// that is physically bigger looks bigger.
  void _paintPieceInRect(Canvas canvas, Rect slot, TrayItem item) {
    final cells = cellsOf(item.shapeId, item.rotation);
    final e = extent(cells);
    final s = shape(item.shapeId);
    final inner = slot.deflate(10);
    final fit = math.min(inner.width / e.w, inner.height / e.h);
    // Three cells across is the reference: anything wider than that fills the
    // slot as before, anything narrower is drawn at the same cell size rather
    // than stretched up to fill.
    final cap = math.min(inner.width, inner.height) / 3;
    final unit = math.min(fit, cap);
    final w = unit * e.w;
    final h = unit * e.h;
    final ox = inner.center.dx - w / 2;
    final oy = inner.center.dy - h / 2;

    for (final (cx, cy) in cells) {
      final r = Rect.fromLTWH(
        ox + cx * unit,
        oy + cy * unit,
        unit,
        unit,
      ).deflate(unit * 0.06);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(unit * 0.18)),
        Paint()..color = p.yarnFor(s.cellCount),
      );
    }

    // Rotation affordance: a pip per distinct rotation, struck through when a
    // fault has disabled rotation. Without it, a player has no way to know
    // that tapping a square does nothing *by design*.
    if (s.rotations.length > 1) {
      final pipY = slot.bottom - 7;
      final count = s.rotations.length;
      final gap = 6.0;
      final startX = slot.center.dx - (count - 1) * gap / 2;
      for (var i = 0; i < count; i++) {
        canvas.drawCircle(
          Offset(startX + i * gap, pipY),
          i == item.rotation % count ? 2.4 : 1.4,
          Paint()
            ..color = view.rotationDisabled
                ? p.inkMuted.withValues(alpha: 0.35)
                : (i == item.rotation % count ? p.accent : p.inkMuted),
        );
      }
      if (view.rotationDisabled) {
        canvas.drawLine(
          Offset(startX - 5, pipY),
          Offset(startX + (count - 1) * gap + 5, pipY),
          Paint()
            ..color = p.warn
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  /// The held piece, floating `liftOffset` above the finger.
  ///
  /// Drawn at board scale, not tray scale, so what the player sees is exactly
  /// what will land.
  void _paintHeldPiece(Canvas canvas) {
    final centre = view.heldCentre;
    final slot = view.heldSlot;
    if (centre == null || slot == null) return;
    final item = view.tray[slot];
    if (item == null) return;

    final cells = cellsOf(item.shapeId, item.rotation);
    final e = extent(cells);
    final s = shape(item.shapeId);
    final left = centre.dx - e.w * l.cell / 2;
    final top = centre.dy - e.h * l.cell / 2;

    // A soft drop shadow lifts the piece off the board, which is most of what
    // sells "held" versus "placed".
    final shadow = Paint()
      ..color = p.shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    for (final (cx, cy) in cells) {
      final r = Rect.fromLTWH(
        left + cx * l.cell,
        top + cy * l.cell,
        l.cell,
        l.cell,
      ).deflate(1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          r.shift(const Offset(0, 4)),
          Radius.circular(_radius),
        ),
        shadow,
      );
    }
    for (final (cx, cy) in cells) {
      _paintYarnCell(
        canvas,
        Rect.fromLTWH(left + cx * l.cell, top + cy * l.cell, l.cell, l.cell),
        s.cellCount,
      );
    }
  }

  @override
  bool shouldRepaint(BoardPainter old) => old.view != view;

  /// Drop the recorded chrome — call on a theme change or a teardown.
  static void invalidateChrome() {
    _chrome = null;
    _chromeSize = null;
    _chromePalette = null;
    _chromeGrid = null;
  }
}
