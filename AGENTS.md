# Space-Folding Puzzle Game - AI Agent Guide

**START HERE** - Essential context for AI agents working on this project.

**Last Updated:** 2026-07-15
**Current Phase:** Core mechanics + step-log foundation (F1-F7) complete. Content/editor
support for the new tile types (PIN, TRIGGER_FOLD) is the current gap — see "What's Next".

---

## ⚠️ ARCHITECTURE UPDATE (2026-07-15): Step-log replay (F1-F7)

Second rewrite of the fold engine in a week, on top of the 2026-07-08 derive/replay
model below. **The source of truth is now a full ACTION LOG, not just a fold list:**
`base_grid` + `initial_player_base_id` + an ordered `Array[FoldStep]` (fold / unfold /
move / place-anchor). Every mutation is replay-reachable, and therefore undoable, by
construction. The 2026-07-08 derive/replay model (immutable base grid, `Fold`,
`FoldReplay.derive`) is still present and still used for pure trial/validation
derivations (e.g. "would this fold be legal"), but `FoldEngine`'s live state is driven
by the step log via `StepReplay`, not by replaying `folds` directly.

**New model (`scripts/model/`):**
- `FoldStep` — one log entry: `fold`, `unfold`, `move(direction)`, or an anchor-selection
  action. `TileTypes.gd` — the single registry for what a tile type IS/DOES
  (`walkable`, `merge_rank`, `blocks_fold`, `blocks_anchor`, `on_enter`); adding a new
  type means editing ONE file, not every switch statement in the engine.
- `StepReplay` — pure `apply_step(base_grid, prev_checkpoint, step) -> checkpoint`.
  `FoldEngine` keeps an **incremental checkpoint stack** (one per step-log prefix), so
  appending a step extends the last checkpoint by one operation instead of replaying
  the whole log, and undo is an O(1) pop.
- `TriggerResolver` — resolves the reaction cascade after a step (F3): landing the
  player on a `TRIGGER_FOLD` tile fires a fold between anchors named in that tile's
  per-instance data. Runs INSIDE `StepReplay.apply_step`, so cascades are deterministic
  and free of bespoke undo logic. Cycle-guarded (`fired` set) + hard iteration cap
  (`MAX_CASCADE`); on hitting the cap the cascade silently terminates.
- Multi-body player (F4): a fold can split the player into more than one body
  (`player_base_ids`); `player_base_id`/`player_plane_pos` remain the primary
  (largest-fragment) body for single-sprite callers.
- Fold-block predicate (F5): `TileTypes.PIN` occupants block excision — a fold that
  would cut/excise a PIN is illegal. Consumed generically, not type-cased.
- Occupants (F6): boxes, split-off player bodies, and anchors are all generalized as
  occupants with engine-authoritative movement; `FoldController` renders occupant
  overlays instead of bespoke box/anchor code paths.
- Pre-placed folds (F7): `LevelData.folds` are applied before the player spawns
  (nested-reveal on unfold; crease dots render for every pre-fold, not just
  player-made ones).
- `scripts/utils/CollisionCore.gd` — polygon-clip + swept collision + navigable
  predicates; carried rigid geometry (a cut piece stays cut, tracked relative to its
  base tile's anchor) so a diagonal-split player stays a triangle across moves.

**Two new tile types**, added directly against the `TileTypes` registry (not
F-numbered, landed in the same merge): `UNANCHORABLE_FLOOR` (walkable, blocks anchor
placement) and `UNANCHORABLE_WALL` (not walkable, blocks anchor placement). Neither
blocks fold excision.

**Fold semantics — MEET-IN-THE-MIDDLE (unchanged):** a fold orders its two anchors
(anchor_a = lexicographic min by (y,x)), excises the strip strictly between their
creases, and slides BOTH outer flaps inward by integer half-shifts
(`shift_a_grid ≈ (b-a)/2`, `shift_b_grid = shift_a_grid - (b-a)`) so the halves meet at
a common line (grid-aligned). The merge/seam (crease dot) sits at
`meeting_pos = anchor_a + shift_a_grid`. Animated folds use polygon interpolation
(`FoldController._fold_map_polygon`): flaps translate, the between strip collapses
onto the meeting line.

**Superseded decisions** (kept for history): the **Null Piece System is GONE**; the
**Seam class and legacy Cell/CellPiece seam+snapshot methods were removed** (Cell is a
pure render view; CellPiece is a render/collision piece); `FoldSystem.gd` and
`ActionHistory.gd` no longer exist in the tree — `FoldEngine` + `FoldController` +
`HistoryManager` replace them; **UNDO is Baba-style global input-history** (reverses
move/fold/unfold AND anchor place/cancel/turn uniformly — not snapshot-per-fold);
**UNFOLD = remove the fold + re-derive**; the **hybrid grid-polygon** cells are a
derived VIEW, not the source of truth. The coordinate system (LOCAL for cells, WORLD
for player) is UNCHANGED. The wall-folded-onto-goal ambiguity noted as an "open item"
on 2026-07-08 is now settled by design: `TileTypes.merge_rank` (goal=4 beats wall=3),
not left to chance.

**Tests:** `HOME=/tmp/godot-home ./run_tests.sh [name]` from the repo root (system Godot;
the bundled `tools/godot` binary is Linux-only). Key new suites: `test_step_log_replay`,
`test_trigger_cascade`, `test_tile_types`, `test_anchor_occupants`, `test_box_push`,
`test_carried_geometry`, `test_collision_core`, `test_swept_collision`,
`test_sub_tile_collision`, `test_split_on_unfold`, `test_player_split`,
`test_preplaced_folds`, `test_unanchorable_tiles`, `test_custom_levels_solvable`
(plus the 2026-07-08 suites: `test_fold_replay`, `test_folded_state`,
`test_fold_unfold_inverse`, `test_history_undo`, `test_player_ride`,
`test_fold_controller`, `test_cell_view_bridge`, `test_base_grid`).

**Open items:** level editor palette has no entry for `PIN` or `TRIGGER_FOLD` (only
hand-edited level JSON can place them today); the official 10-level campaign hasn't
been updated to use any F1-F7 mechanic (only the 10 new `t1`-`t10` demo levels in
`levels/custom/` do); `docs/ARCHITECTURE.md`/`docs/REFERENCE.md` still describe the
deleted `FoldSystem`/`ActionHistory`/null-piece system as current. See "What's Next"
below.

---

## Quick Start

1. **Read this guide** (5 min) - Get essential context
2. **Read [STATUS.md](STATUS.md)** (2 min) - See current progress
3. **Read relevant docs** in `docs/` based on your task (10-30 min)
4. **Run tests** to verify setup: `./run_tests.sh`

---

## Project Overview

**Name:** Space-Folding Puzzle Game
**Engine:** Godot 4.3
**Language:** GDScript
**Approach:** Test-Driven Development (TDD)

A grid-based puzzle game where players fold space by selecting two anchor points, removing the space between them, and merging the grid. The unique mechanic allows for folds at arbitrary angles, creating complex geometric puzzles.

**Core Mechanic:** Select two anchors → Fold removes space between them → Grid cells merge

---

## Current Status Summary

See **[STATUS.md](STATUS.md)** for detailed progress tracking.

**Completed Phases:**
- ✅ Phase 1: Project Setup & Foundation (GeometryCore utilities)
- ✅ Phase 2: Basic Grid System (Cell, GridManager)
- ✅ Phase 3: Simple Axis-Aligned Folding (horizontal/vertical)
- ✅ Phase 4: Geometric Folding (diagonal folds at arbitrary angles)
- ✅ Phase 5: Multi-Seam Handling (multi-piece cells, null pieces)
- ✅ Phase 6: Undo/Unfold System (independent unfold + snapshot undo)
- ✅ Phase 7: Player Character (movement, validation, goal detection)
- ⚙️ Phase 9 & 10: Level system, GUI, audio (substantially complete)
- ✅ F1-F7 + collision: step-log replay, tile registry, triggers, multi-body player,
  fold-block predicate, occupant generalization, pre-placed folds, swept collision
  (see architecture update above)

**Tests:** 496 passing / 496 (0 failing, 0 risky). See STATUS.md for the authoritative count.

**Next Priority:** level editor support for `PIN`/`TRIGGER_FOLD` tiles, and weaving
F1-F7 mechanics into the official campaign (currently only the `t1`-`t10` demo levels
use them). See "What's Next" below.

---

## Critical Architectural Decisions

These shape the entire implementation - **do not deviate** without careful consideration:

### 1. Hybrid Grid-Polygon System
- Start with simple grid cells (position + type)
- Convert to polygons ONLY when split by a fold
- **Why:** Memory efficient, easier level creation

### 2. Player Fold Validation Rule ⚠️ CRITICAL
**Folds are blocked if:**
- Player is in the removed region (between fold lines), OR
- Player is on a cell that would be split by the fold

**Why:** Simplifies player logic, prevents edge cases, intuitive gameplay

**Implementation:** Always call `validate_fold_with_player()` before executing

### 2a. UNFOLD vs UNDO Behavior ⚠️ CRITICAL DISTINCTION
**UNFOLD (seam-based, clicking on seams):**
- Can only unfold if player is NOT standing on the seam
- Fully reverses geometric fold (shifts, merges, splits, removals)
- Does NOT restore player position from fold record
- Player only moves if on a cell that shifts during unfold
- Behaves like unfolding paper - geometric reversal only

**UNDO (action-based, button/keyboard):**
- Full state restoration including player position
- Restores grid AND player to exact state before action
- Reverses most recent action in history (LIFO)
- No player-on-seam validation needed

**Why:** Unfold is a spatial puzzle mechanic with tactical constraints. Undo is a quality-of-life feature for correcting mistakes.

**Implementation:** Seam clicks call `unfold_seam()`, undo button calls `undo_fold_by_id()`

### 3. Coordinate System ⚠️ MOST COMMON BUG
- **Cells use LOCAL coordinates** (relative to GridManager.position)
- **Formula:** `local_pos = Vector2(grid_pos) * cell_size` (NOT grid_to_world!)
- **Player uses WORLD coordinates:** `grid_manager.to_global(local_pos)`
- **Seam lines use LOCAL coordinates** (they're children of GridManager)

**Why:** Cells and Line2D inherit GridManager's transform. Player does not.

### 4. Folding Behavior (Phase 3 Lessons)
- Cells **OVERLAP/MERGE** at anchor positions (not adjacent)
- Shift distance: `anchor2 - anchor1` (full overlap)
- MIN_FOLD_DISTANCE = 0 (adjacent anchors allowed)
- **Must FREE overlapped cells** to prevent memory leaks

### 5. Null Piece System (Geometric Consistency)
- **Null pieces** (CELL_TYPE_NULL = -1) represent missing geometry from folds
- When a piece shifts to empty location, complement geometry is filled with null piece
- Null pieces are **invisible and unwalkable** but geometrically complete
- Treated as highest priority in dominant type (makes cell unwalkable)
- **Why:** Maintains geometric invariants, simplifies future fold operations, no special cases needed

### 6. Other Key Decisions
- **Sutherland-Hodgman** for polygon splitting (industry standard)
- **Bounded Grid Model** - folds clip at boundaries
- **Tessellation** for multi-seam handling (subdivide into convex regions)
- **Strict Undo Ordering** - can only undo newest fold affecting all its cells

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for detailed rationale.

---

## Project Structure

```
/home/user/puzzle/
├── AGENTS.md                    # ← YOU ARE HERE - Start here!
├── STATUS.md                    # Current progress (update frequently)
├── README.md                    # Public-facing project info
│
├── docs/                        # Reference documentation
│   ├── ARCHITECTURE.md          # Design decisions (why)
│   ├── DEVELOPMENT.md           # Development workflow (how)
│   ├── REFERENCE.md             # Code map — pointers to source (where)
│   ├── phases/                  # Phase-specific documentation
│   │   ├── README.md            # Phase overview
│   │   ├── completed/           # Archived completed phases
│   │   └── pending/             # Future phase details
│   └── features/                # Feature-specific docs
│       ├── GUI.md
│       ├── AUDIO.md
│       └── LEVELS.md
│
├── scripts/
│   ├── core/                    # Cell, GridManager, Player
│   ├── systems/                 # FoldSystem, LevelManager, AudioManager
│   ├── utils/                   # GeometryCore, math utilities
│   └── tests/                   # GUT test framework
│
├── scenes/                      # Godot scene files
├── assets/                      # Sprites, shaders, audio
├── levels/                      # Level data files
└── tools/                       # Godot binary, scripts
```

---

## Key Classes (Quick Reference)

See **[docs/REFERENCE.md](docs/REFERENCE.md)** for detailed API.

### GeometryCore (`scripts/utils/GeometryCore.gd`)
Static utility class for geometric calculations.
- `split_polygon_by_line()` - Sutherland-Hodgman algorithm for polygon splitting
- `point_side_of_line()` - Point-line relationship
- `segment_line_intersection()` - Line intersection
- `calculate_complement_geometry()` - Computes missing geometry for null pieces
- **EPSILON = 0.0001** - Never use `==` with floats!

### Cell (`scripts/core/Cell.gd`)
Represents a grid cell with support for multiple geometry pieces.
- `grid_position: Vector2i` - Grid coordinates
- `geometry_pieces: Array[CellPiece]` - Array of polygonal pieces (LOCAL coords)
- `geometry: PackedVector2Array` - Legacy accessor (first piece's geometry)
- `cell_type: int` - Dominant type (1=wall, 2=water, 3=goal, -1=null, 0=empty)
- `is_partial: bool` - True if cell has been split by a fold
- **Note:** Null pieces (-1) are invisible, unwalkable representations of missing geometry

### CellPiece (`scripts/core/CellPiece.gd`)
Represents a single polygon piece within a cell.
- `geometry: PackedVector2Array` - Polygon vertices (LOCAL coords)
- `cell_type: int` - Type of this piece (-1=null, 0=empty, 1=wall, 2=water, 3=goal)
- `source_fold_id: int` - ID of fold that created this piece (-1 if original)
- Used when cells are split by folds or merged after shifts
- **Null pieces:** Created when geometry needs to be completed after splits

### GridManager (`scripts/core/GridManager.gd`)
Manages the grid **view** (materialized from `FoldedState` via `refresh_from_state`).
- `cells: Dictionary` - Vector2i → Cell mapping
- `selected_anchors: Array[Vector2i]` - Max 2 anchors
- `grid_origin: Vector2` - Centering offset
- **Important:** GridManager.position is at grid_origin

### FoldEngine (`scripts/systems/FoldEngine.gd`) + FoldController (`scripts/systems/FoldController.gd`)
Replace the deleted `FoldSystem.gd`/`ActionHistory.gd`. `FoldEngine` is the pure,
tested, step-log-driven core (base grid + step log + incremental checkpoint stack);
`FoldController` is the Godot-node adapter that drives `GridManager`'s view, rides +
animates the Player, and renders crease-dot unfold handles. `FoldController` exposes
the same public surface the old `FoldSystem` did, so callers only needed a type swap.
- `FoldEngine.apply_fold()` / `remove_fold()` - mutate the step log, re-derive
- `FoldEngine.move_player()` - engine-authoritative movement (F6)
- `FoldController` - node-level entry point used by `GridManager`/`InteractionController`

### TileTypes (`scripts/model/TileTypes.gd`)
Single registry for per-type facts (F1) — the reason a new tile type is a one-file
change instead of touching every switch statement in the engine.
- `TileTypes.walkable(type)` / `.merge_rank(type)` / `.blocks_fold(type)` /
  `.blocks_anchor(type)` / `.dominant_type(types: Array) -> int`
- Types: `EMPTY`(0), `WALL`(1), `WATER`(2), `GOAL`(3), `TRIGGER_FOLD`(4), `PIN`(5),
  `UNANCHORABLE_FLOOR`(6), `UNANCHORABLE_WALL`(7)

---

## Common Pitfalls ⚠️

### 1. Coordinate System Confusion (MOST COMMON!)
```gdscript
# ❌ WRONG - Using world coordinates for cell geometry
var world_pos = grid_manager.grid_to_world(grid_pos)
cell.geometry = create_square(world_pos, size)  // Double offset!

# ✅ CORRECT - Using local coordinates
var local_pos = Vector2(grid_pos) * grid_manager.cell_size
cell.geometry = create_square(local_pos, size)
```

**Why:** Cells are children of GridManager, inherit its position.

### 2. Floating Point Precision
```gdscript
# ❌ WRONG
if point.x == 5.0:

# ✅ CORRECT
const EPSILON = 0.0001
if abs(point.x - 5.0) < EPSILON:
```

### 3. Memory Leaks (Cell Merging)
```gdscript
# ❌ WRONG - Overwrites without freeing
cells[new_pos] = shifted_cell  // Old cell still in scene tree!

# ✅ CORRECT - Free old cell first
var existing_cell = cells.get(new_pos)
if existing_cell:
    cells.erase(new_pos)
    if existing_cell.get_parent():
        existing_cell.get_parent().remove_child(existing_cell)
    existing_cell.queue_free()
cells[new_pos] = shifted_cell
```

### 4. Array Modifications During Iteration
```gdscript
# ❌ WRONG
for cell in cells:
    if condition:
        cells.erase(cell)  # Breaks iteration!

# ✅ CORRECT
var cells_to_remove = []
for cell in cells:
    if condition:
        cells_to_remove.append(cell)
for cell in cells_to_remove:
    cells.erase(cell)
```

See **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** for complete pitfall list.

---

## Testing Framework

**Framework:** GUT (Godot Unit Test) v9.4.0
**Test Directory:** `scripts/tests/`

### Running Tests

```bash
./run_tests.sh                   # Run all tests
./run_tests.sh geometry_core     # Partial match on filename
./run_tests.sh fold              # Runs all tests matching "fold"
./run_tests.sh --help
```

`run_tests.sh` prefers the bundled `tools/godot/godot` but **that binary is Linux
x86-64** and won't execute elsewhere; the script auto-falls back to a system
`godot` on PATH. On macOS: `brew install godot` (or add Godot.app's binary to
PATH). If the sandbox blocks Godot's config dir, redirect HOME:

```bash
HOME=/tmp/godot-home ./run_tests.sh
```

### Writing Tests (TDD Approach)

1. **Write test FIRST** (defines expected behavior)
2. **Run test** (should fail)
3. **Implement feature** (make test pass)
4. **Refactor** (keep tests passing)

```gdscript
extends GutTest

func test_something():
    assert_eq(5, 5, "Five should equal five")
    # Always include descriptive messages!
```

**Approach:** New features are expected to ship with tests. See `STATUS.md` for
the current suite size and **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** for
testing best practices.

---

## Development Workflow

### Starting a Task

1. **Check current status:** Read `STATUS.md`
2. **Read relevant context:** completed phase specs in `docs/phases/completed/`, plus `docs/REFERENCE.md` for the code map
3. **Write tests first** (TDD approach)
4. **Run tests frequently:** `./run_tests.sh`
5. **Verify all tests pass** before committing

### Completing a Task

1. **Ensure all tests pass** (`./run_tests.sh`)
2. **Update STATUS.md** (test counts, phase status)
3. **Update phase documentation** if needed
4. **Commit with clear message**
5. **Push to feature branch**

### Code Quality Standards

- ✅ All tests must pass
- ✅ No floating-point equality (`==`) - use epsilon
- ✅ Proper memory management (`queue_free()` for nodes)
- ✅ Clear variable naming
- ✅ Comments explain "why", not "what"
- ✅ No geometry validation errors

---

## Git Workflow

Work happens on `claude/*` feature branches; PRs merge into `main`.

**Committing Changes:**
```bash
# Stage changes
git add .

# Commit with descriptive message
git commit -m "Fix removed-cell restoration in independent unfold"

# Push to the current feature branch
git push -u origin HEAD
```

**Creating Pull Requests:** See git operations section in main instructions.

---

## Documentation Map

Each fact has **one** authoritative home — link to it, don't copy it:

| Doc | Owns |
|---|---|
| `STATUS.md` | Current progress, phase status, **test counts** |
| `AGENTS.md` (this file) | Agent onboarding, critical decisions, pitfalls |
| `docs/ARCHITECTURE.md` | Design decisions & rationale (stable) |
| `docs/DEVELOPMENT.md` | Workflow, testing, contribution guidance |
| `docs/REFERENCE.md` | Code map — pointers to source files (not signatures) |
| `docs/phases/completed/` | Historical phase specs (read-only record) |

Keep this file lean: update it only for a new critical pitfall, a major
architectural change, or a new tool/workflow. Do **not** restate test counts or
progress here — those live in `STATUS.md`.

---

## What's Next

The core folding engine (Phases 1-7) and the step-log foundation (F1-F7 + collision)
are both complete and tested (496/496). What's missing now is **surfacing the new
mechanics to players and level authors**, not more engine architecture:

1. **Level editor support for `PIN` / `TRIGGER_FOLD`** (P1) — the editor palette
   (`LevelEditor.PAINT_TYPES`) already has swatches for `UNANCHORABLE_FLOOR`/`WALL`
   but not for `PIN` or `TRIGGER_FOLD`. `TRIGGER_FOLD` additionally needs an editor UI
   for its per-instance data (channel, target anchors) — right now these two types
   can only be authored by hand-editing level JSON (see `levels/custom/t1_pressure_gate.json`
   for the shape of that data).
2. **Weave F1-F7 mechanics into the official campaign** (P2) — the 10-level campaign
   in `levels/campaign/` (`01_first_fold` … `10_the_gauntlet`) predates F1-F7 and only
   uses wall/water/goal. The new demo levels (`levels/custom/t1`-`t10`) show off
   PIN/TRIGGER_FOLD/boxes/unanchorable tiles but aren't part of the campaign
   progression (`ProgressManager`).
3. **Refresh `docs/ARCHITECTURE.md` / `docs/REFERENCE.md`** (P2) — both still describe
   the deleted `FoldSystem.gd`/`ActionHistory.gd`/null-piece system as current;
   this file (AGENTS.md) and STATUS.md are the accurate source until that pass happens.
4. **Cell Types & Visual Elements polish** (P3) — PIN/TRIGGER_FOLD/unanchorable tiles
   currently render as flat color swatches; richer visuals/animations are unstarted.
5. **Graphics/Audio polish** (P3) — particle effects, seam visual polish, UI/UX
   refinements (carried over from the old Phase 10 backlog).
6. **Testing & Validation** (P4) — edge cases, performance, larger grids.

Completed phase specs live in `docs/phases/completed/` as a historical record.
`docs/phases/pending/` is currently empty; the old Phase 8/11 spec-doc gap is now
superseded by the F-numbered work above.

---

## Getting Help

| Question | Go to |
|---|---|
| Where's the code for X? | `docs/REFERENCE.md` (code map) |
| Why is it designed this way? | `docs/ARCHITECTURE.md` |
| How do I run tests / contribute? | `docs/DEVELOPMENT.md` |
| What's done / next? | `STATUS.md` |
| How does behavior X work? | its `scripts/tests/test_*.gd` — living documentation |

External: [GUT docs](https://gut.readthedocs.io/) · [Godot 4 docs](https://docs.godotengine.org/)

---

## The five things that matter most

1. **Read `STATUS.md` first** — know what's done and what's next.
2. **Cells/seams use LOCAL coords, the player uses WORLD** — the most common bug.
3. **Free cells before overwriting them** — prevents memory leaks.
4. **Never compare floats with `==`** — use `GeometryCore.EPSILON`.
5. **Write the test first** — the suite is the behavioral spec.
