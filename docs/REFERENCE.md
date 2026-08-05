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
| Immutable base level: `BaseTile` per position, grid metrics, `from_types()` constructor, unit squares | `BaseGrid.gd` |
| One base tile: stable `base_id`, `grid_position`, `type`, per-instance `data` | `BaseTile.gd` |
| One fold: anchors, crease points/normal, `shift_a/b` in grid and px, `channel` | `Fold.gd` |
| **The derivation engine.** `derive()`, `derive_pieces()`, `apply_one_fold()` — replays a fold list over the base grid | `FoldReplay.gd` |
| A derived fragment: `base_id`, `type`, `polygon`, `plane_pos`, **`src_offset`** | `FoldedPiece.gd` |
| Queryable derived state: per-position stacks, `dominant_type_at`, `pieces_of_base` | `FoldedState.gd` |
| **Base ↔ derived point transport.** `transport()`, `world_point_from_base()`, `resolve_base_point()`, `piece_at()` | `BaseFrame.gd` |
| **The tile registry.** walkable / merge_rank / blocks_fold / blocks_anchor / on_enter | `TileTypes.gd` |
| Entities that ride base tiles: split-on-unfold latents, carried geometry, footprints | `Occupants.gd` |
| Fold-on-enter cascade: channels, fire-once guard, bounded fixpoint | `TriggerResolver.gd` |
| Authored world: regions (ASCII rows), doors, pre-placed folds; JSON round trip | `WorldData.gd` |

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
| **Everything that makes it a game**: regions, the context stack (subspaces), doors, input, fold/unfold flow, animation, camera, HUD | `FoldWorld.gd` |
| Pure world logic: ASCII map parsing, side-of-fold for a free point, strip capture, seam/glue segments, circle-vs-polygon depenetration, anchor & fold eligibility, camera framing + lookahead | `WorldCore.gd` |
| Player physics body: coyote time, jump buffer, squash; owns the camera (follow + zoom + lookahead easing) | `PlayerBody.gd` |
| Anchors, fold preview band, seam diamonds, glue lines | `WorldOverlay.gd` |
| Controls and the design beats | `README.md` |

`FoldWorld.gd` is the largest file and the one to read first if you want to
understand how the pieces meet. Its header comment is the map.

### Where to look for a specific behavior

| "How does…" | Start at |
|---|---|
| …a fold get committed? | `FoldWorld.do_fold()` / `do_sub_fold()` |
| …the player ride a flap? | `do_fold()` → `BaseFrame.world_point_from_base` → `WorldCore.depenetrate` |
| …getting pinched into a fold work? | `do_fold()`, the `dest == null` branch |
| …a subspace get derived? | `FoldWorld._compute_level()` / `_apply_context()` |
| …unfold blocking work? | `FoldWorld.can_unfold_fold()`, `WorldCore.segment_intersects_band` |
| …exiting a subspace work? | `FoldWorld.try_exit()`, `exit_blocker()` |
| …a door find its partner? | `FoldWorld._check_doors()`, `BaseFrame.resolve_base_point` |
| …a trigger fire? | `FoldWorld._check_triggers()` → `TriggerResolver.resolve` |
| …the camera decide how far to zoom? | `FoldWorld._update_camera()` / `_camera_focus()` → `WorldCore.camera_zoom_for` |
| …the camera decide where to look ahead? | `FoldWorld._update_camera()` → `WorldCore.camera_lookahead_for` (+ `PlayerBody.motion_fraction` / `look_dir`) |
| …F pick which fold to unfold? | `FoldWorld.aimed_fold()` — newest-first, prefers one that can actually come out |

---

## Systems & UI

| Concern | File |
|---|---|
| Audio buses, SFX/music playback, volume persistence | `scripts/systems/AudioManager.gd` (autoload) |
| In-world pause: resume / respawn / settings / quit | `scripts/ui/PauseMenu.gd` |
| Audio & display settings | `scripts/ui/Settings.gd` |

---

## Data

| Concern | Path |
|---|---|
| The authored world | `worlds/overworld.json` |
| Main scene | `scenes/world/World.tscn` |

---

## Conventions that bite (read before editing)

These are enforced by the code, not optional style. Full rationale in
[ARCHITECTURE.md](ARCHITECTURE.md) and [AGENTS.md](../AGENTS.md):

- **Derive, never mutate.** Change the fold list and re-derive; editing a
  `FoldedPiece` in place does not persist.
- **Transport through `BaseFrame`**, not crease arithmetic. Crease math is a
  fallback for points over void and does not compose across folds.
- **Ask `TileTypes`**, don't switch on type ints (`is_walkable`, `blocks_fold`,
  `blocks_anchor`).
- **Never compare floats with `==`** — use `GeometryCore.EPSILON`.
- **Don't mutate a collection while iterating it** — collect, then apply.
- After adding or renaming a `class_name`, run `godot --headless --import` once so
  the global class registry updates.

---

## Tests as living documentation

The suite is the behavioral spec. Naming maps one-to-one onto subjects:
`test_base_frame.gd` covers `BaseFrame`, `test_world_core.gd` covers `WorldCore`,
and so on. The exception is `test_fold_world.gd`, which is **scene-driven** — it
instantiates the real world scene and drives the actual beats (riding, pinching,
subspace folds, door traversal). If you change `FoldWorld`, that is the file that
will catch you.

See [DEVELOPMENT.md](DEVELOPMENT.md) for how to run tests (including the sandbox
`HOME` invocation).
