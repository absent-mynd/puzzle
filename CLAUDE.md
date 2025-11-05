# Space-Folding Puzzle Game - Context for AI Agents

This document provides essential context for AI agents working on this project. It consolidates key information to save time and prevent common mistakes.

## Project Overview

**Name**: Space Folding Puzzle Game
**Engine**: Godot 4.3
**Language**: GDScript
**Type**: Grid-based puzzle game with unique space-folding mechanics

The game allows players to fold space by selecting two anchor points, removing the space between them, and merging the grid along arbitrary angles. This creates complex geometric puzzles.

## Current Project Status

**Last Updated**: 2025-11-05

### Completed Phases
- **Phase 1**: Project Setup & Foundation - All core geometry utilities implemented and tested ✅
- **Phase 2**: Basic Grid System - Cell and GridManager classes fully functional with anchor selection ✅

### Test Status
- **91 tests passing** (GeometryCore: 41, Cell: 14, GridManager: 27, Examples: 9)
- **Test Coverage**: 100% for completed phases
- **CI/CD**: GitHub Actions configured with GUT test automation
- **Pre-push hooks**: Available for local test execution

### Next Priorities
1. **Phase 3**: Simple Axis-Aligned Folding (horizontal/vertical folds)
2. **Phase 7**: Player Character (recommended before complex geometric folding)
3. **Phase 4**: Geometric Folding (most complex - diagonal folds at arbitrary angles)

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
```

**Key Methods**:
- `select_cell(grid_pos)` - Handle anchor selection (max 2)
- `get_cell_at_world_pos(pos)` - World to grid coordinate conversion
- `validate_selection()` - Check if fold can be executed

## Testing Framework

### GUT (Godot Unit Test) v9.4.0

**Test Directory**: `scripts/tests/`

**Running Tests**:
```bash
# Command line (preferred for CI/CD)
godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/

# With script
./run_tests.sh

# In Godot Editor
# Project → Project Settings → Plugins → Enable "Gut"
# Bottom panel → GUT → Run All
```

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

### 2. Coordinate System Confusion
Always be clear about which coordinate system you're using:
- **Grid coordinates** (`Vector2i`): Discrete grid positions (0-9 for 10x10 grid)
- **World coordinates** (`Vector2`): Pixel positions in the game world
- **Local cell coordinates** (`Vector2`): Relative to cell's position

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

### 5. Writing Tests Before Implementation
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
2. **spec_files/claude_code_implementation_guide.md** - Stage-by-stage implementation guide
3. **spec_files/math_utilities_reference.md** - Mathematical algorithms and formulas
4. **spec_files/space_folding_design_exploration.md** - Design decisions and rationale
5. **spec_files/test_scenarios_and_validation.md** - Comprehensive test scenarios

## Quick Reference Commands

```bash
# Run all tests
./run_tests.sh

# Run tests in Docker (CI environment)
docker run --rm -v $(pwd):/workspace -w /workspace \
  barichello/godot-ci:4.3 \
  bash -c "godot --headless --import --quit && \
           godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/ -gexit"

# Setup git hooks (optional but recommended)
./setup-hooks.sh

# List all .gd files
find . -name "*.gd" -not -path "./addons/*"

# Run specific test file
godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/tests/test_example.gd
```

## Phase-Specific Notes

### Phase 3: Simple Axis-Aligned Folding (Next Up)
**Focus**: Horizontal and vertical folds only
- Implement `FoldSystem` class
- Validate with player position (CRITICAL)
- Add visual feedback (preview lines, animations)
- Store fold operations for future undo system

**Key File**: `scripts/systems/FoldSystem.gd` (to be created)

### Phase 4: Geometric Folding (Most Complex)
**Warning**: This is the most complex phase (6-8 hours estimated)
- Arbitrary angle folds
- Cell polygon splitting using `GeometryCore.split_polygon_by_line()`
- Many edge cases (vertex intersections, near-parallel cuts, boundary conditions)
- Requires extensive testing

**Do NOT start Phase 4 until Phase 3 is completely solid**

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
5. ❌ Mixing coordinate systems without conversion
6. ❌ Skipping validation (player position, fold boundaries, etc.)
7. ❌ Creating cells outside grid boundaries
8. ❌ Assuming square cells (they become polygons when split!)

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

- **2025-11-05**: Phase 1 & 2 complete, 91 tests passing
- **Project Start**: TDD approach, comprehensive specification

---

**Remember**: When in doubt, check the existing tests! They demonstrate how the implemented features work and serve as living documentation.
