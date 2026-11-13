/// The play screen: HUD on top, board above the tray, overlays over both.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../game/run_controller.dart';
import '../platform/music.dart';
import '../render/theme.dart';
import 'audio_settings.dart';
import 'board_widget.dart';
import 'how_to_play_screen.dart';
import 'hud.dart';
import 'overlays.dart';
import 'widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    this.music,
    required this.palette,
    required this.onAgain,
    required this.onMenu,
    required this.onShop,
  });

  final RunController controller;

  /// Owned by the app, not the controller — the music outlives a run.
  final Music? music;
  final LoomPalette palette;
  final VoidCallback onAgain;
  final VoidCallback onMenu;
  final VoidCallback onShop;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// How long the jammed cells stay on screen before the summary covers them.
///
/// Long enough to look at a board and see that nothing fits, short enough that
/// it is not a wait. Designed, not measured — what would settle it is watching
/// someone jam twice.
const Duration jamRevealHold = Duration(seconds: 2);

/// How long the board has to sit untouched-and-unfitting before the game says
/// out loud that blocks turn.
///
/// Not instant: a player who is about to find rotation themselves should be
/// allowed to, and a tip that arrives before you have had a chance to think is
/// read as noise.
const Duration rotateHintDelay = Duration(seconds: 5);

class _GameScreenState extends State<GameScreen> {
  RunController get c => widget.controller;
  LoomPalette get p => widget.palette;

  /// Holds the summary back while the jammed cells are shown.
  Timer? _jamTimer;
  bool _holdJamReveal = false;
  bool _jamRevealed = false;

  /// Delays the rotation hint bar.
  Timer? _rotateTimer;
  bool _showRotateHint = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_rebuild);
    _syncJamReveal();
    _syncRotateHint();
  }

  @override
  void dispose() {
    c.removeListener(_rebuild);
    _jamTimer?.cancel();
    _rotateTimer?.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    _syncJamReveal();
    _syncRotateHint();
    setState(() {});
  }

  /// Show the gaps, then the summary (UX review 5).
  ///
  /// A jam used to go straight to a panel reading "No moves left" over a board
  /// the player could no longer see — 43% of early deaths, explained by
  /// nothing, at the exact moment the player wants to know why. Only a jam
  /// does this: running out of moves needs no board.
  void _syncJamReveal() {
    final jammed = c.phase == GamePhase.lost && c.jamCells.isNotEmpty;
    if (!jammed) {
      _jamTimer?.cancel();
      _jamTimer = null;
      _holdJamReveal = false;
      _jamRevealed = false;
      return;
    }
    if (_jamRevealed || _holdJamReveal) return;
    _holdJamReveal = true;
    _jamTimer = Timer(jamRevealHold, () {
      if (!mounted) return;
      setState(() {
        _holdJamReveal = false;
        _jamRevealed = true;
      });
    });
  }

  void _syncRotateHint() {
    final wanted = c.phase == GamePhase.placing &&
        c.needsRotation &&
        !c.account.seenRotateHint;
    if (!wanted) {
      _rotateTimer?.cancel();
      _rotateTimer = null;
      _showRotateHint = false;
      return;
    }
    if (_showRotateHint || _rotateTimer != null) return;
    _rotateTimer = Timer(rotateHintDelay, () {
      if (!mounted) return;
      setState(() => _showRotateHint = true);
    });
  }

  void _openHelp() => showHowToPlaySheet(context, palette: p);

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.panel,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The same three switches the menu shows, from one place: the
              // in-run sheet used to be the *only* way to reach them, so
              // turning the sound off meant starting a run first.
              ...audioToggles(
                account: c.account,
                palette: p,
                haptics: c.haptics,
                sfx: c.sfx,
                music: widget.music,
                onChanged: () => setState(() {}),
              ),
              const Divider(height: Space.xl),
              // Separated from the toggle above by a divider and sitting in
              // warning colour: leaving mid-run is the one irreversible thing
              // on this sheet, and it should not look like another setting.
              LoomButton(
                palette: p,
                // Was "Quit this run" / "The coins earned so far are kept".
                // Shorter, and it answers the thing a player actually worries
                // about when they reach for this button (UX review 9.2).
                label: 'Quit run',
                subtitle: 'You keep your coins',
                icon: Icons.logout,
                onPressed: () {
                  Navigator.of(context).pop();
                  _confirmAbandon();
                },
              ),
              const SizedBox(height: Space.sm),
              LoomButton(
                palette: p,
                label: 'Back to game',
                primary: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What the system back gesture does, by phase.
  ///
  /// Back was previously unhandled, so on Android it popped straight out of
  /// the game and abandoned the run with no warning. Now it does the
  /// least-destructive sensible thing for wherever the player is: disarm an
  /// aimed tool, open the menu from the summary, and during a forced choice
  /// (the act's fault, the draft) do nothing — because there is no "back" from
  /// a decision the run cannot continue without.
  void _onBack() {
    if (c.aiming != ToolAim.none) {
      c.cancelAim();
      return;
    }
    switch (c.phase) {
      case GamePhase.lost:
      case GamePhase.won:
        widget.onMenu();
      case GamePhase.placing:
        _openSettings();
      case GamePhase.faultChoice:
      case GamePhase.draft:
      case GamePhase.motifChoice:
        break;
    }
  }

  /// Confirm before discarding a run in progress.
  ///
  /// The run is autosaved, so leaving does not lose the spools — but it does
  /// end the ladder, and an accidental tap should not be able to do that.
  Future<void> _confirmAbandon() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.panel,
        title: Text(
          'Quit this run?',
          style: TextStyle(color: p.ink, fontSize: FontSize.heading),
        ),
        content: Text(
          'Level ${c.ladder.stage} ends here. You keep your coins.',
          style: TextStyle(color: p.inkMuted, fontSize: FontSize.bodySm),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep playing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: p.warnInk),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    if (ok ?? false) widget.onMenu();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never let the framework pop this route: a run is autosaved but
      // abandoning it should be a choice made in the sheet, not a side effect
      // of a swipe.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // `bottom: true`, deliberately. The tray is the primary touch region of
      // the whole game and it lives at the bottom of the screen, so leaving
      // the bottom inset unpadded put it directly under the home indicator
      // and the Android gesture strip — every drag that started low would
      // race the system's back/home swipe. The board shrinks by the inset
      // instead, which costs a few pixels of cell size and nothing else.
      body: SkyBackground(
        // No graticule here: the board paints the grid on its own cell pitch
        // a layer up, and two grids at two pitches read as a mistake.
        palette: p,
        grid: null,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // The HUD is given at most half the screen and scrolls inside
                  // it. At a 1.4x text scale on a short phone the strip grew
                  // taller than the column and overflowed; capping it keeps the
                  // board playable and lets the readouts scroll rather than
                  // clip.
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Hud(
                            controller: c,
                            palette: p,
                            onSettings: _openSettings,
                            onHelp: _openHelp,
                          ),
                          NextRefillStrip(controller: c, palette: p),
                          HoldIndicator(controller: c, palette: p),
                        ],
                      ),
                    ),
                  ),
                  // Pinned, deliberately outside the scrollable above. The
                  // tools are the only interactive thing in the top half, and
                  // inside the capped scroll view they slid out of sight between
                  // the header and the board as soon as the readouts grew. It
                  // takes no space until a tool is drafted.
                  ToolRow(controller: c, palette: p),
                  // The board must never be squeezed to nothing: below this it
                  // stops being a game.
                  Expanded(
                    flex: 3,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 240),
                      child: BoardWidget(controller: c, palette: p),
                    ),
                  ),
                ],
              ),
              if (_holdJamReveal && c.account.jamsSeen <= 2)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BottomBanner(
                    palette: p,
                    background: p.warn,
                    foreground: p.ink,
                    icon: Icons.block,
                    // Named twice and then never again: by the third jam the
                    // red cells say it on their own, and a game that keeps
                    // explaining a rule you have learned is nagging.
                    label: 'No block fits these gaps',
                  ),
                ),
              if (_showRotateHint && c.aiming == ToolAim.none)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BottomBanner(
                    palette: p,
                    background: p.accent,
                    foreground: p.onAccent,
                    icon: Icons.rotate_right,
                    label: 'Tap a block to rotate it',
                    actionLabel: 'Got it',
                    onAction: () {
                      c.markRotateHintSeen();
                      setState(() => _showRotateHint = false);
                    },
                  ),
                ),
              if (c.aiming != ToolAim.none)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BottomBanner(
                    palette: p,
                    background: p.accent,
                    foreground: p.onAccent,
                    icon: Icons.ads_click,
                    label: _aimHint(c.aiming),
                    // An armed tool must always have a way out — the
                    // `escape-routes` rule, and the difference between a
                    // mis-tap and a wasted charge.
                    actionLabel: 'Cancel',
                    onAction: c.cancelAim,
                  ),
                ),
              if (c.phase == GamePhase.faultChoice)
                Positioned.fill(
                  child: FaultChoiceOverlay(controller: c, palette: p),
                ),
              if (c.phase == GamePhase.draft)
                Positioned.fill(
                  child: DraftOverlay(controller: c, palette: p),
                ),
              if (c.phase == GamePhase.motifChoice)
                Positioned.fill(
                  child: MotifChoiceOverlay(controller: c, palette: p),
                ),
              if ((c.phase == GamePhase.lost || c.phase == GamePhase.won) &&
                  !_holdJamReveal)
                Positioned.fill(
                  child: SummaryOverlay(
                    controller: c,
                    palette: p,
                    onAgain: widget.onAgain,
                    onMenu: widget.onMenu,
                    onShop: widget.onShop,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _aimHint(ToolAim aim) => switch (aim) {
    ToolAim.unpick => 'Tap a block to erase it',
    ToolAim.shears => 'Tap the top-left of a 2×2 to blow up',
    ToolAim.battenRow => 'Tap a row to clear it',
    ToolAim.battenCol => 'Tap a column to clear it',
    ToolAim.none => '',
  };
}

/// The strip along the bottom of the play screen: one line and at most one
/// button.
///
/// Three things use it -- an armed tool, the rotation hint and the jam
/// explanation -- and they were three different hand-rolled rows before, which
/// is three chances for one of them to be the wrong height or to lose its
/// escape route.
class _BottomBanner extends StatelessWidget {
  const _BottomBanner({
    required this.palette,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final LoomPalette palette;
  final Color background;
  final Color foreground;
  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.sm,
          Space.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: FontSize.bodySm,
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  minimumSize: const Size(minTapTarget, minTapTarget),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    ),
  );
}
