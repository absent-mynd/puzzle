# Code Map (Source Pointer Reference)

**Purpose:** Point you to the *right source file* for any subsystem. The source is
the authoritative API — this doc deliberately does **not** restate function
signatures, because a hand-maintained API list drifts out of sync with the code. Read
the file; every class carries `##` doc-comments on its public methods.

> **Finding things fast**
> - Every public type has a `class_name`, so grep for it: `grep -rn "class_name Cell" scripts/`
> - Jump to a symbol's definition or callers with your editor's LSP, or:
>   `grep -rn "func <name>" scripts/`
> - List a file's public API: `grep -nE "^(func|var|const|signal|class_name) " scripts/<file>.gd`

---

## Subsystem → File

### Geometry & collision (pure math, no scene tree)
| Concern | File |
|---|---|
| Polygon splitting (Sutherland-Hodgman), point/line tests, intersections, area/centroid. `const EPSILON = 0.0001` lives here. | `scripts/utils/GeometryCore.gd` |
| Collision layer above GeometryCore: polygon-set folding, navigable/containment/overlap predicates, swept collision, carried rigid geometry. Wraps Godot's `Geometry2D` booleans with output canonicalization for deterministic replay. | `scripts/utils/CollisionCore.gd` |
| File I/O helpers (JSON read/write) | `scripts/utils/FileUtils.gd` |

### Model — the derive/replay core (`scripts/model/`)
| Concern | File |
|---|---|
| Immutable base (unfolded) level: `grid_size`, `cell_size`, `tiles: Array[BaseTile]`. Built once at load, never mutated. | `BaseGrid.gd` |
| Immutable identity for one original grid square (`base_id`, `type`, per-instance `data`). No null type — void is the absence of a piece in the derived output. | `BaseTile.gd` |
| Single-authority registry for tile-type facts: `walkable`, `merge_rank`, `blocks_fold`, `blocks_anchor`, `on_enter`. `dominant_type(types) -> int` resolves merge priority. Types: `EMPTY`(0) `WALL`(1) `WATER`(2) `GOAL`(3) `TRIGGER_FOLD`(4) `PIN`(5) `UNANCHORABLE_FLOOR`(6) `UNANCHORABLE_WALL`(7). | `TileTypes.gd` |
| One immutable fold: anchors + derived crease geometry (meet-in-the-middle shift math). No grid snapshot. | `Fold.gd` |
| `derive(base, folds) -> FoldedState` — pure fold-list-only derivation, used for lightweight trial/validation checks. | `FoldReplay.gd` |
| Derived, queryable folded configuration: per-plane-position stacks of `FoldedPiece`. `dominant_type_at()`, `is_occupied()`, `plane_pos_of_base()`, `center_at()`. | `FoldedState.gd` |
| A derived fragment of a base tile in the current configuration (`base_id`, `type`, current-space polygon). Produced fresh by `FoldReplay.derive` every call; never mutated in place. | `FoldedPiece.gd` |
| One entry in the engine's authoritative step log: `FOLD`, `UNFOLD`, `MOVE`, `PLACE_ANCHOR`. Pure value data, no derived state. | `FoldStep.gd` |
| Replays a `FoldStep` log over the base grid to derive geometry AND occupants (player, boxes, anchors); split-on-unfold / latent-body bookkeeping for occupants a fold cuts through. | `StepReplay.gd` |
| Resolves the fold-on-enter trigger cascade (cycle-guarded, deterministic) as part of `StepReplay.apply_step`. | `TriggerResolver.gd` |

### Systems — stateful engine + game logic (`scripts/systems/`)
| Concern | File |
|---|---|
| Stateful owner of the derived-state model: base grid + step log + incremental checkpoint stack (O(1) undo). Live derived caches (`folds`, `current_state`, `player_base_id`, `player_base_ids`) for existing readers. | `FoldEngine.gd` |
| Godot-node adapter over `FoldEngine`: drives `GridManager`'s view (`refresh_from_state`), rides/animates the Player on its base tile, renders crease-dot unfold handles and occupant overlays. | `FoldController.gd` |
| Baba-Is-You-style global undo: one snapshot per committed input (move/fold/unfold/anchor action), uniformly reversible. | `HistoryManager.gd` |
| Exported enums for player-facing interaction design axes (second-anchor behavior, confirm persistence, action priority, null-anchor handling); tunable from the inspector. | `InteractionConfig.gd` |
| Player-facing interaction state machine (SPACE to interact with the faced tile: place anchors, commit folds, unfold creases). Governed by an `InteractionConfig`. | `InteractionController.gd` |
| Load/save levels (JSON), level cache. | `LevelManager.gd` |
| Validates level data for playability/well-formedness. | `LevelValidator.gd` |
| Campaign progression: completed levels, stars, best times; persists to `user://campaign_progress.json`. | `ProgressManager.gd` |
| SFX/music playback (autoload singleton); separate audio buses. | `AudioManager.gd` |

### Core — grid, cells, player, level data, editor (`scripts/core/`)
| Concern | File |
|---|---|
| A single grid cell: a rendered VIEW materialized from the derived state (`Cell.apply_folded_pieces`), not the source of truth. `grid_position`, `geometry_pieces: Array[CellPiece]`, dominant `cell_type`, `is_partial`, `tile_data` (per-instance params read into `BaseTile`). Coords are **LOCAL**. | `Cell.gd` |
| One polygon piece within a view `Cell` (render/collision piece), materialized from a `FoldedPiece`. | `CellPiece.gd` |
| The grid view: `cells: Dictionary` (Vector2i→Cell), anchor selection, `is_anchor_eligible` (checks `TileTypes.blocks_anchor`), `grid_origin`, coordinate conversion. `GridManager.position` sits at `grid_origin`. | `GridManager.gd` |
| Grid-based player movement (arrows/WASD), wall collision, goal/win detection, position updates during folds. Player uses **WORLD** coords. | `Player.gd` |
| Global game state / fold count (autoload singleton); editor↔play round-trip state (`is_testing_from_editor`, `editor_session`). | `GameManager.gd` |
| Level data resource + JSON (de)serialization; `folds` field for pre-placed folds applied before the player spawns. | `LevelData.gd` |
| In-game level editor: paint palette (`PAINT_TYPES`, currently `EMPTY`/`WALL`/`WATER`/`GOAL`/`UNANCHORABLE_FLOOR`/`UNANCHORABLE_WALL` — no `PIN`/`TRIGGER_FOLD` entries yet), mouse paint/erase, grid resize, metadata editing, play-test round-trip (`T` to test, "Back to Editor"). | `LevelEditor.gd` |

### UI (`scripts/ui/`)
`MainMenu`, `HUD`, `PauseMenu`, `LevelComplete`, `LevelSelect`, `CustomLevelSelect`,
`Settings` — one script per screen; scenes live in `scenes/ui/`.

---

## Conventions that bite (read before editing)

These are enforced by the code, not optional style. Full rationale in
[ARCHITECTURE.md](ARCHITECTURE.md) and the pitfalls section of
[AGENTS.md](../AGENTS.md):

- **Cells use LOCAL coordinates; the player uses WORLD.** Use
  `Vector2(grid_pos) * cell_size`, never `grid_to_world()`, for cell geometry.
- **Never compare floats with `==`** — use `GeometryCore.EPSILON`.
- **The base grid and every `Fold`/`FoldStep` are immutable.** Nothing mutates them
  in place; state changes by appending to the step log and re-deriving.
- **Don't mutate a collection while iterating it** — collect, then apply.
- **A new tile type is a `TileTypes.gd` change first**, not a switch-statement hunt
  across the engine.

---

## Tests as living documentation

The test suite (`scripts/tests/`) is the most reliable behavioral spec. To see how any
subsystem is *meant* to behave, read its `test_*.gd`. Key suites for the derive/replay
+ step-log core: `test_fold_replay`, `test_folded_state`, `test_fold_unfold_inverse`,
`test_step_log_replay`, `test_trigger_cascade`, `test_tile_types`,
`test_anchor_occupants`, `test_box_push`, `test_carried_geometry`,
`test_collision_core`, `test_swept_collision`, `test_split_on_unfold`,
`test_player_split`, `test_preplaced_folds`, `test_unanchorable_tiles`,
`test_history_undo`. See [DEVELOPMENT.md](DEVELOPMENT.md) for how to run tests
(including the macOS / sandbox invocation).
