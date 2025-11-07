# Space-Folding Puzzle Game - AI Agent Guide

**START HERE** - Essential context for AI agents working on this project.

**Last Updated:** 2025-11-07
**Current Phase:** Phase 4 (Geometric Folding) - NEXT CRITICAL PRIORITY

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
- ✅ Phase 7: Player Character (movement, validation, goal detection)

**Tests Passing:** 225 (GeometryCore: 41, Cell: 14, GridManager: 27, FoldSystem: 63, Player: 36, FoldValidation: 32, WinCondition: 12)

**Next Priority:** Phase 4 - Geometric Folding (diagonal folds at arbitrary angles)

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

### 5. Other Key Decisions
- **Sutherland-Hodgman** for polygon splitting (industry standard)
- **Bounded Grid Model** - folds clip at boundaries
- **Tessellation** for multi-seam handling (subdivide into convex regions)
- **Strict Undo Ordering** - can only undo newest fold affecting all its cells

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for detailed rationale.

---

## Project Structure

```
/home/user/puzzle/
├── GUIDE.md                     # ← YOU ARE HERE - Start here!
├── STATUS.md                    # Current progress (update frequently)
├── README.md                    # Public-facing project info
│
├── docs/                        # Reference documentation
│   ├── ARCHITECTURE.md          # Design decisions (why)
│   ├── DEVELOPMENT.md           # Development workflow (how)
│   ├── REFERENCE.md             # API reference (what)
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
- `split_polygon_by_line()` - Sutherland-Hodgman algorithm
- `point_side_of_line()` - Point-line relationship
- `segment_line_intersection()` - Line intersection
- **EPSILON = 0.0001** - Never use `==` with floats!

### Cell (`scripts/core/Cell.gd`)
Represents a grid cell.
- `grid_position: Vector2i` - Grid coordinates
- `geometry: PackedVector2Array` - Polygon vertices (LOCAL coords)
- `cell_type: int` - 0=empty, 1=wall, 2=water, 3=goal
- `is_partial: bool` - True if split by fold

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
# Run all tests (default)
./run_tests.sh

# Run specific test file
./run_tests.sh geometry_core     # Partial match
./run_tests.sh test_fold_system  # Full name
./run_tests.sh fold              # Runs all tests with "fold"

# Show help
./run_tests.sh --help
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

**Target:** 100% test coverage for all features

See **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** for testing best practices.

---

## Development Workflow

### Starting a Task

1. **Check current status:** Read `STATUS.md`
2. **Read phase documentation:** `docs/phases/pending/phase_X.md`
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

**Current Branch:** `claude/condense-context-011CUu8JZwaeZU23X9zmUcTg`

**Committing Changes:**
```bash
# Stage changes
git add .

# Commit with descriptive message
git commit -m "Add geometric folding validation for diagonal cuts"

# Push to feature branch
git push -u origin claude/condense-context-011CUu8JZwaeZU23X9zmUcTg
```

**Creating Pull Requests:** See git operations section in main instructions.

---

## Documentation Maintenance

### When to Update Documentation

**Update STATUS.md after:**
- Completing a phase
- Significant milestone (e.g., 50+ tests added)
- Major feature implementation
- Weekly progress check

**Update phase docs when:**
- Discovering new edge cases
- Finding critical implementation details
- Completing phase (move to `completed/`)

**Update GUIDE.md ONLY when:**
- New critical pitfall discovered
- Major architectural change
- New tool or workflow added

**Don't update:**
- `docs/ARCHITECTURE.md` (stable design decisions)
- `docs/REFERENCE.md` (extract from code, not manually edited)
- Completed phase docs (historical record)

### How to Update STATUS.md

```bash
# 1. Count current tests
grep -r "func test_" scripts/tests/ | wc -l

# 2. Edit STATUS.md
# - Update test counts by category
# - Update "Last Updated" date
# - Move completed phases to "Completed" section
# - Update "Next Priority"

# 3. Commit
git commit -m "Update STATUS.md - Phase X complete, Y tests passing"
```

---

## Phase 4 Preview (Next Critical Task)

**Phase 4: Geometric Folding** is the most complex phase (6-8 hours estimated).

**Key Challenge:** Diagonal folds at arbitrary angles with cell polygon splitting.

**Critical Points:**
- ALL geometry operations MUST use LOCAL coordinates
- Apply Phase 3 lessons (coordinate system, cell merging, player validation)
- Extensive edge case testing required

**Before starting Phase 4:**
1. Read `docs/phases/pending/phase_4.md` thoroughly
2. Review `GeometryCore.split_polygon_by_line()` implementation
3. Understand coordinate system (LOCAL vs WORLD)
4. Review Phase 3 fold algorithm

See **[docs/phases/pending/phase_4.md](docs/phases/pending/phase_4.md)** for complete details.

---

## Quick Reference Commands

```bash
# Run all tests
./run_tests.sh

# Run specific test file
./run_tests.sh geometry_core

# Check test count
grep -r "func test_" scripts/tests/ | wc -l

# List all GDScript files
find . -name "*.gd" -not -path "./addons/*"

# Check git status
git status

# Update STATUS.md test count
vim STATUS.md  # Update test counts manually
```

---

## Getting Help

**Documentation:**
- Stuck on concepts? → `docs/ARCHITECTURE.md`
- Need API reference? → `docs/REFERENCE.md`
- Testing questions? → `docs/DEVELOPMENT.md`
- Phase-specific? → `docs/phases/`

**Code Examples:**
- Check existing tests in `scripts/tests/`
- Review completed phases in `scripts/core/` and `scripts/systems/`

**Resources:**
- [GUT Documentation](https://gut.readthedocs.io/)
- [Godot 4 Documentation](https://docs.godotengine.org/)

---

## Summary

**Remember:**
1. **Read STATUS.md first** - know what's done and what's next
2. **Write tests before code** - TDD approach prevents bugs
3. **Use LOCAL coordinates for cells** - most common bug!
4. **Free overlapped cells** - prevent memory leaks
5. **Update STATUS.md after milestones** - keep progress tracked

**Most Critical Knowledge:**
- Coordinate system: LOCAL for cells, WORLD for player
- Player validation: blocks folds that affect player
- Cell merging: always free old cells
- Testing: 100% coverage target

**Next Steps:**
1. Read [STATUS.md](STATUS.md) for current progress
2. Read [docs/phases/pending/phase_4.md](docs/phases/pending/phase_4.md) for next task
3. Run `./run_tests.sh` to verify environment
4. Start implementing with TDD approach

---

**Good luck, and remember: when in doubt, check the tests - they're living documentation!**
