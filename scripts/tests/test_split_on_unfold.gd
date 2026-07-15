## Split-on-unfold tests (F6)
##
## When a fold hides part of an occupant, that part becomes a latent body; unfolding
## re-materializes it at its home tile. If the surviving part moved away in between,
## the occupant ends up in two places — a SPLIT. A fully-hidden occupant (e.g. a box
## folded over entirely) simply reappears where it was.

extends GutTest


func _engine(cells: Dictionary, start: Vector2i, grid := Vector2i(10, 10)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = cells
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func test_player_splits_when_moved_then_unfolded():
	# Player sits on an anchor, so the fold cuts its tile: the flap survives (active),
	# the hidden half becomes a latent. Move the survivor away, then unfold — the
	# hidden half reappears at home, separate from the moved body: a split.
	var e := _engine({}, Vector2i(3, 5))
	assert_true(e.apply_fold(Vector2i(3, 5), Vector2i(6, 5)), "fold cuts the player's tile")
	assert_eq(e.player_positions().size(), 1, "one active body after the fold (flap); other half latent")
	# Move the surviving body away from home.
	assert_true(e.move_player(Vector2i(0, -1)), "survivor steps away")
	assert_eq(e.player_positions().size(), 1, "still one body while folded")
	assert_true(e.remove_fold(0), "unfold")
	assert_eq(e.player_positions().size(), 2, "the hidden half reappeared: player is split")


func test_fold_then_unfold_without_moving_does_not_split():
	# If the survivor never leaves, the reappearing half rejoins it (dedup) — no split.
	var e := _engine({}, Vector2i(3, 5))
	assert_true(e.apply_fold(Vector2i(3, 5), Vector2i(6, 5)), "fold cuts the player's tile")
	assert_true(e.remove_fold(0), "unfold immediately")
	assert_eq(e.player_positions().size(), 1, "player is whole again, not split")


func test_split_bodies_both_respond_to_one_input():
	var e := _engine({}, Vector2i(3, 5))
	e.apply_fold(Vector2i(3, 5), Vector2i(6, 5))
	e.move_player(Vector2i(0, -1))
	e.remove_fold(0)
	assert_eq(e.player_positions().size(), 2, "split into two bodies")
	var before := e.player_positions()
	assert_true(e.move_player(Vector2i(0, -1)), "one input moves the split player")
	var after := e.player_positions()
	# Both bodies advanced upward (y decreased) — neither was left behind.
	for p in before:
		assert_true((p + Vector2i(0, -1)) in after, "each body advanced on the shared input")


func test_box_folded_over_hides_then_reappears():
	# A box fully inside the excised strip vanishes into the seam, then reappears at
	# its original cell when the fold is undone.
	var e := _engine({Vector2i(5, 5): {"type": 0, "occupant": "box"}}, Vector2i(0, 0))
	assert_true(Vector2i(5, 5) in e.box_positions()[0], "box starts at (5,5)")
	assert_true(e.apply_fold(Vector2i(4, 5), Vector2i(6, 5)), "fold excises the box's cell")
	assert_eq(e.box_positions()[0].size(), 0, "box is hidden while folded")
	assert_true(e.remove_fold(0), "unfold")
	assert_true(Vector2i(5, 5) in e.box_positions()[0], "box reappears where it was")


func test_split_survives_capture_restore():
	# The split state is fully derived from the log, so it round-trips through undo/redo.
	var e := _engine({}, Vector2i(3, 5))
	e.apply_fold(Vector2i(3, 5), Vector2i(6, 5))
	e.move_player(Vector2i(0, -1))
	e.remove_fold(0)
	var snap := e.capture_state()
	e.move_player(Vector2i(0, -1))
	e.restore_state(snap)
	assert_eq(e.player_positions().size(), 2, "restore reproduces the split")
