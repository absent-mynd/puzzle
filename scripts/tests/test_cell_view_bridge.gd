## Cell-as-view bridge tests (Stage 4)
##
## Verifies that a derived FoldedState materializes back into GridManager.cells as
## view Cells, so existing consumers (get_cell().get_dominant_type / has_cell_type /
## get_center) observe the folded configuration through the unchanged Cell API.

extends GutTest

const T_GOAL := 3
const T_WALL := 1


func _gm(size := Vector2i(10, 10)) -> GridManager:
	var gm := GridManager.new()
	gm.grid_size = size
	gm.cell_size = 64.0
	gm.create_grid()
	add_child_autofree(gm)
	return gm


func test_base_grid_snapshot_from_grid_manager():
	var gm := _gm(Vector2i(6, 4))
	gm.get_cell(Vector2i(2, 1)).set_cell_type(T_WALL)
	gm.get_cell(Vector2i(5, 3)).set_cell_type(T_GOAL)
	var base := BaseGrid.from_grid_manager(gm)
	assert_eq(base.tiles.size(), 24, "one base tile per cell")
	assert_eq(base.tile_at(Vector2i(2, 1)).type, T_WALL, "wall captured")
	assert_eq(base.tile_at(Vector2i(5, 3)).type, T_GOAL, "goal captured")
	assert_eq(base.tile_at(Vector2i(0, 0)).type, 0, "empty captured")


func test_apply_folded_pieces_sets_dominant_type():
	var gm := _gm(Vector2i(4, 4))
	var cell := gm.get_cell(Vector2i(1, 1))
	var poly := PackedVector2Array([Vector2(64, 64), Vector2(128, 64), Vector2(128, 128), Vector2(64, 128)])
	var fp := FoldedPiece.new(0, T_GOAL, poly, Vector2i(1, 1), 0)
	cell.apply_folded_pieces([fp])
	assert_eq(cell.get_dominant_type(), T_GOAL, "view cell reports derived dominant type")
	assert_true(cell.has_cell_type(T_GOAL), "view cell reports contained type")


func test_refresh_from_state_matches_fold_outcome():
	var gm := _gm(Vector2i(10, 10))
	var base := BaseGrid.from_grid_manager(gm)
	var state := FoldReplay.derive(base, [Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), 64.0)])
	gm.refresh_from_state(state)

	# Meet-in-the-middle: occupied columns 2..8 exist; 0,1,9 freed from the view cache.
	for x in range(2, 9):
		assert_not_null(gm.get_cell(Vector2i(x, 5)), "col %d present after refresh" % x)
	for x in [0, 1, 9]:
		assert_null(gm.get_cell(Vector2i(x, 5)), "col %d freed after refresh" % x)


func test_refresh_preserves_goal_reachability_for_player_api():
	# Goal rides onto the target column and must read as GOAL through get_cell().
	var gm := _gm(Vector2i(10, 10))
	gm.get_cell(Vector2i(5, 5)).set_cell_type(T_GOAL)
	var base := BaseGrid.from_grid_manager(gm)
	var state := FoldReplay.derive(base, [Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), 64.0)])
	gm.refresh_from_state(state)

	# Goal on anchor_b (5,5) rides to the meeting column (4,5).
	var target := gm.get_cell(Vector2i(4, 5))
	assert_not_null(target, "meeting column occupied")
	assert_eq(target.get_dominant_type(), T_GOAL, "merged goal reachable via Cell API")


func test_refresh_removes_goal_between_anchors():
	var gm := _gm(Vector2i(10, 10))
	gm.get_cell(Vector2i(3, 5)).set_cell_type(T_GOAL)
	var base := BaseGrid.from_grid_manager(gm)
	var state := FoldReplay.derive(base, [Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), 64.0)])
	gm.refresh_from_state(state)

	# No view cell anywhere should report GOAL (it was excised).
	var goal_seen := false
	for pos in gm.cells.keys():
		var c = gm.cells[pos]
		if is_instance_valid(c) and c.has_cell_type(T_GOAL):
			goal_seen = true
	assert_false(goal_seen, "goal between anchors is absent from the view")


func test_view_cells_have_no_null_pieces():
	# The new model has no null pieces, so anchor-eligibility (is_anchor_eligible)
	# naturally treats every occupied cell as eligible.
	var gm := _gm(Vector2i(10, 10))
	var base := BaseGrid.from_grid_manager(gm)
	var state := FoldReplay.derive(base, [Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), 64.0)])
	gm.refresh_from_state(state)
	for pos in gm.cells.keys():
		var c = gm.cells[pos]
		if is_instance_valid(c):
			assert_false(c.has_null_piece(), "no null pieces at %s" % pos)
			assert_true(gm.is_anchor_eligible(pos), "occupied cell is anchor-eligible at %s" % pos)
