/// Haptics.
///
/// Wire this in the **first playable build, not as polish** — on a phone it
/// carries most of the feel (spec §7). The pattern:
///
/// - light tick on lift and on each snap change
/// - medium thud on place
/// - **strong double-tap on a line clear**
/// - sharp buzz on a multiplier break
library;

import 'package:flutter/services.dart';

class Haptics {
  Haptics({this.enabled = true});

  bool enabled;

  /// Snap changes fire often during a drag. A tick per cell crossing is the
  /// point; a tick per frame is a vibrating brick, so they are rate-limited.
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _tickFloor = Duration(milliseconds: 40);

  Future<void> lift() => _tick();

  Future<void> snap() => _tick();

  Future<void> _tick() async {
    if (!enabled) return;
    final now = DateTime.now();
    if (now.difference(_lastTick) < _tickFloor) return;
    _lastTick = now;
    await HapticFeedback.lightImpact();
  }

  Future<void> place() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// The game's loudest feedback, and deliberately so: a line clear is the
  /// thing the whole board is arranged around.
  Future<void> lineClear() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }

  Future<void> multiplierBreak() async {
    if (!enabled) return;
    await HapticFeedback.vibrate();
  }

  Future<void> invalid() async {
    if (!enabled) return;
    await HapticFeedback.selectionClick();
  }

  Future<void> stageClear() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
  }
}
