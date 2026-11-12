/// The pattern book: spend spools on motifs and upgrades.
///
/// **Both tracks open from run 1.** Unlike the original, upgrades are not
/// gated behind unlocking every shape (`economy.json.upgrades`), so a player
/// who wants the opening rhythm can buy it before owning a single tier-3
/// motif.
///
/// Prices come from `data/economy.json`; nothing here knows a number.
library;

import 'package:flutter/material.dart';

import '../core/shapes.dart';
import '../core/types.dart';
import '../data/tuning.dart';
import '../game/account.dart';
import '../render/theme.dart';
import 'loadout_screen.dart';
import 'widgets.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    required this.account,
    required this.economy,
    required this.palette,
    required this.onChanged,
  });

  final Account account;
  final Economy economy;
  final LoomPalette palette;
  final VoidCallback onChanged;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  LoomPalette get p => widget.palette;
  Account get a => widget.account;

  /// Cost of the next motif in a tier. Prices are per-tier and ascending, so
  /// *which* motif you buy in a tier does not change what it costs — only how
  /// many of that tier you already own does.
  int _costOf(Shape s) =>
      widget.economy.costOfNthShapeInTier(s.tier, a.ownedInTier(s.tier));

  void _buyShape(Shape s) {
    final cost = _costOf(s);
    if (a.spools < cost || a.owns(s.id)) return;
    setState(() {
      a.spools -= cost;
      a.ownedShapeIds.add(s.id);
      if (a.loadout.length < a.loadoutSlots) a.loadout.add(s.id);
      a.refreshOwnershipMilestones();
    });
    widget.onChanged();
  }

  void _buyUpgrade(UpgradeDef u) {
    if (a.hasUpgrade(u.id) || a.spools < u.cost) return;
    setState(() {
      a.spools -= u.cost;
      a.upgrades.add(u.id);
      a.refreshOwnershipMilestones();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SkyBackground(
      palette: p,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Shop'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: SpoolTag(palette: p, spools: a.spools),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Buying more never makes your set worse — you choose what goes '
              'in it, right here.',
              style: TextStyle(
                color: p.inkMuted,
                fontSize: FontSize.label,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            // The set picker lives here rather than behind its own menu entry:
            // buying a block and deciding whether to play it are one decision,
            // and split across two screens a player bought something and then
            // had to go elsewhere to use it (loadout_screen.dart).
            LoadoutPicker(
              account: a,
              palette: p,
              onChanged: () {
                setState(() {});
                widget.onChanged();
              },
            ),
            const SizedBox(height: 26),
            for (final tier in [1, 2, 3, 4]) ...[
              _SectionHeader(
                palette: p,
                title: 'Tier $tier',
                trailing: tier == 1
                    ? 'free'
                    : '${a.ownedInTier(tier)} / ${shapesOfTier(tier).length}',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in shapesOfTier(tier))
                    _MotifTile(
                      palette: p,
                      shapeId: s.id,
                      owned: a.owns(s.id),
                      cost: tier == 1 ? 0 : _costOf(s),
                      affordable: a.spools >= _costOf(s),
                      onBuy: () => _buyShape(s),
                    ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            _SectionHeader(palette: p, title: 'Upgrades'),
            const SizedBox(height: 8),
            for (final u in widget.economy.upgrades.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _UpgradeRow(
                  palette: p,
                  upgrade: u,
                  owned: a.hasUpgrade(u.id),
                  affordable: a.spools >= u.cost,
                  onBuy: () => _buyUpgrade(u),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'A fourth tray slot is deliberately not for sale. It is the '
              'biggest power swing in the game and it changes the refill rule '
              'the difficulty rests on, so it lives in the upgrade picks, where '
              'it costs you a choice.',
              style: TextStyle(
                color: p.inkMuted,
                fontSize: FontSize.label,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.palette,
    required this.title,
    this.trailing,
  });

  final LoomPalette palette;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title.toUpperCase(),
        style: TextStyle(
          color: palette.ink,
          fontSize: FontSize.label,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
      const Spacer(),
      if (trailing != null)
        Text(
          trailing!,
          style: TextStyle(color: palette.inkMuted, fontSize: FontSize.label),
        ),
    ],
  );
}

class _MotifTile extends StatelessWidget {
  const _MotifTile({
    required this.palette,
    required this.shapeId,
    required this.owned,
    required this.cost,
    required this.affordable,
    required this.onBuy,
  });

  final LoomPalette palette;
  final String shapeId;
  final bool owned;
  final int cost;
  final bool affordable;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final s = shape(shapeId);
    return SizedBox(
      width: 82,
      child: Material(
        color: palette.panel,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: owned ? null : onBuy,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: owned ? palette.accent : palette.gridLine,
              ),
            ),
            child: Column(
              children: [
                MotifThumb(
                  shapeId: shapeId,
                  palette: palette,
                  size: 38,
                  dimmed: !owned,
                ),
                const SizedBox(height: 6),
                Text(
                  shapeName(shapeId),
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: FontSize.micro,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  LoomPalette.sizeName(s.cellCount),
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: FontSize.micro,
                  ),
                ),
                const SizedBox(height: 4),
                if (owned)
                  Icon(Icons.check, size: 14, color: palette.accent)
                else
                  SpoolTag(
                    palette: palette,
                    spools: cost,
                    affordable: affordable,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({
    required this.palette,
    required this.upgrade,
    required this.owned,
    required this.affordable,
    required this.onBuy,
  });

  final LoomPalette palette;
  final UpgradeDef upgrade;
  final bool owned;
  final bool affordable;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.panel,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: owned ? null : onBuy,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: owned ? palette.accent : palette.gridLine),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    upgradeNames[upgrade.id] ?? upgrade.id,
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: FontSize.body,
                    ),
                  ),
                  if (upgrade.effect.isNotEmpty)
                    Text(
                      upgrade.effect,
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: FontSize.label,
                      ),
                    ),
                ],
              ),
            ),
            if (owned)
              Icon(Icons.check, size: 18, color: palette.accent)
            else
              SpoolTag(
                palette: palette,
                spools: upgrade.cost,
                affordable: affordable,
              ),
          ],
        ),
      ),
    ),
  );
}
