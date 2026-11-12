/// The play screen: HUD on top, board above the tray, overlays over both.
library;

import 'package:flutter/material.dart';

import '../game/run_controller.dart';
import '../platform/music.dart';
import '../render/theme.dart';
import 'audio_settings.dart';
import 'board_widget.dart';
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

class _GameScreenState extends State<GameScreen> {
  RunController get c => widget.controller;
  LoomPalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    c.addListener(_rebuild);
  }

  @override
  void dispose() {
    c.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

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
                label: 'Quit this run',
                subtitle: 'The coins earned so far are kept',
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
          'Level ${c.ladder.stage} ends here. The coins you have '
          'earned are kept.',
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
              if (c.aiming != ToolAim.none)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: p.accent,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.lg,
                        Space.sm,
                        Space.sm,
                        Space.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _aimHint(c.aiming),
                              style: TextStyle(
                                color: p.onAccent,
                                fontWeight: FontWeight.w600,
                                fontSize: FontSize.bodySm,
                              ),
                            ),
                          ),
                          // An armed tool must always have a way out — the
                          // `escape-routes` rule, and the difference between a
                          // mis-tap and a wasted charge.
                          TextButton(
                            onPressed: c.cancelAim,
                            style: TextButton.styleFrom(
                              foregroundColor: p.onAccent,
                              minimumSize: const Size(
                                minTapTarget,
                                minTapTarget,
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
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
              if (c.phase == GamePhase.lost || c.phase == GamePhase.won)
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
