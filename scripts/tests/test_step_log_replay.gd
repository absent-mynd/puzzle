## Step-log replay + incremental derivation tests (F2)
##
## The engine's authoritative state is now an ordered FoldStep log; the fold list,
## folded geometry, and player position are DERIVED by replaying it. These tests
## pin the three guarantees the promotion must keep:
##   1. Deriving the full log reproduces the from-scratch fold-list results.
##   2. Undo == drop the last step (engine-level), for folds AND moves.
##   3. capture/restore round-trips the log deterministically.
## Plus a large grid × long log case so incremental derivation is exercised at scale.

extends GutTest


func _engine(start: Vector2i, grid := Vector2i(10, 10), types: Dictionary = {}) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = types
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func _occupied_set(state: FoldedState) -> Dictionary:
	var out := {}
	for pos in state.stacks.keys():
		if state.is_occupied(pos):
			out[pos] = state.dominant_type_at(pos)
	return out


func test_fold_step_matches_fold_list_derive():
	# The derived state after a FOLD step must equal FoldReplay.derive over the
	# equivalent fold list — the step log is a faithful superset of the old model.
	var e := _engine(Vector2i(8, 5))
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	var scratch := FoldReplay.derive(e.base_grid, e.folds)
	assert_eq(_occupied_set(e.get_state()), _occupied_set(scratch),
		"step-log derived occupancy matches fold-list derive")


func test_move_is_recorded_and_replayed():
	var e := _engine(Vector2i(8, 5))
	assert_eq(e.steps.size(), 0, "log starts empty")
	assert_true(e.move_player(Vector2i(-1, 0)), "move applies")
	assert_eq(e.steps.size(), 1, "move appended one step")
	assert_eq(e.steps[0].kind, FoldStep.Kind.MOVE, "it is a MOVE step")
	assert_eq(e.player_plane_pos, Vector2i(7, 5), "player moved to col 7")


func test_undo_step_drops_last_move():
	var e := _engine(Vector2i(8, 5))
	var start := e.player_plane_pos
	e.move_player(Vector2i(-1, 0))
	assert_ne(e.player_plane_pos, start, "player moved")
	assert_true(e.undo_step(), "undo_step succeeds")
	assert_eq(e.steps.size(), 0, "step dropped")
	assert_eq(e.player_plane_pos, start, "player back to start")


func test_undo_step_drops_last_fold():
	var e := _engine(Vector2i(8, 5))
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	assert_eq(e.fold_count(), 1, "one fold active")
	assert_eq(e.player_plane_pos, Vector2i(7, 5), "player rode the fold")
	assert_true(e.undo_step(), "undo_step succeeds")
	assert_eq(e.fold_count(), 0, "fold removed")
	assert_eq(e.player_plane_pos, Vector2i(8, 5), "player rode back to col 8")


func test_undo_step_empty_log_is_false():
	var e := _engine(Vector2i(8, 5))
	assert_false(e.undo_step(), "nothing to undo on an empty log")


func test_capture_restore_round_trip():
	var e := _engine(Vector2i(8, 5))
	e.move_player(Vector2i(-1, 0))
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	var snap := e.capture_state()
	var before := _occupied_set(e.get_state())
	var before_pos := e.player_plane_pos

	# Mutate further, then restore the snapshot.
	e.move_player(Vector2i(0, 1))
	e.restore_state(snap)

	assert_eq(e.steps.size(), 2, "restored log length")
	assert_eq(e.player_plane_pos, before_pos, "restored player position")
	assert_eq(_occupied_set(e.get_state()), before, "restored geometry")


func test_restore_is_independent_of_original_log():
	# Snapshots must deep-enough copy the log: mutating the engine after capture
	# must not corrupt the snapshot.
	var e := _engine(Vector2i(8, 5))
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	var snap := e.capture_state()
	e.undo_step()  # engine log now empty
	e.move_player(Vector2i(-1, 0))
	e.restore_state(snap)
	assert_eq(e.fold_count(), 1, "snapshot still holds the fold after engine changed")


func test_unfold_via_step_matches_direct_fold_list():
	# Fold twice (no player, so no fold-blocking), unfold the first via an UNFOLD
	# step: the active fold list and geometry must match a from-scratch derive of the
	# surviving fold. Anchors mirror the known-valid pair in test_fold_unfold_inverse.
	var ld := LevelData.new()
	ld.grid_size = Vector2i(10, 10)
	ld.cell_size = 64.0
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	assert_true(e.apply_fold(Vector2i(0, 1), Vector2i(2, 1)), "fold A (id 0) applies")
	assert_true(e.apply_fold(Vector2i(1, 6), Vector2i(1, 8)), "fold B (id 1) applies")
	assert_true(e.remove_fold(0), "unfold id 0")
	assert_eq(e.fold_count(), 1, "one fold remains")
	assert_eq(e.folds[0].fold_id, 1, "the surviving fold is id 1")
	var scratch := FoldReplay.derive(e.base_grid, e.folds)
	assert_eq(_occupied_set(e.get_state()), _occupied_set(scratch),
		"post-unfold geometry matches direct derive of surviving folds")


func test_large_grid_long_log_incremental():
	# Exercises incremental derivation at scale: a big grid and a long log. Each
	# appended step extends the checkpoint stack rather than replaying the whole log;
	# correctness vs a from-scratch derive is the assertion.
	var e := _engine(Vector2i(20, 20), Vector2i(40, 40))
	assert_true(e.apply_fold(Vector2i(2, 20), Vector2i(4, 20)), "edge fold applies")
	# A long run of moves in a small interior loop — every target stays occupied on
	# an open 40x40 grid, so each is a logged MOVE step.
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var moves := 0
	for i in range(40):
		if e.move_player(dirs[i % 4]):
			moves += 1
	assert_gt(moves, 0, "some moves were logged")
	assert_eq(e.steps.size(), 1 + moves, "log length = fold + successful moves")
	# Moves never change geometry, so the incremental state must equal a from-scratch
	# derive of the fold list.
	var scratch := FoldReplay.derive(e.base_grid, e.folds)
	assert_eq(_occupied_set(e.get_state()), _occupied_set(scratch),
		"incremental derivation matches from-scratch geometry over a long log")
	# And undo unwinds step-by-step back to empty.
	while e.undo_step():
		pass
	assert_eq(e.fold_count(), 0, "unwound to no folds")
	assert_eq(e.steps.size(), 0, "log fully unwound")
