import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/render/starfield.dart';

/// The sky is generated, so the things worth testing are the ones a drawing
/// could not get wrong but a generator can: that it is the same sky twice,
/// that nothing lands outside the surface it was asked for, and that a request
/// it cannot satisfy returns rather than spins.
void main() {
  const area = Rect.fromLTWH(0, 0, 400, 800);

  group('scatterStars', () {
    test('the same seed gives the same sky', () {
      final a = scatterStars(area: area, seed: 12345, count: 40);
      final b = scatterStars(area: area, seed: 12345, count: 40);
      expect(a, hasLength(b.length));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].x, b[i].x);
        expect(a[i].y, b[i].y);
        expect(a[i].r, b[i].r);
        expect(a[i].alpha, b[i].alpha);
      }
    });

    test('a different seed gives a different sky', () {
      final a = scatterStars(area: area, seed: 1, count: 40);
      final b = scatterStars(area: area, seed: 2, count: 40);
      final same = List.generate(
        a.length,
        (i) => i < b.length && a[i].x == b[i].x && a[i].y == b[i].y,
      ).where((v) => v).length;
      expect(same, lessThan(4));
    });

    test('every star is inside the area it was given', () {
      final offset = scatterStars(
        area: const Rect.fromLTWH(120, 60, 200, 300),
        seed: 7,
        count: 60,
      );
      for (final s in offset) {
        expect(s.x, inInclusiveRange(120, 320));
        expect(s.y, inInclusiveRange(60, 360));
      }
    });

    test('no two stars are inside the gap of each other', () {
      final stars = scatterStars(area: area, seed: 99, count: 50, minGap: 20);
      for (var i = 0; i < stars.length; i++) {
        for (var j = i + 1; j < stars.length; j++) {
          final close = (stars[i].x - stars[j].x).abs() < 20 &&
              (stars[i].y - stars[j].y).abs() < 20;
          expect(close, isFalse, reason: 'stars $i and $j clump');
        }
      }
    });

    test('radii and alphas stay inside their bounds', () {
      for (final s in scatterStars(area: area, seed: 3, count: 80)) {
        expect(s.r, inInclusiveRange(0.6, 1.9));
        expect(s.alpha, inInclusiveRange(0.22, 0.72));
      }
    });

    test('an impossible density returns short instead of spinning', () {
      // 300 stars 40px apart do not fit in 100x100. The bounded attempt count
      // is the only thing standing between that request and a hung frame.
      final stars = scatterStars(
        area: const Rect.fromLTWH(0, 0, 100, 100),
        seed: 5,
        count: 300,
        minGap: 40,
      );
      expect(stars.length, lessThan(300));
      expect(stars, isNotEmpty);
    });
  });

  group('starCountFor', () {
    test('scales with area and clamps at both ends', () {
      expect(starCountFor(const Size(10, 10)), 18);
      expect(starCountFor(const Size(4000, 4000)), 150);
      final phone = starCountFor(const Size(375, 812));
      expect(phone, inInclusiveRange(100, 125));
    });

    test('honours its own bounds', () {
      expect(starCountFor(const Size(10, 10), min: 4), 4);
      expect(starCountFor(const Size(4000, 4000), max: 40), 40);
    });
  });
}
