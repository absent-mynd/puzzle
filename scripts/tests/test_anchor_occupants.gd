## Anchors-as-occupants tests (F6)
##
## Anchors are first-class occupants (KIND_ANCHOR): level/element-spawnable, they ride
## folds and split on a seam via the SAME latent machinery as player/box — the whole
## point of unifying them into the occupant model. Placement is a logged step, so it
## rides folds and undoes cleanly.
##
## NOTE: using a split anchor to author a 3+ anchor fold is deferred with N-anchor; this
## covers the occupant foundation (ride / split / spawn / place / undo).

extends GutTest


func _engine(cells: Dictionary, start := Vector2i(0, 0), grid := Vector2i(10, 10)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = cells
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func test_level_authored_anchor_loads_and_rides_fold():
	var e := _engine({Vector2i(5, 5): {"type": 0, "occupant": "anchor", "channel": "A"}})
	assert_eq(e.anchor_positions().size(), 1, "one anchor occupant from the level")
	assert_true(Vector2i(5, 5) in e.anchor_positions()[0], "anchor at its authored cell")
	# A fold on the anchor's flank slides it inward, like any tile-riding occupant.
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(4, 5)), "fold applies")
	assert_true(Vector2i(4, 5) in e.anchor_positions()[0], "anchor rode the fold from (5,5) to (4,5)")


func test_player_placed_anchor_is_an_undoable_occupant():
	var e := _engine({})
	e.place_anchor(Vector2i(3, 3))
	assert_eq(e.anchor_positions().size(), 1, "anchor placed")
	assert_true(Vector2i(3, 3) in e.anchor_positions()[0], "at the requested cell")
	assert_true(e.undo_step(), "undo the placement")
	assert_eq(e.anchor_positions().size(), 0, "anchor removed by undo")


func test_anchor_hidden_by_fold_reappears_on_unfold():
	# An anchor fully inside the excised strip vanishes into the seam, then returns.
	var e := _engine({Vector2i(5, 5): {"type": 0, "occupant": "anchor"}})
	assert_true(e.apply_fold(Vector2i(4, 5), Vector2i(6, 5)), "fold excises the anchor's cell")
	assert_eq(e.anchor_positions()[0].size(), 0, "anchor hidden while folded")
	assert_true(e.remove_fold(0), "unfold")
	assert_true(Vector2i(5, 5) in e.anchor_positions()[0], "anchor reappears where it was")


func test_anchor_on_seam_splits_on_unfold():
	# Place an anchor on an anchor-cell (straddles a crease): the fold cuts it, and
	# unfolding after the surviving part is separated yields two anchor cells.
	var e := _engine({})
	e.place_anchor(Vector2i(3, 5))
	# A fold whose crease runs through the anchor's tile cuts it (records a latent).
	assert_true(e.apply_fold(Vector2i(3, 5), Vector2i(6, 5)), "fold cuts the anchor tile")
	assert_true(e.remove_fold(0), "unfold")
	# Without any intervening move the split rejoins (dedup) -> still one cell.
	assert_eq(e.anchor_positions()[0].size(), 1, "anchor rejoined (no divergence) -> single cell")


func test_anchor_survives_capture_restore():
	var e := _engine({Vector2i(5, 5): {"type": 0, "occupant": "anchor", "channel": "Z"}})
	e.apply_fold(Vector2i(2, 5), Vector2i(4, 5))
	var snap := e.capture_state()
	e.move_player(Vector2i(1, 0))
	e.restore_state(snap)
	assert_eq(e.anchor_positions().size(), 1, "anchor restored")
	assert_true(Vector2i(4, 5) in e.anchor_positions()[0], "at its post-fold position")
