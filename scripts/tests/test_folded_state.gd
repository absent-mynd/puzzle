## FoldedState query + merge-rule unit tests (Stage 2)
##
## Exercises the derived-state container directly with hand-built pieces, so the
## merge priority, occupancy, centroid, and ordering logic are pinned independent
## of the replay engine.

extends GutTest

const EPSILON = 0.0001
const T_EMPTY := 0
const T_WALL := 1
const T_WATER := 2
const T_GOAL := 3


func _square(pos: Vector2i, cell := 64.0) -> PackedVector2Array:
	var o := Vector2(pos) * cell
	return PackedVector2Array([o, o + Vector2(cell, 0), o + Vector2(cell, cell), o + Vector2(0, cell)])


func _piece(base_id: int, type: int, pos: Vector2i, fold_id := -1) -> FoldedPiece:
	return FoldedPiece.new(base_id, type, _square(pos), pos, fold_id)


func test_empty_position_is_void():
	var s := FoldedState.new()
	assert_false(s.is_occupied(Vector2i(0, 0)), "no pieces -> not occupied")
	assert_eq(s.pieces_at(Vector2i(0, 0)).size(), 0, "no pieces returned")


func test_single_piece_occupancy_and_type():
	var s := FoldedState.new()
	s.add_piece(_piece(0, T_WATER, Vector2i(1, 1)))
	s.finalize()
	assert_true(s.is_occupied(Vector2i(1, 1)), "occupied")
	assert_eq(s.dominant_type_at(Vector2i(1, 1)), T_WATER, "single type dominates")


func test_merge_priority_goal_beats_empty():
	var s := FoldedState.new()
	s.add_piece(_piece(0, T_EMPTY, Vector2i(2, 2)))
	s.add_piece(_piece(1, T_GOAL, Vector2i(2, 2)))
	s.finalize()
	assert_eq(s.dominant_type_at(Vector2i(2, 2)), T_GOAL, "goal reachable when merged with floor")


func test_merge_priority_goal_beats_wall():
	# Current tunable: goal > wall (matches legacy priority minus null).
	var s := FoldedState.new()
	s.add_piece(_piece(0, T_WALL, Vector2i(2, 2)))
	s.add_piece(_piece(1, T_GOAL, Vector2i(2, 2)))
	s.finalize()
	assert_eq(s.dominant_type_at(Vector2i(2, 2)), T_GOAL, "goal wins over wall (per plan default)")


func test_merge_priority_wall_beats_water_and_empty():
	var s := FoldedState.new()
	s.add_piece(_piece(0, T_EMPTY, Vector2i(0, 0)))
	s.add_piece(_piece(1, T_WATER, Vector2i(0, 0)))
	s.add_piece(_piece(2, T_WALL, Vector2i(0, 0)))
	s.finalize()
	assert_eq(s.dominant_type_at(Vector2i(0, 0)), T_WALL, "wall blocks when no goal present")


func test_has_type_at():
	var s := FoldedState.new()
	s.add_piece(_piece(0, T_EMPTY, Vector2i(0, 0)))
	s.add_piece(_piece(1, T_GOAL, Vector2i(0, 0)))
	s.finalize()
	assert_true(s.has_type_at(Vector2i(0, 0), T_GOAL), "goal present in stack")
	assert_false(s.has_type_at(Vector2i(0, 0), T_WATER), "no water in stack")


func test_stack_order_later_fold_on_top():
	var s := FoldedState.new()
	s.add_piece(_piece(0, T_EMPTY, Vector2i(0, 0), 2))   # later fold
	s.add_piece(_piece(1, T_WATER, Vector2i(0, 0), 5))   # latest fold
	s.add_piece(_piece(2, T_WALL, Vector2i(0, 0), -1))   # base
	s.finalize()
	var arr := s.pieces_at(Vector2i(0, 0))
	assert_eq(arr[0].source_fold_id, 5, "latest fold sits on top")
	assert_eq(arr[arr.size() - 1].source_fold_id, -1, "base geometry sits at bottom")
	assert_eq(arr[0].stack_order, 0, "top has stack_order 0")


func test_base_to_piece_prefers_largest_fragment():
	var s := FoldedState.new()
	var big := _piece(7, T_EMPTY, Vector2i(1, 0))          # full square, area 4096
	var small := FoldedPiece.new(7, T_EMPTY, PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]), Vector2i(0, 0), 1)
	s.add_piece(small)
	s.add_piece(big)
	s.finalize()
	assert_eq(s.plane_pos_of_base(7), Vector2i(1, 0), "primary fragment is the largest one")


func test_plane_pos_of_missing_base_is_sentinel():
	var s := FoldedState.new()
	assert_eq(s.plane_pos_of_base(999), Vector2i(-99999, -99999), "excised/missing base -> sentinel")


func test_center_at_weighted_centroid():
	var s := FoldedState.new()
	s.add_piece(_piece(0, T_EMPTY, Vector2i(0, 0)))  # square [0,64]^2 -> center (32,32)
	s.finalize()
	assert_almost_eq(s.center_at(Vector2i(0, 0)).distance_to(Vector2(32, 32)), 0.0, EPSILON,
		"single-square center is its centroid")


func test_center_at_empty_falls_back_to_cell_center():
	var s := FoldedState.new()
	var c := s.center_at(Vector2i(2, 3), 64.0)
	assert_almost_eq(c.distance_to(Vector2(2 * 64 + 32, 3 * 64 + 32)), 0.0, EPSILON,
		"empty position falls back to nominal cell center")
