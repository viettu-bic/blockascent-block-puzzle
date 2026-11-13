/// The workshop: the title screen.
library;

import 'package:flutter/material.dart';

import '../core/shapes.dart';
import '../game/account.dart';
import '../render/theme.dart';
import 'widgets.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.account,
    required this.palette,
    required this.onPlay,
    required this.onResume,
    required this.onShop,
    required this.onHowToPlay,
    required this.onSettings,
    required this.canResume,
  });

  final Account account;
  final LoomPalette palette;
  final VoidCallback onPlay;
  final VoidCallback onResume;
  final VoidCallback onShop;
  final VoidCallback onHowToPlay;
  final VoidCallback onSettings;
  final bool canResume;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final loadout = account.loadoutShapes();

    return SkyBackground(
      palette: p,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Scrollable, with the column stretched to at least the viewport.
        //
        // It used to be a plain Column with Spacers, which overflowed by 59px on
        // a 375x667 phone and by far more at a large text scale — and a Spacer
        // cannot live inside a scroll view anyway, so the flexible gaps become
        // fixed ones. On a roomy screen this looks identical; on a cramped one
        // it scrolls instead of throwing.
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // Distributes down the viewport when there is room and falls back
                    // to its natural height (and scrolls) when there is not. Dropping
                    // the Spacers for fixed gaps fixed the overflow but left the menu
                    // stacked at the top of a tall screen with 500px of dead space
                    // under it.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: Space.sm),
                      // Scales to fit on one line whatever the title is.
                      //
                      // At a fixed hero size the name has to be short enough to fit
                      // 360dp minus the gutters, and the title is deliberately a
                      // single constant that will change again before launch — so
                      // the layout adapts to the name rather than the name having to
                      // fit the layout.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          gameTitle.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            color: p.ink,
                            fontSize: FontSize.hero,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          gameSubtitle.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            color: p.accentInk,
                            fontSize: FontSize.bodySm,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                      // No rules paragraph here (UX review §2.1). It repeated
                      // How to Play word for word, on the one screen whose job
                      // is to get the player into a run — and a player who
                      // reads rules on a title screen is a player who has not
                      // started yet.
                      const SizedBox(height: Space.xl),
                      LoomPanel(
                        palette: p,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  'COINS',
                                  style: TextStyle(
                                    color: p.inkMuted,
                                    fontSize: FontSize.micro,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const Spacer(),
                                SpoolTag(palette: p, spools: account.spools),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // "BEST" alone reads as a high score, and the
                                // value was a sentence ("level 1 · 2 won").
                                // The noun belongs in the label and the value
                                // is a number — and 0 rather than an em dash,
                                // because a dash on the first visit reads as
                                // "nothing was saved" (UX review §2.4).
                                Text(
                                  'BEST LEVEL',
                                  style: TextStyle(
                                    color: p.inkMuted,
                                    fontSize: FontSize.micro,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${account.milestones.bestStage}',
                                  style: TextStyle(
                                    color: p.ink,
                                    fontSize: FontSize.label,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  'BLOCKS',
                                  style: TextStyle(
                                    color: p.inkMuted,
                                    fontSize: FontSize.micro,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (final s in loadout)
                                        MotifThumb(
                                          shapeId: s.id,
                                          palette: p,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (canResume) ...[
                        LoomButton(
                          palette: p,
                          label: 'Continue',
                          subtitle: 'A run is still in progress',
                          primary: true,
                          onPressed: onResume,
                        ),
                        const SizedBox(height: 10),
                        LoomButton(
                          palette: p,
                          label: 'New Game',
                          onPressed: onPlay,
                        ),
                      ] else
                        LoomButton(
                          palette: p,
                          label: 'Play',
                          primary: true,
                          onPressed: onPlay,
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: LoomButton(
                              palette: p,
                              label: 'How to play',
                              onPressed: onHowToPlay,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            // "Shop & Set · 5 / 22 blocks · 5 in play" was a
                            // sentence on a button: it made the two cards
                            // different heights, and "5 in play" means nothing
                            // before you have seen the set picker (UX review
                            // §2.3).
                            child: LoomButton(
                              palette: p,
                              label: 'Shop',
                              subtitle:
                                  '${account.ownedShapeIds.length}/${allShapes.length}',
                              onPressed: onShop,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Audio settings were reachable only from inside a run, which
                      // meant starting one to turn the sound off.
                      LoomButton(
                        palette: p,
                        label: 'Sound & Vibration',
                        icon: Icons.tune,
                        onPressed: onSettings,
                      ),
                      // The "working title, pending a store and trademark
                      // search" note was a line from the team to the team,
                      // printed under the player's Play button, where it reads
                      // as "this game is not finished" (UX review §2.2).
                      const SizedBox(height: Space.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
