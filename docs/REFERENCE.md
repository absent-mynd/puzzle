# Code Map (Source Pointer Reference)

**Purpose:** point you to the *right source file* for any subsystem. The source is
the authoritative API — this doc deliberately does **not** restate function
signatures, because a hand-maintained API list drifts out of sync with the code
(this file used to do that, and it went badly stale).

> **Finding things fast**
> - Every public type has a `class_name`, so grep for it: `grep -rn "class_name BaseFrame" scripts/`
> - List a file's public API: `grep -nE "^(func|var|const|signal|class_name) " scripts/<file>.gd`
> - To learn *behavior*, read the test: `scripts/tests/test_<subject>.gd`

---

## Layering

```
scripts/model/  +  scripts/utils/     ← kernel: pure, headless, no scene tree
        ▲
scripts/world/                        ← the game: view, physics, input
scripts/ui/  scripts/systems/         ← menus, audio
```

The kernel must never reference `scripts/world/`. See `AGENTS.md` §Layers.

---

## Kernel — `scripts/model/`

| Concern | File |
|---|---|
| **The current space**: what space the player is in — its pieces, collision geometry, how it repeats, how far the one non-repeating axis runs. The value that lets a collaborator be handed "where you are" instead of the whole world | `Space.gd` |
| Pure world logic: ASCII map parsing, side-of-fold for a free point, strip capture, seam/glue segments, carrying a point or line through a later fold, circle-vs-polygon depenetration, anchor reach & fold eligibility, camera framing + lookahead | `WorldCore.gd` |
| Immutable base grid: `BaseTile` per position, grid metrics, `from_types()` constructor, unit squares | `BaseGrid.gd` |
| One base tile: stable `base_id`, `grid_position`, `type`, per-instance `data` | `BaseTile.gd` |
| One fold: anchors, crease points/normal, `shift_a/b` in grid and px, `channel`, `held_hands`, and the world's `bolts` it will put back | `Fold.gd` |
| **The derivation engine.** `derive()`, `derive_pieces()`, `apply_one_fold()` — replays a fold list over the base grid | `FoldReplay.gd` |
| A derived piece: `base_id`, `type`, `polygon`, `plane_pos`, **`src_offset`** | `FoldedPiece.gd` |
| Queryable derived state: per-position stacks, `dominant_type_at`, `pieces_of_base` | `FoldedState.gd` |
| **Base ↔ derived point transport.** `transport()`, `world_point_from_base()`, `resolve_base_point()`, `piece_at()` | `BaseFrame.gd` |
| **The tile registry.** walkable / merge_rank / blocks_fold / blocks_anchor / on_enter / on_weight / swim | `TileTypes.gd` |
| **Which weight plates are down**, and so which channels they keep live. Asked in base ids, every frame, nothing stored | `Weights.gd` |
| **The hand registry.** One entry per kind: colour, fuse, authoring key. `fuse_for()` mixes a pair | `HandTypes.gd` |
| A hand lying in the world: base identity + point in tile, `dropped_at()`, `resolve_all()`. One object for authored loose hands and hands a burst popped out | `HandPickup.gd` |
| **The hand ledger.** `SLOTS`, `free_slots()`, `first_empty()`, `held_in()`, `total()` — conservation across slots / pinned / folds / ground, nothing stored | `HandStock.gd` |
| Entities that ride base tiles: split-on-unfold latents, carried geometry, footprints | `Occupants.gd` |
| One anchor: a base identity, the kind of hand in it, what arms it and whether a burst may take it back | `Anchor.gd` |
| **Which two anchors are about to fold together**, and their fuses. The pairing rule, derived per frame — and which channels are live: latched (stored) or weighted (handed in) | `AnchorField.gd` |
| Authored world: regions (ASCII rows), doors, pre-placed folds, lights, `starting_hands`; JSON round trip | `WorldData.gd` |
| A light as an occupant: base identity + point in tile, resolved per configuration | `LightSource.gd` |

## Kernel — `scripts/utils/`

| Concern | File |
|---|---|
| Polygon clipping under a fold (`fold_polygons`), shifts, unions, footprint tests | `CollisionCore.gd` |
| Sutherland-Hodgman split, point/line side, intersections, area/centroid. **`const EPSILON = 0.0001` lives here.** | `GeometryCore.gd` |
| JSON/dir helpers | `FileUtils.gd` |

---

## The game — `scripts/world/`

| Concern | File |
|---|---|
| **Everything that makes it a game**: regions, the context stack (subspaces), doors, the one-key tap/burst verb, the placement cursor and its stopped clock, the hand ledger, the auto-commit fuse, loose hands, weight plates and what the world gets back, sigils, the room reset, fold/unfold flow, animation, camera, HUD | `FoldWorld.gd` |
| **The window-resolution overlay**: background, controls line, status readout, the centre flash and its lifetime. Told what to say; holds no reference back | `WorldHud.gd` |
| **What the camera should be showing**: the lead, the lens, and the render-target size that stands in for zoom. Takes the world's facts as a context dictionary | `WorldCamera.gd` |
| **Hands in the air**: the flight, the wrap, the turn-back at a strip's end. Emits `landed` / `lost`; a hand at rest is an occupant and belongs to `FoldWorld` | `HandField.gd` |
| Player physics body: coyote time, jump buffer, the swim, squash; owns the pixel-snapped camera (follow + zoom + lookahead easing, all held still by `camera_held`); wears the loading burst as a colour (`charge_color`) | `PlayerBody.gd` |
| Anchors, fold preview strip, the placement cursor and its reach, seam lines and their diamonds, glue lines, the fuse pulse, loose hands, the burst ring | `WorldOverlay.gd` |
| The hands that float beside the player, and `draw_hand` — the ONE place a hand is drawn | `HandOrbit.gd` |
| **How big an art pixel is.** `WORLD_PER_PIXEL`, `TILE_PX`, `VIEW_PX`, `target_size`, snapping, and `hairline_runs` — a one-pixel line stepped into pixels rather than drawn as a quad | `PixelArt.gd` |
| **The tileset.** Kinds, variants, and base-space UVs for cut pieces | `TileAtlas.gd` |
| Lit materials, per-frame light uniforms, lamp glyphs | `LightRig.gd` |
| **What time it is for things in the world.** Stops when the world does; everything that drifts, throbs or flickers reads it | `WorldClock.gd` |
| Controls and the design beats | `README.md` |

`FoldWorld.gd` is the largest file and the one to read first if you want to
understand how the pieces meet. Its header comment is the map.

### Where to look for a specific behavior

| "How does…" | Start at |
|---|---|
| …a fold get committed? | `FoldWorld.do_fold()` / `do_sub_fold()` |
| …the player ride a flap? | `do_fold()` → `BaseFrame.world_point_from_base` → `WorldCore.depenetrate` |
| …getting pinched into a fold work? | `do_fold()`, the `dest == null` branch |
| …a subspace get derived? | `FoldWorld._compute_space()` / `_apply_context()` |
| …unfold blocking work? | `FoldWorld.can_unfold_fold()`, `WorldCore.segment_intersects_strip` |
| …exiting a subspace work? | `FoldWorld.try_exit()`, `exit_blocker()` |
| …a door find its partner? | `FoldWorld._check_doors()`, `BaseFrame.resolve_base_point` |
| …a tile react to being stood on? | `FoldWorld._check_triggers()` — dispatches on `TileTypes.on_enter_kind` |
| …a fold trigger fire? | `FoldWorld._fire_fold_trigger()` → `_plant_pair` → the ordinary fuse |
| …a burst plate fire? | `FoldWorld._fire_burst_plate()` → `FoldWorld._burst()` — the same one your release fires |
| …a weight plate keep a fold standing? | `FoldWorld._tick_plates()` → `Weights.channel_states` → `AnchorField.weigh_channel`; the fold itself is the ordinary fuse |
| …a plate's fold let go? | `FoldWorld._tick_plates()` → `unfold_space_fold(fold, true)` — newest-first, quietly |
| …the world get its bolts back? | `FoldWorld._give_back_to_world()` — and why that cannot refold forever |
| …a hand become a weight? | `FoldWorld.place_hand()` — `Anchor.NEVER` on a tile `TileTypes.is_weighable` |
| …the body know it is in water? | `FoldWorld._physics_process` sets `PlayerBody.in_water`; the swim is `PlayerBody.swim_step` |
| …a sigil get found? | `FoldWorld._check_goal()` — and `found_sigil_polys()` for the dimming |
| …`R` put a room back? | `FoldWorld._reset_region()` → `_build_region()` — a rebuild and a refund, no snapshot |
| …a fall know where to put you? | `FoldWorld._respawn_point()` — the door you came in by |
| …I know a shipped room can be done? | `scripts/tests/test_overworld_solutions.gd`, on `scripts/tests/support/world_probe.gd` |
| …a tile get its art? | `FoldWorld._make_tile()` → `TileAtlas.uv_for` |
| …the editor play the world it is editing? | `WorldEditor.playtest()` → `Shell._on_play_requested` → `FoldWorld.data_override` |
| …a playtest drop you where you were looking? | `FoldWorld._apply_spawn_override()` |
| …Escape get you back to what you came from? | `Shell.close_top()` — the stack IS the return path |
| …a light know where it is? | `FoldWorld.lights_here()` → `LightSource.position_in` |
| …lighting stay pixelly? | `assets/shaders/pixel_lit.gdshader` (snap, quantize, dither) |
| …the camera decide how far to zoom? | `FoldWorld._update_camera()` / `_camera_focus()` → `WorldCore.camera_zoom_for` |
| …the camera decide where to look ahead? | `FoldWorld._update_camera()` → `WorldCore.camera_lookahead_for` (+ `PlayerBody.motion_fraction` / `look_dir`) |
| …zoom stay compatible with pixel art? | `PixelArt.target_size` → `FoldWorld._size_pixel_view()` — the target resizes, the lens never moves |
| …F pick which fold to unfold? | `FoldWorld.aimed_fold()` — newest-first, prefers one that can actually come out |
| …a hand get placed? | `FoldWorld.begin_aim()` / `move_aim()` / `finish_aim()` → `place_hand(cell)` |
| …time stop while you aim? | `FoldWorld.placing()` — `_physics_process` returns early and the body is `frozen` |
| …the cursor know how far it may go? | `WorldCore.within_arm_reach` / `clamp_to_arm_reach`, radius `FoldWorld.ARM_REACH` |
| …everything in the world stop animating at once? | `WorldClock` — `FoldWorld._process` stops advancing it |
| …the screen say the world is held? | `assets/shaders/held.gdshader`, eased by `FoldWorld._tick_held_look` |
| …the held look know where to stay clear? | `FoldWorld._body_in_target_px()` → the shader's `clear_at` / `clear_radius` |
| …the camera stop while you aim? | `PlayerBody.camera_held`, set each frame by `FoldWorld._process` |

---

## Systems & UI

| Concern | File |
|---|---|
| **The sound vocabulary + the mix** (one file per sound) | `scripts/systems/Sounds.gd` |
| Audio buses, SFX/music playback, volume persistence | `scripts/systems/AudioManager.gd` (autoload) |
| Generating the shipped audio assets | `tools/gen_audio.py` |
| **The screen stack**: what is running, what it suspended to run it, and how a run or an editor is built | `scripts/ui/Shell.gd` |
| **The world select**: what is in `worlds/`, and playing or editing one | `scripts/ui/Launcher.gd` |
| In-world pause: resume / respawn / settings / quit (**not yet reachable**) | `scripts/ui/PauseMenu.gd` |
| Audio & display settings | `scripts/ui/Settings.gd` |

---

## Data

| Concern | Path |
|---|---|
| The authored world | `worlds/overworld.json` |
| Main scene — the app: launcher, editor and game as three screens | `scenes/Shell.tscn` |
| A run of the game | `scenes/world/World.tscn` |
| The world select | `scenes/ui/Launcher.tscn` |
| The lighting shader | `assets/shaders/pixel_lit.gdshader` |
| The held-world screen effect | `assets/shaders/held.gdshader` |
| Tileset layout & how to drop in a drawn one | `assets/sprites/README.md` |

---

## Conventions that bite (read before editing)

These are enforced by the code, not optional style. Full rationale in
[ARCHITECTURE.md](ARCHITECTURE.md) and [AGENTS.md](../AGENTS.md); the vocabulary
the names are drawn from is [GLOSSARY.md](GLOSSARY.md):

- **Derive, never mutate.** Change the fold list and re-derive; editing a
  `FoldedPiece` in place does not persist.
- **Transport through `BaseFrame`**, not crease arithmetic. Crease math is a
  fallback for points over void and does not compose across folds.
- **Ask `TileTypes`**, don't switch on type ints (`is_walkable`, `blocks_fold`,
  `blocks_anchor`).
- **Never compare floats with `==`** — use `GeometryCore.EPSILON`.
- **Don't mutate a collection while iterating it** — collect, then apply.
- After adding or renaming a `class_name`, run `godot --headless --editor --quit` once so
  the global class registry updates.

---

## Tests as living documentation

The suite is the behavioral spec. Naming maps one-to-one onto subjects:
`test_base_frame.gd` covers `BaseFrame`, `test_world_core.gd` covers `WorldCore`,
and so on. The exception is `test_fold_world.gd`, which is **scene-driven** — it
instantiates the real world scene and drives the actual beats (riding, pinching,
subspace folds, door traversal). If you change `FoldWorld`, that is the file that
will catch you. `test_world_mechanics.gd` is its sibling for plates, sockets, water,
sigils and the room reset, and `test_overworld_solutions.gd` plays the shipped world
from its first room to its last.

See [DEVELOPMENT.md](DEVELOPMENT.md) for how to run tests (including the sandbox
`HOME` invocation).
