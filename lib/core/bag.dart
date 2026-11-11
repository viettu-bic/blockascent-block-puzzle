/// The draw bag for one run, ported from `reference/ts-core/core/bag.ts`.
///
/// A shuffled bag rather than independent random draws, so a loadout of N
/// shapes is seen roughly evenly — independent draws produce streaks of the
/// same piece that read as unfair. Refills by reshuffling the whole loadout
/// when empty.
///
/// Which shapes form the loadout is the player's pre-run choice (docs/01 §5);
/// that is the fix for the original's dilution problem, and this class is
/// deliberately ignorant of how the loadout was chosen.
library;

import 'rng.dart';
import 'types.dart';

class Bag {
  Bag(List<Shape> loadout, this._rng) : _loadout = List.of(loadout) {
    if (_loadout.isEmpty) throw ArgumentError('empty loadout');
  }

  final List<Shape> _loadout;
  final Rng _rng;
  final List<Shape> _pending = [];

  List<Shape> get loadout => List.unmodifiable(_loadout);
  int get pendingCount => _pending.length;

  /// What is left of the current shuffle, bottom first — the order [draw]
  /// will consume from the end.
  ///
  /// This has to be persisted with a run. The bag is NOT a pure function of
  /// the loadout and the RNG cursor: how much of the current shuffle is left
  /// is independent state, because the cursor also advances for draft offers
  /// and knot scattering. Rebuilding the bag from the cursor alone reshuffles
  /// early and serves different motifs after a restore.
  List<String> get pendingIds => [for (final s in _pending) s.id];

  /// Restore a saved shuffle. Ids not in the loadout are dropped, so a save
  /// written before a Cull cannot resurrect the culled motif.
  void restorePending(List<String> ids) {
    _pending.clear();
    for (final id in ids) {
      final s = _loadout.firstWhere(
        (s) => s.id == id,
        orElse: () => const Shape(id: '', tier: 1, cellCount: 0, rotations: []),
      );
      if (s.id.isNotEmpty) _pending.add(s);
    }
  }

  /// A read-only peek at what the next draws will be, without consuming them.
  ///
  /// Jacquard Card ("see the next refill before spending the current tray")
  /// needs this. It may have to reshuffle to answer, so it is only correct to
  /// call between placements — which is the only time the card is offered.
  List<Shape> peek(int n) {
    while (_pending.length < n) {
      final refill = _rng.shuffle(List.of(_loadout));
      _pending.insertAll(0, refill);
    }
    return [for (var i = 0; i < n; i++) _pending[_pending.length - 1 - i]];
  }

  Shape draw() {
    if (_pending.isEmpty) {
      _pending.addAll(_rng.shuffle(List.of(_loadout)));
    }
    return _pending.removeLast();
  }

  /// Draw the first shape satisfying [test], putting the rejects back under
  /// the bag so nothing is lost.
  ///
  /// Barré ("the bag serves only motifs of 4 cells or more") and Small Hands
  /// ("every refill contains at least one motif of 3 cells or fewer") both
  /// need a filtered draw. Returns null when the loadout cannot satisfy the
  /// filter at all, which the caller must treat as "ignore the filter" rather
  /// than as an error — a fault that empties the bag would be an instant jam.
  Shape? drawWhere(bool Function(Shape) test) {
    if (!_loadout.any(test)) return null;
    final rejected = <Shape>[];
    for (var guard = 0; guard < _loadout.length * 4 + 8; guard++) {
      final s = draw();
      if (test(s)) {
        // Rejects go to the bottom, preserving their order.
        _pending.insertAll(0, rejected.reversed);
        return s;
      }
      rejected.add(s);
    }
    _pending.insertAll(0, rejected.reversed);
    return null;
  }

  /// Cull: permanently remove one motif from this run's bag.
  ///
  /// The most important card in the game — the only in-run answer to a bad
  /// bag, and the mechanical counterweight to the dilution problem the
  /// original never solved (docs/05 §3). Refuses to empty the bag.
  bool cull(String shapeId) {
    if (_loadout.length <= 1) return false;
    final i = _loadout.indexWhere((s) => s.id == shapeId);
    if (i < 0) return false;
    _loadout.removeAt(i);
    _pending.removeWhere((s) => s.id == shapeId);
    return true;
  }

  /// Favour: add a second copy of one motif to this run's bag.
  bool favour(String shapeId) {
    final s = _loadout.firstWhere(
      (s) => s.id == shapeId,
      orElse: () => throw ArgumentError('not in loadout: $shapeId'),
    );
    _loadout.add(s);
    return true;
  }

  /// Drop whatever is left of the current shuffle, so the next draw starts a
  /// fresh one. Used after Cull or Favour so the change is felt immediately.
  void resetPending() => _pending.clear();
}

/// Tray refill rule: refill **only** when all slots are empty.
///
/// This single rule is where the difficulty lives (spec §2.1). One-slot-at-a-
/// time refills always leave the player maximum choice and the board drifts
/// toward solvable forever; refilling only on empty forces commitment to
/// shapes they do not want, and the last placement of each cycle is where runs
/// die.
bool shouldRefill(List<TrayItem?> tray) => tray.every((slot) => slot == null);
