# Architecture & Design Decisions

**Purpose:** This document explains **WHY** things are designed the way they are.

**Last Updated:** 2026-07-15

---

## Core Design Philosophy

**1. Test-Driven Development (TDD)**
- Write tests before implementation
- Tests define expected behavior
- Tests serve as living documentation

**2. Simplicity First**
- Start with the simplest solution that works
- Add complexity only when needed
- Clear, readable code over clever code
- Explicit over implicit

**3. Derive, Don't Mutate**
- State is a small, immutable base plus an ordered log of what happened to it
- Everything else (geometry, occupant positions, the active fold list) is a pure
  function of that log, recomputed on demand
- A pure derivation is trivially undoable (drop the last log entry, re-derive) and
  trivially testable (same input log always produces the same output)

---

## Critical Architectural Decisions

These decisions shape the entire implementation. **Do not deviate** without careful
consideration.

---

### Decision 1: Immutable Base + Pure Derivation

**The Decision:**
- `BaseGrid`/`BaseTile` (`scripts/model/`) are the immutable, unfolded level: a set of
  base tiles plus grid metrics, built once at level load and never mutated.
- The folded configuration is never stored directly. It is always the output of a pure
  function over `(BaseGrid, log)`.
- There is no "null" or "void" tile type. Void is simply the absence of a piece at a
  plane position in the derived output.

**Rationale:**
- **No snapshot bookkeeping:** unfold = drop a log entry and re-derive; nothing needs
  to remember "what it looked like before."
- **No stale state:** every read goes through the same derivation, so there is no
  class of bug where the live grid and the "authoritative" state disagree.
- **Testability:** `derive(base, log) -> DerivedState` is a pure function — easy to
  unit test with plain inputs/outputs, no scene tree required.

**Impact:**
- `Cell`/`CellPiece` (`scripts/core/`) are a rendered VIEW materialized from the
  derived state (`GridManager.refresh_from_state`), not the source of truth.
- Adding a new kind of mutation (a new step type, a new trigger) means teaching the
  derivation function about it — not adding a new subsystem to keep in sync.

---

### Decision 2: The Step Log Is the Source of Truth

**The Decision:**
State = `BaseGrid` + the player's starting tile + an ordered `Array[FoldStep]`
(`scripts/model/FoldStep.gd`: `FOLD`, `UNFOLD`, `MOVE`, `PLACE_ANCHOR`). Every player
action that changes the world is a step appended to this log. `StepReplay`
(`scripts/model/StepReplay.gd`) replays the log to derive both the folded geometry
**and** the world's occupants (player, boxes, anchors).

**Rationale:**
- **Replay-reachable ⇒ undoable by construction:** because every mutation is a log
  entry, any future mutation type (destruction, triggered folds, pushes) is
  automatically undoable — there is no separate undo path to keep in sync.
- **Incremental derivation:** `FoldEngine` keeps a stack of checkpoints, one per log
  prefix. Appending a step extends the last checkpoint by a single operation instead
  of replaying the whole log from scratch; undo is an O(1) checkpoint pop.
- **Determinism:** steps are plain value data (ints/`Vector2i`), so a log can be
  duplicated, serialized, and replayed to produce byte-identical results.

**Impact:**
- `FoldEngine` (`scripts/systems/FoldEngine.gd`) is the stateful owner: it appends
  steps and exposes the live derived caches (`folds`, `current_state`,
  `player_base_id`) that existing readers depend on.
- `FoldReplay.derive(base, folds) -> FoldedState` (fold-list only, no occupants) still
  exists as a lighter-weight pure function used for **trial derivations** — e.g.
  "would this fold be legal" — where the full step/occupant machinery isn't needed.

---

### Decision 3: TileTypes Is the Single Authority for Type Facts

**The Decision:**
`scripts/model/TileTypes.gd` is a registry mapping each tile type id to its facts:
`walkable`, `merge_rank` (co-surface merge priority), `blocks_fold` (can't be
excised by a fold), `blocks_anchor` (can't be used as a fold anchor), and `on_enter`
(behavior hook, e.g. `"fold"` for trigger tiles).

**Rationale:**
- Before this registry, the type int was switched on in every consumer (merge
  priority, dominant-type calculation, movement checks, anchor eligibility). Adding a
  type meant hunting down and editing every site.
- Centralizing per-type facts means a new tile type — "destroys pieces," "triggers an
  unfold," "blocks folding" — is added in ONE file. Consumers call
  `TileTypes.blocks_fold(type)` etc. and never switch on the raw int.

**Current types:** `EMPTY`(0), `WALL`(1), `WATER`(2), `GOAL`(3), `TRIGGER_FOLD`(4),
`PIN`(5), `UNANCHORABLE_FLOOR`(6), `UNANCHORABLE_WALL`(7).

**Impact:**
- `TileTypes.dominant_type(types: Array) -> int` resolves which type "wins" when
  several pieces share a plane position (merge_rank order:
  `NULL > PIN > GOAL > WALL > WATER > EMPTY`), which is what actually determines,
  e.g., whether a wall folded onto a goal is still reachable.
- `PIN` tiles are fold-proof: `blocks_fold` is consumed by a general fold-block
  predicate in `FoldEngine`, so no fold can excise or cut through one.
- `UNANCHORABLE_FLOOR`/`UNANCHORABLE_WALL` set `blocks_anchor`, checked by
  `GridManager.is_anchor_eligible` — the single coordination point for anchor
  legality.

---

### Decision 4: Fold-on-Enter Trigger Cascades

**The Decision:**
`TriggerResolver` (`scripts/model/TriggerResolver.gd`) runs INSIDE
`StepReplay.apply_step`: when a step lands the player on a `TRIGGER_FOLD` tile, a fold
is created between the anchors named in that tile's per-instance data, tagged with the
tile's channel. The cascade iterates, since a triggered fold can ride the player onto
another trigger.

**Rationale:**
- Running the cascade as part of pure derivation (not as a side effect fired from
  gameplay code) means triggered folds are recomputed on every replay and are
  therefore deterministic and undoable for free — dropping the authored step
  re-derives the prefix without the cascade, no special-case cleanup needed.

**Termination & idempotence:**
- Each trigger fires at most once per cascade (a `fired` set is the cycle guard).
- A fold is created only if no active fold already holds that channel, so standing on
  a trigger repeatedly does not spawn duplicate folds.
- A hard iteration cap (`MAX_CASCADE`) is the backstop for pathological chains; on
  hitting it the cascade terminates silently rather than looping forever.

---

### Decision 5: Occupants Generalize the Player

**The Decision:**
The player, pushable boxes, and anchors are all modeled as **occupants**: an identity
that rides a set of base tiles (`{kind, base_ids, latents}`), rather than the player
being special-cased everywhere.

**Rationale:**
- A fold can split an occupant's footprint. The part that gets folded away is
  remembered as a **latent** (`{base_id, fold_id}`) rather than deleted; the surviving
  part (if any) stays an active body and can move independently. Unfolding that fold
  re-materializes the latent at its home tile — if the active part had moved
  elsewhere, the occupant is now in two places at once: a genuine split. A body fully
  inside the excised region (e.g. a folded-over box) has no surviving flap and stays
  hidden until unfolded.
- Generalizing "thing that occupies tiles and can be affected by folds" once means box
  pushing, player splitting, and anchor tracking all share one code path
  (`StepReplay.occupant_positions`, `occupant_footprint`) instead of three.

**Impact:**
- The player can be split into multiple bodies by a fold (`player_base_ids`);
  `player_base_id`/`player_plane_pos` remain the primary (largest-fragment) body for
  single-sprite callers and simple queries.
- `FoldController` renders occupant overlays generically rather than hand-coding a
  box-rendering path and a separate anchor-rendering path.

---

### Decision 6: Meet-in-the-Middle Fold Geometry

**The Decision:**
A fold orders its two anchors (`anchor_a` = lexicographically smaller by `(y, x)`),
excises the strip strictly between their creases, and slides BOTH outer flaps inward
by integer half-shifts (`shift_a_grid ≈ (b - a) / 2`, `shift_b_grid = shift_a_grid -
(b - a)`) so the halves meet at a common, grid-aligned line. The merge/seam (crease
dot) sits at `meeting_pos = anchor_a + shift_a_grid`.

**Rationale:**
- Symmetric movement (both sides travel toward the middle) reads more like folding a
  physical sheet of paper than "one side slides fully onto the other," and keeps the
  seam roughly centered regardless of which anchor the player picked first.

**Impact:**
- Animated folds use polygon interpolation (`FoldController._fold_map_polygon`):
  flaps translate, and the between-strip visually collapses onto the meeting line.
- `Fold` (`scripts/model/Fold.gd`) stores only the anchors and derived crease
  geometry — no grid snapshot — since the fold's effect is always recomputed by
  `FoldReplay`/`StepReplay`, never stored.

---

### Decision 7: Coordinate System — LOCAL Cells, WORLD Player

**The Decision:**
- **Cells store geometry in LOCAL coordinates** (relative to `GridManager.position`).
- **Player uses WORLD coordinates** (absolute pixel positions).
- **`GridManager` is positioned at `grid_origin`** (centered on screen).

**Rationale:**
- Cells are children of `GridManager` and inherit its transform; the player is not a
  child (it needs absolute positioning for camera follow), so it needs the conversion
  explicitly.

**Formula:**
```gdscript
# Creating cell geometry (LOCAL coordinates)
var local_pos = Vector2(grid_pos) * cell_size

# Converting for player (WORLD coordinates)
player.position = grid_manager.to_global(local_pos + offset)
```

**Common bug:** using `grid_manager.grid_to_world(grid_pos)` for cell geometry
double-applies the origin offset, since `Cell` already inherits it via the scene
tree. Always build cell geometry from `Vector2(grid_pos) * cell_size` directly.

---

### Decision 8: Sutherland-Hodgman Clipping + a Collision Layer Above It

**The Decision:**
`GeometryCore` (`scripts/utils/GeometryCore.gd`) implements Sutherland-Hodgman polygon
splitting plus point/line/intersection primitives — pure math, no scene tree,
`EPSILON = 0.0001` for all float comparisons. `CollisionCore`
(`scripts/utils/CollisionCore.gd`) sits above it: polygon-set folding, and the
navigable/containment/overlap predicates that gate movement, wrapping Godot's built-in
`Geometry2D` boolean ops (`clip_polygons`, `intersect_polygons`, `merge_polygons`).

**Rationale:**
- Sutherland-Hodgman is the proven, simple, O(n) algorithm for splitting a polygon by
  a line — the core operation every fold performs on affected tiles.
- Godot's `Geometry2D` booleans handle the harder general polygon-set operations
  (swept collision, carried rigid geometry) that would be expensive to hand-roll, but
  their output vertex order/winding is not guaranteed stable across calls — so
  `CollisionCore` canonicalizes and quantizes (`canon`) every result before it's
  stored in a replay checkpoint, keeping the pure derive/replay byte-identical across
  runs.

**Impact:**
- Carried rigid geometry means a piece that got diagonally cut by a fold stays cut
  (tracked relative to its base tile's anchor) as it moves — a split player stays a
  triangle rather than snapping back to a square.
- Never compare floats with `==` anywhere in this stack; use `GeometryCore.EPSILON`.

---

### Decision 9: Bounded Grid Model

**The Decision:**
Folds clip at grid boundaries; no cells are created outside the grid. Grid size is
fixed per level (though levels can specify different sizes).

**Rationale:**
- Most intuitive for players (clear playfield boundaries), simplest to implement (no
  infinite-grid or scrolling management), and gives a predictable maximum cell count
  for performance.

---

### Decision 10: Baba-Style Global Undo

**The Decision:**
`HistoryManager` (`scripts/systems/HistoryManager.gd`) implements a single, uniform
undo: each committed player input (move, fold, or unfold) pushes one lightweight
snapshot of the engine's mutable state (the fold list + player state — no grid
snapshot, since the folded state is always re-derived). Undo pops the last snapshot
and restores it, reversing whichever input was last, uniformly.

**Rationale:**
- One undo path for every action type is simpler than tracking per-fold dependency
  graphs or restricting which folds are eligible to undo — the player just gets
  "undo my last input," repeatable as many times as there are snapshots.
- Snapshots are cheap because the fold list is immutable data and the folded
  geometry is never stored — only re-derived on demand.

---

### Decision 11: JSON Levels, Pre-Placed Folds

**The Decision:**
Levels are JSON (`LevelData`, `scripts/core/LevelData.gd`) for portability and
version-control-friendliness. `LevelData.folds` can specify folds that are applied
before the player spawns; unfolding one of these reveals whatever was behind it
(nested-reveal), and a crease dot renders for every pre-fold, not just player-made
ones.

**Rationale:**
- Human-readable, diffable, and easy to hand-author or generate — the demo/campaign
  levels are authored directly as JSON.
- Pre-placed folds let a level start "already folded," which is its own puzzle
  primitive (what's hidden behind this seam?) distinct from folds the player
  performs during play.

---

## Implementation Patterns

### Pattern 1: Always Validate Before Committing a Step

```gdscript
func attempt_fold(anchor1, anchor2):
    if not engine.is_fold_legal(anchor1, anchor2):
        show_error_message("Cannot fold here")
        return false

    engine.apply_fold(anchor1, anchor2)  # appends a FoldStep, re-derives
    return true
```

**Why:** Prevents invalid states from ever entering the step log, and gives the
player feedback instead of a silent no-op.

---

### Pattern 2: Test-Driven Development Flow

```gdscript
# 1. Write test FIRST
func test_pin_blocks_fold_excision():
    var result = engine.apply_fold(anchor_a, anchor_b)
    assert_false(result, "Fold should be blocked by PIN tile")

# 2. Run test (fails)
# 3. Implement feature
# 4. Run test (passes)
# 5. Refactor if needed; run test again (still passes)
```

**Why:** Defines expected behavior, catches regressions, builds confidence.

---

### Pattern 3: Floating Point Comparisons

```gdscript
const EPSILON = 0.0001

# NEVER use ==
if point.x == 5.0:  # WRONG

# ALWAYS use epsilon
if abs(point.x - 5.0) < EPSILON:  # CORRECT

# For Vector2
func vectors_equal(a: Vector2, b: Vector2) -> bool:
    return a.distance_to(b) < EPSILON
```

**Why:** Floating point arithmetic is imprecise; epsilon handles rounding errors.

---

## Performance Considerations

### Targets

- **Fold operation:** stays well under a frame budget on the grid sizes currently
  authored (up to 12×12).
- **Animation:** 60 FPS.
- **Test suite:** runs in single-digit seconds (`./run_tests.sh`), fast enough to run
  on every change.

### Optimization Strategy

1. **Measure first:** use the Godot profiler, don't guess.
2. **Optimize hot paths:** the incremental checkpoint stack (Decision 2) already
   avoids the most obvious hot path — re-deriving the whole log on every step.
3. **Avoid premature optimization:** simple code first, optimize if a real grid size
   or level actually shows a problem.

### Future Optimizations (if needed)

- Spatial partitioning (quadtree) for much larger grids.
- Pre-calculated centroids, cached per checkpoint.
- Batched visual updates for cell/occupant overlays.

---

## Design Questions Resolved

### Should fold animations be interruptible?
**Decision:** No, animations play to completion; player input is locked while
`FoldController.is_animating` is true.
**Rationale:** Simpler state management, short animations.

### How does diagonal movement work for the player?
**Decision:** Grid-based only (4 directions: up, down, left, right).
**Rationale:** Simpler, matches the puzzle grid structure.

### Should we show fold count/undo count in UI?
**Decision:** Yes, in the HUD with par comparison.
**Rationale:** Gives players feedback on performance.

### Level win condition?
**Decision:** Reach the goal tile.
**Rationale:** Simple; can add collectibles later if desired.

### Should folds that remove the goal tile be prevented?
**Decision:** Not enforced by the engine — level design should avoid this.
**Rationale:** Allows creative level designs; treated as a level-authoring
responsibility, not an engine constraint.

### Should level files be JSON or `.tres` format?
**Decision:** JSON.
**Rationale:** Human-readable, version-control friendly, easy to hand-author.

---

## References

**Algorithms:**
- Sutherland-Hodgman: [Wikipedia](https://en.wikipedia.org/wiki/Sutherland%E2%80%93Hodgman_algorithm)

**Godot Documentation:**
- [Scene Tree](https://docs.godotengine.org/en/stable/getting_started/step_by_step/scene_tree.html)
- [Coordinate Systems](https://docs.godotengine.org/en/stable/tutorials/2d/2d_transforms.html)
- [Geometry2D](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html)

**Testing:**
- [GUT Documentation](https://gut.readthedocs.io/)

---

**This document is stable** — only update when major architectural decisions are made
or revised. For what's currently done vs. pending, see `STATUS.md`; for a code map,
see `REFERENCE.md`.
