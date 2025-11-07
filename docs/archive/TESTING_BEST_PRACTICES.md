# Testing Best Practices for Fold Operations

This document outlines testing strategies to catch bugs like the "disappearing cells" issue that slipped through our test suite.

## The Bug That Escaped

**Symptom**: Cell (9,0) should have moved to (7,2) but position (7,2) ended up empty.
**Why Tests Missed It**: Tests only checked if cells existed at certain positions, not whether they were the CORRECT cells.

## Test Robustness Checklist

### 1. Cell Count Conservation ✅

**Always assert on total cell count:**

```gdscript
var cells_before = grid_manager.cells.size()
var expected_removed = 12  # Number of cells in removed region

fold_system.execute_diagonal_fold(anchor1, anchor2)

var cells_after = grid_manager.cells.size()
var expected_after = cells_before - expected_removed

# CRITICAL: Assert the count
assert_eq(cells_after, expected_after,
    "Expected %d cells after fold, got %d (lost %d cells)" %
    [expected_after, cells_after, cells_before - cells_after])
```

**Why**: If cells disappear during shifts/merges, count will be wrong.

### 2. Cell Identity Tracking ✅

**Mark cells with unique identifiers to track their journey:**

```gdscript
# Before fold: Mark cells with their original position
for pos in grid_manager.cells.keys():
    var cell = grid_manager.get_cell(pos)
    cell.cell_type = pos.x * 100 + pos.y  # Unique ID per cell

# Execute fold
fold_system.execute_diagonal_fold(anchor1, anchor2)

# After fold: Verify specific cell ended up at expected position
var cell_at_7_2 = grid_manager.get_cell(Vector2i(7, 2))
assert_not_null(cell_at_7_2, "Cell should exist at (7,2)")
assert_eq(cell_at_7_2.cell_type, 900,
    "Cell at (7,2) should be the one originally from (9,0), but is from (%d,%d)" %
    [cell_at_7_2.cell_type / 100, cell_at_7_2.cell_type % 100])
```

**Why**: Ensures the RIGHT cell ends up at each position, not just ANY cell.

### 3. No Freed Instances in Dictionary ✅

**Check for freed/invalid cell references:**

```gdscript
func verify_no_freed_cells(grid_manager: GridManager):
    var freed_count = 0
    var freed_positions = []

    for pos in grid_manager.cells.keys():
        var cell = grid_manager.cells[pos]
        if not is_instance_valid(cell):
            freed_count += 1
            freed_positions.append(pos)

    assert_eq(freed_count, 0,
        "Found %d freed cell references at positions: %s" %
        [freed_count, freed_positions])

# After every fold:
fold_system.execute_diagonal_fold(anchor1, anchor2)
verify_no_freed_cells(grid_manager)
```

**Why**: Catches memory leaks and dangling references immediately.

### 4. Geometry Validation ✅

**Verify cells have valid, non-empty geometry:**

```gdscript
func verify_cell_geometry(cell: Cell, min_area: float = 100.0):
    assert_not_null(cell.geometry, "Cell should have geometry")
    assert_gt(cell.geometry.size(), 2,
        "Cell geometry should have at least 3 vertices")

    var area = GeometryCore.polygon_area(cell.geometry)
    assert_gt(area, min_area,
        "Cell area %.1f is too small (min: %.1f)" % [area, min_area])

    # Check for degenerate geometry (all points on a line)
    var centroid = GeometryCore.polygon_centroid(cell.geometry)
    assert_not_null(centroid, "Cell should have valid centroid")

# After fold, check all cells:
for pos in grid_manager.cells.keys():
    var cell = grid_manager.get_cell(pos)
    verify_cell_geometry(cell)
```

**Why**: Catches cases where cells have empty or degenerate geometry.

### 5. Total Area Conservation ✅

**For operations that don't change total area:**

```gdscript
func calculate_total_area(grid_manager: GridManager) -> float:
    var total = 0.0
    for cell in grid_manager.cells.values():
        if is_instance_valid(cell):
            total += GeometryCore.polygon_area(cell.geometry)
    return total

var area_before = calculate_total_area(grid_manager)
fold_system.execute_diagonal_fold(anchor1, anchor2)
var area_after = calculate_total_area(grid_manager)

# Splits and merges shouldn't change total area
assert_almost_eq(area_before, area_after, 10.0,
    "Total area changed: %.1f → %.1f" % [area_before, area_after])
```

**Why**: Ensures geometry isn't being lost during splits/merges/shifts.

### 6. Grid Bounds Consistency ✅

**Verify grid doesn't shrink unexpectedly:**

```gdscript
func get_grid_bounds(grid_manager: GridManager) -> Dictionary:
    var min_x = INF
    var max_x = -INF
    var min_y = INF
    var max_y = -INF

    for pos in grid_manager.cells.keys():
        min_x = min(min_x, pos.x)
        max_x = max(max_x, pos.x)
        min_y = min(min_y, pos.y)
        max_y = max(max_y, pos.y)

    return {
        "min_x": min_x, "max_x": max_x,
        "min_y": min_y, "max_y": max_y,
        "width": max_x - min_x + 1,
        "height": max_y - min_y + 1
    }

var bounds_before = get_grid_bounds(grid_manager)
fold_system.execute_diagonal_fold(anchor1, anchor2)
var bounds_after = get_grid_bounds(grid_manager)

# Grid shouldn't shrink (can expand)
assert_ge(bounds_after.width, bounds_before.width - 5,  # Allow some shrinkage
    "Grid width decreased more than expected")
```

**Why**: Detects when cells disappear from grid edges.

### 7. Shift Verification ✅

**For cells known to shift, verify they moved correctly:**

```gdscript
# Before fold: Record which cells should shift
var cells_that_should_shift = []
var expected_destinations = {}

# Mark cells (9,0), (8,0), etc. as shifting
for pos in [(9,0), (8,0), (7,0)]:
    var cell = grid_manager.get_cell(Vector2i(pos[0], pos[1]))
    if cell:
        cells_that_should_shift.append(cell)
        # With shift (-2, 2), calculate expected destination
        expected_destinations[cell] = Vector2i(pos[0] - 2, pos[1] + 2)

# Execute fold
fold_system.execute_diagonal_fold(anchor1, anchor2)

# Verify each cell ended up at expected destination
for cell in cells_that_should_shift:
    var expected_pos = expected_destinations[cell]
    var cell_at_dest = grid_manager.get_cell(expected_pos)

    assert_not_null(cell_at_dest,
        "Expected cell at %s but found none" % expected_pos)
    assert_eq(cell, cell_at_dest,
        "Wrong cell at %s" % expected_pos)
```

**Why**: Directly verifies shift logic works correctly.

## Example: Comprehensive Fold Test

```gdscript
func test_diagonal_fold_comprehensive():
    # Setup
    var anchor1 = Vector2i(3, 2)
    var anchor2 = Vector2i(5, 0)

    # 1. Record initial state
    var cells_before = grid_manager.cells.size()
    var area_before = calculate_total_area(grid_manager)
    var bounds_before = get_grid_bounds(grid_manager)

    # 2. Mark cells for identity tracking
    mark_cells_with_original_positions(grid_manager)

    # 3. Execute fold
    fold_system.execute_diagonal_fold(anchor1, anchor2)

    # 4. Cell count validation
    var cells_after = grid_manager.cells.size()
    var expected_removed = 12  # Based on classification
    assert_eq(cells_after, cells_before - expected_removed,
        "Cell count mismatch")

    # 5. No freed instances
    verify_no_freed_cells(grid_manager)

    # 6. Geometry validation
    for pos in grid_manager.cells.keys():
        var cell = grid_manager.get_cell(pos)
        verify_cell_geometry(cell)

    # 7. Area conservation
    var area_after = calculate_total_area(grid_manager)
    var expected_area = area_before - (expected_removed * 64 * 64)
    assert_almost_eq(area_after, expected_area, 100.0,
        "Total area mismatch")

    # 8. Grid bounds validation
    var bounds_after = get_grid_bounds(grid_manager)
    assert_ge(bounds_after.min_x, 0, "Grid should not have negative X")
    assert_ge(bounds_after.min_y, 0, "Grid should not have negative Y")

    # 9. Specific cell identity checks
    var cell_7_2 = grid_manager.get_cell(Vector2i(7, 2))
    assert_not_null(cell_7_2, "Cell should exist at (7,2)")
    assert_eq(cell_7_2.cell_type, 900,
        "Cell at (7,2) should be from original (9,0)")
```

## Testing Philosophy

1. **Test outcomes, not implementation**: Check what SHOULD happen, not how it happens
2. **Assert everything critical**: If it matters, assert it
3. **Track identity**: Don't just check existence, verify correctness
4. **Validate invariants**: Properties that should always be true (count, area, bounds)
5. **Test edge cases**: Empty grids, single cells, boundary conditions
6. **Use descriptive messages**: Failed assertions should clearly indicate what went wrong

## Integration with CI/CD

Add these validations to a test utility class that can be called after every fold:

```gdscript
class_name FoldTestValidator

static func validate_fold_result(
    grid_manager: GridManager,
    cells_before: int,
    area_before: float,
    expected_removed: int
) -> void:
    # Runs all validation checks
    # Fails with clear messages if anything is wrong
    pass
```

## Lessons Learned

**From the "disappearing cells" bug:**
- ❌ **Don't just check existence** - verify identity
- ❌ **Don't just print counts** - assert them
- ❌ **Don't assume intermediate steps work** - validate them
- ✅ **Do track specific cells through operations**
- ✅ **Do validate invariants at each step**
- ✅ **Do check for memory issues (freed instances)**

**Remember**: A test that passes but doesn't check enough is worse than no test at all, because it gives false confidence!
