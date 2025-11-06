# Space-Folding Puzzle Game - Context for AI Agents

This document provides essential context for AI agents working on this project. It consolidates key information to save time and prevent common mistakes.

## Project Overview

**Name**: Space Folding Puzzle Game
**Engine**: Godot 4.3
**Language**: GDScript
**Type**: Grid-based puzzle game with unique space-folding mechanics

The game allows players to fold space by selecting two anchor points, removing the space between them, and merging the grid along arbitrary angles. This creates complex geometric puzzles.

## Current Project Status

**Last Updated**: 2025-11-06 (Post-Phase 3 Implementation)

### Completed Phases
- **Phase 1**: Project Setup & Foundation - All core geometry utilities implemented and tested ✅
- **Phase 2**: Basic Grid System - Cell and GridManager classes fully functional with anchor selection ✅
- **Phase 3**: Simple Axis-Aligned Folding - Horizontal and vertical folds with validation, animations, and overlapping merge behavior ✅
- **Phase 7**: Player Character - Grid-based movement, fold validation, goal detection, position updates during folds ✅

### Test Status
- **225 tests passing** (GeometryCore: 41, Cell: 14, GridManager: 27, FoldSystem: 63, Player: 36, FoldValidation: 32, WinCondition: 12)
- **Test Coverage**: 100% for completed phases
- **CI/CD**: GitHub Actions configured with GUT test automation
- **Pre-push hooks**: Available for local test execution

### Next Priorities
1. **Phase 4**: Geometric Folding (most complex - diagonal folds at arbitrary angles)
2. **Phase 5**: Multi-Seam Handling (cells with multiple intersecting seams)
3. **Phase 6**: Undo System (with dependency checking)

### Phase 3 Implementation Notes (CRITICAL FOR NEXT PHASES)

**Coordinate System** (MOST IMPORTANT):
- Cells store geometry in **LOCAL coordinates** (relative to GridManager's position)
- GridManager is positioned at `grid_origin` (centered on screen)
- When creating geometry: use `Vector2(grid_pos) * cell_size` (LOCAL, not world)
- Player uses **WORLD coordinates**: convert with `grid_manager.to_global(local_pos)`
- Seam lines (Line2D) are children of GridManager: use LOCAL coordinates

**Folding Behavior**:
- Cells **OVERLAP/MERGE** at anchor positions (not adjacent)
- Right/bottom anchor shifts to left/top anchor position
- `MIN_FOLD_DISTANCE = 0` - adjacent anchors are allowed
- Overlapped cells are properly freed to prevent memory leaks

**Player Integration**:
- Player shifts with grid during folds
- Both `grid_position` and world `position` updated
- Uses `grid_manager.to_global()` for coordinate conversion

**Seam Line Management**:
- Seam lines in removed regions are deleted
- Remaining seam lines shift with cells
- Positioned at center of merged cell (left/top anchor)

## Project Structure

```
/home/user/puzzle/
├── addons/
│   └── gut/                    # GUT (Godot Unit Test) v9.4.0 framework
├── assets/
│   ├── shaders/                # Visual effects for folding
│   └── sprites/                # Game graphics
├── scenes/
│   ├── main.tscn               # Main scene file
│   ├── grid/                   # Grid visualization scenes
│   ├── player/                 # Player character scenes
│   └── ui/                     # User interface scenes
├── scripts/
│   ├── core/                   # Cell, GridManager classes
│   ├── systems/                # FoldSystem, UndoManager (future)
│   ├── utils/                  # GeometryCore utility class
│   └── tests/                  # All test files (GUT framework)
├── spec_files/                 # Design documents and specifications
│   ├── claude_code_implementation_guide.md
│   ├── math_utilities_reference.md
│   ├── space_folding_design_exploration.md
│   └── test_scenarios_and_validation.md
├── tools/                      # Development tools
│   └── godot/                  # Godot 4.3 binary (compressed)
├── IMPLEMENTATION_PLAN.md      # Comprehensive 9-phase implementation plan
├── PHASE_*_ISSUES.md          # Detailed issue tracking per phase
├── README.md                   # Project documentation
├── project.godot               # Godot project configuration
├── .gutconfig.json             # GUT test configuration
├── run_tests.sh                # Script to run tests locally
└── setup-hooks.sh              # Git hooks setup script
```

## Critical Architectural Decisions

These decisions shape the entire implementation - do NOT deviate without careful consideration:

### 1. Hybrid Grid-Polygon System
- Start with simple grid cells (position + type only)
- Convert to polygon geometry ONLY when cell is split by a fold
- **Benefit**: Memory efficient, easier level creation
- **Implementation**: Cell class has `is_partial` flag and `geometry: PackedVector2Array`

### 2. Player Fold Validation Rule (CRITICAL)
**Folds are blocked if**:
- Player is in the removed region (between fold lines), OR
- Player is on a cell that would be split by the fold

**Why**: Simplifies player logic, prevents edge cases, makes gameplay intuitive

**Implementation**: Always call `validate_fold_with_player()` before executing any fold

### 3. Sutherland-Hodgman Polygon Splitting
- Industry-standard algorithm for polygon clipping
- Implemented in `GeometryCore.split_polygon_by_line()`
- Handles all edge cases reliably

### 4. Bounded Grid Model
- Folds clip at grid boundaries
- Don't create cells outside the grid
- Most intuitive for players

### 5. Tessellation for Multi-Seam Handling
- When seams intersect, subdivide cells into convex regions
- Most robust approach for complex fold scenarios

### 6. Strict Undo Ordering
- Can only undo a fold if it's the newest fold affecting ALL its cells
- Simpler than partial resolution

## Key Classes and Their Roles

### GeometryCore (`scripts/utils/GeometryCore.gd`)
**Status**: ✅ Complete (41 tests passing)

Static utility class providing all geometric calculations:
- `point_side_of_line()` - Point-line relationship
- `segment_line_intersection()` - Line segment intersection detection
- `split_polygon_by_line()` - Sutherland-Hodgman polygon splitting
- `polygon_area()` - Calculate polygon area
- `polygon_centroid()` - Calculate centroid
- `validate_polygon()` - Check for self-intersections

**Critical Constant**: `EPSILON = 0.0001` - NEVER use `==` with floats!

### Cell (`scripts/core/Cell.gd`)
**Status**: ✅ Complete (14 tests passing)

Represents a single grid cell:
```gdscript
class_name Cell extends Node2D

var grid_position: Vector2i          # Grid coordinates
var geometry: PackedVector2Array     # Initially square, becomes polygon when split
var cell_type: int = 0               # 0=empty, 1=wall, 2=water, 3=goal
var is_partial: bool = false         # True if cell has been split
var seams: Array[Seam] = []          # Seam metadata (future)
```

**Key Methods**:
- `apply_split(split_result)` - Split cell into two cells
- `get_center()` - Calculate centroid
- `add_seam(seam_data)` - Track seam information (future)

### GridManager (`scripts/core/GridManager.gd`)
**Status**: ✅ Complete (27 tests passing)

Manages the entire grid:
```gdscript
class_name GridManager extends Node2D

var grid_size := Vector2i(10, 10)    # Default 10x10 grid
var cell_size := 64.0                # 64 pixels per cell
var cells: Dictionary = {}           # Vector2i -> Cell mapping
var selected_anchors: Array[Vector2i] = []  # Max 2 anchors
var grid_origin: Vector2              # Offset for centering grid
```

**Key Methods**:
- `select_cell(grid_pos)` - Handle anchor selection (max 2)
- `get_cell_at_world_pos(pos)` - World to grid coordinate conversion
- `validate_selection()` - Check if fold can be executed
- `grid_to_world(grid_pos)` - Convert grid position to world coordinates
- `to_global(local_pos)` - Convert local coordinates to world coordinates
- `to_local(world_pos)` - Convert world coordinates to local coordinates

**Coordinate System**:
- GridManager.position is set to grid_origin (centered on screen)
- ALL child cells and seam lines use LOCAL coordinates
- Player is NOT a child, uses WORLD coordinates

### FoldSystem (`scripts/systems/FoldSystem.gd`)
**Status**: ✅ Complete (63 tests passing)

Manages all folding operations:
```gdscript
class_name FoldSystem extends Node

const MIN_FOLD_DISTANCE = 0          # Adjacent anchors allowed
var grid_manager: GridManager
var player: Player                   # Optional player reference
var seam_lines: Array[Line2D] = []   # Visual seam indicators
var fold_history: Array[Dictionary] = []
```

**Key Methods**:
- `execute_horizontal_fold(anchor1, anchor2)` - Horizontal fold (cells overlap at left anchor)
- `execute_vertical_fold(anchor1, anchor2)` - Vertical fold (cells overlap at top anchor)
- `execute_horizontal_fold_animated(...)` - With visual animations
- `execute_vertical_fold_animated(...)` - With visual animations
- `validate_fold(anchor1, anchor2)` - Check all validation rules
- `validate_fold_with_player(...)` - Check if player blocks fold

**Fold Algorithm** (Horizontal example):
1. Normalize anchors (left/right)
2. Calculate removed cells (between anchors, exclusive)
3. Remove cells from grid and free nodes
4. Remove seam lines in removed region
5. Shift cells from right_anchor onwards LEFT by shift_distance
6. For each shifted cell:
   - Update grid_position
   - Recalculate geometry using LOCAL coordinates
   - FREE any existing cell at target position (merging)
   - Update dictionary
7. Update player position if in shifted region (use to_global!)
8. Create seam line at merged position (LOCAL coordinates)
9. Record fold in history

**Critical Implementation Details**:
- Shift distance: `right_anchor.x - left_anchor.x` (full overlap)
- Geometry: Always use LOCAL coordinates (`Vector2(pos) * cell_size`)
- Player position: Always use WORLD coordinates (`to_global(local_center)`)
- Cell cleanup: Must free overlapped cells to prevent memory leaks
- Seam positioning: Center of left/top anchor (where merge happens)

## Testing Framework

### GUT (Godot Unit Test) v9.4.0

**Test Directory**: `scripts/tests/`

**Running Tests**:
```bash
# Run all tests (default)
./run_tests.sh

# Run specific test file (multiple ways)
./run_tests.sh geometry_core           # By name (with or without test_ prefix)
./run_tests.sh test_fold_system        # With test_ prefix
./run_tests.sh fold                    # Partial match (runs all tests containing "fold")

# Show help
./run_tests.sh --help

# Advanced: Pass GUT options directly
./run_tests.sh -gtest=res://scripts/tests/test_geometry_core.gd

# Command line (for CI/CD)
godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/

# In Godot Editor
# Project → Project Settings → Plugins → Enable "Gut"
# Bottom panel → GUT → Run All
```

**Notes**:
- The script automatically handles test file names (with or without `test_` prefix or `.gd` extension)
- Using partial names will run all test files containing that string (e.g., `player` runs both `test_player.gd` and `test_player_fold_validation.gd`)
- Running specific tests is much faster for development and debugging

**Test File Structure**:
```gdscript
extends GutTest

func test_something():
    assert_eq(5, 5, "Five should equal five")
    # Always include descriptive assertion messages!
```

**Common Assertions**:
- `assert_eq(a, b, msg)` - Assert equal
- `assert_ne(a, b, msg)` - Assert not equal
- `assert_gt(a, b, msg)` - Assert greater than
- `assert_lt(a, b, msg)` - Assert less than
- `assert_true(val, msg)` - Assert true
- `assert_false(val, msg)` - Assert false
- `assert_null(val, msg)` - Assert null
- `assert_not_null(val, msg)` - Assert not null
- `assert_almost_eq(a, b, epsilon, msg)` - Assert almost equal (for floats)

**CI/CD**: GitHub Actions automatically runs all tests on PRs and pushes to main

## Common Pitfalls and How to Avoid Them

### 1. Floating Point Precision
```gdscript
# ❌ WRONG - Never use == with floats
if point.x == 5.0:

# ✅ CORRECT - Always use epsilon comparison
const EPSILON = 0.0001
if abs(point.x - 5.0) < EPSILON:
```

### 2. Coordinate System Confusion (CRITICAL!)
Always be clear about which coordinate system you're using:
- **Grid coordinates** (`Vector2i`): Discrete grid positions (0-9 for 10x10 grid)
- **Local coordinates** (`Vector2`): Relative to GridManager's position (used for cell geometry and seam lines)
- **World coordinates** (`Vector2`): Absolute pixel positions in the game world (used for player position)

**CRITICAL RULES**:
```gdscript
# ❌ WRONG - Using world coordinates for cell geometry
var world_pos = grid_manager.grid_to_world(grid_pos)
cell.geometry = create_square(world_pos, size)  // Double offset!

# ✅ CORRECT - Using local coordinates for cell geometry
var local_pos = Vector2(grid_pos) * grid_manager.cell_size
cell.geometry = create_square(local_pos, size)

# ❌ WRONG - Using local coordinates for player
player.position = cell.get_center()  // Player in wrong location!

# ✅ CORRECT - Converting to world coordinates for player
player.position = grid_manager.to_global(cell.get_center())
```

**Why**: Cells and Line2D seam lines are children of GridManager, so they inherit its position. Player is NOT a child of GridManager, so it needs world coordinates.

### 3. Array Modifications During Iteration
```gdscript
# ❌ WRONG - Modifying array during iteration
for cell in cells:
    if condition:
        cells.erase(cell)  # Breaks iteration!

# ✅ CORRECT - Collect first, then modify
var cells_to_remove = []
for cell in cells:
    if condition:
        cells_to_remove.append(cell)
for cell in cells_to_remove:
    cells.erase(cell)
```

### 4. Memory Management
```gdscript
# Always properly free visual nodes
if cell.polygon_visual:
    cell.polygon_visual.queue_free()  # Don't use free() directly!
    cell.polygon_visual = null

# Clear dictionary references
cells.erase(key)  # Allows garbage collection
```

### 5. Cell Merging and Memory Leaks (CRITICAL!)
When cells shift to overlap during folds, the old cell at the target position MUST be freed:

```gdscript
# ❌ WRONG - Overwrites dictionary but leaves old cell in scene tree
grid_manager.cells.erase(old_pos)
grid_manager.cells[new_pos] = shifted_cell  // Memory leak!

# ✅ CORRECT - Free old cell before assigning new one
grid_manager.cells.erase(old_pos)

var existing_cell = grid_manager.cells.get(new_pos)
if existing_cell:
    grid_manager.cells.erase(new_pos)
    if existing_cell.get_parent():
        existing_cell.get_parent().remove_child(existing_cell)
    existing_cell.queue_free()

grid_manager.cells[new_pos] = shifted_cell
```

**Why**: Dictionary assignment doesn't free Node2D objects. Old cells accumulate in scene tree.

### 6. Writing Tests Before Implementation
**Required**: Always write tests for new features BEFORE implementing them (TDD approach)
- Tests define the expected behavior
- Tests catch regressions
- 100% test coverage is the goal

## Development Workflow

### Git Branch Strategy
- Feature branches follow pattern: `claude/<feature-name>-<session-id>`
- Always push to the designated feature branch
- Never push to `main` directly
- PRs automatically trigger CI tests

### When Adding New Features

1. **Write tests first** (TDD approach)
   - Define expected behavior in test
   - Run test (should fail)

2. **Implement feature**
   - Make test pass
   - Keep implementation simple

3. **Verify**
   - All tests pass (`./run_tests.sh`)
   - No geometry validation errors

4. **Commit and push**
   - Clear, descriptive commit messages
   - Reference issue numbers if applicable

### Pre-Commit Checklist
- [ ] All tests pass locally
- [ ] No floating-point equality comparisons (`==`)
- [ ] Proper memory management (`.queue_free()` for nodes)
- [ ] Clear, descriptive variable names
- [ ] Comments explain "why", not "what"

## Configuration Files

### `.gutconfig.json`
GUT test framework configuration - already configured correctly

### `project.godot`
Godot project settings:
- Viewport: 1280x720
- Renderer: Forward Plus
- MSAA 2D enabled
- Texture filter: Nearest (pixelated look)

### `.github/workflows/gut-tests.yml`
CI/CD configuration - runs on every PR and push to main

## Important Documentation Files

Read these when working on specific features:

1. **IMPLEMENTATION_PLAN.md** - Comprehensive 9-phase plan with all details
2. **AGENT_TASK_DELEGATION.md** - Task breakdown and delegation guide for AI agents working on this project
3. **spec_files/claude_code_implementation_guide.md** - Stage-by-stage implementation guide
4. **spec_files/math_utilities_reference.md** - Mathematical algorithms and formulas
5. **spec_files/space_folding_design_exploration.md** - Design decisions and rationale
6. **spec_files/test_scenarios_and_validation.md** - Comprehensive test scenarios

## Quick Reference Commands

```bash
# Run all tests
./run_tests.sh

# Run specific test file (fast - recommended for development)
./run_tests.sh geometry_core           # Run test_geometry_core.gd
./run_tests.sh fold_system             # Run test_fold_system.gd
./run_tests.sh player                  # Run all tests with "player" in filename

# Show test runner help
./run_tests.sh --help

# Run tests in Docker (CI environment)
docker run --rm -v $(pwd):/workspace -w /workspace \
  barichello/godot-ci:4.3 \
  bash -c "godot --headless --import --quit && \
           godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/ -gexit"

# Setup git hooks (optional but recommended)
./setup-hooks.sh

# List all .gd files
find . -name "*.gd" -not -path "./addons/*"

# Advanced: Run specific test file with Godot directly
godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/tests/test_example.gd
```

## Phase-Specific Notes

### Phase 3: Simple Axis-Aligned Folding ✅ COMPLETE
**Status**: Fully implemented and tested (63 tests passing)

**Key Implementations**:
- `FoldSystem` class with horizontal and vertical folds
- Player position validation and shifting during folds
- Animated and non-animated fold variants
- Seam line creation, removal, and shifting
- Overlapping/merging behavior at anchors
- Memory-safe cell cleanup during merges

**Key Files**:
- `scripts/systems/FoldSystem.gd` - Complete fold implementation
- `scripts/tests/test_fold_system.gd` - 63 passing tests
- `scripts/tests/test_fold_validation.gd` - 32 passing tests

**Critical Lessons Learned**:
1. **Coordinate Systems**: LOCAL for cells/seams (children of GridManager), WORLD for player
2. **Cell Merging**: Always free overlapped cells to prevent memory leaks
3. **Player Shifting**: Update both grid_position and world position during folds
4. **Seam Management**: Remove seams in deleted regions, shift remaining seams

### Phase 4: Geometric Folding (Next Priority)
**Warning**: This is the most complex phase (6-8 hours estimated)
- Arbitrary angle folds
- Cell polygon splitting using `GeometryCore.split_polygon_by_line()`
- Many edge cases (vertex intersections, near-parallel cuts, boundary conditions)
- Requires extensive testing

**Prerequisites**: Phase 3 is solid ✅

**Key Considerations for Phase 4**:
- Coordinate system: ALL geometry operations must use LOCAL coordinates
- When splitting cells, new geometry is still in LOCAL coordinates
- Player position updates will need `to_global()` conversion
- Seam lines at arbitrary angles: still use LOCAL coordinates for Line2D points
- Overlapped cell cleanup: same pattern as Phase 3

### Phase 7: Player Character (Recommended Before Phase 4)
**Why Before Phase 4**: Testing gameplay feel early is valuable
- Grid-based movement (one cell at a time)
- Arrow keys or WASD
- Collision with walls
- Fold validation with player position

## Design Principles

1. **Test-Driven Development**: Write tests before implementation
2. **Simplicity First**: Start with simple cases, add complexity gradually
3. **Clear Separation**: Core logic in `/core`, systems in `/systems`, utilities in `/utils`
4. **Explicit Over Implicit**: Clear variable names, descriptive comments
5. **Fail Fast**: Validate inputs early, use assertions liberally
6. **Memory Safety**: Always use `queue_free()` for nodes, clear references

## Anti-Patterns to Avoid

1. ❌ Implementing features without tests
2. ❌ Using `==` for float comparisons
3. ❌ Modifying arrays during iteration
4. ❌ Calling `free()` directly on nodes (use `queue_free()`)
5. ❌ **Mixing coordinate systems without conversion** (MOST COMMON BUG!)
   - Using world coordinates for cell geometry (causes double offset)
   - Using local coordinates for player position (causes wrong location)
   - Always verify: "Is this node a child of GridManager?"
6. ❌ Skipping validation (player position, fold boundaries, etc.)
7. ❌ Creating cells outside grid boundaries
8. ❌ Assuming square cells (they become polygons when split!)
9. ❌ **Overwriting dictionary entries without freeing old nodes** (memory leak!)
10. ❌ Forgetting to update player position during grid transformations

## Godot-Specific Gotchas

### Node Lifecycle
- Use `_ready()` for initialization
- Use `_process(delta)` for per-frame updates
- Use `_physics_process(delta)` for physics
- Always call `super._ready()` when overriding

### Signal Connections
```gdscript
# Connect signals in _ready()
signal_name.connect(callable_method)

# Disconnect when cleaning up
if signal_name.is_connected(callable_method):
    signal_name.disconnect(callable_method)
```

### Scene Tree Operations
```gdscript
# Adding nodes
add_child(node)

# Removing nodes
remove_child(node)  # Doesn't free memory
node.queue_free()   # Frees memory at end of frame

# Finding nodes
get_node("NodeName")
$NodeName  # Shorthand
```

## Performance Considerations

Current targets (for 10x10 grid):
- Fold operation: < 100ms
- Animation: 60 FPS
- Memory: < 50MB

For larger grids (future):
- Consider spatial partitioning (quadtree)
- Pre-calculate cell centroids
- Use object pooling for split cells
- Batch visual updates

## Contact Points and Resources

- **GUT Documentation**: https://gut.readthedocs.io/
- **Godot 4 Documentation**: https://docs.godotengine.org/
- **GitHub Repository**: https://github.com/absent-mynd/puzzle
- **CI/CD Dashboard**: GitHub Actions tab

## Version History

- **2025-11-06**: Phase 1, 2, 3, 7 complete, 225 tests passing
- **2025-11-05**: Phase 1 & 2 complete, 91 tests passing
- **Project Start**: TDD approach, comprehensive specification

---

**Remember**: When in doubt, check the existing tests! They demonstrate how the implemented features work and serve as living documentation.
