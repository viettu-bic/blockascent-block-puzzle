/// Overlays: the act's fault choice, the draft, the motif choice a few cards
/// demand, and the run summary.
library;

import 'package:flutter/material.dart';

import '../core/faults.dart';
import '../core/powers.dart';
import '../core/run.dart';
import '../core/shapes.dart';
import '../game/run_controller.dart';
import '../render/theme.dart';
import 'widgets.dart';

/// The act's three faults, announced when the act **begins** — so the player
/// can draft toward the one they chose (`faults.json._placement`).
class FaultChoiceOverlay extends StatelessWidget {
  const FaultChoiceOverlay({
    super.key,
    required this.controller,
    required this.palette,
  });

  final RunController controller;
  final LoomPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final act = actOf(c.ladder.stage);
    final faultStage = act * 4;

    return LoomOverlay(
      palette: palette,
      title: 'Act $act',
      subtitle: 'Choose the challenge you will face on level $faultStage.\n'
          'You have ${faultStage - c.ladder.stage + 1} levels to prepare '
          'for it.',
      child: SingleChildScrollView(
        child: StaggeredList(
          spacing: Space.md,
          children: [
            for (final f in c.faultOptions)
              _FaultCard(
                fault: f,
                palette: palette,
                onTap: () => c.chooseFault(f.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _FaultCard extends StatelessWidget {
  const _FaultCard({
    required this.fault,
    required this.palette,
    required this.onTap,
  });

  final FaultDef fault;
  final LoomPalette palette;
  final VoidCallback onTap;

  static const Map<DraftReward, String> _rewardText = {
    DraftReward.normal: 'Reward: a normal upgrade pick',
    DraftReward.uncommonOrBetter: 'Reward: uncommon or better only',
    DraftReward.raresOnly: 'Reward: rares only',
  };

  static const List<String> _tierWords = ['', 'mild', 'hard', 'severe'];

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${fault.name}, ${_tierWords[fault.tier]}. ${fault.rule}. '
        'Hurts ${fault.attacks}. ${_rewardText[fault.reward]}',
    excludeSemantics: true,
    child: PressScale(
      child: Material(
        color: palette.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: minTapTarget),
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: palette.warn.withValues(alpha: 0.6),
                // A nastier fault gets a heavier frame, so the tier does not
                // rest on counting three small dots.
                width: 0.8 + fault.tier * 0.6,
              ),
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fault.name,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: FontSize.heading,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Row(
                  children: [
                    // The tier in words as well as pips: three dots of the
                    // same colour is a count, not a label.
                    Text(
                      _tierWords[fault.tier].toUpperCase(),
                      style: TextStyle(
                        color: palette.warnInk,
                        fontSize: FontSize.micro,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: i < fault.tier
                              ? palette.warn
                              : palette.gridLine,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              fault.rule,
              style: TextStyle(
                color: palette.ink,
                fontSize: FontSize.bodySm,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hurts: ${fault.attacks}',
              style: TextStyle(color: palette.inkMuted, fontSize: FontSize.label),
            ),
            const SizedBox(height: 4),
                Text(
                  _rewardText[fault.reward]!,
                  style: TextStyle(
                    color: palette.accentInk,
                    fontSize: FontSize.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One pick per stage cleared, three offered.
class DraftOverlay extends StatelessWidget {
  const DraftOverlay({
    super.key,
    required this.controller,
    required this.palette,
  });

  final RunController controller;
  final LoomPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return LoomOverlay(
      palette: palette,
      title: 'Level ${c.ladder.stage} complete',
      subtitle: 'Pick one upgrade.',
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: StaggeredList(
                spacing: Space.md,
                children: [
                  for (final def in c.draftOptions)
                    PowerCard(
                      def: def,
                      palette: palette,
                      stacksTaken: c.powers.stacksOf(def.id),
                      onTap: () => c.takeDraftCard(def),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: c.skipDraft,
                child: Text(
                  'Take nothing',
                  style: TextStyle(color: palette.inkMuted),
                ),
              ),
            ],
          ),
          if (c.powers.picks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Your upgrades: '
                '${c.powers.picks.map((p) => powerName(p.id)).join(' · ')}',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.inkMuted, fontSize: FontSize.label),
              ),
            ),
        ],
      ),
    );
  }
}

/// Slub Yarn, Cull and Favour each need a motif named.
class MotifChoiceOverlay extends StatelessWidget {
  const MotifChoiceOverlay({
    super.key,
    required this.controller,
    required this.palette,
  });

  final RunController controller;
  final LoomPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final def = c.pendingMotifCard;
    if (def == null) return const SizedBox.shrink();

    final options = c.bagLoadout;
    final prompt = switch (def.id) {
      'cull' => 'Remove which block from this run, for good?',
      'favour' => 'Add a second copy of which block?',
      _ => 'Which block gets the bonus points?',
    };

    return LoomOverlay(
      palette: palette,
      title: powerName(def.id),
      subtitle: prompt,
      child: GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          for (final s in options)
            Semantics(
              button: true,
              label: '${shapeName(s.id)}, ${s.cellCount} cells',
              excludeSemantics: true,
              child: PressScale(
                child: Material(
                  color: palette.panel,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => c.chooseMotifForCard(s.id),
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MotifThumb(shapeId: s.id, palette: palette, size: 40),
                        const SizedBox(height: Space.xs),
                        Text(
                          shapeName(s.id),
                          style: TextStyle(
                            color: palette.inkMuted,
                            fontSize: FontSize.micro,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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

/// The run summary: what happened, what it paid, and a button you press again
/// without being asked to (build-order step 6).
class SummaryOverlay extends StatelessWidget {
  const SummaryOverlay({
    super.key,
    required this.controller,
    required this.palette,
    required this.onAgain,
    required this.onMenu,
    required this.onShop,
  });

  final RunController controller;
  final LoomPalette palette;
  final VoidCallback onAgain;
  final VoidCallback onMenu;
  final VoidCallback onShop;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final won = c.phase == GamePhase.won;

    return LoomOverlay(
      palette: palette,
      title: won ? 'You win!' : c.lossHeadline,
      subtitle: won
          ? 'All ${c.tuning.curve.stages} levels cleared.'
          : 'Level ${c.ladder.stage} of ${c.tuning.curve.stages}',
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
          LoomPanel(
            palette: palette,
            accent: won,
            child: Column(
              children: [
                _Stat(
                  palette: palette,
                  label: 'Levels cleared',
                  value: '${c.stagesCleared}',
                ),
                _Stat(
                  palette: palette,
                  label: 'Score',
                  value: formatScore(c.ladder.score.total),
                ),
                _Stat(
                  palette: palette,
                  label: 'Best combo',
                  value: '×${c.account.milestones.bestRhythm.toStringAsFixed(2)}',
                ),
                const Divider(height: 18),
                _Stat(
                  palette: palette,
                  label: 'Coins earned',
                  value: '+${formatScore(c.spoolsEarned)}',
                  strong: true,
                ),
                if (c.firstRunOfDay)
                  _Stat(
                    palette: palette,
                    label: 'of which first run of the day',
                    value: '+${c.tuning.economy.payout.firstRunOfDayBonus}',
                    muted: true,
                  ),
                _Stat(
                  palette: palette,
                  label: 'Coins',
                  value: formatScore(c.account.spools),
                  muted: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (c.powers.picks.isNotEmpty)
            LoomPanel(
              palette: palette,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR UPGRADES',
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: FontSize.micro,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.powers.picks
                        .map(
                          (p) => powerName(p.id) +
                              (p.motifId != null
                                  ? ' (${shapeName(p.motifId!)})'
                                  : ''),
                        )
                        .join(' · '),
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: FontSize.label,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Estimated build strength '
                    '+${c.powers.estimatedGain(c.tuning.powers)}%',
                    style: TextStyle(color: palette.inkMuted, fontSize: FontSize.micro),
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: LoomButton(
                  palette: palette,
                  label: 'Play again',
                  primary: true,
                  onPressed: onAgain,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: LoomButton(
                  palette: palette,
                  label: 'Shop',
                  onPressed: onShop,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: LoomButton(
                  palette: palette,
                  label: 'Menu',
                  onPressed: onMenu,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.palette,
    required this.label,
    required this.value,
    this.strong = false,
    this.muted = false,
  });

  final LoomPalette palette;
  final String label;
  final String value;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: muted ? palette.inkMuted : palette.ink,
              fontSize: muted ? 11 : 13,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: strong ? palette.accentInk : palette.ink,
            fontSize: strong ? 18 : 13,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
