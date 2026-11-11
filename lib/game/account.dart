/// The persistent account: spools, owned motifs, bought upgrades, milestones
/// and the chosen draft (loadout).
///
/// Lives in `lib/game` rather than `lib/core` because it is serialised and
/// talks to storage; the rules engine never sees it. What it *produces* for
/// the engine is a loadout and a handful of opening numbers.
library;

import '../core/powers.dart';
import '../core/shapes.dart';
import '../core/types.dart';

/// Base loadout size. You own motifs and pick this many per run — the fix for
/// the original's dilution problem, where every unlock went into the bag and
/// buying more could leave you worse off (docs/01 §5).
const int baseLoadoutSlots = 8;

class Account {
  Account({
    this.spools = 0,
    Set<String>? ownedShapeIds,
    Set<String>? upgrades,
    List<String>? loadout,
    this.milestones = const Milestones(),
    this.lastPlayedDay,
    this.hapticsEnabled = true,
    this.runsStarted = 0,
    this.bestRunTotal = 0,
    this.wins = 0,
  })  : ownedShapeIds = ownedShapeIds ?? {for (final s in tier1) s.id},
        upgrades = upgrades ?? {},
        loadout = loadout ?? [for (final s in tier1) s.id];

  int spools;

  /// Tier 1's five motifs are free at install.
  Set<String> ownedShapeIds;

  /// Ids from `data/economy.json.upgrades`.
  Set<String> upgrades;

  /// The motifs chosen for the next run, in order.
  List<String> loadout;

  Milestones milestones;

  /// `yyyy-mm-dd` of the last run started, for the first-run-of-day bonus.
  String? lastPlayedDay;

  bool hapticsEnabled;
  int runsStarted;
  int bestRunTotal;
  int wins;

  int get loadoutSlots =>
      baseLoadoutSlots + (upgrades.contains('loadoutSlot9') ? 1 : 0);

  bool owns(String shapeId) => ownedShapeIds.contains(shapeId);
  bool hasUpgrade(String id) => upgrades.contains(id);

  int ownedInTier(int tier) =>
      ownedShapeIds.where((id) => shape(id).tier == tier).length;

  /// Fraction of everything unlockable that is unlocked.
  ///
  /// docs/06 §3 keys the three gates to this: unwinnable at 0%, winnable with
  /// a good run at ~85%, reliable at 100%.
  double get unlockFraction {
    final totalShapes = allShapes.length;
    final totalUpgrades = 9;
    return (ownedShapeIds.length + upgrades.length) /
        (totalShapes + totalUpgrades);
  }

  /// The shapes the next run's bag will be built from.
  ///
  /// With only tier 1 you cannot fill eight slots, so the loadout is simply
  /// everything you own — which is also why early power comes from breadth
  /// rather than from choosing well (docs/06 §4).
  List<Shape> loadoutShapes() {
    final valid = loadout.where(owns).toList();
    final chosen = valid.take(loadoutSlots).toList();
    if (chosen.isEmpty) {
      return [for (final id in ownedShapeIds.take(loadoutSlots)) shape(id)];
    }
    return [for (final id in chosen) shape(id)];
  }

  /* ---------------- the opening, as bought ---------------- */

  /// Opening Rhythm: start each run at ×1.2 instead of ×1.0.
  double? get openingMultiplier => hasUpgrade('openingRhythm') ? 1.2 : null;

  /// Starting Selvage: begin each run holding one shield.
  int get openingShields => hasUpgrade('startingSelvage') ? 1 : 0;

  /// Opening Allowance: +2 placements on stage 1.
  int get openingAllowanceBonus => hasUpgrade('openingAllowance') ? 2 : 0;

  YarnUpgrades get yarnUpgrades => YarnUpgrades(
    fineYarn: hasUpgrade('fineYarn'),
    standardYarn: hasUpgrade('standardYarn'),
    heavyYarn: hasUpgrade('heavyYarn'),
  );

  /// Keep [milestones] in step with what the account itself knows, so a
  /// milestone that depends on ownership cannot go stale.
  void refreshOwnershipMilestones() {
    milestones = milestones.copyWith(
      tier3Owned: ownedInTier(3),
      motifsOwned: ownedShapeIds.length,
      spoolsBanked: spools,
    );
  }

  /* ---------------- serialisation ---------------- */

  Map<String, dynamic> toJson() => {
    'spools': spools,
    'owned': ownedShapeIds.toList(),
    'upgrades': upgrades.toList(),
    'loadout': loadout,
    'lastPlayedDay': lastPlayedDay,
    'haptics': hapticsEnabled,
    'runsStarted': runsStarted,
    'bestRunTotal': bestRunTotal,
    'wins': wins,
    'milestones': {
      'bestStage': milestones.bestStage,
      'bestRhythm': milestones.bestRhythm,
      'runsFinished': milestones.runsFinished,
      'clearedThreeAtOnce': milestones.clearedThreeAtOnce,
      'lostToBrokenRhythm': milestones.lostToBrokenRhythm,
      'jammed': milestones.jammed,
    },
  };

  /// Tolerant by design: a save written by an older build must load field by
  /// field rather than all-or-nothing, or one added field costs every player
  /// their account.
  static Account fromJson(Map<String, dynamic> j) {
    final m = (j['milestones'] as Map<String, dynamic>?) ?? const {};
    final owned = <String>{
      for (final id in (j['owned'] as List?) ?? const [])
        if (shapesById.containsKey(id)) id as String,
    };
    if (owned.isEmpty) {
      owned.addAll([for (final s in tier1) s.id]);
    }
    final account = Account(
      spools: (j['spools'] as num?)?.toInt() ?? 0,
      ownedShapeIds: owned,
      upgrades: {
        for (final id in (j['upgrades'] as List?) ?? const []) id as String,
      },
      loadout: [
        for (final id in (j['loadout'] as List?) ?? const [])
          if (owned.contains(id)) id as String,
      ],
      lastPlayedDay: j['lastPlayedDay'] as String?,
      hapticsEnabled: (j['haptics'] as bool?) ?? true,
      runsStarted: (j['runsStarted'] as num?)?.toInt() ?? 0,
      bestRunTotal: (j['bestRunTotal'] as num?)?.toInt() ?? 0,
      wins: (j['wins'] as num?)?.toInt() ?? 0,
      milestones: Milestones(
        bestStage: (m['bestStage'] as num?)?.toInt() ?? 0,
        bestRhythm: (m['bestRhythm'] as num?)?.toDouble() ?? 1.0,
        runsFinished: (m['runsFinished'] as num?)?.toInt() ?? 0,
        clearedThreeAtOnce: (m['clearedThreeAtOnce'] as bool?) ?? false,
        lostToBrokenRhythm: (m['lostToBrokenRhythm'] as bool?) ?? false,
        jammed: (m['jammed'] as bool?) ?? false,
      ),
    );
    if (account.loadout.isEmpty) {
      account.loadout = owned.toList();
    }
    account.refreshOwnershipMilestones();
    return account;
  }
}
