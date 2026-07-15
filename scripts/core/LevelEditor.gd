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

## Currently selected paint type (0=empty, 1=wall, 2=water, 3=goal). Used by mouse painting
## and shown in the on-screen palette.
var current_paint_type: int = 1

## Last grid cell painted during a mouse drag (avoids redundant repaints)
var last_painted_pos: Vector2i = Vector2i(-1, -1)

## Player start position marker
var player_start_marker: Polygon2D
var player_start_position: Vector2i = Vector2i(1, 1)

## UI elements
var status_label: Label
var help_label: Label

## Tool palette (Part C): a row of type swatches; the active one is highlighted.
var palette_container: HBoxContainer
var palette_swatches: Dictionary = {}  # cell_type:int -> Panel

## Constants for colors
const CURSOR_COLOR = Color(1.0, 1.0, 0.0, 0.6)  # Yellow with transparency
const PLAYER_MARKER_COLOR = Color(1.0, 0.0, 1.0, 0.8)  # Magenta

## File dialog state
var save_filename: String = "custom_level"
# input_mode: "edit", "save_input", "load_input", "resize_input", "metadata_input", "browse"
var input_mode: String = "edit"
var input_buffer: String = ""

## Metadata editing: which field is currently being typed (0=name, 1=par, 2=difficulty)
var metadata_field: int = 0

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

	# Restore a stashed editing session if we're returning from a test play; otherwise
	# start a fresh empty level.
	var restoring := not GameManager.editor_session.is_empty()
	if restoring:
		current_level = GameManager.editor_session["level_data"]
		cursor_position = GameManager.editor_session["cursor"]
		player_start_position = GameManager.editor_session["player_start"]
		save_filename = GameManager.editor_session["filename"]
		GameManager.editor_session = {}  # consume once
	else:
		current_level = LevelData.new()
		current_level.level_id = "custom_" + str(Time.get_unix_time_from_system())
		current_level.level_name = "Custom Level"
		current_level.grid_size = Vector2i(10, 10)
		current_level.cell_size = 64.0
		current_level.player_start_position = player_start_position

	# Wait for grid to be ready (GridManager._ready runs create_grid on this frame)
	await get_tree().process_frame

	# Create cursor visual
	create_cursor_visual()

	# Create player start marker
	create_player_start_marker()

	# Create UI
	create_ui()

	# When restoring, rebuild the grid at the stashed size (resize_grid repaints the cells).
	if restoring:
		resize_grid(current_level.grid_size)

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
	help_label.position = Vector2(10, 560)
	help_label.add_theme_font_size_override("font_size", 16)
	help_label.text = """Keyboard Controls:
Arrow Keys: Move cursor | Mouse: Click/drag to paint, right-click erase
0: Empty  1: Wall  2: Water  3: Goal (also sets paint type)
P: Set player start  G: Resize grid  M: Edit metadata
S: Save level  L: Load level  N: New level
B: Browse levels  T: Test level  ESC: Exit editor"""
	add_child(help_label)

	# Tool palette (Part C): swatch row showing the active paint type
	create_palette()
	update_palette()

	# Browse label (for browse mode, initially hidden)
	browse_label = Label.new()
	browse_label.position = Vector2(10, 150)
	browse_label.add_theme_font_size_override("font_size", 18)
	browse_label.visible = false
	add_child(browse_label)


## Type -> (display name, swatch color). Mirrors Cell.get_cell_color_for_type so the palette
## matches how cells actually render in-game.
const PAINT_TYPES := {
	0: {"name": "Empty",              "color": Color(0.8, 0.8, 0.8)},
	1: {"name": "Wall",               "color": Color(0.2, 0.2, 0.2)},
	2: {"name": "Water",              "color": Color(0.2, 0.4, 1.0)},
	3: {"name": "Goal",               "color": Color(0.2, 1.0, 0.2)},
	6: {"name": "Unanchorable Floor", "color": Color(0.75, 0.7, 0.85)},
	7: {"name": "Unanchorable Wall",  "color": Color(0.25, 0.15, 0.3)},
}


## Create the on-screen tool palette: one framed swatch per paint type.
func create_palette() -> void:
	palette_container = HBoxContainer.new()
	palette_container.position = Vector2(10, 110)
	palette_container.add_theme_constant_override("separation", 12)
	add_child(palette_container)

	for cell_type in [0, 1, 2, 3, 6, 7]:
		var info = PAINT_TYPES[cell_type]

		# Frame Panel — its border is toggled to show which type is active.
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(96, 74)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(vbox)

		var swatch := ColorRect.new()
		swatch.color = info["color"]
		swatch.custom_minimum_size = Vector2(88, 44)
		vbox.add_child(swatch)

		var label := Label.new()
		label.text = "%d: %s" % [cell_type, info["name"]]
		label.add_theme_font_size_override("font_size", 13)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)

		palette_container.add_child(frame)
		palette_swatches[cell_type] = frame


## Highlight the swatch matching current_paint_type.
func update_palette() -> void:
	for cell_type in palette_swatches:
		var frame: Panel = palette_swatches[cell_type]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 0.6)
		if cell_type == current_paint_type:
			style.border_color = Color(1.0, 1.0, 0.0)  # yellow highlight
			style.set_border_width_all(4)
		else:
			style.border_color = Color(0.4, 0.4, 0.4)
			style.set_border_width_all(1)
		frame.add_theme_stylebox_override("panel", style)


## Handle keyboard + mouse input
func _input(event: InputEvent) -> void:
	# Mouse painting is only active in normal edit mode (not while typing a filename etc.)
	if input_mode == "edit" and _handle_mouse_paint(event):
		return

	if not event is InputEventKey or not event.pressed:
		return

	# Handle different input modes
	if input_mode == "save_input":
		handle_save_input(event)
		return
	elif input_mode == "load_input":
		handle_load_input(event)
		return
	elif input_mode == "resize_input":
		handle_resize_input(event)
		return
	elif input_mode == "metadata_input":
		handle_metadata_input(event)
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
			select_and_paint(0)
		KEY_1:
			select_and_paint(1)
		KEY_2:
			select_and_paint(2)
		KEY_3:
			select_and_paint(3)
		KEY_6:
			select_and_paint(6)
		KEY_7:
			select_and_paint(7)
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
		KEY_G:
			start_resize_input()
		KEY_M:
			start_metadata_input()
		KEY_T:
			test_level()
		KEY_ESCAPE:
			exit_editor()


## Select a paint type AND paint it at the current cursor (number keys). Keeps the original
## "press N to place type N at cursor" muscle memory while also setting the mouse paint type.
func select_and_paint(cell_type: int) -> void:
	current_paint_type = cell_type
	set_cell_type_at_cursor(cell_type)
	update_palette()


## Mouse painting (Part D): left-click / drag paints the current type, right-click erases.
## Returns true if the event was consumed as a paint action.
func _handle_mouse_paint(event: InputEvent) -> bool:
	if not grid_manager:
		return false

	if event is InputEventMouseButton:
		if not event.pressed:
			last_painted_pos = Vector2i(-1, -1)  # end of a drag; next click repaints
			return false
		if event.button_index == MOUSE_BUTTON_LEFT:
			return _paint_at_mouse(current_paint_type)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			return _paint_at_mouse(0)  # erase
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			return _paint_at_mouse(current_paint_type)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			return _paint_at_mouse(0)

	return false


## Convert the mouse position to a grid cell and paint it (moving the cursor there too).
## Guarded so a drag only repaints when the cell under the mouse changes.
func _paint_at_mouse(cell_type: int) -> bool:
	var grid_pos := grid_manager.world_to_grid(get_global_mouse_position())
	if not grid_manager.is_valid_position(grid_pos):
		return false
	if grid_pos == last_painted_pos:
		return true  # already painted this cell during the current drag; consume silently
	last_painted_pos = grid_pos
	cursor_position = grid_pos
	set_cell_type_at_cursor(cell_type)
	update_cursor_visual()
	update_status()
	return true


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

	var par_text = "none" if current_level.par_folds < 0 else str(current_level.par_folds)
	status_label.text = "Level Editor — %s\n" % current_level.level_name
	status_label.text += "Grid: %dx%d  Par: %s  Diff: %d\n" % [
		current_level.grid_size.x, current_level.grid_size.y,
		par_text, current_level.difficulty]
	status_label.text += "Cursor: (%d, %d)  Cell: %s\n" % [
		cursor_position.x, cursor_position.y, cell_type_name]
	status_label.text += "Player Start: (%d, %d)  Paint: %s" % [
		player_start_position.x, player_start_position.y,
		PAINT_TYPES[current_paint_type]["name"]]


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
	var levels_dir = GameManager.CUSTOM_LEVELS_DIR
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
	var levels_dir = GameManager.CUSTOM_LEVELS_DIR
	var file_path = levels_dir + save_filename + ".json"

	var loaded_level = level_manager.load_level(file_path)

	if loaded_level:
		current_level = loaded_level
		player_start_position = current_level.player_start_position

		# Rebuild the grid at the loaded size (resize_grid repaints the cells).
		resize_grid(current_level.grid_size)

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
	# Reset level data
	current_level = LevelData.new()
	current_level.level_id = "custom_" + str(Time.get_unix_time_from_system())
	current_level.level_name = "New Level"
	current_level.grid_size = Vector2i(10, 10)
	current_level.cell_size = 64.0
	current_level.player_start_position = Vector2i(1, 1)

	player_start_position = Vector2i(1, 1)
	cursor_position = Vector2i(0, 0)

	# Rebuild the grid at the default size (also clears all cells + repaints).
	resize_grid(Vector2i(10, 10))

	update_cursor_visual()
	update_player_marker()
	update_status()


## Start browse mode
func start_browse_mode() -> void:
	# Get list of custom level files
	var levels_dir = GameManager.CUSTOM_LEVELS_DIR
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


## Rebuild the grid at a new size (Part E). Frees the old cells (avoiding leaks — see
## AGENTS.md), recreates + recenters the grid, clamps cursor/player-start into the new
## bounds, drops now-out-of-bounds cell data, and repaints from current_level.cell_data.
func resize_grid(new_size: Vector2i) -> void:
	new_size = new_size.clamp(Vector2i.ONE, Vector2i(30, 30))

	current_level.grid_size = new_size
	grid_manager.grid_size = new_size

	# Free existing cells before recreating them.
	for cell in grid_manager.cells.values():
		if is_instance_valid(cell):
			cell.queue_free()
	grid_manager.cells.clear()

	grid_manager.create_grid()
	grid_manager.center_grid_on_screen()

	# Clamp cursor + player start into the new bounds.
	var max_pos := new_size - Vector2i.ONE
	cursor_position = cursor_position.clamp(Vector2i.ZERO, max_pos)
	player_start_position = player_start_position.clamp(Vector2i.ZERO, max_pos)
	current_level.player_start_position = player_start_position

	# Drop any cell data now outside the grid (iterate a copy of the keys).
	for pos in current_level.cell_data.keys():
		if not grid_manager.is_valid_position(pos):
			current_level.cell_data.erase(pos)

	apply_level_to_grid()


## Start grid-resize text entry (G key)
func start_resize_input() -> void:
	input_mode = "resize_input"
	input_buffer = "%dx%d" % [current_level.grid_size.x, current_level.grid_size.y]
	status_label.text = "Resize grid WxH (ENTER, ESC cancel): %s_" % input_buffer


## Handle grid-resize input
func handle_resize_input(event: InputEventKey) -> void:
	if event.keycode == KEY_ENTER:
		var new_size := _parse_size(input_buffer)
		if new_size != Vector2i.ZERO:
			resize_grid(new_size)
		input_mode = "edit"
		update_status()
	elif event.keycode == KEY_ESCAPE:
		input_mode = "edit"
		update_status()
	elif event.keycode == KEY_BACKSPACE:
		if input_buffer.length() > 0:
			input_buffer = input_buffer.substr(0, input_buffer.length() - 1)
			status_label.text = "Resize grid WxH (ENTER, ESC cancel): %s_" % input_buffer
	elif event.unicode >= 32 and event.unicode < 127:
		input_buffer += char(event.unicode)
		status_label.text = "Resize grid WxH (ENTER, ESC cancel): %s_" % input_buffer


## Parse a "WxH" string to a Vector2i, or Vector2i.ZERO if malformed.
func _parse_size(s: String) -> Vector2i:
	var parts := s.to_lower().split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


## Start metadata text entry (M key): cycles through name -> par -> difficulty.
func start_metadata_input() -> void:
	input_mode = "metadata_input"
	metadata_field = 0
	_load_metadata_field_buffer()
	_update_metadata_prompt()


## Handle metadata input
func handle_metadata_input(event: InputEventKey) -> void:
	if event.keycode == KEY_ENTER:
		_commit_metadata_field()
		metadata_field += 1
		if metadata_field > 2:
			input_mode = "edit"
			update_status()
		else:
			_load_metadata_field_buffer()
			_update_metadata_prompt()
	elif event.keycode == KEY_ESCAPE:
		input_mode = "edit"
		update_status()
	elif event.keycode == KEY_BACKSPACE:
		if input_buffer.length() > 0:
			input_buffer = input_buffer.substr(0, input_buffer.length() - 1)
			_update_metadata_prompt()
	elif event.unicode >= 32 and event.unicode < 127:
		input_buffer += char(event.unicode)
		_update_metadata_prompt()


## Load the current metadata field's value into the input buffer.
func _load_metadata_field_buffer() -> void:
	match metadata_field:
		0: input_buffer = current_level.level_name
		1: input_buffer = str(current_level.par_folds)
		2: input_buffer = str(current_level.difficulty)


## Show the prompt for the current metadata field.
func _update_metadata_prompt() -> void:
	var prompts := ["Level name", "Par folds (int, -1=none)", "Difficulty (1-5)"]
	status_label.text = "%s (ENTER, ESC cancel): %s_" % [prompts[metadata_field], input_buffer]


## Commit the currently-typed metadata field into current_level.
func _commit_metadata_field() -> void:
	match metadata_field:
		0:
			current_level.level_name = input_buffer
		1:
			if input_buffer.is_valid_int():
				current_level.par_folds = int(input_buffer)
		2:
			if input_buffer.is_valid_int():
				current_level.difficulty = clampi(int(input_buffer), 1, 5)


## Test/play the current level
##
## Stashes the live editing session in GameManager (which survives the scene change) so the
## player can return to the editor with edits intact, then loads the game scene from an
## in-memory clone. No disk write is needed — saving stays an explicit action on the S key.
func test_level() -> void:
	current_level.player_start_position = player_start_position

	# Stash the editing session for the return trip (independent clone — see below).
	GameManager.editor_session = {
		"level_data": current_level.clone(),
		"cursor": cursor_position,
		"player_start": player_start_position,
		"filename": save_filename,
	}
	GameManager.is_testing_from_editor = true

	# Drive gameplay from a SEPARATE clone. The stash and the play copy must be independent
	# because return_to_editor() nulls out current_level_data.
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
