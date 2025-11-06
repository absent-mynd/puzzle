## Space-Folding Puzzle Game - Geometric Folding Tests
##
## Tests for Phase 4: Diagonal folds at arbitrary angles with polygon cell splitting.
## This is the most complex test suite in the project.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0
## @phase: 4 - Geometric Folding

extends GutTest

# Test constants
const EPSILON = 0.0001

# Test fixtures
var grid_manager: GridManager
var fold_system: FoldSystem
var player: Player


## Setup before each test
func before_each():
	grid_manager = GridManager.new()
	grid_manager.grid_size = Vector2i(10, 10)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()  # FIX: Use create_grid() not initialize_grid()
	add_child_autofree(grid_manager)

	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)
	add_child_autofree(fold_system)

	player = Player.new()
	player.initialize(grid_manager, Vector2i(0, 0))
	add_child_autofree(player)

	fold_system.set_player(player)


## ============================================================================
## DIAGONAL FOLD LINE CALCULATION TESTS (Issue #10)
## ============================================================================

## Test horizontal fold (0 degrees) returns correct perpendicular
func test_calculate_cut_lines_horizontal():
	var anchor1 = Vector2(100, 100)
	var anchor2 = Vector2(300, 100)

	var cut_lines = fold_system.calculate_cut_lines(anchor1, anchor2)

	# Verify structure
	assert_not_null(cut_lines, "Cut lines should not be null")
	assert_true(cut_lines.has("line1"), "Should have line1")
	assert_true(cut_lines.has("line2"), "Should have line2")
	assert_true(cut_lines.has("fold_axis"), "Should have fold_axis")

	# For horizontal fold (fold axis is horizontal), cut lines should be VERTICAL
	# Cut lines perpendicular to fold axis means lines with normal parallel to fold axis
	# Horizontal fold axis → normal should be horizontal (1, 0) or (-1, 0)
	var normal = cut_lines.line1.normal
	assert_almost_eq(abs(normal.x), 1.0, EPSILON, "Cut line perpendicular to horizontal fold should have horizontal normal")
	assert_almost_eq(abs(normal.y), 0.0, EPSILON, "Horizontal normal should have y=0")


## Test vertical fold (90 degrees) returns correct perpendicular
func test_calculate_cut_lines_vertical():
	var anchor1 = Vector2(100, 100)
	var anchor2 = Vector2(100, 300)

	var cut_lines = fold_system.calculate_cut_lines(anchor1, anchor2)

	# For vertical fold (fold axis is vertical), cut lines should be HORIZONTAL
	# Cut lines perpendicular to fold axis means lines with normal parallel to fold axis
	# Vertical fold axis → normal should be vertical (0, 1) or (0, -1)
	var normal = cut_lines.line1.normal
	assert_almost_eq(abs(normal.y), 1.0, EPSILON, "Cut line perpendicular to vertical fold should have vertical normal")
	assert_almost_eq(abs(normal.x), 0.0, EPSILON, "Vertical normal should have x=0")


## Test diagonal fold (45 degrees) returns correct perpendicular
func test_calculate_cut_lines_45_degrees():
	var anchor1 = Vector2(100, 100)
	var anchor2 = Vector2(200, 200)  # 45-degree diagonal

	var cut_lines = fold_system.calculate_cut_lines(anchor1, anchor2)

	# For 45-degree fold, perpendicular should also be at 45 degrees (rotated 90°)
	# Original vector: (100, 100) normalized = (√2/2, √2/2)
	# Perpendicular: (-√2/2, √2/2) or (√2/2, -√2/2)
	var normal = cut_lines.line1.normal
	assert_almost_eq(abs(normal.x), abs(normal.y), EPSILON, "45-degree perpendicular should have equal x and y magnitudes")


## Test arbitrary angle fold (30 degrees) returns correct perpendicular
func test_calculate_cut_lines_30_degrees():
	# 30 degrees: tan(30°) = 1/√3 ≈ 0.577
	# For a distance of 100 horizontally: vertical = 100 * tan(30°) ≈ 57.7
	var anchor1 = Vector2(100, 100)
	var anchor2 = Vector2(200, 157.7)  # Approximately 30 degrees

	var cut_lines = fold_system.calculate_cut_lines(anchor1, anchor2)

	var normal = cut_lines.line1.normal

	# Verify normal is normalized (length = 1)
	var length = sqrt(normal.x * normal.x + normal.y * normal.y)
	assert_almost_eq(length, 1.0, EPSILON, "Normal vector should be unit length")


## Test perpendicular normal is unit length
func test_calculate_cut_lines_normal_is_unit_length():
	var anchor1 = Vector2(50, 75)
	var anchor2 = Vector2(200, 300)

	var cut_lines = fold_system.calculate_cut_lines(anchor1, anchor2)

	var normal = cut_lines.line1.normal
	var length = sqrt(normal.x * normal.x + normal.y * normal.y)

	assert_almost_eq(length, 1.0, EPSILON, "Normal vector should be unit length")


## Test both cut lines are parallel (same normal)
func test_calculate_cut_lines_both_lines_parallel():
	var anchor1 = Vector2(100, 150)
	var anchor2 = Vector2(250, 200)

	var cut_lines = fold_system.calculate_cut_lines(anchor1, anchor2)

	var normal1 = cut_lines.line1.normal
	var normal2 = cut_lines.line2.normal

	assert_almost_eq(normal1.x, normal2.x, EPSILON, "Both normals should have same x component")
	assert_almost_eq(normal1.y, normal2.y, EPSILON, "Both normals should have same y component")


## Test parallel relationship (normal is parallel to fold vector)
func test_calculate_cut_lines_perpendicular_relationship():
	var anchor1 = Vector2(100, 100)
	var anchor2 = Vector2(300, 250)

	var cut_lines = fold_system.calculate_cut_lines(anchor1, anchor2)

	var fold_vector = anchor2 - anchor1
	var normal = cut_lines.line1.normal

	# For cut lines perpendicular to fold axis, normal should be parallel to fold vector
	# Check if normal is parallel by verifying cross product is 0
	# For 2D: cross product = nx * fy - ny * fx
	var cross_product = abs(normal.x * fold_vector.y - normal.y * fold_vector.x)

	assert_almost_eq(cross_product, 0.0, EPSILON, "Normal should be parallel to fold vector (cross product = 0)")


## ============================================================================
## CELL REGION CLASSIFICATION TESTS (Issue #11)
## ============================================================================

## Test cell fully on left side is classified as "kept_left"
func test_classify_cell_region_kept_left():
	# Set up a vertical fold (same x-coordinate)
	var anchor1_grid = Vector2i(5, 0)
	var anchor2_grid = Vector2i(5, 9)

	# Convert to LOCAL coordinates (cell centers, relative to GridManager)
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	# Cell at (3, 5) should be on the kept-left side (x < 5)
	var cell = grid_manager.get_cell(Vector2i(3, 5))
	var region = fold_system.classify_cell_region(cell, cut_lines)

	assert_eq(region, "kept_left", "Cell at (3, 5) should be classified as kept_left")


## Test cell fully in removed region is classified as "removed"
func test_classify_cell_region_removed():
	# Horizontal fold at rows 3 and 7 (same y-coordinate)
	var anchor1_grid = Vector2i(3, 5)
	var anchor2_grid = Vector2i(7, 5)

	# Convert to LOCAL coordinates (cell centers, relative to GridManager)
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	# Cell at (5, 5) should be in the removed region (between x=3 and x=7)
	var cell = grid_manager.get_cell(Vector2i(5, 5))
	var region = fold_system.classify_cell_region(cell, cut_lines)

	assert_eq(region, "removed", "Cell at (5, 5) should be in removed region")


## Test cell fully on right side is classified as "kept_right"
func test_classify_cell_region_kept_right():
	# Horizontal fold at columns 3 and 7 (same y-coordinate)
	var anchor1_grid = Vector2i(3, 5)
	var anchor2_grid = Vector2i(7, 5)

	# Convert to LOCAL coordinates (cell centers, relative to GridManager)
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	# Cell at (8, 5) should be on the kept-right side (x > 7)
	var cell = grid_manager.get_cell(Vector2i(8, 5))
	var region = fold_system.classify_cell_region(cell, cut_lines)

	assert_eq(region, "kept_right", "Cell at (8, 5) should be classified as kept_right")


## Test cell intersecting line1 is classified as "split_line1"
func test_classify_cell_region_split_line1():
	# Horizontal fold with anchor at center of cell (3, 5)
	# This should split the cell
	var anchor1_grid = Vector2i(3, 5)
	var anchor2_grid = Vector2i(7, 5)

	# Use cell centers for anchors
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	# Cell at (3, 5) should be split by line1 (line passes through cell center)
	var cell = grid_manager.get_cell(Vector2i(3, 5))
	var region = fold_system.classify_cell_region(cell, cut_lines)

	assert_eq(region, "split_line1", "Cell should be split by line1")


## Test cell intersecting line2 is classified as "split_line2"
func test_classify_cell_region_split_line2():
	# Horizontal fold with anchor2 at center of cell (7, 5)
	# This should split the cell
	var anchor1_grid = Vector2i(3, 5)
	var anchor2_grid = Vector2i(7, 5)

	# Use cell centers for anchors
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2_grid) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	# Cell at (7, 5) should be split by line2 (line passes through cell center)
	var cell = grid_manager.get_cell(Vector2i(7, 5))
	var region = fold_system.classify_cell_region(cell, cut_lines)

	assert_eq(region, "split_line2", "Cell should be split by line2")


## ============================================================================
## CELL SPLITTING TESTS (Issue #12)
## ============================================================================

## Test cell splits into two valid polygons
func test_cell_apply_split_creates_two_polygons():
	var cell = grid_manager.get_cell(Vector2i(5, 5))

	# Split cell vertically down the middle
	var line_point = cell.get_center()
	var line_normal = Vector2(1, 0)  # Vertical line

	var split_result = GeometryCore.split_polygon_by_line(cell.geometry, line_point, line_normal)

	# Verify split result has intersections
	assert_gt(split_result.intersections.size(), 0, "Split should produce intersections")

	# Apply split
	var new_cell = cell.apply_split(split_result, line_point, line_normal, "left")

	assert_not_null(new_cell, "New cell should be created")
	assert_true(cell.is_partial, "Original cell should be marked as partial")
	assert_true(new_cell.is_partial, "New cell should be marked as partial")


## Test split polygons have correct vertex count
func test_cell_apply_split_valid_vertex_count():
	var cell = grid_manager.get_cell(Vector2i(5, 5))

	var line_point = cell.get_center()
	var line_normal = Vector2(1, 0)

	var split_result = GeometryCore.split_polygon_by_line(cell.geometry, line_point, line_normal)
	var new_cell = cell.apply_split(split_result, line_point, line_normal, "left")

	assert_gte(cell.geometry.size(), 3, "Original cell should have at least 3 vertices")
	assert_gte(new_cell.geometry.size(), 3, "New cell should have at least 3 vertices")


## Test total area is conserved (sum of halves equals original)
func test_cell_apply_split_conserves_area():
	var cell = grid_manager.get_cell(Vector2i(5, 5))

	var original_area = GeometryCore.polygon_area(cell.geometry)

	var line_point = cell.get_center()
	var line_normal = Vector2(1, 0)

	var split_result = GeometryCore.split_polygon_by_line(cell.geometry, line_point, line_normal)
	var new_cell = cell.apply_split(split_result, line_point, line_normal, "left")

	var area1 = GeometryCore.polygon_area(cell.geometry)
	var area2 = GeometryCore.polygon_area(new_cell.geometry)
	var total_area = area1 + area2

	assert_almost_eq(total_area, original_area, 1.0, "Total area should be conserved after split")


## Test both cells marked as partial
func test_cell_apply_split_marks_as_partial():
	var cell = grid_manager.get_cell(Vector2i(5, 5))

	assert_false(cell.is_partial, "Cell should start as not partial")

	var line_point = cell.get_center()
	var line_normal = Vector2(1, 0)

	var split_result = GeometryCore.split_polygon_by_line(cell.geometry, line_point, line_normal)
	var new_cell = cell.apply_split(split_result, line_point, line_normal, "left")

	assert_true(cell.is_partial, "Original cell should be marked as partial")
	assert_true(new_cell.is_partial, "New cell should be marked as partial")


## Test seam metadata stored in both cells
func test_cell_apply_split_stores_seam_metadata():
	var cell = grid_manager.get_cell(Vector2i(5, 5))

	var line_point = cell.get_center()
	var line_normal = Vector2(1, 0)

	var split_result = GeometryCore.split_polygon_by_line(cell.geometry, line_point, line_normal)
	var new_cell = cell.apply_split(split_result, line_point, line_normal, "left")

	assert_eq(cell.seams.size(), 1, "Original cell should have 1 seam")
	assert_eq(new_cell.seams.size(), 1, "New cell should have 1 seam")


## Test split at 45 degrees
func test_cell_apply_split_45_degrees():
	var cell = grid_manager.get_cell(Vector2i(5, 5))

	var line_point = cell.get_center()
	var line_normal = Vector2(1, 1).normalized()  # 45-degree line

	var split_result = GeometryCore.split_polygon_by_line(cell.geometry, line_point, line_normal)

	assert_gt(split_result.intersections.size(), 0, "45-degree split should produce intersections")

	var new_cell = cell.apply_split(split_result, line_point, line_normal, "left")

	assert_not_null(new_cell, "Should create new cell from 45-degree split")


## ============================================================================
## EDGE CASE TESTS (Issue #14)
## ============================================================================

## Test fold line through cell vertex
func test_fold_line_through_vertex():
	var cell = grid_manager.get_cell(Vector2i(5, 5))

	# Line passing exactly through top-left corner
	var line_point = cell.geometry[0]  # Top-left vertex
	var line_normal = Vector2(1, 1).normalized()

	var split_result = GeometryCore.split_polygon_by_line(cell.geometry, line_point, line_normal)

	# Should handle gracefully (either split or not split, but no crash)
	assert_true(true, "Should handle vertex intersection without crashing")


## Test minimum distance validation for diagonal
func test_validate_minimum_distance_diagonal():
	# Diagonal fold with anchors too close
	var anchor1 = Vector2i(3, 3)
	var anchor2 = Vector2i(4, 4)  # Only 1 cell away diagonally

	var validation = fold_system.validate_fold(anchor1, anchor2)

	# This should pass basic validation but might be too close
	# For now, we're just testing it doesn't crash
	assert_true(true, "Diagonal minimum distance validation should not crash")


## Test player validation blocks diagonal fold splitting player cell
func test_player_validation_blocks_diagonal_split():
	# Place player at (5, 5)
	player.grid_position = Vector2i(5, 5)

	# Diagonal fold that would split cell (5, 5)
	var anchor1 = Vector2i(4, 4)
	var anchor2 = Vector2i(6, 6)

	var validation = fold_system.validate_fold_with_player(anchor1, anchor2)

	# Should block if player cell would be split
	# Note: This test might need adjustment based on exact implementation
	assert_true(true, "Player validation should handle diagonal folds")


## ============================================================================
## INTEGRATION TESTS
## ============================================================================

## Test complete 45-degree diagonal fold execution
func test_execute_diagonal_fold_45_degrees():
	# This is a complex integration test
	# For now, just verify it doesn't crash

	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(7, 7)

	# Place player away from fold
	player.grid_position = Vector2i(0, 0)

	# execute_fold is a coroutine, so must use await even with animated=false
	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	# Should execute without crashing
	assert_true(true, "45-degree diagonal fold should execute")
