## Sub-tile collision tests (F-sub)
##
## Walkability is per-fragment, not whole-cell: a body stands on the covered walkable
## sub-region even when the rest of the cell is void or a wall. Positioning uses the
## body's own fragment centroid, so it sits on its sub-region.

extends GutTest

const T_EMPTY := 0
const T_WALL := 1


func _left_half(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o, o + Vector2(cell / 2.0, 0), o + Vector2(cell / 2.0, cell), o + Vector2(0, cell)])


func _right_half(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o + Vector2(cell / 2.0, 0), o + Vector2(cell, 0), o + Vector2(cell, cell), o + Vector2(cell / 2.0, cell)])


func test_partial_floor_is_walkable():
	# A lone half-floor fragment (rest void) — incomplete, but walkable under sub-tile.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _left_half(Vector2i(1, 1)), Vector2i(1, 1), 0))
	s.finalize()
	assert_false(s.is_complete(Vector2i(1, 1), 64.0), "cell is only half-covered")
	assert_true(s.is_walkable(Vector2i(1, 1)), "but the covered floor sub-region is walkable")


func test_floor_beside_wall_is_walkable_on_the_floor():
	# Half floor + half wall sharing a cell: dominant type is wall, yet the floor
	# sub-region is walkable (a body fits beside the wall).
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _left_half(Vector2i(2, 2)), Vector2i(2, 2), 0))
	s.add_piece(FoldedPiece.new(1, T_WALL, _right_half(Vector2i(2, 2)), Vector2i(2, 2), 0))
	s.finalize()
	assert_eq(s.dominant_type_at(Vector2i(2, 2)), T_WALL, "wall still dominates the cell's type")
	assert_true(s.is_walkable(Vector2i(2, 2)), "but the floor sub-region is walkable")
	assert_eq(s.walkable_pieces_at(Vector2i(2, 2)).size(), 1, "only the floor fragment is walkable")


func test_fully_wall_cell_is_not_walkable():
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_WALL, _left_half(Vector2i(3, 3)), Vector2i(3, 3), 0))
	s.add_piece(FoldedPiece.new(1, T_WALL, _right_half(Vector2i(3, 3)), Vector2i(3, 3), 0))
	s.finalize()
	assert_false(s.is_walkable(Vector2i(3, 3)), "no walkable fragment -> not walkable")


func test_center_of_base_is_sub_cell():
	# A body on a half-floor sits at the half's centroid, offset from the cell center.
	var s := FoldedState.new()
	s.add_piece(FoldedPiece.new(0, T_EMPTY, _left_half(Vector2i(0, 0)), Vector2i(0, 0), 0))
	s.finalize()
	var c := s.center_of_base_at(0, Vector2i(0, 0), 64.0)
	var cell_center := Vector2(32, 32)
	assert_almost_eq(c.x, 16.0, 0.5, "left-half centroid sits left of the cell center")
	assert_gt(cell_center.distance_to(c), 5.0, "body position is sub-cell, not the cell center")


func test_player_rides_sub_cell_beside_wall():
	# End-to-end: fold the player (on empty anchor_a) toward a wall anchor_b. They land
	# on the floor sub-region of the merged meeting cell, positioned off-center.
	var ld := LevelData.new()
	ld.grid_size = Vector2i(10, 10)
	ld.cell_size = 64.0
	ld.cell_data = {Vector2i(5, 5): T_WALL}
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(Vector2i(2, 5))
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "fold beside the wall is allowed")
	var pos := e.player_plane_pos
	assert_true(e.get_state().is_walkable(pos), "player stands on a walkable sub-region")
	var cell_center := Vector2(pos) * 64.0 + Vector2(32, 32)
	assert_gt(cell_center.distance_to(e.player_center(64.0)), 5.0,
		"player is positioned on its fragment centroid, not the merged cell center")
