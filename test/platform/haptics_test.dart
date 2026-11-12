import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loomcraft/platform/haptics.dart';

/// Haptics had no test at all, which is how the real bug survived: the
/// `VIBRATE` permission was missing from the Android manifest, so every
/// `HapticFeedback.vibrate()` was a silent no-op and the loudest feedback in
/// the game was felt as nothing (see `lib/platform/haptics.dart`).
///
/// A test cannot check a manifest or how a given phone renders a constant, so
/// it checks the two things it can: that the **pattern** of each event is what
/// the design says, and that the toggle really silences everything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('HapticFeedback')) calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// How many times the motor was driven, as opposed to a `*Impact` tick.
  ///
  /// Every variant arrives as the same method, `HapticFeedback.vibrate`; what
  /// separates them is the argument. `vibrate()` sends **none**, while the
  /// impact family names its type — which is also a fair summary of why the
  /// two behave so differently on a real phone.
  int vibrates() => calls.where((c) => c.arguments == null).length;

  group('the events that must be felt drive the motor', () {
    test('a line clear is two pulses — the only way to score', () async {
      await Haptics().lineClear();
      expect(vibrates(), 2);
    });

    test('a combo break is three fast pulses, a stutter', () async {
      await Haptics().multiplierBreak();
      expect(vibrates(), 3);
    });

    test('a level clear is two pulses', () async {
      await Haptics().stageClear();
      expect(vibrates(), 2);
    });

    test('the end of a run is three pulses, and used to be silent', () async {
      // The worst gap in the set: a jam is 43% of early deaths and the run
      // simply ended with no feedback, while a combo break buzzed.
      await Haptics().runEnd();
      expect(vibrates(), 3);
    });

    test('a win is four pulses, and used to be silent too', () async {
      await Haptics().win();
      expect(vibrates(), 4);
    });

    test('they are distinguishable from each other by count', () async {
      final h = Haptics();
      await h.lineClear();
      final clear = vibrates();
      calls.clear();
      await h.runEnd();
      final over = vibrates();
      expect(
        clear,
        isNot(over),
        reason: 'vibrate() has no amplitude, so pattern is the only signal',
      );
    });
  });

  group('the ticks stay subtle', () {
    test('lifting and placing never drive the motor', () async {
      final h = Haptics();
      await h.lift();
      await h.place();
      await h.invalid();
      expect(calls, isNotEmpty, reason: 'they still fire something');
      expect(
        vibrates(),
        0,
        reason: 'a placement that clears nothing scores nothing — keep it a tap',
      );
    });

    test('lift is never throttled, so a quick second drag still ticks', () async {
      // It used to share the snap throttle, so picking a block up right after
      // a drag could lose its own feedback — which is one half of "sometimes".
      final h = Haptics();
      await h.lift();
      await h.lift();
      await h.lift();
      expect(calls, hasLength(3));
    });

    test('snap is throttled, because a tick per frame is a vibrating brick',
        () async {
      final h = Haptics();
      await h.snap();
      await h.snap();
      await h.snap();
      expect(calls, hasLength(1), reason: 'within the 40ms floor');
    });
  });

  group('the toggle', () {
    test('silences every event', () async {
      final h = Haptics(enabled: false);
      await h.lift();
      await h.snap();
      await h.place();
      await h.invalid();
      await h.lineClear();
      await h.multiplierBreak();
      await h.stageClear();
      await h.runEnd();
      await h.win();
      expect(calls, isEmpty);
    });

    test('a pattern interrupted mid-way stops where it is', () async {
      // The player can flip the switch while a run is in flight, and a
      // four-pulse win takes most of half a second.
      final h = Haptics();
      final pending = h.win();
      h.enabled = false;
      await pending;
      expect(
        vibrates(),
        lessThan(4),
        reason: 'turning it off should take effect immediately',
      );
    });
  });
}
