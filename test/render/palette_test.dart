import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/render/theme.dart';

/// The palette's contrast guarantees, re-measured on every run.
///
/// A palette is the easiest thing in a codebase to break by eye: someone
/// nudges one hex to "look nicer" and a whole theme quietly drops under the
/// threshold. Writing the numbers in a comment does not prevent that; this
/// does.
///
/// Thresholds are WCAG: 4.5:1 for normal text, 3:1 for large text and non-text
/// UI (which is what a board cell is).
void main() {
  double channel(double c) {
    final s = c / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  double luminance(Color c) =>
      0.2126 * channel((c.r * 255).roundToDouble()) +
      0.7152 * channel((c.g * 255).roundToDouble()) +
      0.0722 * channel((c.b * 255).roundToDouble());

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  // One palette since 2026-11-12 (`docs/07` §4i). Still a map and still a
  // loop: every guarantee below is a property of *a* palette, not of this one,
  // so a second palette added later is measured the moment it is named here.
  final themes = {'dark': LoomPalette.dark};

  themes.forEach((name, p) {
    group('$name theme', () {
      test('body and muted text clear 4.5:1 on every surface', () {
        for (final surface in {
          'background': p.background,
          'panel': p.panel,
          'boardBackground': p.boardBackground,
        }.entries) {
          for (final fg in {'ink': p.ink, 'inkMuted': p.inkMuted}.entries) {
            expect(
              contrast(fg.value, surface.value),
              greaterThanOrEqualTo(4.5),
              reason: '${fg.key} on ${surface.key}',
            );
          }
        }
      });

      test('the ink variants of accent and warn clear 4.5:1 as text', () {
        for (final surface in {
          'background': p.background,
          'panel': p.panel,
          'boardBackground': p.boardBackground,
        }.entries) {
          expect(
            contrast(p.accentInk, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'accentInk on ${surface.key}',
          );
          expect(
            contrast(p.warnInk, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'warnInk on ${surface.key}',
          );
        }
      });

      test('onAccent is readable on an accent fill', () {
        // The primary button. `onAccent` and `accent` are separate tokens
        // because text on a fill is a different job from the fill itself —
        // the light palette made that unmissable and this outlived it.
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
      });

      test('accent works as a fill against every surface it fills on', () {
        // The progress bar fills over an emptyCell track, so that pair matters
        // more than accent-on-panel does — it is the one a player reads every
        // placement.
        expect(contrast(p.accent, p.emptyCell), greaterThanOrEqualTo(3.0));
        expect(contrast(p.accent, p.panel), greaterThanOrEqualTo(3.0));
        expect(contrast(p.accent, p.background), greaterThanOrEqualTo(3.0));
      });

      test('warn works as a non-text indicator', () {
        expect(contrast(p.warn, p.panel), greaterThanOrEqualTo(3.0));
        expect(contrast(p.warn, p.background), greaterThanOrEqualTo(3.0));
      });

      test('every yarn clears 3:1 against an empty cell', () {
        // THE load-bearing contrast: it is how a player reads the board.
        for (var n = 1; n <= 9; n++) {
          expect(
            contrast(p.yarnFor(n), p.emptyCell),
            greaterThanOrEqualTo(3.0),
            reason: 'yarn $n (${LoomPalette.sizeName(n)})',
          );
        }
      });

      test('the knot mark reads against the knot it is drawn on', () {
        // The mark is the non-colour half of "this cell is a defect", so if it
        // is invisible the knot is encoded by hue alone.
        expect(contrast(p.knotMark, p.knot), greaterThanOrEqualTo(3.0));
      });

      test('a knot is distinguishable from an empty cell and from yarn', () {
        expect(contrast(p.knot, p.emptyCell), greaterThanOrEqualTo(1.6));
        // And from every yarn, so a knot never reads as ordinary thread. The
        // drawn cross does the rest of the work, which is why this bar is
        // lower than 3:1 — colour is the second cue here, not the only one.
        for (var n = 1; n <= 9; n++) {
          expect(
            contrast(p.knot, p.yarnFor(n)),
            greaterThanOrEqualTo(1.4),
            reason: 'knot vs yarn $n',
          );
        }
      });

      test('an empty cell is visible against the board behind it', () {
        expect(contrast(p.emptyCell, p.boardBackground), greaterThan(1.05));
        expect(contrast(p.gridLine, p.boardBackground), greaterThan(1.05));
      });

      test('the yarn ramp is monotonic, so greyscale keeps the order', () {
        final lums = [for (var n = 1; n <= 9; n++) luminance(p.yarnFor(n))];
        for (var i = 0; i < lums.length - 1; i++) {
          expect(
            lums[i],
            greaterThan(lums[i + 1]),
            reason: 'yarn ${i + 1} must be lighter than yarn ${i + 2}',
          );
        }
      });

      test('adjacent weights are NOT claimed to be separable by luminance', () {
        // Documents the honest limit rather than hiding it. Nine steps inside
        // the range the 3:1 floor allows land ~1.16:1 apart, which is not a
        // reliable difference — so nothing in the game may encode information
        // in yarn colour alone. A motif's cell count is legible from its own
        // shape, which is what makes that acceptable here.
        final lums = [for (var n = 1; n <= 9; n++) luminance(p.yarnFor(n))];
        final steps = [
          for (var i = 0; i < lums.length - 1; i++)
            (lums[i] + 0.05) / (lums[i + 1] + 0.05),
        ];
        expect(steps.reduce(math.max), lessThan(1.4));
      });

      test('rarity colours are visible on a card panel', () {
        final table = rarityColours;
        expect(table, hasLength(3));
        for (final entry in table.entries) {
          expect(
            contrast(entry.value, p.panel),
            greaterThanOrEqualTo(3.0),
            reason: entry.key,
          );
        }
      });

      test('rarity colours differ from each other, not just from the card', () {
        final table = rarityColours.values.toList();
        for (var i = 0; i < table.length; i++) {
          for (var j = i + 1; j < table.length; j++) {
            expect(contrast(table[i], table[j]), greaterThan(1.25));
          }
        }
      });

      test('an unknown rarity falls back instead of throwing', () {
        expect(rarityColour(p, 'mythic'), p.inkMuted);
      });
    });
  });

  group('tokens', () {
    test('the tap target satisfies both platform minimums', () {
      expect(minTapTarget, greaterThanOrEqualTo(48.0)); // Android dp
      expect(minTapTarget, greaterThanOrEqualTo(44.0)); // iOS pt
    });

    test('no font size is below the legibility floor', () {
      for (final size in [
        FontSize.hero,
        FontSize.title,
        FontSize.heading,
        FontSize.body,
        FontSize.bodySm,
        FontSize.label,
        FontSize.micro,
      ]) {
        expect(size, greaterThanOrEqualTo(minFontSize));
      }
    });

    test('the type scale is strictly descending', () {
      const scale = [
        FontSize.hero,
        FontSize.title,
        FontSize.heading,
        FontSize.body,
        FontSize.bodySm,
        FontSize.label,
        FontSize.micro,
      ];
      for (var i = 0; i < scale.length - 1; i++) {
        expect(scale[i], greaterThan(scale[i + 1]));
      }
    });

    test('the spacing scale is a 4/8 rhythm', () {
      for (final s in [
        Space.xs,
        Space.sm,
        Space.md,
        Space.lg,
        Space.xl,
        Space.xxl,
      ]) {
        expect(s % 4, 0, reason: '$s is off the rhythm');
      }
    });

    test('an exit is faster than its entrance', () {
      expect(
        Motion.overlayOut.inMilliseconds,
        lessThan(Motion.overlay.inMilliseconds),
      );
      expect(
        Motion.overlayOut.inMilliseconds / Motion.overlay.inMilliseconds,
        closeTo(0.7, 0.1),
      );
    });

    test('a four-line clear fits the 400ms animation budget', () {
      // spec §8. The flash and the settle overlap rather than queue.
      final longest = math.max(
        Motion.clearFlash.inMilliseconds,
        Motion.settle.inMilliseconds,
      );
      expect(longest, lessThan(400));
    });

    test('a full stagger stays short enough not to feel like a queue', () {
      expect(Motion.stagger.inMilliseconds, inInclusiveRange(30, 50));
      expect(Motion.stagger.inMilliseconds * 4, lessThan(250));
    });
  });

  group('seed codes', () {
    test('are short enough to read aloud and round-trip', () {
      for (final seed in [0, 1, 12345, 0xFFFFFFFF, 999999]) {
        final code = seedCode(seed);
        expect(code.length, lessThanOrEqualTo(7));
        expect(parseSeedCode(code), seed);
      }
    });

    test('reject nonsense rather than returning a wrong seed', () {
      expect(parseSeedCode(''), isNull);
      expect(parseSeedCode('!!!'), isNull);
      expect(parseSeedCode('ZZZZZZZZZZ'), isNull);
    });
  });

  group('formatScore', () {
    test('groups thousands', () {
      expect(formatScore(0), '0');
      expect(formatScore(999), '999');
      expect(formatScore(1000), '1,000');
      expect(formatScore(1118), '1,118');
      expect(formatScore(1234567), '1,234,567');
      expect(formatScore(-1500), '-1,500');
    });
  });
}
