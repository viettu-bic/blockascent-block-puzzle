/// The draft: choose which motifs form this run's bag.
///
/// In weaving a *draft* is the threading plan you commit to before you start,
/// which is why the loadout and the power pick share the word and both are
/// correct (docs/03 §3).
///
/// This screen is the fix for the original's dilution problem: you own motifs
/// and pick [Account.loadoutSlots] of them, so an unlock adds an *option*
/// rather than watering down the bag (docs/01 §5).
library;

import 'package:flutter/material.dart';

import '../core/shapes.dart';
import '../game/account.dart';
import '../render/theme.dart';
import 'widgets.dart';

class LoadoutScreen extends StatefulWidget {
  const LoadoutScreen({
    super.key,
    required this.account,
    required this.palette,
    required this.onChanged,
  });

  final Account account;
  final LoomPalette palette;
  final VoidCallback onChanged;

  @override
  State<LoadoutScreen> createState() => _LoadoutScreenState();
}

class _LoadoutScreenState extends State<LoadoutScreen> {
  LoomPalette get p => widget.palette;
  Account get a => widget.account;

  void _toggle(String id) {
    setState(() {
      if (a.loadout.contains(id)) {
        // Never let the player warp the loom with nothing on it.
        if (a.loadout.length > 1) a.loadout.remove(id);
      } else if (a.loadout.length < a.loadoutSlots) {
        a.loadout.add(id);
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final owned = allShapes.where((s) => a.owns(s.id)).toList();
    final chosen = a.loadout.length;

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        title: const Text('Your Blocks'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$chosen / ${a.loadoutSlots}',
                style: TextStyle(
                  color: chosen == a.loadoutSlots ? p.accentInk : p.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text(
              owned.length <= a.loadoutSlots
                  ? 'You own ${owned.length} blocks and have '
                      '${a.loadoutSlots} slots, so all of them are in play. '
                      'Buying more blocks is what makes this a choice.'
                  : 'Pick ${a.loadoutSlots}. A smaller set means you see each '
                      'block more often — which is the point.',
              style: TextStyle(color: p.inkMuted, fontSize: FontSize.label, height: 1.4),
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // Grows taller as text grows. A fixed ratio overflowed the
              // tile by 43px at a 1.4x scale, because the thumbnail is a
              // fixed size but the two labels under it are not.
              childAspectRatio:
                  0.82 / MediaQuery.textScalerOf(context).scale(1.0),
              children: [
                for (final s in owned)
                  _LoadoutTile(
                    palette: p,
                    shapeId: s.id,
                    selected: a.loadout.contains(s.id),
                    order: a.loadout.indexOf(s.id),
                    onTap: () => _toggle(s.id),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: LoomButton(
                      palette: p,
                      label: 'Done',
                      primary: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadoutTile extends StatelessWidget {
  const _LoadoutTile({
    required this.palette,
    required this.shapeId,
    required this.selected,
    required this.order,
    required this.onTap,
  });

  final LoomPalette palette;
  final String shapeId;
  final bool selected;
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = shape(shapeId);
    return Semantics(
      button: true,
      selected: selected,
      label: '${shapeName(shapeId)}, ${s.cellCount} cells'
          '${selected ? ', slot ${order + 1}' : ''}',
      excludeSemantics: true,
      child: Material(
      color: palette.panel,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accent : palette.gridLine,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MotifThumb(
                    shapeId: shapeId,
                    palette: palette,
                    // Gives way to the labels rather than competing with
                    // them: the thumbnail is the one part of this tile that
                    // can afford to lose a few pixels.
                    size: 38 /
                        MediaQuery.textScalerOf(context).scale(1.0).clamp(1, 2),
                    dimmed: !selected,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shapeName(shapeId),
                    style: TextStyle(color: palette.ink, fontSize: FontSize.micro),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${s.cellCount} blocks',
                    style: TextStyle(color: palette.inkMuted, fontSize: FontSize.micro),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${order + 1}',
                      style: TextStyle(
                        color: palette.onAccent,
                        fontSize: FontSize.micro,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
