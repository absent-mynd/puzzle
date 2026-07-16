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

## UI — all Controls live under a CanvasLayer (screen space, themed), built in create_ui().
var ui_layer: CanvasLayer
var toolbar: HBoxContainer
var status_label: Label
var help_label: Label
var toast_label: Label
var toast_timer: Timer
var editor_dialog: EditorDialog

## Trigger-tile inspector (visible only when the cursor sits on a TRIGGER_FOLD cell).
var inspector_panel: PanelContainer
var inspector_channel: LineEdit
var inspector_anchors: LineEdit

## Tool palette: a row of clickable type swatches; the active one is highlighted.
var palette_container: HBoxContainer
var palette_swatches: Dictionary = {}  # cell_type:int -> Panel

## Undo/redo over LevelData snapshots. `_suppress_history` guards the rebuilds that
## restoring a snapshot triggers, so undo/redo don't record themselves as new edits.
var editor_history: EditorHistory = EditorHistory.new()
var _suppress_history: bool = false

## Constants for colors
const CURSOR_COLOR = Color(1.0, 1.0, 0.0, 0.6)  # Yellow with transparency
const PLAYER_MARKER_COLOR = Color(1.0, 0.0, 1.0, 0.8)  # Magenta

## Persisted filename for save/load (also stashed in the editor session).
var save_filename: String = "custom_level"


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

	# Seed the edit history with the starting level.
	editor_history.set_baseline(current_level)

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


## Build the whole editor UI under a CanvasLayer (screen space, themed). Replaces the
## old absolute-positioned labels-on-a-Node2D layout.
func create_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks fall through to the grid
	ui_layer.add_child(root)

	# Left column: toolbar over the status panel over the palette (stacks, never overlaps).
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 10
	left.offset_top = 10
	left.add_theme_constant_override("separation", UIConstants.SPACING_SM)
	root.add_child(left)

	var toolbar_panel := PanelContainer.new()
	left.add_child(toolbar_panel)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", UIConstants.SPACING_SM)
	toolbar_panel.add_child(toolbar)
	_add_tool_button("New", new_level)
	_add_tool_button("Load", _action_load)
	_add_tool_button("Save", _action_save)
	_add_tool_button("Resize", _action_resize)
	_add_tool_button("Metadata", _action_metadata)
	_add_tool_button("Browse", _action_browse)
	_add_tool_button("Test", test_level)
	_add_tool_button("Exit", exit_editor)

	var status_box := PanelContainer.new()
	left.add_child(status_box)
	status_label = Label.new()
	status_label.theme_type_variation = &"StatusLabel"
	status_box.add_child(status_label)

	var palette_box := PanelContainer.new()
	left.add_child(palette_box)
	palette_container = HBoxContainer.new()
	palette_container.add_theme_constant_override("separation", UIConstants.SPACING_SM)
	palette_box.add_child(palette_container)
	create_palette()
	update_palette()

	# Trigger inspector (top-right, hidden unless the cursor is on a TRIGGER_FOLD cell).
	_build_inspector(root)

	# Help (bottom).
	var help_box := PanelContainer.new()
	help_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_box.offset_left = 10
	help_box.offset_bottom = -10
	help_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(help_box)
	help_label = Label.new()
	help_label.theme_type_variation = &"StatusLabel"
	help_label.text = "Arrows: move  Click/drag: paint  RClick: erase  0-7: tile  P: start  Ctrl+Z/Y: undo/redo  T: test  ESC: exit"
	help_box.add_child(help_label)

	# Toast (transient messages, centered near the top).
	toast_label = Label.new()
	toast_label.theme_type_variation = &"HeadingLabel"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 40
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.visible = false
	root.add_child(toast_label)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.timeout.connect(func(): if toast_label: toast_label.visible = false)
	add_child(toast_timer)

	# The one reusable modal dialog (on top of everything).
	editor_dialog = EditorDialog.new()
	ui_layer.add_child(editor_dialog)


## Add a compact toolbar button wired to an action.
func _add_tool_button(label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.theme_type_variation = &"HudButton"
	b.focus_mode = Control.FOCUS_CLICK
	b.pressed.connect(action)
	toolbar.add_child(b)


## Build the (initially hidden) TRIGGER_FOLD inspector panel: channel + anchors + Apply.
func _build_inspector(root: Control) -> void:
	inspector_panel = PanelContainer.new()
	inspector_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inspector_panel.offset_right = -10
	inspector_panel.offset_top = 90
	inspector_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inspector_panel.visible = false
	root.add_child(inspector_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UIConstants.SPACING_SM)
	inspector_panel.add_child(vbox)

	var title := Label.new()
	title.theme_type_variation = &"HeadingLabel"
	title.text = "Trigger Fold"
	vbox.add_child(title)

	var ch_label := Label.new()
	ch_label.theme_type_variation = &"StatusLabel"
	ch_label.text = "Channel"
	vbox.add_child(ch_label)
	inspector_channel = LineEdit.new()
	inspector_channel.custom_minimum_size = Vector2(200, 0)
	vbox.add_child(inspector_channel)

	var an_label := Label.new()
	an_label.theme_type_variation = &"StatusLabel"
	an_label.text = "Anchors (x,y x,y)"
	vbox.add_child(an_label)
	inspector_anchors = LineEdit.new()
	inspector_anchors.custom_minimum_size = Vector2(200, 0)
	vbox.add_child(inspector_anchors)

	var apply := Button.new()
	apply.text = "Apply"
	apply.theme_type_variation = &"PrimaryButton"
	apply.focus_mode = Control.FOCUS_CLICK
	apply.pressed.connect(_apply_inspector)
	vbox.add_child(apply)


## Paintable tile types, in palette order. Name + swatch color for each come from the
## TileTypes registry (the single source of truth), so the palette can never drift from
## how cells actually render. (Phase 4 adds TRIGGER_FOLD/PIN to this list.)
const PAINT_TYPE_ORDER := [0, 1, 2, 3, 4, 5, 6, 7]


## Fill the palette container (built in create_ui) with one clickable swatch per paint
## type. Clicking a swatch selects it as the paint type (mouse parity with keys 0-7).
func create_palette() -> void:
	for cell_type in PAINT_TYPE_ORDER:
		# Frame Panel — its border is toggled to show which type is active.
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(84, 66)
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.gui_input.connect(_on_swatch_input.bind(cell_type))

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks reach the frame
		frame.add_child(vbox)

		var swatch := ColorRect.new()
		swatch.color = TileTypes.color_for(cell_type)
		swatch.custom_minimum_size = Vector2(76, 38)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(swatch)

		var label := Label.new()
		label.text = "%d: %s" % [cell_type, TileTypes.display_name(cell_type)]
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(label)

		palette_container.add_child(frame)
		palette_swatches[cell_type] = frame


## Click a palette swatch -> select that paint type (mouse equivalent of pressing 0-7).
func _on_swatch_input(event: InputEvent, cell_type: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		current_paint_type = cell_type
		update_palette()
		update_status()


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


## Handle keyboard + mouse input. While a modal dialog is open it owns all input, so the
## editor ignores everything (no more `input_mode` string machine — the dialog is the mode).
func _input(event: InputEvent) -> void:
	if editor_dialog and editor_dialog.is_open():
		return

	if not event is InputEventKey or not event.pressed:
		return

	# Undo / redo (Ctrl+Z / Ctrl+Y) over the edit history.
	if event.ctrl_pressed and event.keycode == KEY_Z:
		undo_edit()
		return
	if event.ctrl_pressed and event.keycode == KEY_Y:
		redo_edit()
		return

	# Edit-mode shortcuts. The letter keys open the corresponding dialog action.
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
		KEY_4:
			select_and_paint(4)
		KEY_5:
			select_and_paint(5)
		KEY_6:
			select_and_paint(6)
		KEY_7:
			select_and_paint(7)
		KEY_P:
			set_player_start_at_cursor()
		KEY_S:
			_action_save()
		KEY_L:
			_action_load()
		KEY_N:
			new_level()
		KEY_B:
			_action_browse()
		KEY_G:
			_action_resize()
		KEY_M:
			_action_metadata()
		KEY_T:
			test_level()
		KEY_ESCAPE:
			exit_editor()


## Mouse painting runs in _unhandled_input (not _input) so UI controls consume their own
## clicks first — clicking a toolbar button or palette swatch no longer paints the grid
## cell beneath it. Grid cells are Node2D (not Controls), so clicks over the map still
## fall through to here.
func _unhandled_input(event: InputEvent) -> void:
	if editor_dialog and editor_dialog.is_open():
		return
	_handle_mouse_paint(event)


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

		# Update level data. EditorCellModel handles the int-vs-dict shape so behavioral
		# tiles (TRIGGER_FOLD) get a proper params dict and a loaded dict isn't flattened
		# on repaint.
		EditorCellModel.set_type(current_level.cell_data, cursor_position, cell_type)

		_record_history()
		update_status()


## Set player start position at cursor
func set_player_start_at_cursor() -> void:
	player_start_position = cursor_position
	current_level.player_start_position = player_start_position
	_record_history()
	update_player_marker()
	update_status()


## Record the current level state as an undoable edit (no-op while restoring a snapshot).
func _record_history() -> void:
	if not _suppress_history:
		editor_history.push(current_level)


## Undo the last edit, restoring the previous level snapshot.
func undo_edit() -> void:
	var restored := editor_history.undo()
	if restored != null:
		_restore_level(restored)


## Redo a previously-undone edit.
func redo_edit() -> void:
	var restored := editor_history.redo()
	if restored != null:
		_restore_level(restored)


## Swap in a restored LevelData and rebuild the view without recording it as a new edit.
func _restore_level(level: LevelData) -> void:
	_suppress_history = true
	current_level = level
	player_start_position = level.player_start_position
	cursor_position = cursor_position.clamp(Vector2i.ZERO, current_level.grid_size - Vector2i.ONE)
	resize_grid(current_level.grid_size)  # rebuilds + repaints from current_level
	update_player_marker()
	update_status()
	_suppress_history = false


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
	# Name comes from the TileTypes registry so all registered types label correctly
	# (previously only 0-3 were handled and 4-7 mislabeled as "Empty").
	var cell_type_name = TileTypes.display_name(cell.cell_type) if cell else "Empty"

	var par_text = "none" if current_level.par_folds < 0 else str(current_level.par_folds)
	status_label.text = "Level Editor — %s\n" % current_level.level_name
	status_label.text += "Grid: %dx%d  Par: %s  Diff: %d\n" % [
		current_level.grid_size.x, current_level.grid_size.y,
		par_text, current_level.difficulty]
	status_label.text += "Cursor: (%d, %d)  Cell: %s\n" % [
		cursor_position.x, cursor_position.y, cell_type_name]
	status_label.text += "Player Start: (%d, %d)  Paint: %s" % [
		player_start_position.x, player_start_position.y,
		TileTypes.display_name(current_paint_type)]

	_refresh_inspector()


## Show a transient toast message (replaces the old status-label + await-timer toasts).
func _toast(text: String) -> void:
	if not toast_label:
		return
	toast_label.text = text
	toast_label.visible = true
	if toast_timer:
		toast_timer.start(2.0)


## Save: ask for a filename, then write to disk.
func _action_save() -> void:
	var name = await editor_dialog.prompt_text("Save level as", save_filename)
	if name == null or String(name).strip_edges().is_empty():
		return
	save_filename = String(name).strip_edges()
	save_level()


## Load: ask for a filename, then load it.
func _action_load() -> void:
	var name = await editor_dialog.prompt_text("Load level (filename)", save_filename)
	if name == null or String(name).strip_edges().is_empty():
		return
	save_filename = String(name).strip_edges()
	load_level()


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

	_toast("Level saved: %s" % save_filename if success else "Failed to save level!")
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

		# A freshly loaded level starts a new undo history.
		editor_history.set_baseline(current_level)

		_toast("Level loaded: %s" % current_level.level_name)
	else:
		_toast("Failed to load level!")

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

	# Apply cell data from level. Use type_at so a behavioral tile stored as a
	# {"type": N, ...} dict resolves to its int type (set_cell_type expects an int).
	for grid_pos in current_level.cell_data:
		var cell = grid_manager.get_cell(grid_pos)
		if cell:
			cell.set_cell_type(current_level.type_at(grid_pos))

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

	# A new level starts a fresh undo history.
	editor_history.set_baseline(current_level)

	update_cursor_visual()
	update_player_marker()
	update_status()


## Browse: pick a saved custom level from a list dialog, then load it for editing.
func _action_browse() -> void:
	var levels_dir = GameManager.CUSTOM_LEVELS_DIR
	var files: Array = FileUtils.get_custom_level_files(levels_dir)
	if files.is_empty():
		_toast("No custom levels found.")
		return
	var idx = await editor_dialog.prompt_choice("Open custom level", files)
	if idx == null or int(idx) < 0:
		return
	save_filename = files[int(idx)]
	load_level()


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


## Resize: prompt for a "WxH" string, then rebuild the grid. Recorded as an edit.
func _action_resize() -> void:
	var current := "%dx%d" % [current_level.grid_size.x, current_level.grid_size.y]
	var text = await editor_dialog.prompt_text("Resize grid (WxH)", current)
	if text == null:
		return
	var new_size := _parse_size(String(text))
	if new_size != Vector2i.ZERO:
		resize_grid(new_size)
		_record_history()
		update_status()
	else:
		_toast("Invalid size — use WxH, e.g. 12x8")


## Parse a "WxH" string to a Vector2i, or Vector2i.ZERO if malformed.
func _parse_size(s: String) -> Vector2i:
	var parts := s.to_lower().split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


## Metadata: one form dialog editing all level fields at once (broadened from the old
## name/par/difficulty-only flow to also cover id/description/max_folds/cell_size).
func _action_metadata() -> void:
	var fields := [
		{"key": "level_name", "label": "Name", "value": current_level.level_name, "kind": "text"},
		{"key": "level_id", "label": "Level ID", "value": current_level.level_id, "kind": "text"},
		{"key": "description", "label": "Description", "value": current_level.description, "kind": "text"},
		{"key": "par_folds", "label": "Par folds (-1 = none)", "value": current_level.par_folds, "kind": "int"},
		{"key": "max_folds", "label": "Max folds (-1 = unlimited)", "value": current_level.max_folds, "kind": "int"},
		{"key": "difficulty", "label": "Difficulty (1-5)", "value": current_level.difficulty, "kind": "int"},
		{"key": "cell_size", "label": "Cell size (px)", "value": current_level.cell_size, "kind": "float"},
	]
	var r = await editor_dialog.prompt_form("Level metadata", fields)
	if r == null:
		return
	current_level.level_name = str(r["level_name"])
	current_level.level_id = str(r["level_id"])
	current_level.description = str(r["description"])
	if r["par_folds"] is int:
		current_level.par_folds = r["par_folds"]
	if r["max_folds"] is int:
		current_level.max_folds = r["max_folds"]
	if r["difficulty"] is int:
		current_level.difficulty = clampi(r["difficulty"], 1, 5)
	if r["cell_size"] is float:
		current_level.cell_size = r["cell_size"]
	_record_history()
	update_status()


## Show/populate the trigger inspector for the cell under the cursor (called from
## update_status, so it refreshes whenever the cursor moves or a cell is painted).
func _refresh_inspector() -> void:
	if not inspector_panel:
		return
	var is_trigger := current_level.type_at(cursor_position) == TileTypes.TRIGGER_FOLD
	inspector_panel.visible = is_trigger
	if not is_trigger:
		return
	var data := current_level.data_at(cursor_position)
	inspector_channel.text = str(data.get("channel", "A"))
	inspector_anchors.text = _anchors_to_text(data.get("anchors", []))


## Write the inspector's channel + anchors onto the trigger cell under the cursor.
func _apply_inspector() -> void:
	if current_level.type_at(cursor_position) != TileTypes.TRIGGER_FOLD:
		return
	var anchors := _parse_anchors(inspector_anchors.text)
	EditorCellModel.set_trigger_params(
		current_level.cell_data, cursor_position,
		inspector_channel.text.strip_edges(), anchors)
	_record_history()
	_toast("Trigger updated")


## "[[x,y],[x,y]]" -> "x,y x,y" for the inspector field.
func _anchors_to_text(anchors) -> String:
	var parts: Array = []
	if anchors is Array:
		for a in anchors:
			if a is Array and a.size() == 2:
				parts.append("%d,%d" % [int(a[0]), int(a[1])])
	return " ".join(parts)


## "x,y x,y" -> [[x,y],[x,y]] (ignores malformed tokens).
func _parse_anchors(text: String) -> Array:
	var out: Array = []
	for tok in text.split(" ", false):
		var xy := tok.split(",")
		if xy.size() == 2 and xy[0].is_valid_int() and xy[1].is_valid_int():
			out.append([int(xy[0]), int(xy[1])])
	return out


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
