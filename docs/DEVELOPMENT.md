# Development Workflow & Best Practices

**Purpose:** This document explains **HOW** to develop features for this project.

**Last Updated:** 2025-11-07

---

## Table of Contents

1. [Development Workflow](#development-workflow)
2. [Testing Best Practices](#testing-best-practices)
3. [Common Pitfalls](#common-pitfalls)
4. [Code Quality Standards](#code-quality-standards)
5. [Git Workflow](#git-workflow)
6. [Godot-Specific Tips](#godot-specific-tips)

---

## Development Workflow

### Starting a New Task

1. **Read current status**
   ```bash
   cat STATUS.md
   ```

2. **Read relevant phase documentation**
   ```bash
   cat docs/phases/pending/phase_X.md
   ```

3. **Verify test environment**
   ```bash
   ./run_tests.sh
   # Should see: "All tests passed" (225/225)
   ```

4. **Create feature branch** (if not already on one)
   ```bash
   git checkout -b claude/feature-name-SESSION_ID
   ```

5. **Write tests FIRST** (TDD approach)
   - Define expected behavior
   - Write failing tests
   - See tests fail (red)

6. **Implement feature**
   - Make tests pass (green)
   - Keep implementation simple

7. **Refactor if needed**
   - Improve code quality
   - Keep tests passing

8. **Commit frequently**
   ```bash
   git add .
   git commit -m "Add diagonal fold validation for edge case X"
   ```

### Completing a Task

1. **Ensure all tests pass**
   ```bash
   ./run_tests.sh
   # Must see: "All tests passed"
   ```

2. **Update STATUS.md**
   ```bash
   # Update test counts, phase status, last updated date
   vim STATUS.md
   git add STATUS.md
   git commit -m "Update STATUS.md - Feature X complete"
   ```

3. **Update phase documentation** (if needed)
   - Add implementation notes
   - Document edge cases discovered
   - Update completion status

4. **Push to remote**
   ```bash
   git push -u origin claude/feature-name-SESSION_ID
   ```

5. **Create PR** (if feature complete)
   - Clear description
   - Reference issue numbers
   - List tests added

---

## Testing Best Practices

### Test-Driven Development (TDD)

**Philosophy:** Tests define behavior, code implements behavior.

**Red-Green-Refactor Cycle:**
1. **Red:** Write failing test
2. **Green:** Write minimal code to pass
3. **Refactor:** Improve code, keep tests passing

### Test Structure

```gdscript
extends GutTest

const CELL := 64.0
var base: BaseGrid

# Setup run before each test. The kernel is pure — no nodes to free afterwards,
# which is why most suites need no after_each() at all.
func before_each():
    base = BaseGrid.from_types(Vector2i(10, 10), CELL)

# Test function - must start with "test_"
func test_fold_excises_the_strip_between_the_creases():
    # Arrange - Set up test conditions
    var f := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)

    # Act - Derive the folded state
    var state := FoldReplay.derive(base, [f])

    # Assert - Verify results
    assert_lt(state.occupied_count(), 100,
        "The excised strip should reduce the occupied position count")

    # Always include descriptive assertion messages!
```

### Test Categories

**1. Unit Tests** - Test individual functions
```gdscript
func test_point_side_of_line_returns_negative_for_left():
    var point = Vector2(0, 5)
    var line_point = Vector2(5, 5)
    var line_normal = Vector2(1, 0)

    var side = GeometryCore.point_side_of_line(point, line_point, line_normal)

    assert_lt(side, 0, "Point should be on negative side of line")
```

**2. Integration Tests** - Test multiple components together
```gdscript
func test_fold_carries_a_point_on_the_ridden_flap():
    # Tests FoldReplay + BaseFrame interaction
    var before := FoldReplay.derive_pieces(base, [])
    var f := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
    var after := FoldReplay.derive_pieces(base, [f])

    var moved = BaseFrame.transport(before, after, Vector2(8.5, 5.5) * CELL, CELL)
    assert_not_null(moved,
        "Player should shift with grid")
```

**3. Edge Case Tests** - Test boundaries and special cases
```gdscript
func test_diagonal_fold_handles_vertex_intersection():
    # Crease passes exactly through tile corners
    var f := Fold.create(0, Vector2i(3, 2), Vector2i(5, 4), CELL)

    var pieces := FoldReplay.derive_pieces(base, [f])

    # Verify no crashes and valid geometry
    for p in pieces:
        assert_gt(p.polygon.size(), 2, "every fragment is a real polygon")
```

### Common Test Assertions

```gdscript
# Equality
assert_eq(actual, expected, "message")
assert_ne(actual, not_expected, "message")

# Comparisons
assert_gt(value, threshold, "message")  # Greater than
assert_lt(value, threshold, "message")  # Less than
assert_ge(value, threshold, "message")  # Greater or equal
assert_le(value, threshold, "message")  # Less or equal

# Boolean
assert_true(condition, "message")
assert_false(condition, "message")

# Null checks
assert_null(value, "message")
assert_not_null(value, "message")

# Floating point (use for Vector2, floats)
assert_almost_eq(actual, expected, epsilon, "message")
# Example: assert_almost_eq(area, 4096.0, 0.1, "Area should be ~4096")

# Collections
assert_has(collection, item, "message")
assert_does_not_have(collection, item, "message")
```

### Robust Test Validation

Geometry bugs are quiet — a fold that loses area or scrambles identity still renders
plausibly. Assert the invariants, not just the happy path:

#### 1. Occupancy Conservation
```gdscript
func test_fold_removes_only_the_excised_strip():
    var before := FoldReplay.derive(base, []).occupied_count()

    var f := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
    var after := FoldReplay.derive(base, [f]).occupied_count()

    assert_lt(after, before, "the fold excised something")
    assert_eq(FoldReplay.derive(base, []).occupied_count(), before,
        "re-deriving without the fold restores the original occupancy exactly")
```

#### 2. Identity Tracking
```gdscript
func test_a_specific_tile_lands_where_expected():
    # base_id is stable across every fold — that is what makes riding exact.
    var bid: int = base.tile_at(Vector2i(9, 0)).base_id

    var f := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
    var state := FoldReplay.derive(base, [f])

    assert_true(state.has_base(bid), "the tile survived the fold")
    assert_eq(state.plane_pos_of_base(bid), Vector2i(7, 0),
        "and landed at the position its flap's shift implies")
```

#### 3. Fragment Integrity
```gdscript
# Every fragment must keep the invariant polygon == base_polygon + src_offset,
# which is what BaseFrame relies on. A fragment that fails it will transport
# points to the wrong place rather than erroring.
func verify_fragments_intact(base: BaseGrid, pieces: Array):
    for p in pieces:
        var rebuilt := CollisionCore.shift(p.polygon, -p.src_offset)
        assert_gt(rebuilt.size(), 2, "fragment %d kept real geometry" % p.base_id)
        assert_not_null(base.tile_by_id(p.base_id),
            "fragment %d still maps to a real base tile" % p.base_id)
```

#### 4. Geometry Validation
```gdscript
func verify_fragment_geometry(piece: FoldedPiece, min_area: float = 1.0):
    assert_gt(piece.polygon.size(), 2,
        "fragment geometry should have at least 3 vertices")

    var area := GeometryCore.polygon_area(piece.polygon)
    assert_gt(area, min_area,
        "fragment area %.1f is degenerate (min: %.1f)" % [area, min_area])
```

#### 5. Area Accounting
```gdscript
func test_fold_removes_exactly_the_strip_area():
    var area_before := _total_area(FoldReplay.derive_pieces(base, []))

    # A 4-cell-wide strip across a 10-wide grid.
    var f := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
    var area_after := _total_area(FoldReplay.derive_pieces(base, [f]))

    assert_almost_eq(area_after, area_before - (4 * 10 * CELL * CELL), 100.0,
        "area lost should equal the excised band, no more and no less")
```

### Running Tests

```bash
# Run all tests (takes ~2 seconds)
./run_tests.sh

# Run specific test file (much faster for development!)
./run_tests.sh geometry_core
./run_tests.sh world          # test_world_core, test_world_data, test_fold_world
./run_tests.sh fold           # Runs all tests matching "fold"

# Run specific test within a file (advanced)
./run_tests.sh -gtest=res://scripts/tests/test_fold_replay.gd \
    -gunit_test=test_horizontal_fold_removes_correct_cells

# Show help
./run_tests.sh --help
```

### Test Organization

Tests live in `scripts/tests/`, one `test_<subsystem>.gd` file per subsystem
(e.g. `test_geometry_core.gd`, `test_base_frame.gd`, `test_world_core.gd`). The
exception is `test_fold_world.gd`, which is scene-driven and covers integration.
List them with:

```bash
ls scripts/tests/test_*.gd
```

Counts intentionally aren't enumerated here — they drift. See STATUS.md for suite
totals.

---

## Common Pitfalls

### 1. Mutating Derived State ⚠️ MOST COMMON

**The Problem:** editing a `FoldedPiece` (or the fragment list) and expecting it to
stick.

**Symptom:** your change works for one frame and vanishes on the next fold, unfold,
region load, or subspace transition.

**Why:** derived state is rebuilt from scratch by
`FoldReplay.derive_pieces(base, folds)` on every change. Fragments are outputs, not
storage.

```gdscript
# ❌ WRONG - the next rebuild throws this away
piece.type = TileTypes.WALL

# ✅ CORRECT - change the inputs, then re-derive
folds.append(fold)
rebuild_world()

# ✅ CORRECT - persistent facts belong on the BASE grid
base.tile_at(pos).type = TileTypes.WALL
rebuild_world()
```

**Rule of thumb:** if you want it to survive, it belongs in `BaseGrid`, the fold
list, or `WorldData` — never in a derived fragment.

---

### 2. Floating Point Precision

**The Problem:** Using `==` with floats

**Symptom:** Conditions that should be true are false, vertex checks fail

**Solution:**
```gdscript
const EPSILON = 0.0001

# ❌ WRONG
if point.x == 5.0:

# ✅ CORRECT
if abs(point.x - 5.0) < EPSILON:

# For Vector2
if point.distance_to(target) < EPSILON:
```

---

### 3. Transporting Points With Crease Math

**The Problem:** moving something through a fold by classifying which side it is on
and applying that side's shift.

**Symptom:** correct for a single fold; drifts or lands in the wrong place once two
or more folds compose, and silently wrong inside subspaces.

```gdscript
# ❌ WRONG - does not compose across folds
var side := WorldCore.side_of_fold(pos, fold)
pos += WorldCore.fold_shift_for_side(side, fold, CS)

# ✅ CORRECT - exact, composes through any fold/unfold sequence
var dest = BaseFrame.transport(old_pieces, new_pieces, pos, CS)
if dest == null:
    return  # the point was folded away — decide what that means
```

`fold_shift_for_side` is a deliberate fallback for points over **void**, where there
is no fragment to ask. That is its only legitimate use.

---

### 4. Array Modifications During Iteration

**The Problem:** Modifying array while iterating over it

**Symptom:** Items skipped, crashes, undefined behavior

**Solution:**
```gdscript
# ❌ WRONG
for cell in cells:
    if condition:
        cells.erase(cell)  # Modifies array during iteration!

# ✅ CORRECT - Collect first, then modify
var cells_to_remove = []
for cell in cells:
    if condition:
        cells_to_remove.append(cell)

for cell in cells_to_remove:
    cells.erase(cell)
```

---

### 5. Switching on Tile Types

**The Problem:** hardcoding behavior per type instead of asking the registry.

**Symptom:** a new tile type is invisible to collision, or anchorable when it should
not be — because one of the ~6 sites that used to switch on the int was missed.

```gdscript
# ❌ WRONG - PIN and UNANCHORABLE_WALL fall through as walkable
if piece.type == TileTypes.WALL:
    add_collider(piece.polygon)

# ✅ CORRECT - the registry decides
if not TileTypes.is_walkable(piece.type):
    add_collider(piece.polygon)
```

Same for `TileTypes.blocks_fold()` (pins refuse to be excised),
`TileTypes.blocks_anchor()` (unanchorable tiles refuse a grip) and
`TileTypes.merge_rank()`. Adding a tile type should mean editing **one** table.

---

### 5b. Forgetting to Validate a Fold

```gdscript
# ✅ Gate the fold before applying it
if WorldCore.fold_blocked_by_tile(current_pieces, fold, CS):
    _show_flash("Something in that span refuses to fold.")
    return false
```

Anchor placement is gated separately by `WorldCore.can_anchor_at`.

---

### 6. Scene Tree Operations

**The Problem:** Incorrect node lifecycle management

**Solution:**
```gdscript
# Adding nodes
add_child(node)

# Removing nodes (doesn't free memory)
remove_child(node)

# Freeing nodes (safe deferred free)
node.queue_free()

# Correct sequence for cleanup
if node.get_parent():
    node.get_parent().remove_child(node)
node.queue_free()
```

---

### 7. Signal Connection Leaks

**The Problem:** Signals remain connected after node freed

**Solution:**
```gdscript
# Connect in _ready()
func _ready():
    button.pressed.connect(_on_button_pressed)

# Disconnect before free
func _exit_tree():
    if button.pressed.is_connected(_on_button_pressed):
        button.pressed.disconnect(_on_button_pressed)
```

---

## Code Quality Standards

### Pre-Commit Checklist

Before committing, verify:

- [ ] All tests pass (`./run_tests.sh`)
- [ ] No floating-point equality comparisons (`==` with floats)
- [ ] Nothing persistent stored in derived state (see Pitfall 1)
- [ ] Point transport goes through `BaseFrame`, not crease math (Pitfall 3)
- [ ] Per-type behavior asks `TileTypes`, not an int comparison (Pitfall 5)
- [ ] The kernel (`scripts/model/`, `scripts/utils/`) does not import `scripts/world/`
- [ ] Proper memory management (`queue_free()` for nodes)
- [ ] Comments explain "why", not "what"
- [ ] No debug print statements (or wrapped in `if DEBUG_FLAG:`)
- [ ] All new features have tests

### Variable Naming Conventions

```gdscript
# Constants - UPPER_SNAKE_CASE
const EPSILON = 0.0001
const ANCHOR_REACH = 1

# Class variables - snake_case
var grid_position: Vector2i
var cell_size: float

# Private variables - _snake_case
var _internal_state: int

# Functions - snake_case
func seam_segment():
func capture_strip():

# Classes - PascalCase
class_name BaseFrame
class_name WorldCore
```

### Comment Style

```gdscript
# ✅ GOOD - Explains WHY
# Ask the registry, not the int: PIN and UNANCHORABLE_WALL must collide too.
if not TileTypes.is_walkable(piece.type):

# ❌ BAD - Explains WHAT (code already shows this)
# Check if the piece is walkable
if not TileTypes.is_walkable(piece.type):

# ✅ GOOD - Documents complex algorithm
# Sutherland-Hodgman polygon clipping algorithm:
# For each edge of the polygon, classify vertices as inside/outside
# and generate new intersection vertices where edge crosses the line

# ✅ GOOD - Warns about edge case
# IMPORTANT: Must free existing cell to prevent memory leak
if existing_cell:
    existing_cell.queue_free()
```

### Error Handling

```gdscript
# Validate inputs
func execute_fold(anchor1: Vector2i, anchor2: Vector2i):
    if anchor1 == anchor2:
        push_error("Anchors cannot be the same position")
        return

    if not validate_fold(anchor1, anchor2):
        push_warning("Fold validation failed")
        return

# Use assertions for internal invariants
assert(cells.size() > 0, "Grid should not be empty")
assert(cell_size > 0, "Cell size must be positive")
```

---

## Git Workflow

### Branch Naming

Format: `claude/<feature-name>-<session-id>`

Example: `claude/geometric-folding-011CUu8JZwaeZU23X9zmUcTg`

### Commit Messages

```bash
# Good commit messages
git commit -m "Add diagonal fold validation for vertex intersections"
git commit -m "Fix memory leak in cell merging during horizontal folds"
git commit -m "Refactor GeometryCore.split_polygon_by_line for clarity"

# Bad commit messages
git commit -m "Fix bug"
git commit -m "WIP"
git commit -m "Updates"
```

**Format:**
- Imperative mood ("Add", "Fix", "Refactor", not "Added", "Fixed")
- Concise summary (< 72 characters)
- Reference issue number if applicable

### Committing Tests and Implementation

```bash
# Commit tests first (TDD)
git add scripts/tests/test_diagonal_fold.gd
git commit -m "Add tests for diagonal fold edge cases"

# Then commit implementation
git add scripts/model/FoldReplay.gd
git commit -m "Implement diagonal fold with Sutherland-Hodgman splitting"

# Update documentation
git add STATUS.md
git commit -m "Update STATUS.md - diagonal fold coverage"
```

### Pushing Changes

```bash
# First push (set upstream)
git push -u origin claude/feature-name-SESSION_ID

# Subsequent pushes
git push
```

---

## Godot-Specific Tips

### Node Lifecycle

```gdscript
# Initialization
func _init():
    # Constructor - called when object created
    pass

func _ready():
    # Called when node enters scene tree
    # Use for setup, signal connections
    pass

func _process(delta):
    # Called every frame
    # Use for continuous updates
    pass

func _physics_process(delta):
    # Called at fixed interval (60 FPS)
    # Use for physics, movement
    pass

func _exit_tree():
    # Called when node leaves scene tree
    # Use for cleanup, disconnect signals
    pass
```

### Finding Nodes

```gdscript
# By path (fast)
var node = get_node("Path/To/Node")
var node = $Path/To/Node  # Shorthand

# By group (slower)
var nodes = get_tree().get_nodes_in_group("enemies")

# By parent
var parent = get_parent()
var children = get_children()
```

### Signals

```gdscript
# Define signal
signal fold_executed(anchor1, anchor2)
signal cell_selected(grid_pos)

# Emit signal
fold_executed.emit(anchor1, anchor2)

# Connect signal (Godot 4 syntax)
player.goal_reached.connect(_on_goal_reached)

# Disconnect signal
player.goal_reached.disconnect(_on_goal_reached)
```

### Resource Loading

```gdscript
# Preload (compile-time)
const CELL_SCENE = preload("res://scenes/grid/Cell.tscn")

# Load (runtime)
var cell_scene = load("res://scenes/grid/Cell.tscn")

# Instantiate
var cell_instance = CELL_SCENE.instantiate()
add_child(cell_instance)
```

---

## Performance Tips

### Profiling

```gdscript
# Use built-in profiler
# Debug → Profiler → Start

# Manual timing
var start_time = Time.get_ticks_msec()
# ... operation ...
var elapsed = Time.get_ticks_msec() - start_time
print("Operation took %d ms" % elapsed)
```

### Optimization Guidelines

1. **Profile first** - Don't guess where bottlenecks are
2. **Optimize hot paths** - Focus on code that runs frequently
3. **Avoid in tight loops:**
   - Object creation (`new()`)
   - String concatenation
   - Complex calculations

4. **Use appropriate data structures:**
   - Dictionary for lookups: O(1)
   - Array for iteration: cache `size()`
   - PackedVector2Array for geometry: more efficient than Array

5. **Batch operations:**
   - Update all visuals in single pass
   - Group physics queries

---

## Debugging Tools

### Print Debugging

```gdscript
# Conditional debug prints
const DEBUG_FOLD_EXECUTION = false

if DEBUG_FOLD_EXECUTION:
    print("Fold executed: ", anchor1, " → ", anchor2)
    print("Cells removed: ", removed_cells.size())
```

### Debug Visualization

```gdscript
# Draw debug lines (in _draw())
func _draw():
    if DEBUG_SHOW_FOLD_LINES:
        draw_line(line_start, line_end, Color.RED, 2.0)
```

### Breakpoints

- Click left margin in script editor to add breakpoint
- Run in debug mode (F5)
- Inspect variables in debugger panel

---

## Documentation Maintenance

### When to Update Docs

**Update STATUS.md:**
- After completing a phase
- After adding 50+ tests
- Weekly progress check

**Update phase docs:**
- When discovering new edge cases
- When completing phase (move to completed/)
- When implementation differs from plan

**Update AGENTS.md:**
- When discovering critical pitfall
- When major architectural change made
- When new tool/workflow added

**DON'T update:**
- ARCHITECTURE.md (stable design decisions)
- REFERENCE.md (auto-generated from code)
- Completed phase docs (historical record)

---

## Quick Reference

### Running Tests
```bash
./run_tests.sh                # All tests
./run_tests.sh fold           # Tests matching "fold"
./run_tests.sh --help         # Show help
```

### Checking Test Count
```bash
grep -r "func test_" scripts/tests/ | wc -l
```

### Finding TODO Comments
```bash
grep -r "# TODO" scripts/
```

### Listing GDScript Files
```bash
find . -name "*.gd" -not -path "./addons/*"
```

---

**Remember:** When in doubt, check the tests. They're the living documentation of expected behavior!
