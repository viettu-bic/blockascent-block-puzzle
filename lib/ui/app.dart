/// App root: boot, theme, and the handful of screens.
///
/// Portrait-locked (spec §8). The board is above the tray because the thumb
/// drags upward out of the tray, and that whole geometry assumes one
/// orientation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tuning.dart';
import '../game/account.dart';
import '../game/run_controller.dart';
import '../platform/haptics.dart';
import '../platform/storage.dart';
import '../render/board_painter.dart';
import '../render/theme.dart';
import 'game_screen.dart';
import '../platform/music.dart';
import '../platform/sfx.dart';
import 'audio_settings.dart';
import 'how_to_play_screen.dart';
import 'menu_screen.dart';
import 'shop_screen.dart';

class LoomcraftApp extends StatefulWidget {
  const LoomcraftApp({
    super.key,
    this.storageOverride,
    this.tuningOverride,
    this.sfxOverride,
    this.musicOverride,
  });

  /// Injected by tests; production opens shared preferences.
  final Storage? storageOverride;

  /// Injected by widget tests, which cannot await `rootBundle`: a widget test
  /// runs in a fake-async zone and a real platform-channel future never
  /// completes there. `test/data/tuning_test.dart` covers the asset path
  /// itself, outside that zone.
  final Tuning? tuningOverride;

  /// Injected silent in tests. Constructing a real [Sfx] reaches the
  /// `audioplayers` platform channel, which a widget test does not have, and a
  /// sound effect is never worth failing a test over.
  final Sfx? sfxOverride;

  /// Injected silent in tests, for the same reason as [sfxOverride].
  final Music? musicOverride;

  @override
  State<LoomcraftApp> createState() => _LoomcraftAppState();
}

class _LoomcraftAppState extends State<LoomcraftApp> {
  Tuning? _tuning;
  Account? _account;
  Storage? _storage;
  Haptics? _haptics;
  Sfx? _sfx;
  Music? _music;
  RunController? _run;
  bool _inGame = false;
  bool _savedRunExists = false;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final storage = widget.storageOverride ?? await PrefsStorage.open();
      final tuning = widget.tuningOverride ?? await Tuning.load();
      final accountJson = await storage.read(accountKey);
      final account = accountJson == null
          ? Account()
          : Account.fromJson(accountJson);
      final haptics = Haptics(enabled: account.hapticsEnabled);
      final sfx = widget.sfxOverride ?? Sfx(enabled: account.sfxEnabled);
      final music =
          widget.musicOverride ?? Music(enabled: account.musicEnabled);
      final savedRun = await storage.read(runKey);

      if (!mounted) return;
      setState(() {
        _storage = storage;
        _tuning = tuning;
        _account = account;
        _haptics = haptics;
        _sfx = sfx;
        _music = music;
        _savedRunExists = savedRun != null;
      });
      // The app opens on the menu, so that is the track it opens on.
      music.play(MusicTrack.menu);
    } on Object catch (e) {
      if (!mounted) return;
      // A boot failure is almost always a malformed data/*.json. Say so rather
      // than showing a blank screen: the tuning files are the one thing a
      // designer edits without a compiler to catch them.
      setState(() => _bootError = '$e');
    }
  }

  /// The game has one palette and does not follow the system setting.
  ///
  /// See `docs/07` §4i: the night sky is the product, and a light mode of it
  /// was a parchment star atlas — a second art direction to keep working,
  /// measure and look at, for a theme that is about darkness.

  RunController _controller() {
    return _run ??= RunController(
      tuning: _tuning!,
      account: _account!,
      storage: _storage!,
      haptics: _haptics!,
      sfx: _sfx!,
    );
  }

  /// Screen transitions own the track. `Music.play` is a no-op when the
  /// track is already the current one, so opening the shop does not restart
  /// the menu loop.
  void _musicFor(MusicTrack track) => _music?.play(track);

  void _newRun() {
    final c = _controller();
    c.begin();
    _musicFor(MusicTrack.gameplay);
    setState(() {
      _inGame = true;
      _savedRunExists = false;
    });
  }

  Future<void> _resume() async {
    final c = _controller();
    final ok = await c.restore();
    if (!mounted) return;
    if (ok) {
      _musicFor(MusicTrack.gameplay);
      setState(() => _inGame = true);
    } else {
      setState(() => _savedRunExists = false);
      _newRun();
    }
  }

  void _toMenu() {
    _musicFor(MusicTrack.menu);
    setState(() {
      _inGame = false;
      _run = null;
    });
    _saveAccount();
  }

  void _saveAccount() => _storage?.write(accountKey, _account!.toJson());

  @override
  Widget build(BuildContext context) {
    const palette = LoomPalette.dark;

    // Paint the status and navigation bars to match the app.
    //
    // Without this they stay the platform's grey and black, so the game sits
    // in a frame that belongs to a different product — the first thing you
    // notice on a device and the last thing a widget test can show you.
    // Light icons on both bars, unconditionally: the app is dark whatever
    // the system setting says, so following that setting here would put dark
    // icons on a dark bar for every player who runs their phone in light mode.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: palette.background,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: palette.background,
      ),
    );

    return MaterialApp(
      title: gameFullTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(palette),
      // Honour the system text size, but only so far.
      //
      // The board is a square grid of fixed cells with the HUD above it and
      // the tray below, so text cannot reflow indefinitely the way a document
      // can — at 200% the HUD would push the tray off the bottom of the
      // screen. Ignoring the setting entirely is the easy and wrong answer;
      // clamping honours it up to a size the layout survives and no further.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(
        builder: (context) {
          if (_bootError != null) return _BootError(message: _bootError!);
          if (_tuning == null || _account == null) {
            // A static splash, not a spinner. Boot reads four local JSON
            // files, so a spinner would only ever flash for a frame or two —
            // and an indeterminate animation on screen means nothing in a
            // widget test can ever settle.
            return Scaffold(
              backgroundColor: palette.background,
              body: Center(
                child: Text(
                  gameTitle.toUpperCase(),
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: FontSize.title,
                    letterSpacing: 5,
                  ),
                ),
              ),
            );
          }
          if (_inGame) {
            return GameScreen(
              controller: _controller(),
              music: _music,
              palette: palette,
              onAgain: _newRun,
              onMenu: _toMenu,
              onShop: () {
                _toMenu();
                _openShop(context, palette);
              },
            );
          }
          // The rules open themselves on the very first launch. A help page
          // behind a menu button is read by nobody; an FTUE is the thing that
          // appears. docs/08 E2, and it matters more now that 43% of early
          // deaths are jams nobody explained (docs/04 §9).
          if (!_account!.seenHowToPlay && !_howToPlayOpened) {
            _howToPlayOpened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _openHowToPlay(context, palette, firstLaunch: true);
              }
            });
          }
          return MenuScreen(
            account: _account!,
            palette: palette,
            canResume: _savedRunExists,
            onPlay: _newRun,
            onResume: _resume,
            onShop: () => _openShop(context, palette),
            onHowToPlay: () => _openHowToPlay(context, palette),
            onSettings: () => showAudioSettings(
              context,
              account: _account!,
              palette: palette,
              haptics: _haptics,
              sfx: _sfx,
              music: _music,
              onChanged: _saveAccount,
            ),
          );
        },
      ),
    );
  }

  /// Open the rules screen. [firstLaunch] turns the footer into "Got it" and
  /// marks the account, so it opens itself exactly once.
  /// Guards the one-shot: a rebuild must not queue a second push.
  bool _howToPlayOpened = false;

  void _openHowToPlay(
    BuildContext context,
    LoomPalette palette, {
    bool firstLaunch = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HowToPlayScreen(
          palette: palette,
          onDone: firstLaunch
              ? () {
                  _account!.seenHowToPlay = true;
                  _saveAccount();
                }
              : null,
        ),
      ),
    );
  }

  void _openShop(BuildContext context, LoomPalette palette) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopScreen(
          account: _account!,
          economy: _tuning!.economy,
          palette: palette,
          onChanged: () {
            _saveAccount();
            setState(() {});
          },
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The recorded loom frame is palette-dependent, so a theme switch has to
    // drop it or the board keeps the old background.
    BoardPainter.invalidateChrome();
  }
}

class _BootError extends StatelessWidget {
  const _BootError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LoomPalette.dark.background,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: LoomPalette.dark.warn, size: 40),
            const SizedBox(height: 12),
            Text(
              'Could not read the tuning in data/',
              style: TextStyle(
                color: LoomPalette.dark.ink,
                fontSize: FontSize.heading,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: LoomPalette.dark.inkMuted, fontSize: FontSize.label),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lock the app to portrait. The entire layout — board above tray, thumb
/// dragging upward — assumes it.
Future<void> lockPortrait() => SystemChrome.setPreferredOrientations([
  DeviceOrientation.portraitUp,
]);

/// Draw the app behind the status and navigation bars.
///
/// Without this the bars keep the platform's own grey, and the game sits in a
/// frame that belongs to a different product. Every screen already wraps its
/// content in a `SafeArea`, so nothing moves under them — only the background
/// extends.
Future<void> drawEdgeToEdge() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
