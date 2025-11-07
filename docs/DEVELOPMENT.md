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

# Setup run before each test
func before_each():
    grid_manager = GridManager.new()
    grid_manager.initialize(Vector2i(10, 10), 64.0)

# Teardown run after each test
func after_each():
    if grid_manager:
        grid_manager.queue_free()

# Test function - must start with "test_"
func test_horizontal_fold_removes_correct_cells():
    # Arrange - Set up test conditions
    var anchor1 = Vector2i(2, 5)
    var anchor2 = Vector2i(6, 5)

    # Act - Execute the operation
    fold_system.execute_horizontal_fold(anchor1, anchor2)

    # Assert - Verify results
    assert_eq(grid_manager.cells.size(), 96,
        "Expected 96 cells after removing 4 cells")

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
func test_fold_updates_player_position():
    # Tests FoldSystem + GridManager + Player interaction
    player.set_grid_position(Vector2i(8, 5))
    fold_system.execute_horizontal_fold(Vector2i(2, 5), Vector2i(6, 5))

    assert_eq(player.grid_position, Vector2i(4, 5),
        "Player should shift with grid")
```

**3. Edge Case Tests** - Test boundaries and special cases
```gdscript
func test_fold_handles_vertex_intersection():
    # Fold line passes exactly through cell corner
    var anchor1 = Vector2i(3, 2)
    var anchor2 = Vector2i(5, 4)  # Diagonal

    var result = fold_system.execute_diagonal_fold(anchor1, anchor2)

    # Verify no crashes, valid geometry
    assert_true(result.success)
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

Based on lessons learned from the "disappearing cells" bug, always validate:

#### 1. Cell Count Conservation
```gdscript
func test_fold_preserves_cell_count():
    var cells_before = grid_manager.cells.size()
    var expected_removed = 12

    fold_system.execute_fold(anchor1, anchor2)

    var cells_after = grid_manager.cells.size()
    assert_eq(cells_after, cells_before - expected_removed,
        "Expected %d cells after fold, got %d (lost %d cells)" %
        [cells_before - expected_removed, cells_after, cells_before - cells_after])
```

#### 2. Cell Identity Tracking
```gdscript
func test_specific_cell_shifts_to_correct_position():
    # Mark cell with unique identifier
    var cell_9_0 = grid_manager.get_cell(Vector2i(9, 0))
    cell_9_0.cell_type = 900  # Unique ID

    fold_system.execute_fold(anchor1, anchor2)

    # Verify CORRECT cell at destination
    var cell_7_2 = grid_manager.get_cell(Vector2i(7, 2))
    assert_not_null(cell_7_2, "Cell should exist at (7,2)")
    assert_eq(cell_7_2.cell_type, 900,
        "Cell at (7,2) should be the one from (9,0)")
```

#### 3. No Freed Instances
```gdscript
func verify_no_freed_cells(grid_manager: GridManager):
    for pos in grid_manager.cells.keys():
        var cell = grid_manager.cells[pos]
        assert_true(is_instance_valid(cell),
            "Cell at %s is freed but still in dictionary!" % pos)
```

#### 4. Geometry Validation
```gdscript
func verify_cell_geometry(cell: Cell, min_area: float = 100.0):
    assert_not_null(cell.geometry, "Cell should have geometry")
    assert_gt(cell.geometry.size(), 2,
        "Cell geometry should have at least 3 vertices")

    var area = GeometryCore.polygon_area(cell.geometry)
    assert_gt(area, min_area,
        "Cell area %.1f is too small (min: %.1f)" % [area, min_area])
```

#### 5. Total Area Conservation
```gdscript
func test_fold_conserves_total_area():
    var area_before = calculate_total_area(grid_manager)

    fold_system.execute_fold(anchor1, anchor2)

    var area_after = calculate_total_area(grid_manager)
    var expected_removed_area = 12 * 64 * 64  # 12 cells removed

    assert_almost_eq(area_after, area_before - expected_removed_area, 100.0,
        "Total area mismatch: before=%.1f, after=%.1f" % [area_before, area_after])
```

### Running Tests

```bash
# Run all tests (takes ~8 seconds)
./run_tests.sh

# Run specific test file (much faster for development!)
./run_tests.sh geometry_core
./run_tests.sh test_fold_system
./run_tests.sh fold  # Runs all tests matching "fold"

# Run specific test within a file (advanced)
./run_tests.sh -gtest=res://scripts/tests/test_fold_system.gd \
    -gunit_test=test_horizontal_fold_removes_correct_cells

# Show help
./run_tests.sh --help
```

### Test Organization

```
scripts/tests/
├── test_geometry_core.gd      # GeometryCore utility tests (41 tests)
├── test_cell.gd                # Cell class tests (14 tests)
├── test_grid_manager.gd        # GridManager tests (27 tests)
├── test_fold_system.gd         # FoldSystem tests (63 tests)
├── test_fold_validation.gd     # Fold validation tests (32 tests)
├── test_player.gd              # Player movement tests (36 tests)
└── test_win_condition.gd       # Win condition tests (12 tests)
```

---

## Common Pitfalls

### 1. Coordinate System Confusion ⚠️ MOST COMMON

**The Problem:** Mixing LOCAL and WORLD coordinates

**Symptom:** Cells appear at wrong positions, double offsets, player in wrong location

**Solution:**
```gdscript
# ❌ WRONG - Using world coordinates for cell geometry
var world_pos = grid_manager.grid_to_world(grid_pos)
cell.geometry = create_square(world_pos, size)
# Result: Cell at grid_origin + grid_origin!

# ✅ CORRECT - Use local coordinates for cells
var local_pos = Vector2(grid_pos) * grid_manager.cell_size
cell.geometry = create_square(local_pos, size)
# Result: Cell at correct position relative to GridManager

# ✅ CORRECT - Use world coordinates for player
player.position = grid_manager.to_global(local_center)
# Result: Player at correct world position
```

**Rule of Thumb:**
- Cells are children of GridManager → LOCAL coordinates
- Player is NOT a child → WORLD coordinates
- Line2D seams are children of GridManager → LOCAL coordinates

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

### 3. Memory Leaks (Cell Merging)

**The Problem:** Overwriting dictionary entries without freeing old nodes

**Symptom:** Memory usage grows, nodes accumulate in scene tree, performance degrades

**Solution:**
```gdscript
# ❌ WRONG - Old cell still in scene tree
cells[new_pos] = shifted_cell

# ✅ CORRECT - Free old cell first
var existing_cell = cells.get(new_pos)
if existing_cell:
    cells.erase(new_pos)
    if existing_cell.get_parent():
        existing_cell.get_parent().remove_child(existing_cell)
    existing_cell.queue_free()

cells[new_pos] = shifted_cell
```

**Always:**
- Use `queue_free()` not `free()` (defers until safe)
- Remove from parent before freeing
- Erase from dictionaries

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

### 5. Forgetting to Validate

**The Problem:** Skipping validation before fold

**Symptom:** Player on split cell, folds create invalid states

**Solution:**
```gdscript
# ❌ WRONG - No validation
fold_system.execute_fold(anchor1, anchor2)

# ✅ CORRECT - Always validate first
if not fold_system.validate_fold(anchor1, anchor2):
    return

if player and not fold_system.validate_fold_with_player(anchor1, anchor2, player):
    show_error_message("Cannot fold - player in the way")
    return

fold_system.execute_fold(anchor1, anchor2)
```

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
- [ ] Proper memory management (`queue_free()` for nodes)
- [ ] Clear, descriptive variable names
- [ ] Comments explain "why", not "what"
- [ ] No debug print statements (or wrapped in `if DEBUG_FLAG:`)
- [ ] Coordinate system used correctly (LOCAL vs WORLD)
- [ ] All new features have tests

### Variable Naming Conventions

```gdscript
# Constants - UPPER_SNAKE_CASE
const EPSILON = 0.0001
const MIN_FOLD_DISTANCE = 0

# Class variables - snake_case
var grid_position: Vector2i
var cell_size: float

# Private variables - _snake_case
var _internal_state: int

# Functions - snake_case
func calculate_fold_line():
func execute_horizontal_fold():

# Classes - PascalCase
class_name GridManager
class_name FoldSystem
```

### Comment Style

```gdscript
# ✅ GOOD - Explains WHY
# Use local coordinates because cells are children of GridManager
var local_pos = Vector2(grid_pos) * cell_size

# ❌ BAD - Explains WHAT (code already shows this)
# Calculate local position
var local_pos = Vector2(grid_pos) * cell_size

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
git add scripts/systems/FoldSystem.gd
git commit -m "Implement diagonal fold with Sutherland-Hodgman splitting"

# Update documentation
git add STATUS.md
git commit -m "Update STATUS.md - Phase 4 tests complete"
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
fold_system.fold_executed.connect(_on_fold_executed)

# Disconnect signal
fold_system.fold_executed.disconnect(_on_fold_executed)
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

**Update GUIDE.md:**
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
