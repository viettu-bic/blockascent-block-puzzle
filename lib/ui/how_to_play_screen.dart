/// The three rules that decide every run, said out loud.
///
/// **This is the first half of an FTUE and it exists because the measurements
/// demanded one** (docs/08 E2). The game teaches none of its load-bearing
/// rules, and two of them are not guessable from a lifetime of other block
/// games:
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
/// It shows itself once, on the first launch, which is what makes it an FTUE
/// rather than a help page nobody opens.
library;

import 'package:flutter/material.dart';

import '../core/shapes.dart';
import '../render/theme.dart';
import 'widgets.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key, required this.palette, this.onDone});

  final LoomPalette palette;

  /// Shown as "Got it" when the screen opened itself on first launch.
  final VoidCallback? onDone;

  static const List<({String title, String body, List<String> motifs})>
  _rules = [
    (
      title: 'Rows AND columns clear',
      body:
          'Fill a whole row or a whole column and it clears. Both count, and '
          'a placement that completes several at once scores far more than the '
          'same lines cleared one at a time.',
      motifs: ['i4', 'i3'],
    ),
    (
      title: 'Clearing is the only way to score',
      body:
          'Putting a block down earns nothing by itself. Points come from '
          'lines. Later you can buy or draft block bonuses, and then placing '
          'pays too — but a run that is not clearing is not scoring.',
      motifs: ['o2', 't4'],
    ),
    (
      title: 'The tray refills only when it is empty',
      body:
          'You get three blocks and you must place all three before you see '
          'three more. The third one is where runs go wrong, because you have '
          'to find room for a block you would not have chosen.',
      motifs: ['s4', 'z4', 'l3'],
    ),
    (
      title: 'A one-cell hole needs a one-cell block',
      body:
          'You start with nothing smaller than three cells, so small gaps '
          'add up and the board clogs. Getting stuck with no legal move ends '
          'the run. Small blocks are the fix, and they are what the shop sells '
          'first.',
      motifs: ['dot', 'i2'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SkyBackground(
      palette: p,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('How to Play'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Four rules decide every run. The first two are not what other '
              'block games taught you.',
              style: TextStyle(
                color: p.inkMuted,
                fontSize: FontSize.label,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            for (final (i, rule) in _rules.indexed) ...[
              _RuleCard(palette: p, number: i + 1, rule: rule),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
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

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.palette,
    required this.number,
    required this.rule,
  });

  final LoomPalette palette;
  final int number;
  final ({String title, String body, List<String> motifs}) rule;

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
