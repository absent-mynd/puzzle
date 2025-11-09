## Main scene controller
##
## Manages the overall game state, coordinates GridManager and Player,
## and handles level setup.

extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var player: Player = $Player

## Fold system for grid transformations
var fold_system: FoldSystem = null

## Snapshot history for unified undo system (Phase 6 Task 9)
var snapshot_history: SnapshotHistory = null

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

	# Initialize SnapshotHistory (Phase 6 Task 9)
	snapshot_history = SnapshotHistory.new()

	# Initialize player with grid manager
	if player and grid_manager:
		# Connect FoldSystem to player for validation
		fold_system.set_player(player)

		# Wire GridManager to FoldSystem for preview line validation
		grid_manager.fold_system = fold_system

		# Connect to player signals
		player.goal_reached.connect(_on_player_goal_reached)
		player.position_changed.connect(_on_player_position_changed)  # Phase 6 Task 7

		# Connect to fold system signals (Phase 6 Task 8 - UNFOLD as action)
		fold_system.fold_unfolded.connect(_on_fold_unfolded)

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


## Handle player position changes (Phase 6 Task 9 - Snapshot-based Undo)
## Captures game state snapshot after successful player move
func _on_player_position_changed(old_pos: Vector2i, new_pos: Vector2i) -> void:
	if not snapshot_history or not fold_system:
		return

	# Capture snapshot AFTER player has moved
	var snapshot = fold_system.create_game_snapshot(player, "move", "Player moved from %s to %s" % [old_pos, new_pos])
	snapshot_history.push_snapshot(snapshot)

	# Update undo button state
	if hud:
		hud.set_can_undo(snapshot_history.can_undo())


## Handle fold unfolded (seam click) - Phase 6 Task 9
## Captures game state snapshot after successful unfold
func _on_fold_unfolded(fold_id: int, anchor1: Vector2i, anchor2: Vector2i, orientation: String) -> void:
	if not snapshot_history or not fold_system:
		return

	# Capture snapshot AFTER unfold has completed
	var snapshot = fold_system.create_game_snapshot(player, "unfold", "Unfolded fold %d at %s-%s" % [fold_id, anchor1, anchor2])
	snapshot_history.push_snapshot(snapshot)

	# Update undo button state
	if hud:
		hud.set_can_undo(snapshot_history.can_undo())


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
		hud.set_can_undo(false)  # Initialize undo button as disabled
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


## Handle undo request (from UI button)
func _on_undo_requested() -> void:
	# Phase 6 Task 9: Unified snapshot-based undo system
	if not snapshot_history or not snapshot_history.can_undo():
		print("No game states to undo")
		return

	# Pop the most recent snapshot
	var snapshot = snapshot_history.pop_snapshot()

	if snapshot.is_empty():
		print("No game states to undo")
		return

	# Restore game state from snapshot (single unified approach)
	var success = fold_system.restore_from_snapshot(snapshot, player)

	if success:
		# Update HUD with restored state
		if hud:
			hud.set_fold_count(GameManager.fold_count)
			hud.set_can_undo(snapshot_history.can_undo())

		# Log action type for debugging
		var action_type = snapshot.get("action_type", "unknown")
		var action_summary = snapshot.get("action_summary", "")
		print("Undo successful! (%s) %s" % [action_type, action_summary])
	else:
		# Should not happen with snapshots, but handle gracefully
		print("Failed to restore from snapshot")


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


## Handle input for fold execution (Issue #9) and seam clicking (Phase 6)
func _unhandled_input(event: InputEvent) -> void:
	# Block input if level is complete
	if is_level_complete:
		return

	# PHASE 6: Handle mouse clicks on seams for unfold
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			handle_mouse_click(event.position)
			return

	# PHASE 6: Handle keyboard undo (U key)
	if event.is_action_pressed("ui_undo"):
		_on_undo_requested()
		return

	# Execute fold when ENTER/SPACE is pressed
	if event.is_action_pressed("ui_accept"):
		execute_fold()


## Handle mouse click for seam-based undo (Phase 6)
func handle_mouse_click(mouse_position: Vector2) -> void:
	if not fold_system or not grid_manager:
		return

	# Convert mouse position from global (screen) to local (GridManager) coordinates
	var local_pos = grid_manager.to_local(mouse_position)

	# Check if click is on a seam
	var click_result = fold_system.detect_seam_click(local_pos)

	if not click_result:
		# Not clicking on a seam, ignore
		return

	# Clicked on a seam!
	var fold_id = click_result["fold_id"]
	var can_undo = click_result["can_undo"]

	if can_undo:
		# UNFOLD this seam (geometric reversal without state restoration)
		# Phase 6 Task 9: Snapshot is automatically captured by fold_unfolded signal
		var success = fold_system.unfold_seam(fold_id)
		if success:
			# Update HUD (snapshot capture happens automatically via signal)
			if hud:
				hud.set_fold_count(GameManager.fold_count)
				hud.set_can_undo(snapshot_history.can_undo())
			print("Seam unfold successful! Fold %d unfolded. Total folds: %d" % [fold_id, GameManager.fold_count])
		else:
			print("Cannot unfold fold %d - player may be standing on seam" % fold_id)
	else:
		# Seam is blocked
		print("Cannot unfold fold %d - it's blocked by newer intersecting folds" % fold_id)


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
		# Update fold count in GameManager
		GameManager.increment_fold_count()

		# Update HUD
		if hud:
			hud.set_fold_count(GameManager.fold_count)

		# Phase 6 Task 9: Capture game state snapshot after successful fold
		if snapshot_history and fold_system:
			var newest_fold_id = -1
			for record in fold_system.fold_history:
				if record["fold_id"] > newest_fold_id:
					newest_fold_id = record["fold_id"]

			if newest_fold_id >= 0:
				var snapshot = fold_system.create_game_snapshot(player, "fold", "Fold executed at %s-%s" % [anchors[0], anchors[1]])
				snapshot_history.push_snapshot(snapshot)

				# Update undo button state
				if hud:
					hud.set_can_undo(snapshot_history.can_undo())

		print("Fold executed successfully! Total folds: %d" % GameManager.fold_count)
	else:
		print("Fold failed - check validation messages")


