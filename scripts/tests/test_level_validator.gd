extends GutTest

# Tests for LevelValidator class
# LevelValidator checks if a level is valid and playable

var validator: LevelValidator

func before_each():
	validator = LevelValidator.new()
	add_child_autofree(validator)

func test_validator_initialization():
	assert_not_null(validator, "LevelValidator should be instantiable")

func test_validate_valid_level():
	var level = _create_valid_level()

	var result = validator.validate_level(level)

	assert_not_null(result, "validate_level should return a result")
	assert_true(result.has("valid"), "Result should have 'valid' key")
	assert_true(result.has("errors"), "Result should have 'errors' key")
	assert_true(result.has("warnings"), "Result should have 'warnings' key")
	assert_true(result["valid"], "Valid level should pass validation")
	assert_eq(result["errors"].size(), 0, "Valid level should have no errors")

func test_validate_level_without_player_start():
	var level = LevelData.new()
	level.level_id = "test_no_player"
	level.level_name = "No Player Start"
	# LevelData defaults to Vector2i(0,0) which is valid
	# To test invalid, we need to set it outside grid or make (0,0) a wall
	level.cell_data[Vector2i(0, 0)] = 1  # Wall at default player start
	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level with player starting on wall should fail")
	assert_gt(result["errors"].size(), 0, "Should have at least one error")

func test_validate_level_without_goal():
	var level = LevelData.new()
	level.level_id = "test_no_goal"
	level.level_name = "No Goal"
	level.player_start_position = Vector2i(0, 0)
	# Don't add any goal cells

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level without goal should fail validation")
	assert_true(_has_error_containing(result["errors"], "goal"), "Should have error about missing goal")

func test_validate_level_with_player_start_outside_grid():
	var level = LevelData.new()
	level.level_id = "test_out_of_bounds"
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(15, 15)  # Outside 10x10 grid
	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level with player start outside grid should fail")
	assert_true(_has_error_containing(result["errors"], "outside"), "Should have error about position being outside grid")

func test_validate_level_with_player_on_wall():
	var level = LevelData.new()
	level.level_id = "test_wall_start"
	level.player_start_position = Vector2i(0, 0)
	level.cell_data[Vector2i(0, 0)] = 1  # Wall at player start
	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level with player starting on wall should fail")
	assert_true(_has_error_containing(result["errors"], "wall"), "Should have error about player on wall")

func test_validate_level_with_goal_outside_grid():
	var level = LevelData.new()
	level.level_id = "test_goal_outside"
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(0, 0)
	level.cell_data[Vector2i(15, 15)] = 3  # Goal outside grid

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level with goal outside grid should fail")

func test_validate_level_warns_if_goal_unreachable():
	var level = LevelData.new()
	level.level_id = "test_unreachable"
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(0, 0)

	# Create a wall barrier
	for x in range(10):
		level.cell_data[Vector2i(x, 5)] = 1  # Wall

	level.cell_data[Vector2i(9, 9)] = 3  # Goal on other side of wall

	var result = validator.validate_level(level)

	# This should be a warning, not necessarily an error (player might use folds to reach goal)
	assert_gt(result["warnings"].size(), 0, "Should have warning about potentially unreachable goal")

func test_validate_level_with_very_restrictive_max_folds():
	var level = _create_valid_level()
	level.max_folds = 1  # Very restrictive

	var result = validator.validate_level(level)

	# Should be valid but with a warning
	assert_true(result["valid"], "Level with restrictive max_folds should still be valid")
	assert_gt(result["warnings"].size(), 0, "Should warn about restrictive max_folds")

func test_validate_level_with_negative_max_folds():
	var level = _create_valid_level()
	level.max_folds = -1  # Unlimited (valid)

	var result = validator.validate_level(level)

	assert_true(result["valid"], "Level with -1 max_folds (unlimited) should be valid")

func test_validate_level_with_par_greater_than_max():
	var level = _create_valid_level()
	level.max_folds = 5
	level.par_folds = 10  # Par is greater than max - impossible to achieve par

	var result = validator.validate_level(level)

	assert_true(result["valid"], "Level should still be technically valid")
	assert_gt(result["warnings"].size(), 0, "Should warn about impossible par")

func test_validate_level_with_zero_grid_size():
	var level = LevelData.new()
	level.level_id = "test_zero_grid"
	level.grid_size = Vector2i(0, 0)
	level.player_start_position = Vector2i(0, 0)

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level with zero grid size should fail")
	assert_true(_has_error_containing(result["errors"], "grid size"), "Should have error about grid size")

func test_validate_level_with_negative_grid_size():
	var level = LevelData.new()
	level.level_id = "test_negative_grid"
	level.grid_size = Vector2i(-5, -5)

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level with negative grid size should fail")

func test_validate_level_with_very_large_grid():
	var level = _create_valid_level()
	level.grid_size = Vector2i(100, 100)

	var result = validator.validate_level(level)

	# Should be valid but might have performance warning
	assert_true(result["valid"], "Large grid should be valid")

func test_validate_level_with_multiple_goals():
	var level = LevelData.new()
	level.level_id = "test_multi_goal"
	level.player_start_position = Vector2i(0, 0)
	level.cell_data[Vector2i(5, 5)] = 3  # Goal 1
	level.cell_data[Vector2i(9, 9)] = 3  # Goal 2

	var result = validator.validate_level(level)

	# Multiple goals should be valid (player needs to reach any one)
	assert_true(result["valid"], "Level with multiple goals should be valid")

func test_validate_level_without_level_id():
	var level = LevelData.new()
	level.level_id = ""  # Empty ID
	level.level_name = "No ID"
	level.player_start_position = Vector2i(0, 0)
	level.cell_data[Vector2i(9, 9)] = 3

	var result = validator.validate_level(level)

	# Empty ID might be a warning rather than error
	assert_not_null(result, "Should still return a result")

func test_is_goal_reachable_simple_path():
	var level = _create_valid_level()

	var reachable = validator.is_goal_reachable(level)

	assert_true(reachable, "Goal should be reachable in simple valid level")

func test_is_goal_reachable_with_walls():
	var level = LevelData.new()
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(0, 0)

	# Create complete wall barrier (no path)
	for x in range(10):
		level.cell_data[Vector2i(x, 5)] = 1

	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	var reachable = validator.is_goal_reachable(level)

	assert_false(reachable, "Goal should not be reachable with complete wall barrier")

func test_is_goal_reachable_with_gap_in_walls():
	var level = LevelData.new()
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(0, 0)

	# Create wall barrier with a gap
	for x in range(10):
		if x != 5:  # Leave gap at x=5
			level.cell_data[Vector2i(x, 5)] = 1

	level.cell_data[Vector2i(9, 9)] = 3  # Goal

	var reachable = validator.is_goal_reachable(level)

	assert_true(reachable, "Goal should be reachable through gap in walls")

func test_validate_level_with_invalid_cell_types():
	var level = _create_valid_level()
	level.cell_data[Vector2i(5, 5)] = 99  # Invalid cell type

	var result = validator.validate_level(level)

	# Should warn about invalid cell types
	assert_not_null(result, "Should return validation result")

func test_multiple_validation_errors_collected():
	var level = LevelData.new()
	level.level_id = "test_multi_errors"
	# Missing player start
	# Missing goal
	level.grid_size = Vector2i(0, 0)  # Invalid grid size

	var result = validator.validate_level(level)

	assert_false(result["valid"], "Level with multiple errors should fail")
	assert_gt(result["errors"].size(), 1, "Should collect multiple errors")

# Helper functions

func _create_valid_level() -> LevelData:
	var level = LevelData.new()
	level.level_id = "valid_test"
	level.level_name = "Valid Test Level"
	level.grid_size = Vector2i(10, 10)
	level.player_start_position = Vector2i(0, 0)
	level.cell_data[Vector2i(9, 9)] = 3  # Goal
	return level

func _has_error_containing(errors: Array, substring: String) -> bool:
	for error in errors:
		if error.to_lower().contains(substring.to_lower()):
			return true
	return false
