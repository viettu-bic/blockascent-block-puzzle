/// The draft: choose which motifs form this run's bag.
///
/// In weaving a *draft* is the threading plan you commit to before you start,
/// which is why the loadout and the power pick share the word and both are
/// correct (docs/03 §3).
///
/// This is the fix for the original's dilution problem: you own motifs and pick
/// [Account.loadoutSlots] of them, so an unlock adds an *option* rather than
/// watering down the bag (docs/01 §5).
///
/// **It is a section of the shop, not a screen of its own** (2026-11-12).
/// Buying a block and deciding whether to play it are one decision — splitting
/// them across two menu entries meant a player bought something and then had to
/// go somewhere else to use it, and had no way to see what a purchase would do
/// to the set they already had.
library;

import 'package:flutter/material.dart';

import '../core/shapes.dart';
import '../game/account.dart';
import '../render/theme.dart';
import 'widgets.dart';

/// Pick which owned motifs go in the bag. Renders inline — no Scaffold, no
/// scroll view of its own — so it can sit inside the shop's list.
class LoadoutPicker extends StatefulWidget {
  const LoadoutPicker({
    super.key,
    required this.account,
    required this.palette,
    required this.onChanged,
  });

  final Account account;
  final LoomPalette palette;
  final VoidCallback onChanged;

  @override
  State<LoadoutPicker> createState() => _LoadoutPickerState();
}

class _LoadoutPickerState extends State<LoadoutPicker> {
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
    final full = chosen >= a.loadoutSlots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'YOUR SET',
                style: TextStyle(
                  color: p.inkMuted,
                  fontSize: FontSize.micro,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$chosen / ${a.loadoutSlots}',
              style: TextStyle(
                color: full ? p.accentInk : p.inkMuted,
                fontWeight: FontWeight.w700,
                fontSize: FontSize.label,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // What a tile does, always on screen (UX review 6.1).
        //
        // The old copy claimed "all of them are in play", which stops being
        // true the moment the player removes one — and they can, from the
        // first run, with five blocks and eight slots. Nothing anywhere said
        // a tile could be tapped at all.
        Text(
          'The blocks that can show up in your tray. Tap one to add or '
          'remove it.'
          '${owned.length > a.loadoutSlots ? ' ${owned.length} blocks, '
              '${a.loadoutSlots} slots. Pick the ${a.loadoutSlots} you want '
              'to play with.' : ''}',
          style: TextStyle(
            color: p.inkMuted,
            fontSize: FontSize.label,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        // Inside the shop's ListView, so it must not scroll on its own.
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          // Grows taller as text grows. A fixed ratio overflowed the tile by
          // 43px at a 1.4x scale, because the thumbnail is a fixed size but
          // the two labels under it are not.
          childAspectRatio: 0.82 / MediaQuery.textScalerOf(context).scale(1.0),
          children: [
            for (final s in owned)
              _LoadoutTile(
                palette: p,
                shapeId: s.id,
                selected: a.loadout.contains(s.id),
                onTap: () => _toggle(s.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _LoadoutTile extends StatelessWidget {
  const _LoadoutTile({
    required this.palette,
    required this.shapeId,
    required this.selected,
    required this.onTap,
  });

  final LoomPalette palette;
  final String shapeId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = shape(shapeId);
    return Semantics(
      button: true,
      selected: selected,
      label: '${shapeName(shapeId)}, ${s.cellCount} cells'
          '${selected ? ', in your set' : ''}',
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
            // Name only, and the accent frame for "in your set" (UX review
            // 6.2). The second line read "3 blocks" for a three-CELL block,
            // and the corner badge numbered the order the blocks were added to
            // the set — which changes nothing about a run.
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MotifThumb(
                  shapeId: shapeId,
                  palette: palette,
                  // Gives way to the label rather than competing with it: the
                  // thumbnail is the one part of this tile that can afford to
                  // lose a few pixels.
                  size: 38 /
                      MediaQuery.textScalerOf(context)
                          .scale(1.0)
                          .clamp(1, 2),
                  dimmed: !selected,
                ),
                const SizedBox(height: 4),
                Text(
                  shapeName(shapeId),
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: FontSize.micro,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
