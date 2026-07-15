## EditorCellModel unit tests
##
## Covers the int-vs-dict cell_data shape the editor writes, and the regression the
## whole feature exists to prevent: repainting a loaded TRIGGER_FOLD must NOT flatten
## its channel/anchors back to a bare int.

extends GutTest

const TRIGGER := TileTypes.TRIGGER_FOLD
const PIN := TileTypes.PIN


func test_plain_type_writes_bare_int():
	var data := {}
	EditorCellModel.set_type(data, Vector2i(1, 1), TileTypes.WALL)
	assert_eq(data[Vector2i(1, 1)], TileTypes.WALL, "wall stored as a bare int")


func test_empty_erases_entry():
	var data := {Vector2i(2, 2): TileTypes.WALL}
	EditorCellModel.set_type(data, Vector2i(2, 2), TileTypes.EMPTY)
	assert_false(data.has(Vector2i(2, 2)), "painting EMPTY removes the cell")


func test_trigger_writes_param_dict():
	var data := {}
	EditorCellModel.set_type(data, Vector2i(3, 1), TRIGGER)
	var v = data[Vector2i(3, 1)]
	assert_true(v is Dictionary, "trigger stored as a dict")
	assert_eq(int(v["type"]), TRIGGER, "dict carries the type")
	assert_true(v.has("channel"), "dict has a channel param")
	assert_true(v.has("anchors"), "dict has an anchors param")


func test_pin_is_a_plain_int():
	# PIN has no per-instance params, so it's a bare int (not a dict).
	assert_false(EditorCellModel.is_dict_type(PIN), "PIN needs no data dict")
	var data := {}
	EditorCellModel.set_type(data, Vector2i(0, 0), PIN)
	assert_eq(data[Vector2i(0, 0)], PIN, "pin stored as a bare int")


func test_repaint_preserves_trigger_params():
	# The named regression: author params, then repaint the same trigger -> params survive.
	var pos := Vector2i(4, 4)
	var data := {}
	EditorCellModel.set_type(data, pos, TRIGGER)
	EditorCellModel.set_trigger_params(data, pos, "B", [[3, 1], [5, 1]])

	EditorCellModel.set_type(data, pos, TRIGGER)  # repaint same type
	var v = data[pos]
	assert_true(v is Dictionary, "still a dict after repaint")
	assert_eq(v["channel"], "B", "channel preserved on repaint")
	assert_eq(v["anchors"], [[3, 1], [5, 1]], "anchors preserved on repaint")


func test_changing_type_replaces_dict():
	var pos := Vector2i(5, 5)
	var data := {}
	EditorCellModel.set_type(data, pos, TRIGGER)
	EditorCellModel.set_type(data, pos, TileTypes.WALL)  # change to a plain type
	assert_eq(data[pos], TileTypes.WALL, "changing to a plain type writes a bare int")


func test_trigger_params_roundtrip_through_leveldata():
	# The dict must survive LevelData serialization (the editor saves via to_dict).
	var pos := Vector2i(2, 1)
	var ld := LevelData.new()
	EditorCellModel.set_type(ld.cell_data, pos, TRIGGER)
	EditorCellModel.set_trigger_params(ld.cell_data, pos, "C", [[1, 1], [4, 1]])

	var restored := LevelData.new()
	restored.from_dict(ld.to_dict())
	assert_eq(restored.type_at(pos), TRIGGER, "type survives round-trip")
	assert_eq(restored.data_at(pos)["channel"], "C", "channel survives round-trip")
	assert_eq(restored.data_at(pos)["anchors"], [[1, 1], [4, 1]], "anchors survive round-trip")
