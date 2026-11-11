import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec §3, and one of the README's two hard constraints:
///
/// > `lib/core` must not import `dart:ui`, `package:flutter`, or anything
/// > platform-specific.
///
/// That constraint is what buys daily challenges, replays, server-verifiable
/// scores and the simulation harness — all for free, later. It is also the
/// kind of rule that erodes one convenient import at a time, so it is checked
/// mechanically rather than by review.
void main() {
  test('lib/core imports nothing from Flutter or a platform', () {
    final dir = Directory('lib/core');
    expect(dir.existsSync(), isTrue, reason: 'run this from the repo root');

    final offenders = <String>[];
    // dart:math, dart:typed_data and dart:collection are pure language
    // libraries with no platform behind them, so they are allowed — with or
    // without an `as` prefix. Everything else in `dart:` reaches for a
    // platform: dart:io, dart:ui, dart:isolate, dart:html.
    final allowed =
        RegExp(r"^import 'dart:(math|typed_data|collection)'( as \w+)?;$");
    final importLine = RegExp(r"^import\s+'([^']+)'");

    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final raw in f.readAsLinesSync()) {
        final line = raw.trim();
        final m = importLine.firstMatch(line);
        if (m == null) continue;
        final uri = m.group(1)!;
        final isRelative = !uri.contains(':');
        if (isRelative || allowed.hasMatch(line)) continue;
        offenders.add('${f.path}: $line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'lib/core must stay pure Dart — move this code out of core',
    );
  });

  test('lib/core does not reach for a clock or an unseeded random', () {
    // Determinism is load-bearing. `DateTime.now()` and `dart:math`'s Random
    // both break a replay, and both are easy to reach for by accident.
    final offenders = <String>[];
    for (final f in Directory('lib/core')
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final needle in ['DateTime.now(', 'Random(', 'Random.secure(']) {
        if (!src.contains(needle)) continue;
        // rng.dart's randomSeed() is the one sanctioned entry point for
        // non-determinism: it *produces* a seed rather than consuming entropy
        // mid-run, and everything downstream of it is replayable.
        if (f.path.endsWith('rng.dart') && needle == 'DateTime.now(') continue;
        offenders.add('${f.path}: $needle');
      }
    }
    expect(offenders, isEmpty);
  });
}
