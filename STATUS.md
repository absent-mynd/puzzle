# Project Status — Space Folding

**Last Updated:** 2026-08-05
**Current Phase:** Consolidated onto the gravity metroidvania direction. Playable
vertical slice: two regions, doors, real subspaces, fold/unfold with animation —
now rendered as pixel art with fold-aware dynamic lighting.
**Tests:** **280 passing** / 280 (0 failing, 0 risky), 17 scripts, ~3.7s.

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
| Pixel-art render pass (low-res target, 16px tileset, UVs) | ✅ In the world |
| Dynamic lights as fold-aware occupants | ✅ In the world, 5 placed |
| Hand-drawn tilesheet | ⚙️ Layout + drop-in path done; sheet is generated in code |
| Audio | ⚙️ `AudioManager` + `Settings` carried over; no assets |
| Save / progression | ❌ Not started |
| Entities (items, enemies, save points) | ❌ Not started |

---

## Test suite

280 passing across 17 scripts. Composition:

| Script | Tests | Covers |
|---|---:|---|
| `test_geometry_core` | 41 | Sutherland-Hodgman, epsilon, area/centroid |
| `test_audio_manager` | 30 | Bus routing, volume, playback |
| `test_fold_world` | 29 | **Scene-driven**: riding, pinch, subspaces, doors, pins, plates, lights |
| `test_world_data` | 25 | World format + the shipped world's content, incl. lights |
| `test_world_core` | 19 | Map parsing, seams, anchor/fold eligibility |
| `test_tile_atlas` | 17 | Tileset kinds/variants, base-space UVs, the generated sheet |
| `test_tile_types` | 16 | The registry |
| `test_light_source` | 15 | Lights as occupants: fold-away, ride, split, serialization |
| `test_collision_core` | 13 | Polygon clipping under folds |
| `test_trigger_cascade` | 12 | Firing, idempotence, pin veto, cascade cap |
| `test_occupants` | 11 | Split-on-unfold, footprints, carried geometry |
| `test_folded_state` | 11 | Per-position stacks, dominant type |
| `test_fold_replay` | 11 | The derivation engine |
| `test_base_grid` | 9 | Immutable base model |
| `test_base_frame` | 9 | Base ↔ derived transport |
| `test_pixel_art` | 8 | The art-pixel quantum and the camera that preserves the view |
| `test_fold_unfold_inverse` | 4 | Unfold-as-drop-and-re-derive |

> The consolidation dropped the count from 525 to 226 because ~340 tests covered
> code it deleted. Kernel coverage is intact; every ported subsystem — and every
> subsystem added since — shipped with tests.

`test_fold_world` is the one that matters most for confidence: it drives the real
scene and exercises the beats end to end.

---

## Recent Changes

### 2026-08-05 — Pixel art + dynamic lighting

- **Pixel render pass.** The world draws into a 320x180 `SubViewport` scaled up 4x
  with nearest filtering; the camera zooms out by the same factor, so one art pixel
  is 4 world units and *exactly as much world is on screen as before*. No physics
  constant, cell size or coordinate changed. `PixelArt` is the one place that says
  how big an art pixel is. The HUD stays outside the pixel viewport at window
  resolution.
- **A real tileset** (`TileAtlas`): 16px tiles, one row per kind, one column per
  variant, generated procedurally so it ships as readable code and headless tests
  never touch the import pipeline. Drop a sheet at `assets/sprites/tiles.png` and it
  is used instead — see `assets/sprites/README.md`.
- **Base-space UVs.** Fold fragments are arbitrary polygons, so tiles cannot be
  blitted on a grid. `TileAtlas.uv_for` sends each vertex back through `src_offset`
  to its base tile, so a fragment carries the patch of art it was cut from and the
  crease cuts the art exactly as it cuts the geometry. **The seam stays a hard
  line** — deliberately, for now.
- **Lights are occupants** (`LightSource`, kernel): a base identity plus a point in
  the tile, resolved through `BaseFrame` against whatever configuration is on
  screen. Fold a lamp away and it leaves the overworld and lights that fold's
  *interior*; fold something else and it rides the flap. Nothing special-cases
  this — it is the door machinery applied to light. Five lamps placed in the
  shipped world, including one sealed inside east's pre-placed fold.
- **Pixel-level lighting** (`assets/shaders/pixel_lit.gdshader`, `LightRig`):
  shaded point and light position are snapped to the art-pixel grid, intensity is
  quantized into bands, and band edges are ordered-dithered with a 4x4 Bayer
  threshold — light arrives in chunky rings, not a smooth glow. Ambient is
  deliberately generous: **lighting is style, not fog of war**, and the player and
  overlay markers are drawn unlit so they never vanish into a dark corner.
- Foreground and background answer light differently (the registry's walkability
  picks which), which is the only depth cue the flat world has.

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

0. **Draw the tileset by hand.** The generated sheet is real but plain; the layout
   and drop-in path are done, so this is now an art job, not an engineering one.
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
- Lights do not cast shadows: they pass through walls. Occluders would have to be
  re-derived per fold and would want to soften the seam, which the art is currently
  committed to keeping hard.
- The tilesheet is generated in code, so the world looks systematic rather than
  authored. The layout is fixed and a drawn sheet drops in without code changes.
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
