# Project Status — Space Folding

**Last Updated:** 2026-08-05
**Current Phase:** Consolidated onto the gravity metroidvania direction. Playable
vertical slice: two regions, doors, real subspaces, fold/unfold with animation.
**Tests:** **243 passing** / 243 (0 failing, 0 risky), 14 scripts, ~3.0s.

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
| Tile registry (pins, unanchorable, water, triggers) | ✅ Wired, tested, **in the world** |
| Fold-on-enter triggers | ✅ Wired at world level, **in the world** |
| Occupant model (entities riding tiles) | ⚙️ Ported and tested, **not yet used in-world** |
| World authoring (`worlds/overworld.json`) | ⚙️ Format done; one hand-authored world |
| Unanchorable tiles (`_`, `X`) | ⚙️ Wired and tested, not yet placed in the world |
| Audio | ⚙️ `AudioManager` + `Settings` carried over; no assets |
| Save / progression | ❌ Not started |
| Entities (items, enemies, save points) | ❌ Not started |

---

## Test suite

243 passing across 14 scripts. Composition:

| Script | Tests | Covers |
|---|---:|---|
| `test_geometry_core` | 41 | Sutherland-Hodgman, epsilon, area/centroid |
| `test_audio_manager` | 30 | Bus routing, volume, playback |
| `test_fold_world` | 29 | **Scene-driven**: riding, pinch, subspaces, doors, pins, plates, camera |
| `test_world_data` | 19 | World format + the shipped world's content |
| `test_world_core` | 28 | Map parsing, seams, anchor/fold eligibility, camera framing |
| `test_tile_types` | 16 | The registry |
| `test_collision_core` | 13 | Polygon clipping under folds |
| `test_trigger_cascade` | 12 | Firing, idempotence, pin veto, cascade cap |
| `test_occupants` | 11 | Split-on-unfold, footprints, carried geometry |
| `test_folded_state` | 11 | Per-position stacks, dominant type |
| `test_fold_replay` | 11 | The derivation engine |
| `test_base_grid` | 9 | Immutable base model |
| `test_base_frame` | 9 | Base ↔ derived transport |
| `test_fold_unfold_inverse` | 4 | Unfold-as-drop-and-re-derive |

> The count fell from 525 because ~340 tests covered code the consolidation
> deleted. Kernel coverage is intact; every ported subsystem shipped with tests.

`test_fold_world` is the one that matters most for confidence: it drives the real
scene and exercises the beats end to end.

---

## Recent Changes

### 2026-08-05 — The camera frames the moment, not a fixed lens

- **Zoom is dynamic.** The frame rested at 1:1 — about twenty cells across — which
  read tight for a game whose subject is the shape of the space. It now rests at
  `WorldCore.ZOOM_RESTING` (0.80) and *opens* from there, never closes:
  - **speed** — running widens a little, falling hard widens a lot;
  - **the fold you are composing** — pin an anchor, walk away, and the view opens
    to keep it on screen; the span you can see IS the decision you are making;
  - **the band you are inside** — a subspace is framed glue to glue, so a wide
    strip reads as a cylinder rather than a corridor with no visible walls;
  - **a fold rearranging the world** — the transition steps the camera back.
- **`WorldCore.camera_zoom_for` is the pure decision** (a motion scalar, a widen
  scalar, and a focus set of points that must stay on screen); `FoldWorld` supplies
  the context, `PlayerBody` supplies motion from its own limits and eases the lens
  (much lazier than the follow — a frame that resizes as fast as it pans breathes).
  Hard relocations cut the zoom with the position.
- **Subspace wrap copies now derive from the widest frame** rather than a hardcoded
  1400px, so the repeating strip has no visible end when the lens opens.

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

1. **Finish putting the ported systems in the world.** `PIN` and `TRIGGER_FOLD` are
   now placed (east's right wing); `Occupants` and `UNANCHORABLE_*` still are not.
   Placing them is also how their design gets pressure-tested.
2. **Settle fold extent.** Infinite-crease is the biggest open question in the
   direction (see `AGENTS.md` §"Open design questions"). Barrier-scoped folds are
   the leading candidate.
3. **Save / checkpoints.** Undo is gone by design; respawn currently sends you to the
   region spawn. Real save points are the replacement.
4. **Entities.** `Occupants` is the model; nothing renders or moves one yet.
5. **Authoring tooling.** ASCII rows in JSON are workable but hand-editing region
   geometry will not scale. Revisit an editor once the tile vocabulary settles.

---

## Known issues

- The `topdown-archive` tag is **local only** — the remote refused the tag push
  (session credentials are scoped to the working branch). Use `git checkout 8bf8193`.
- No audio assets ship; `AudioManager` is wired but silent.
- Unanchorable tiles (`_`, `X`) and occupants are covered by tests but not placed in
  the world yet. Pins and triggers now are — see east's right wing.
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
