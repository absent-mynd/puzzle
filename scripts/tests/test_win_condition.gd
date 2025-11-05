## Test Suite for Win Condition (Phase 7 Issue 12)
##
## Tests goal detection, win condition triggering, and level completion state.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends GutTest

var grid_manager: GridManager
var player: Player


## Set up before each test
func before_each():
	# Create grid manager
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager._ready()

	# Create player
	player = Player.new()
	add_child_autofree(player)
	player._ready()
	player.initialize(grid_manager, Vector2i(1, 1))


## Clean up after each test
func after_each():
	grid_manager = null
	player = null


## Test 1: Player on goal cell triggers goal_reached signal
func test_player_on_goal_triggers_signal():
	# Set up goal cell
	var goal_pos = Vector2i(3, 3)
	grid_manager.set_goal_cell(goal_pos)

	# Set up signal watcher
	watch_signals(player)

	# Move player to goal
	player.set_grid_position(goal_pos)
	player.check_goal()

	# Verify signal was emitted
	assert_signal_emitted(player, "goal_reached", "goal_reached signal should be emitted")


## Test 2: Player on non-goal cell doesn't trigger signal
func test_player_on_non_goal_no_signal():
	# Set up goal cell
	grid_manager.set_goal_cell(Vector2i(5, 5))

	# Set up signal watcher
	watch_signals(player)

	# Player is at non-goal position
	player.set_grid_position(Vector2i(3, 3))
	player.check_goal()

	# Verify signal was not emitted
	assert_signal_not_emitted(player, "goal_reached", "goal_reached signal should not be emitted for non-goal cell")


## Test 3: Goal cell is walkable
func test_goal_cell_is_walkable():
	# Set up goal cell
	var goal_pos = Vector2i(2, 1)
	grid_manager.set_goal_cell(goal_pos)

	# Player at adjacent position
	player.set_grid_position(Vector2i(1, 1))

	# Check if player can move to goal
	var can_move = player.can_move_to(goal_pos)

	assert_true(can_move, "Player should be able to move to goal cell")


## Test 4: set_goal_cell returns true for valid position
func test_set_goal_cell_valid_position():
	var result = grid_manager.set_goal_cell(Vector2i(5, 5))

	assert_true(result, "set_goal_cell should return true for valid position")

	var cell = grid_manager.get_cell(Vector2i(5, 5))
	assert_eq(cell.cell_type, 3, "Cell type should be 3 (goal)")


## Test 5: set_goal_cell returns false for invalid position
func test_set_goal_cell_invalid_position():
	var result = grid_manager.set_goal_cell(Vector2i(20, 20))

	assert_false(result, "set_goal_cell should return false for invalid position")


## Test 6: Goal cell has correct color
func test_goal_cell_has_green_color():
	grid_manager.set_goal_cell(Vector2i(4, 4))
	var cell = grid_manager.get_cell(Vector2i(4, 4))

	var expected_color = Color(0.2, 1.0, 0.2)  # Green
	var actual_color = cell.get_cell_color()

	assert_eq(actual_color, expected_color, "Goal cell should be green")


## Test 7: Player input can be disabled
func test_player_input_can_be_disabled():
	# Initially enabled
	assert_true(player.input_enabled, "Player input should be enabled by default")

	# Disable input
	player.input_enabled = false

	# Verify disabled
	assert_false(player.input_enabled, "Player input should be disabled")


## Test 8: Multiple goal cells can exist
func test_multiple_goal_cells():
	grid_manager.set_goal_cell(Vector2i(2, 2))
	grid_manager.set_goal_cell(Vector2i(7, 7))

	var cell1 = grid_manager.get_cell(Vector2i(2, 2))
	var cell2 = grid_manager.get_cell(Vector2i(7, 7))

	assert_eq(cell1.cell_type, 3, "First cell should be goal type")
	assert_eq(cell2.cell_type, 3, "Second cell should be goal type")


## Test 9: Player check_goal only triggers on goal type
func test_check_goal_only_on_goal_type():
	# Set different cell types
	grid_manager.get_cell(Vector2i(1, 1)).set_cell_type(0)  # Empty
	grid_manager.get_cell(Vector2i(2, 2)).set_cell_type(1)  # Wall
	grid_manager.get_cell(Vector2i(3, 3)).set_cell_type(2)  # Water
	grid_manager.get_cell(Vector2i(4, 4)).set_cell_type(3)  # Goal

	watch_signals(player)

	# Test empty
	player.set_grid_position(Vector2i(1, 1))
	player.check_goal()
	assert_signal_emit_count(player, "goal_reached", 0, "No signal on empty cell")

	# Test water
	player.set_grid_position(Vector2i(3, 3))
	player.check_goal()
	assert_signal_emit_count(player, "goal_reached", 0, "No signal on water cell")

	# Test goal
	player.set_grid_position(Vector2i(4, 4))
	player.check_goal()
	assert_signal_emit_count(player, "goal_reached", 1, "Signal should emit on goal cell")


## Test 10: Player movement followed by goal check
func test_player_movement_triggers_goal_check():
	# Set up goal
	var goal_pos = Vector2i(2, 1)
	grid_manager.set_goal_cell(goal_pos)

	# Start player at adjacent position
	player.set_grid_position(Vector2i(1, 1))

	# Watch for signal
	watch_signals(player)

	# Execute move to goal (this should trigger check_goal internally)
	player.execute_move(goal_pos)

	# Wait for tween to complete
	await wait_seconds(0.3)

	# Signal should have been emitted after movement completes
	assert_signal_emitted(player, "goal_reached", "goal_reached should emit after movement to goal")


## Test 11: Goal cell properties are preserved
func test_goal_cell_properties_preserved():
	var goal_pos = Vector2i(6, 6)
	grid_manager.set_goal_cell(goal_pos)

	var cell = grid_manager.get_cell(goal_pos)

	# Check properties
	assert_eq(cell.cell_type, 3, "Cell type should be goal")
	assert_eq(cell.grid_position, goal_pos, "Grid position should match")
	assert_false(cell.is_partial, "Goal cell should not be partial initially")
	assert_eq(cell.geometry.size(), 4, "Goal cell should have 4 vertices (square)")


## Test 12: Player can reach goal from all directions
func test_player_can_reach_goal_from_all_directions():
	var goal_pos = Vector2i(5, 5)
	grid_manager.set_goal_cell(goal_pos)

	# Test from above
	player.set_grid_position(Vector2i(5, 4))
	assert_true(player.can_move_to(goal_pos), "Can move to goal from above")

	# Test from below
	player.set_grid_position(Vector2i(5, 6))
	assert_true(player.can_move_to(goal_pos), "Can move to goal from below")

	# Test from left
	player.set_grid_position(Vector2i(4, 5))
	assert_true(player.can_move_to(goal_pos), "Can move to goal from left")

	# Test from right
	player.set_grid_position(Vector2i(6, 5))
	assert_true(player.can_move_to(goal_pos), "Can move to goal from right")
