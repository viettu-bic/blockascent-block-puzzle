/// Loomcraft: Block Puzzle.
///
/// A no-gravity polyomino placement puzzle wrapped in a roguelite campaign.
/// The rules engine is in `lib/core` and imports nothing — see
/// `docs/00-implementation-spec.md`, which is self-contained.
library;

import 'package:flutter/material.dart';

import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await lockPortrait();
  await drawEdgeToEdge();
  runApp(const LoomcraftApp());
}
