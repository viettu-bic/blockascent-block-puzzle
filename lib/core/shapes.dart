/// The shape roster and its geometry, ported from
/// `reference/ts-core/core/shapes.ts`.
///
/// Shapes are defined from ASCII art and their rotations are **computed and
/// deduplicated at load** — never hand-listed. Deduplicating matters for feel:
/// tapping a 2×2 square should visibly do nothing rather than cycle through
/// four identical states.
library;

import 'types.dart';

/// Bounding box of a rotation, in cells.
({int w, int h}) extent(ShapeCells cells) {
  var w = 0;
  var h = 0;
  for (final (x, y) in cells) {
    if (x + 1 > w) w = x + 1;
    if (y + 1 > h) h = y + 1;
  }
  return (w: w, h: h);
}

/// Shift cells so min x and min y are 0, then sort so the list has a canonical
/// order (row-major: by y, then x).
ShapeCells normalise(List<Coord> cells) {
  var minX = cells.first.$1;
  var minY = cells.first.$2;
  for (final (x, y) in cells) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
  }
  final out = [for (final (x, y) in cells) (x - minX, y - minY)];
  out.sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
  return out;
}

/// Rotate 90° clockwise: `(x, y) -> (-y, x)`, then renormalise to the origin.
ShapeCells rotateCw(ShapeCells cells) =>
    normalise([for (final (x, y) in cells) (-y, x)]);

String shapeKey(ShapeCells cells) =>
    cells.map((c) => '${c.$1},${c.$2}').join(';');

/// All *distinct* rotations, in clockwise order starting from the given form.
List<ShapeCells> rotationsOf(List<Coord> base) {
  final out = <ShapeCells>[];
  final seen = <String>{};
  var current = normalise(base);
  for (var i = 0; i < 4; i++) {
    final key = shapeKey(current);
    if (seen.add(key)) out.add(current);
    current = rotateCw(current);
  }
  return out;
}

/// Parse ASCII art — `#` is filled, anything else is empty. Rows top to
/// bottom.
List<Coord> parseArt(List<String> art) {
  final cells = <Coord>[];
  for (var y = 0; y < art.length; y++) {
    final row = art[y];
    for (var x = 0; x < row.length; x++) {
      if (row[x] == '#') cells.add((x, y));
    }
  }
  if (cells.isEmpty) throw ArgumentError('shape art has no filled cells');
  return cells;
}

Shape _def(String id, int tier, List<String> art) {
  final rotations = rotationsOf(parseArt(art));
  return Shape(
    id: id,
    tier: tier,
    cellCount: rotations.first.length,
    rotations: rotations,
  );
}

/* ------------------------------------------------------------------ */
/* Roster                                                             */
/* ------------------------------------------------------------------ */
//
// Tiers are the meta-progression unlock order (docs/01 §6). Value scales
// sub-linearly with cell count before powers, so big shapes are a liquidity
// risk rather than a free win.
//
// No duplicates across tiers: the O-tetromino IS the 2×2 square and the
// I-tetromino IS the 1×4, so each appears exactly once. A naive roster
// double-lists them and the draw bag silently skews small.

final List<Shape> tier1 = [
  _def('dot', 1, ['#']),
  _def('i2', 1, ['##']),
  _def('i3', 1, ['###']),
  _def('o2', 1, ['##', '##']),
  _def('l3', 1, ['#.', '##']),
];

final List<Shape> tier2 = [
  _def('i4', 2, ['####']),
  _def('t4', 2, ['###', '.#.']),
  _def('s4', 2, ['.##', '##.']),
  _def('z4', 2, ['##.', '.##']),
  _def('j4', 2, ['.#', '.#', '##']),
  _def('l4', 2, ['#.', '#.', '##']),
];

final List<Shape> tier3 = [
  _def('i5', 3, ['#####']),
  _def('r23', 3, ['###', '###']),
  _def('x5', 3, ['.#.', '###', '.#.']),
  _def('u5', 3, ['#.#', '###']),
  _def('p5', 3, ['##', '##', '#.']),
  _def('t5', 3, ['###', '.#.', '.#.']),
];

final List<Shape> tier4 = [
  _def('o3', 4, ['###', '###', '###']),
  _def('r24', 4, ['####', '####']),
  _def('w5', 4, ['#..', '##.', '.##']),
  _def('z5', 4, ['##.', '.#.', '.##']),
  _def('f5', 4, ['.##', '##.', '.#.']),
];

final List<Shape> allShapes = [...tier1, ...tier2, ...tier3, ...tier4];

final Map<String, Shape> shapesById = {
  for (final s in allShapes) s.id: s,
};

/// Human-readable block names.
///
/// Plain descriptions of what each piece looks like. Deliberately **not**
/// tetromino letter names (T, S, Z, J, L): spec §11 keeps this game clear of
/// Tetris trade dress, and while letter names are far less risky than the
/// colourway, there is no reason to reach for them when "Hook" and "Step"
/// describe the shape just as well.
const Map<String, String> shapeNames = {
  'dot': 'Single',
  'i2': 'Double',
  'i3': 'Triple',
  'o2': 'Square',
  'l3': 'Corner',
  'i4': 'Line',
  't4': 'Tee',
  's4': 'Step',
  'z4': 'Zigzag',
  'j4': 'Hook',
  'l4': 'Elbow',
  'i5': 'Long Line',
  'r23': 'Brick',
  'x5': 'Plus',
  'u5': 'Cup',
  'p5': 'Chunk',
  't5': 'Arrow',
  'o3': 'Big Square',
  'r24': 'Slab',
  'w5': 'Stairs',
  'z5': 'Bolt',
  'f5': 'Twist',
};

Shape shape(String id) {
  final s = shapesById[id];
  if (s == null) throw ArgumentError('unknown shape: $id');
  return s;
}

String shapeName(String id) => shapeNames[id] ?? id;

ShapeCells cellsOf(String id, int rotation) {
  final s = shape(id);
  return s.rotations[rotation % s.rotations.length];
}

/// Next rotation index, wrapping. Tapping a tray piece advances this.
///
/// Rotation is tap-only and cycles *forward* through distinct rotations.
/// Long-press for counter-clockwise was considered and rejected: holding still
/// is how a drag begins, so the two gestures collide (spec §7).
int nextRotation(String id, int rotation) =>
    (rotation + 1) % shape(id).rotations.length;

/// Tiers 1 and 2 — the loadout a player owns at install plus the first unlock
/// tier. Small enough that the board stays solvable while the drag is being
/// judged, big enough that refills feel varied. This is also the loadout the
/// port-parity simulation plays, so it must keep exactly these 11 shapes in
/// exactly this order.
final List<Shape> spikeLoadout = [...tier1, ...tier2];

List<Shape> shapesOfTier(int tier) =>
    allShapes.where((s) => s.tier == tier).toList();

/// Render the shape as ASCII art — for readable test failures and debug
/// output.
List<String> shapeToArt(ShapeCells cells) {
  final e = extent(cells);
  final grid = List.generate(e.h, (_) => List.filled(e.w, '.'));
  for (final (x, y) in cells) {
    grid[y][x] = '#';
  }
  return grid.map((r) => r.join()).toList();
}
