## HistoryManager (Baba-style global undo) tests (Stage 3)
##
## Undo reverses the last committed input uniformly — a move, a fold, OR an unfold.
## Convention: record(engine) is called BEFORE each input; undo() restores it.

extends GutTest


func _engine() -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = Vector2i(10, 10)
	ld.cell_size = 64.0
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(Vector2i(8, 5))
	return e


func test_undo_of_fold_restores_board_and_count():
	var e := _engine()
	var h := HistoryManager.new()
	var before := e.get_state().occupied_count()

	h.record(e)
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "fold applies")
	assert_lt(e.get_state().occupied_count(), before, "fold compressed")
	assert_eq(e.fold_count(), 1, "one fold recorded")

	assert_true(h.undo(e), "undo succeeds")
	assert_eq(e.get_state().occupied_count(), before, "undo restores board")
	assert_eq(e.fold_count(), 0, "undo removes the fold")


func test_undo_of_move_restores_player():
	var e := _engine()
	var h := HistoryManager.new()
	var start := e.player_plane_pos

	h.record(e)
	assert_true(e.move_player(Vector2i(-1, 0)), "move applies")
	assert_ne(e.player_plane_pos, start, "player moved")

	assert_true(h.undo(e), "undo succeeds")
	assert_eq(e.player_plane_pos, start, "undo restores player position")


func test_undo_of_unfold_reapplies_the_fold():
	var e := _engine()
	var h := HistoryManager.new()

	# Fold (recorded), then unfold (recorded). Undo should reverse the unfold,
	# i.e. bring the fold back.
	h.record(e)
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	var folded_count := e.get_state().occupied_count()

	h.record(e)
	assert_true(e.remove_fold(0), "unfold applies")
	assert_gt(e.get_state().occupied_count(), folded_count, "unfold expanded the board")

	assert_true(h.undo(e), "undo the unfold")
	assert_eq(e.fold_count(), 1, "fold is back after undoing the unfold")
	assert_eq(e.get_state().occupied_count(), folded_count, "board matches folded state again")


func test_mixed_sequence_undo_is_lifo():
	var e := _engine()
	var h := HistoryManager.new()
	var start_pos := e.player_plane_pos
	var start_count := e.get_state().occupied_count()

	h.record(e); e.move_player(Vector2i(-1, 0))
	h.record(e); e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))

	# Undo the fold first (last input), then the move.
	assert_true(h.undo(e), "undo fold")
	assert_eq(e.fold_count(), 0, "fold undone")
	assert_true(h.undo(e), "undo move")
	assert_eq(e.player_plane_pos, start_pos, "player back to start")
	assert_eq(e.get_state().occupied_count(), start_count, "board fully restored")
	assert_false(h.can_undo(), "history empty")


func test_undo_empty_history_returns_false():
	var e := _engine()
	var h := HistoryManager.new()
	assert_false(h.undo(e), "nothing to undo")


func test_max_depth_caps_history():
	var e := _engine()
	var h := HistoryManager.new()
	h.max_depth = 3
	for i in range(10):
		h.record(e)
	assert_eq(h.depth(), 3, "history capped at max_depth")
