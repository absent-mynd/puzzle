## Player-riding + fold-blocking tests (Stage 3)
##
## The player is attached to a base tile (player_base_id). After any fold/unfold the
## player's plane position follows that base tile — no bespoke shift-tracking. Folds
## that would excise or split the player's cell are rejected.

extends GutTest


func _engine(start: Vector2i, types: Dictionary = {}) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = Vector2i(10, 10)
	ld.cell_size = 64.0
	ld.cell_data = types
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func test_player_rides_shifted_cell():
	# Player on the B-side; meet-in-the-middle slides their cell left by 1 (col 8 -> 7).
	var e := _engine(Vector2i(8, 5))
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "fold applies")
	assert_eq(e.player_plane_pos, Vector2i(7, 5), "player rides from col 8 to col 7")
	# And still stands on a real, walkable cell.
	assert_true(e.get_state().is_occupied(e.player_plane_pos), "player cell exists")


func test_player_on_a_side_rides_toward_center():
	# Meet-in-the-middle: both sides move. A-side player (col 0) slides +2 to col 2.
	var e := _engine(Vector2i(0, 5))
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "fold applies")
	assert_eq(e.player_plane_pos, Vector2i(2, 5), "A-side player rides inward to col 2")


func test_fold_through_player_is_rejected():
	# Player sits strictly between the anchors -> fold must be blocked.
	var e := _engine(Vector2i(3, 5))
	assert_false(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)),
		"cannot fold with the player in the excised region")
	assert_eq(e.fold_count(), 0, "no fold recorded")


func test_fold_splitting_player_cell_permitted_when_lands_navigable():
	# Player on an anchor cell (edge of the fold). New rule: permit if the tile they ride
	# to is navigable. Here they ride to the meeting cell (4,5), which is walkable.
	var e := _engine(Vector2i(2, 5))
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)),
		"fold permitted: player on the fold edge lands on a navigable tile")
	assert_eq(e.player_plane_pos, Vector2i(4, 5), "player rides to the meeting cell")


func test_fold_splitting_player_fits_beside_wall_subtile():
	# Player on anchor_a (empty); anchor_b is a wall. Both halves merge at (4,5): the
	# player's floor fragment and the wall's fragment share the cell in different
	# sub-regions. With SUB-TILE collision the player fits on the floor sub-region
	# beside the wall, so the fold is allowed (the whole-cell rule used to block it).
	var e := _engine(Vector2i(2, 5), {Vector2i(5, 5): 1})  # 1 = wall
	var result := e.player_fold_result(Vector2i(2, 5), Vector2i(5, 5))
	assert_false(result["blocks"], "fold allowed: player fits on the floor beside the wall")
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "apply succeeds")
	assert_eq(e.fold_count(), 1, "fold recorded")
	assert_eq(e.player_plane_pos, Vector2i(4, 5), "player rode to the meeting cell")
	assert_true(e.get_state().has_type_at(Vector2i(4, 5), 1), "a wall fragment shares that cell")
	assert_true(e.get_state().is_walkable(Vector2i(4, 5)), "but the floor sub-region is walkable")


func test_player_rides_back_on_unfold():
	var e := _engine(Vector2i(8, 5))
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	assert_eq(e.player_plane_pos, Vector2i(7, 5), "rode to col 7")
	assert_true(e.remove_fold(0), "unfold")
	assert_eq(e.player_plane_pos, Vector2i(8, 5), "player rides back to col 8 on unfold")


func test_move_then_fold_player_tracks_new_base():
	var e := _engine(Vector2i(8, 5))
	assert_true(e.move_player(Vector2i(-1, 0)), "move to col 7")
	assert_eq(e.player_plane_pos, Vector2i(7, 5), "moved")
	assert_true(e.apply_fold(Vector2i(2, 5), Vector2i(5, 5)), "fold applies")
	assert_eq(e.player_plane_pos, Vector2i(6, 5), "col 7 (B-side) rides left by 1 to col 6")
