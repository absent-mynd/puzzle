## Swept collision — engine-level tests (collision engine, Stage 3)
##
## Movement is gated by the occupant's real shape sweeping its path, not by area. A body
## can't phase through a wall it shares a cell with; a whole body can't enter a partial
## cell; normal full-on-full movement is unaffected.

extends GutTest

const CELL := 64.0


func _engine(start: Vector2i, cells := {}, grid := Vector2i(10, 10)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = CELL
	ld.cell_data = cells
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func test_cut_player_cannot_phase_through_adjacent_wall():
	# Fold the player (on anchor_a) toward a wall anchor_b: the player becomes a half
	# footprint sharing the meeting cell with the wall's half. Sliding on requires
	# passing THROUGH the wall's half — swept collision refuses it.
	var e := _engine(Vector2i(2, 5), {Vector2i(5, 5): 1})
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "fold applies")
	var before := e.player_plane_pos
	assert_false(e.move_player(Vector2i(1, 0)), "cannot slide through the wall half")
	assert_eq(e.player_plane_pos, before, "player stayed put")


func test_player_cannot_enter_fully_walled_cell():
	var e := _engine(Vector2i(0, 5), {Vector2i(1, 5): 1})
	assert_false(e.move_player(Vector2i(1, 0)), "a wall cell blocks entry")
	assert_eq(e.player_plane_pos, Vector2i(0, 5), "stayed")


func test_player_cannot_step_off_grid():
	var e := _engine(Vector2i(0, 5))
	assert_false(e.move_player(Vector2i(-1, 0)), "void (off-grid) blocks the slide")


func test_normal_full_movement_still_works():
	var e := _engine(Vector2i(3, 5))
	assert_true(e.move_player(Vector2i(1, 0)), "full body slides freely onto full floor")
	assert_eq(e.player_plane_pos, Vector2i(4, 5), "advanced one cell")


func test_non_colliding_anchor_does_not_block():
	# An anchor occupant (collides=false) in the path is passed through freely.
	var e := _engine(Vector2i(0, 5), {Vector2i(1, 5): {"type": 0, "occupant": "anchor"}})
	assert_true(e.move_player(Vector2i(1, 0)), "player passes through a non-colliding anchor")
	assert_eq(e.player_plane_pos, Vector2i(1, 5), "advanced onto the anchor's cell")


func test_box_push_onto_full_floor_ok_but_into_wall_blocked():
	# Push onto clear floor works; pushing a box into a wall is refused (swept).
	var e := _engine(Vector2i(0, 5), {Vector2i(2, 5): {"type": 0, "occupant": "box"}})
	assert_true(e.move_player(Vector2i(1, 0)), "step to (1,5)")
	assert_true(e.move_player(Vector2i(1, 0)), "push the box onto clear floor")
	assert_true(Vector2i(3, 5) in e.box_positions()[0], "box pushed to (3,5)")

	var e2 := _engine(Vector2i(0, 5), {Vector2i(2, 5): {"type": 0, "occupant": "box"}, Vector2i(3, 5): 1})
	e2.move_player(Vector2i(1, 0))
	assert_false(e2.move_player(Vector2i(1, 0)), "cannot push a box into a wall")
	assert_true(Vector2i(2, 5) in e2.box_positions()[0], "box did not move")
