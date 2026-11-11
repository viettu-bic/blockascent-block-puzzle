import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';
import 'package:loomcraft/data/tuning.dart';
import 'package:loomcraft/game/account.dart';
import 'package:loomcraft/game/run_controller.dart';
import 'package:loomcraft/platform/haptics.dart';
import 'package:loomcraft/platform/storage.dart';
import 'package:loomcraft/render/board_painter.dart';
import 'package:loomcraft/render/layout.dart';
import 'package:loomcraft/render/theme.dart';
import 'package:loomcraft/ui/app.dart';
import 'package:loomcraft/ui/game_screen.dart';
import 'package:loomcraft/ui/loadout_screen.dart';
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
  );

  group('boot', () {
    testWidgets('loads the real data/*.json and shows the workshop', (
      tester,
    ) async {
      await pumpPhone(tester, app());
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Your Blocks'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
    });

    testWidgets('starting a run reaches the act 1 fault choice', (
      tester,
    ) async {
      await pumpPhone(tester, app());
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Act 1'), findsOneWidget);
      expect(find.text('Tight Budget'), findsOneWidget);
      expect(find.text('Columns Only'), findsOneWidget);
      expect(find.text('Short Fuse'), findsOneWidget);
    });

    testWidgets('choosing a fault shows the board and the HUD', (
      tester,
    ) async {
      await pumpPhone(tester, app());
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Columns Only'));
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
      theme: buildTheme(LoomPalette.dark, Brightness.dark),
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
      expect(find.text('TIER 1'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Starting Combo'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Starting Combo'), findsOneWidget);
      expect(find.text('UPGRADES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the loadout screen caps selection at the slot count', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        host(
          LoadoutScreen(
            account: account,
            palette: LoomPalette.dark,
            onChanged: () {},
          ),
        ),
      );
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
