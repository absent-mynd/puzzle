extends GutTest
## Unit Tests for FoldSystem
##
## This test suite validates the FoldSystem class functionality including:
## - Fold detection (horizontal, vertical, diagonal)
## - Horizontal fold execution
## - Vertical fold execution
## - Cell removal
## - Cell shifting and position updates
## - Fold history tracking
## - Edge cases and boundary conditions

var fold_system: FoldSystem
var grid_manager: GridManager


func before_each():
	# Create a fresh GridManager for each test
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	# Create and initialize FoldSystem
	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)


func after_each():
	# GUT's add_child_autofree() handles cleanup automatically
	fold_system = null
	grid_manager = null


func before_all():
	gut.p("=== FoldSystem Test Suite ===")


func after_all():
	gut.p("=== FoldSystem Tests Complete ===")


# ===== Fold Detection Tests =====

func test_horizontal_fold_detection():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(7, 5)
	assert_true(fold_system.is_horizontal_fold(anchor1, anchor2),
		"Should detect horizontal fold (same Y coordinate)")


func test_vertical_fold_detection():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 7)
	assert_true(fold_system.is_vertical_fold(anchor1, anchor2),
		"Should detect vertical fold (same X coordinate)")


func test_diagonal_fold_detection():
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(7, 7)
	assert_false(fold_system.is_horizontal_fold(anchor1, anchor2),
		"Diagonal should not be horizontal")
	assert_false(fold_system.is_vertical_fold(anchor1, anchor2),
		"Diagonal should not be vertical")


func test_get_fold_orientation_horizontal():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(7, 5)
	assert_eq(fold_system.get_fold_orientation(anchor1, anchor2), "horizontal",
		"Should return 'horizontal' for same-row anchors")


func test_get_fold_orientation_vertical():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 7)
	assert_eq(fold_system.get_fold_orientation(anchor1, anchor2), "vertical",
		"Should return 'vertical' for same-column anchors")


func test_get_fold_orientation_diagonal():
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(7, 7)
	assert_eq(fold_system.get_fold_orientation(anchor1, anchor2), "diagonal",
		"Should return 'diagonal' for non-aligned anchors")


# ===== Helper Method Tests =====

func test_calculate_removed_cells_horizontal():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)
	var removed = fold_system.calculate_removed_cells(anchor1, anchor2)

	assert_eq(removed.size(), 3, "Should remove 3 cells between anchors")
	assert_has(removed, Vector2i(3, 5), "Should include cell at (3, 5)")
	assert_has(removed, Vector2i(4, 5), "Should include cell at (4, 5)")
	assert_has(removed, Vector2i(5, 5), "Should include cell at (5, 5)")


func test_calculate_removed_cells_vertical():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)
	var removed = fold_system.calculate_removed_cells(anchor1, anchor2)

	assert_eq(removed.size(), 3, "Should remove 3 cells between anchors")
	assert_has(removed, Vector2i(5, 3), "Should include cell at (5, 3)")
	assert_has(removed, Vector2i(5, 4), "Should include cell at (5, 4)")
	assert_has(removed, Vector2i(5, 5), "Should include cell at (5, 5)")


func test_calculate_removed_cells_adjacent():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(3, 5)
	var removed = fold_system.calculate_removed_cells(anchor1, anchor2)

	assert_eq(removed.size(), 0, "Adjacent anchors should have no cells between them")


func test_get_fold_distance_horizontal():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(7, 5)
	var distance = fold_system.get_fold_distance(anchor1, anchor2)

	assert_eq(distance, 4, "Distance should be 4 cells")


func test_get_fold_distance_vertical():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 7)
	var distance = fold_system.get_fold_distance(anchor1, anchor2)

	assert_eq(distance, 4, "Distance should be 4 cells")


func test_get_fold_distance_adjacent():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(3, 5)
	var distance = fold_system.get_fold_distance(anchor1, anchor2)

	assert_eq(distance, 0, "Adjacent anchors should have 0 distance")


# ===== Horizontal Fold Execution Tests =====

func test_horizontal_fold_removes_correct_cells():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	# Store references to original cells that should be removed
	var cell_to_remove_1 = grid_manager.get_cell(Vector2i(3, 5))
	var cell_to_remove_2 = grid_manager.get_cell(Vector2i(4, 5))
	var cell_to_remove_3 = grid_manager.get_cell(Vector2i(5, 5))

	# Verify cells exist before fold
	assert_not_null(cell_to_remove_1, "Cell (3,5) should exist before fold")
	assert_not_null(cell_to_remove_2, "Cell (4,5) should exist before fold")
	assert_not_null(cell_to_remove_3, "Cell (5,5) should exist before fold")

	# Execute fold
	fold_system.execute_horizontal_fold(anchor1, anchor2)

	# Verify the original cells were removed (not in dictionary anymore)
	# Note: positions may be occupied by shifted cells
	var found_removed_cells = 0
	for cell in grid_manager.cells.values():
		if cell == cell_to_remove_1 or cell == cell_to_remove_2 or cell == cell_to_remove_3:
			found_removed_cells += 1

	assert_eq(found_removed_cells, 0, "Original cells should be removed from grid")


func test_horizontal_fold_keeps_anchor_cells():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	fold_system.execute_horizontal_fold(anchor1, anchor2)

	# Anchor cells should still exist
	assert_not_null(grid_manager.get_cell(anchor1), "Anchor1 cell should remain")
	assert_not_null(grid_manager.get_cell(anchor2), "Anchor2 cell should remain")


func test_horizontal_fold_shifts_cells_correctly():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	# Store original cell at position (7, 5)
	var original_cell = grid_manager.get_cell(Vector2i(7, 5))
	assert_not_null(original_cell, "Cell at (7,5) should exist")

	# Execute fold
	fold_system.execute_horizontal_fold(anchor1, anchor2)

	# Cell that was at (7, 5) should now be at (3, 5)
	# Shift distance is 6 - 2 = 4, so 7 - 4 = 3
	assert_null(grid_manager.get_cell(Vector2i(7, 5)), "Old position should be empty")

	var shifted_cell = grid_manager.get_cell(Vector2i(3, 5))
	assert_not_null(shifted_cell, "Shifted cell should exist at new position")
	assert_eq(shifted_cell.grid_position, Vector2i(3, 5), "Cell grid_position should update")


func test_horizontal_fold_updates_world_positions():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	# Execute fold
	fold_system.execute_horizontal_fold(anchor1, anchor2)

	# Check that shifted cells have correct world positions
	var shifted_cell = grid_manager.get_cell(Vector2i(3, 5))
	if shifted_cell:
		var expected_world_pos = grid_manager.grid_to_world(Vector2i(3, 5))
		var actual_center = shifted_cell.get_center()
		var cell_size = grid_manager.cell_size

		# Center should be at expected_world_pos + half cell_size
		var expected_center = expected_world_pos + Vector2(cell_size / 2, cell_size / 2)

		assert_almost_eq(actual_center.x, expected_center.x, 1.0,
			"Shifted cell X position should be correct")
		assert_almost_eq(actual_center.y, expected_center.y, 1.0,
			"Shifted cell Y position should be correct")


func test_horizontal_fold_with_reversed_anchors():
	# Test that fold works regardless of anchor order
	var anchor1 = Vector2i(6, 5)  # Right anchor first
	var anchor2 = Vector2i(2, 5)  # Left anchor second

	# Store references to original cells that should be removed
	var cell_to_remove_1 = grid_manager.get_cell(Vector2i(3, 5))
	var cell_to_remove_2 = grid_manager.get_cell(Vector2i(4, 5))
	var cell_to_remove_3 = grid_manager.get_cell(Vector2i(5, 5))

	fold_system.execute_horizontal_fold(anchor1, anchor2)

	# Verify the original cells were removed
	var found_removed_cells = 0
	for cell in grid_manager.cells.values():
		if cell == cell_to_remove_1 or cell == cell_to_remove_2 or cell == cell_to_remove_3:
			found_removed_cells += 1

	assert_eq(found_removed_cells, 0, "Original cells should be removed from grid")


# ===== Vertical Fold Execution Tests =====

func test_vertical_fold_removes_correct_cells():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	# Store references to original cells that should be removed
	var cell_to_remove_1 = grid_manager.get_cell(Vector2i(5, 3))
	var cell_to_remove_2 = grid_manager.get_cell(Vector2i(5, 4))
	var cell_to_remove_3 = grid_manager.get_cell(Vector2i(5, 5))

	# Verify cells exist before fold
	assert_not_null(cell_to_remove_1, "Cell (5,3) should exist before fold")
	assert_not_null(cell_to_remove_2, "Cell (5,4) should exist before fold")
	assert_not_null(cell_to_remove_3, "Cell (5,5) should exist before fold")

	# Execute fold
	fold_system.execute_vertical_fold(anchor1, anchor2)

	# Verify the original cells were removed (not in dictionary anymore)
	# Note: positions may be occupied by shifted cells
	var found_removed_cells = 0
	for cell in grid_manager.cells.values():
		if cell == cell_to_remove_1 or cell == cell_to_remove_2 or cell == cell_to_remove_3:
			found_removed_cells += 1

	assert_eq(found_removed_cells, 0, "Original cells should be removed from grid")


func test_vertical_fold_keeps_anchor_cells():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	fold_system.execute_vertical_fold(anchor1, anchor2)

	# Anchor cells should still exist
	assert_not_null(grid_manager.get_cell(anchor1), "Anchor1 cell should remain")
	assert_not_null(grid_manager.get_cell(anchor2), "Anchor2 cell should remain")


func test_vertical_fold_shifts_cells_correctly():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	# Store original cell at position (5, 7)
	var original_cell = grid_manager.get_cell(Vector2i(5, 7))
	assert_not_null(original_cell, "Cell at (5,7) should exist")

	# Execute fold
	fold_system.execute_vertical_fold(anchor1, anchor2)

	# Cell that was at (5, 7) should now be at (5, 3)
	# Shift distance is 6 - 2 = 4, so 7 - 4 = 3
	assert_null(grid_manager.get_cell(Vector2i(5, 7)), "Old position should be empty")

	var shifted_cell = grid_manager.get_cell(Vector2i(5, 3))
	assert_not_null(shifted_cell, "Shifted cell should exist at new position")
	assert_eq(shifted_cell.grid_position, Vector2i(5, 3), "Cell grid_position should update")


func test_vertical_fold_updates_world_positions():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	# Execute fold
	fold_system.execute_vertical_fold(anchor1, anchor2)

	# Check that shifted cells have correct world positions
	var shifted_cell = grid_manager.get_cell(Vector2i(5, 3))
	if shifted_cell:
		var expected_world_pos = grid_manager.grid_to_world(Vector2i(5, 3))
		var actual_center = shifted_cell.get_center()
		var cell_size = grid_manager.cell_size

		# Center should be at expected_world_pos + half cell_size
		var expected_center = expected_world_pos + Vector2(cell_size / 2, cell_size / 2)

		assert_almost_eq(actual_center.x, expected_center.x, 1.0,
			"Shifted cell X position should be correct")
		assert_almost_eq(actual_center.y, expected_center.y, 1.0,
			"Shifted cell Y position should be correct")


func test_vertical_fold_with_reversed_anchors():
	# Test that fold works regardless of anchor order
	var anchor1 = Vector2i(5, 6)  # Bottom anchor first
	var anchor2 = Vector2i(5, 2)  # Top anchor second

	# Store references to original cells that should be removed
	var cell_to_remove_1 = grid_manager.get_cell(Vector2i(5, 3))
	var cell_to_remove_2 = grid_manager.get_cell(Vector2i(5, 4))
	var cell_to_remove_3 = grid_manager.get_cell(Vector2i(5, 5))

	fold_system.execute_vertical_fold(anchor1, anchor2)

	# Verify the original cells were removed
	var found_removed_cells = 0
	for cell in grid_manager.cells.values():
		if cell == cell_to_remove_1 or cell == cell_to_remove_2 or cell == cell_to_remove_3:
			found_removed_cells += 1

	assert_eq(found_removed_cells, 0, "Original cells should be removed from grid")


# ===== Main Execute Fold Tests =====

func test_execute_fold_horizontal():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	# Store reference to a cell that should be removed
	var cell_to_remove = grid_manager.get_cell(Vector2i(3, 5))

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_true(result, "Horizontal fold should succeed")

	# Verify the original cell was removed
	var found = false
	for cell in grid_manager.cells.values():
		if cell == cell_to_remove:
			found = true
			break
	assert_false(found, "Original cell should be removed")


func test_execute_fold_vertical():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	# Store reference to a cell that should be removed
	var cell_to_remove = grid_manager.get_cell(Vector2i(5, 3))

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_true(result, "Vertical fold should succeed")

	# Verify the original cell was removed
	var found = false
	for cell in grid_manager.cells.values():
		if cell == cell_to_remove:
			found = true
			break
	assert_false(found, "Original cell should be removed")


func test_execute_fold_diagonal_fails():
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(7, 7)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	assert_false(result, "Diagonal fold should fail in Phase 3")


# ===== Fold History Tests =====

func test_fold_history_records_operation():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	await fold_system.execute_fold(anchor1, anchor2, false)  # Use await since execute_fold is a coroutine

	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 1, "Should have one fold in history")

	var record = history[0]
	assert_has(record, "fold_id", "Record should have fold_id")
	assert_has(record, "anchor1", "Record should have anchor1")
	assert_has(record, "anchor2", "Record should have anchor2")
	assert_has(record, "removed_cells", "Record should have removed_cells")
	assert_has(record, "orientation", "Record should have orientation")
	assert_has(record, "timestamp", "Record should have timestamp")


func test_fold_history_multiple_folds():
	await fold_system.execute_fold(Vector2i(2, 5), Vector2i(6, 5), false)  # Use await since execute_fold is a coroutine
	await fold_system.execute_fold(Vector2i(3, 2), Vector2i(3, 4), false)  # Use await since execute_fold is a coroutine

	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 2, "Should have two folds in history")

	assert_eq(history[0].orientation, "horizontal", "First fold should be horizontal")
	assert_eq(history[1].orientation, "vertical", "Second fold should be vertical")


func test_fold_history_incrementing_ids():
	await fold_system.execute_fold(Vector2i(2, 5), Vector2i(6, 5), false)  # Use await since execute_fold is a coroutine
	await fold_system.execute_fold(Vector2i(3, 2), Vector2i(3, 4), false)  # Use await since execute_fold is a coroutine

	var history = fold_system.get_fold_history()
	assert_eq(history[0].fold_id, 0, "First fold should have ID 0")
	assert_eq(history[1].fold_id, 1, "Second fold should have ID 1")


# ===== Edge Case Tests =====

func test_horizontal_fold_adjacent_anchors():
	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(3, 5)

	fold_system.execute_horizontal_fold(anchor1, anchor2)

	# No cells should be removed (adjacent anchors)
	assert_eq(fold_system.get_fold_history()[0].removed_cells.size(), 0,
		"Adjacent anchors should remove no cells")


func test_vertical_fold_adjacent_anchors():
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 3)

	fold_system.execute_vertical_fold(anchor1, anchor2)

	# No cells should be removed (adjacent anchors)
	assert_eq(fold_system.get_fold_history()[0].removed_cells.size(), 0,
		"Adjacent anchors should remove no cells")


func test_horizontal_fold_at_grid_edge():
	# Fold near right edge of grid
	var anchor1 = Vector2i(7, 5)
	var anchor2 = Vector2i(9, 5)

	fold_system.execute_horizontal_fold(anchor1, anchor2)

	# Should only remove cell at (8, 5)
	assert_null(grid_manager.get_cell(Vector2i(8, 5)), "Cell (8,5) should be removed")
	assert_not_null(grid_manager.get_cell(anchor1), "Anchor cells should remain")
	assert_not_null(grid_manager.get_cell(anchor2), "Anchor cells should remain")


func test_vertical_fold_at_grid_edge():
	# Fold near bottom edge of grid
	var anchor1 = Vector2i(5, 7)
	var anchor2 = Vector2i(5, 9)

	fold_system.execute_vertical_fold(anchor1, anchor2)

	# Should only remove cell at (5, 8)
	assert_null(grid_manager.get_cell(Vector2i(5, 8)), "Cell (5,8) should be removed")
	assert_not_null(grid_manager.get_cell(anchor1), "Anchor cells should remain")
	assert_not_null(grid_manager.get_cell(anchor2), "Anchor cells should remain")


# ===== Integration Tests =====

func test_multiple_sequential_horizontal_folds():
	# First fold
	await fold_system.execute_fold(Vector2i(1, 3), Vector2i(5, 3), false)  # Use await since execute_fold is a coroutine

	# Second fold on same row
	await fold_system.execute_fold(Vector2i(0, 3), Vector2i(2, 3), false)  # Use await since execute_fold is a coroutine

	# Verify history
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 2, "Should have two folds in history")


func test_multiple_sequential_vertical_folds():
	# First fold
	await fold_system.execute_fold(Vector2i(4, 1), Vector2i(4, 5), false)  # Use await since execute_fold is a coroutine

	# Second fold on same column
	await fold_system.execute_fold(Vector2i(4, 0), Vector2i(4, 2), false)  # Use await since execute_fold is a coroutine

	# Verify history
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 2, "Should have two folds in history")


func test_mixed_folds():
	# Horizontal fold
	await fold_system.execute_fold(Vector2i(2, 5), Vector2i(6, 5), false)  # Use await since execute_fold is a coroutine

	# Vertical fold (different row/column)
	await fold_system.execute_fold(Vector2i(3, 2), Vector2i(3, 4), false)  # Use await since execute_fold is a coroutine

	# Both should succeed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 2, "Should have two folds in history")


func test_grid_remains_consistent_after_fold():
	await fold_system.execute_fold(Vector2i(2, 5), Vector2i(6, 5), false)  # Use await since execute_fold is a coroutine

	# Check that all remaining cells are valid
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		assert_not_null(cell, "All cells in dictionary should be valid")
		assert_eq(cell.grid_position, pos, "Cell grid_position should match dictionary key")
