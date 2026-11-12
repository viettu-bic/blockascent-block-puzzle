import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/data/tuning.dart';
import 'package:loomcraft/game/account.dart';
import 'package:loomcraft/game/run_controller.dart';
import 'package:loomcraft/platform/haptics.dart';
import 'package:loomcraft/platform/storage.dart';
import 'package:loomcraft/render/board_painter.dart';
import 'package:loomcraft/render/theme.dart';
import 'package:loomcraft/ui/game_screen.dart';
import 'package:loomcraft/ui/hud.dart';
import 'package:loomcraft/ui/how_to_play_screen.dart';
import 'package:loomcraft/ui/menu_screen.dart';
import 'package:loomcraft/ui/shop_screen.dart';
import 'package:loomcraft/ui/widgets.dart';

import '../support/load_tuning.dart';

/// UX guarantees, enforced rather than reviewed.
///
/// Flutter ships the four accessibility guidelines these screens have to meet,
/// so they are used directly instead of hand-rolled tree walks:
///
/// - [androidTapTargetGuideline] — 48×48dp
/// - [iOSTapTargetGuideline] — 44×44pt
/// - [labeledTapTargetGuideline] — every tappable has an accessible name
/// - [textContrastGuideline] — 4.5:1 for normal text
///
/// Every screen is also checked at the largest text scale the game allows and
/// on the smallest phone it targets, because an overflow only appears when
/// both are true at once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Tuning tuning;

  setUpAll(() async {
    tuning = await loadTuningForTest();
  });

  setUp(BoardPainter.invalidateChrome);

  /// Semantics are not built unless something asks for them.
  ///
  /// `meetsGuideline` creates and disposes its own handle, so only a direct
  /// `find.bySemanticsLabel` needs this — and it must be disposed inside the
  /// test body, because the framework checks for leaked handles *before*
  /// tearDowns run.
  Future<void> withSemantics(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await body();
    } finally {
      handle.dispose();
    }
  }

  Account richAccount() => Account(
    spools: 9000,
    ownedShapeIds: {for (final s in allShapes) s.id},
    upgrades: {'loadoutSlot9', 'openingRhythm'},
    loadout: ['dot', 'i2', 'i3', 'o2', 'l3', 'i4', 't4', 'l4'],
  );

  RunController controllerFor(Account a, {bool withTools = false}) {
    final c = RunController(
      tuning: tuning,
      account: a,
      storage: MemoryStorage(),
      haptics: Haptics(enabled: false),
      seedSource: () => 7,
    );
    c.begin();
    c.chooseFault('thin_place');
    if (withTools) {
      c.powers = c.powers
          .plus(const PickedPower('unpick'))
          .plus(const PickedPower('shears'))
          .plus(const PickedPower('rethread'))
          .plus(const PickedPower('hold'));
      c.toolCharges
        ..['unpick'] = 2
        ..['shears'] = 1
        ..['rethread'] = 2;
      c.battenCharges = 1;
    }
    return c;
  }

  /// Pump a screen at a given device size, text scale and theme.
  Future<void> pump(
    WidgetTester tester,
    Widget Function(LoomPalette p) build, {
    Size size = const Size(375, 667), // the smallest phone targeted
    double textScale = 1.0,
    bool reduceMotion = false,
  }) async {
    const palette = LoomPalette.dark;
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(palette),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 3.0,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
            // A notch and a gesture bar, which is what a real phone has and
            // what the tray has to stay clear of.
            padding: const EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: build(palette),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every screen under test, as builders so each can be pumped per theme.
  final screens = <String, Widget Function(LoomPalette, Tuning, Account)>{
    'menu': (p, t, a) => MenuScreen(
      account: a,
      palette: p,
      canResume: true,
      onPlay: () {},
      onResume: () {},
      onShop: () {},
      onHowToPlay: () {},
      onSettings: () {},
    ),
    'shop': (p, t, a) => ShopScreen(
      account: a,
      economy: t.economy,
      palette: p,
      onChanged: () {},
    ),
    // The set picker is a section of the shop now, not a screen (docs/08 E7),
    // so 'shop' above covers it. The rules screen is the new menu entry.
    'howToPlay': (p, t, a) => HowToPlayScreen(palette: p),
  };

  group('tap targets and labels', () {
    for (final name in screens.keys) {
      testWidgets('$name meets both platform tap-target minimums', (
        tester,
      ) async {
        final a = richAccount();
        await pump(tester, (p) => screens[name]!(p, tuning, a));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      });

      testWidgets('$name labels every tappable', (tester) async {
        final a = richAccount();
        await pump(tester, (p) => screens[name]!(p, tuning, a));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }

    testWidgets('the game screen meets the tap-target minimums', (
      tester,
    ) async {
      // With every tool armed, because the tool chips were the smallest
      // targets in the game — 31px high before this pass.
      final c = controllerFor(richAccount(), withTools: true);
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    });

    testWidgets('the draft overlay meets the tap-target minimums', (
      tester,
    ) async {
      final c = controllerFor(richAccount());
      c.draftOptions = tuning.powers.defs.where((d) => d.isInitial).take(3).toList();
      c.phase = GamePhase.draft;
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('the settings icon has an accessible name', (tester) async {
      // It is icon-only, so without a name a screen reader announces nothing
      // but "button".
      final c = controllerFor(richAccount());
      // Semantics have to be on BEFORE the tree is built, or the nodes this
      // searches for were never created.
      await withSemantics(tester, () async {
        await pump(
          tester,
          (p) => GameScreen(
            controller: c,
            palette: p,
            onAgain: () {},
            onMenu: () {},
            onShop: () {},
          ),
        );
        expect(find.byIcon(Icons.settings), findsOneWidget);
        // The IconButton's node, not the Icon's: the Icon itself is
        // deliberately unlabelled, and the accessible name belongs to the
        // control that does something.
        final node = tester.getSemantics(find.byType(IconButton));
        expect(
          node.label,
          contains('Settings'),
          reason: 'the settings control must announce what it does',
        );
        expect(node.flagsCollection.isButton, isTrue);
      });
    });
  });

  group('text contrast', () {
    // One palette to check since 2026-11-12 (`docs/07` §4i); this used to run
    // each screen twice.
    testWidgets('the menu passes the contrast guideline', (tester) async {
      final a = richAccount();
      await pump(tester, (p) => screens['menu']!(p, tuning, a));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });

    testWidgets('the shop passes the contrast guideline', (tester) async {
      final a = richAccount();
      await pump(tester, (p) => screens['shop']!(p, tuning, a));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });

  group('large text and small screens', () {
    for (final name in screens.keys) {
      testWidgets('$name survives the largest allowed text scale', (
        tester,
      ) async {
        // The clamp in app.dart caps scaling at maxTextScale; this is that
        // worst case on the narrowest phone, which is the only combination
        // where an overflow actually shows up.
        final a = richAccount();
        await pump(
          tester,
          (p) => screens[name]!(p, tuning, a),
          textScale: maxTextScale,
          size: const Size(360, 640),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('drafted tools stay on screen, not scrolled out of it', (
      tester,
    ) async {
      // The bug this pins: the tool row used to be the last child of the HUD,
      // which lives in a height-capped `SingleChildScrollView`. As soon as the
      // readouts above it grew — a long fault name, a large text scale, a short
      // phone — the tools slid out of sight in the gap between the header and
      // the board, with no scrollbar to say they existed.
      //
      // `findsOneWidget` would not have caught it: a widget scrolled out of a
      // viewport is still in the tree. The assertion has to be geometric.
      //
      // It matters because these are charge-limited escape valves costing a
      // draft pick each (docs/05 §3). A tool the player cannot see is a card
      // they paid for and will never spend.
      const size = Size(360, 640);
      final c = controllerFor(richAccount(), withTools: true);
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
        textScale: maxTextScale,
        size: size,
      );
      expect(tester.takeException(), isNull);

      final tools = find.byType(ToolButton);
      expect(tools, findsWidgets, reason: 'the run drafted tools');

      final screen = Rect.fromLTWH(0, 0, size.width, size.height);
      for (var i = 0; i < tools.evaluate().length; i++) {
        final r = tester.getRect(tools.at(i));
        // The first tool must be fully on screen. Later ones may run off the
        // right-hand edge, which is fine and deliberate — the row scrolls
        // horizontally, where a thumb can reach it — so only the vertical
        // bounds are checked past the first.
        expect(
          r.top,
          greaterThanOrEqualTo(screen.top),
          reason: 'tool $i is above the top of the screen',
        );
        expect(
          r.bottom,
          lessThanOrEqualTo(screen.bottom),
          reason: 'tool $i is below the bottom of the screen',
        );
        if (i == 0) {
          expect(
            screen.contains(r.center),
            isTrue,
            reason: 'the first tool must be fully visible, not clipped',
          );
        }
      }

      // **The load-bearing assertion.** This is the one that actually failed
      // on the old layout: the button existed, laid out inside plausible
      // bounds, and was clipped out of its scroll viewport, so hit-testing
      // found nothing and the tap went nowhere. A control the player cannot
      // press is the bug, whatever its rect says.
      await tester.tap(tools.first);
      await tester.pumpAndSettle();
      expect(c.aiming, isNot(ToolAim.none));
    });

    testWidgets('the tool row takes no space before a tool is drafted', (
      tester,
    ) async {
      // The board is the game; an empty strip reserving height above it is a
      // cost paid by every run for a feature most runs do not have yet.
      final c = controllerFor(richAccount());
      await pump(
        tester,
        (p) => Scaffold(
          backgroundColor: p.background,
          body: ToolRow(controller: c, palette: p),
        ),
        size: const Size(360, 640),
      );
      expect(find.byType(ToolButton), findsNothing);
      expect(tester.getSize(find.byType(ToolRow)).height, 0);
    });

    testWidgets('the HUD alone survives the largest allowed text scale', (
      tester,
    ) async {
      // Isolated from the board, because Flutter reports only the first
      // overflow per run and a game-screen failure hides which strip caused
      // it.
      final c = controllerFor(richAccount(), withTools: true);
      await pump(
        tester,
        (p) => Scaffold(
          backgroundColor: p.background,
          body: Hud(controller: c, palette: p, onSettings: () {}),
        ),
        textScale: maxTextScale,
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the game screen survives the largest allowed text scale', (
      tester,
    ) async {
      final c = controllerFor(richAccount(), withTools: true);
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
        textScale: maxTextScale,
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the run summary survives the largest allowed text scale', (
      tester,
    ) async {
      final c = controllerFor(richAccount());
      c.powers = c.powers.plus(const PickedPower('slub_yarn', motifId: 'l3'));
      c.phase = GamePhase.lost;
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
        textScale: maxTextScale,
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('safe areas', () {
    testWidgets('the tray stays clear of the gesture bar', (tester) async {
      // The tray is the primary touch region of the game. With the bottom
      // inset unpadded it sat under the home indicator, so every low drag
      // raced the system back/home swipe.
      const size = Size(375, 812);
      const bottomInset = 34.0;
      final c = controllerFor(richAccount());
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
        size: size,
      );

      final board = tester.getRect(find.byType(CustomPaint).last);
      expect(
        board.bottom,
        lessThanOrEqualTo(size.height - bottomInset + 0.5),
        reason: 'the board/tray canvas must end above the gesture bar',
      );
    });
  });

  group('reduced motion', () {
    testWidgets('the draft overlay renders at once, with no animation', (
      tester,
    ) async {
      final c = controllerFor(richAccount());
      c.draftOptions = tuning.powers.defs.where((d) => d.isInitial).take(3).toList();
      c.phase = GamePhase.draft;
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
        reduceMotion: true,
      );
      // Every card is fully present, and no stagger animation was built at
      // all — the reveal is skipped, not merely shortened.
      expect(find.text('Small Block Bonus'), findsOneWidget);
      expect(find.byType(StaggeredList), findsOneWidget);
      expect(find.byType(AnimatedScale), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a press does not animate under reduced motion', (
      tester,
    ) async {
      final a = richAccount();
      await pump(
        tester,
        (p) => screens['menu']!(p, tuning, a),
        reduceMotion: true,
      );
      // PressScale returns its child untouched, so no scale animation exists
      // to interrupt.
      expect(find.byType(AnimatedScale), findsNothing);
    });

    testWidgets('a press DOES animate when motion is allowed', (tester) async {
      final a = richAccount();
      await pump(tester, (p) => screens['menu']!(p, tuning, a));
      expect(find.byType(AnimatedScale), findsWidgets);
    });
  });

  group('orientation', () {
    testWidgets('landscape does not throw, even though portrait is locked', (
      tester,
    ) async {
      // The app locks portrait, but a device can still deliver one landscape
      // frame during rotation, and that frame must not be an exception.
      final c = controllerFor(richAccount());
      await pump(
        tester,
        (p) => GameScreen(
          controller: c,
          palette: p,
          onAgain: () {},
          onMenu: () {},
          onShop: () {},
        ),
        size: const Size(812, 375),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
