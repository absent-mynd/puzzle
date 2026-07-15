## Smoke tests for the level editor scene (Parts C/D/E).
##
## Instantiates the real editor scene and exercises the new palette, grid resize, and
## paint helpers. Ensures _ready() (which awaits a frame + builds the grid) comes up clean.

extends GutTest


func _boot_editor():
	GameManager.editor_session = {}  # ensure a fresh (non-restoring) boot
	var scene: PackedScene = load("res://scenes/ui/LevelEditor.tscn")
	var ed = scene.instantiate()
	add_child_autofree(ed)
	# _ready() awaits one process_frame before building the UI; interleave a few frames so
	# that continuation (create_ui -> create_palette) has run before we assert.
	for i in range(5):
		await get_tree().process_frame
	return ed


func test_editor_boots_with_palette_and_default_paint() -> void:
	var ed = await _boot_editor()

	assert_eq(ed.current_paint_type, 1, "default paint type is Wall")
	assert_eq(ed.palette_swatches.size(), 8, "palette has 8 swatches (empty/wall/water/goal/trigger/pin/unanchorable x2)")
	assert_not_null(ed.grid_manager, "grid manager created")
	assert_eq(ed.grid_manager.grid_size, Vector2i(10, 10), "default 10x10 grid")


func test_editor_resize_rebuilds_grid() -> void:
	var ed = await _boot_editor()

	ed.resize_grid(Vector2i(6, 6))

	assert_eq(ed.grid_manager.grid_size, Vector2i(6, 6), "grid manager resized")
	assert_eq(ed.current_level.grid_size, Vector2i(6, 6), "level data resized")
	assert_eq(ed.grid_manager.cells.size(), 36, "6x6 = 36 cells created")


func test_editor_resize_drops_out_of_bounds_cells() -> void:
	var ed = await _boot_editor()
	ed.current_level.cell_data[Vector2i(8, 8)] = 1  # inside 10x10, outside 6x6

	ed.resize_grid(Vector2i(6, 6))

	assert_false(ed.current_level.cell_data.has(Vector2i(8, 8)),
		"cell outside the new bounds is dropped")


func test_select_and_paint_writes_cell_data() -> void:
	var ed = await _boot_editor()

	ed.cursor_position = Vector2i(2, 2)
	ed.select_and_paint(2)  # Water

	assert_eq(ed.current_paint_type, 2, "paint type updated")
	assert_true(ed.current_level.cell_data.has(Vector2i(2, 2)), "cell recorded")
	assert_eq(ed.current_level.cell_data[Vector2i(2, 2)], 2, "recorded as water")


func test_parse_size_handles_good_and_bad_input() -> void:
	var ed = await _boot_editor()

	assert_eq(ed._parse_size("12x8"), Vector2i(12, 8), "parses WxH")
	assert_eq(ed._parse_size("7X3"), Vector2i(7, 3), "case-insensitive")
	assert_eq(ed._parse_size("bad"), Vector2i.ZERO, "malformed returns zero")


func test_painting_trigger_writes_param_dict() -> void:
	var ed = await _boot_editor()

	ed.cursor_position = Vector2i(3, 3)
	ed.select_and_paint(TileTypes.TRIGGER_FOLD)

	var v = ed.current_level.cell_data[Vector2i(3, 3)]
	assert_true(v is Dictionary, "trigger tile stored as a params dict, not a bare int")
	assert_eq(int(v["type"]), TileTypes.TRIGGER_FOLD, "dict carries the trigger type")


func test_editor_undo_reverts_a_paint() -> void:
	var ed = await _boot_editor()

	ed.cursor_position = Vector2i(4, 1)
	ed.select_and_paint(1)  # Wall
	assert_true(ed.current_level.cell_data.has(Vector2i(4, 1)), "cell painted")

	ed.undo_edit()
	assert_false(ed.current_level.cell_data.has(Vector2i(4, 1)), "undo removes the painted cell")


func test_editor_redo_reapplies_a_paint() -> void:
	var ed = await _boot_editor()

	ed.cursor_position = Vector2i(5, 1)
	ed.select_and_paint(3)  # Goal
	ed.undo_edit()
	ed.redo_edit()
	assert_eq(ed.current_level.type_at(Vector2i(5, 1)), 3, "redo reapplies the paint")
