# Blockascent: Block Puzzle

A no-gravity polyomino placement puzzle wrapped in a roguelite campaign.
**Flutter / Dart, iOS and Android, portrait.**

Pieces are **placed**, never dropped. Full **rows and columns both clear**. A
combo multiplier is the real resource. A run is a ladder of **12 stages**, each
with a score target and a limited number of placements; clearing one lets you
**draft one of three** upgrade cards, and the board carries over. Dying pays a
currency that permanently unlocks shapes and upgrades.

---

## Start here

**→ [`docs/00-implementation-spec.md`](docs/00-implementation-spec.md)**  —  the spec.
**→ [`docs/07-port-notes.md`](docs/07-port-notes.md)**  —  what the Dart port
actually does, what it is verified against, and what is left.

The spec is self-contained: the model, the algorithms, the Dart porting
hazards, the drag spec, the build order and the verification gate. Everything
else is reference.

Build-order steps 1–9 are done. The exception is step 5's exit test — the drag
has to be judged on a physical phone, and has not been. Read the port notes
before changing anything in `lib/`.

The first file written was `lib/core/rng.dart` and the first test was the
golden-vector check in §5.3, because if those ten numbers do not match,
nothing downstream is trustworthy. They match to 1e-15.

---

## What is already decided

This project arrives with the design settled and the numbers measured, not
guessed. Three things are worth knowing before you change any of them:

- **The curve was wrong by a factor of three on the first attempt.** The
  original `300 × 1.45` killed 100% of simulated runs on stage 1. The current
  `100 × 1.25` came out of a greedy simulation harness, which is in
  `reference/ts-tests/curve.sim.test.ts` and should be ported.
- **Payout keys off stages cleared, never score.** Keying it to score creates an
  inflation spiral: buy a value upgrade → score rises → earn more → buy more,
  and because stage targets are fixed, the ladder also gets easier. See
  `docs/04 §1`.
- **Shape unlocks never dilute the draw bag.** You own shapes and pick 8 per
  run. The original design this is based on added every unlock to the bag, so
  buying more could leave you worse off. See `docs/01 §5`.
- **The simulated floor player is not the floor.** The greedy sim clears 5
  stages; a first-time human clears 2. The economy was priced against the sim,
  so a real first run paid 35 spools against a 100-spool first unlock and the
  shop was unaffordable — while the test asserting "first unlock on run 1"
  passed, because it asked the bot. Simulate balance, measure onboarding. See
  `docs/04 §7`.

---

## Layout

```
docs/00-implementation-spec.md   the spec — start here
docs/01 … 06                     design reasoning (what, why, how much)
docs/07-port-notes.md            the port: status, deviations, findings
docs/08-design-backlog.md        open design questions, with ids
data/*.json                      all tuning: curve, economy, powers, faults
lib/core/                        PURE DART rules engine — imports nothing
lib/data/                        loaders for data/*.json
lib/render/ lib/input/ lib/ui/   painter, drag controller, screens
lib/game/                        the run controller: sequencing, not rules
lib/platform/                    haptics, storage
test/                            mirrors lib, plus test/sim — the parity gate
reference/ts-core/               proven TypeScript core — the port oracle
reference/ts-tests/              its 79 passing tests + the simulation harness
```

```bash
flutter test      # 389 tests, including the port-parity gate
flutter analyze
```

`.claude/skills/puzzle-roguelite-design/` carries the design method and the
invariants — the evidence standard, the one relationship every card's value hangs
on, and the verification recipes — so a design change does not have to start by
re-reading 2,400 lines of `docs/`. Read it before proposing any tuning number.

`reference/` is **not** code to ship. It is a working implementation of the
rules engine with a full test suite, kept so the Dart port has something to be
verified against rather than merely reviewed.

---

## The two gates

**Port parity — passed.** `test/sim/curve_sim_test.dart` reproduces the
TypeScript histogram from the same seeds: median stage 6, median run total
1,118, 124 median placements, 0% jam deaths. A silent RNG or rounding
difference changes the game and nobody notices for a month, so those numbers
are pinned as assertions.

**The drag — still outstanding.** Nothing after the rules engine is worth building until the drag
feels right *on a physical phone*. A mouse in an emulator will tell you it is
fine when it is not. The constants that decide it are in spec §7 and in
`lib/input/drag_controller.dart`; the snap rule itself is unit-tested, the feel
is not and cannot be.

---

## Two hard constraints

**`lib/core` imports nothing** — no Flutter, no `dart:ui`, no platform APIs. It
is a pure seeded state machine, and that is what buys daily challenges, replays,
verifiable scores and the simulation harness later.

**Never reproduce Tetris trade dress.** Colour by *cell count*, not shape
identity. No canonical tetromino colourway, no "-tris", and never `tetris` in
the keyword field. Spec §11. The palette lives in `lib/render/theme.dart` and
is keyed by size, so the canonical colourway is unreachable by construction.

---

## Name

**Blockascent: Block Puzzle** is provisional, pending a direct App Store and
Google Play title search plus a trademark check on `Blockascent` in the
games/software class. Three earlier candidates (Blocksmith, Blockforge,
Blockwright) were already taken. It is kept in one constants file
(`lib/render/theme.dart`) and out of the bundle identifier, which is
`com.evol.blockpuzzle` — an application id cannot be changed after the first
release without shipping a new app. Reasoning and the shortlist behind it:
`docs/03 §6`.
