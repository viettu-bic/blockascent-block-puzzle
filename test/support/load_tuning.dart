import 'dart:convert';
import 'dart:io';

import 'package:loomcraft/core/faults.dart';
import 'package:loomcraft/core/powers.dart';
import 'package:loomcraft/core/run.dart';
import 'package:loomcraft/data/tuning.dart';

/// Load the real `data/*.json` from disk for a unit test.
///
/// Deliberately *not* via `rootBundle`: reading the files directly means these
/// tests fail when the shipping tuning is malformed, rather than when a test
/// fixture is. There is only one copy of these numbers and the tests check
/// that copy.
Future<Tuning> loadTuningForTest() async {
  Future<Map<String, dynamic>> read(String name) async =>
      jsonDecode(await File('data/$name').readAsString())
          as Map<String, dynamic>;

  return Tuning(
    curve: parseCurve(await read('curve.json')),
    economy: parseEconomy(await read('economy.json')),
    powers: parsePowers(await read('powers.json')),
    faults: parseFaults(await read('faults.json')),
  );
}

/// Convenience for tests that only want one slice.
Future<CurveConfig> loadCurveForTest() async =>
    (await loadTuningForTest()).curve;

Future<PowerPool> loadPowersForTest() async =>
    (await loadTuningForTest()).powers;

Future<FaultRoster> loadFaultsForTest() async =>
    (await loadTuningForTest()).faults;
