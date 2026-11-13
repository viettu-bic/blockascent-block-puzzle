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
    Set<String>? faultsCleared,
    List<String>? loadout,
    this.milestones = const Milestones(),
    this.lastPlayedDay,
    this.hapticsEnabled = true,
    this.sfxEnabled = true,
    this.musicEnabled = true,
    this.seenHowToPlay = false,
    this.seenRotateHint = false,
    this.jamsSeen = 0,
    this.runsStarted = 0,
    this.bestRunTotal = 0,
    this.wins = 0,
  })  : // Copied, never adopted. Every one of these is mutated in place
        // later — the shop adds to `ownedShapeIds` and `upgrades`, clearing a
        // fault stage adds to `faultsCleared`, the loadout screen reorders
        // `loadout` — so holding a caller's collection means an unmodifiable
        // or shared one throws or leaks at the first purchase. A const set
        // literal from a test or a fixture is the usual way to find out.
        ownedShapeIds = {...(ownedShapeIds ?? {for (final s in tier1) s.id})},
        upgrades = {...?upgrades},
        faultsCleared = {...?faultsCleared},
        loadout = [...(loadout ?? [for (final s in tier1) s.id])];

  int spools;

  /// Tier 1's five motifs are free at install.
  Set<String> ownedShapeIds;

  /// Ids from `data/economy.json.upgrades`.
  Set<String> upgrades;

  /// Fault ids this account has cleared the stage of.
  ///
  /// Faults unlock by tier within their act (`unlockedFaults`): tier 1 is
  /// always offered, tier 2 opens once tier 1 is cleared, tier 3 once tier 2
  /// is. This has to live on the **account** rather than the run, because each
  /// act happens once per run — a per-run set would mean the player never saw
  /// anything but tier 1, ever.
  Set<String> faultsCleared;

  /// The motifs chosen for the next run, in order.
  List<String> loadout;

  Milestones milestones;

  /// `yyyy-mm-dd` of the last run started, for the first-run-of-day bonus.
  String? lastPlayedDay;

  bool hapticsEnabled;
  bool sfxEnabled;
  bool musicEnabled;

  /// Whether the rules screen has been opened.
  ///
  /// It no longer opens itself: the first launch goes straight into a level 1
  /// arranged to teach, and the rules live behind the menu card and the "?"
  /// in the HUD (UX review 1.1). Kept for save compatibility, and because
  /// "has this player ever read the rules" is still worth knowing.
  bool seenHowToPlay;

  /// Whether the player has dismissed "Tap a block to rotate it".
  ///
  /// Rotation is the only control the game has that it never names anywhere,
  /// so the hint appears the first time nothing in the tray fits unturned and
  /// then never again (UX review 4.1).
  bool seenRotateHint;

  /// How many runs have ended in a jam.
  ///
  /// The board-level explanation ("No block fits these gaps") is a lesson, not
  /// a readout, so it is shown on the first two jams and then the red cells
  /// speak for themselves (UX review 5).
  int jamsSeen;

  int runsStarted;
  int bestRunTotal;
  int wins;

  int get loadoutSlots =>
      baseLoadoutSlots +
      (upgrades.contains('loadoutSlot9') ? 1 : 0) +
      (upgrades.contains('loadoutSlot10') ? 1 : 0);

  /// A 4th tray slot, bought rather than drafted.
  ///
  /// docs/04 §3 refused to sell this — biggest power swing, alters the
  /// refill-on-empty rule, roughly halves jam risk. All true, and all three
  /// are now reasons to sell it: halving jam risk is what the shop is *for*
  /// (docs/08 B7). Second Shuttle stacks on top for a 5th.
  int get extraTraySlots => hasUpgrade('fourthTraySlot') ? 1 : 0;

  /// Handful: every refill contains a motif of 3 cells or fewer. The strongest
  /// jam insurance in the shop.
  bool get guaranteesSmallMotif => hasUpgrade('handful');

  /// Toolkit: permanent tool charges, refreshed every stage.
  Map<String, int> get toolChargesPerStage =>
      hasUpgrade('toolkit') ? const {'unpick': 2} : const {};

  bool owns(String shapeId) => ownedShapeIds.contains(shapeId);
  bool hasUpgrade(String id) => upgrades.contains(id);
  bool hasClearedFault(String id) => faultsCleared.contains(id);

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

  /// Opening Rhythm: **every stage** starts at ×1.5 or better, not just the
  /// run. A break no longer follows you across a stage boundary, which is the
  /// difference between a number and a change to how a run feels.
  double? get openingMultiplier => hasUpgrade('openingRhythm') ? 2.0 : null;

  /// Starting Selvage: two shields, refilled at every stage.
  int get openingShields => hasUpgrade('startingSelvage') ? 3 : 0;

  /// Opening Allowance: +3 placements on **every** stage, not only the first.
  /// Allowance is what lets a player spend a placement digging out of a bad
  /// board instead of scoring, so it is jam insurance as much as tempo.
  int get openingAllowanceBonus => hasUpgrade('openingAllowance') ? 5 : 0;

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
    'faultsCleared': faultsCleared.toList(),
    'loadout': loadout,
    'lastPlayedDay': lastPlayedDay,
    'haptics': hapticsEnabled,
    'sfx': sfxEnabled,
    'music': musicEnabled,
    'seenHowToPlay': seenHowToPlay,
    'seenRotateHint': seenRotateHint,
    'jamsSeen': jamsSeen,
    'runsStarted': runsStarted,
    'bestRunTotal': bestRunTotal,
    'wins': wins,
    'milestones': milestones.toJson(),
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
      faultsCleared: {
        for (final id in (j['faultsCleared'] as List?) ?? const [])
          id as String,
      },
      loadout: [
        for (final id in (j['loadout'] as List?) ?? const [])
          if (owned.contains(id)) id as String,
      ],
      lastPlayedDay: j['lastPlayedDay'] as String?,
      hapticsEnabled: (j['haptics'] as bool?) ?? true,
      sfxEnabled: (j['sfx'] as bool?) ?? true,
      musicEnabled: (j['music'] as bool?) ?? true,
      // An existing save has already played, so do not interrupt it with a
      // tutorial it did not ask for.
      seenHowToPlay: (j['seenHowToPlay'] as bool?) ?? true,
      // An existing save has placed blocks already, so it is not shown a
      // first-time control hint it has no use for.
      seenRotateHint: (j['seenRotateHint'] as bool?) ?? true,
      jamsSeen: (j['jamsSeen'] as num?)?.toInt() ?? 0,
      runsStarted: (j['runsStarted'] as num?)?.toInt() ?? 0,
      bestRunTotal: (j['bestRunTotal'] as num?)?.toInt() ?? 0,
      wins: (j['wins'] as num?)?.toInt() ?? 0,
      milestones: Milestones.fromJson(Map<String, dynamic>.from(m)),
    );
    if (account.loadout.isEmpty) {
      account.loadout = owned.toList();
    }
    account.refreshOwnershipMilestones();
    return account;
  }
}
