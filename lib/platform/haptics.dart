/// Haptics.
///
/// Wire this in the **first playable build, not as polish** — on a phone it
/// carries most of the feel (spec §7).
///
/// ## Why this was rebuilt on 2026-11-12
///
/// Reported from a device: *"I barely feel anything, just sometimes on a
/// random block picked."* Two causes, and the first was fatal:
///
/// 1. **There was no `VIBRATE` permission in the Android manifest.**
///    `HapticFeedback.vibrate()` drives the system `Vibrator`, which silently
///    does nothing without `android.permission.VIBRATE`. So the combo-break
///    buzz — the loudest feedback the design asked for — never fired at all.
/// 2. **The `*Impact` family is not ordered the way its names suggest.** On
///    Android those map onto `performHapticFeedback` constants whose strength
///    is up to the OEM and whose relative weight is not guaranteed, so
///    `heavyImpact` is often *lighter* than `mediumImpact` and several render
///    as nothing. They also respect a system touch-feedback toggle the player
///    may have off. That is exactly "sometimes, on some actions".
///
/// So the events that **must** be felt use `vibrate()`, which actually drives
/// the motor, and they differentiate by **pattern** rather than by strength —
/// one pulse, two, three — because `vibrate()` has no amplitude control
/// without a plugin and this stays dependency-free.
///
/// The `*Impact` family is kept only for the ticks, where being subtle is the
/// point and being dropped on a stingy device costs nothing.
///
/// ## The mapping, and why it is this way
///
/// | Event | Feel | |
/// |---|---|---|
/// | lift, snap | faint tick | throttled; a tick per frame is a vibrating brick |
/// | place | light tap | fires 20–40× a stage, and a placement that clears nothing is worth **zero points** now (docs/05 §10) — it should feel unremarkable |
/// | **line clear** | **two pulses** | the only way to score, so it is the thing you feel |
/// | combo break | three fast pulses | a stutter reads as "that went wrong" |
/// | level clear | two spaced pulses | |
/// | **run over** | three slow pulses | was **silent**, and a jam is 43% of early deaths |
/// | **win** | four rising pulses | was silent too |
///
/// The through-line: **you feel it when you score, and when a run ends.**
library;

import 'package:flutter/services.dart';

class Haptics {
  Haptics({this.enabled = true});

  bool enabled;

  /// Snap changes fire often during a drag. A tick per cell crossing is the
  /// point; a tick per frame is a vibrating brick, so they are rate-limited.
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _tickFloor = Duration(milliseconds: 40);

  /// Picking a block up is the start of a gesture, so it is never throttled —
  /// sharing the snap throttle meant a quick second drag lost its own lift.
  Future<void> lift() async {
    if (!enabled) return;
    _lastTick = DateTime.now();
    await HapticFeedback.selectionClick();
  }

  Future<void> snap() async {
    if (!enabled) return;
    final now = DateTime.now();
    if (now.difference(_lastTick) < _tickFloor) return;
    _lastTick = now;
    await HapticFeedback.selectionClick();
  }

  /// A placement that clears nothing scores nothing, so it stays a tap.
  Future<void> place() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// The game's loudest feedback, and deliberately so: clearing a line is the
  /// only way to score, so it is the one thing the hand should always register.
  Future<void> lineClear() => _pulses(2, const Duration(milliseconds: 90));

  /// Three fast pulses — a stutter, which reads as "that went wrong".
  Future<void> multiplierBreak() =>
      _pulses(3, const Duration(milliseconds: 60));

  Future<void> stageClear() => _pulses(2, const Duration(milliseconds: 160));

  /// The run is over, by jam or by target.
  ///
  /// **This used to be silent**, which was the worst gap in the set: a jam is
  /// 43% of early deaths (docs/04 §9) and the moment the player most needs to
  /// register, while a mere combo break got a full buzz.
  Future<void> runEnd() => _pulses(3, const Duration(milliseconds: 200));

  /// Twelve levels cleared. Also used to be silent.
  Future<void> win() => _pulses(4, const Duration(milliseconds: 130));

  Future<void> invalid() async {
    if (!enabled) return;
    await HapticFeedback.selectionClick();
  }

  /// [count] system vibrations with [gap] between them.
  ///
  /// `vibrate()` rather than the impact family because it is the only one that
  /// reliably drives the motor on Android — and it needs
  /// `android.permission.VIBRATE`, which is why that is now in the manifest.
  Future<void> _pulses(int count, Duration gap) async {
    if (!enabled) return;
    for (var i = 0; i < count; i++) {
      if (i > 0) await Future<void>.delayed(gap);
      if (!enabled) return;
      await HapticFeedback.vibrate();
    }
  }
}
