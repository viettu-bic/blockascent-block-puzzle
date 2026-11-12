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
                      const SizedBox(height: Space.md),
                      Text(
                        'Place blocks on the board. Fill a full row or column to '
                        'clear it. Keep your combo alive.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.inkMuted,
                          fontSize: FontSize.label,
                          height: 1.5,
                        ),
                      ),
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
                                Text(
                                  'BEST',
                                  style: TextStyle(
                                    color: p.inkMuted,
                                    fontSize: FontSize.micro,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  account.milestones.bestStage == 0
                                      ? '—'
                                      : 'level ${account.milestones.bestStage}'
                                            '${account.wins > 0 ? ' · ${account.wins} won' : ''}',
                                  style: TextStyle(
                                    color: p.ink,
                                    fontSize: FontSize.label,
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
                              label: 'How to Play',
                              subtitle: 'Four rules that decide every run',
                              onPressed: onHowToPlay,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LoomButton(
                              palette: p,
                              label: 'Shop & Set',
                              subtitle:
                                  '${account.ownedShapeIds.length} / ${allShapes.length} blocks · '
                                  '${account.loadout.length} in play',
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
                      const SizedBox(height: Space.xl),
                      Text(
                        'Working title, pending a store and trademark search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.inkMuted,
                          fontSize: FontSize.micro,
                        ),
                      ),
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
