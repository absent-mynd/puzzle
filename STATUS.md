# Project Status — Space Folding

**Last Updated:** 2026-08-05
**Current Phase:** Consolidated onto the gravity metroidvania direction. Playable
vertical slice: two regions, doors, real subspaces, fold/unfold with animation,
and folding as a **finite carried resource**.
**Tests:** **254 passing** / 254 (0 failing, 0 risky), 15 scripts, ~4.7s.

---

## Where the project is

The long-running split between a top-down grid puzzler and a side-view gravity
metroidvania is **resolved in favour of gravity**. See `AGENTS.md` §"the
2026-08-04 consolidation" for what that removed and what it kept.

What exists and works today:

| Area | State |
|---|---|
| Fold kernel (derive/replay, arbitrary crease angles) | ✅ Solid, well covered |
| Base-frame transport (`BaseFrame`) | ✅ Solid, well covered |
| Side-view world: gravity, riding flaps, depenetration | ✅ Playable |
| Subspaces (fold interiors as real places) | ✅ Playable |
| Regions + doors (recursive partner resolution) | ✅ Playable |
| Tile registry (pins, unanchorable, water, triggers, caches) | ✅ Wired, tested, **in the world** |
| Fold-on-enter triggers | ✅ Wired at world level, **in the world** |
| Anchors as a conserved resource (`AnchorStock`) | ✅ Playable, **in the world** |
| Anchor caches (`A`) — the capacity upgrade | ✅ Three placed, ⚙️ untuned |
| One-key fold verb (tap = pin/commit, hold = pull back) | ✅ Playable |
| Occupant model (entities riding tiles) | ⚙️ Ported and tested, **not yet used in-world** |
| World authoring (`worlds/overworld.json`) | ⚙️ Format done; one hand-authored world |
| Unanchorable tiles (`_`, `X`) | ⚙️ Wired and tested, not yet placed in the world |
| Audio | ⚙️ `AudioManager` + `Settings` carried over; no assets |
| Save / progression | ❌ Not started |
| Entities (items, enemies, save points) | ❌ Not started |

---

## Test suite

254 passing across 15 scripts. Composition:

| Script | Tests | Covers |
|---|---:|---|
| `test_geometry_core` | 41 | Sutherland-Hodgman, epsilon, area/centroid |
| `test_fold_world` | 32 | **Scene-driven**: riding, pinch, subspaces, doors, pins, plates, the anchor economy |
| `test_audio_manager` | 30 | Bus routing, volume, playback |
| `test_world_data` | 22 | World format + the shipped world's content |
| `test_tile_types` | 20 | The registry |
| `test_world_core` | 19 | Map parsing, seams, anchor/fold eligibility |
| `test_collision_core` | 13 | Polygon clipping under folds |
| `test_trigger_cascade` | 12 | Firing, idempotence, pin veto, cascade cap |
| `test_occupants` | 11 | Split-on-unfold, footprints, carried geometry |
| `test_folded_state` | 11 | Per-position stacks, dominant type |
| `test_fold_replay` | 11 | The derivation engine |
| `test_anchor_stock` | 10 | Anchor conservation: pocket ↔ pending ↔ fold |
| `test_base_grid` | 9 | Immutable base model |
| `test_base_frame` | 9 | Base ↔ derived transport |
| `test_fold_unfold_inverse` | 4 | Unfold-as-drop-and-re-derive |

> The count fell from 525 because ~340 tests covered code the consolidation
> deleted. Kernel coverage is intact; every ported subsystem shipped with tests.

`test_fold_world` is the one that matters most for confidence: it drives the real
scene and exercises the beats end to end.

---

## Recent Changes

### 2026-08-05 — Anchors are a thing you carry, and one key spends them

Folding was free and unlimited. It is now paid for out of a countable, **conserved**
stock, and the whole verb collapsed onto one key.

- **New `AnchorStock`** (kernel): `free = capacity - held-by-live-folds - pinned`.
  Nothing is stored — `held` is summed from `Fold.held_anchors` across every live
  fold list, so **unfolding refunds by simply removing the fold**. Adding a "spent"
  counter would be a second source of truth; don't.
- **A standing fold holds two of your anchors.** The budget is how many folds may
  stand *at once*, not how many you may ever make. Crossing a pit still costs
  nothing permanent (fold, walk the seam, unfold behind you); what costs is a fold
  you must leave standing. Folds the *world* makes — authored pre-folds, trigger
  folds — hold zero and charge you nothing.
- **Charged at pin time**, so the count drops as you place and the commit moves the
  same two anchors into the fold without moving the total. An un-affordable or
  too-close anchor is refused *when placed*, because the next tap is the commit.
- **One key (F): tap pushes in, hold pulls back.** Tap pins anchor 1, then anchor 2,
  then commits. Hold retrieves your own anchor, unfolds the fold under a seam
  diamond, or exits a subspace by its glue diamond. `Q`/`E`/`Esc`/`U` are gone —
  and with `U` went the remote unfold, which had been a free escape valve.
- **New `ANCHOR_CACHE` tile (`A`)**, registry-driven (`grant: 2`). Three placed, each
  behind a beat rather than in front of one: the pillar top pays for the climb fold,
  the sealed chamber pays its way back out, and one sits **inside east's shipped
  pre-fold** — reachable only through door W1, because a cache folded away is not
  lost. Collected caches dim in place; collection is per-region runtime state.
- `WorldData.anchor_capacity` (4) authors the starting allowance. The old level-era
  "fold budget" this resembles was a per-level par; this one is carried and refunded.

### 2026-08-05 — The inside of a fold reads as one cylinder

- **The player is drawn in every visible copy of the strip.** `rebuild_sub` gives
  each wrap band a twin of the blob (`sub_player_ghosts`), updated with the body
  each frame. One lone body made the repeated strip read as separate worlds.
- **Crossing a glue line is seamless.** The wrap now displaces body *and* camera
  by the same band width (`PlayerBody.shift_camera`) instead of snapping the
  camera to the body — the snap threw away the smoothing lag (~40px at a full
  run) and jolted the view every crossing.
- `PlayerBody` owns its camera smoothing (Camera2D exposes no way to move its
  smoothed centre, only `reset_smoothing()`), and `FoldWorld` now runs its
  per-frame world logic *after* the body has moved (`process_physics_priority`).
- `WorldOverlay` grew `_copy_offsets()`; the aim ring and pending-anchor rings
  repeat with the copies like doors and seam diamonds already did.

### 2026-08-04 — Consolidation onto the gravity direction

- **Deleted** the top-down view/entity layer (`GridManager`, `Cell`, `CellPiece`,
  grid `Player`, `FoldController`, `InteractionController`, `MainScene`), the
  level-based meta layer (`GameManager`, `LevelManager`, `LevelValidator`,
  `ProgressManager`, `LevelEditor`, `LevelData`, level-select/complete/HUD UI,
  `MainMenu`), the step-log undo (`HistoryManager`, `FoldStep`, `StepReplay`), and
  the 10-level campaign + 10 custom levels.
- **Promoted** `scripts/prototype/` → `scripts/world/`; `Proto*` →
  `FoldWorld` / `WorldCore` / `PlayerBody` / `WorldOverlay`.
  `scenes/world/World.tscn` is the main scene.
- **New `BaseFrame`** (kernel): exact base ↔ derived point transport, lifted out of
  the view layer so pure derivation can use it without a model→view cycle.
- **New `Occupants`** (from `StepReplay`): tile-riding entities with split-on-unfold
  latents. The player no longer uses it — a continuous body has no ridden tile.
- **`TileTypes` wired into the world**: solidity, anchor eligibility
  (`UNANCHORABLE_*`) and fold-proof tiles (`PIN`) are registry-driven; the fold and
  collision paths no longer switch on type ints.
- **`TriggerResolver` reworked** to run against a fragment list and a continuous
  player position. Determinism, channel idempotence, the fire-once guard and the
  cascade cap all carry over.
- **New `WorldData`** (from `LevelData`): regions of ASCII terrain, doors, and
  pre-placed folds per region. The world boots from `worlds/overworld.json`; region
  shapes are byte-identical to the previously hardcoded maps.
- **`PauseMenu`** rebuilt as an in-world overlay (resume / respawn / settings / quit).

### Earlier

The fold kernel (derive/replay engine, diagonal folds, multi-piece fragments) and the
gravity prototype it drives were built between 2025-11 and 2026-07. See
`git log` and the `topdown-archive` tag (`8bf8193`) for that history.

---

## Next up

Roughly in priority order — nothing here is committed to yet:

1. **Playtest the anchor economy.** The allowance (4) and cache grant (2) are first
   guesses, and west's beats were authored when folding was free. The question to
   answer by feel: does scarcity make the world read as *considered*, or merely
   fussy? Tuning is a playtesting job, not an editing one.
2. **Finish putting the ported systems in the world.** `PIN` and `TRIGGER_FOLD` are
   now placed (east's right wing); `Occupants` and `UNANCHORABLE_*` still are not.
   Placing them is also how their design gets pressure-tested.
3. **Settle fold extent.** Infinite-crease is the biggest open question in the
   direction (see `AGENTS.md` §"Open design questions"). Barrier-scoped folds are
   the leading candidate.
4. **Save / checkpoints.** Undo is gone by design; respawn currently sends you to the
   region spawn. Real save points are the replacement — and they are now also what
   collected caches need to outlive a session, and the answer to stranding yourself
   with no anchors and no reachable seam.
5. **Entities.** `Occupants` is the model; nothing renders or moves one yet.
6. **Authoring tooling.** ASCII rows in JSON are workable but hand-editing region
   geometry will not scale. Revisit an editor once the tile vocabulary settles.

---

## Known issues

- The `topdown-archive` tag is **local only** — the remote refused the tag push
  (session credentials are scoped to the working branch). Use `git checkout 8bf8193`.
- No audio assets ship; `AudioManager` is wired but silent.
- Unanchorable tiles (`_`, `X`) and occupants are covered by tests but not placed in
  the world yet. Pins and triggers now are — see east's right wing.
- **You can strand yourself.** Spend your last anchors on a fold, walk somewhere its
  seam cannot be reached from, and `R` is the only way back. Accepted cost of having
  no remote unfold; save points are the real fix.
- Collected anchor caches are runtime-only state (`regions[id].collected`) and reset
  with `R` — the first piece of world state that is not `(base, folds)`.
- The pin/trigger wing lives in **east**, not west, and is reached through a door.
  West's four authored beats depend on its exact geometry and infinite creases make
  a pin a global veto on a band of folds, so nothing was placed there without
  playtesting. See the note in `scripts/world/README.md`.

---

## For detailed information

- [AGENTS.md](AGENTS.md) — start here: architecture, layering, critical decisions
- [scripts/world/README.md](scripts/world/README.md) — controls and design beats
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design decisions & rationale
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — workflow, testing, pitfalls
- [docs/REFERENCE.md](docs/REFERENCE.md) — code map
