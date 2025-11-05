## Unit tests for Player class
##
## Tests grid-based movement, collision detection, and player-grid interaction

extends GutTest

var player: Player
var grid_manager: GridManager
var start_position: Vector2i


## Set up test environment before each test
func before_each():
	# Create grid manager
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)

	# Wait for grid to initialize
	await wait_frames(2)

	# Create player
	player = Player.new()
	add_child_autofree(player)

	# Initialize player at center of grid
	start_position = Vector2i(5, 5)
	player.initialize(grid_manager, start_position)

	await wait_frames(1)


## Test: Player initializes at correct grid position
func test_player_initialization():
	assert_eq(player.grid_position, start_position, "Player should be at starting position")
	assert_not_null(player.grid_manager, "Player should have grid manager reference")
	assert_false(player.is_moving, "Player should not be moving initially")


## Test: Player can move to valid adjacent cell
func test_player_move_to_valid_cell():
	var initial_pos = player.grid_position

	# Attempt to move right
	var success = player.attempt_move(Vector2i(1, 0))

	assert_true(success, "Move to valid cell should succeed")
	assert_eq(player.grid_position, initial_pos + Vector2i(1, 0), "Grid position should update")
	assert_true(player.is_moving, "Player should be marked as moving")


## Test: Player movement blocked by grid boundaries
func test_player_blocked_by_boundary():
	# Move player to edge
	player.set_grid_position(Vector2i(9, 5))
	await wait_frames(1)

	# Try to move beyond right boundary
	var success = player.attempt_move(Vector2i(1, 0))

	assert_false(success, "Move beyond boundary should fail")
	assert_eq(player.grid_position, Vector2i(9, 5), "Position should not change")


## Test: Player movement blocked by walls
func test_player_blocked_by_wall():
	# Place a wall to the right of player
	var wall_pos = start_position + Vector2i(1, 0)
	var wall_cell = grid_manager.get_cell(wall_pos)
	wall_cell.set_cell_type(1)  # Set as wall

	# Try to move right into wall
	var success = player.attempt_move(Vector2i(1, 0))

	assert_false(success, "Move into wall should fail")
	assert_eq(player.grid_position, start_position, "Position should not change")


## Test: Player can move in all four directions
func test_player_four_direction_movement():
	# Test up
	player.set_grid_position(Vector2i(5, 5))
	await wait_frames(1)
	assert_true(player.can_move_to(Vector2i(5, 4)), "Should be able to move up")

	# Test down
	assert_true(player.can_move_to(Vector2i(5, 6)), "Should be able to move down")

	# Test left
	assert_true(player.can_move_to(Vector2i(4, 5)), "Should be able to move left")

	# Test right
	assert_true(player.can_move_to(Vector2i(6, 5)), "Should be able to move right")


## Test: Player can walk on empty cells (type 0)
func test_player_can_walk_on_empty():
	var target_pos = start_position + Vector2i(1, 0)
	var target_cell = grid_manager.get_cell(target_pos)
	target_cell.set_cell_type(0)  # Empty

	assert_true(player.can_move_to(target_pos), "Should be able to walk on empty cells")


## Test: Player can walk on water cells (type 2)
func test_player_can_walk_on_water():
	var target_pos = start_position + Vector2i(1, 0)
	var target_cell = grid_manager.get_cell(target_pos)
	target_cell.set_cell_type(2)  # Water

	assert_true(player.can_move_to(target_pos), "Should be able to walk on water cells")


## Test: Player can walk on goal cells (type 3)
func test_player_can_walk_on_goal():
	var target_pos = start_position + Vector2i(1, 0)
	var target_cell = grid_manager.get_cell(target_pos)
	target_cell.set_cell_type(3)  # Goal

	assert_true(player.can_move_to(target_pos), "Should be able to walk on goal cells")


## Test: Player cannot walk through walls (type 1)
func test_player_cannot_walk_through_walls():
	var target_pos = start_position + Vector2i(1, 0)
	var target_cell = grid_manager.get_cell(target_pos)
	target_cell.set_cell_type(1)  # Wall

	assert_false(player.can_move_to(target_pos), "Should not be able to walk through walls")


## Test: Player position snaps to cell center
func test_player_position_snaps_to_center():
	var cell = grid_manager.get_cell(start_position)
	var expected_center = cell.get_center()

	# Allow small epsilon for floating point comparison
	var distance = player.position.distance_to(expected_center)
	assert_lt(distance, 0.1, "Player should be at cell center")


## Test: Player can be teleported to new position
func test_player_teleport():
	var new_pos = Vector2i(7, 7)
	player.set_grid_position(new_pos)

	assert_eq(player.grid_position, new_pos, "Player grid position should update")
	assert_false(player.is_moving, "Player should not be in moving state after teleport")


## Test: Player cannot move while already moving
func test_player_cannot_move_while_moving():
	# Start a move
	player.attempt_move(Vector2i(1, 0))
	assert_true(player.is_moving, "Player should be moving")

	var current_pos = player.grid_position

	# Try to move again immediately
	var success = player.attempt_move(Vector2i(0, 1))

	assert_false(success, "Cannot move while already moving")
	assert_eq(player.grid_position, current_pos, "Position should not change")


## Test: Player movement respects grid boundaries (all edges)
func test_player_respects_all_boundaries():
	# Test left boundary
	player.set_grid_position(Vector2i(0, 5))
	await wait_frames(1)
	assert_false(player.can_move_to(Vector2i(-1, 5)), "Cannot move left of grid")

	# Test right boundary
	player.set_grid_position(Vector2i(9, 5))
	await wait_frames(1)
	assert_false(player.can_move_to(Vector2i(10, 5)), "Cannot move right of grid")

	# Test top boundary
	player.set_grid_position(Vector2i(5, 0))
	await wait_frames(1)
	assert_false(player.can_move_to(Vector2i(5, -1)), "Cannot move above grid")

	# Test bottom boundary
	player.set_grid_position(Vector2i(5, 9))
	await wait_frames(1)
	assert_false(player.can_move_to(Vector2i(5, 10)), "Cannot move below grid")


## Test: Player movement with complex wall configuration
func test_player_movement_with_wall_maze():
	# Create a simple maze
	var maze_cell1 = grid_manager.get_cell(Vector2i(4, 4))
	if maze_cell1:
		maze_cell1.set_cell_type(1)
	var maze_cell2 = grid_manager.get_cell(Vector2i(4, 5))
	if maze_cell2:
		maze_cell2.set_cell_type(1)
	var maze_cell3 = grid_manager.get_cell(Vector2i(4, 6))
	if maze_cell3:
		maze_cell3.set_cell_type(1)

	player.set_grid_position(Vector2i(3, 5))
	await wait_frames(1)

	# Cannot move right (wall)
	assert_false(player.can_move_to(Vector2i(4, 5)), "Cannot move into wall at (4,5)")

	# Can move up
	assert_true(player.can_move_to(Vector2i(3, 4)), "Can move up to (3,4)")

	# Can move down
	assert_true(player.can_move_to(Vector2i(3, 6)), "Can move down to (3,6)")


## Test: Get grid position returns correct value
func test_get_grid_position():
	var pos = player.get_grid_position()
	assert_eq(pos, start_position, "get_grid_position should return current position")

	player.set_grid_position(Vector2i(3, 3))
	pos = player.get_grid_position()
	assert_eq(pos, Vector2i(3, 3), "get_grid_position should reflect updated position")


## Test: Player world position updates correctly after move
func test_world_position_updates_after_move():
	var target_grid_pos = start_position + Vector2i(1, 0)
	var target_cell = grid_manager.get_cell(target_grid_pos)
	var expected_world_pos = target_cell.get_center()

	player.attempt_move(Vector2i(1, 0))

	# Wait for tween to complete
	await wait_seconds(0.3)

	var distance = player.position.distance_to(expected_world_pos)
	assert_lt(distance, 1.0, "Player world position should be at target cell center")
