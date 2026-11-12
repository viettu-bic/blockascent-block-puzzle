import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';
import 'package:loomcraft/data/tuning.dart';
import 'package:loomcraft/game/account.dart';
import 'package:loomcraft/game/run_controller.dart';
import 'package:loomcraft/platform/haptics.dart';
import 'package:loomcraft/platform/sfx.dart';
import 'package:loomcraft/platform/storage.dart';
import 'package:loomcraft/render/board_painter.dart';
import 'package:loomcraft/render/layout.dart';
import 'package:loomcraft/render/theme.dart';
import 'package:loomcraft/ui/app.dart';
import 'package:loomcraft/ui/game_screen.dart';
import 'package:loomcraft/ui/how_to_play_screen.dart';
import 'package:loomcraft/ui/shop_screen.dart';

import '../support/load_tuning.dart';

/// Smoke tests. These do not judge the drag — spec §7 is explicit that only a
/// physical device can — but they do catch the failures that make a build
/// unlaunchable: an overflowing layout, a missing asset, a screen that throws
/// on first paint.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded in setUpAll, never inside a testWidgets body: `loadTuningForTest`
  // does real file I/O, and a real-async future never completes inside the
  // fake-async zone testWidgets runs in — the test just hangs.
  late Tuning tuning;

  setUpAll(() async {
    tuning = await loadTuningForTest();
  });

  setUp(() {
    // The recorded loom frame is static and palette-keyed, so it has to be
    // dropped between tests that use different sizes.
    BoardPainter.invalidateChrome();
  });

  Future<void> pumpPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(child);
    // Boot is asynchronous (four JSON reads plus storage), so give it frames
    // to land before settling.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  LoomcraftApp app() => LoomcraftApp(
    storageOverride: MemoryStorage(),
    tuningOverride: tuning,
    // Silent: a real Sfx reaches the audioplayers platform channel, which a
    // widget test does not have.
    sfxOverride: Sfx(enabled: false),
  );

  group('boot', () {
    /// A fresh install opens the rules screen over the menu before anything
    /// else — that is the FTUE, not an accident — so a boot test has to get
    /// past it first. Dismissing it is also the assertion that it appeared.
    Future<void> dismissTutorial(WidgetTester tester) async {
      expect(
        find.text('How to Play'),
        findsOneWidget,
        reason: 'a fresh install should open the rules by itself',
      );
      // The button sits under the four rule cards, so it is below the fold on
      // a phone — which is the point: you scroll past the rules to continue.
      await tester.dragUntilVisible(
        find.text('Got it'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    }

    testWidgets('a fresh install opens the rules by itself, once', (
      tester,
    ) async {
      await pumpPhone(tester, app());
      await dismissTutorial(tester);
      // Back on the menu, and it does not come back.
      expect(find.text('Play'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Rows AND columns clear'), findsNothing);
    });

    testWidgets('loads the real data/*.json and shows the workshop', (
      tester,
    ) async {
      await pumpPhone(tester, app());
      await dismissTutorial(tester);
      expect(find.text('Play'), findsOneWidget);
      // The set picker moved into the shop, so the menu's second slot is the
      // rules now (docs/08 E7).
      expect(find.text('How to Play'), findsOneWidget);
      expect(find.text('Shop & Set'), findsOneWidget);
    });

    testWidgets('starting a run reaches the act 1 fault choice', (
      tester,
    ) async {
      await pumpPhone(tester, app());
      await dismissTutorial(tester);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Act 1'), findsOneWidget);
      // All three are shown — a ladder the player cannot see is not a ladder —
      // and the two locked ones carry what unlocks them.
      expect(find.text('Tight Budget'), findsOneWidget);
      expect(find.text('Columns Only'), findsOneWidget);
      expect(find.text('Short Fuse'), findsOneWidget);
      expect(find.textContaining('Locked'), findsNWidgets(2));
    });

    testWidgets('choosing a fault shows the board and the HUD', (
      tester,
    ) async {
      await pumpPhone(tester, app());
      await dismissTutorial(tester);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tight Budget'));
      await tester.pumpAndSettle();

      // The stage and the act share one line now, so they fit beside the
      // settings control at a large text scale.
      expect(find.textContaining('LEVEL 1 / 12'), findsOneWidget);
      expect(find.textContaining('ACT 1'), findsOneWidget);
      expect(find.text('×1.00'), findsOneWidget);
      expect(find.textContaining('moves left'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('screens render at phone size without overflowing', () {
    late RunController controller;
    late Account account;

    setUp(() {
      account = Account(
        spools: 5000,
        ownedShapeIds: {for (final s in allShapes) s.id},
        loadout: ['dot', 'i2', 'i3', 'o2', 'l3', 'i4', 't4', 'l4'],
      );
      controller = RunController(
        tuning: tuning,
        account: account,
        storage: MemoryStorage(),
        haptics: Haptics(enabled: false),
        seedSource: () => 7,
      );
      controller.begin();
      controller.chooseFault('thin_place');
    });

    Widget host(Widget child) => MaterialApp(
      theme: buildTheme(LoomPalette.dark),
      home: child,
    );

    testWidgets('the game screen', (tester) async {
      await pumpPhone(
        tester,
        host(
          GameScreen(
            controller: controller,
            palette: LoomPalette.dark,
            onAgain: () {},
            onMenu: () {},
            onShop: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the draft overlay, with four options under Apprentice', (
      tester,
    ) async {
      controller.powers =
          controller.powers.plus(const PickedPower('apprentice'));
      controller.draftOptions = controller.tuning.powers.defs
          .where((d) => d.isInitial)
          .take(4)
          .toList();
      controller.phase = GamePhase.draft;

      await pumpPhone(
        tester,
        host(
          GameScreen(
            controller: controller,
            palette: LoomPalette.dark,
            onAgain: () {},
            onMenu: () {},
            onShop: () {},
          ),
        ),
      );
      expect(find.text('Small Block Bonus'), findsOneWidget);
      expect(find.text('Take nothing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the run summary', (tester) async {
      controller.phase = GamePhase.lost;
      await pumpPhone(
        tester,
        host(
          GameScreen(
            controller: controller,
            palette: LoomPalette.dark,
            onAgain: () {},
            onMenu: () {},
            onShop: () {},
          ),
        ),
      );
      expect(find.text('Play again'), findsOneWidget);
      expect(find.text('Coins earned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shop, with every motif and upgrade', (tester) async {
      await pumpPhone(
        tester,
        host(
          ShopScreen(
            account: account,
            economy: controller.tuning.economy,
            palette: LoomPalette.dark,
            onChanged: () {},
          ),
        ),
      );
      expect(find.text('Shop'), findsOneWidget);
      // The set picker sits above the tiers now, so the first tier header is
      // below the fold on a phone.
      expect(find.text('YOUR SET'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('TIER 1'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('TIER 1'), findsOneWidget);
      // 'Combo Floor', not 'Starting Combo': the upgrades were rebuilt as
      // structural buys on 2026-11-12 (docs/04 §9). The header is checked
      // first, because there are eleven upgrades now and scrolling to the
      // one in the middle of the list leaves it off the top.
      await tester.dragUntilVisible(
        find.text('UPGRADES'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('UPGRADES'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Combo Floor'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Combo Floor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the set picker in the shop caps selection at the slots', (
      tester,
    ) async {
      // The picker lives in the shop now: buying a block and deciding whether
      // to play it are one decision (docs/08 E7).
      await pumpPhone(
        tester,
        host(
          ShopScreen(
            account: account,
            economy: controller.tuning.economy,
            palette: LoomPalette.dark,
            onChanged: () {},
          ),
        ),
      );
      expect(find.text('YOUR SET'), findsOneWidget);
      expect(find.text('8 / 8'), findsOneWidget);

      // Tapping an unselected motif while full must change nothing.
      await tester.tap(find.text('Long Line'));
      await tester.pumpAndSettle();
      expect(account.loadout, hasLength(8));
      expect(account.loadout, isNot(contains('i5')));

      // Dropping one frees a slot.
      await tester.tap(find.text('Single'));
      await tester.pumpAndSettle();
      expect(account.loadout, hasLength(7));
      expect(tester.takeException(), isNull);
    });
  });

  group('how to play', () {
    testWidgets('names the four rules a player cannot guess', (tester) async {
      await pumpPhone(
        tester,
        MaterialApp(
          theme: buildTheme(LoomPalette.dark),
          home: const HowToPlayScreen(palette: LoomPalette.dark),
        ),
      );
      // The two nobody brings with them from other block games.
      expect(find.text('Rows AND columns clear'), findsOneWidget);
      expect(
        find.text('The tray refills only when it is empty'),
        findsOneWidget,
      );
      // And the two this redesign created.
      expect(find.text('Clearing is the only way to score'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('A one-cell hole needs a one-cell block'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(
        find.text('A one-cell hole needs a one-cell block'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('a fresh account has not seen it; a loaded one has', () {
      // A new install gets the tutorial; an existing save does not get
      // interrupted by one it never asked for.
      expect(Account().seenHowToPlay, isFalse);
      expect(Account.fromJson({'spools': 10}).seenHowToPlay, isTrue);
      expect(
        Account.fromJson(Account().toJson()).seenHowToPlay,
        isFalse,
        reason: 'the flag round-trips rather than defaulting on save',
      );
    });
  });

  group('the board renders', () {
    testWidgets('paints a populated board and a held piece without throwing', (
      tester,
    ) async {
      final c = RunController(
        tuning: tuning,
        account: Account(),
        storage: MemoryStorage(),
        haptics: Haptics(enabled: false),
        seedSource: () => 3,
      );
      c.begin();
      c.chooseFault('thin_place');

      final layout = computeLayout(390, 600, 8, 8);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: const Size(390, 600),
            painter: BoardPainter(
              BoardView(
                board: c.board,
                layout: layout,
                palette: LoomPalette.dark,
                tray: c.tray,
                heldSlot: 0,
                heldCentre: layout.board.center,
                anchor: const Anchor(2, 2),
                ghost: GhostState.willClear,
                previewClears: const Clears([3], [4]),
                clearAnimation: const ClearAnimation(
                  clears: Clears([1], [2]),
                  t: 0.5,
                ),
                rotationDisabled: true,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('repaints only when the view changed', (tester) async {
      // An idle board must burn no GPU (spec §8).
      final layout = computeLayout(390, 600, 8, 8);
      final c = RunController(
        tuning: tuning,
        account: Account(),
        storage: MemoryStorage(),
        haptics: Haptics(enabled: false),
        seedSource: () => 3,
      );
      c.begin();
      c.chooseFault('thin_place');

      BoardView view() => BoardView(
        board: c.board,
        layout: layout,
        palette: LoomPalette.dark,
        tray: c.tray,
      );

      final a = BoardPainter(view());
      final b = BoardPainter(view());
      expect(b.shouldRepaint(a), isFalse);

      c.place(0, const Anchor(0, 0));
      expect(BoardPainter(view()).shouldRepaint(a), isTrue);
    });
  });
}
