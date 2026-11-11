/// Shared widgets: panels, buttons, motif thumbnails, card frames.
///
/// Flutter widgets do the HUD, menus, shop and draft — those are lists and
/// forms, not a game (spec §8). Only the board is a `CustomPainter`.
library;

import 'package:flutter/material.dart';

import '../core/powers.dart';
import '../core/shapes.dart';
import '../core/types.dart';
import '../render/theme.dart';

class LoomPanel extends StatelessWidget {
  const LoomPanel({
    super.key,
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent = false,
  });

  final LoomPalette palette;
  final Widget child;
  final EdgeInsets padding;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: palette.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: accent ? palette.accent : palette.gridLine,
        width: accent ? 1.6 : 1,
      ),
    ),
    child: child,
  );
}

/// Scale-on-press feedback.
///
/// `Transform.scale` rather than a size change, so the press never reflows
/// anything around it — a button that nudges its neighbours when touched reads
/// as a bug, not as feedback. Skipped entirely under reduce-motion, where the
/// ink splash is still the confirmation.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || reduceMotionOf(context)) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: Motion.instant,
        curve: Motion.press,
        child: widget.child,
      ),
    );
  }
}

class LoomButton extends StatelessWidget {
  const LoomButton({
    super.key,
    required this.palette,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.subtitle,
    this.icon,
  });

  final LoomPalette palette;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// Secondary line. Part of the button's accessible name, since on its own
  /// "Your draft" does not tell a screen-reader user that it says 8 / 8.
  final String? subtitle;

  /// Decorative only — it always sits beside the visible label, so it is
  /// hidden from the accessibility tree.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = primary ? palette.onAccent : palette.ink;
    final bg = primary ? palette.accent : palette.panel;
    final subtitleColour = primary ? palette.onAccent : palette.inkMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: subtitle == null ? label : '$label. $subtitle',
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: Opacity(
          // Material's disabled range. Paired with no tap handler, so it is
          // non-interactive as well as visibly inert.
          opacity: enabled ? 1 : 0.45,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(minHeight: minTapTarget),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.md,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: primary ? palette.accent : palette.gridLine,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: fg),
                      const SizedBox(width: Space.sm),
                    ],
                    // Flexible, not a bare Column: two of these sit side by
                    // side in Expanded on the menu, and a label plus a
                    // subtitle at their natural width overflows a half-screen
                    // button. Let the text shrink rather than the layout break.
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w600,
                              fontSize: FontSize.body,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                // Full opacity: a subtitle faded to 70% of a
                                // light-on-gold foreground drops under 4.5:1.
                                // Hierarchy comes from size and weight here.
                                color: subtitleColour,
                                fontSize: FontSize.label,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A motif drawn as flat squares — the pattern-book and shop thumbnail.
class MotifThumb extends StatelessWidget {
  const MotifThumb({
    super.key,
    required this.shapeId,
    required this.palette,
    this.size = 44,
    this.rotation = 0,
    this.dimmed = false,
  });

  final String shapeId;
  final LoomPalette palette;
  final double size;
  final int rotation;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    // Decorative: every place this is used shows the motif's name next to it,
    // so announcing the thumbnail too would just read the name twice.
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _MotifPainter(
            cells: cellsOf(shapeId, rotation),
            colour: palette.yarnFor(shape(shapeId).cellCount),
            dimmed: dimmed,
            empty: palette.emptyCell,
            outline: palette.gridLine,
          ),
        ),
      ),
    );
  }
}

class _MotifPainter extends CustomPainter {
  _MotifPainter({
    required this.cells,
    required this.colour,
    required this.dimmed,
    required this.empty,
    required this.outline,
  });

  final ShapeCells cells;
  final Color colour;
  final bool dimmed;
  final Color empty;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final e = extent(cells);
    final unit = (size.width / e.w) < (size.height / e.h)
        ? size.width / e.w
        : size.height / e.h;
    final ox = (size.width - unit * e.w) / 2;
    final oy = (size.height - unit * e.h) / 2;
    final paint = Paint()..color = dimmed ? empty : colour;
    // A dimmed thumbnail is drawn in the empty-cell colour, which by design
    // barely differs from the surface behind it — so the silhouette gets an
    // outline. Without it a locked motif in the shop is an invisible blob
    // rather than a shape you can recognise and want.
    final stroke = dimmed
        ? (Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1)
        : null;
    for (final (cx, cy) in cells) {
      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(ox + cx * unit, oy + cy * unit, unit, unit)
            .deflate(unit * 0.08),
        Radius.circular(unit * 0.2),
      );
      canvas.drawRRect(rr, paint);
      if (stroke != null) canvas.drawRRect(rr, stroke);
    }
  }

  @override
  bool shouldRepaint(_MotifPainter old) =>
      old.cells != cells ||
      old.colour != colour ||
      old.dimmed != dimmed ||
      old.outline != outline;
}

/// A draft card. The frame, the rarity colour and the charge pips are
/// parametric and never baked into an image (docs/03 §4b); only the glyph
/// would ever be an asset, and these are the placeholder geometric glyphs the
/// doc calls for during F1–F2.
class PowerCard extends StatelessWidget {
  const PowerCard({
    super.key,
    required this.def,
    required this.palette,
    required this.stacksTaken,
    this.onTap,
    this.compact = false,
  });

  final PowerDef def;
  final LoomPalette palette;
  final int stacksTaken;
  final VoidCallback? onTap;
  final bool compact;

  static const Map<String, IconData> _familyGlyphs = {
    'yarn': Icons.auto_awesome_mosaic,
    'rhythm': Icons.graphic_eq,
    'selvage': Icons.shield_outlined,
    'tools': Icons.construction,
    'draft': Icons.grid_view,
    'commission': Icons.receipt_long,
  };

  @override
  Widget build(BuildContext context) {
    final rarity = rarityColour(palette, def.rarity.name);
    // Border weight rises with rarity, so the tier is legible from the frame
    // without reading the colour. The rarity word below is the third cue.
    final borderWidth = switch (def.rarity) {
      Rarity.common => 1.0,
      Rarity.uncommon => 1.8,
      Rarity.rare => 2.8,
    };
    return Semantics(
      button: onTap != null,
      label: '${powerName(def.id)}. ${def.rarity.name} '
          '${powerFamilyName(def.family)}. '
          '${def.effect}.'
          '${def.stacks > 1 ? ' Taken $stacksTaken of ${def.stacks}.' : ''}',
      excludeSemantics: true,
      child: PressScale(
        enabled: onTap != null,
        child: Material(
          color: palette.panel,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: minTapTarget),
              padding: EdgeInsets.all(compact ? Space.sm : Space.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: rarity, width: borderWidth),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rarity.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: rarity.withValues(alpha: 0.5)),
                    ),
                    child: Icon(
                      _familyGlyphs[def.family] ?? Icons.circle_outlined,
                      size: 20,
                      color: rarity,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                powerName(def.id),
                                style: TextStyle(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: FontSize.body,
                                ),
                              ),
                            ),
                            if (def.stacks > 1)
                              _StackPips(
                                total: def.stacks,
                                filled: stacksTaken,
                                colour: rarity,
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          def.effect,
                          style: TextStyle(
                            color: palette.inkMuted,
                            fontSize: FontSize.label,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          '${def.rarity.name} · '
                          '${powerFamilyName(def.family)}',
                          style: TextStyle(
                            // inkMuted, not the rarity colour: a rarity colour
                            // is tuned to 3:1 as a frame, and "common" grey at
                            // 3.3:1 is under the 4.5:1 that text needs. The
                            // colour stays on the frame and the glyph, where
                            // the 3:1 bar is the right one.
                            color: palette.inkMuted,
                            fontSize: FontSize.micro,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
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
}

class _StackPips extends StatelessWidget {
  const _StackPips({
    required this.total,
    required this.filled,
    required this.colour,
  });

  final int total;
  final int filled;
  final Color colour;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < total; i++)
        Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? colour : colour.withValues(alpha: 0.25),
            ),
          ),
        ),
    ],
  );
}

/// A row of charge pips for an in-run tool button.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.palette,
    required this.label,
    required this.charges,
    required this.icon,
    this.active = false,
    this.onPressed,
  });

  final LoomPalette palette;
  final String label;
  final int charges;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = charges > 0 && onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: active,
      // "Unpick, 2 charges" rather than "Unpick 2" — the number alone does not
      // say what it counts.
      label: '$label, $charges ${charges == 1 ? 'charge' : 'charges'}',
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Material(
            color: active ? palette.accent : palette.panel,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                // The visual chip is shorter than this; the hit area is not.
                constraints: const BoxConstraints(minHeight: minTapTarget),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active ? palette.accent : palette.gridLine,
                    // An active tool is also thicker-bordered, so "armed" is
                    // not carried by colour alone.
                    width: active ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: active ? palette.onAccent : palette.ink,
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: FontSize.label,
                        color: active ? palette.onAccent : palette.ink,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      '$charges',
                      style: TextStyle(
                        fontSize: FontSize.label,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: active ? palette.onAccent : palette.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spool count, shown wherever currency matters.
class SpoolTag extends StatelessWidget {
  const SpoolTag({
    super.key,
    required this.palette,
    required this.spools,
    this.affordable = true,
  });

  final LoomPalette palette;
  final int spools;
  final bool affordable;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${formatScore(spools)} spools'
        '${affordable ? '' : ' — not enough'}',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 10,
          color: affordable ? palette.accentInk : palette.inkMuted,
        ),
        const SizedBox(width: Space.xs),
        Text(
          formatScore(spools),
          style: TextStyle(
            color: affordable ? palette.ink : palette.inkMuted,
            fontWeight: FontWeight.w600,
            fontSize: FontSize.bodySm,
            // A price that changes width as it counts makes a shop list jitter.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// A full-screen overlay with a weave-textured scrim — the draft, the fault
/// choice and the run summary all sit on one.
class LoomOverlay extends StatelessWidget {
  const LoomOverlay({
    super.key,
    required this.palette,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final LoomPalette palette;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionOf(context);
    final content = Container(
      // Fully opaque, not 96%. At 96% the board's grid showed faintly through
      // the card text behind it; a scrim exists to isolate the foreground, and
      // "almost isolated" is the one thing it must not be.
      color: palette.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Space.sm),
              // The overlay's heading is the first thing a screen reader
              // should land on when it opens.
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: FontSize.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Space.sm),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: FontSize.bodySm,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: Space.lg),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );

    if (reduce) return content;
    // Rises slightly as it fades in — a direction that reads as "this came
    // forward", rather than a bare cut.
    return _OverlayEntrance(child: content);
  }
}

class _OverlayEntrance extends StatefulWidget {
  const _OverlayEntrance({required this.child});

  final Widget child;

  @override
  State<_OverlayEntrance> createState() => _OverlayEntranceState();
}

class _OverlayEntranceState extends State<_OverlayEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.overlay,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Motion.enter);
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Reveals its children one after another.
///
/// 40ms per item: enough that the eye follows the order, short enough that a
/// three-card draft is fully on screen in about a tenth of a second. A player
/// who taps during the reveal is not blocked — the cards are live from the
/// first frame, they are only still fading.
class StaggeredList extends StatelessWidget {
  const StaggeredList({super.key, required this.children, this.spacing = 0});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          _StaggerItem(index: i, child: children[i]),
        ],
      ],
    );
  }
}

class _StaggerItem extends StatefulWidget {
  const _StaggerItem({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<_StaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.quick,
  );

  @override
  void initState() {
    super.initState();
    final delay = Motion.stagger * widget.index;
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Motion.enter);
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
