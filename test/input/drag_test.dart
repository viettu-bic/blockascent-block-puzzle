
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';
import 'package:loomcraft/input/drag_controller.dart';
import 'package:loomcraft/render/layout.dart';

/// Ported from `reference/ts-tests/drag.test.ts`.
///
/// The snap rule is pure, so it is testable without a widget tree. These
/// assertions are the contract the drag feel depends on — if one of them
/// changes, the game feels different.
void main() {
  // iPhone-14-ish canvas below the HUD.
  final l = computeLayout(390, 700, 8, 8);
  final dot = cellsOf('dot', 0);
  final o2 = cellsOf('o2', 0);

  /// Centre of the float rectangle that would land a piece at (ax, ay).
  ({double cx, double cy}) centreFor(int ax, int ay, int pw, int ph) => (
    cx: l.board.left + ax * l.cell + (pw * l.cell) / 2,
    cy: l.board.top + ay * l.cell + (ph * l.cell) / 2,
  );

  group('layout', () {
    test('puts the board above the tray and keeps it square', () {
      expect(l.board.width, l.cell * 8);
      expect(l.board.height, l.cell * 8);
      expect(l.board.bottom, lessThanOrEqualTo(l.tray.top));
      expect(l.slots, hasLength(3));
    });

    test('gives a ~42px cell at 375pt, as the spec sizes it', () {
      final narrow = computeLayout(375, 700, 8, 8);
      expect(narrow.cell, closeTo(42, 2.5));
    });

    test('keeps the board on screen on a short phone', () {
      final short = computeLayout(390, 560, 8, 8);
      expect(short.board.left, greaterThanOrEqualTo(0));
      expect(short.board.right, lessThanOrEqualTo(390));
      expect(short.board.bottom, lessThanOrEqualTo(short.tray.top));
      expect(short.cell, greaterThan(0));
    });

    test('centres the board horizontally', () {
      expect(l.board.left, closeTo(390 - l.board.right, 0.001));
    });

    test('tray slots are inside the tray and do not overlap', () {
      for (final s in l.slots) {
        expect(s.top, greaterThanOrEqualTo(l.tray.top));
        expect(s.bottom, lessThanOrEqualTo(l.tray.bottom));
      }
      for (var i = 1; i < l.slots.length; i++) {
        expect(l.slots[i].left, greaterThan(l.slots[i - 1].right));
      }
    });

    test('makes room for a 4th slot when Second Shuttle is taken', () {
      final wide = computeLayout(390, 700, 8, 8, slotCount: 4);
      expect(wide.slots, hasLength(4));
      expect(wide.slots.last.right, lessThanOrEqualTo(390));
      for (var i = 1; i < wide.slots.length; i++) {
        expect(wide.slots[i].left, greaterThan(wide.slots[i - 1].right));
      }
    });

    test('hit-tests tray slots', () {
      final slot = l.slots[1];
      expect(traySlotAt(l, slot.left + 2, slot.top + 2), 1);
      expect(traySlotAt(l, l.board.left + 4, l.board.top + 4), isNull);
    });

    test('cellRect and originOf agree with the board rectangle', () {
      expect(l.originOf(0, 0), Offset(l.board.left, l.board.top));
      expect(l.cellRect(7, 7).right, closeTo(l.board.right, 0.001));
      expect(l.cellRect(7, 7).bottom, closeTo(l.board.bottom, 0.001));
    });
  });

  group('resolveAnchor', () {
    test('snaps a piece centred on a cell to that cell', () {
      final c = centreFor(3, 4, 1, 1);
      expect(resolveAnchor(l, dot, c.cx, c.cy, null), const Anchor(3, 4));
    });

    test('snaps by the piece, not the touch point', () {
      // A 2x2 centred over the boundary of cells (2,2)..(3,3) lands at (2,2).
      final c = centreFor(2, 2, 2, 2);
      expect(resolveAnchor(l, o2, c.cx, c.cy, null), const Anchor(2, 2));
    });

    test('clamps so the whole shape stays in bounds', () {
      // Far enough right to round to column 8, which does not exist.
      final cx = l.board.left + 7.75 * l.cell + l.cell / 2;
      final cy = l.board.top + l.cell / 2;
      expect(resolveAnchor(l, dot, cx, cy, null), const Anchor(7, 0));

      // Still overlapping the board, but rounding to (7, 7) would hang a 2x2
      // off the bottom-right corner, so both axes clamp to 6.
      final lowCy = l.board.top + 7.2 * l.cell + l.cell;
      expect(resolveAnchor(l, o2, cx, lowCy, null), const Anchor(6, 6));
    });

    test('returns null when the held piece does not overlap the board', () {
      expect(resolveAnchor(l, dot, l.board.left + l.cell, -500, null), isNull);
      expect(resolveAnchor(l, dot, -500, l.board.top + l.cell, null), isNull);
    });

    test('holds the previous target inside the sticky threshold', () {
      const previous = Anchor(3, 4);
      // Exactly half a cell right: plain rounding would jump to column 4.
      final cx = l.board.left + 3.5 * l.cell + l.cell / 2;
      final cy = l.board.top + 4 * l.cell + l.cell / 2;
      expect(resolveAnchor(l, dot, cx, cy, previous), previous);
    });

    test('releases the previous target once the piece drifts far enough', () {
      const previous = Anchor(3, 4);
      final cx = l.board.left + 3.7 * l.cell + l.cell / 2;
      final cy = l.board.top + 4 * l.cell + l.cell / 2;
      expect(resolveAnchor(l, dot, cx, cy, previous), const Anchor(4, 4));
    });

    test('lets a piece reach the bottom row while the finger is below it', () {
      // The piece floats liftOffset above the finger, so a thumb resting in
      // the tray still addresses row 7. Here the float centre is on row 7
      // even though the finger that produced it would be ~56px lower, inside
      // the tray.
      final c = centreFor(0, 7, 1, 1);
      expect(c.cy, lessThan(l.tray.top));
      expect(resolveAnchor(l, dot, c.cx, c.cy, null), const Anchor(0, 7));
    });

    test('a thumb in the tray can still address the bottom row', () {
      // The same claim, stated the way a player experiences it: the FINGER is
      // inside the tray rectangle and the piece still lands on row 7.
      final finger = Offset(
        l.board.left + l.cell / 2,
        l.board.top + 7 * l.cell + l.cell / 2 + liftOffset,
      );
      expect(finger.dy, greaterThan(l.tray.top));
      final centre = floatCentre(finger);
      expect(
        resolveAnchor(l, dot, centre.dx, centre.dy, null),
        const Anchor(0, 7),
      );
    });

    test('a tall rotation clamps on the axis that would hang off', () {
      final i4v = cellsOf('i4', 1); // 1 wide, 4 tall
      final cx = l.board.left + l.cell / 2;
      final cy = l.board.top + 7 * l.cell;
      expect(resolveAnchor(l, i4v, cx, cy, null), const Anchor(0, 4));
    });

    test('a shape larger than the board has no anchor at all', () {
      final tiny = computeLayout(390, 700, 2, 2);
      expect(
        resolveAnchor(tiny, cellsOf('i4', 0), tiny.board.center.dx,
            tiny.board.center.dy, null),
        isNull,
      );
    });
  });

  group('DragController', () {
    late List<String> log;
    late int clock;
    late DragController c;
    late Anchor? lastAnchor;

    setUp(() {
      log = [];
      clock = 0;
      lastAnchor = null;
      c = DragController(
        deps: DragDeps(
          layout: () => l,
          // Slot 2 is spent, so it must never lift.
          pieceCells: (slot) => slot == 2 ? null : dot,
        ),
        handlers: DragHandlers(
          onLift: (s) => log.add('lift $s'),
          onUpdate: (s, centre, a) {
            lastAnchor = a;
            log.add('update $s');
          },
          onCommit: (s, a) {
            lastAnchor = a;
            log.add('commit $s ${a ?? 'none'}');
          },
          onTap: (s) => log.add('tap $s'),
          onCancel: (s) => log.add('cancel $s'),
        ),
        now: () => clock,
      );
    });

    PointerDownEvent down(Offset p, {int pointer = 1}) =>
        PointerDownEvent(pointer: pointer, position: p);
    PointerMoveEvent move(Offset p, {int pointer = 1}) =>
        PointerMoveEvent(pointer: pointer, position: p);
    PointerUpEvent up(Offset p, {int pointer = 1}) =>
        PointerUpEvent(pointer: pointer, position: p);
    PointerCancelEvent cancel(Offset p, {int pointer = 1}) =>
        PointerCancelEvent(pointer: pointer, position: p);

    Offset inSlot(int i) => l.slots[i].center;

    test('pointer down on a tray slot lifts that piece', () {
      c.onPointerDown(down(inSlot(0)));
      expect(log, ['lift 0', 'update 0']);
      expect(c.isDragging, isTrue);
      expect(c.draggingSlot, 0);
    });

    test('pointer down on an empty slot lifts nothing', () {
      c.onPointerDown(down(inSlot(2)));
      expect(log, isEmpty);
      expect(c.isDragging, isFalse);
    });

    test('pointer down outside the tray lifts nothing', () {
      c.onPointerDown(down(l.board.center));
      expect(log, isEmpty);
    });

    test('a short, still release rotates instead of placing', () {
      c.onPointerDown(down(inSlot(0)));
      clock = tapMs - 1;
      c.onPointerUp(up(inSlot(0)));
      expect(log.last, 'tap 0');
    });

    test('a release after a long hold commits, even without movement', () {
      // Holding still is how a drag begins, so a long hold must NOT be read
      // as a tap — this is why long-press was rejected as the rotate gesture.
      c.onPointerDown(down(inSlot(0)));
      clock = tapMs + 1;
      c.onPointerUp(up(inSlot(0)));
      expect(log.last, startsWith('commit 0'));
    });

    test('a release after real movement commits, however quick', () {
      c.onPointerDown(down(inSlot(0)));
      c.onPointerMove(move(inSlot(0) + const Offset(0, -40)));
      clock = 10;
      c.onPointerUp(up(inSlot(0) + const Offset(0, -40)));
      expect(log.last, startsWith('commit 0'));
    });

    test('movement under the tap threshold is still a tap', () {
      c.onPointerDown(down(inSlot(0)));
      c.onPointerMove(move(inSlot(0) + const Offset(3, -4)));
      clock = 100;
      c.onPointerUp(up(inSlot(0) + const Offset(3, -4)));
      expect(log.last, 'tap 0');
    });

    test('dragging over the board produces a live anchor', () {
      c.onPointerDown(down(inSlot(0)));
      final target = centreFor(3, 3, 1, 1);
      c.onPointerMove(
        move(Offset(target.cx, target.cy + liftOffset)),
      );
      expect(lastAnchor, const Anchor(3, 3));
    });

    test('an invalid release reports a null anchor, so the piece survives', () {
      c.onPointerDown(down(inSlot(0)));
      // Drag sideways off the board entirely.
      c.onPointerMove(move(const Offset(-400, 300)));
      clock = tapMs + 1;
      c.onPointerUp(up(const Offset(-400, 300)));
      expect(log.last, 'commit 0 none');
      expect(lastAnchor, isNull);
    });

    test('pointer cancel puts the piece back', () {
      c.onPointerDown(down(inSlot(1)));
      c.onPointerCancel(cancel(inSlot(1)));
      expect(log.last, 'cancel 1');
      expect(c.isDragging, isFalse);
    });

    test('a second pointer cannot hijack a drag in progress', () {
      c.onPointerDown(down(inSlot(0)));
      log.clear();
      c.onPointerDown(down(inSlot(1), pointer: 2));
      c.onPointerMove(move(l.board.center, pointer: 2));
      c.onPointerUp(up(l.board.center, pointer: 2));
      expect(log, isEmpty, reason: 'events from pointer 2 are ignored');
      expect(c.draggingSlot, 0);
    });

    test('abort cancels without committing', () {
      c.onPointerDown(down(inSlot(0)));
      c.abort();
      expect(log.last, 'cancel 0');
      expect(c.isDragging, isFalse);
      c.abort();
      expect(log.where((e) => e == 'cancel 0'), hasLength(1));
    });

    test('events after a release are ignored', () {
      c.onPointerDown(down(inSlot(0)));
      clock = tapMs + 1;
      c.onPointerUp(up(inSlot(0)));
      log.clear();
      c.onPointerMove(move(l.board.center));
      c.onPointerUp(up(l.board.center));
      c.onPointerCancel(cancel(l.board.center));
      expect(log, isEmpty);
    });
  });
}
