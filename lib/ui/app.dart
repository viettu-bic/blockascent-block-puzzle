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
import 'loadout_screen.dart';
import 'menu_screen.dart';
import 'shop_screen.dart';

class LoomcraftApp extends StatefulWidget {
  const LoomcraftApp({
    super.key,
    this.storageOverride,
    this.tuningOverride,
  });

  /// Injected by tests; production opens shared preferences.
  final Storage? storageOverride;

  /// Injected by widget tests, which cannot await `rootBundle`: a widget test
  /// runs in a fake-async zone and a real platform-channel future never
  /// completes there. `test/data/tuning_test.dart` covers the asset path
  /// itself, outside that zone.
  final Tuning? tuningOverride;

  @override
  State<LoomcraftApp> createState() => _LoomcraftAppState();
}

class _LoomcraftAppState extends State<LoomcraftApp> {
  Tuning? _tuning;
  Account? _account;
  Storage? _storage;
  Haptics? _haptics;
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
      final savedRun = await storage.read(runKey);

      if (!mounted) return;
      setState(() {
        _storage = storage;
        _tuning = tuning;
        _account = account;
        _haptics = haptics;
        _savedRunExists = savedRun != null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      // A boot failure is almost always a malformed data/*.json. Say so rather
      // than showing a blank screen: the tuning files are the one thing a
      // designer edits without a compiler to catch them.
      setState(() => _bootError = '$e');
    }
  }

  LoomPalette _paletteFor(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.light
          ? LoomPalette.light
          : LoomPalette.dark;

  RunController _controller() {
    return _run ??= RunController(
      tuning: _tuning!,
      account: _account!,
      storage: _storage!,
      haptics: _haptics!,
    );
  }

  void _newRun() {
    final c = _controller();
    c.begin();
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
      setState(() => _inGame = true);
    } else {
      setState(() => _savedRunExists = false);
      _newRun();
    }
  }

  void _toMenu() {
    setState(() {
      _inGame = false;
      _run = null;
    });
    _saveAccount();
  }

  void _saveAccount() => _storage?.write(accountKey, _account!.toJson());

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(context);
    final brightness = MediaQuery.platformBrightnessOf(context);
    final dark = brightness == Brightness.dark;

    // Paint the status and navigation bars to match the app.
    //
    // Without this they stay the platform's grey and black, so the game sits
    // in a frame that belongs to a different product — the first thing you
    // notice on a device and the last thing a widget test can show you.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.background,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: palette.background,
      ),
    );

    return MaterialApp(
      title: gameFullTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(palette, brightness),
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
              palette: palette,
              onAgain: _newRun,
              onMenu: _toMenu,
              onShop: () {
                _toMenu();
                _openShop(context, palette);
              },
            );
          }
          return MenuScreen(
            account: _account!,
            palette: palette,
            canResume: _savedRunExists,
            onPlay: _newRun,
            onResume: _resume,
            onShop: () => _openShop(context, palette),
            onLoadout: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LoadoutScreen(
                  account: _account!,
                  palette: palette,
                  onChanged: _saveAccount,
                ),
              ),
            ),
          );
        },
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
