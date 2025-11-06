# Phase 4 GitHub Issues - Geometric Folding (Diagonal Folds)

This document contains all issues for Phase 4 of the Space-Folding Puzzle Game implementation. Phase 4 is the most complex phase, enabling diagonal folds at arbitrary angles with polygon cell splitting.

**Status:** ✅ COMPLETE
**Actual Time:** 6-8 hours
**Complexity:** ⭐⭐⭐⭐⭐ (Most Complex)
**Priority:** P0 - CRITICAL PATH

**IMPORTANT: Updated After Main Branch Merge**
This implementation has been updated to align with Phase 3 improvements from main:
- **LOCAL coordinates** for all cell geometry (relative to GridManager)
- **MIN_FOLD_DISTANCE = 0** (adjacent anchors allowed)
- **Cell overlapping/merging** behavior at anchors
- **AudioManager integration** for sound effects
- **Player position updates** using `to_global()` conversion

---

## Overview

Phase 4 extends the folding system from simple axis-aligned folds (horizontal/vertical) to arbitrary-angle geometric folds. This requires:

- Calculating perpendicular cut lines at any angle
- Classifying cells into regions (kept-left, removed, kept-right, split)
- Splitting cells into polygons when intersected by fold lines
- Merging corresponding half-cells across the fold seam
- Handling all edge cases (vertices, boundaries, player validation)

---

## Issue 10: Implement Diagonal Fold Line Calculation

**Title:** Calculate Perpendicular Cut Lines for Diagonal Folds

**Labels:** `core`, `phase-4`, `geometric-folding`, `math`

**Priority:** High

**Estimated Time:** 2 hours

**Description:**

Implement the mathematical foundation for diagonal folds by calculating the two perpendicular cut lines that define the fold region.

### Tasks

#### Core Implementation

- [ ] Implement `calculate_cut_lines(anchor1: Vector2, anchor2: Vector2) -> Dictionary` in FoldSystem
  - Calculate fold axis vector (from anchor1 to anchor2)
  - Calculate perpendicular normal vector
  - Return both cut lines (at anchor1 and anchor2) with their normals
  - Include fold axis for reference

#### Mathematical Approach

```gdscript
func calculate_cut_lines(anchor1: Vector2, anchor2: Vector2) -> Dictionary:
    # Fold axis vector (direction between anchors)
    var fold_vector = anchor2 - anchor1

    # Perpendicular vector (rotate 90 degrees)
    # For vector (x, y), perpendicular is (-y, x)
    var perpendicular = Vector2(-fold_vector.y, fold_vector.x).normalized()

    return {
        "line1": {"point": anchor1, "normal": perpendicular},
        "line2": {"point": anchor2, "normal": perpendicular},
        "fold_axis": {"start": anchor1, "end": anchor2}
    }
```

### Testing Requirements

Create tests in `scripts/tests/test_geometric_folding.gd`:

- [ ] Test horizontal fold (0 degrees) returns correct perpendicular
- [ ] Test vertical fold (90 degrees) returns correct perpendicular
- [ ] Test diagonal fold (45 degrees) returns correct perpendicular
- [ ] Test arbitrary angle fold (30 degrees) returns correct perpendicular
- [ ] Test perpendicular normal is unit length
- [ ] Test both cut lines are parallel (same normal)

### Acceptance Criteria

- Cut lines calculated correctly for any angle
- Normal vectors are properly normalized
- Perpendicular relationship verified (dot product with fold_vector is 0)
- All tests pass

**Dependencies:** None (GeometryCore already complete)

**Risk:** LOW - Pure mathematics, well-defined

---

## Issue 11: Implement Cell Region Classification

**Title:** Classify Cells Into Fold Regions (Kept/Removed/Split)

**Labels:** `core`, `phase-4`, `geometric-folding`

**Priority:** High

**Estimated Time:** 3-4 hours

**Description:**

Implement the algorithm to classify each cell into one of five categories based on its relationship to the fold lines:
1. **Kept (left of line1)**: Cell is entirely on the kept-left side
2. **Removed (between lines)**: Cell is entirely in the removed region
3. **Kept (right of line2)**: Cell is entirely on the kept-right side
4. **Split by line1**: Cell straddles the first cut line
5. **Split by line2**: Cell straddles the second cut line

### Tasks

#### Core Implementation

- [ ] Implement `classify_cell_region(cell: Cell, cut_lines: Dictionary) -> String` in FoldSystem
  - Calculate cell centroid
  - Determine which side of each line the centroid is on
  - Check if cell geometry intersects either cut line
  - Return classification: "kept_left", "removed", "kept_right", "split_line1", "split_line2"

- [ ] Implement `does_cell_intersect_line(cell: Cell, line_point: Vector2, line_normal: Vector2) -> bool`
  - Use `GeometryCore.split_polygon_by_line()` to test intersection
  - Cell intersects if split result has non-empty intersections array

#### Region Classification Logic

```gdscript
func classify_cell_region(cell: Cell, cut_lines: Dictionary) -> String:
    var centroid = cell.get_center()
    var line1 = cut_lines.line1
    var line2 = cut_lines.line2

    # Determine centroid position
    var side1 = GeometryCore.point_side_of_line(centroid, line1.point, line1.normal)
    var side2 = GeometryCore.point_side_of_line(centroid, line2.point, line2.normal)

    # Check for splits first (most important)
    var split_result1 = GeometryCore.split_polygon_by_line(cell.geometry, line1.point, line1.normal)
    var split_result2 = GeometryCore.split_polygon_by_line(cell.geometry, line2.point, line2.normal)

    if split_result1.intersections.size() > 0:
        return "split_line1"
    if split_result2.intersections.size() > 0:
        return "split_line2"

    # No splits - classify based on centroid position
    if side1 < 0:
        return "kept_left"
    elif side2 > 0:
        return "kept_right"
    else:
        return "removed"
```

### Testing Requirements

Create tests in `scripts/tests/test_geometric_folding.gd`:

- [ ] Test cell fully on left side is classified as "kept_left"
- [ ] Test cell fully in removed region is classified as "removed"
- [ ] Test cell fully on right side is classified as "kept_right"
- [ ] Test cell intersecting line1 is classified as "split_line1"
- [ ] Test cell intersecting line2 is classified as "split_line2"
- [ ] Test for horizontal fold (sanity check - should match Phase 3 logic)
- [ ] Test for vertical fold (sanity check)
- [ ] Test for 45-degree diagonal fold
- [ ] Test cell with vertex exactly on line is handled correctly

### Acceptance Criteria

- All cell classifications are correct
- Split detection is reliable
- Edge cases (vertices on line) handled properly
- All tests pass

**Dependencies:** Issue #10 (cut line calculation)

**Risk:** MEDIUM - Complex geometry logic

---

## Issue 12: Implement Cell Splitting for Diagonal Folds

**Title:** Split Cells Into Polygons When Intersected By Fold Lines

**Labels:** `core`, `phase-4`, `geometric-folding`, `polygon-geometry`

**Priority:** High

**Estimated Time:** 3-4 hours

**Description:**

Implement cell splitting functionality that divides cells into two polygon pieces when a fold line passes through them.

### Tasks

#### Core Implementation

- [ ] Implement `apply_split(split_result: Dictionary, line_point: Vector2, line_normal: Vector2) -> Cell` in Cell class
  - Takes split result from `GeometryCore.split_polygon_by_line()`
  - Updates current cell geometry to one half
  - Creates and returns new cell with other half
  - Marks both cells as partial (`is_partial = true`)
  - Stores seam metadata in both cells

#### Cell.apply_split() Method

```gdscript
## Split this cell into two cells along a line
##
## Updates this cell's geometry to one half and creates a new cell for the other half.
## Both cells are marked as partial and store seam information.
##
## @param split_result: Result from GeometryCore.split_polygon_by_line()
## @param line_point: Point on the splitting line
## @param line_normal: Normal vector of the splitting line
## @param keep_side: Which side to keep in this cell ("left" or "right")
## @return: New Cell containing the other half
func apply_split(split_result: Dictionary, line_point: Vector2, line_normal: Vector2, keep_side: String) -> Cell:
    # Validate split result
    if split_result.intersections.size() == 0:
        push_error("apply_split called with no intersections")
        return null

    # Determine which geometry to keep and which to create new cell with
    var kept_geometry: PackedVector2Array
    var new_geometry: PackedVector2Array

    if keep_side == "left":
        kept_geometry = split_result.left
        new_geometry = split_result.right
    else:
        kept_geometry = split_result.right
        new_geometry = split_result.left

    # Validate geometries
    if kept_geometry.size() < 3 or new_geometry.size() < 3:
        push_error("apply_split resulted in degenerate polygon")
        return null

    # Update this cell's geometry
    geometry = kept_geometry
    is_partial = true

    # Create seam data
    var seam_data = {
        "line_point": line_point,
        "line_normal": line_normal,
        "intersection_points": split_result.intersections,
        "timestamp": Time.get_ticks_msec()
    }
    add_seam(seam_data)

    # Update visual
    update_visual()

    # Create new cell for the other half
    var new_cell = Cell.new(grid_position, Vector2.ZERO, 0)  # Temporary values
    new_cell.geometry = new_geometry
    new_cell.cell_type = cell_type
    new_cell.is_partial = true
    new_cell.add_seam(seam_data)
    new_cell.update_visual()

    return new_cell
```

#### Integration with FoldSystem

- [ ] Update diagonal fold execution to handle split cells
  - Classify all cells in grid
  - For split cells, call `apply_split()` and keep appropriate half
  - Track new cells created from splits
  - Remove cells in the removed region
  - Shift kept-right cells toward kept-left

### Testing Requirements

Create tests in `scripts/tests/test_geometric_folding.gd`:

- [ ] Test cell splits into two valid polygons
- [ ] Test split polygons have correct vertex count
- [ ] Test total area is conserved (sum of halves equals original)
- [ ] Test both cells marked as partial
- [ ] Test seam metadata stored in both cells
- [ ] Test intersection points are on both polygons' boundaries
- [ ] Test split at 45 degrees
- [ ] Test split at arbitrary angle (e.g., 30 degrees)
- [ ] Test split with line passing through vertex (epsilon handling)

### Acceptance Criteria

- Cell splitting works reliably for any angle
- Geometry validation passes (no self-intersections)
- Area conservation verified
- Seam metadata correctly stored
- All tests pass
- No degenerate polygons created

**Dependencies:** Issue #11 (cell classification)

**Risk:** MEDIUM - Geometry complexity, edge cases

---

## Issue 13: Implement Diagonal Fold Execution

**Title:** Execute Complete Diagonal Fold with Cell Splitting and Merging

**Labels:** `core`, `phase-4`, `geometric-folding`

**Priority:** High

**Estimated Time:** 2-3 hours

**Description:**

Integrate all Phase 4 components to execute diagonal folds end-to-end.

### Tasks

#### Core Implementation

- [ ] Implement `execute_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i)` in FoldSystem
  - Calculate cut lines
  - Classify all cells in grid
  - Process split cells (split and keep appropriate halves)
  - Remove cells in removed region
  - Shift kept-right cells
  - Update world positions
  - Create seam visualization
  - Record fold operation

#### Algorithm Structure

```gdscript
func execute_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i):
    # 1. Calculate cut lines
    var cut_lines = calculate_cut_lines(
        grid_manager.grid_to_world(anchor1),
        grid_manager.grid_to_world(anchor2)
    )

    # 2. Classify all cells
    var cells_by_region = {
        "kept_left": [],
        "removed": [],
        "kept_right": [],
        "split_line1": [],
        "split_line2": []
    }

    for pos in grid_manager.cells.keys():
        var cell = grid_manager.get_cell(pos)
        var region = classify_cell_region(cell, cut_lines)
        cells_by_region[region].append(cell)

    # 3. Process split cells
    var new_cells_from_splits = []

    for cell in cells_by_region.split_line1:
        var split_result = GeometryCore.split_polygon_by_line(
            cell.geometry, cut_lines.line1.point, cut_lines.line1.normal
        )
        var new_cell = cell.apply_split(split_result, cut_lines.line1.point, cut_lines.line1.normal, "left")
        new_cells_from_splits.append({"original": cell, "new": new_cell, "line": "line1"})

    for cell in cells_by_region.split_line2:
        var split_result = GeometryCore.split_polygon_by_line(
            cell.geometry, cut_lines.line2.point, cut_lines.line2.normal
        )
        var new_cell = cell.apply_split(split_result, cut_lines.line2.point, cut_lines.line2.normal, "right")
        new_cells_from_splits.append({"original": cell, "new": new_cell, "line": "line2"})

    # 4. Remove cells in removed region
    for cell in cells_by_region.removed:
        grid_manager.cells.erase(cell.grid_position)
        cell.queue_free()

    # 5. Shift kept-right cells (this is complex for diagonal - may need different approach)
    # For now, keep cells in place but update their visual positions
    # (True spatial shifting for diagonal folds is complex - future enhancement)

    # 6. Create seam visualization
    create_diagonal_seam_visual(cut_lines)

    # 7. Record fold operation
    var fold_record = create_fold_record(anchor1, anchor2, cells_by_region.removed, "diagonal")
    fold_history.append(fold_record)
```

#### Update Main execute_fold() Method

- [ ] Update `execute_fold()` to route diagonal folds to `execute_diagonal_fold()`
  - Remove Phase 3 limitation that rejected diagonal folds
  - Add "diagonal" case to orientation match statement

### Testing Requirements

Create tests in `scripts/tests/test_geometric_folding.gd`:

- [ ] Test complete diagonal fold execution
- [ ] Test cells are correctly split
- [ ] Test removed cells are freed
- [ ] Test fold history recorded correctly
- [ ] Test 45-degree fold end-to-end
- [ ] Test 30-degree fold end-to-end
- [ ] Test near-horizontal fold (85 degrees)
- [ ] Test grid remains in valid state after fold

### Acceptance Criteria

- Diagonal folds execute successfully
- Cell splitting and removal work correctly
- Grid state remains valid
- Seam visualization appears
- Fold history tracks diagonal folds
- All tests pass
- No memory leaks

**Dependencies:** Issues #10, #11, #12

**Risk:** MEDIUM - Integration complexity

---

## Issue 14: Handle Critical Edge Cases

**Title:** Implement Edge Case Handling for Geometric Folding

**Labels:** `core`, `phase-4`, `geometric-folding`, `edge-cases`, `validation`

**Priority:** High

**Estimated Time:** 2-3 hours

**Description:**

Implement robust handling for all edge cases in geometric folding to ensure reliability.

### Tasks

#### Edge Case 1: Cut Through Vertex

- [ ] Test fold line passing exactly through cell corner
- [ ] Verify epsilon comparison prevents degenerate splits
- [ ] Test that vertex on line is added to both halves

#### Edge Case 2: Near-Parallel Cuts

- [ ] Define `MAX_FOLD_ANGLE = 5.0` degrees (minimum angle from horizontal/vertical)
- [ ] Implement `validate_fold_angle(anchor1, anchor2) -> bool`
- [ ] For near-axis-aligned folds, route to axis-aligned handlers
- [ ] Test folds at 1°, 3°, 5°, 7° from horizontal

```gdscript
func validate_fold_angle(anchor1: Vector2, anchor2: Vector2) -> bool:
    var fold_vector = anchor2 - anchor1
    var angle_rad = atan2(fold_vector.y, fold_vector.x)
    var angle_deg = rad_to_deg(angle_rad)

    # Normalize to 0-90 degree range
    angle_deg = fmod(abs(angle_deg), 90.0)

    # Check if too close to 0° or 90° (axis-aligned)
    if angle_deg < MAX_FOLD_ANGLE or angle_deg > (90.0 - MAX_FOLD_ANGLE):
        return false  # Too close to axis-aligned, should use axis-aligned handler

    return true
```

#### Edge Case 3: Minimum Distance

- [x] Use `MIN_FOLD_DISTANCE = 0` (adjacent anchors allowed)
- [x] Validation only checks minimum distance for axis-aligned folds
- [x] Diagonal folds do not require minimum distance validation
- [x] Test diagonal fold with adjacent anchors (should succeed)

#### Edge Case 4: Boundary Conditions (Bounded Grid Model)

- [ ] Implement fold line clipping at grid boundaries
- [ ] Don't create cells outside grid bounds
- [ ] Test diagonal fold that would extend beyond grid
- [ ] Verify split cells are clipped to grid boundaries

#### Edge Case 5: Player Position Validation

- [ ] Implement `would_cell_be_split(cell, anchor1, anchor2) -> bool` for diagonal folds
- [ ] Update `validate_fold_with_player()` to check diagonal fold splitting
- [ ] Test fold blocked when player cell would be split by diagonal
- [ ] Test fold blocked when player in diagonal removed region

```gdscript
func would_cell_be_split(cell: Cell, anchor1: Vector2i, anchor2: Vector2i) -> bool:
    # Convert anchor positions to world coordinates
    var anchor1_world = grid_manager.grid_to_world(anchor1)
    var anchor2_world = grid_manager.grid_to_world(anchor2)

    # Calculate cut lines
    var cut_lines = calculate_cut_lines(anchor1_world, anchor2_world)

    # Check both perpendicular cut lines
    var split1 = GeometryCore.split_polygon_by_line(
        cell.geometry, cut_lines.line1.point, cut_lines.line1.normal
    )
    var split2 = GeometryCore.split_polygon_by_line(
        cell.geometry, cut_lines.line2.point, cut_lines.line2.normal
    )

    # Cell is split if either line divides it
    return split1.intersections.size() > 0 or split2.intersections.size() > 0
```

### Testing Requirements

Create tests in `scripts/tests/test_geometric_folding.gd`:

- [ ] Test fold line through cell vertex
- [ ] Test near-horizontal fold (2 degrees)
- [ ] Test near-vertical fold (88 degrees)
- [ ] Test minimum distance validation for diagonal
- [ ] Test fold extending beyond grid boundaries
- [ ] Test player validation blocks diagonal fold splitting player cell
- [ ] Test player validation blocks diagonal fold with player in removed region
- [ ] Test all edge cases combined (stress test)

### Acceptance Criteria

- All edge cases handled gracefully
- No crashes or errors
- Player validation prevents invalid diagonal folds
- Near-axis-aligned folds route to appropriate handlers
- Grid boundaries respected
- All tests pass

**Dependencies:** Issues #10-13

**Risk:** HIGH - Edge cases are where bugs hide

---

## Additional Phase 4 Requirements

### Performance Targets

- Diagonal fold operation: < 100ms on 10x10 grid
- Cell splitting: < 10ms per cell
- Region classification: < 50ms for entire grid
- Animation: 60 FPS maintained

### Code Quality Standards

- TDD approach: Write tests before implementation
- 100% test coverage for geometric folding
- No floating-point equality comparisons (`==`)
- Proper memory management (use `queue_free()`)
- Clear variable names and comprehensive comments
- All geometric operations use `GeometryCore` utilities

### Testing Strategy

1. **Unit Tests:** Test each component in isolation
   - Cut line calculation
   - Cell classification
   - Cell splitting
   - Edge case handling

2. **Integration Tests:** Test complete fold operations
   - End-to-end diagonal folds
   - Multiple sequential diagonal folds
   - Diagonal + axis-aligned folds combined

3. **Visual Tests:** Manual verification
   - Fold animations appear correct
   - Seam lines render properly
   - No visual glitches

4. **Edge Case Tests:** Comprehensive edge case coverage
   - All scenarios from `test_scenarios_and_validation.md`
   - Boundary conditions
   - Player validation

### Success Criteria for Phase 4

- ✅ Diagonal folds work at arbitrary angles
- ✅ Cells split correctly into polygons
- ✅ Geometry validation passes (no self-intersections)
- ✅ Area conservation verified
- ✅ Player validation blocks invalid folds
- ✅ Edge cases handled robustly
- ✅ 50+ new tests passing
- ✅ Performance targets met
- ✅ No memory leaks
- ✅ Visual feedback clear and correct
- ✅ Ready for Phase 5 (Multi-Seam Handling)

---

## Implementation Timeline

✅ **Completed (6-8 hours total):**
- Issue #10: Diagonal fold line calculation ✅
- Issue #11: Cell region classification ✅
- Issue #12: Cell splitting implementation ✅
- Issue #13: Diagonal fold execution ✅
- Issue #14: Edge case handling ✅
- Integration with Phase 3 improvements ✅
- Updated coordinate system to use LOCAL coordinates ✅
- AudioManager integration ✅
- Test updates and validation ✅

---

## Risk Mitigation

### High-Risk Areas

1. **Polygon Splitting Complexity**
   - *Risk:* Edge cases in `split_polygon_by_line()` could cause bugs
   - *Mitigation:* Extensive unit tests, use proven Sutherland-Hodgman algorithm

2. **Cell Classification Errors**
   - *Risk:* Misclassifying cells could break fold logic
   - *Mitigation:* Visualize classifications, add debug rendering mode

3. **Player Validation Edge Cases**
   - *Risk:* Might allow invalid folds that break game state
   - *Mitigation:* Comprehensive player validation tests, conservative blocking

### Medium-Risk Areas

4. **Performance with Many Splits**
   - *Risk:* Large grids with many split cells could slow down
   - *Mitigation:* Profile early, optimize if needed

5. **Memory Leaks from Split Cells**
   - *Risk:* Improperly freed cells could leak memory
   - *Mitigation:* Always use `queue_free()`, test with memory profiler

---

## Notes for Developers

### Before Starting Phase 4

1. Review `CLAUDE.md` for architectural decisions
2. Read `IMPLEMENTATION_PLAN.md` Phase 4 section
3. Study `GeometryCore.gd` to understand utilities
4. Run existing tests to ensure Phase 1-3 still work: `./run_tests.sh`

### During Development

1. Write tests FIRST (TDD)
2. Run tests frequently
3. Use visualization/debug rendering to understand geometry
4. Comment complex geometry operations thoroughly
5. Never use `==` for float comparisons

### After Completing Phase 4

1. Ensure all tests pass (225 existing + 50+ new = 275+ total)
2. Verify performance targets met
3. Update `CLAUDE.md` with any new learnings
4. Commit with clear, descriptive messages
5. Prepare for Phase 5 (Multi-Seam Handling)

---

**Document Maintainer:** Update this document as implementation progresses.

**Last Updated:** 2025-11-06
