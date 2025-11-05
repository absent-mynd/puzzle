extends GutTest
## Unit Tests for FoldSystem Validation
##
## This test suite validates the fold validation system including:
## - Basic validation rules (anchors exist, not same cell, minimum distance)
## - Axis-aligned constraint (Phase 3: only horizontal/vertical)
## - Validation error messages
## - Integration with execute_fold()
## - Edge cases and boundary conditions

var fold_system: FoldSystem
var grid_manager: GridManager


func before_each():
	# Create a fresh GridManager for each test
	grid_manager = GridManager.new()
	grid_manager.create_grid()

	# Create and initialize FoldSystem
	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)


func after_each():
	if fold_system:
		fold_system.free()
	fold_system = null

	if grid_manager:
		# Free all cells first to avoid memory leaks
		for cell in grid_manager.cells.values():
			if cell:
				cell.free()
		grid_manager.cells.clear()
		grid_manager.free()
	grid_manager = null


func before_all():
	gut.p("=== FoldSystem Validation Test Suite ===")


func after_all():
	gut.p("=== FoldSystem Validation Tests Complete ===")


# ===== Valid Fold Tests =====

func test_validation_passes_for_valid_horizontal_fold():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_true(result.valid, "Valid horizontal fold should pass validation")
	assert_eq(result.reason, "", "Valid fold should have empty reason")


func test_validation_passes_for_valid_vertical_fold():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_true(result.valid, "Valid vertical fold should pass validation")
	assert_eq(result.reason, "", "Valid fold should have empty reason")


func test_validation_passes_for_minimum_distance():
	# Anchors with exactly 1 cell between them (minimum allowed)
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(4, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_true(result.valid, "Fold with minimum distance should pass validation")


# ===== Same Cell Tests =====

func test_validation_fails_for_same_cell():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(5, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Same cell fold should fail validation")
	assert_eq(result.reason, "Cannot fold a cell onto itself",
		"Should provide correct error message for same cell")


func test_validate_not_same_cell_returns_false():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(5, 5)

	assert_false(fold_system.validate_not_same_cell(anchor1, anchor2),
		"validate_not_same_cell should return false for same cell")


func test_validate_not_same_cell_returns_true():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(6, 5)

	assert_true(fold_system.validate_not_same_cell(anchor1, anchor2),
		"validate_not_same_cell should return true for different cells")


# ===== Minimum Distance Tests =====

func test_validation_fails_for_adjacent_cells():
	# Adjacent cells have 0 distance between them
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Adjacent cells should fail validation")
	assert_eq(result.reason, "Anchors must have at least one cell between them",
		"Should provide correct error message for adjacent cells")


func test_validate_minimum_distance_for_adjacent_horizontal():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(6, 5)

	assert_false(fold_system.validate_minimum_distance(anchor1, anchor2),
		"Adjacent horizontal cells should fail minimum distance check")


func test_validate_minimum_distance_for_adjacent_vertical():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(5, 6)

	assert_false(fold_system.validate_minimum_distance(anchor1, anchor2),
		"Adjacent vertical cells should fail minimum distance check")


func test_validate_minimum_distance_for_valid_horizontal():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	assert_true(fold_system.validate_minimum_distance(anchor1, anchor2),
		"Valid horizontal distance should pass minimum distance check")


func test_validate_minimum_distance_for_valid_vertical():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	assert_true(fold_system.validate_minimum_distance(anchor1, anchor2),
		"Valid vertical distance should pass minimum distance check")


# ===== Diagonal Fold Tests (Phase 3 Limitation) =====

func test_validation_fails_for_diagonal_fold():
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(7, 7)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Diagonal fold should fail validation in Phase 3")
	assert_eq(result.reason, "Only horizontal and vertical folds supported (for now)",
		"Should provide correct error message for diagonal fold")


func test_validate_same_row_or_column_for_diagonal():
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(7, 7)

	assert_false(fold_system.validate_same_row_or_column(anchor1, anchor2),
		"Diagonal should fail axis-aligned check")


func test_validate_same_row_or_column_for_horizontal():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(7, 5)

	assert_true(fold_system.validate_same_row_or_column(anchor1, anchor2),
		"Horizontal should pass axis-aligned check")


func test_validate_same_row_or_column_for_vertical():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 7)

	assert_true(fold_system.validate_same_row_or_column(anchor1, anchor2),
		"Vertical should pass axis-aligned check")


# ===== Out of Bounds Tests =====

func test_validation_fails_for_anchor1_out_of_bounds_x_negative():
	var anchor1 = Vector2i(-1, 5)
	var anchor2 = Vector2i(5, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Out of bounds anchor should fail validation")
	assert_eq(result.reason, "One or both anchors are invalid",
		"Should provide correct error message for out of bounds anchor")


func test_validation_fails_for_anchor1_out_of_bounds_x_too_large():
	var anchor1 = Vector2i(10, 5)  # Grid is 10x10 (0-9)
	var anchor2 = Vector2i(5, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Out of bounds anchor should fail validation")


func test_validation_fails_for_anchor1_out_of_bounds_y_negative():
	var anchor1 = Vector2i(5, -1)
	var anchor2 = Vector2i(5, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Out of bounds anchor should fail validation")


func test_validation_fails_for_anchor1_out_of_bounds_y_too_large():
	var anchor1 = Vector2i(5, 10)  # Grid is 10x10 (0-9)
	var anchor2 = Vector2i(5, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Out of bounds anchor should fail validation")


func test_validation_fails_for_anchor2_out_of_bounds():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(15, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Out of bounds anchor should fail validation")


func test_validate_anchors_exist_for_out_of_bounds():
	var anchor1 = Vector2i(-1, 5)
	var anchor2 = Vector2i(5, 5)

	assert_false(fold_system.validate_anchors_exist(anchor1, anchor2),
		"validate_anchors_exist should return false for out of bounds")


# ===== Non-Existent Cell Tests =====

func test_validation_fails_for_removed_cell():
	# Remove a cell first
	var removed_pos = Vector2i(5, 5)
	var cell_to_remove = grid_manager.get_cell(removed_pos)
	if cell_to_remove:
		grid_manager.cells.erase(removed_pos)
		cell_to_remove.free()

	# Try to use the removed cell as anchor
	var anchor1 = removed_pos
	var anchor2 = Vector2i(2, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_false(result.valid, "Non-existent cell should fail validation")
	assert_eq(result.reason, "One or both anchors are invalid",
		"Should provide correct error message for non-existent cell")


func test_validate_anchors_exist_for_removed_cell():
	# Remove a cell first
	var removed_pos = Vector2i(5, 5)
	var cell_to_remove = grid_manager.get_cell(removed_pos)
	if cell_to_remove:
		grid_manager.cells.erase(removed_pos)
		cell_to_remove.free()

	var anchor1 = removed_pos
	var anchor2 = Vector2i(2, 5)

	assert_false(fold_system.validate_anchors_exist(anchor1, anchor2),
		"validate_anchors_exist should return false for removed cell")


func test_validate_anchors_exist_for_valid_cells():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	assert_true(fold_system.validate_anchors_exist(anchor1, anchor2),
		"validate_anchors_exist should return true for valid cells")


# ===== Integration with execute_fold() =====

func test_execute_fold_respects_validation_for_valid_fold():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_true(result, "execute_fold should succeed for valid fold")

	# Verify fold was actually executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 1, "Fold should be recorded in history")


func test_execute_fold_respects_validation_for_same_cell():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(5, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_false(result, "execute_fold should fail for same cell")

	# Verify fold was NOT executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 0, "Invalid fold should not be recorded")


func test_execute_fold_respects_validation_for_adjacent_cells():
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(6, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_false(result, "execute_fold should fail for adjacent cells")

	# Verify fold was NOT executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 0, "Invalid fold should not be recorded")


func test_execute_fold_respects_validation_for_diagonal():
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(7, 7)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_false(result, "execute_fold should fail for diagonal fold")

	# Verify fold was NOT executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 0, "Invalid fold should not be recorded")


func test_execute_fold_respects_validation_for_out_of_bounds():
	var anchor1 = Vector2i(-1, 5)
	var anchor2 = Vector2i(5, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_false(result, "execute_fold should fail for out of bounds anchor")

	# Verify fold was NOT executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 0, "Invalid fold should not be recorded")


func test_execute_fold_respects_validation_for_removed_cell():
	# Remove a cell first
	var removed_pos = Vector2i(5, 5)
	var cell_to_remove = grid_manager.get_cell(removed_pos)
	if cell_to_remove:
		grid_manager.cells.erase(removed_pos)
		cell_to_remove.free()

	var anchor1 = removed_pos
	var anchor2 = Vector2i(2, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_false(result, "execute_fold should fail for removed cell")

	# Verify fold was NOT executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 0, "Invalid fold should not be recorded")


# ===== Edge Cases =====

func test_validation_allows_fold_at_grid_edge():
	# Fold near right edge
	var anchor1 = Vector2i(7, 5)
	var anchor2 = Vector2i(9, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_true(result.valid, "Fold at grid edge should be valid")


func test_validation_allows_minimum_distance_fold():
	# Anchors with exactly 1 cell between them
	var anchor1 = Vector2i(5, 5)
	var anchor2 = Vector2i(7, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_true(result.valid, "Minimum distance fold should be valid")
	assert_eq(fold_system.get_fold_distance(anchor1, anchor2), 1,
		"Should have exactly 1 cell between anchors")


func test_validation_with_reversed_anchor_order():
	# Test with right anchor first (should still work)
	var anchor1 = Vector2i(7, 5)
	var anchor2 = Vector2i(3, 5)

	var result = fold_system.validate_fold(anchor1, anchor2)

	assert_true(result.valid, "Validation should work regardless of anchor order")


# ===== Validation Message Tests =====

func test_validation_message_for_same_cell():
	var result = fold_system.validate_fold(Vector2i(5, 5), Vector2i(5, 5))
	assert_eq(result.reason, "Cannot fold a cell onto itself",
		"Should have correct message for same cell")


func test_validation_message_for_adjacent_cells():
	var result = fold_system.validate_fold(Vector2i(5, 5), Vector2i(6, 5))
	assert_eq(result.reason, "Anchors must have at least one cell between them",
		"Should have correct message for adjacent cells")


func test_validation_message_for_diagonal():
	var result = fold_system.validate_fold(Vector2i(2, 2), Vector2i(7, 7))
	assert_eq(result.reason, "Only horizontal and vertical folds supported (for now)",
		"Should have correct message for diagonal fold")


func test_validation_message_for_out_of_bounds():
	var result = fold_system.validate_fold(Vector2i(-1, 5), Vector2i(5, 5))
	assert_eq(result.reason, "One or both anchors are invalid",
		"Should have correct message for out of bounds")


func test_validation_message_for_removed_cell():
	# Remove a cell first
	var removed_pos = Vector2i(5, 5)
	var cell_to_remove = grid_manager.get_cell(removed_pos)
	if cell_to_remove:
		grid_manager.cells.erase(removed_pos)
		cell_to_remove.free()

	var result = fold_system.validate_fold(removed_pos, Vector2i(2, 5))
	assert_eq(result.reason, "One or both anchors are invalid",
		"Should have correct message for removed cell")
