## Main scene controller
##
## Manages the overall game state, coordinates GridManager and Player,
## and handles level setup.

extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var player: Player = $Player

## Fold system for grid transformations
var fold_system: FoldSystem = null

## Game state
var is_level_complete: bool = false

## UI elements
var hud: CanvasLayer = null
var pause_menu: Control = null
var level_complete: Control = null


func _ready() -> void:
	# Start background music
	AudioManager.play_music("gameplay", true)

	# Fix background ColorRect to not block mouse input
	var background = $ColorRect
	if background:
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Wait for grid to be ready
	await get_tree().process_frame

	# Load level from GameManager
	if GameManager.current_level_data == null:
		push_warning("MainScene: No level loaded in GameManager, using fallback test level")
		setup_fallback_level()
	else:
		load_level(GameManager.current_level_data)

	# Initialize FoldSystem
	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)
	add_child(fold_system)

	# Initialize player with grid manager
	if player and grid_manager:
		# Connect FoldSystem to player for validation
		fold_system.set_player(player)

		# Wire GridManager to FoldSystem for preview line validation
		grid_manager.fold_system = fold_system

		# Connect to player signals
		player.goal_reached.connect(_on_player_goal_reached)

	# Initialize GUI
	setup_gui()


## Loads a level from LevelData
func load_level(level_data: LevelData) -> void:
	# Set grid size and cell size
	grid_manager.grid_size = level_data.grid_size
	grid_manager.cell_size = level_data.cell_size

	# Clear existing grid if it exists
	for cell in grid_manager.cells.values():
		cell.queue_free()
	grid_manager.cells.clear()

	# Create new grid with updated size
	grid_manager.create_grid()
	grid_manager.center_grid_on_screen()

	# Apply cell data
	for pos in level_data.cell_data:
		var cell = grid_manager.get_cell(pos)
		if cell:
			cell.set_cell_type(level_data.cell_data[pos])

	# Initialize player at start position
	if player:
		player.initialize(grid_manager, level_data.player_start_position)


## Fallback level for testing without GameManager
func setup_fallback_level() -> void:
	# Create a simple fallback level
	var fallback_data = LevelData.new()
	fallback_data.level_id = "fallback_test"
	fallback_data.level_name = "Test Level"
	fallback_data.grid_size = Vector2i(10, 10)
	fallback_data.cell_size = 64.0
	fallback_data.player_start_position = Vector2i(5, 5)
	fallback_data.par_folds = 5

	# Add a goal cell
	fallback_data.cell_data[Vector2i(7, 7)] = 3  # Goal

	# Set as current level in GameManager
	GameManager.current_level_data = fallback_data
	GameManager.current_level_id = "fallback_test"

	# Load the level
	load_level(fallback_data)


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
		# Use level data from GameManager
		var level_name = GameManager.current_level_data.level_name if GameManager.current_level_data else "Unknown Level"
		var par_folds = GameManager.current_level_data.par_folds if GameManager.current_level_data else -1
		hud.set_level_info(level_name, par_folds)
		hud.set_fold_count(GameManager.fold_count)
		hud.pause_requested.connect(_on_pause_requested)
		hud.restart_requested.connect(_on_restart_requested)
		hud.undo_requested.connect(_on_undo_requested)

	# Load and instantiate Pause Menu as CanvasLayer
	var pause_scene = load("res://scenes/ui/PauseMenu.tscn")
	if pause_scene:
		var pause_canvas = CanvasLayer.new()
		pause_canvas.layer = 100  # High layer to appear on top
		add_child(pause_canvas)

		pause_menu = pause_scene.instantiate()
		pause_canvas.add_child(pause_menu)
		pause_menu.resume_requested.connect(_on_resume_requested)
		pause_menu.restart_requested.connect(_on_restart_requested)
		pause_menu.main_menu_requested.connect(_on_main_menu_requested)

	# Load and instantiate Level Complete screen as CanvasLayer
	var complete_scene = load("res://scenes/ui/LevelComplete.tscn")
	if complete_scene:
		var complete_canvas = CanvasLayer.new()
		complete_canvas.layer = 100  # High layer to appear on top
		add_child(complete_canvas)

		level_complete = complete_scene.instantiate()
		complete_canvas.add_child(level_complete)
		level_complete.next_level_requested.connect(_on_next_level_requested)
		level_complete.retry_requested.connect(_on_restart_requested)
		level_complete.level_select_requested.connect(_on_level_select_requested)
		level_complete.main_menu_requested.connect(_on_main_menu_requested)


## Display level complete UI
func show_win_ui() -> void:
	if level_complete:
		# Complete the level in GameManager
		GameManager.complete_level()

		# Show level complete screen with current stats
		var par_folds = GameManager.current_level_data.par_folds if GameManager.current_level_data else -1
		level_complete.show_complete(GameManager.fold_count, par_folds)


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
	GameManager.restart_level()


## Handle undo request
func _on_undo_requested() -> void:
	# TODO: Implement undo system (Phase 6)
	print("Undo not yet implemented")


## Handle main menu request
func _on_main_menu_requested() -> void:
	get_tree().paused = false  # Ensure game is unpaused
	GameManager.return_to_main_menu()


## Handle next level request
func _on_next_level_requested() -> void:
	get_tree().paused = false  # Ensure game is unpaused
	var next_level_id = GameManager.get_next_level_id()
	if not next_level_id.is_empty():
		GameManager.start_level(next_level_id)
	else:
		# No more levels, return to menu
		print("No more levels! Returning to main menu.")
		GameManager.return_to_main_menu()


## Handle level select request
func _on_level_select_requested() -> void:
	get_tree().paused = false  # Ensure game is unpaused
	# TODO: Open level select screen when created
	print("Level select not yet implemented")
	GameManager.return_to_main_menu()


## Check if level is complete (for testing)
func check_win_condition() -> bool:
	return is_level_complete


## Handle input for fold execution (Issue #9)
func _unhandled_input(event: InputEvent) -> void:
	# Toggle debug mode with F3
	if event.is_action_pressed("ui_debug"):
		toggle_debug_mode()
		return

	# Block input if level is complete
	if is_level_complete:
		return

	# Execute fold when ENTER/SPACE is pressed
	if event.is_action_pressed("ui_accept"):
		execute_fold()


## Toggle debug visualization mode
func toggle_debug_mode() -> void:
	if grid_manager:
		grid_manager.toggle_debug_mode()
		var status = "ON" if grid_manager.debug_mode else "OFF"
		print("Debug mode: %s" % status)


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
	var success = fold_system.execute_fold(anchors[0], anchors[1], true)

	# Clear selection after fold (whether successful or not)
	if grid_manager:
		grid_manager.clear_selection()

	if success:
		# Update fold count in GameManager
		GameManager.increment_fold_count()

		# Update HUD
		if hud:
			hud.set_fold_count(GameManager.fold_count)

		# Update debug displays after fold
		if grid_manager and grid_manager.debug_mode:
			grid_manager.update_debug_displays()

		print("Fold executed successfully! Total folds: %d" % GameManager.fold_count)
	else:
		print("Fold failed - check validation messages")
