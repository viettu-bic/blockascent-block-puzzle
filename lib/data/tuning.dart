/// Loaders for the JSON in `data/`.
///
/// All tuning lives in `data/*.json`, never inline in Dart (spec §2.8). There
/// is exactly one copy of those files — the repo-root `data/` directory, which
/// `pubspec.yaml` declares as an asset and which the TypeScript oracle in
/// `reference/` reads too. Duplicating them under `assets/` would guarantee
/// that one copy goes stale.
///
/// Keys beginning with `_` in those files are commentary for humans and are
/// ignored here.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../core/faults.dart';
import '../core/powers.dart';
import '../core/run.dart';
import '../core/scoring.dart';

class Tuning {
  const Tuning({
    required this.curve,
    required this.economy,
    required this.powers,
    required this.faults,
  });

  final CurveConfig curve;
  final Economy economy;
  final PowerPool powers;
  final FaultRoster faults;

  static Future<Tuning> load() async {
    final jsons = await Future.wait([
      _loadJson('data/curve.json'),
      _loadJson('data/economy.json'),
      _loadJson('data/powers.json'),
      _loadJson('data/faults.json'),
    ]);
    return Tuning(
      curve: parseCurve(jsons[0]),
      economy: parseEconomy(jsons[1]),
      powers: parsePowers(jsons[2]),
      faults: parseFaults(jsons[3]),
    );
  }

  static Future<Map<String, dynamic>> _loadJson(String path) async =>
      jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>;
}

CurveConfig parseCurve(Map<String, dynamic> j) {
  final s = j['scoring'] as Map<String, dynamic>?;
  return CurveConfig(
    baseTarget: (j['baseTarget'] as num).toInt(),
    targetGrowth: (j['targetGrowth'] as num).toDouble(),
    baseAllowance: (j['baseAllowance'] as num).toInt(),
    allowanceGrowth: (j['allowanceGrowth'] as num).toInt(),
    stages: (j['stages'] as num?)?.toInt() ?? 12,
    scoring: s == null
        ? ScoringConfig.defaults
        : ScoringConfig(
            lineBonusTable: [
              for (final v in s['lineBonus'] as List) (v as num).toInt(),
            ],
            multStart: (s['multStart'] as num).toDouble(),
            multStep: (s['multStep'] as num).toDouble(),
            multCap: (s['multCap'] as num).toDouble(),
            patienceMax: (s['patienceMax'] as num).toInt(),
          ),
  );
}

/* ------------------------------------------------------------------ */
/* Economy                                                            */
/* ------------------------------------------------------------------ */

class Payout {
  const Payout({
    required this.base,
    required this.perStage,
    required this.firstRunOfDayBonus,
    this.payForStageReached = true,
  });

  final int base;
  final int perStage;
  final int firstRunOfDayBonus;

  /// Pay for every stage the run **reached**, not only the ones it cleared.
  ///
  /// See [forRun]. Kept in `data/economy.json` rather than inline so the rule
  /// can be switched off and re-simulated without a rebuild.
  final bool payForStageReached;

  /// `spools = sum over s in 1..n of (base + perStage * s)`.
  ///
  /// Payout keys off **stages, never score**. Score inflates when the player
  /// buys value upgrades; stages do not, because the target curve defines
  /// them. Keying payout to score creates a buy-more-earn-more spiral that
  /// destroys the curve (docs/04 §1).
  int forStages(int n) {
    var total = 0;
    for (var s = 1; s <= n; s++) {
      total += base + perStage * s;
    }
    return total;
  }

  /// What a finished run actually pays, before Piecework and the daily bonus.
  ///
  /// A run is paid for every stage it **reached**. The stage you fought and
  /// lost is a stage you played, and paying nothing for it is what made a real
  /// first run return 35 spools against a 100-spool first unlock — the greedy
  /// sim clears 5 stages, a first-time human clears 2, and the economy had
  /// been priced against the sim (docs/04 §7).
  ///
  /// This is still keyed to stages, not score, so docs/04 §1 rule 1 holds: a
  /// stage reached is defined by the fixed target curve and cannot inflate.
  /// Monotonic in depth, and a win has no unreached stage, so the 12-stage
  /// cap is unchanged.
  int forRun({
    required int stagesCleared,
    required int finalStage,
    required bool won,
  }) {
    if (!payForStageReached) return forStages(stagesCleared);
    if (won) return forStages(stagesCleared);
    final reached =
        stagesCleared + 1 <= finalStage ? stagesCleared + 1 : finalStage;
    return forStages(reached);
  }
}

class UpgradeDef {
  const UpgradeDef({
    required this.id,
    required this.cost,
    required this.effect,
  });

  final String id;
  final int cost;
  final String effect;
}

class Economy {
  const Economy({
    required this.payout,
    required this.shapeCosts,
    required this.upgrades,
  });

  final Payout payout;

  /// Tier (2..4) to the ascending price list for that tier. Tier 1 is free at
  /// install.
  final Map<int, List<int>> shapeCosts;
  final Map<String, UpgradeDef> upgrades;

  int costOfNthShapeInTier(int tier, int alreadyOwnedInTier) {
    final list = shapeCosts[tier];
    if (list == null || list.isEmpty) return 0;
    return list[alreadyOwnedInTier.clamp(0, list.length - 1)];
  }

  int upgradeCost(String id) => upgrades[id]?.cost ?? 0;
}

const Map<String, String> upgradeNames = {
  'fourthTraySlot': 'Fourth Tray Slot',
  'loadoutSlot9': 'Ninth Block Slot',
  'loadoutSlot10': 'Tenth Block Slot',
  'handful': 'Small Block Guarantee',
  'toolkit': 'Toolkit',
  'openingRhythm': 'Combo Floor',
  'openingAllowance': 'Extra Moves',
  'startingSelvage': 'Shields',
  'fineYarn': 'Small Block Bonus',
  'standardYarn': 'Mid Block Bonus',
  'heavyYarn': 'Big Block Bonus',
};

Economy parseEconomy(Map<String, dynamic> j) {
  final p = j['payout'] as Map<String, dynamic>;
  final sc = j['shapeCosts'] as Map<String, dynamic>;
  final up = j['upgrades'] as Map<String, dynamic>;

  final costs = <int, List<int>>{};
  for (final tier in [2, 3, 4]) {
    final list = sc['tier$tier'];
    if (list is List) {
      costs[tier] = [for (final v in list) (v as num).toInt()];
    }
  }

  final upgrades = <String, UpgradeDef>{};
  up.forEach((key, value) {
    if (key.startsWith('_')) return;
    if (value is num) {
      upgrades[key] = UpgradeDef(id: key, cost: value.toInt(), effect: '');
    } else if (value is Map<String, dynamic>) {
      upgrades[key] = UpgradeDef(
        id: key,
        cost: (value['cost'] as num).toInt(),
        effect: (value['effect'] as String?) ?? '',
      );
    }
  });

  return Economy(
    payout: Payout(
      base: (p['base'] as num).toInt(),
      perStage: (p['perStage'] as num).toInt(),
      firstRunOfDayBonus: (p['firstRunOfDayBonus'] as num?)?.toInt() ?? 0,
      payForStageReached: (p['payForStageReached'] as bool?) ?? true,
    ),
    shapeCosts: costs,
    upgrades: upgrades,
  );
}

/* ------------------------------------------------------------------ */
/* Powers and faults                                                  */
/* ------------------------------------------------------------------ */

PowerPool parsePowers(Map<String, dynamic> j) {
  final offer = j['offer'] as Map<String, dynamic>;
  return PowerPool(
    offerCount: (offer['count'] as num).toInt(),
    noDuplicateUnlessStackable:
        (offer['noDuplicateUnlessStackable'] as bool?) ?? true,
    weights: [
      for (final w in offer['weights'] as List)
        OfferWeights(
          upToStage: ((w as Map<String, dynamic>)['upToStage'] as num).toInt(),
          common: (w['common'] as num).toInt(),
          uncommon: (w['uncommon'] as num).toInt(),
          rare: (w['rare'] as num).toInt(),
        ),
    ],
    defs: [
      for (final p in j['powers'] as List)
        PowerDef(
          id: (p as Map<String, dynamic>)['id'] as String,
          family: p['family'] as String,
          rarity: rarityFromName(p['rarity'] as String),
          unlock: p['unlock'] as String,
          stacks: (p['stacks'] as num).toInt(),
          gain: (p['gain'] as num).toInt(),
          effect: p['effect'] as String,
          gamble: (p['gamble'] as bool?) ?? false,
          measured: (p['measured'] as bool?) ?? false,
        ),
    ],
  );
}

FaultRoster parseFaults(Map<String, dynamic> j) => FaultRoster([
  for (final a in j['acts'] as List)
    FaultAct(
      act: ((a as Map<String, dynamic>)['act'] as num).toInt(),
      stage: (a['stage'] as num).toInt(),
      name: a['name'] as String,
      faults: [
        for (final f in a['faults'] as List)
          FaultDef(
            id: (f as Map<String, dynamic>)['id'] as String,
            name: f['name'] as String,
            tier: (f['tier'] as num).toInt(),
            rule: f['rule'] as String,
            attacks: f['attacks'] as String,
            act: (a['act'] as num).toInt(),
            stage: (a['stage'] as num).toInt(),
          ),
      ],
    ),
]);
