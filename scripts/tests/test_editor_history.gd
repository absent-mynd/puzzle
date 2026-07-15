## EditorHistory unit tests
##
## Push/undo/redo over LevelData snapshots, including redo-branch truncation on a new
## edit. Snapshots must be independent (deep clones) so later edits don't mutate history.

extends GutTest


func _level_with(pos: Vector2i, type: int) -> LevelData:
	var ld := LevelData.new()
	ld.cell_data[pos] = type
	return ld


func test_no_undo_or_redo_initially():
	var h := EditorHistory.new()
	h.set_baseline(LevelData.new())
	assert_false(h.can_undo(), "nothing to undo at baseline")
	assert_false(h.can_redo(), "nothing to redo at baseline")


func test_undo_restores_previous_state():
	var h := EditorHistory.new()
	h.set_baseline(LevelData.new())  # empty

	var edited := _level_with(Vector2i(1, 1), TileTypes.WALL)
	h.push(edited)
	assert_true(h.can_undo(), "can undo after an edit")

	var restored := h.undo()
	assert_not_null(restored, "undo returns a state")
	assert_false(restored.cell_data.has(Vector2i(1, 1)), "undo reverts to the empty baseline")


func test_redo_reapplies_undone_edit():
	var h := EditorHistory.new()
	h.set_baseline(LevelData.new())
	h.push(_level_with(Vector2i(1, 1), TileTypes.WALL))

	h.undo()
	assert_true(h.can_redo(), "can redo after undo")
	var redone := h.redo()
	assert_eq(redone.cell_data[Vector2i(1, 1)], TileTypes.WALL, "redo reapplies the edit")


func test_new_edit_truncates_redo_branch():
	var h := EditorHistory.new()
	h.set_baseline(LevelData.new())
	h.push(_level_with(Vector2i(1, 1), TileTypes.WALL))
	h.undo()

	# A fresh edit after an undo should drop the redo branch.
	h.push(_level_with(Vector2i(2, 2), TileTypes.GOAL))
	assert_false(h.can_redo(), "new edit truncates redo")


func test_snapshots_are_independent():
	var h := EditorHistory.new()
	h.set_baseline(LevelData.new())
	var edited := _level_with(Vector2i(1, 1), TileTypes.WALL)
	h.push(edited)

	# Mutating the pushed level afterwards must not corrupt the recorded snapshot.
	edited.cell_data[Vector2i(9, 9)] = TileTypes.WATER
	h.undo()
	var redone := h.redo()
	assert_false(redone.cell_data.has(Vector2i(9, 9)), "snapshot is a deep clone, not a reference")
