extends GutTest
## Unit Tests for Player-Fold Validation
##
## Tests the validation system that prevents folds from affecting the player.
## Specifically tests:
## - Player in removed region detection
## - Fold blocking when player is in the way
## - Validation integration with execute_fold()
## - Error message handling
## - Edge cases with player at various positions

var fold_system: FoldSystem
var grid_manager: GridManager
var player: Player


func before_each():
	# Create a fresh GridManager for each test
	grid_manager = GridManager.new()
	grid_manager.create_grid()

	# Create player
	player = Player.new()
	player.initialize(grid_manager, Vector2i(5, 5))

	# Create and initialize FoldSystem
	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)
	fold_system.set_player(player)


func after_each():
	if player:
		player.free()
	player = null

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
	gut.p("=== Player-Fold Validation Test Suite ===")


func after_all():
	gut.p("=== Player-Fold Validation Tests Complete ===")


# ===== Basic Player Validation Tests =====

func test_validate_fold_with_player_passes_when_player_not_in_way():
	# Player at (7, 5), fold removes columns 3-5 across all rows
	# Player is in column 7, which is outside the removed region
	player.set_grid_position(Vector2i(7, 5))

	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(6, 2)

	var result = fold_system.validate_fold_with_player(anchor1, anchor2)

	assert_true(result.valid, "Fold should be valid when player not in removed region")
	assert_eq(result.reason, "", "Valid player validation should have empty reason")


func test_validate_fold_with_player_fails_when_player_in_removed_region():
	# Player at (4, 5), fold removes cells (3, 5), (4, 5), (5, 5)
	player.set_grid_position(Vector2i(4, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.validate_fold_with_player(anchor1, anchor2)

	assert_false(result.valid, "Fold should fail when player in removed region")
	assert_eq(result.reason, "Cannot fold - player in the way",
		"Should provide correct error message")


func test_validate_fold_with_player_passes_when_no_player():
	# Create fold system without player
	var fold_system_no_player = FoldSystem.new()
	fold_system_no_player.initialize(grid_manager)
	# Don't set player

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system_no_player.validate_fold_with_player(anchor1, anchor2)

	assert_true(result.valid, "Validation should pass when no player is set")
	assert_eq(result.reason, "", "Should have empty reason when no player")

	fold_system_no_player.free()


# ===== is_player_in_removed_region Tests =====

func test_is_player_in_removed_region_horizontal_fold_player_in_middle():
	# Player at (4, 5), fold removes (3, 5), (4, 5), (5, 5)
	player.set_grid_position(Vector2i(4, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player at (4, 5) should be in removed region")


func test_is_player_in_removed_region_horizontal_fold_player_at_start():
	# Player at (3, 5) - first removed cell
	player.set_grid_position(Vector2i(3, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player at first removed cell should be in removed region")


func test_is_player_in_removed_region_horizontal_fold_player_at_end():
	# Player at (5, 5) - last removed cell
	player.set_grid_position(Vector2i(5, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player at last removed cell should be in removed region")


func test_is_player_in_removed_region_horizontal_fold_player_at_anchor1():
	# Player at anchor1 - should NOT be in removed region
	player.set_grid_position(Vector2i(2, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_false(result, "Player at anchor cell should NOT be in removed region")


func test_is_player_in_removed_region_horizontal_fold_player_at_anchor2():
	# Player at anchor2 - should NOT be in removed region
	player.set_grid_position(Vector2i(6, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_false(result, "Player at anchor cell should NOT be in removed region")


func test_is_player_in_removed_region_horizontal_fold_player_adjacent():
	# Player at (1, 5) - adjacent to fold but not in removed region
	player.set_grid_position(Vector2i(1, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_false(result, "Player adjacent to fold should NOT be in removed region")


func test_is_player_in_removed_region_horizontal_fold_player_on_different_row():
	# Player at (4, 4) - in removed column 4, different row
	# Horizontal fold removes ENTIRE columns 3-5 across ALL rows
	player.set_grid_position(Vector2i(4, 4))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player in removed column (even on different row) SHOULD be in removed region")


func test_is_player_in_removed_region_vertical_fold_player_in_middle():
	# Player at (5, 4), fold removes (5, 3), (5, 4), (5, 5)
	player.set_grid_position(Vector2i(5, 4))

	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player at (5, 4) should be in removed region")


func test_is_player_in_removed_region_vertical_fold_player_at_start():
	# Player at (5, 3) - first removed cell
	player.set_grid_position(Vector2i(5, 3))

	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player at first removed cell should be in removed region")


func test_is_player_in_removed_region_vertical_fold_player_at_end():
	# Player at (5, 5) - last removed cell
	player.set_grid_position(Vector2i(5, 5))

	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player at last removed cell should be in removed region")


func test_is_player_in_removed_region_vertical_fold_player_at_anchor():
	# Player at anchor - should NOT be in removed region
	player.set_grid_position(Vector2i(5, 2))

	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_false(result, "Player at anchor cell should NOT be in removed region")


func test_is_player_in_removed_region_vertical_fold_player_on_different_column():
	# Player at (4, 4) - in removed row 4, different column
	# Vertical fold removes ENTIRE rows 3-5 across ALL columns
	player.set_grid_position(Vector2i(4, 4))

	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = fold_system.is_player_in_removed_region(anchor1, anchor2)

	assert_true(result, "Player in removed row (even on different column) SHOULD be in removed region")


func test_is_player_in_removed_region_returns_false_when_no_player():
	# Create fold system without player
	var fold_system_no_player = FoldSystem.new()
	fold_system_no_player.initialize(grid_manager)

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = fold_system_no_player.is_player_in_removed_region(anchor1, anchor2)

	assert_false(result, "Should return false when no player is set")

	fold_system_no_player.free()


# ===== Integration with execute_fold() =====

func test_execute_fold_succeeds_when_player_not_in_way():
	# Player at safe position outside removed columns
	# Horizontal fold from (2,5) to (6,5) removes columns 3-5
	# Player at (7, 1) is in column 7, which is safe
	player.set_grid_position(Vector2i(7, 1))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_true(result, "Fold should succeed when player not in the way")

	# Verify fold was executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 1, "Fold should be recorded in history")


func test_execute_fold_fails_when_player_in_removed_region():
	# Player in removed region
	player.set_grid_position(Vector2i(4, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_false(result, "Fold should fail when player in removed region")

	# Verify fold was NOT executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 0, "Fold should not be recorded when blocked by player")


func test_execute_fold_checks_player_validation_after_basic_validation():
	# Invalid fold (same cell) should fail basic validation first, before checking player
	player.set_grid_position(Vector2i(5, 5))

	var anchor1 = Vector2i(3, 3)
	var anchor2 = Vector2i(3, 3)  # Same cell - invalid

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_false(result, "Should fail basic validation for same cell before checking player")


func test_execute_fold_with_player_at_anchor_succeeds():
	# Player at anchor cell should be OK
	player.set_grid_position(Vector2i(2, 5))

	var anchor1 = Vector2i(2, 5)
	var anchor2 = Vector2i(6, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_true(result, "Fold should succeed when player at anchor")

	# Verify fold was executed
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 1, "Fold should be recorded in history")


# ===== Minimum Distance Edge Cases =====

func test_execute_fold_minimum_distance_with_player_in_middle():
	# Minimum distance fold (1 cell between anchors)
	# Player in that single removed cell
	player.set_grid_position(Vector2i(4, 5))

	var anchor1 = Vector2i(3, 5)
	var anchor2 = Vector2i(5, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_false(result, "Should fail when player in single removed cell")


func test_execute_fold_minimum_distance_with_player_not_in_middle():
	# Minimum distance fold, player elsewhere
	player.set_grid_position(Vector2i(1, 1))

	var anchor1 = Vector2i(3, 5)
	var anchor2 = Vector2i(5, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_true(result, "Should succeed when player not in removed cell")


# ===== Reversed Anchor Order =====

func test_execute_fold_with_reversed_anchors_player_in_way():
	# Player at (4, 5)
	player.set_grid_position(Vector2i(4, 5))

	# Anchors reversed (right first, then left)
	var anchor1 = Vector2i(6, 5)
	var anchor2 = Vector2i(2, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_false(result, "Should still block fold when anchors reversed")


func test_execute_fold_with_reversed_anchors_player_safe():
	# Player safe
	player.set_grid_position(Vector2i(1, 1))

	# Anchors reversed
	var anchor1 = Vector2i(6, 5)
	var anchor2 = Vector2i(2, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_true(result, "Should still succeed when player safe and anchors reversed")


# ===== Multiple Folds =====

func test_multiple_folds_with_player_moving_between():
	# First fold - player safe
	player.set_grid_position(Vector2i(1, 1))

	var result1 = await fold_system.execute_fold(Vector2i(2, 5), Vector2i(6, 5), false)
	assert_true(result1, "First fold should succeed")

	# Move player to a position that would block second fold
	player.set_grid_position(Vector2i(4, 7))

	var result2 = await fold_system.execute_fold(Vector2i(2, 7), Vector2i(6, 7), false)
	assert_false(result2, "Second fold should fail with player in the way")

	# Verify only first fold was recorded
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 1, "Only first fold should be in history")


func test_multiple_folds_with_player_always_safe():
	# Player in corner, safe from all folds
	player.set_grid_position(Vector2i(0, 0))

	var result1 = await fold_system.execute_fold(Vector2i(2, 5), Vector2i(6, 5), false)
	assert_true(result1, "First fold should succeed")

	var result2 = await fold_system.execute_fold(Vector2i(5, 2), Vector2i(5, 4), false)
	assert_true(result2, "Second fold should succeed")

	# Verify both folds were recorded
	var history = fold_system.get_fold_history()
	assert_eq(history.size(), 2, "Both folds should be in history")


# ===== Vertical Fold Tests =====

func test_execute_vertical_fold_with_player_in_removed_region():
	# Player in removed region for vertical fold
	player.set_grid_position(Vector2i(5, 4))

	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_false(result, "Vertical fold should fail when player in removed region")


func test_execute_vertical_fold_with_player_safe():
	# Player safe from vertical fold
	# Vertical fold from (5,2) to (5,6) removes rows 3-5
	# Player at (3, 7) is in row 7, which is safe
	player.set_grid_position(Vector2i(3, 7))

	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_true(result, "Vertical fold should succeed when player safe")


# ===== Grid Boundary Tests =====

func test_fold_at_grid_edge_with_player_in_way():
	# Fold near edge, player in removed region
	player.set_grid_position(Vector2i(8, 5))

	var anchor1 = Vector2i(7, 5)
	var anchor2 = Vector2i(9, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_false(result, "Edge fold should fail when player in the way")


func test_fold_at_grid_edge_with_player_safe():
	# Fold near edge, player safe
	player.set_grid_position(Vector2i(0, 0))

	var anchor1 = Vector2i(7, 5)
	var anchor2 = Vector2i(9, 5)

	var result = await fold_system.execute_fold(anchor1, anchor2, false)

	assert_true(result, "Edge fold should succeed when player safe")


# ===== Validation Message Consistency =====

func test_validation_error_message_is_correct():
	player.set_grid_position(Vector2i(4, 5))

	var result = fold_system.validate_fold_with_player(Vector2i(2, 5), Vector2i(6, 5))

	assert_eq(result.reason, "Cannot fold - player in the way",
		"Error message should be correct")


func test_validation_success_message_is_empty():
	player.set_grid_position(Vector2i(1, 1))

	var result = fold_system.validate_fold_with_player(Vector2i(2, 5), Vector2i(6, 5))

	assert_eq(result.reason, "",
		"Success message should be empty")
