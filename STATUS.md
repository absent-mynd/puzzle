# Project Status — Space Folding

**Last Updated:** 2026-08-05
**Current Phase:** Consolidated onto the gravity metroidvania direction. Playable
vertical slice: two regions, doors, real subspaces, fold/unfold with animation,
folding as a **finite carried resource** — rendered as pixel art with fold-aware
dynamic lighting, framed by a camera that zooms and leads with the moment.
**Tests:** **360 passing** / 360 (0 failing, 0 risky), 19 scripts, ~8s.

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
| Pixel-art render pass (low-res target, 16px tileset, UVs) | ✅ In the world |
| Dynamic lights as fold-aware occupants | ✅ In the world, 5 placed |
| Hand-drawn tilesheet | ⚙️ Layout + drop-in path done; sheet is generated in code |
| Audio | ⚙️ `AudioManager` + `Settings` carried over; no assets |
| Save / progression | ❌ Not started |
| Entities (items, enemies, save points) | ❌ Not started |

---

## Test suite

360 passing across 19 scripts. Composition:

| Script | Tests | Covers |
|---|---:|---|
| `test_fold_world` | 59 | **Scene-driven**: riding, pinch, subspaces, doors, pins, plates, lights, camera, the anchor economy |
| `test_geometry_core` | 41 | Sutherland-Hodgman, epsilon, area/centroid |
| `test_world_core` | 36 | Map parsing, seams, anchor/fold eligibility, camera framing + lookahead |
| `test_audio_manager` | 30 | Bus routing, volume, playback |
| `test_world_data` | 28 | World format + the shipped world's content, incl. lights and caches |
| `test_tile_types` | 20 | The registry |
| `test_tile_atlas` | 17 | Tileset kinds/variants, base-space UVs, the generated sheet |
| `test_light_source` | 15 | Lights as occupants: fold-away, ride, split, serialization |
| `test_pixel_art` | 14 | The art-pixel quantum; the target that resizes so zoom stays crisp |
| `test_collision_core` | 13 | Polygon clipping under folds |
| `test_trigger_cascade` | 12 | Firing, idempotence, pin veto, cascade cap |
| `test_occupants` | 11 | Split-on-unfold, footprints, carried geometry |
| `test_folded_state` | 11 | Per-position stacks, dominant type |
| `test_fold_replay` | 11 | The derivation engine |
| `test_anchor_stock` | 10 | Anchor conservation: pocket ↔ pending ↔ fold |
| `test_player_body` | 10 | Look/point keys, velocity-as-fraction, motion scalar |
| `test_base_grid` | 9 | Immutable base model |
| `test_base_frame` | 9 | Base ↔ derived transport |
| `test_fold_unfold_inverse` | 4 | Unfold-as-drop-and-re-derive |

> The consolidation dropped the count from 525 to 226 because ~340 tests covered
> code it deleted. Kernel coverage is intact; every ported subsystem — and every
> subsystem added since — shipped with tests.

`test_fold_world` is the one that matters most for confidence: it drives the real
scene and exercises the beats end to end.

---

## Recent Changes

### 2026-08-05 — Reset stops confiscating your caches; the HUD stops lecturing

- **`R` keeps what you found.** Collected caches were per-region state inside
  `regions`, so `_setup_all` wiped them on every reset — and reset is the only way
  out of stranding yourself with no anchors and no reachable seam. Using the escape
  hatch cost you your progression. Caches now live in `FoldWorld.collected_caches`
  (region id -> {base_id: grant}), **outside** `regions` precisely so the rebuild
  cannot reach them. Folds still reset, which is what makes `R` a real remedy: with
  no fold standing, every anchor is back in hand.
- **The on-screen help is one line of controls.** It was nine lines that explained
  the fold verb, the economy, the caches and the doors — teaching, in text, over the
  top of a game whose aim ring, preview band, seam diamonds and anchor readout
  already say those things in place. Flash messages lost their instructional tails
  too ("Folded IN. F at the seam anchor (white diamond) unfolds it." → "Folded in.").

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
- Integrated with the pixel pass: `ANCHOR_CACHE` is a tileset row (`TileAtlas.K_CACHE`,
  a pair of upright pegs — two is what it grants and what a fold costs), and a spent
  cache is the same tile modulated dark rather than a different one.

### 2026-08-05 — Pixel art meets the dynamic camera

The pixel pass and the dynamic camera were built in parallel and are, on their
face, incompatible: the pass wanted the lens pinned at 1/4 so a 64-unit cell
covers exactly 16 art pixels, and the camera wanted to open from 0.80 to 0.55.

- **Resolved by resizing the render target instead of moving the lens.** Inside a
  render target the size of an art pixel is purely a function of camera zoom — so
  the lens now *never* moves (`PixelArt.CAMERA_ZOOM`), and "show more world" is
  answered with more pixels: `PixelArt.target_size` gives the resolution a given
  logical zoom needs and `FoldWorld._size_pixel_view` applies it as the zoom eases.
  World-per-art-pixel holds at 4.0 across the whole zoom range, so the tileset is
  never resampled.
- `PlayerBody.zoom_target` / `camera_zoom()` are therefore **logical** zoom: they
  size the buffer. The pixel snap moved into `_cam.offset`, leaving
  `global_position` the unsnapped truth — quantizing the smoothing state itself
  would let a slow pan stall inside a pixel.
- Verified in the real scene: opening the frame from 0.80 to 0.55 grows the target
  400x225 → 582x327 with the lens fixed at 0.250 and a cell steady at ~16 art px.

### 2026-08-05 — Pixel art + dynamic lighting

- **Pixel render pass.** The world draws into a low-resolution `SubViewport` scaled
  up with nearest filtering; one art pixel is 4 world units and a cell is 16 art
  pixels. No physics constant, cell size or coordinate changed. `PixelArt` is the
  one place that says how big an art pixel is. The HUD stays outside the pixel
  viewport at window resolution. (The target is sized from the camera's logical
  zoom — see the entry above.)
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

### 2026-08-05 — The frame leads where you are going

- **Camera lookahead.** Zoom decides how *much* to show; lookahead decides *where
  to centre it*. The body sat dead centre, which spent half the frame on ground
  already crossed. The view now leads:
  - **speed** — the lead is a fraction of the body's own limits, so it saturates
    at a full run rather than tracking velocity forever;
  - **falling much harder than rising** — a fall is committed and its landing is
    what you need to see; the top of a jump is about to reverse, and leading hard
    there would swing the frame back a moment later;
  - **held look keys** — the same W/S that aim an anchor lean the frame, so
    pressing up to point up shows you what you are pointing at;
  - **flat along a folded band** — inside a fold the strip repeats along the
    crease normal, so a lead that way slides the view across identical copies.
- **`WorldCore.camera_lookahead_for` is the pure decision**; `PlayerBody` supplies
  `motion_fraction` (velocity as a signed fraction of *its own* run / fall / jump
  limits) and `look_dir`, and eases the lead even more lazily than the zoom —
  the lead flips sign when you turn around, and eased that reads as the view
  swinging round rather than whipping across the body. Capped at 6 cells; hard
  relocations cut it along with the lens.
- **Ordering matters and is now load-bearing**: the lead is computed *before* the
  zoom, because the lead moves the camera and the zoom's focus distances are
  measured from where the camera ends up. Reversed, a hard lead would quietly
  crop the very things the focus set exists to keep on screen.
- **Fixed: stacked seam diamonds offered you the fold you could not unfold.**
  Two folds can meet in the same cell; `aimed_fold` took the first in fold order,
  which is exactly the one the newer fold blocks — so F on the diamond only ever
  reported the refusal. It now searches newest-first and prefers a fold that can
  actually come out. The overlay draws one diamond per meeting *cell*
  (`FoldWorld.seam_markers`) so the colour cannot promise what the act refuses.

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

1. **Playtest the anchor economy.** The allowance (4) and cache grant (2) are first
   guesses, and west's beats were authored when folding was free. The question to
   answer by feel: does scarcity make the world read as *considered*, or merely
   fussy? Tuning is a playtesting job, not an editing one.
2. **Draw the tileset by hand.** The generated sheet is real but plain; the layout
   and drop-in path are done, so this is now an art job, not an engineering one.
3. **Finish putting the ported systems in the world.** `PIN` and `TRIGGER_FOLD` are
   now placed (east's right wing); `Occupants` and `UNANCHORABLE_*` still are not.
   Placing them is also how their design gets pressure-tested.
4. **Settle fold extent.** Infinite-crease is the biggest open question in the
   direction (see `AGENTS.md` §"Open design questions"). Barrier-scoped folds are
   the leading candidate.
5. **Save / checkpoints.** Undo is gone by design; respawn currently sends you to the
   region spawn. Real save points are the replacement — and they are now also what
   collected caches need to outlive a session, and the answer to stranding yourself
   with no anchors and no reachable seam.
6. **Entities.** `Occupants` is the model; nothing renders or moves one yet.
7. **Authoring tooling.** ASCII rows in JSON are workable but hand-editing region
   geometry will not scale. Revisit an editor once the tile vocabulary settles.

---

## Known issues

- The `topdown-archive` tag is **local only** — the remote refused the tag push
  (session credentials are scoped to the working branch). Use `git checkout 8bf8193`.
- No audio assets ship; `AudioManager` is wired but silent.
- Unanchorable tiles (`_`, `X`) and occupants are covered by tests but not placed in
  the world yet. Pins and triggers now are — see east's right wing.
- **You can strand yourself.** Spend your last anchors on a fold, walk somewhere its
  seam cannot be reached from, and `R` is the only way back. `R` is survivable by
  design — it refunds every anchor and keeps your caches — but it still costs your
  position and fold configuration. Save points are the real fix.
- Collected anchor caches are runtime-only state (`FoldWorld.collected_caches`) — the
  first thing that is not `(base, folds)`. They survive `R` but not the session; a save
  system is what they need next.
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
