## Main scene controller
##
## Manages the overall game state, coordinates GridManager and Player,
## and handles level setup.

extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var player: Player = $Player

## Starting position for player
var player_start_position := Vector2i(5, 5)


func _ready() -> void:
	# Wait for grid to be ready
	await get_tree().process_frame

	# Initialize player with grid manager
	if player and grid_manager:
		player.initialize(grid_manager, player_start_position)

		# Optional: Set up some test walls
		setup_test_level()


## Set up a simple test level with some walls and a goal
func setup_test_level() -> void:
	# Create border walls (top and bottom)
	for x in range(10):
		var top_cell = grid_manager.get_cell(Vector2i(x, 0))
		if top_cell:
			top_cell.set_cell_type(1)  # Wall

		var bottom_cell = grid_manager.get_cell(Vector2i(x, 9))
		if bottom_cell:
			bottom_cell.set_cell_type(1)  # Wall

	# Create border walls (left and right)
	for y in range(10):
		var left_cell = grid_manager.get_cell(Vector2i(0, y))
		if left_cell:
			left_cell.set_cell_type(1)  # Wall

		var right_cell = grid_manager.get_cell(Vector2i(9, y))
		if right_cell:
			right_cell.set_cell_type(1)  # Wall

	# Add some internal walls for testing
	var wall1 = grid_manager.get_cell(Vector2i(3, 3))
	if wall1:
		wall1.set_cell_type(1)
	var wall2 = grid_manager.get_cell(Vector2i(4, 3))
	if wall2:
		wall2.set_cell_type(1)
	var wall3 = grid_manager.get_cell(Vector2i(5, 3))
	if wall3:
		wall3.set_cell_type(1)

	# Add a goal cell
	var goal_cell = grid_manager.get_cell(Vector2i(7, 7))
	if goal_cell:
		goal_cell.set_cell_type(3)

	# Add some water cells (optional)
	var water1 = grid_manager.get_cell(Vector2i(2, 6))
	if water1:
		water1.set_cell_type(2)
	var water2 = grid_manager.get_cell(Vector2i(3, 6))
	if water2:
		water2.set_cell_type(2)
