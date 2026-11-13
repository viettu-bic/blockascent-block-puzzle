/// The three audio toggles, in one place, reachable from two.
///
/// They used to live only in the in-run settings sheet, which is reachable
/// **only from inside a run** — so to turn the sound off you had to start one
/// first. That was tolerable with a single Vibration switch and silly with
/// three, so the sheet is shared: the menu opens it on its own, and the game
/// screen opens it with "Quit this run" added underneath.
library;

import 'package:flutter/material.dart';

import '../game/account.dart';
import '../platform/haptics.dart';
import '../platform/music.dart';
import '../platform/sfx.dart';
import '../render/theme.dart';

/// The switches themselves, so both callers show exactly the same thing.
///
/// Each one writes to the account *and* to the live object, because the
/// account is what survives a restart and the object is what the current run
/// is already holding.
List<Widget> audioToggles({
  required Account account,
  required LoomPalette palette,
  required VoidCallback onChanged,
  Haptics? haptics,
  Sfx? sfx,
  Music? music,
}) {
  final p = palette;

  // Three switches, three words, no descriptions (UX review 9.1). "A calm
  // loop. Quieter than the effects on purpose" is a note about how the music
  // was made; nobody decides whether to turn sound on by reading it. "Sound"
  // became "Sound effects" because that is the only thing that tells it apart
  // from "Music".
  Widget toggle({
    required String title,
    required bool value,
    required ValueChanged<bool> onToggle,
  }) =>
      SwitchListTile(
        value: value,
        onChanged: (v) {
          onToggle(v);
          onChanged();
        },
        title: Text(title, style: TextStyle(color: p.ink)),
        activeThumbColor: p.accent,
      );

  return [
    toggle(
      title: 'Music',
      value: account.musicEnabled,
      onToggle: (v) {
        account.musicEnabled = v;
        music?.setEnabled(v);
      },
    ),
    toggle(
      title: 'Sound effects',
      value: account.sfxEnabled,
      onToggle: (v) {
        account.sfxEnabled = v;
        if (sfx != null) sfx.enabled = v;
      },
    ),
    toggle(
      title: 'Vibration',
      value: account.hapticsEnabled,
      onToggle: (v) {
        account.hapticsEnabled = v;
        if (haptics != null) haptics.enabled = v;
      },
    ),
  ];
}

/// The sheet, for callers with nothing to add to it — i.e. the menu.
Future<void> showAudioSettings(
  BuildContext context, {
  required Account account,
  required LoomPalette palette,
  required VoidCallback onChanged,
  Haptics? haptics,
  Sfx? sfx,
  Music? music,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.panel,
    builder: (context) => SafeArea(
      child: StatefulBuilder(
        // The switches have to redraw as they are flipped, and the menu behind
        // the sheet is not what is rebuilding.
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...audioToggles(
                account: account,
                palette: palette,
                haptics: haptics,
                sfx: sfx,
                music: music,
                onChanged: () {
                  setSheetState(() {});
                  onChanged();
                },
              ),
              const SizedBox(height: Space.sm),
            ],
          ),
        ),
      ),
    ),
  );
}
