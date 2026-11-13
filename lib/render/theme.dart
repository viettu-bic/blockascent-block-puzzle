/// Palette and theme.
///
/// ## Colour keys off cell count, not shape identity
///
/// This is both the visual design and the trade-dress defence (spec §4, §11).
/// Yarn weight is assigned by motif size, so a 4-cell motif is always the same
/// yarn whatever its shape. **Never** use the canonical tetromino colourway
/// (cyan I, yellow O, purple T, green S, red Z, blue J, orange L) — and note
/// that keying by size rather than by silhouette makes that colourway
/// unreachable by construction, which is the point.
///
/// ## Contrast and colourblind play
///
/// Every value here was measured, not eyeballed, and `test/render/palette_test.dart`
/// re-measures it on every run.
///
/// The load-bearing contrast in this game is **filled cell versus empty cell**:
/// it is how a player reads the board at all. Every one of the nine yarns
/// clears 3:1 against [emptyCell], which is the non-text UI threshold.
/// Getting there is why the ramp spans a narrower lightness
/// range than a naive dark-to-light gradient would: the heavy end cannot go as
/// dark as the dye names suggest without disappearing into the board.
///
/// The ramp is also monotonic in luminance, so a greyscale rendering keeps the
/// weights in the right *order*. It does **not** make adjacent weights
/// distinguishable by luminance alone — nine steps inside that range sit about
/// 1.16:1 apart, which is not a reliable difference. That is acceptable here
/// and nowhere else: a motif's cell count is already legible from its own
/// shape, so yarn colour is redundant encoding rather than the only channel.
/// Anywhere colour carries information that shape does not — the ghost states,
/// knots, fault warnings — a second non-colour cue is mandatory, which is what
/// spec §7.5 requires.
///
/// ## Semantic roles, not one colour per concept
///
/// [accent] and [warn] are **fills and indicators** (3:1, non-text).
/// [accentInk] and [warnInk] are the **text** versions of the same ideas
/// (4.5:1), and [onAccent] is text drawn *on* an accent fill.
///
/// On this palette each pair happens to coincide, and the pairs are kept
/// apart anyway. They were separate because a gold that worked as a button
/// fill on the light palette was far too pale to read as text; the light
/// palette is gone (`docs/07` §4i), but the call sites still say which job
/// they are asking for, and that is the half of the distinction worth having.
library;


import 'package:flutter/material.dart';

/// The provisional title, in exactly one place.
///
/// Pending a direct App Store / Google Play title search and a trademark check
/// on `Loomcraft` in the games/software class (spec §11, docs/03 §6). Keep it
/// here and **out of the bundle identifier** until that clears.
const String gameTitle = 'Blockascent';
const String gameSubtitle = 'Block Puzzle';
const String gameFullTitle = '$gameTitle: $gameSubtitle';

class LoomPalette {
  const LoomPalette({
    required this.background,
    required this.frame,
    required this.boardBackground,
    required this.emptyCell,
    required this.gridLine,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.onAccent,
    required this.accentInk,
    required this.warn,
    required this.warnInk,
    required this.knot,
    required this.knotMark,
    required this.yarns,
    required this.weaveLine,
    required this.panel,
    required this.highlight,
    required this.shadow,
  });

  final Color background;
  final Color frame;
  final Color boardBackground;
  final Color emptyCell;
  final Color gridLine;
  final Color ink;
  final Color inkMuted;

  /// Accent as a **fill or indicator** — progress bars, primary buttons,
  /// borders. Non-text, so the bar is 3:1.
  final Color accent;

  /// Text drawn on top of an [accent] fill. 4.5:1 against [accent].
  final Color onAccent;

  /// Accent as **text or a thin border** on [background] / [panel]. 4.5:1.
  final Color accentInk;

  /// Warning as a fill or indicator. Non-text, 3:1.
  final Color warn;

  /// Warning as **text**. 4.5:1 against [background], [panel] and
  /// [boardBackground].
  final Color warnInk;

  final Color knot;

  /// The crossed slub drawn through a knot — the cue that says "defect" when
  /// hue is unavailable, so it has to clear 3:1 against [knot] itself. It was
  /// previously the background colour at 55% alpha, which in dark mode put a
  /// near-black mark on a dark-brown cell and conveyed nothing.
  final Color knotMark;

  /// Index 0 is unused; 1..9 are the yarn weights by cell count.
  final List<Color> yarns;
  final Color weaveLine;
  final Color panel;

  /// The thread-catching-the-light overlay on a filled cell, and the drop
  /// shadow under a held piece. Tokens rather than raw `Colors.white` /
  /// `Colors.black` so a theme owns every colour the painter can draw.
  final Color highlight;
  final Color shadow;

  Color yarnFor(int cellCount) => yarns[cellCount.clamp(1, yarns.length - 1)];

  /// Plain size words, so a player can name a block without naming a colour
  /// — which is also the one label a colourblind player can always rely on.
  /// One word per thing: a **block** is the piece you place, a **cell** is a
  /// square of the board. These count cells, and saying "3 blocks" for a
  /// three-cell block was the single most confusing string in the game
  /// (UX review 6.2, 8.1).
  static const List<String> sizeNames = [
    '',
    '1 cell',
    '2 cells',
    '3 cells',
    '4 cells',
    '5 cells',
    '6 cells',
    '7 cells',
    '8 cells',
    '9 cells',
  ];

  static String sizeName(int cellCount) =>
      sizeNames[cellCount.clamp(1, sizeNames.length - 1)];

  /// The palette. Not the default one — the only one, since 2026-11-12
  /// (`docs/07` §4i). The game does not follow the system light/dark setting:
  /// the night sky is the product, and the store art has to read
  /// roguelite-with-stakes rather than cozy-craft (docs/03 §5).
  static const LoomPalette dark = LoomPalette(
    background: Color(0xFF14161C),
    frame: Color(0xFF0E1014),
    boardBackground: Color(0xFF1B1F28),
    emptyCell: Color(0xFF232833),
    gridLine: Color(0xFF3A4150),
    ink: Color(0xFFF2EDE2),
    inkMuted: Color(0xFF8D9099),
    accent: Color(0xFFE8C77A),
    onAccent: Color(0xFF14161C),
    accentInk: Color(0xFFE8C77A),
    warn: Color(0xFFD4654B),
    warnInk: Color(0xFFDE7257),
    // Below the whole yarn ramp in luminance, on purpose: a knot is a defect,
    // and at #6B625A it sat inside the ramp and read as another thread.
    knot: Color(0xFF514A42),
    knotMark: Color(0xFFA69E92),
    weaveLine: Color(0xFF20242E),
    panel: Color(0xFF1E222C),
    highlight: Color(0x1AFFFFFF),
    shadow: Color(0x47000000),
    // Light yarn on a dark cell. The span stops at Y=0.17 because anything
    // darker drops under 3:1 against emptyCell — the heavy end is held up by
    // that floor, not by the dye names.
    yarns: [
      Color(0x00000000),
      Color(0xFFDAC47E), // 1 — Ecru
      Color(0xFFE5B106), // 2 — Weld
      Color(0xFFF79635), // 3 — Ochre
      Color(0xFFEF846F), // 4 — Madder
      Color(0xFFE4729C), // 5 — Cochineal
      Color(0xFFC16DCE), // 6 — Logwood
      Color(0xFF7E7AD5), // 7 — Indigo
      Color(0xFF2885A2), // 8 — Woad
      Color(0xFF23825E), // 9 — Myrtle
    ],
  );

}

/// Rarity colours for draft cards. Code does the systematic part — the frame,
/// the rarity colour, the charge pips — and never bakes it into an image
/// (docs/03 §4b).
///
/// Rarity is never the *only* cue: a card also shows its rarity as a word, and
/// a fault shows its tier as filled pips, because a rarity a player cannot
/// distinguish is a rarity that does not exist.
/// Spaced in **luminance**, not just hue: at the first pass these three were
/// a grey, a blue and a gold of near-identical lightness, so the tiers were
/// hue-only and a colourblind player could not rank them at all. Brighter is
/// rarer. The printed rarity word remains the non-colour cue regardless.
///
/// There was a second table for the light palette, where darker was rarer.
/// It went with the palette (`docs/07` §4i).
const Map<String, Color> rarityColours = {
  'common': Color(0xFF6C737E),
  'uncommon': Color(0xFF4DA5CB),
  'rare': Color(0xFFE9C767),
};

Color rarityColour(LoomPalette p, String rarity) =>
    rarityColours[rarity] ?? p.inkMuted;

/* ------------------------------------------------------------------ */
/* Spacing                                                            */
/* ------------------------------------------------------------------ */

/// A 4/8 rhythm. Every gap, pad and inset in the UI comes from here, so
/// "slightly off" spacing cannot creep in one widget at a time.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Minimum tap target.
///
/// 48 rather than 44: Android asks for 48dp and iOS for 44pt, and one number
/// that satisfies both is worth more than two that have to be chosen between
/// at every call site. Visual size may be smaller — the *hit area* may not.
const double minTapTarget = 48.0;

/// Smallest type the UI is allowed to use.
///
/// Anything under this is unreadable on a phone in a lit room, and it is the
/// single most common way a dense game HUD turns into a wall of grey mush.
const double minFontSize = 11.0;

/* ------------------------------------------------------------------ */
/* Type scale                                                         */
/* ------------------------------------------------------------------ */

/// One scale, floored at [minFontSize].
///
/// `hero` is the multiplier readout — the one number the whole HUD is arranged
/// around (spec §8) — and is the only size allowed to be large.
abstract final class FontSize {
  static const double hero = 40;
  static const double title = 24;
  static const double heading = 18;
  static const double body = 15;
  static const double bodySm = 13;
  static const double label = 12;
  static const double micro = minFontSize;
}

/* ------------------------------------------------------------------ */
/* Motion                                                             */
/* ------------------------------------------------------------------ */

/// Shared motion tokens, so every transition in the game shares one rhythm
/// instead of each widget inventing a duration.
///
/// Chosen by distance and complexity, not copied from one value: a cell flash
/// travels no distance and is fast; an overlay covers the screen and is slower.
/// Exits run at roughly 70% of their entrance, because a dismissal that takes
/// as long as a presentation feels like lag.
///
/// The total for a four-line clear stays inside the 400ms budget in spec §8:
/// [clearFlash] 120 + [settle] 90 run concurrently, not in sequence.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration clearFlash = Duration(milliseconds: 120);
  static const Duration settle = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration overlay = Duration(milliseconds: 240);
  static const Duration overlayOut = Duration(milliseconds: 170);

  /// Entrance: decelerate into place.
  static const Curve enter = Curves.easeOutCubic;

  /// Exit: accelerate away.
  static const Curve exit = Curves.easeInCubic;

  /// A press, which should feel springy rather than linear.
  static const Curve press = Curves.easeOutBack;

  /// Per-item delay when a list reveals itself. Low enough that a three-card
  /// draft is fully on screen in under 100ms of stagger.
  static const Duration stagger = Duration(milliseconds: 40);
}

/// Is the player asking for less motion?
///
/// Every animation in this game is decorative — the board state is already
/// updated when a flash begins — so honouring this is a matter of skipping to
/// the final frame, never of withholding information.
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The largest text scale the game's fixed-geometry screens can absorb.
///
/// The board is a square grid of fixed cells and the HUD sits above it, so text
/// cannot reflow indefinitely the way a document can. Rather than ignore the
/// system setting — which would be the easy and wrong answer — the game honours
/// it up to this bound and then stops, which keeps large-text users readable
/// without pushing the tray off the bottom of the screen.
const double maxTextScale = 1.4;

ThemeData buildTheme(LoomPalette p) {
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: Brightness.dark,
  ).copyWith(surface: p.background, onSurface: p.ink);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    textTheme: Typography.material2021(platform: TargetPlatform.iOS)
        .black
        .apply(bodyColor: p.ink, displayColor: p.ink)
        .copyWith(
          // The multiplier is the hero number (spec §8), so it gets its own
          // tabular-figure style: a count-up that changes width jitters.
          displayLarge: TextStyle(
            fontSize: FontSize.hero,
            fontWeight: FontWeight.w700,
            color: p.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.0,
          ),
          titleLarge: TextStyle(
            fontSize: FontSize.title,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
          titleMedium: TextStyle(
            fontSize: FontSize.heading,
            fontWeight: FontWeight.w600,
            color: p.ink,
          ),
          bodyMedium: TextStyle(
            fontSize: FontSize.body,
            color: p.ink,
            height: 1.45,
          ),
          bodySmall: TextStyle(
            fontSize: FontSize.bodySm,
            color: p.inkMuted,
            height: 1.45,
          ),
          labelSmall: TextStyle(
            fontSize: FontSize.label,
            color: p.inkMuted,
            letterSpacing: 0.8,
          ),
        ),
    sliderTheme: SliderThemeData(activeTrackColor: p.accent),
    dividerColor: p.gridLine,
    // Material's defaults are 36-40 high, under both platform minimums, so
    // they are raised once here rather than at every call site.
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(minTapTarget, minTapTarget),
        foregroundColor: p.ink,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(minTapTarget, minTapTarget),
        foregroundColor: p.accentInk,
        textStyle: const TextStyle(
          fontSize: FontSize.bodySm,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    // A visible focus ring, for switch control and an attached keyboard. The
    // default is easy to lose against a dark board.
    focusColor: p.accent.withValues(alpha: 0.30),
    splashColor: p.accent.withValues(alpha: 0.16),
    highlightColor: p.accent.withValues(alpha: 0.10),
    // Material's default is 48 and its density shrinks it; keep the floor.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
}

/// A seed as a short, typeable, copy-pasteable code.
///
/// Base 36 turns a 32-bit seed into at most seven characters, which fits in
/// the HUD and can be read aloud — the two things a shareable seed has to be.
String seedCode(int seed) =>
    (seed & 0xFFFFFFFF).toRadixString(36).toUpperCase();

/// The inverse, for a "play this seed" field. Returns null on anything that is
/// not a valid code.
int? parseSeedCode(String code) {
  final cleaned = code.trim().toLowerCase();
  if (cleaned.isEmpty || cleaned.length > 7) return null;
  final v = int.tryParse(cleaned, radix: 36);
  if (v == null || v < 0 || v > 0xFFFFFFFF) return null;
  return v;
}

/// Numbers with thousands separators, for scores. Written out rather than
/// pulling in `intl`: the game needs one format and no localisation yet.
String formatScore(int n) {
  final s = n.abs().toString();
  final sb = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) sb.write(',');
    sb.write(s[i]);
  }
  return sb.toString();
}
