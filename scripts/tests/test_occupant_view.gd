## Live-view wiring tests (F6): boxes and split-off player bodies render as overlay
## markers, and engine-authoritative movement (request_move) drives them. Verifies the
## FoldController view layer without needing a display or keyboard input.

extends GutTest


func _setup(box_cells: Array, start := Vector2i(0, 1), grid := Vector2i(6, 3)) -> Dictionary:
	var gm := GridManager.new()
	gm.grid_size = grid
	gm.cell_size = 64.0
	gm.create_grid()
	add_child_autofree(gm)
	for c in box_cells:
		gm.get_cell(c).tile_data = {"occupant": "box"}
	var fc := FoldController.new()
	add_child_autofree(fc)
	fc.initialize(gm)
	var player := Player.new()
	player.initialize(gm, start)
	add_child_autofree(player)
	fc.set_player(player)
	return {"gm": gm, "fc": fc, "player": player}


func test_box_renders_an_overlay_marker():
	# Overlays now include the player's own footprint polygon + the box polygon.
	var s := _setup([Vector2i(2, 1)])
	assert_gte(s.fc._occupant_overlays.size(), 1, "box (and player) footprints rendered at load")
	assert_eq(s.fc.engine.occupant_footprints(StepReplay.KIND_BOX).size(), 1, "one box occupant")


func test_request_move_pushes_box_and_updates_view():
	var s := _setup([Vector2i(2, 1)])
	var fc = s.fc
	assert_true(fc.request_move(Vector2i(1, 0)), "step toward the box")
	assert_true(fc.request_move(Vector2i(1, 0)), "push the box")
	assert_eq(fc.engine.player_plane_pos, Vector2i(2, 1), "player advanced into the box's cell")
	assert_true(Vector2i(3, 1) in fc.engine.box_positions()[0], "engine pushed the box")
	assert_gte(fc._occupant_overlays.size(), 1, "footprints still rendered after the push")


func test_engine_authoritative_move_is_routed_through_controller():
	# The player node delegates to the controller when a mover is set (live game).
	var s := _setup([])
	assert_eq(s.player.mover, s.fc, "player movement is engine-authoritative in the live view")
	assert_true(s.player.attempt_move(Vector2i(1, 0)), "attempt_move routes through the engine")
	assert_eq(s.fc.engine.player_plane_pos, Vector2i(1, 1), "engine advanced the primary body")


func test_blocked_push_does_not_move_player_in_view():
	# Box with a wall behind it: the player cannot advance.
	var s := _setup([Vector2i(2, 1)])
	s.gm.get_cell(Vector2i(3, 1)).set_cell_type(1)  # wall behind the box
	s.fc.initialize(s.gm)                            # rebuild base with the wall
	s.fc.set_player(s.player)
	s.player.set_grid_position(Vector2i(1, 1))
	s.fc.engine.set_player_start(Vector2i(1, 1))
	assert_false(s.fc.request_move(Vector2i(1, 0)), "cannot push box into wall")
	assert_eq(s.fc.engine.player_plane_pos, Vector2i(1, 1), "player stayed put")
