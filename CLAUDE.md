# Space-Folding Puzzle Game - AI Agent Guide

**START HERE** - Essential context for AI agents working on this project.

**Last Updated:** 2026-07-08
**Current Phase:** Core mechanics complete. Fold engine re-architected to derive/replay (see below).

---

## ⚠️ ARCHITECTURE UPDATE (2026-07-08): Derive / Replay engine

The fold engine was rewritten. **State = an immutable base grid + an ordered list of
folds; everything else is DERIVED by replaying the folds from scratch.** The old mutating
`FoldSystem` (and `ActionHistory`) are DELETED.

**New model (`scripts/model/` + `scripts/systems/`):**
- `BaseGrid` / `BaseTile` — immutable base level (never mutated). No null type: "void" = a
  position with no piece.
- `Fold` — one fold: anchors, target/source, crease geometry, `shift_grid`. No snapshot.
- `FoldReplay.derive(base, folds) -> FoldedState` — pure function; the heart of the engine.
- `FoldedState` / `FoldedPiece` — derived per-position stacks; queries `dominant_type_at`,
  `is_occupied`, `plane_pos_of_base`, `center_at`.
- `FoldEngine` — stateful core (apply/remove fold; player rides its `base_id`).
- `HistoryManager` — Baba-style global undo (snapshots of engine + selection + heading).
- `FoldController` (Node) — adapter the game uses; keeps the old FoldSystem method names,
  materializes the derived state into `GridManager.cells` as view Cells
  (`Cell.apply_folded_pieces`, `GridManager.refresh_from_state`), rides + animates the
  player, and renders crease-dot unfold handles.

**Fold semantics — MEET-IN-THE-MIDDLE:** a fold orders its two anchors (anchor_a =
lexicographic min by (y,x)), excises the strip strictly between their creases, and slides
BOTH outer flaps inward by integer half-shifts (`shift_a_grid ≈ (b-a)/2`,
`shift_b_grid = shift_a_grid - (b-a)`) so the halves meet at a common line (grid-aligned).
The merge/seam (crease dot) sits at `meeting_pos = anchor_a + shift_a_grid`. Animated folds
use polygon interpolation (`FoldController._fold_map_polygon`): flaps translate, the between
strip collapses onto the meeting line.

**Superseded decisions below** (kept for history): the **Null Piece System is GONE**;
the **Seam class and legacy Cell/CellPiece seam+snapshot methods were removed** (Cell is a
pure render view; CellPiece is a render/collision piece);
**UNDO is now Baba-style global input-history** (reverses move/fold/unfold AND anchor
place/cancel/turn uniformly — not snapshot-per-fold); **UNFOLD = remove the fold + re-derive**;
the **hybrid grid-polygon** cells are now a derived VIEW, not the source of truth. The
coordinate system (LOCAL for cells, WORLD for player) is UNCHANGED.

**Tests:** `HOME=/tmp/godot-home ./run_tests.sh [name]` from the repo root (system Godot;
the bundled `tools/godot` binary is Linux-only). Key new suites: `test_fold_replay`,
`test_folded_state`, `test_fold_unfold_inverse`, `test_history_undo`, `test_player_ride`,
`test_fold_controller`, `test_cell_view_bridge`, `test_base_grid`.

**Open items:** wall-folded-onto-goal currently resolves to a walkable goal (tunable in
`FoldedState.dominant_type_at`); campaign level solutions still pass under the new
target-anchor rule but should be re-validated if fold direction is retuned.

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

**Tests:** 559 passing / 571 run (12 risky diagnostic tests). See STATUS.md for the authoritative count.

**Next Priority:** Phase 8 - Cell Types & Visual Elements (content/polish; no spec doc yet)

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
├── CLAUDE.md                    # ← YOU ARE HERE - Start here!
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
Manages the grid.
- `cells: Dictionary` - Vector2i → Cell mapping
- `selected_anchors: Array[Vector2i]` - Max 2 anchors
- `grid_origin: Vector2` - Centering offset
- **Important:** GridManager.position is at grid_origin

### FoldSystem (`scripts/systems/FoldSystem.gd`)
Executes fold operations.
- `execute_horizontal_fold()` - Horizontal folds
- `execute_vertical_fold()` - Vertical folds
- `validate_fold_with_player()` - Check player blocking
- MIN_FOLD_DISTANCE = 0

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
| `CLAUDE.md` (this file) | Agent onboarding, critical decisions, pitfalls |
| `docs/ARCHITECTURE.md` | Design decisions & rationale (stable) |
| `docs/DEVELOPMENT.md` | Workflow, testing, contribution guidance |
| `docs/REFERENCE.md` | Code map — pointers to source files (not signatures) |
| `docs/phases/completed/` | Historical phase specs (read-only record) |

Keep this file lean: update it only for a new critical pitfall, a major
architectural change, or a new tool/workflow. Do **not** restate test counts or
progress here — those live in `STATUS.md`.

---

## What's Next

The core folding engine (Phases 1-7) is complete: axis-aligned and diagonal
folds, multi-seam cells, and the dual undo/unfold system all work and are tested.
Remaining work is **content and polish**, not core-mechanic engineering:

- **Phase 8 – Cell Types & Visual Elements:** richer cell types, animations
- **Phase 9 – Level Management (polish):** campaign content, final integration
- **Phase 10 – Graphics/Audio (polish):** particles, seam visuals, UI/UX
- **Phase 11 – Testing & Validation:** edge cases, performance

Completed phase specs live in `docs/phases/completed/` as a historical record.
`docs/phases/pending/` is currently empty; Phases 8 and 11 do not yet have
standalone spec documents.

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
