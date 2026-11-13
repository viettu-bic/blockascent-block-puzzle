/// The four rules that decide every run, said out loud — plus the one control
/// the game never mentions anywhere else.
///
/// **These are the rules the measurements said were missing** (docs/08 E2).
/// The game teaches none of its load-bearing rules, and two of them are not
/// guessable from a lifetime of other block games:
///
/// - **Rows *and* columns clear.** Everyone who picks this up assumes gravity
///   and a single axis. docs/01 §1 is explicit that this is the one thing that
///   makes it a different game.
/// - **The tray refills only when all three slots are empty.** docs/01 §2
///   calls this "the load-bearing decision" — the difference between a toy and
///   a game — and nothing on screen says it.
/// - **A one-cell hole needs a one-cell block.** Since placing scores nothing
///   (docs/05 §10) and the free roster has nothing under three cells
///   (docs/04 §9), a board clogs and **43% of early deaths are jams**. A player
///   who was never told that will read a jam as unfair rather than as a
///   consequence — which is exactly the line docs/06 §6 draws between losing to
///   a decision and losing to the dice.
///
/// **It no longer opens itself on the first launch** (UX review §1). It was
/// ~200 words behind a button that needed scrolling to reach, shown to someone
/// who had not yet seen a board — so it was skipped, and the rules it carried
/// were taught by nothing. The first launch now opens *level 1*, pre-arranged
/// so the opening move clears a column, and the rules are taught where they
/// apply. This page stays as the place to look them up: from the menu, and
/// from the "?" beside the gear mid-run.
///
/// One line per rule, deliberately. The four bodies used to run three
/// sentences each, which is a wall of prose on the screen a new player skims
/// hardest.
library;

import 'package:flutter/material.dart';

import '../core/shapes.dart';
import '../render/theme.dart';
import 'widgets.dart';

typedef Rule = ({String title, String body, List<String> motifs});

/// Shared by the full page and the in-run sheet, so the rules can never drift
/// apart between the two places they are read.
const List<Rule> howToPlayRules = [
  (
    title: 'Rows AND columns clear',
    body: 'Fill a row or column to clear it. Clear several at once for bonus '
        'points.',
    motifs: ['i4', 'i3'],
  ),
  (
    title: 'Clearing is the only way to score',
    body: 'Putting a block down earns nothing on its own.',
    motifs: ['o2', 't4'],
  ),
  (
    title: 'The tray refills only when it is empty',
    body: 'New blocks arrive after you place all 3.',
    motifs: ['s4', 'z4', 'l3'],
  ),
  (
    // Was "A one-cell hole needs a one-cell block", over a paragraph ending
    // "...and they are what the shop sells first". Both halves were read as a
    // promise that the 1×1 is cheap and early. It is the single most expensive
    // thing in the game — tier 4, 3,600 coins — while a 2-cell block arrives in
    // tier 2 for 40. The rule a player needs is the consequence, not the
    // shopping list (UX review §1.3).
    title: 'Tiny gaps can end your run',
    body: 'Small blocks from the Shop fill them.',
    motifs: ['dot', 'i2'],
  ),
];

/// The rules as a list, with the rotation hint under them.
///
/// Laid out by the caller: the page puts it in a `ListView`, the sheet in a
/// scrollable column.
List<Widget> howToPlayBody(LoomPalette palette) => [
  for (final (i, rule) in howToPlayRules.indexed) ...[
    _RuleCard(palette: palette, number: i + 1, rule: rule),
    const SizedBox(height: Space.md),
  ],
  // Not a rule — a control, and the only one the game never mentions. The
  // rotation pips under a tray block are the entire current affordance, and
  // nothing anywhere says what they are for (UX review §1.2).
  _RotateHint(palette: palette),
];

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key, required this.palette, this.onDone});

  final LoomPalette palette;

  /// Turns the footer into "Got it" rather than "Back".
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SkyBackground(
      palette: p,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('How to play'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...howToPlayBody(p),
            const SizedBox(height: Space.lg),
            SafeArea(
              top: false,
              child: LoomButton(
                palette: p,
                label: onDone == null ? 'Back' : 'Got it',
                primary: true,
                onPressed: () {
                  onDone?.call();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same rules, as a sheet that slides up over a run and leaves it running.
///
/// A player who forgets a rule mid-run had nowhere to look: the gear is
/// settings, and leaving for the menu ends the run. This is the "?" beside it
/// (UX review §4.5).
Future<void> showHowToPlaySheet(
  BuildContext context, {
  required LoomPalette palette,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.panel,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'How to play',
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: FontSize.heading,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: palette.inkMuted,
                      semanticLabel: 'Close',
                    ),
                    constraints: const BoxConstraints(
                      minWidth: minTapTarget,
                      minHeight: minTapTarget,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: howToPlayBody(palette),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RotateHint extends StatelessWidget {
  const _RotateHint({required this.palette});

  final LoomPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.rotate_right, size: 20, color: p.accentInk),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'Tap a block to rotate it.',
              style: TextStyle(
                color: p.ink,
                fontSize: FontSize.body,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.palette,
    required this.number,
    required this.rule,
  });

  final LoomPalette palette;
  final int number;
  final Rule rule;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      label: 'Rule $number. ${rule.title}. ${rule.body}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.gridLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: p.onAccent,
                      fontSize: FontSize.micro,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rule.title,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: FontSize.body,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rule.body,
              style: TextStyle(
                color: p.ink,
                fontSize: FontSize.bodySm,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            // The shapes the rule is about, so it is not four paragraphs of
            // prose on a screen a new player will skim.
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final id in rule.motifs)
                  if (shapesById.containsKey(id))
                    MotifThumb(shapeId: id, palette: p, size: 30),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
