## Pushable box tests (F6 — occupant generalization)
##
## A box is an OCCUPANT (not a tile type): a floor tile carrying data.occupant=="box".
## It rides folds like the player, blocks movement, and is pushed one cell when the
## player walks into it (if the box's own destination is clear). All of this is part
## of the replayable derivation, so pushes undo cleanly.

extends GutTest


func _engine(cells: Dictionary, start: Vector2i, grid := Vector2i(8, 3)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = 64.0
	ld.cell_data = cells
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func _box(cells := {}) -> Dictionary:
	# helper to declare a box on a floor tile
	return {"type": 0, "occupant": "box"}


func test_box_loads_as_occupant():
	var e := _engine({Vector2i(2, 1): _box()}, Vector2i(0, 1))
	assert_eq(e.box_positions().size(), 1, "one box occupant loaded")
	assert_true(Vector2i(2, 1) in e.box_positions()[0], "box starts at (2,1)")


func test_player_pushes_box():
	var e := _engine({Vector2i(2, 1): _box()}, Vector2i(0, 1))
	assert_true(e.move_player(Vector2i(1, 0)), "step to (1,1)")
	assert_true(e.move_player(Vector2i(1, 0)), "step into the box, pushing it")
	assert_eq(e.player_plane_pos, Vector2i(2, 1), "player advanced into the box's old cell")
	assert_true(Vector2i(3, 1) in e.box_positions()[0], "box was pushed to (3,1)")


func test_push_blocked_by_wall_is_noop():
	# Box at (2,1) with a wall right behind it at (3,1): pushing is impossible.
	var e := _engine({Vector2i(2, 1): _box(), Vector2i(3, 1): 1}, Vector2i(0, 1))
	e.move_player(Vector2i(1, 0))  # to (1,1)
	assert_false(e.move_player(Vector2i(1, 0)), "cannot push box into a wall — move is a no-op")
	assert_eq(e.player_plane_pos, Vector2i(1, 1), "player did not advance")
	assert_true(Vector2i(2, 1) in e.box_positions()[0], "box did not move")


func test_cannot_walk_through_box_without_pushing_room():
	# Box at (2,1), wall behind at (3,1). The player is blocked at (1,1).
	var e := _engine({Vector2i(2, 1): _box(), Vector2i(3, 1): 1}, Vector2i(1, 1))
	assert_false(e.move_player(Vector2i(1, 0)), "box + wall behind blocks the player")


func test_push_is_undoable():
	var e := _engine({Vector2i(2, 1): _box()}, Vector2i(1, 1))
	e.move_player(Vector2i(1, 0))  # push box (2,1)->(3,1), player ->(2,1)
	assert_true(Vector2i(3, 1) in e.box_positions()[0], "box pushed")
	assert_true(e.undo_step(), "undo the push")
	assert_eq(e.player_plane_pos, Vector2i(1, 1), "player restored")
	assert_true(Vector2i(2, 1) in e.box_positions()[0], "box restored to its cell")


func test_box_rides_a_fold():
	# A box on the B-flap slides inward with the fold, like any tile.
	var e := _engine({Vector2i(5, 1): _box()}, Vector2i(0, 1), Vector2i(10, 3))
	assert_true(e.apply_fold(Vector2i(2, 1), Vector2i(4, 1)), "fold applies")
	assert_true(Vector2i(4, 1) in e.box_positions()[0],
		"box rode the fold from (5,1) to (4,1)")
