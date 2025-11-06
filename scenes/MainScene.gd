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
var hud: CanvasLayer = null
var pause_menu: Control = null
var level_complete: Control = null

## Fold counter
var fold_count: int = 0


func _ready() -> void:
	# Fix background ColorRect to not block mouse input
	var background = $ColorRect
	if background:
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	# Initialize GUI
	setup_gui()


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


## Set up GUI components
func setup_gui() -> void:
	# Load and instantiate HUD
	var hud_scene = load("res://scenes/ui/HUD.tscn")
	if hud_scene:
		hud = hud_scene.instantiate()
		add_child(hud)
		hud.set_level_info("Test Level", 5)  # Par of 5 folds
		hud.pause_requested.connect(_on_pause_requested)
		hud.restart_requested.connect(_on_restart_requested)
		hud.undo_requested.connect(_on_undo_requested)

	# Load and instantiate Pause Menu
	var pause_scene = load("res://scenes/ui/PauseMenu.tscn")
	if pause_scene:
		pause_menu = pause_scene.instantiate()
		add_child(pause_menu)
		pause_menu.resume_requested.connect(_on_resume_requested)
		pause_menu.restart_requested.connect(_on_restart_requested)
		pause_menu.main_menu_requested.connect(_on_main_menu_requested)

	# Load and instantiate Level Complete screen
	var complete_scene = load("res://scenes/ui/LevelComplete.tscn")
	if complete_scene:
		level_complete = complete_scene.instantiate()
		add_child(level_complete)
		level_complete.next_level_requested.connect(_on_next_level_requested)
		level_complete.retry_requested.connect(_on_restart_requested)
		level_complete.level_select_requested.connect(_on_level_select_requested)
		level_complete.main_menu_requested.connect(_on_main_menu_requested)


## Display level complete UI
func show_win_ui() -> void:
	if level_complete:
		level_complete.show_complete(fold_count, 5)  # Par of 5 folds


## Handle pause request
func _on_pause_requested() -> void:
	if pause_menu:
		pause_menu.show_pause_menu()


## Handle resume request
func _on_resume_requested() -> void:
	# Game automatically resumes when pause menu hides
	pass


## Handle restart request
func _on_restart_requested() -> void:
	get_tree().paused = false  # Ensure game is unpaused
	get_tree().reload_current_scene()


## Handle undo request
func _on_undo_requested() -> void:
	# TODO: Implement undo system (Phase 6)
	print("Undo not yet implemented")


## Handle main menu request
func _on_main_menu_requested() -> void:
	get_tree().paused = false  # Ensure game is unpaused
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


## Handle next level request
func _on_next_level_requested() -> void:
	# TODO: Load next level when level system is implemented
	print("Next level not yet implemented")
	_on_restart_requested()


## Handle level select request
func _on_level_select_requested() -> void:
	# TODO: Open level select screen
	print("Level select not yet implemented")
	_on_main_menu_requested()


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
		fold_count += 1
		if hud:
			hud.set_fold_count(fold_count)
		print("Fold executed successfully! Total folds: %d" % fold_count)
	else:
		print("Fold failed - check validation messages")
