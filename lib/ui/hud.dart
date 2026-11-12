/// The HUD.
///
/// ```
///  │ stage 3      seed   ⚙   │  safe-area top
///  │ 1,240 / 1,327    22 left│  target progress, always visible
///  │ ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░  │
///  │ ×2.40              ●●   │  multiplier = the hero number
/// ```
///
/// The multiplier is the hero number because it is the real resource — the
/// thing the player is protecting (spec §8). Target progress is *always*
/// visible: a stage you cannot see the end of is a stage you cannot plan.
library;

import 'package:flutter/material.dart';

import '../core/run.dart';
import '../game/run_controller.dart';
import '../core/shapes.dart';
import '../render/theme.dart';
import 'widgets.dart';

class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.controller,
    required this.palette,
    required this.onSettings,
  });

  final RunController controller;
  final LoomPalette palette;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = c.ladder;
    final progress = stageProgress(l);
    final fault = c.activeFault;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One line, one Flexible. The stage, the act and the seed used to be
          // three separate children here and together they exceeded the width
          // at a large text scale, with nowhere to wrap to. The seed moved to
          // the settings sheet: it is reference information a player copies
          // once, not live state they read every placement.
          Row(
            children: [
              Expanded(
                child: Text(
                  'LEVEL ${l.stage} / ${c.tuning.curve.stages}'
                  '   ACT ${actOf(l.stage)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: FontSize.label,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // The run total lives here, not beside the multiplier. On a
              // 360dp screen it was jammed hard against "RHYTHM" and the two
              // read as one word — and a run-level number belongs with the
              // other run-level numbers anyway, not competing with the hero.
              Text(
                'total ${formatScore(l.score.total)}',
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: FontSize.label,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: Space.xs),
              // Icon-only, so it needs a name: "Settings" is what a screen
              // reader and a long-press tooltip both announce. The 32x32 box
              // it used to carry was under both platform minimums.
              IconButton(
                onPressed: onSettings,
                tooltip: 'Settings',
                // `semanticLabel` on the Icon, not just `tooltip`: the
                // tooltip's label lands on an ancestor node, so the button a
                // screen reader actually focuses was announcing only "button".
                icon: Icon(
                  Icons.settings,
                  size: 20,
                  color: palette.inkMuted,
                  semanticLabel: 'Settings',
                ),
                constraints: const BoxConstraints(
                  minWidth: minTapTarget,
                  minHeight: minTapTarget,
                ),
              ),
            ],
          ),
          Semantics(
            label: 'Level ${l.stage} of ${c.tuning.curve.stages}. '
                '${l.stageScore} of ${l.target} points. '
                '${l.placementsLeft} moves left.',
            child: const SizedBox.shrink(),
          ),
          // Both halves are Flexible: at a large text scale the score, the
          // target and the warp count together exceed the width, and this row
          // has nowhere to wrap to.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatScore(l.stageScore),
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: FontSize.title,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Flexible(
                      child: Text(
                        ' / ${formatScore(l.target)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.inkMuted,
                          fontSize: FontSize.body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              // Running out of warp is currently signalled by the number
              // turning red, which is colour-only. The warning icon carries
              // the same information without it.
              if (l.placementsLeft <= 3) ...[
                Icon(Icons.error_outline, size: 15, color: palette.warnInk),
                const SizedBox(width: Space.xs),
              ],
              Text(
                '${l.placementsLeft}',
                style: TextStyle(
                  color: l.placementsLeft <= 3
                      ? palette.warnInk
                      : palette.ink,
                  fontSize: FontSize.heading,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Flexible(
                child: Text(
                  ' moves left',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: FontSize.label,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.gridLine),
            ),
            clipBehavior: Clip.antiAlias,
            child: LinearProgressIndicator(
              value: progress,
              // 6px was a hairline against a dark board. 8 is still slim and
              // actually visible, and it keeps the 4/8 rhythm.
              minHeight: Space.sm,
              semanticsLabel: 'Level progress',
              semanticsValue: '${(progress * 100).round()}%',
              backgroundColor: palette.emptyCell,
              valueColor: AlwaysStoppedAnimation(
                progress >= 1 ? palette.accent : palette.yarnFor(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Three explicit flex shares rather than a Spacer competing with
          // two loose Flexibles: that combination left the pip strip with
          // almost no width and overflowed it. The hero keeps the largest
          // share, so it is the last thing to give way.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The hero number, announced together with the patience pips
              // beside it — "times two point four" on its own does not say
              // what is about to be lost.
              //
              // FittedBox keeps it at full size whenever there is room and
              // shrinks it only when there is not, so it gives way last.
              Flexible(
                flex: 4,
                child: Semantics(
                  label:
                      'Combo ${l.score.multiplier.toStringAsFixed(2)} times. '
                      '${l.score.patience} of ${c.scoring.patienceMax} '
                      'misses left'
                      '${l.score.shields > 0 ? ', ${l.score.shields} shields' : ''}',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '×${l.score.multiplier.toStringAsFixed(2)}',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: l.score.multiplier > 1.0
                            ? palette.accentInk
                            : palette.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Flexible(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PatiencePips(
                      palette: palette,
                      patience: l.score.patience,
                      max: c.scoring.patienceMax,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'COMBO',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: FontSize.micro,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (l.score.shields > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < l.score.shields; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: Space.xs),
                        child: Icon(
                          Icons.shield,
                          size: 16,
                          color: palette.yarnFor(7),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (fault != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 14, color: palette.warn),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      '${fault.name} — ${fault.rule}',
                      style: TextStyle(color: palette.warnInk, fontSize: FontSize.label),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PatiencePips extends StatelessWidget {
  const _PatiencePips({
    required this.palette,
    required this.patience,
    required this.max,
  });

  final LoomPalette palette;
  final int patience;
  final int max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < max; i++)
        Padding(
          padding: const EdgeInsets.only(right: Space.xs),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < patience ? palette.ink : palette.emptyCell,
              border: Border.all(color: palette.gridLine),
            ),
          ),
        ),
    ],
  );
}

/// The charged tools a run has drafted: Eraser, Bomb, Reshuffle, Swap Tray,
/// Clear row/col.
///
/// **This is pinned in the screen's column, not placed inside the HUD.** It
/// used to be the last child of [Hud], which lives in a height-capped
/// `SingleChildScrollView` — so as soon as the readouts above it grew (a long
/// fault name, a large text scale, a short phone) the tools scrolled out of
/// sight between the header and the board, with no scrollbar to say they were
/// there.
///
/// That is worse than untidy. These are charge-limited escape valves priced at
/// 12–20% of a stage's capability each (docs/05 §3), and a tool the player
/// cannot see is a card they paid a pick for and will never spend. Anything
/// the player *acts on* belongs outside a scrollable; readouts can scroll.
///
/// It renders nothing at all when there is nothing to show, so the board keeps
/// the space until a tool is actually drafted.
class ToolRow extends StatelessWidget {
  const ToolRow({super.key, required this.controller, required this.palette});

  final RunController controller;
  final LoomPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final buttons = _buttons(c);
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 6),
      // Horizontal, so a wide set of tools at a large text scale runs off the
      // side where the player can reach it rather than off the top.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: buttons),
      ),
    );
  }

  List<Widget> _buttons(RunController c) {
    return [
          if (c.hasTool('unpick'))
            ToolButton(
              palette: palette,
              label: 'Eraser',
              // `backspace` is text deletion — a left arrow with an X. This
              // erases one cell of the board, so a square with a line through
              // it says it better.
              icon: Icons.deselect,
              charges: c.toolCharges['unpick'] ?? 0,
              active: c.aiming == ToolAim.unpick,
              onPressed: () => c.aiming == ToolAim.unpick
                  ? c.cancelAim()
                  : c.aimTool('unpick'),
            ),
          if (c.hasTool('shears')) ...[
            const SizedBox(width: Space.sm),
            ToolButton(
              palette: palette,
              label: 'Bomb',
              // Was `content_cut`, a pair of scissors — left over from the
              // card's weaving name, Shears, after the player-facing label
              // became Bomb. The icon and the label were telling the player
              // two different things. A burst is what clearing a 2x2 is.
              icon: Icons.flare,
              charges: c.toolCharges['shears'] ?? 0,
              active: c.aiming == ToolAim.shears,
              onPressed: () => c.aiming == ToolAim.shears
                  ? c.cancelAim()
                  : c.aimTool('shears'),
            ),
          ],
          if (c.hasTool('rethread')) ...[
            const SizedBox(width: Space.sm),
            ToolButton(
              palette: palette,
              label: 'Reshuffle',
              // `refresh` reads as "retry". This shuffles the tray.
              icon: Icons.shuffle,
              charges: c.toolCharges['rethread'] ?? 0,
              onPressed: c.rethread,
            ),
          ],
          if (c.hasTool('resley')) ...[
            const SizedBox(width: Space.sm),
            ToolButton(
              palette: palette,
              label: 'Swap Tray',
              icon: Icons.swap_horiz,
              charges: c.toolCharges['resley'] ?? 0,
              onPressed: c.resley,
            ),
          ],
          if (c.battenCharges > 0) ...[
            const SizedBox(width: Space.sm),
            ToolButton(
              palette: palette,
              label: 'Clear row',
              // A matched pair with Clear col below, so the two read as one
              // mechanic on two axes.
              icon: Icons.table_rows,
              charges: c.battenCharges,
              active: c.aiming == ToolAim.battenRow,
              onPressed: () => c.aimBatten(row: true),
            ),
            const SizedBox(width: Space.sm),
            ToolButton(
              palette: palette,
              label: 'Clear col',
              // **Was `more_vert`** — the three-dot overflow menu, which every
              // phone user reads as "more options" and nobody reads as "clear
              // a column". Material has no vertical rule, so the columns glyph
              // is the honest choice.
              icon: Icons.view_column,
              charges: c.battenCharges,
              active: c.aiming == ToolAim.battenCol,
              onPressed: () => c.aimBatten(row: false),
            ),
          ],
    ];
  }
}

/// Jacquard Card: see the next refill before spending the current tray.
class NextRefillStrip extends StatelessWidget {
  const NextRefillStrip({
    super.key,
    required this.controller,
    required this.palette,
  });

  final RunController controller;
  final LoomPalette palette;

  @override
  Widget build(BuildContext context) {
    final peek = controller.nextRefillPeek;
    if (peek.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            'NEXT',
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: FontSize.micro,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          for (final s in peek)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: MotifThumb(shapeId: s.id, palette: palette, size: 22),
            ),
        ],
      ),
    );
  }
}

/// Hold: the set-aside motif, draggable like a tray slot.
class HoldIndicator extends StatelessWidget {
  const HoldIndicator({
    super.key,
    required this.controller,
    required this.palette,
  });

  final RunController controller;
  final LoomPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.powers.hasHold) return const SizedBox.shrink();
    if (c.holdItem != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'HOLD',
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: FontSize.micro,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: Space.sm),
          // These were 26px GestureDetectors with no press feedback: too
          // small to hit reliably and silent when you did. InkWell inside a
          // Material gives the ripple, and the box is padded to the minimum.
          for (var i = 0; i < c.tray.length; i++)
            if (c.tray[i] != null)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: Semantics(
                  button: true,
                  label: 'Hold ${shapeName(c.tray[i]!.shapeId)}',
                  excludeSemantics: true,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => c.holdPiece(i),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: minTapTarget,
                        height: minTapTarget,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: palette.gridLine),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: MotifThumb(
                          shapeId: c.tray[i]!.shapeId,
                          rotation: c.tray[i]!.rotation,
                          palette: palette,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
