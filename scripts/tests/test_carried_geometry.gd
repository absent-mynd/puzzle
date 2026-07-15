## Carried rigid geometry — "cuts stay cut" (collision engine, Stage 4)
##
## A diagonal fold cuts the player in half; the surviving half is a triangle it carries
## RIGIDLY (stays a triangle as it moves — no healing). When the fold is unfolded, the
## missing half reappears at its original spot with its cut geometry, as a second body
## of the same (player) entity. Fold+unfold with no move rejoins to the whole.

extends GutTest

const CELL := 64.0
const FULL := CELL * CELL


func _engine(start := Vector2i(4, 4), grid := Vector2i(10, 10)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = CELL
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func _area(fp: Array) -> float:
	var a := 0.0
	for p in fp:
		a += GeometryCore.polygon_area(p)
	return a


func test_diagonal_fold_cuts_player_into_a_triangle():
	var e := _engine()
	assert_true(e.apply_fold(Vector2i(4, 4), Vector2i(6, 6)), "diagonal fold cuts the player")
	assert_almost_eq(_area(e.player_footprint()), FULL / 2.0, 1.0, "player is now a half (triangle)")


func test_cut_shape_persists_across_moves():
	var e := _engine()
	e.apply_fold(Vector2i(4, 4), Vector2i(6, 6))
	var before := e.player_plane_pos
	assert_true(e.move_player(Vector2i(0, -1)), "the triangle navigates away")
	assert_ne(e.player_plane_pos, before, "it moved")
	assert_almost_eq(_area(e.player_footprint()), FULL / 2.0, 1.0,
		"it is STILL a triangle after moving — rigid, no heal")


func test_unfold_reappears_missing_half_as_second_body():
	var e := _engine()
	e.apply_fold(Vector2i(4, 4), Vector2i(6, 6))
	e.move_player(Vector2i(0, -1))
	assert_eq(e.player_positions().size(), 1, "one active body while folded")
	assert_true(e.remove_fold(0), "unfold the fold that split him")
	assert_eq(e.player_positions().size(), 2, "the missing half reappeared as a second body")
	assert_almost_eq(_area(e.player_footprint()), FULL, 1.0,
		"the two pieces together carry the whole original cell's geometry")


func test_both_pieces_move_as_one_entity():
	var e := _engine()
	e.apply_fold(Vector2i(4, 4), Vector2i(6, 6))
	e.move_player(Vector2i(0, -1))
	e.remove_fold(0)
	var before := e.player_positions()
	before.sort()
	# One input moves the whole (split) player entity.
	assert_true(e.move_player(Vector2i(0, -1)), "one input drives the split player")
	var after := e.player_positions()
	assert_eq(after.size(), 2, "still two bodies after the shared input")


func test_fold_then_unfold_without_moving_rejoins_whole():
	var e := _engine()
	e.apply_fold(Vector2i(4, 4), Vector2i(6, 6))
	assert_true(e.remove_fold(0), "unfold immediately, no move")
	assert_eq(e.player_positions().size(), 1, "rejoined to a single body")
	assert_almost_eq(_area(e.player_footprint()), FULL, 1.0, "back to the whole cell")
