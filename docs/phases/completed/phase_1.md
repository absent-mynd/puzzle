# Phase 1 GitHub Issues - Project Setup & Foundation

This document contains all issues for Phase 1 of the Space-Folding Puzzle Game implementation. Each issue is structured to be copy-pasted directly into GitHub.

---

## Issue 1: Set Up Godot 4 Project Structure

**Title:** Set Up Godot 4 Project Structure

**Labels:** `setup`, `phase-1`, `foundation`

**Priority:** High

**Estimated Time:** 1-2 hours

**Description:**

Create the initial Godot 4 project structure with all necessary directories for the Space-Folding Puzzle Game.

### Tasks

- [ ] Create new Godot 4 project
- [ ] Set up directory structure:
  ```
  SpaceFoldingPuzzle/
  ├── scenes/
  │   ├── main.tscn
  │   ├── grid/
  │   ├── player/
  │   └── ui/
  ├── scripts/
  │   ├── core/           # Cell, Grid, Fold classes
  │   ├── systems/        # FoldSystem, UndoManager
  │   ├── utils/          # GeometryCore, math utilities
  │   └── tests/          # Unit and integration tests
  └── assets/
      ├── sprites/
      └── shaders/
  ```
- [ ] Create placeholder `.gdignore` files where needed
- [ ] Configure project settings (resolution, rendering, etc.)
- [ ] Create initial `main.tscn` scene
- [ ] Verify project runs successfully

### Acceptance Criteria

- All directories exist and are properly organized
- Project can be opened in Godot 4 without errors
- Main scene loads correctly
- Project structure matches the implementation plan

### References

- Implementation Plan: Phase 1.1
- Target: Week 1

---

## Issue 2: Implement GeometryCore Utility Class

**Title:** Implement GeometryCore Utility Class with Polygon Operations

**Labels:** `core`, `geometry`, `phase-1`, `critical`

**Priority:** Critical

**Estimated Time:** 2-3 hours

**Description:**

Implement the foundational `GeometryCore` utility class that provides all geometric calculations needed for the space-folding mechanics. This is a **CRITICAL** component as all folding logic depends on these utilities.

### Tasks

#### Core Functions

- [ ] Create `scripts/utils/GeometryCore.gd` file
- [ ] Implement `point_side_of_line(point: Vector2, line_point: Vector2, line_normal: Vector2) -> int`
  - Returns: -1 (left), 0 (on line), 1 (right)
  - Use epsilon comparison for "on line" (EPSILON = 0.0001)
- [ ] Implement `segment_line_intersection(seg_start: Vector2, seg_end: Vector2, line_point: Vector2, line_normal: Vector2) -> Variant`
  - Returns intersection point or null if no intersection
  - Handle parallel/collinear cases
- [ ] Implement `split_polygon_by_line(vertices: PackedVector2Array, line_point: Vector2, line_normal: Vector2) -> Dictionary`
  - Returns: `{left_polygon: PackedVector2Array, right_polygon: PackedVector2Array, intersections: PackedVector2Array}`
  - Use Sutherland-Hodgman algorithm
  - Handle degenerate cases (line doesn't intersect polygon)
- [ ] Implement `polygon_area(vertices: PackedVector2Array) -> float`
  - Use shoelace formula
  - Return absolute value
- [ ] Implement `polygon_centroid(vertices: PackedVector2Array) -> Vector2`
  - Calculate geometric center
  - Handle empty/invalid polygons
- [ ] Implement `validate_polygon(vertices: PackedVector2Array) -> bool`
  - Check for minimum 3 vertices
  - Check for self-intersection
  - Check for degenerate triangles
  - Verify counter-clockwise winding order

#### Constants

- [ ] Define `const EPSILON = 0.0001` for floating-point comparisons

#### Documentation

- [ ] Add comprehensive comments for each function
- [ ] Include usage examples in comments
- [ ] Document edge cases and assumptions

### Testing Requirements

Create test scenarios in `scripts/tests/test_geometry_core.gd`:

- [ ] Test `point_side_of_line` with points clearly on each side
- [ ] Test `point_side_of_line` with point exactly on line (epsilon)
- [ ] Test `segment_line_intersection` with clear intersections
- [ ] Test `segment_line_intersection` with parallel segments
- [ ] Test `split_polygon_by_line` with axis-aligned cuts (horizontal/vertical)
- [ ] Test `split_polygon_by_line` with 45-degree diagonal cuts
- [ ] Test `split_polygon_by_line` with cuts through vertices
- [ ] Test `split_polygon_by_line` with cuts that miss the polygon entirely
- [ ] Test `polygon_area` calculation accuracy
- [ ] Verify area conservation (sum of split polygons = original area)
- [ ] Test `polygon_centroid` for various shapes
- [ ] Test `validate_polygon` with valid and invalid polygons

### Acceptance Criteria

- All functions implemented and properly documented
- All test cases pass
- Polygon splitting works correctly at various angles (0°, 45°, 90°, etc.)
- Area conservation verified (splitting doesn't lose/gain area)
- Edge cases handled gracefully (vertices on lines, degenerate cases)
- No crashes with invalid input
- Epsilon-based floating-point comparisons used consistently

### Implementation Notes

**Sutherland-Hodgman Algorithm:**
```gdscript
func split_polygon_by_line(vertices: PackedVector2Array, line_point: Vector2, line_normal: Vector2) -> Dictionary:
    # For each edge in polygon:
    #   1. Check if start/end vertices are on left/right of line
    #   2. If edge crosses line, compute intersection point
    #   3. Build two output polygons (left and right)
    # Return both polygons and intersection points
```

**Important:** Always use epsilon comparison for floating-point values. Never use `==` with floats.

### References

- Implementation Plan: Phase 1.2
- Math Utilities Reference: `math_utilities_reference.md`
- Target: Week 1

### Dependencies

- Depends on: Issue #1 (Project structure must exist first)

---

## Issue 3: Create Basic Unit Test Framework

**Title:** Set Up Unit Testing Framework and Initial Test Suite

**Labels:** `testing`, `phase-1`, `infrastructure`

**Priority:** Medium

**Estimated Time:** 1 hour

**Description:**

Set up the testing framework to enable test-driven development for the project. This will be used immediately for testing GeometryCore and throughout the project.

### Tasks

- [ ] Research testing options for Godot 4 (GUT or built-in testing)
- [ ] Install/configure chosen testing framework
- [ ] Create `scripts/tests/` directory structure
- [ ] Create example test file with basic assertions
- [ ] Document how to run tests in project README
- [ ] Verify tests can be run from command line and/or Godot editor

### Recommended Framework

**GUT (Godot Unit Test)** is recommended:
- Mature and well-documented
- Good assertion library
- Integrates with Godot editor
- CI/CD friendly

### Acceptance Criteria

- Testing framework installed and configured
- Example test runs successfully
- Documentation exists for running tests
- Tests can be run both in editor and via command line
- Test output is clear and readable

### References

- Implementation Plan: Phase 9.1
- Target: Week 1 (early setup for TDD approach)

### Dependencies

- Depends on: Issue #1 (Project structure must exist first)

---

## Additional Notes

### Phase 1 Overview

**Total Estimated Time:** 4-6 hours

**Goals:**
- Establish solid project foundation
- Implement critical geometric utilities
- Enable test-driven development
- Prepare for Phase 2 (Basic Grid System)

### Success Criteria for Phase 1

- ✅ Project structure is complete and organized
- ✅ GeometryCore class is fully implemented and tested
- ✅ All geometric operations work correctly
- ✅ Area conservation is verified
- ✅ Testing framework is operational
- ✅ Ready to implement Cell and Grid classes (Phase 2)

### Next Phase Preview

Phase 2 will implement:
- Cell class with geometry support
- GridManager for 10x10 grid
- Anchor selection system
- Basic visual rendering

These components will build directly on the GeometryCore utilities from Phase 1.
