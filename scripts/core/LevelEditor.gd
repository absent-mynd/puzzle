## Space-Folding Puzzle Game - Level Editor
##
## A keyboard-only level editor for creating and editing puzzle levels.
## Allows users to place cells, set player start position, and save/load levels.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends Node2D
class_name LevelEditor

## Properties

## Grid management
var grid_manager: GridManager
var level_manager: LevelManager
var current_level: LevelData

## Cursor state
var cursor_position: Vector2i = Vector2i(0, 0)
var cursor_visual: Polygon2D

## Player start position marker
var player_start_marker: Polygon2D
var player_start_position: Vector2i = Vector2i(1, 1)

## UI elements
var status_label: Label
var help_label: Label

## Constants for colors
const CURSOR_COLOR = Color(1.0, 1.0, 0.0, 0.6)  # Yellow with transparency
const PLAYER_MARKER_COLOR = Color(1.0, 0.0, 1.0, 0.8)  # Magenta

## File dialog state
var save_filename: String = "custom_level"
var input_mode: String = "edit"  # "edit", "save_input", "load_input", "browse"
var input_buffer: String = ""

## Browse mode state
var custom_level_files: Array[String] = []
var browse_selection_index: int = 0
var browse_label: Label


## Initialize the level editor
func _ready() -> void:
	# Create grid manager
	grid_manager = GridManager.new()
	add_child(grid_manager)

	# Create level manager
	level_manager = LevelManager.new()
	add_child(level_manager)

	# Create new level
	current_level = LevelData.new()
	current_level.level_id = "custom_" + str(Time.get_unix_time_from_system())
	current_level.level_name = "Custom Level"
	current_level.grid_size = Vector2i(10, 10)
	current_level.cell_size = 64.0
	current_level.player_start_position = player_start_position

	# Wait for grid to be ready
	await get_tree().process_frame

	# Create cursor visual
	create_cursor_visual()

	# Create player start marker
	create_player_start_marker()

	# Create UI
	create_ui()

	# Update displays
	update_cursor_visual()
	update_player_marker()
	update_status()


## Create the cursor visual indicator
func create_cursor_visual() -> void:
	cursor_visual = Polygon2D.new()
	cursor_visual.color = CURSOR_COLOR
	add_child(cursor_visual)


## Create the player start position marker
func create_player_start_marker() -> void:
	player_start_marker = Polygon2D.new()
	player_start_marker.color = PLAYER_MARKER_COLOR
	add_child(player_start_marker)


## Create UI elements
func create_ui() -> void:
	# Status label (top-left)
	status_label = Label.new()
	status_label.position = Vector2(10, 10)
	status_label.add_theme_font_size_override("font_size", 20)
	add_child(status_label)

	# Help label (bottom-left)
	help_label = Label.new()
	help_label.position = Vector2(10, 600)
	help_label.add_theme_font_size_override("font_size", 16)
	help_label.text = """Keyboard Controls:
Arrow Keys: Move cursor
0: Empty  1: Wall  2: Water  3: Goal
P: Set player start
S: Save level  L: Load level  N: New level
B: Browse levels  T: Test level
ESC: Exit editor"""
	add_child(help_label)

	# Browse label (for browse mode, initially hidden)
	browse_label = Label.new()
	browse_label.position = Vector2(10, 150)
	browse_label.add_theme_font_size_override("font_size", 18)
	browse_label.visible = false
	add_child(browse_label)


## Handle keyboard input
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	# Handle different input modes
	if input_mode == "save_input":
		handle_save_input(event)
		return
	elif input_mode == "load_input":
		handle_load_input(event)
		return
	elif input_mode == "browse":
		handle_browse_input(event)
		return

	# Normal edit mode
	match event.keycode:
		KEY_UP:
			move_cursor(Vector2i(0, -1))
		KEY_DOWN:
			move_cursor(Vector2i(0, 1))
		KEY_LEFT:
			move_cursor(Vector2i(-1, 0))
		KEY_RIGHT:
			move_cursor(Vector2i(1, 0))
		KEY_0:
			set_cell_type_at_cursor(0)
		KEY_1:
			set_cell_type_at_cursor(1)
		KEY_2:
			set_cell_type_at_cursor(2)
		KEY_3:
			set_cell_type_at_cursor(3)
		KEY_P:
			set_player_start_at_cursor()
		KEY_S:
			start_save_input()
		KEY_L:
			start_load_input()
		KEY_N:
			new_level()
		KEY_B:
			start_browse_mode()
		KEY_T:
			test_level()
		KEY_ESCAPE:
			exit_editor()


## Move cursor by delta
func move_cursor(delta: Vector2i) -> void:
	var new_pos = cursor_position + delta

	# Clamp to grid bounds
	if grid_manager.is_valid_position(new_pos):
		cursor_position = new_pos
		update_cursor_visual()
		update_status()


## Set cell type at current cursor position
func set_cell_type_at_cursor(cell_type: int) -> void:
	var cell = grid_manager.get_cell(cursor_position)
	if cell:
		cell.set_cell_type(cell_type)

		# Update level data
		if cell_type == 0:
			# Remove empty cells from level data
			current_level.cell_data.erase(cursor_position)
		else:
			current_level.cell_data[cursor_position] = cell_type

		update_status()


## Set player start position at cursor
func set_player_start_at_cursor() -> void:
	player_start_position = cursor_position
	current_level.player_start_position = player_start_position
	update_player_marker()
	update_status()


## Update cursor visual position and appearance
func update_cursor_visual() -> void:
	if not cursor_visual or not grid_manager:
		return

	var cell = grid_manager.get_cell(cursor_position)
	if cell:
		# Create a highlighted border around the cell
		var size = grid_manager.cell_size
		var world_pos = grid_manager.grid_to_world(cursor_position)

		cursor_visual.polygon = PackedVector2Array([
			world_pos,
			world_pos + Vector2(size, 0),
			world_pos + Vector2(size, size),
			world_pos + Vector2(0, size)
		])


## Update player start marker position
func update_player_marker() -> void:
	if not player_start_marker or not grid_manager:
		return

	var world_pos = grid_manager.grid_to_world(player_start_position)
	var size = grid_manager.cell_size
	var center = world_pos + Vector2(size, size) / 2
	var radius = size * 0.3

	# Create a triangle pointing up
	player_start_marker.polygon = PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius * 0.866, radius * 0.5),
		center + Vector2(-radius * 0.866, radius * 0.5)
	])


## Update status label
func update_status() -> void:
	if not status_label:
		return

	var cell = grid_manager.get_cell(cursor_position)
	var cell_type_name = "Empty"
	if cell:
		match cell.cell_type:
			0: cell_type_name = "Empty"
			1: cell_type_name = "Wall"
			2: cell_type_name = "Water"
			3: cell_type_name = "Goal"

	status_label.text = "Level Editor\n"
	status_label.text += "Cursor: (%d, %d)\n" % [cursor_position.x, cursor_position.y]
	status_label.text += "Cell Type: %s\n" % cell_type_name
	status_label.text += "Player Start: (%d, %d)" % [player_start_position.x, player_start_position.y]


## Start save input mode
func start_save_input() -> void:
	input_mode = "save_input"
	input_buffer = save_filename
	status_label.text = "Save as (press ENTER): %s_" % input_buffer


## Handle save input
func handle_save_input(event: InputEventKey) -> void:
	if event.keycode == KEY_ENTER:
		save_filename = input_buffer
		save_level()
		input_mode = "edit"
		update_status()
	elif event.keycode == KEY_ESCAPE:
		input_mode = "edit"
		update_status()
	elif event.keycode == KEY_BACKSPACE:
		if input_buffer.length() > 0:
			input_buffer = input_buffer.substr(0, input_buffer.length() - 1)
			status_label.text = "Save as (press ENTER): %s_" % input_buffer
	elif event.unicode >= 32 and event.unicode < 127:  # Printable characters
		input_buffer += char(event.unicode)
		status_label.text = "Save as (press ENTER): %s_" % input_buffer


## Start load input mode
func start_load_input() -> void:
	input_mode = "load_input"
	input_buffer = save_filename
	status_label.text = "Load file (press ENTER): %s_" % input_buffer


## Handle load input
func handle_load_input(event: InputEventKey) -> void:
	if event.keycode == KEY_ENTER:
		save_filename = input_buffer
		load_level()
		input_mode = "edit"
		update_status()
	elif event.keycode == KEY_ESCAPE:
		input_mode = "edit"
		update_status()
	elif event.keycode == KEY_BACKSPACE:
		if input_buffer.length() > 0:
			input_buffer = input_buffer.substr(0, input_buffer.length() - 1)
			status_label.text = "Load file (press ENTER): %s_" % input_buffer
	elif event.unicode >= 32 and event.unicode < 127:  # Printable characters
		input_buffer += char(event.unicode)
		status_label.text = "Load file (press ENTER): %s_" % input_buffer


## Save the current level
func save_level() -> void:
	# Ensure player start position is set in level data
	current_level.player_start_position = player_start_position

	# Create levels directory if it doesn't exist
	var levels_dir = "user://levels/"
	if not DirAccess.dir_exists_absolute(levels_dir):
		DirAccess.make_dir_recursive_absolute(levels_dir)

	var file_path = levels_dir + save_filename + ".json"
	var success = level_manager.save_level(current_level, file_path)

	if success:
		status_label.text = "Level saved to:\n%s" % file_path
		await get_tree().create_timer(2.0).timeout
	else:
		status_label.text = "Failed to save level!"
		await get_tree().create_timer(2.0).timeout

	update_status()


## Load a level
func load_level() -> void:
	var levels_dir = "user://levels/"
	var file_path = levels_dir + save_filename + ".json"

	var loaded_level = level_manager.load_level(file_path)

	if loaded_level:
		current_level = loaded_level
		player_start_position = current_level.player_start_position

		# Apply level data to grid
		apply_level_to_grid()

		status_label.text = "Level loaded: %s" % current_level.level_name
		await get_tree().create_timer(2.0).timeout
	else:
		status_label.text = "Failed to load level!"
		await get_tree().create_timer(2.0).timeout

	update_status()


## Apply current level data to the grid
func apply_level_to_grid() -> void:
	# Clear all cells first
	for y in range(grid_manager.grid_size.y):
		for x in range(grid_manager.grid_size.x):
			var grid_pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(grid_pos)
			if cell:
				cell.set_cell_type(0)

	# Apply cell data from level
	for grid_pos in current_level.cell_data:
		var cell = grid_manager.get_cell(grid_pos)
		if cell:
			cell.set_cell_type(current_level.cell_data[grid_pos])

	# Update visuals
	update_player_marker()
	update_cursor_visual()


## Create a new empty level
func new_level() -> void:
	# Clear all cells
	for y in range(grid_manager.grid_size.y):
		for x in range(grid_manager.grid_size.x):
			var grid_pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(grid_pos)
			if cell:
				cell.set_cell_type(0)

	# Reset level data
	current_level = LevelData.new()
	current_level.level_id = "custom_" + str(Time.get_unix_time_from_system())
	current_level.level_name = "New Level"
	current_level.grid_size = Vector2i(10, 10)
	current_level.cell_size = 64.0
	current_level.player_start_position = Vector2i(1, 1)

	player_start_position = Vector2i(1, 1)
	cursor_position = Vector2i(0, 0)

	update_cursor_visual()
	update_player_marker()
	update_status()


## Start browse mode
func start_browse_mode() -> void:
	# Get list of custom level files
	var levels_dir = "user://levels/"
	custom_level_files = FileUtils.get_custom_level_files(levels_dir)

	if custom_level_files.is_empty():
		status_label.text = "No custom levels found!\nPress any key to continue..."
		await get_tree().create_timer(2.0).timeout
		update_status()
		return

	input_mode = "browse"
	browse_selection_index = 0
	browse_label.visible = true
	cursor_visual.visible = false
	player_start_marker.visible = false
	update_browse_display()


## Handle browse mode input
func handle_browse_input(event: InputEventKey) -> void:
	if event.keycode == KEY_UP:
		browse_selection_index = max(0, browse_selection_index - 1)
		update_browse_display()
	elif event.keycode == KEY_DOWN:
		browse_selection_index = min(custom_level_files.size() - 1, browse_selection_index + 1)
		update_browse_display()
	elif event.keycode == KEY_ENTER:
		# Load selected level for editing
		save_filename = custom_level_files[browse_selection_index]
		exit_browse_mode()
		load_level()
	elif event.keycode == KEY_T:
		# Test/play selected level
		save_filename = custom_level_files[browse_selection_index]
		exit_browse_mode()
		test_level()
	elif event.keycode == KEY_ESCAPE:
		exit_browse_mode()


## Update browse display
func update_browse_display() -> void:
	if not browse_label:
		return

	var display_text = "=== Browse Custom Levels ===\n\n"
	display_text += "Use UP/DOWN to select\n"
	display_text += "ENTER to edit, T to test/play\n"
	display_text += "ESC to cancel\n\n"

	for i in range(custom_level_files.size()):
		var prefix = "  "
		if i == browse_selection_index:
			prefix = "> "
		display_text += prefix + custom_level_files[i] + "\n"

	browse_label.text = display_text
	status_label.text = "Browse Mode"


## Exit browse mode
func exit_browse_mode() -> void:
	input_mode = "edit"
	browse_label.visible = false
	cursor_visual.visible = true
	player_start_marker.visible = true
	update_status()


## Test/play the current level
func test_level() -> void:
	# Save the current level temporarily
	current_level.player_start_position = player_start_position

	# Create levels directory if it doesn't exist
	var levels_dir = "user://levels/"
	if not DirAccess.dir_exists_absolute(levels_dir):
		DirAccess.make_dir_recursive_absolute(levels_dir)

	var file_path = levels_dir + save_filename + ".json"
	var success = level_manager.save_level(current_level, file_path)

	if not success:
		status_label.text = "Failed to save level for testing!"
		await get_tree().create_timer(2.0).timeout
		update_status()
		return

	# Store the file path in GameManager to load it
	GameManager.current_level_id = ""
	GameManager.current_level_data = current_level.clone()
	GameManager.fold_count = 0
	GameManager.level_start_time = Time.get_ticks_msec() / 1000.0

	# Load the game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Exit the editor
func exit_editor() -> void:
	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
