## Main scene controller
##
## Manages the overall game state, coordinates GridManager and Player,
## and handles level setup.

extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var player: Player = $Player

## Starting position for player
var player_start_position := Vector2i(5, 5)

## Fold system for grid transformations
var fold_system: FoldSystem = null

## Game state
var is_level_complete: bool = false

## UI elements
var win_ui: Control = null
var win_label: Label = null
var restart_button: Button = null


func _ready() -> void:
	# Wait for grid to be ready
	await get_tree().process_frame

	# Initialize FoldSystem (Issue #9)
	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)
	add_child(fold_system)

	# Initialize player with grid manager
	if player and grid_manager:
		player.initialize(grid_manager, player_start_position)

		# Connect FoldSystem to player for validation
		fold_system.set_player(player)

		# Wire GridManager to FoldSystem for preview line validation
		grid_manager.fold_system = fold_system

		# Connect to player signals
		player.goal_reached.connect(_on_player_goal_reached)

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


## Handle player reaching goal
func _on_player_goal_reached() -> void:
	if is_level_complete:
		return  # Already won, don't trigger again

	is_level_complete = true

	# Disable player input
	if player:
		player.input_enabled = false

	show_win_ui()


## Display win UI
func show_win_ui() -> void:
	# Create UI container
	win_ui = Control.new()
	win_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(win_ui)

	# Create semi-transparent background
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_ui.add_child(bg)

	# Create center container
	var center_container = VBoxContainer.new()
	center_container.custom_minimum_size = Vector2(400, 200)
	center_container.position = Vector2(440, 260)  # Centered on 1280x720
	win_ui.add_child(center_container)

	# Add win message
	win_label = Label.new()
	win_label.text = "LEVEL COMPLETE!"
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 48)
	win_label.add_theme_color_override("font_color", Color.GREEN)
	center_container.add_child(win_label)

	# Add spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	center_container.add_child(spacer)

	# Add restart button
	restart_button = Button.new()
	restart_button.text = "Restart Level"
	restart_button.custom_minimum_size = Vector2(200, 50)
	restart_button.pressed.connect(_on_restart_pressed)
	center_container.add_child(restart_button)


## Handle restart button press
func _on_restart_pressed() -> void:
	# Reload the scene
	get_tree().reload_current_scene()


## Check if level is complete (for testing)
func check_win_condition() -> bool:
	return is_level_complete


## Handle input for fold execution (Issue #9)
func _unhandled_input(event: InputEvent) -> void:
	# Block input if level is complete
	if is_level_complete:
		return

	# Execute fold when ENTER/SPACE is pressed
	if event.is_action_pressed("ui_accept"):
		execute_fold()


## Execute fold with selected anchors
func execute_fold() -> void:
	if not fold_system or not grid_manager:
		return

	# Check if we have exactly 2 anchors selected
	var anchors = grid_manager.get_selected_anchors()
	if anchors.size() != 2:
		print("Select exactly 2 anchor cells to fold")
		return

	# Execute the fold (with animation)
	var success = await fold_system.execute_fold(anchors[0], anchors[1], true)

	# Clear selection after fold (whether successful or not)
	if grid_manager:
		grid_manager.clear_selection()

	if success:
		print("Fold executed successfully!")
	else:
		print("Fold failed - check validation messages")
