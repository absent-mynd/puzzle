## FoldReplay.derive tests (Stage 2) — the heart of the re-architecture
##
## Pure, headless: build a BaseGrid, make Fold records, derive a FoldedState,
## assert observable geometry/occupancy. No nodes, no GridManager, no mutation.

extends GutTest

const EPSILON = 0.0001
const T_EMPTY := 0
const T_WALL := 1
const T_WATER := 2
const T_GOAL := 3


func _grid(size: Vector2i = Vector2i(10, 10), cell := 64.0, types: Dictionary = {}) -> BaseGrid:
	var ld := LevelData.new()
	ld.grid_size = size
	ld.cell_size = cell
	ld.cell_data = types
	return BaseGrid.from_level_data(ld)


func _fold(base: BaseGrid, a1: Vector2i, a2: Vector2i, id := 0) -> Fold:
	return Fold.create(id, a1, a2, base.cell_size)


## ---------------------------------------------------------------------------
## Identity
## ---------------------------------------------------------------------------
func test_identity_derive_one_piece_per_tile():
	var base := _grid(Vector2i(4, 3))
	var state := FoldReplay.derive(base, [])
	assert_eq(state.occupied_count(), 12, "every base tile occupies one plane position")
	for y in range(3):
		for x in range(4):
			var pieces := state.pieces_at(Vector2i(x, y))
			assert_eq(pieces.size(), 1, "one piece at %s" % Vector2i(x, y))
			assert_almost_eq(pieces[0].area(), 64.0 * 64.0, 1.0, "full-square area")


func test_identity_plane_pos_matches_base():
	var base := _grid(Vector2i(5, 5))
	var state := FoldReplay.derive(base, [])
	var bid := base.tile_at(Vector2i(3, 2)).base_id
	assert_eq(state.plane_pos_of_base(bid), Vector2i(3, 2), "base sits at its own position")


## ---------------------------------------------------------------------------
## Single horizontal fold: anchors (2,5)-(5,5). MEET-IN-THE-MIDDLE: A-side (cols
## 0-2) slides +2, B-side (cols 5-9) slides -1; they meet at col 4. Occupied 2..8.
## ---------------------------------------------------------------------------
func test_horizontal_fold_compresses_to_seven_columns():
	var base := _grid(Vector2i(10, 10))
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(2, 5), Vector2i(5, 5))])

	# Columns 2..8 occupied on every row; 0,1,9 empty.
	for y in range(10):
		for x in range(2, 9):
			assert_true(state.is_occupied(Vector2i(x, y)),
				"col %d row %d should be occupied" % [x, y])
		for x in [0, 1, 9]:
			assert_false(state.is_occupied(Vector2i(x, y)),
				"col %d row %d should be empty" % [x, y])

	assert_eq(state.occupied_count(), 70, "10x10 -> 7x10 after folding a 3-wide strip")


func test_horizontal_fold_merges_at_meeting_column():
	var base := _grid(Vector2i(10, 10))
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(2, 5), Vector2i(5, 5))])
	# Meeting column 4 gets base col2's A-half + base col5's B-half = 2 pieces.
	var pieces := state.pieces_at(Vector2i(4, 5))
	assert_eq(pieces.size(), 2, "meeting column merges two half-fragments")


func test_horizontal_fold_sides_ride_to_new_positions():
	var base := _grid(Vector2i(10, 10))
	var far_b := base.tile_at(Vector2i(8, 5)).base_id   # B-side, slides -1 -> col 7
	var far_a := base.tile_at(Vector2i(0, 5)).base_id   # A-side, slides +2 -> col 2
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(2, 5), Vector2i(5, 5))])
	assert_eq(state.plane_pos_of_base(far_b), Vector2i(7, 5), "B-side tile rides to col 7")
	assert_eq(state.plane_pos_of_base(far_a), Vector2i(2, 5), "A-side tile rides to col 2")


## ---------------------------------------------------------------------------
## Goal semantics (requirement 4)
## ---------------------------------------------------------------------------
func test_goal_between_anchors_is_excised():
	var base := _grid(Vector2i(10, 10), 64.0, {Vector2i(3, 5): T_GOAL})
	var goal_id := base.tile_at(Vector2i(3, 5)).base_id
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(2, 5), Vector2i(5, 5))])

	assert_false(state.has_base(goal_id), "goal strictly between anchors is dropped")
	# No plane position reports GOAL.
	for pos in state.stacks:
		assert_false(state.has_type_at(pos, T_GOAL), "no goal anywhere at %s" % pos)


func test_goal_on_anchor_a_merges_walkable():
	var base := _grid(Vector2i(10, 10), 64.0, {Vector2i(2, 5): T_GOAL})
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(2, 5), Vector2i(5, 5))])
	# anchor_a's goal half slides +2 to the meeting column 4; dominant is GOAL.
	assert_eq(state.dominant_type_at(Vector2i(4, 5)), T_GOAL,
		"goal on anchor_a rides to the meeting column and stays reachable")


func test_goal_on_anchor_b_rides_and_merges():
	var base := _grid(Vector2i(10, 10), 64.0, {Vector2i(5, 5): T_GOAL})
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(2, 5), Vector2i(5, 5))])
	# anchor_b's goal half slides -1 to the meeting column 4 and merges as a goal.
	assert_eq(state.dominant_type_at(Vector2i(4, 5)), T_GOAL,
		"goal on anchor_b rides onto the meeting column")


## ---------------------------------------------------------------------------
## Vertical + diagonal
## ---------------------------------------------------------------------------
func test_vertical_fold_compresses_rows():
	var base := _grid(Vector2i(10, 10))
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(5, 2), Vector2i(5, 5))])
	# anchor_a=(5,2) A-side slides +2, anchor_b=(5,5) B-side slides -1; rows 2..8.
	assert_eq(state.occupied_count(), 70, "vertical 3-tall strip removed -> 10x7")
	for x in range(10):
		assert_true(state.is_occupied(Vector2i(x, 5)), "row 5 present")
		assert_false(state.is_occupied(Vector2i(x, 0)), "row 0 empty")
		assert_false(state.is_occupied(Vector2i(x, 9)), "row 9 empty")


func test_diagonal_fold_compresses_and_is_stable():
	var base := _grid(Vector2i(10, 10))
	var state := FoldReplay.derive(base, [_fold(base, Vector2i(2, 2), Vector2i(5, 5))])
	assert_lt(state.occupied_count(), 100, "diagonal fold reduces occupied cells")
	assert_gt(state.occupied_count(), 0, "diagonal fold leaves a board")


## ---------------------------------------------------------------------------
## Stacked folds compose
## ---------------------------------------------------------------------------
func test_two_horizontal_folds_compose():
	var base := _grid(Vector2i(10, 10))
	var f1 := _fold(base, Vector2i(2, 5), Vector2i(5, 5), 0)  # -> occupied cols 2..8
	# Second fold targets still-occupied columns so it removes real content.
	var f2 := _fold(base, Vector2i(4, 5), Vector2i(7, 5), 1)
	var state := FoldReplay.derive(base, [f1, f2])
	assert_lt(state.occupied_count(), 70, "second fold compresses further")
	# First fold alone:
	var one := FoldReplay.derive(base, [f1])
	assert_eq(one.occupied_count(), 70, "single fold unchanged by presence of f2 in list order")
