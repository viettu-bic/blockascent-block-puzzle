import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/data/tuning.dart';

import '../support/load_tuning.dart';

/// `Tuning.load()` reads `data/*.json` through `rootBundle`, which is how the
/// shipping app gets its numbers. That path can only really break in one way —
/// `pubspec.yaml` not declaring the asset — and it cannot be covered from a
/// `testWidgets` body, because a widget test runs in a fake-async zone where a
/// real platform-channel future never completes.
///
/// So it is covered here instead, in a plain test with real async.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads every tuning file from the asset bundle', () async {
    final t = await Tuning.load();

    expect(t.curve.baseTarget, 80);
    expect(t.curve.stages, 12);
    expect(t.curve.scoring.lineBonusTable, const [0, 10, 25, 45, 70, 100]);
    expect(t.economy.payout.forStages(5), 125);
    expect(t.economy.shapeCosts[2], hasLength(5));
    expect(t.economy.upgrades, hasLength(11));
    expect(t.powers.defs, hasLength(34));
    expect(t.powers.offerCount, 3);
    expect(t.powers.weights, hasLength(3));
    expect(t.faults.all, hasLength(9));
    expect(t.faults.acts.map((a) => a.stage), [4, 8, 12]);
  });

  test('the asset bundle serves the same copy the repo holds', () async {
    // There is exactly one copy of these files: the repo-root `data/`
    // directory, which pubspec declares as an asset and which the TypeScript
    // oracle reads too. If someone ever adds a second copy under `assets/`,
    // this is where the two silently disagree.
    final bundled = await Tuning.load();
    final onDisk = await loadTuningForTest();

    expect(bundled.curve.targetGrowth, onDisk.curve.targetGrowth);
    expect(bundled.curve.baseAllowance, onDisk.curve.baseAllowance);
    expect(bundled.curve.stages, onDisk.curve.stages);
    expect(
      bundled.powers.defs.map((d) => '${d.id}:${d.gain}'),
      onDisk.powers.defs.map((d) => '${d.id}:${d.gain}'),
    );
    expect(
      bundled.faults.all.map((f) => f.id),
      onDisk.faults.all.map((f) => f.id),
    );
    expect(
      bundled.economy.upgrades.values.map((u) => '${u.id}:${u.cost}'),
      onDisk.economy.upgrades.values.map((u) => '${u.id}:${u.cost}'),
    );
  });
}
