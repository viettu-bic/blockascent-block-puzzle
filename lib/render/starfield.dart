/// Procedural night sky.
///
/// Replaces the weave texture of `docs/03` §4b. The reasoning there survives
/// the change of theme: structure that can be written as a function needs no
/// bitmap, so the game still ships no texture assets at all. A star field is
/// if anything a better fit than a weave was — a weave had to be a repeating
/// tile, and a repeating tile of stars reads as wallpaper the moment the eye
/// finds the seam. This scatters instead, once, and the result is pre-recorded
/// into a [ui.Picture] — the board's chrome for the graticule, [SkyPainter]'s
/// own cache for the field — so nothing here is redrawn per frame.
///
/// ## Where the sky goes — and does not
///
/// **Yes:** the margins outside the board, the recessed frame behind it, and
/// any large still surface.
///
/// **No:** filled cells at play size, the dragged piece, the ghost. That rule
/// is inherited verbatim from `docs/03` §4 and is not a theme decision: a
/// 42px cell is too small for anything but flat colour, the palette's contrast
/// guarantees are measured against flat fills, and a glow inside a cell would
/// crawl while a piece is dragged.
///
/// ## Determinism
///
/// The field is generated from [Rng], the game's own seeded generator, so the
/// same board size always produces the same sky. That matters for two
/// unglamorous reasons: the chrome is cached and re-recorded on resize, so a
/// re-roll would make the stars jump when the keyboard opens, and a widget
/// test that could not predict the sky could not assert anything about it.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/rng.dart';
import 'theme.dart';

/// One star: a position in logical pixels, a radius, and a brightness.
class Star {
  const Star(this.x, this.y, this.r, this.alpha);

  final double x;
  final double y;
  final double r;
  final double alpha;
}

/// Scatter [count] stars across [area], deterministically for [seed].
///
/// Rejection sampling keeps them apart: stars that land within [minGap] of one
/// already placed are discarded. Without it a uniform scatter clumps, and a
/// clump of three at 1px reads as a smudge on the screen rather than as sky.
/// The loop is bounded because a dense request in a small rect can otherwise
/// reject for ever.
List<Star> scatterStars({
  required Rect area,
  required int seed,
  required int count,
  double minGap = 14,
  double minRadius = 0.6,
  double maxRadius = 1.9,
}) {
  final rng = Rng(seed);
  final stars = <Star>[];
  var attempts = 0;
  while (stars.length < count && attempts < count * 24) {
    attempts++;
    final x = area.left + rng.next() * area.width;
    final y = area.top + rng.next() * area.height;
    var clear = true;
    for (final s in stars) {
      if ((s.x - x).abs() < minGap && (s.y - y).abs() < minGap) {
        clear = false;
        break;
      }
    }
    if (!clear) continue;
    // Cubed, so most stars are small and a handful are not. A uniform radius
    // gives a field of identical dots, which reads as a pattern, not a sky.
    final t = rng.next();
    final r = minRadius + (maxRadius - minRadius) * t * t * t;
    stars.add(Star(x, y, r, 0.22 + rng.next() * 0.5));
  }
  return stars;
}

/// Draw a field. Two passes per star: a wide dim halo, then the core.
///
/// The halo is what separates a star from a dust speck, and at these sizes a
/// flat disc behind the core is indistinguishable from a real falloff and
/// costs one draw call instead of a gradient shader.
void paintStars(Canvas canvas, List<Star> stars, {required Color colour}) {
  for (final s in stars) {
    canvas.drawCircle(
      Offset(s.x, s.y),
      s.r * 2.8,
      Paint()..color = colour.withValues(alpha: s.alpha * 0.16),
    );
    canvas.drawCircle(
      Offset(s.x, s.y),
      s.r,
      Paint()..color = colour.withValues(alpha: s.alpha),
    );
  }
}

/// A single soft bloom — the one piece of hue in the background.
///
/// One radial gradient over a large rect, drawn once into the chrome. It is
/// here because a flat near-black panel reads as an absence rather than as a
/// night, and because `docs/09` §7's claim that this theme costs no art has to
/// hold for the game as well as for the icon.
void paintNebula(
  Canvas canvas,
  Rect area, {
  required Offset centre,
  required double radius,
  required Color colour,
  double opacity = 0.12,
}) {
  final paint = Paint()
    ..shader = RadialGradient(
      colors: [
        colour.withValues(alpha: opacity),
        colour.withValues(alpha: 0),
      ],
    ).createShader(Rect.fromCircle(center: centre, radius: radius));
  canvas.drawRect(area, paint);
}

/// The first grid line at or after [edge] that is in phase with [origin].
///
/// **This was `ceil`, and it drew a line a whole cell outside the area.**
/// `CustomPaint` does not clip its painter, so on the game screen that line
/// landed above the board canvas and straight across the HUD — a long dash
/// through the multiplier and the combo pips, which is exactly how it was
/// reported from a device.
///
/// `floor` is the correct direction: it returns the largest in-phase value
/// that is still at or after the edge, so the first line drawn is the first
/// one inside the area. `test/render/starfield_test.dart` pins both halves of
/// that — in phase, and never before the edge.
double gridStart(double origin, double edge, double spacing) =>
    origin - ((origin - edge) / spacing).floor() * spacing;

/// The chart grid over the frame and margins.
///
/// **Both axes**, which is the whole reason this theme was worth having: a
/// star chart carries a coordinate graticule, and this game clears rows *and*
/// columns. The grid is the only place in the chrome that states the rule
/// before a player has met it.
///
/// Replaces `paintWarpLines`, which drew one axis because a warp only runs one
/// way.
void paintChartGrid(
  Canvas canvas,
  Rect area, {
  required Color line,
  double spacing = 7.0,
  double width = 1.0,
  Offset? origin,
}) {
  final paint = Paint()
    ..color = line
    ..strokeWidth = width;

  // Align to [origin] when given, so the graticule can be put on the board's
  // own pitch and the board's rows and columns run on into the sky. A grid at
  // some other pitch reads as hatching laid over the board rather than as the
  // chart the board sits on.
  double start(double from, double edge) => gridStart(from, edge, spacing);

  for (
    var x = start(origin?.dx ?? area.left, area.left);
    x <= area.right;
    x += spacing
  ) {
    canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), paint);
  }
  for (
    var y = start(origin?.dy ?? area.top, area.top);
    y <= area.bottom;
    y += spacing
  ) {
    canvas.drawLine(Offset(area.left, y), Offset(area.right, y), paint);
  }
}

/// How many stars a surface of this size wants.
///
/// Density, not a fixed count, so a tablet does not get the same forty stars
/// spread thin. One per 2,600 logical px², clamped, which is sparse enough
/// that no star ever competes with a block.
int starCountFor(Size size, {int min = 18, int max = 150}) {
  final n = (size.width * size.height / 2600).round();
  return math.max(min, math.min(max, n));
}

/// The sky as a full-surface background, for every screen that is not the
/// board.
///
/// **One sky per screen, never one per canvas.** The board's own canvas
/// covers only the part of the game screen below the HUD, so a sky painted
/// there would put a second nebula and a second star field in the lower two
/// thirds of the screen with a seam across the middle. This sits behind the
/// whole screen instead, and the board canvas is transparent over it.
///
/// One picture per size and palette, cached, with [shouldRepaint] false —
/// these screens scroll and rebuild, and the sky must not be redrawn when
/// they do.
class SkyPainter extends CustomPainter {
  const SkyPainter(this.palette, {this.grid = 44.0});

  final LoomPalette palette;

  /// The graticule's pitch, or null for no graticule.
  ///
  /// Null on the game screen, where the board paints the grid itself on its
  /// own cell pitch: two grids at two pitches on one screen read as a mistake,
  /// and only the board knows what its pitch is.
  ///
  /// Elsewhere it is 44, which is not the board's cell size — those screens
  /// have no board to agree with — but is close enough to it that the chart
  /// reads as the same chart.
  final double? grid;

  static ui.Picture? _cached;
  static Size? _size;
  static LoomPalette? _palette;
  static double? _grid;
  static bool _hadGrid = false;

  @override
  void paint(Canvas canvas, Size size) {
    if (_cached == null ||
        _size != size ||
        _palette != palette ||
        _grid != grid ||
        _hadGrid != (grid != null)) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      final area = Offset.zero & size;

      c.drawRect(area, Paint()..color = palette.background);
      paintNebula(
        c,
        area,
        centre: Offset(size.width * 0.16, size.height * 0.12),
        radius: size.width * 0.95,
        colour: palette.yarnFor(8),
        opacity: 0.10,
      );
      paintNebula(
        c,
        area,
        centre: Offset(size.width * 0.9, size.height * 0.85),
        radius: size.width * 0.85,
        colour: palette.yarnFor(6),
        opacity: 0.07,
      );
      if (grid != null) {
        paintChartGrid(c, area, line: palette.weaveLine, spacing: grid!);
      }
      paintStars(
        c,
        scatterStars(
          area: area,
          seed:
              (size.width.round() * 73856093) ^
              (size.height.round() * 19349663),
          count: starCountFor(size),
        ),
        colour: palette.ink,
      );

      _cached = recorder.endRecording();
      _size = size;
      _palette = palette;
      _grid = grid;
      _hadGrid = grid != null;
    }
    canvas.drawPicture(_cached!);
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.palette != palette || old.grid != grid;
}
