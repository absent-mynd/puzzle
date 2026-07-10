## FoldController integration tests (Stage 5)
##
## Drives the node-level adapter over the real GridManager + Player: fold -> view
## refresh -> player ride -> unfold, all through the public surface the game uses.
## Proves the new engine reproduces gameplay outcomes end-to-end (not just headless).

extends GutTest

const T_GOAL := 3
const T_WALL := 1


func _setup(start := Vector2i(0, 0), types := {}) -> Dictionary:
	var gm := GridManager.new()
	gm.grid_size = Vector2i(10, 10)
	gm.cell_size = 64.0
	gm.create_grid()
	add_child_autofree(gm)
	for pos in types:
		gm.get_cell(pos).set_cell_type(types[pos])

	var player := Player.new()
	player.initialize(gm, start)
	add_child_autofree(player)

	var fc := FoldController.new()
	add_child_autofree(fc)
	fc.initialize(gm)
	fc.set_player(player)
	fc.seed_history()
	return {"gm": gm, "player": player, "fc": fc}


func test_fold_compresses_grid_via_view():
	var s := _setup()
	var ok = await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	assert_true(ok, "fold succeeds")
	# Meet-in-the-middle: occupied cols 2..8; 0,1,9 gone.
	for x in range(2, 9):
		assert_not_null(s.gm.get_cell(Vector2i(x, 5)), "col %d present" % x)
	for x in [0, 1, 9]:
		assert_null(s.gm.get_cell(Vector2i(x, 5)), "col %d gone" % x)


func test_player_rides_through_controller():
	var s := _setup(Vector2i(8, 5))
	var ok = await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	assert_true(ok, "fold succeeds")
	assert_eq(s.player.grid_position, Vector2i(7, 5), "player (B-side) rode from col 8 to col 7")
	# World position matches the (existing) cell center.
	var cell = s.gm.get_cell(Vector2i(7, 5))
	assert_almost_eq(s.player.global_position.distance_to(s.gm.to_global(cell.get_center())), 0.0, 0.5,
		"player world position tracks its cell")


func test_fold_through_player_rejected():
	var s := _setup(Vector2i(3, 5))  # between anchors
	var ok = await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	assert_false(ok, "cannot fold through the player")
	assert_eq(s.fc.fold_history.size(), 0, "no fold recorded")


func test_unfold_restores_via_controller():
	var s := _setup(Vector2i(0, 0), {Vector2i(7, 2): T_WALL})
	var before: int = s.gm.cells.size()
	var ok = await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	assert_true(ok, "fold succeeds")
	assert_lt(s.gm.cells.size(), before, "grid compressed")
	assert_true(s.fc.unfold_seam(0), "unfold succeeds")
	assert_eq(s.gm.cells.size(), before, "grid restored to full size")
	# Wall is back at its original spot.
	assert_eq(s.gm.get_cell(Vector2i(7, 2)).get_dominant_type(), T_WALL, "wall restored")


func test_goal_between_anchors_disappears_and_returns():
	var s := _setup(Vector2i(0, 0), {Vector2i(3, 5): T_GOAL})
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	var goal_seen := false
	for pos in s.gm.cells.keys():
		if is_instance_valid(s.gm.cells[pos]) and s.gm.cells[pos].has_cell_type(T_GOAL):
			goal_seen = true
	assert_false(goal_seen, "goal excised while folded")
	s.fc.unfold_seam(0)
	assert_eq(s.gm.get_cell(Vector2i(3, 5)).get_dominant_type(), T_GOAL, "goal returns on unfold")


func test_crease_dot_registered_after_fold():
	var s := _setup(Vector2i(0, 0))
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	# The crease dot tracks the meeting column (4,5).
	assert_eq(s.fc.crease_dot_at(Vector2i(4, 5)), 0, "crease dot at meeting column for fold 0")
	assert_eq(s.fc.crease_dot_at(Vector2i(9, 9)), -1, "no crease dot elsewhere")


## --- Fold animation vertex map (polygon interpolation geometry) ----------------

func test_fold_vertex_map_endpoints():
	var s := _setup()
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), 64.0)
	var cs := 64.0
	var c1 := f.crease_point1
	var normal := f.crease_normal
	var gap := f.gap_distance()
	var shift_a := f.shift_a_px(cs)
	var shift_b := f.shift_b_px(cs)
	var m: float = shift_a.dot(normal)

	# t=0 is the identity map.
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(600, 0), Vector2(256, 0)])
	var at0: PackedVector2Array = s.fc._fold_map_polygon(poly, 0.0, c1, normal, gap, m, shift_a, shift_b)
	for i in range(poly.size()):
		assert_almost_eq(at0[i].distance_to(poly[i]), 0.0, 0.01, "t=0 identity for vertex %d" % i)

	# t=1: A-side + shift_a, B-side + shift_b, between collapses onto the meeting line.
	var at1: PackedVector2Array = s.fc._fold_map_polygon(poly, 1.0, c1, normal, gap, m, shift_a, shift_b)
	assert_almost_eq(at1[0].distance_to(Vector2(0, 0) + shift_a), 0.0, 0.01, "A-side vertex translates by shift_a")
	assert_almost_eq(at1[1].distance_to(Vector2(600, 0) + shift_b), 0.0, 0.01, "B-side vertex translates by shift_b")
	# Between vertex ends on the meeting line: normal-distance from crease1 == m.
	var between_d: float = (at1[2] - c1).dot(normal)
	assert_almost_eq(between_d, m, 0.01, "between vertex collapses onto the meeting line")


## --- Crease-dot position is derived (out-of-order collinear unfold) --------------

func test_collinear_seams_dot_correct_after_out_of_order_unfold():
	# Two collinear folds on the same crease line -> their crease dots coincide.
	var s := _setup()
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)  # fold 0
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)  # fold 1 (collinear)

	var dot1_before: Vector2i = s.fc._crease_plane_pos(1)
	# Unfold the OLDER fold first (opposite of creation order).
	assert_true(s.fc.unfold_seam(0), "older collinear fold unfolds first")

	# Fold 1's dot must still sit on its seam (meeting column 4), not drift off.
	var dot1_after: Vector2i = s.fc._crease_plane_pos(1)
	assert_eq(dot1_after, Vector2i(4, 5), "remaining seam's dot stays on its meeting line")
	assert_eq(s.fc.crease_dot_at(Vector2i(4, 5)), 1, "crease_dot_at finds fold 1 at its seam")


## --- Unfold-blocking modes (Axis E) ----------------------------------------------

func test_stacked_fold_buries_earlier_seam_until_unburied():
	# Stacking a collinear fold excises the earlier seam -> it is hidden (buried) and NOT
	# unfoldable while the burying fold remains. Hiding is order-independent: it stays
	# hidden until the fold that buried it is removed, then it reappears.
	var s := _setup()
	s.fc.unfold_blocking_mode = 0  # ALLOW_ANY
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)  # fold 0
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)  # fold 1 buries fold 0's seam

	assert_true(s.fc.has_newer_seam_intersections(1)["valid"], "newest (top) seam is unfoldable")
	assert_false(s.fc.has_newer_seam_intersections(0)["valid"], "buried older seam is hidden")

	assert_true(s.fc.unfold_seam(1), "remove the burying fold")
	assert_true(s.fc.has_newer_seam_intersections(0)["valid"], "older seam reappears once unburied")


func test_block_on_intersection_blocks_a_crossing_fold():
	var s := _setup()
	# Fold 0: horizontal fold -> a vertical seam. Fold 1: vertical fold near the top that
	# does NOT bury fold 0's seam but whose (horizontal) seam crosses it.
	await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)  # fold 0
	await s.fc.execute_fold(Vector2i(4, 0), Vector2i(4, 2), false)  # fold 1 (crosses)
	assert_true(s.fc.has_newer_seam_intersections(0)["valid"], "not blocked while seam not hidden")

	# The two seams cross, so under BLOCK_ON_INTERSECTION the older fold is blocked.
	s.fc.unfold_blocking_mode = 1
	assert_false(s.fc.has_newer_seam_intersections(0)["valid"],
		"a newer crossing seam blocks the older fold under BLOCK_ON_INTERSECTION")
	# ALLOW_ANY ignores the crossing (only visibility + player-safety matter).
	s.fc.unfold_blocking_mode = 0
	assert_true(s.fc.has_newer_seam_intersections(0)["valid"], "ALLOW_ANY permits it")


func test_validate_rejects_same_cell_and_missing():
	var s := _setup()
	assert_false(s.fc.validate_fold(Vector2i(3, 3), Vector2i(3, 3)).valid, "same cell invalid")
	assert_true(s.fc.validate_fold(Vector2i(1, 1), Vector2i(4, 1)).valid, "distinct occupied valid")


## --- Player heading (facing) as undoable state -------------------------------

func test_turn_without_moving_is_undoable():
	# At (0,0), pressing up is a blocked move (off-grid) but still changes heading.
	var s := _setup(Vector2i(0, 0))
	assert_eq(s.player.facing, Vector2i(1, 0), "default faces right")
	s.player.attempt_move(Vector2i(0, -1))
	assert_eq(s.player.facing, Vector2i(0, -1), "heading changed on blocked bump")
	assert_true(s.fc.can_undo(), "a heading-only change is recorded as an input")
	assert_true(s.fc.undo(), "undo the turn")
	assert_eq(s.player.facing, Vector2i(1, 0), "undo restores the prior heading")


func test_repeated_bump_same_direction_records_once():
	var s := _setup(Vector2i(0, 0))
	s.player.attempt_move(Vector2i(0, -1))   # turn up (recorded)
	s.player.attempt_move(Vector2i(0, -1))   # bump up again, no heading change (not recorded)
	assert_true(s.fc.undo(), "one undo")
	assert_eq(s.player.facing, Vector2i(1, 0), "single undo restores original heading")
	assert_false(s.fc.can_undo(), "no extra no-op input was recorded")


func test_facing_preserved_and_restored_across_fold_undo():
	var s := _setup(Vector2i(0, 0))
	s.player.attempt_move(Vector2i(0, -1))   # face up (blocked), recorded
	var ok = await s.fc.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)
	assert_true(ok, "fold applies")
	s.fc.commit_input()   # mimics MainScene._finalize_fold_success recording the fold
	assert_eq(s.player.facing, Vector2i(0, -1), "fold does not change heading")
	assert_true(s.fc.undo(), "undo the fold")
	assert_eq(s.player.facing, Vector2i(0, -1), "heading preserved after undoing a fold")
	assert_true(s.fc.undo(), "undo the turn")
	assert_eq(s.player.facing, Vector2i(1, 0), "heading restored to original")
