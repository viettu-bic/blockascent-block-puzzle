/// Persistence: the account (spools, unlocks, upgrades, milestones) and the
/// autosaved run in progress.
///
/// **Autosave after every placement.** Phone games get interrupted; losing a
/// run to a phone call is unforgivable (spec §8).
///
/// Two separate keys rather than one blob: the account must survive a corrupt
/// or version-mismatched run save, because losing a run is annoying and losing
/// a month of unlocks is uninstallable. Both are JSON so a save from an older
/// build can be read field by field instead of all-or-nothing.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class Storage {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
  Future<void> delete(String key);
}

const String accountKey = 'loomcraft.account.v1';
const String runKey = 'loomcraft.run.v1';

class PrefsStorage implements Storage {
  PrefsStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsStorage> open() async =>
      PrefsStorage(await SharedPreferences.getInstance());

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      // A save we cannot parse is a save we must not crash on. Drop it and
      // carry on — the account and the run are stored separately precisely so
      // this only ever costs one of them.
      await delete(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    await _prefs.setString(key, jsonEncode(value));
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }
}

/// In-memory storage, for tests and for a first launch where preferences are
/// unavailable.
class MemoryStorage implements Storage {
  final Map<String, Map<String, dynamic>> _data = {};

  @override
  Future<Map<String, dynamic>?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}
