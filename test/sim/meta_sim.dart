/// **docs/08 A1 — the drafting, account-carrying simulation.**
///
/// The old harness (`curve_sim_test.dart`) plays a greedy placement player
/// against a bare ladder: no draft, no account, a fixed loadout. That is the
/// right instrument for port parity and the wrong one for every balance
/// question the design actually has open, because the shipped game hands the
/// player eleven picks and a shop.
///
/// This harness drives the **real [RunController]** instead of a
/// reimplementation of the ladder, which matters more than it sounds: the
/// controller is where drafts, faults, motif choices, tool charges and stage
/// sequencing live, so a sim built beside it would drift from the game within
/// a week. The greedy placement player is unchanged — it is still the floor.
///
/// What is a *policy* here rather than a rule is marked, because every policy
/// is a decision about how a hypothetical player behaves and each one is a
/// place the measurement can be wrong:
///
/// - **Placement**: greedy, no lookahead (`greedy.dart`). A floor.
/// - **Draft**: take the highest `gain` on offer. docs/05 §6 calls this "the
///   simplest useful version", and it gives a floor on *build quality* the way
///   greedy placement gives a floor on play. It is also deliberately naive:
///   `gain` figures are estimates, so a draft policy that trusts them inherits
///   their errors, which is exactly what we want to expose.
/// - **Loadout**: the smallest motifs you own. Small motifs are more liquid,
///   so this is what a knowledgeable player does; it is not what a new player
///   does.
/// - **Fault**: by default the easiest tier offered. Conservative — harder
///   faults pay better drafts, so taking the easy one understates depth.
///
/// None of these predicts a human. They produce a *consistent* player, so a
/// change to the tuning shows up as a change in how far runs get.
library;

import 'package:loomcraft/core/faults.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/core/shapes.dart';
import 'package:loomcraft/core/types.dart';
import 'package:loomcraft/data/tuning.dart';
import 'package:loomcraft/game/account.dart';
import 'package:loomcraft/game/run_controller.dart';
import 'package:loomcraft/platform/haptics.dart';
import 'package:loomcraft/platform/storage.dart';

import 'greedy.dart';

/// Which fault the sim takes when an act offers a choice.
enum FaultPick {
  /// The easiest offered. Understates depth, so a gate that passes here passes.
  lowest,

  /// The hardest offered — the reward tiers make this the greedy-income pick.
  highest,
}

class SimPolicy {
  const SimPolicy({
    this.families,
    this.faultPick = FaultPick.lowest,
    this.takeCards = true,
    this.inject = const [],
  });

  /// Powers handed to the run at its start instead of drafted, for measuring
  /// one card at a time ([measureCard]).
  ///
  /// Applied straight to the controller's [PowerSet], which covers every
  /// *passive* card. It does **not** cover cards whose effect runs through the
  /// controller's own card path — Cull and Favour rewrite the bag, Batten and
  /// Second Shuttle touch charges and the tray — nor tools, which the greedy
  /// player never activates. Those are listed in [unmeasurableCards].
  final List<PickedPower> inject;

  /// Restrict the draft to these `powers.json` families, for the
  /// forced-archetype runs in docs/05 §5. `null` means the whole pool.
  ///
  /// The restriction is a preference, not a hard filter: if an offer contains
  /// nothing from the family the sim still takes the best card available,
  /// because a real player playing an archetype does not skip a free pick.
  final Set<String>? families;

  final FaultPick faultPick;

  /// False measures the ladder with no build at all, which is the old
  /// harness's question asked through the new harness.
  final bool takeCards;
}

class SimReport {
  const SimReport({
    required this.seed,
    required this.stage,
    required this.stagesCleared,
    required this.won,
    required this.total,
    required this.placements,
    required this.peakRhythm,
    required this.reason,
    required this.picks,
    required this.offers,
    required this.faults,
    required this.spools,
  });

  final int seed;

  /// The stage the run was on when it ended.
  final int stage;
  final int stagesCleared;
  final bool won;
  final int total;
  final int placements;
  final double peakRhythm;
  final LossReason? reason;

  /// Card ids taken, in order.
  final List<String> picks;

  /// Every card id *offered*, including the ones not taken. docs/08 C4 needs
  /// this: a card is dead or mispriced by how often it is passed over, which
  /// the picks alone cannot show.
  final List<String> offers;

  /// Fault ids chosen, one per act reached.
  final List<String> faults;

  final int spools;
}

/* ------------------------------------------------------------------ */
/* Building an account at a given unlock fraction                     */
/* ------------------------------------------------------------------ */

/// An account that owns the cheapest `fraction` of everything buyable.
///
/// Buying in **ascending price order across both tracks** is both what a
/// sensible player does and what ties this measurement to the real economy:
/// change a price in `data/economy.json` and the 85% account changes with it,
/// rather than staying pinned to a hand-written list that quietly goes stale.
///
/// Milestones are set as a function of the same fraction, because the two
/// really do travel together — a player who has bought 85% of the shop has
/// played dozens of runs and met most of the milestone conditions. That is an
/// assumption, and it is the one to revisit if the unlock gates misbehave: it
/// makes a mid-progress account's *card pool* wider than its spools alone
/// would justify.
Account accountAt(
  double fraction,
  Economy economy, {
  Milestones? milestones,
}) {
  final buyable = <({int cost, String kind, String id})>[];

  for (final tier in [2, 3, 4]) {
    final prices = economy.shapeCosts[tier] ?? const <int>[];
    final shapes = shapesOfTier(tier);
    for (var i = 0; i < shapes.length && i < prices.length; i++) {
      buyable.add((cost: prices[i], kind: 'shape', id: shapes[i].id));
    }
  }
  for (final u in economy.upgrades.values) {
    buyable.add((cost: u.cost, kind: 'upgrade', id: u.id));
  }

  buyable.sort((a, b) => a.cost - b.cost);

  final take = (buyable.length * fraction).round().clamp(0, buyable.length);
  final owned = <String>{for (final s in tier1) s.id};
  final upgrades = <String>{};
  for (var i = 0; i < take; i++) {
    final item = buyable[i];
    if (item.kind == 'shape') {
      owned.add(item.id);
    } else {
      upgrades.add(item.id);
    }
  }

  final account = Account(
    ownedShapeIds: owned,
    upgrades: upgrades,
    milestones: milestones ?? _milestonesAt(fraction),
    faultsCleared: _faultsClearedAt(fraction),
  );
  account.loadout = chooseLoadout(account);
  account.refreshOwnershipMilestones();
  return account;
}

/// Which faults a player at this unlock fraction has plausibly cleared.
///
/// Fault tiers unlock by clearing the tier below (docs/06 §6a), so an account
/// measured at 100% has to carry this or the 100% gate would be measuring a
/// narrower game than it claims.
Set<String> _faultsClearedAt(double fraction) {
  const tier1 = {'thin_place', 'fixed_heddles', 'tight_reed'};
  const tier2 = {'reediness', 'barre', 'the_smash'};
  const tier3 = {'mispick', 'slubs', 'floats'};
  if (fraction >= 0.9) return {...tier1, ...tier2, ...tier3};
  if (fraction >= 0.5) return {...tier1, ...tier2};
  if (fraction > 0) return {...tier1};
  return {};
}

/// Milestone state a player at this unlock fraction has plausibly reached.
///
/// **This couples two axes that are independent, and that matters.** Milestones
/// track what a player has *done*; purchases track what they have *bought*.
/// Tying them together is realistic for the three unlock gates — someone who
/// has bought 85% of the shop has played dozens of runs — but it makes the
/// *equipment* sweep unreadable, because a step in depth could be a motif or
/// could be a milestone widening the card pool.
///
/// It bit once already: the first "the first four purchases are worth +6
/// stages" reading was partly this. At 3/24 purchases `lostToBrokenRhythm` is
/// false and at 4/24 it is true, which unlocks **Patience** — the pool's
/// strongest uncommon. The step was a card, not a bag.
///
/// So any sweep that varies purchases must pass an explicit [Milestones] to
/// [accountAt] and hold it fixed.
Milestones _milestonesAt(double fraction) {
  if (fraction <= 0) return const Milestones();
  return Milestones(
    bestStage: (12 * fraction).round(),
    bestRhythm: 1.0 + 3.0 * fraction,
    runsFinished: (60 * fraction).round(),
    clearedThreeAtOnce: fraction >= 0.3,
    lostToBrokenRhythm: fraction >= 0.15,
    jammed: fraction >= 0.5,
    spoolsBanked: (6000 * fraction).round(),
  );
}

/// **Policy.** Eight scoring motifs, then one small one for emergencies.
///
/// This was "the smallest motifs owned", which was right while the roster ran
/// size-ascending and became wrong the moment it inverted: `dot` sorts first
/// by cell count and is a **scoring liability** — one point and a spent
/// placement — so the old policy filled a full account's loadout with the
/// cheapest-scoring pieces it owned and made 100% unlocks measure *worse* than
/// 85%.
///
/// A knowledgeable player wants the 3–4 cell band, which is where points per
/// placement peaks against the risk of not fitting, plus one small piece to
/// finish holes with. So: the 3–4 cell motifs first, then the smallest of
/// what is left.
///
/// Like every policy here it is a model of a player, not a player. Treat the
/// depth it produces as "someone who understands the game", not "a person".
List<String> chooseLoadout(Account account) {
  int cells(Shape s) => cellsOf(s.id, 0).length;
  final owned = [
    for (final id in account.ownedShapeIds) shape(id),
  ]..sort((a, b) {
    final aBand = cells(a) >= 3 && cells(a) <= 4 ? 0 : 1;
    final bBand = cells(b) >= 3 && cells(b) <= 4 ? 0 : 1;
    if (aBand != bBand) return aBand - bBand;
    final byCells = cells(a) - cells(b);
    return byCells != 0 ? byCells : a.id.compareTo(b.id);
  });
  return [for (final s in owned.take(account.loadoutSlots)) s.id];
}

/* ------------------------------------------------------------------ */
/* The run                                                            */
/* ------------------------------------------------------------------ */

/// Play one seeded run of the real controller to its end.
SimReport simulateRun({
  required Tuning tuning,
  required Account account,
  required int seed,
  SimPolicy policy = const SimPolicy(),
  int guard = 20000,
}) {
  final controller = RunController(
    tuning: tuning,
    account: account,
    storage: MemoryStorage(),
    haptics: Haptics(enabled: false),
    seedSource: () => seed,
  );

  final picks = <String>[];
  final offers = <String>[];
  final faults = <String>[];
  var peakRhythm = 1.0;
  var placements = 0;

  controller.begin();
  for (final pick in policy.inject) {
    controller.powers = controller.powers.plus(pick);
  }

  for (var step = 0; step < guard; step++) {
    switch (controller.phase) {
      case GamePhase.faultChoice:
        final chosen = _pickFault(controller.faultOptions, policy.faultPick);
        faults.add(chosen.id);
        controller.chooseFault(chosen.id);

      case GamePhase.draft:
        if (!policy.takeCards || controller.draftOptions.isEmpty) {
          controller.skipDraft();
          break;
        }
        offers.addAll(controller.draftOptions.map((d) => d.id));
        final card = _pickCard(controller.draftOptions, policy.families);
        picks.add(card.id);
        controller.takeDraftCard(card);

      case GamePhase.motifChoice:
        controller.chooseMotifForCard(
          _pickMotif(controller.pendingMotifCard, controller.bagLoadout),
        );

      case GamePhase.placing:
        final slots = <TrayItem?>[
          ...controller.tray,
          if (controller.powers.hasHold) controller.holdItem,
        ];
        final move = bestMove(
          controller.board,
          slots,
          allowRotation: !controller.rotationDisabled,
        );
        if (move == null) {
          // The controller detects the jam itself on the next tick; looping
          // here without placing would spin the guard instead.
          throw StateError('greedy found no move while still placing');
        }
        _rotateTo(controller, move.slot, move.rotation);
        if (!controller.place(move.slot, Anchor(move.ax, move.ay))) {
          throw StateError('greedy proposed an illegal placement');
        }
        placements++;
        if (controller.ladder.score.multiplier > peakRhythm) {
          peakRhythm = controller.ladder.score.multiplier;
        }

      case GamePhase.lost:
      case GamePhase.won:
        return SimReport(
          seed: seed,
          stage: controller.ladder.stage,
          stagesCleared: controller.stagesCleared,
          won: controller.phase == GamePhase.won,
          total: controller.ladder.score.total,
          placements: placements,
          peakRhythm: peakRhythm,
          reason: controller.ladder.lossReason,
          picks: picks,
          offers: offers,
          faults: faults,
          spools: controller.spoolsEarned,
        );
    }
  }
  throw StateError('run did not terminate within $guard steps');
}

FaultDef _pickFault(List<FaultDef> options, FaultPick how) {
  if (options.isEmpty) throw StateError('fault choice with no options');
  final sorted = [...options]..sort((a, b) => a.tier - b.tier);
  return how == FaultPick.lowest ? sorted.first : sorted.last;
}

/// **Policy.** Highest estimated gain on offer (docs/05 §6).
///
/// Gambles are skipped when anything else is available: Bulk Order's gain is
/// negative by design, so a pure max-gain policy would never take it anyway,
/// but Piecework's gain is *zero* and would be taken over nothing at all,
/// which is not what a player does with a free pick.
PowerDef _pickCard(List<PowerDef> options, Set<String>? families) {
  Iterable<PowerDef> pool = options;
  if (families != null) {
    final preferred = options.where((d) => families.contains(d.family));
    if (preferred.isNotEmpty) pool = preferred;
  }
  final serious = pool.where((d) => d.gain > 0);
  final from = serious.isNotEmpty ? serious : pool;
  return from.reduce((a, b) => b.gain > a.gain ? b : a);
}

/// **Policy.** Cull the biggest motif in the bag; favour or enrich the
/// smallest. Both follow from small motifs being the liquid ones.
String _pickMotif(PowerDef? card, List<Shape> bag) {
  if (bag.isEmpty) throw StateError('motif choice with an empty bag');
  final sorted = [...bag]
    ..sort((a, b) => cellsOf(a.id, 0).length - cellsOf(b.id, 0).length);
  return card?.id == 'cull' ? sorted.last.id : sorted.first.id;
}

void _rotateTo(RunController c, int slot, int target) {
  TrayItem? live() => slot < c.tray.length ? c.tray[slot] : c.holdItem;
  var guard = 0;
  while (live() != null && live()!.rotation != target && guard++ < 8) {
    c.rotate(slot);
  }
}

/* ------------------------------------------------------------------ */
/* Reading a batch of runs                                            */
/* ------------------------------------------------------------------ */

class SimBatch {
  SimBatch(this.label, this.reports);

  final String label;
  final List<SimReport> reports;

  List<int> get _stages => [for (final r in reports) r.stage]..sort();

  int get medianStage => _quantile(_stages, 0.5);
  int get p10Stage => _quantile(_stages, 0.1);
  int get p90Stage => _quantile(_stages, 0.9);
  int get bestStage => _stages.last;
  int get wins => reports.where((r) => r.won).length;
  double get winRate => wins / reports.length;
  int get jams =>
      reports.where((r) => r.reason == LossReason.jam).length;

  int get medianTotal =>
      _quantile([for (final r in reports) r.total]..sort(), 0.5);
  int get medianPlacements =>
      _quantile([for (final r in reports) r.placements]..sort(), 0.5);
  double get medianPeakRhythm =>
      _quantile([for (final r in reports) r.peakRhythm]..sort(), 0.5);
  int get medianSpools =>
      _quantile([for (final r in reports) r.spools]..sort(), 0.5);

  /// How often each card was taken, as a fraction of the drafts it appeared
  /// in. docs/05 §6 item 5 / docs/08 C4: under 5% is dead, over 60% is
  /// underpriced.
  Map<String, double> get pickRates {
    final offered = <String, int>{};
    final taken = <String, int>{};
    for (final r in reports) {
      for (final id in r.offers) {
        offered[id] = (offered[id] ?? 0) + 1;
      }
      for (final id in r.picks) {
        taken[id] = (taken[id] ?? 0) + 1;
      }
    }
    return {
      for (final e in offered.entries)
        e.key: (taken[e.key] ?? 0) / e.value,
    };
  }

  Map<String, int> get faultChoices {
    final counts = <String, int>{};
    for (final r in reports) {
      for (final id in r.faults) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  Map<int, int> get histogram {
    final h = <int, int>{};
    for (final s in _stages) {
      h[s] = (h[s] ?? 0) + 1;
    }
    return h;
  }

  String report() {
    final h = histogram.entries.toList()..sort((a, b) => a.key - b.key);
    return [
      '',
      '── $label  (${reports.length} runs)',
      '   stage reached   p10 $p10Stage · median $medianStage · '
          'p90 $p90Stage · best $bestStage',
      '   wins            $wins / ${reports.length} '
          '(${(winRate * 100).toStringAsFixed(0)}%)',
      '   deaths          target ${reports.length - jams - wins} · jam $jams',
      for (final e in h)
        '     stage ${e.key.toString().padLeft(2)}  '
            '${'#' * e.value} ${e.value}',
      '   median total    $medianTotal',
      '   median moves    $medianPlacements',
      '   median peak ×   ${medianPeakRhythm.toStringAsFixed(2)}',
      '   median spools   $medianSpools',
      '',
    ].join('\n');
  }
}

/// Play [runs] seeded runs on a fresh copy of [account] each time.
///
/// A fresh copy per run matters: the controller mutates the account (spools,
/// milestones, `lastPlayedDay`), so reusing one would let run 3 draft from a
/// pool that run 1 unlocked, and the batch would no longer measure a single
/// point on the progression curve.
SimBatch simulateBatch({
  required String label,
  required Tuning tuning,
  required double unlockFraction,
  int runs = 60,
  SimPolicy policy = const SimPolicy(),
  Milestones? milestones,
}) {
  final reports = <SimReport>[];
  for (var seed = 1; seed <= runs; seed++) {
    reports.add(simulateRun(
      tuning: tuning,
      account: accountAt(
        unlockFraction,
        tuning.economy,
        milestones: milestones,
      ),
      seed: seed,
      policy: policy,
    ));
  }
  return SimBatch(label, reports);
}

/* ------------------------------------------------------------------ */
/* Measuring one card                                                 */
/* ------------------------------------------------------------------ */

/// Cards this harness cannot price, and why.
///
/// Stating them is the point: a measurement that silently returns 0% for a
/// card the sim never uses is worse than no measurement, because it reads as
/// evidence that the card is dead.
const Map<String, String> unmeasurableCards = {
  'unpick': 'a tool — the greedy player never activates one',
  'rethread': 'a tool',
  'shears': 'a tool',
  'resley': 'a tool',
  'batten': 'a tool, and it sets charges through the card path',
  'hold': 'a tool',
  'cull': 'rewrites the bag through the controller card path',
  'favour': 'rewrites the bag through the controller card path',
  'second_shuttle': 'changes the tray through the controller card path',
  'piecework': 'pays spools, not depth — gain 0 is correct, not a failure',
  'bulk_order': 'a gamble: trades depth for currency by design',
  'apprentice': 'widens the draft, which this harness bypasses',
  'jacquard_card': 'informs a decision the greedy player does not make',
};

class CardMeasurement {
  const CardMeasurement({
    required this.id,
    required this.pointsPerStage,
    required this.baselinePointsPerStage,
    required this.medianStage,
    required this.baselineMedianStage,
  });

  final String id;
  final double pointsPerStage;
  final double baselinePointsPerStage;
  final int medianStage;
  final int baselineMedianStage;

  /// Measured gain, as the percentage `powers.json` claims to express: how much
  /// this card adds to a floor player's per-stage capability.
  double get gainPercent =>
      (pointsPerStage / baselinePointsPerStage - 1) * 100;
}

/// Points per stage played, median across [runs] seeded runs.
///
/// Divided by stages *played* rather than cleared, so the stage a run died in
/// counts — it is a stage the player scored in. The last stage is partial in
/// both arms of the comparison, so the ratio between them still holds.
double _pointsPerStage(List<SimReport> reports) {
  final perStage = [
    for (final r in reports) r.total / (r.stagesCleared + 1),
  ]..sort();
  return _quantile(perStage, 0.5);
}

/// What one card is actually worth, against a no-build baseline.
///
/// Every `gain` in `powers.json` is an estimate — docs/05 §1 says so plainly
/// and asks for exactly this. Drafting is switched off in both arms so the
/// measurement is the card and nothing else.
CardMeasurement measureCard({
  required Tuning tuning,
  required String cardId,
  String? motifId,
  int stacks = 1,
  int runs = 60,
  double unlockFraction = 0,
}) {
  SimBatch run(List<PickedPower> inject) => simulateBatch(
    label: cardId,
    tuning: tuning,
    unlockFraction: unlockFraction,
    runs: runs,
    policy: SimPolicy(takeCards: false, inject: inject),
  );

  final baseline = run(const []);
  final withCard = run([
    for (var i = 0; i < stacks; i++) PickedPower(cardId, motifId: motifId),
  ]);

  return CardMeasurement(
    id: cardId,
    pointsPerStage: _pointsPerStage(withCard.reports),
    baselinePointsPerStage: _pointsPerStage(baseline.reports),
    medianStage: withCard.medianStage,
    baselineMedianStage: baseline.medianStage,
  );
}

T _quantile<T>(List<T> sorted, double q) =>
    sorted[(sorted.length * q).floor().clamp(0, sorted.length - 1)];
