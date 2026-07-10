extends GutTest
## PHASE 8 tests for player facing and the move signals.

var player: Player
var grid_manager: GridManager


func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	await wait_physics_frames(2)

	player = Player.new()
	add_child_autofree(player)
	player.initialize(grid_manager, Vector2i(5, 5))
	await wait_physics_frames(1)


func test_facing_updates_on_successful_move():
	player.attempt_move(Vector2i(1, 0))
	assert_eq(player.facing, Vector2i(1, 0), "Facing updates on a successful move")


func test_facing_updates_on_blocked_move():
	# Move to the right edge, then bump the boundary
	player.set_grid_position(Vector2i(9, 5))
	await wait_physics_frames(1)
	var success = player.attempt_move(Vector2i(1, 0))
	assert_false(success, "Move past the boundary fails")
	assert_eq(player.facing, Vector2i(1, 0), "Facing still turns toward a blocked move")


func test_facing_turns_without_moving_into_wall():
	# Put a wall to the player's left; attempt to move into it
	grid_manager.get_cell(Vector2i(4, 5)).set_cell_type(1)  # wall
	var success = player.attempt_move(Vector2i(-1, 0))
	assert_false(success, "Cannot move into a wall")
	assert_eq(player.facing, Vector2i(-1, 0), "Facing turns toward the wall")


func test_move_attempted_signal_success():
	watch_signals(player)
	player.attempt_move(Vector2i(1, 0))
	assert_signal_emitted(player, "move_attempted", "move_attempted fires")
	var params = get_signal_parameters(player, "move_attempted", 0)
	assert_eq(params[0], Vector2i(1, 0), "Direction reported")
	assert_true(params[1], "Success flag true for a valid move")


func test_move_attempted_signal_failure():
	player.set_grid_position(Vector2i(9, 5))
	await wait_physics_frames(1)
	watch_signals(player)
	player.attempt_move(Vector2i(1, 0))
	var params = get_signal_parameters(player, "move_attempted", 0)
	assert_false(params[1], "Success flag false for a blocked move")
