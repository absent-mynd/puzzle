## Main scene controller
##
## Manages the overall game state, coordinates GridManager and Player,
## and handles level setup.

extends Node2D

@onready var grid_manager: GridManager = $GridManager
@onready var player: Player = $Player

## Fold controller (derive/replay engine adapter) for grid transformations
var fold_system: FoldController = null

## PHASE 8: Player-facing interaction debug toggles. These appear as dropdowns directly
## on the Main node in the inspector so gameplay combinations (Axes A-D) can be explored
## without creating a sub-resource. They are copied into `interaction_config` at runtime.
@export_group("Interaction (debug toggles)")
@export var second_anchor: InteractionConfig.SecondAnchor = InteractionConfig.SecondAnchor.PLACE_THEN_CONFIRM
@export var action_priority: InteractionConfig.ActionPriority = InteractionConfig.ActionPriority.CREASE_DOT_WINS
@export var unfold_blocking: InteractionConfig.UnfoldBlocking = InteractionConfig.UnfoldBlocking.ALLOW_ANY
@export var null_anchor: InteractionConfig.NullAnchor = InteractionConfig.NullAnchor.CENTROID_IN_NULL
@export_group("")

var interaction_config: InteractionConfig = null
var interaction_controller: InteractionController = null

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

	# Initialize FoldController (derive/replay engine over the current grid)
	fold_system = FoldController.new()
	add_child(fold_system)
	fold_system.initialize(grid_manager)

	# F7: apply the level's pre-placed folds before the player is placed, so they ship
	# folded (hidden regions the player can unfold to reveal).
	if GameManager.current_level_data:
		fold_system.apply_preplaced_folds(GameManager.current_level_data.fold_pairs())

	# PHASE 8: Build the interaction config from the inspector dropdowns on this node.
	interaction_config = InteractionConfig.new()
	interaction_config.second_anchor = second_anchor
	interaction_config.action_priority = action_priority
	interaction_config.unfold_blocking = unfold_blocking
	interaction_config.null_anchor = null_anchor

	# Wire the unfold-blocking mode into the controller (0=ALLOW_ANY, 1=BLOCK_ON_INTERSECTION).
	fold_system.unfold_blocking_mode = unfold_blocking

	# Initialize player with grid manager
	if player and grid_manager:
		# Connect FoldController to player for validation
		fold_system.set_player(player)

		# Wire GridManager to FoldController for preview line validation + history
		grid_manager.fold_system = fold_system

		# PHASE 8: Wire the interaction config into GridManager (Axis D eligibility)
		grid_manager.interaction_config = interaction_config

		# Seed undo history with the initial (post-load) state.
		fold_system.seed_history()

		# Connect to player signals
		player.goal_reached.connect(_on_player_goal_reached)

	# PHASE 8: Player-facing interaction controller
	interaction_controller = InteractionController.new()
	add_child(interaction_controller)
	interaction_controller.initialize(grid_manager, fold_system, player, self, interaction_config)

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

	# Apply cell data. Values may be a plain int type or a {type, ...params} dict
	# (F3 behavioral tiles) — read both uniformly; carry per-instance params on the
	# view Cell so they reach the engine's BaseTile at base construction.
	for pos in level_data.cell_data:
		var cell = grid_manager.get_cell(pos)
		if cell:
			cell.set_cell_type(level_data.type_at(pos))
			cell.tile_data = level_data.data_at(pos)

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
		hud.set_can_undo(false)  # Initialize undo button as disabled
		hud.set_test_mode(GameManager.is_testing_from_editor)
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
		pause_menu.editor_requested.connect(_on_editor_requested)
		pause_menu.set_editor_mode(GameManager.is_testing_from_editor)

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
		level_complete.editor_requested.connect(_on_editor_requested)
		level_complete.set_editor_mode(GameManager.is_testing_from_editor)


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


## Handle undo request (from UI button or U key)
##
## Baba-Is-You-style global undo: steps the whole game state back by one input,
## reversing the last move, fold, unfold, or anchor placement/cancel uniformly.
func _on_undo_requested() -> void:
	if not fold_system or not fold_system.can_undo():
		print("No actions to undo")
		return

	if fold_system.undo():
		_sync_after_change()
		print("Undo successful! Folds: %d" % GameManager.fold_count)


## Sync GameManager fold count + HUD to the engine's current state. Called after
## any change to the fold list (fold, unfold, undo).
func _sync_after_change() -> void:
	if fold_system and fold_system.engine:
		GameManager.fold_count = fold_system.engine.fold_count()
	if hud:
		hud.set_fold_count(GameManager.fold_count)
		hud.set_can_undo(fold_system.can_undo() if fold_system else false)


## Handle main menu request
func _on_main_menu_requested() -> void:
	get_tree().paused = false  # Ensure game is unpaused
	GameManager.return_to_main_menu()


## Handle "Back to Editor" request (only reachable while testing a level from the editor)
func _on_editor_requested() -> void:
	get_tree().paused = false  # Ensure game is unpaused
	GameManager.return_to_editor()


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

	# PHASE 6: Handle keyboard undo (U key). Mark handled so the HUD's _unhandled_input
	# doesn't also fire undo for the same press (deterministic single undo).
	if event.is_action_pressed("ui_undo"):
		_on_undo_requested()
		get_viewport().set_input_as_handled()
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

	# PHASE 8: Prefer the crease dot (explicit unfold handle), then fall back to seam zones
	var click_result = fold_system.detect_crease_dot_click(local_pos)
	if click_result.is_empty():
		click_result = fold_system.detect_seam_click(local_pos)

	if not click_result:
		# Not clicking on a seam or crease dot, ignore
		return

	# Clicked on a seam or crease dot!
	perform_unfold(click_result["fold_id"], click_result["can_undo"])


## Unfold a fold and update bookkeeping (shared by mouse click and facing-interact)
##
## @param fold_id: The fold to unfold
## @param can_undo: Whether the fold is currently unfoldable (from click/detection result)
## @return: true if the unfold succeeded
func perform_unfold(fold_id: int, can_undo: bool) -> bool:
	if not can_undo:
		_notify(FoldFailReason.message("blocked by a newer crossing fold"), UIPalette.DANGER)
		return false

	# UNFOLD this seam (removes the fold from the list and re-derives)
	var success = fold_system.unfold_seam(fold_id)
	if success:
		# Unfold is itself an undoable input (Baba-style).
		fold_system.commit_input()
		_sync_after_change()
	else:
		_notify(FoldFailReason.message("player would be stranded"), UIPalette.DANGER)
	return success


## Surface a short message to the player via the HUD toast (falls back to print if no HUD).
func _notify(text: String, color: Color = Color.WHITE) -> void:
	if hud and hud.has_method("show_toast"):
		hud.show_toast(text, color)
	else:
		print(text)


## Execute fold with selected anchors
func execute_fold() -> void:
	if not fold_system or not grid_manager:
		return

	# Check if we have exactly 2 anchors selected
	var anchors = grid_manager.get_selected_anchors()
	if anchors.size() != 2:
		_notify(FoldFailReason.message("needs two anchors"), UIPalette.WARNING)
		return

	# Execute the fold (with animation)
	var a1 = anchors[0]
	var a2 = anchors[1]

	# Pre-validate so we can tell the player WHY on failure (the reason is otherwise
	# swallowed by execute_fold's bool return). A deferred player-position rejection
	# still fails at commit with an empty reason -> generic fallback.
	var reason := ""
	var v := fold_system.validate_fold(a1, a2)
	if v.valid:
		v = fold_system.validate_fold_with_player(a1, a2)
	if not v.valid:
		reason = v.reason

	var success = await fold_system.execute_fold(a1, a2, true)

	if success:
		if grid_manager:
			grid_manager.clear_selection()
		_finalize_fold_success()
	else:
		# Briefly show the invalid region (e.g. deferred player-position rejection).
		# Clear first so the flash's auto-clear timer hides it (no anchors remain here).
		if grid_manager:
			grid_manager.clear_selection()
			grid_manager.flash_invalid_fold(a1, a2)
		_notify(FoldFailReason.message(reason), UIPalette.DANGER)


## Shared post-fold bookkeeping for both the debug flow and the player-interact flow
##
## Records the fold as an undoable input and syncs fold count + HUD.
func _finalize_fold_success() -> void:
	# The fold is an undoable input (Baba-style history).
	if fold_system:
		fold_system.commit_input()
	_sync_after_change()
	print("Fold executed successfully! Total folds: %d" % GameManager.fold_count)
