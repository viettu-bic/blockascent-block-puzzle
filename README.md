# Blockascent: Block Puzzle

A no-gravity polyomino placement puzzle wrapped in a roguelite campaign.
**Flutter / Dart, iOS and Android, portrait.**

Pieces are **placed**, never dropped. Full **rows and columns both clear**, and
clearing is the **only** way to score — placing a block pays nothing until you
buy or draft the income for its size band. A combo multiplier is the real
resource. A run is a ladder of **12 stages**, each
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

- **The curve has been wrong twice, and both times reading it was not enough.**
  `300 × 1.45` killed 100% of simulated runs on stage 1. Its replacement,
  `100 × 1.25`, was measured — but against a player with no draft and no shop,
  and once those existed it let an 85%-unlock account win 90% of its runs and a
  0%-unlock account win the campaign outright. The live value is **`100 × 1.43`**,
  reached in six measured steps (`test/sim/gates_sim_test.dart`, `docs/06 §3a`).
  Each step paid for something: the draft existing, a wider free roster, and a
  draft policy that finally ranked cards by *measured* worth rather than by
  guesses. Equipment raises the floor and only a steeper curve keeps the ceiling
  out of reach, so the two always move together.
- **Payout keys off stages cleared, never score.** Keying it to score creates an
  inflation spiral: buy a value upgrade → score rises → earn more → buy more,
  and because stage targets are fixed, the ladder also gets easier. See
  `docs/04 §1`.
- **Shape unlocks never dilute the draw bag.** You own shapes and pick 8 per
  run. The original design this is based on added every unlock to the bag, so
  buying more could leave you worse off. See `docs/01 §5`.
- **Clearing lines is the only way to score.** Placing a block paid 44% of a
  stage's points for putting a shape down; `cellValueFor` starts at zero now
  and placement income is bought or drafted band by band. The shop has two
  phases as a result — early purchases buy survival, late ones buy income. See
  `docs/05 §10`, which also records the version of this that handed one card
  a measured +125% and therefore the whole run.
- **The jam is the early wall; the shop is the way out.** Nothing under three
  cells is free, so a first run clogs. Buying `1×2` takes the jam share from
  58% to 20%, `1×3` and `1×4` to 7%, a full account to 0%. See `docs/04 §9` —
  which also lists the six design rules that were deleted to get here, and the
  three that stayed.
- **The small precise blocks are the expensive ones.** Pricing used to run
  size-ascending — the 1×1 free, the big blocks costing 12,700 of 13,730
  spools — and measured, that gave away the useful pieces and sold the ones
  nobody fields: **jams were 0% of deaths** at every unlock level, and a
  100%-unlock loadout contained nothing above tier 2. The 1×1 is now the single
  most expensive purchase in the game. See `docs/04 §8`.
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
docs/09-theme-market-research.md which theme sells, and what it costs
docs/10-core-gameplay-market-research.md  the competitive set, feature by feature
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

```
lib/ui/how_to_play_screen.dart   the FTUE — four rules, shown once on first launch
lib/ui/loadout_screen.dart       LoadoutPicker, a section of the shop
lib/platform/sfx.dart            sound, four voices, fire-and-forget
lib/platform/music.dart          two loops, switched at screen transitions
lib/ui/audio_settings.dart       the three toggles, shared by menu and in-run
tool/make_sfx.py                 generates assets/sfx/*.wav — stdlib Python
tool/make_music.py               generates assets/music/*.wav — same
assets/sfx/                      ten sounds, 157 KB
assets/music/                    two loops, 2.4 MB
```

**All the audio is synthesised, not sourced.** Two scripts in `tool/` build the
ten effects and both music loops from sine partials and seeded noise with the
Python standard library, so there is no attribution, no licence file and no
provenance question — and a regenerate is byte-identical.

**Everything is in C**, and that part was forced: the effects are C major
pentatonic, a line clear is the most frequent sound in the game, and in any
other key the player would hear a clash every time they scored. The music is
calm and hookless by the same brief that set the visuals — *"no timer means no
urgency audio"* (`docs/01 §7`). Icons are Material Symbols, bundled and
Apache-2.0. See `docs/07 §4f` and `§4g`.

`.claude/skills/puzzle-roguelite-design/` carries the design method and the
invariants — the evidence standard, the one relationship every card's value hangs
on, and the verification recipes — so a design change does not have to start by
re-reading 2,400 lines of `docs/`. Read it before proposing any tuning number.

`reference/` is **not** code to ship. It is a working implementation of the
rules engine with a full test suite, kept so the Dart port has something to be
verified against rather than merely reviewed.

---

## The three gates

**Port parity — passed.** `test/sim/curve_sim_test.dart` reproduces the
TypeScript histogram from the same seeds: median stage 6, median run total
1,118, 124 median placements, 0% jam deaths. A silent RNG or rounding
difference changes the game and nobody notices for a month, so those numbers
are pinned as assertions. It pins the tuning values the oracle played — growth
1.25, patience 2 — rather than reading the live ones, because parity is a
question about the **engine**. Reading the live numbers made it report an
engine fault the first time the curve was re-tuned.

**The unlock gates — passed.** `test/sim/gates_sim_test.dart` drives the real
run controller with a greedy placement player, a draft policy and an account
built from the real prices, then asks the question the design turns on:

| Unlocked | Median death | **Jam share of deaths** | Wins | |
|---|---|---|---|---|
| 0% | 8 | **43%** | **0%** | unwinnable, and jam-led ✓ |
| 85% | 10 | 0% | 12% | winnable with a good run ✓ |
| 100% | 12 | 0% | **87%** | reliable ✓ |

**All three hold.** Progression is read on the jam share rather than on depth:
a first run gets stuck 58% of the time, a full account never does. That is a
number a player can feel, and the shop's job is to sell them out of it.

Two of three hold, and the meta is worth +4 stages of median depth, which is the
budget `docs/04` has asked for and never met. The third is open with a measured
cause: Standard Yarn and Selvage each measure 48% as *initial* cards, so a
player who owns nothing gets most of the way to a full account and the shop has
little left to sell.

It has also caught itself out twice, which is worth knowing before trusting it.
It derived an account's milestones from its purchase count and reported a
+6-stage step in the shop's first four purchases that was really the Patience
card unlocking — **pin every progression axis you are not varying**. And its
draft policy ranks by `gain`, a field that was pure estimate, so pick rates once
"proved" five starter cards dead when three of them were fine — **an instrument
that trusts bad numbers measures the numbers.**

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
