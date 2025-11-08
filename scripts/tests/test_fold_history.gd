extends GutTest

## Tests for enhanced fold history serialization
## Verifies that fold records capture complete grid state for undo system

var grid_manager: GridManager
var fold_system: FoldSystem


func before_each():
	# Create GridManager
	grid_manager = GridManager.new()
	grid_manager.grid_size = Vector2i(5, 5)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()
	add_child_autofree(grid_manager)

	# Create FoldSystem
	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.grid_manager = grid_manager


func test_create_fold_record_basic_structure():
	var anchor1 = Vector2i(1, 2)
	var anchor2 = Vector2i(3, 2)
	var removed_cells: Array[Vector2i] = [Vector2i(2, 2)]

	var record = fold_system.create_fold_record(anchor1, anchor2, removed_cells, "horizontal")

	assert_has(record, "fold_id", "Record should have fold_id")
	assert_has(record, "anchor1", "Record should have anchor1")
	assert_has(record, "anchor2", "Record should have anchor2")
	assert_has(record, "removed_cells", "Record should have removed_cells")
	assert_has(record, "orientation", "Record should have orientation")
	assert_has(record, "timestamp", "Record should have timestamp")
	assert_has(record, "cells_state", "Record should have cells_state")
	assert_has(record, "player_position", "Record should have player_position")
	assert_has(record, "fold_count", "Record should have fold_count")


func test_fold_id_increments():
	var anchor1 = Vector2i(1, 2)
	var anchor2 = Vector2i(3, 2)
	var removed_cells: Array[Vector2i] = []

	var record1 = fold_system.create_fold_record(anchor1, anchor2, removed_cells, "horizontal")
	var record2 = fold_system.create_fold_record(anchor1, anchor2, removed_cells, "horizontal")

	assert_eq(record1["fold_id"], 0, "First fold_id should be 0")
	assert_eq(record2["fold_id"], 1, "Second fold_id should be 1")


func test_serialize_grid_state_captures_all_cells():
	# Grid has 5x5 = 25 cells
	var state = fold_system.serialize_grid_state()

	assert_eq(state.size(), 25, "Should serialize all 25 cells")


func test_serialize_grid_state_captures_cell_properties():
	# Modify a cell
	var cell = grid_manager.get_cell(Vector2i(2, 2))
	cell.set_cell_type(1)  # Wall
	cell.is_partial = true

	var state = fold_system.serialize_grid_state()
	var cell_key = var_to_str(Vector2i(2, 2))

	assert_has(state, cell_key, "Should have cell at (2,2)")

	var cell_data = state[cell_key]
	assert_has(cell_data, "grid_position", "Cell data should have grid_position")
	assert_has(cell_data, "geometry", "Cell data should have geometry")
	assert_has(cell_data, "cell_type", "Cell data should have cell_type")
	assert_has(cell_data, "is_partial", "Cell data should have is_partial")
	assert_has(cell_data, "seams", "Cell data should have seams")

	assert_eq(cell_data["cell_type"], 1, "Cell type should be preserved")
	assert_eq(cell_data["is_partial"], true, "is_partial should be preserved")


func test_serialize_grid_state_captures_geometry():
	var cell = grid_manager.get_cell(Vector2i(1, 1))
	var original_geometry = cell.geometry.duplicate()

	var state = fold_system.serialize_grid_state()
	var cell_key = var_to_str(Vector2i(1, 1))
	var cell_data = state[cell_key]

	assert_eq(cell_data["geometry"].size(), 4, "Should have 4 vertices for square cell")

	# Verify geometry is correctly serialized
	for i in range(4):
		var v = original_geometry[i]
		var serialized_v = cell_data["geometry"][i]
		assert_almost_eq(serialized_v["x"], v.x, 0.1, "Geometry x should match")
		assert_almost_eq(serialized_v["y"], v.y, 0.1, "Geometry y should match")


func test_serialize_grid_state_captures_seams():
	var cell = grid_manager.get_cell(Vector2i(2, 2))

	# Add seam data
	var seam_data = {
		"line_point": Vector2(100, 100),
		"line_normal": Vector2(1, 0),
		"intersection_points": [Vector2(100, 0), Vector2(100, 200)],
		"timestamp": 12345
	}
	cell.add_seam(seam_data)

	var state = fold_system.serialize_grid_state()
	var cell_key = var_to_str(Vector2i(2, 2))
	var cell_data = state[cell_key]

	assert_eq(cell_data["seams"].size(), 1, "Should have 1 seam")
	assert_has(cell_data["seams"][0], "line_point", "Seam should have line_point")
	assert_has(cell_data["seams"][0], "timestamp", "Seam should have timestamp")


func test_fold_record_captures_player_position():
	# Create player
	var player = autofree(Player.new())
	add_child_autofree(player)
	player.grid_position = Vector2i(3, 3)
	fold_system.player = player

	var record = fold_system.create_fold_record(Vector2i(0, 0), Vector2i(4, 0), [], "horizontal")

	assert_eq(record["player_position"], Vector2i(3, 3), "Should capture player position")


func test_fold_record_without_player():
	# No player set
	fold_system.player = null

	var record = fold_system.create_fold_record(Vector2i(0, 0), Vector2i(4, 0), [], "horizontal")

	assert_eq(record["player_position"], Vector2i(-1, -1), "Should use (-1,-1) when no player")


func test_fold_history_appends_records():
	fold_system.clear_fold_history()

	var anchor1 = Vector2i(1, 2)
	var anchor2 = Vector2i(3, 2)

	var record = fold_system.create_fold_record(anchor1, anchor2, [], "horizontal")
	fold_system.fold_history.append(record)

	assert_eq(fold_system.get_fold_history().size(), 1, "Should have 1 record")


func test_fold_history_multiple_folds():
	fold_system.clear_fold_history()

	for i in range(3):
		var record = fold_system.create_fold_record(Vector2i(i, 0), Vector2i(i+1, 0), [], "horizontal")
		fold_system.fold_history.append(record)

	assert_eq(fold_system.get_fold_history().size(), 3, "Should have 3 records")


func test_clear_fold_history():
	fold_system.clear_fold_history()

	# Add some records
	for i in range(3):
		var record = fold_system.create_fold_record(Vector2i(i, 0), Vector2i(i+1, 0), [], "horizontal")
		fold_system.fold_history.append(record)

	fold_system.clear_fold_history()

	assert_eq(fold_system.get_fold_history().size(), 0, "History should be empty after clear")
	assert_eq(fold_system.next_fold_id, 0, "fold_id counter should reset to 0")


func test_fold_record_removed_cells_array():
	var removed: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]

	var record = fold_system.create_fold_record(Vector2i(0, 0), Vector2i(4, 0), removed, "horizontal")

	assert_eq(record["removed_cells"].size(), 3, "Should have 3 removed cells")
	assert_has(record["removed_cells"], Vector2i(1, 1), "Should contain (1,1)")
	assert_has(record["removed_cells"], Vector2i(2, 2), "Should contain (2,2)")
	assert_has(record["removed_cells"], Vector2i(3, 3), "Should contain (3,3)")


func test_fold_record_orientation():
	var record_h = fold_system.create_fold_record(Vector2i(0, 0), Vector2i(2, 0), [], "horizontal")
	var record_v = fold_system.create_fold_record(Vector2i(0, 0), Vector2i(0, 2), [], "vertical")
	var record_d = fold_system.create_fold_record(Vector2i(0, 0), Vector2i(2, 2), [], "diagonal")

	assert_eq(record_h["orientation"], "horizontal", "Should record horizontal orientation")
	assert_eq(record_v["orientation"], "vertical", "Should record vertical orientation")
	assert_eq(record_d["orientation"], "diagonal", "Should record diagonal orientation")


func test_deserialize_grid_state():
	# Serialize current state
	var original_state = fold_system.serialize_grid_state()

	# Deserialize it
	var restored = fold_system.deserialize_grid_state(original_state)

	assert_eq(restored.size(), original_state.size(), "Should restore same number of cells")


func test_cell_to_dict_preserves_all_properties():
	var cell = grid_manager.get_cell(Vector2i(2, 2))
	cell.set_cell_type(2)  # Water
	cell.is_partial = true

	var cell_dict = cell.to_dict()

	assert_has(cell_dict, "grid_position", "Should have grid_position")
	assert_has(cell_dict, "geometry", "Should have geometry")
	assert_has(cell_dict, "cell_type", "Should have cell_type")
	assert_has(cell_dict, "is_partial", "Should have is_partial")
	assert_has(cell_dict, "seams", "Should have seams")

	assert_eq(cell_dict["cell_type"], 2, "Cell type should be preserved")
	assert_eq(cell_dict["is_partial"], true, "is_partial flag should be preserved")


func test_cell_state_snapshot():
	var cell = grid_manager.get_cell(Vector2i(1, 1))
	cell.set_cell_type(3)  # Goal

	var snapshot = cell.create_state_snapshot()

	assert_has(snapshot, "cell_type", "Snapshot should have cell_type")
	assert_eq(snapshot["cell_type"], 3, "Snapshot should preserve cell type")
