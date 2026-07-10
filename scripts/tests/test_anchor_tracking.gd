## Anchor base-point tracking + re-resolve on unfold (new mechanic)
##
## Placed anchors pin to a BASE-SPACE point (the point mapped back through the folds).
## Their current position is derived by transforming that point forward through the fold
## list; an anchor whose point is ambiguous (on a seam) or hidden (excised) disappears.

extends GutTest

const INF := Vector2.INF


func _setup() -> Dictionary:
	var gm := GridManager.new()
	gm.grid_size = Vector2i(10, 10)
	gm.cell_size = 64.0
	gm.create_grid()
	add_child_autofree(gm)

	var fc := FoldController.new()
	add_child_autofree(fc)
	fc.initialize(gm)
	gm.fold_system = fc
	return {"gm": gm, "fc": fc}


func _center(pos: Vector2i) -> Vector2:
	return Vector2(pos) * 64.0 + Vector2(32, 32)


func test_base_point_at_full_cell_is_identity():
	var s := _setup()
	# No folds -> a cell center maps to itself in base space.
	var bp: Vector2 = s.fc.base_point_at(_center(Vector2i(3, 3)))
	assert_true(bp != INF, "plain cell center is unambiguous")
	assert_almost_eq(bp.distance_to(_center(Vector2i(3, 3))), 0.0, 0.01, "identity map with no folds")


func test_cell_center_covered_full_vs_void():
	var s := _setup()
	assert_true(s.fc.cell_center_covered(Vector2i(3, 3)), "full cell center is covered")
	assert_false(s.fc.cell_center_covered(Vector2i(99, 99)), "void cell center is not covered")


func test_base_point_at_seam_is_ambiguous():
	var s := _setup()
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	# The merged meeting cell's center sits on the seam -> ambiguous (INF).
	assert_eq(s.fc.base_point_at(_center(Vector2i(4, 5))), INF, "seam center is ambiguous")


func test_anchor_follows_tile_through_unfold():
	var s := _setup()
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	# Col 7 is a full cell after the fold (base originally at col 8, rode -1). Anchor it.
	assert_true(s.gm.select_cell(Vector2i(7, 5)), "anchor placed on col 7")

	# Unfold: the tile returns to col 8, and the anchor rides with it.
	assert_true(s.fc.unfold_seam(0), "unfold succeeds")
	assert_eq(s.gm.get_selected_anchors().size(), 1, "anchor survives (unambiguous)")
	assert_eq(s.gm.get_selected_anchors()[0], Vector2i(8, 5),
		"anchor rode its base tile back to col 8 on unfold")


func test_ambiguous_anchor_disappears_on_unfold():
	var s := _setup()
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	# Force an ambiguous anchor (as if placed exactly on the seam).
	s.gm.set_selection([Vector2i(4, 5)], [INF])
	assert_eq(s.gm.get_selected_anchors().size(), 1, "one anchor before unfold")

	assert_true(s.fc.unfold_seam(0), "unfold succeeds")
	assert_eq(s.gm.get_selected_anchors().size(), 0,
		"anchor placed on the unfolded seam disappears")


func test_side_anchor_follows_its_side_on_unfold():
	var s := _setup()
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	# A point strictly inside one side's piece of the merged meeting cell.
	var pieces: Array = s.fc.get_state().surface_pieces_at(Vector2i(4, 5))
	assert_gt(pieces.size(), 1, "meeting cell is merged")
	var side_base: int = pieces[0].base_id
	var home: Vector2i = s.fc.engine.base_grid.tile_by_id(side_base).grid_position

	assert_true(s.gm.select_cell(Vector2i(4, 5), pieces[0].center()), "anchor placed on one side")
	assert_true(s.fc.unfold_seam(0), "unfold succeeds")
	assert_eq(s.gm.get_selected_anchors().size(), 1, "side anchor survives")
	assert_eq(s.gm.get_selected_anchors()[0], home, "side anchor rode its side's tile home")
