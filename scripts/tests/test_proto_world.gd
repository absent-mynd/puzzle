extends GutTest

## Integration tests for the gravity-prototype scene (ProtoWorld): exact
## base-frame riding through fold/unfold, pinch-into-subspace (applied for
## real), folding inside a subspace with persistence on exit, glue-crossing
## exit blocking, seam-aimed unfolding, and anchor transport. Runs the real
## scene with animation disabled; assertions are synchronous.

const SCENE := "res://scenes/prototype/FoldPrototype.tscn"
const CS := 64.0

var world


func before_each() -> void:
	world = load(SCENE).instantiate()
	add_child_autofree(world)
	world.anim_enabled = false


func _pinch_over_pit() -> void:
	# Stand mid-air over the pit (air tiles), fold across: player is swallowed.
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))


func test_player_rides_a_side_flap_and_unfold_returns() -> void:
	var start: Vector2 = world.player.global_position
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_eq(world.folds.size(), 1, "Fold applied")
	assert_eq(world.mode, world.Mode.WORLD, "Riding a flap stays in the world")
	assert_almost_eq(world.player.global_position.x, start.x + 4 * CS, 130.0,
		"A-side rides shift_a (4 cells right, +/- depenetration slack)")

	world.pop_fold()
	assert_eq(world.folds.size(), 0, "Unfold removes the fold")
	assert_almost_eq(world.player.global_position.x, start.x, 130.0,
		"Unfold carries the player back exactly")


func test_pinch_applies_fold_for_real_and_exit_restores() -> void:
	_pinch_over_pit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Player in the strip is folded IN")
	assert_eq(world.folds.size(), 1, "The pinch fold IS applied to the world")
	assert_gt(world.sub_geo.get_child_count(), 0, "Subspace geometry exists")
	assert_false(world.world_geo.visible, "Outside world is hidden")

	world.player.teleport(Vector2(15.5 * CS, 12.5 * CS), false)
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exit returns to the world")
	assert_eq(world.folds.size(), 0, "Exit unfolds the outer fold")
	assert_true(world.world_geo.visible, "World visible again")
	assert_almost_eq(world.player.global_position.x, 15.5 * CS, 130.0,
		"Moving inside the fold moved you in the world")


func test_two_slot_placement_then_commit_pinches() -> void:
	# Player spawns in cell (4,12); reach is the adjacent cell, facing right.
	world.place_pending(0, Vector2i(1, 0))
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Q pins anchor 1 on the aimed cell")
	world.place_pending(0, Vector2i(1, 0))
	assert_eq(world.pending_cell(0), null, "Re-pinning the same spot clears the slot")

	world.place_pending(0, Vector2i(1, 0))          # (5,12) again
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.place_pending(1, Vector2i(1, 0))          # (9,12)
	assert_eq(world.pending_cell(1), Vector2i(9, 12), "E pins anchor 2 independently")
	assert_eq(world.folds.size(), 0, "Placement alone never commits")

	world.commit_or_unfold(Vector2i(0, -1))         # aim up: no seam there
	assert_eq(world.mode, world.Mode.SUBSPACE,
		"F with the player inside the band folds them in")
	assert_eq(world.pending_a, null, "Pendings clear on commit")


func test_commit_requires_both_anchors_and_min_gap() -> void:
	world.commit_or_unfold(Vector2i(1, 0))
	assert_eq(world.folds.size(), 0, "No anchors pinned: nothing commits")

	world.place_pending(0, Vector2i(1, 0))          # (5,12)
	world.place_pending(1, Vector2i(0, 1))          # (4,13): dist sqrt(2)
	world.commit_or_unfold(Vector2i(0, -1))
	assert_eq(world.folds.size(), 0, "Too-close pair is rejected at commit")
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Pendings kept for adjustment")


func test_interact_aimed_at_seam_unfolds_that_fold() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))  # seam anchor at (24,12)
	assert_eq(world.folds.size(), 1, "Fold active")
	world.player.teleport(Vector2(23.5 * CS, 12.5 * CS), false)
	world.commit_or_unfold(Vector2i(1, 0))          # aiming at the seam diamond
	assert_eq(world.folds.size(), 0, "F aimed at the seam anchor unfolds it")


func test_unfold_blocked_by_newer_crossing_fold() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(24, 12))  # X: vertical seam at x=22.5c
	world.do_fold(Vector2i(30, 8), Vector2i(30, 11))   # Y: horizontal band, crosses X's seam
	assert_eq(world.folds.size(), 2, "Both folds applied")
	assert_false(world.can_unfold_fold(world.folds[0]), "Newer crossing fold blocks X")

	world.unfold_level_fold(world.folds[0])
	assert_eq(world.folds.size(), 2, "Blocked unfold changes nothing")

	world.unfold_level_fold(world.folds[1])            # newest first
	assert_eq(world.folds.size(), 1, "Y unfolds fine")
	world.unfold_level_fold(world.folds[0])
	assert_eq(world.folds.size(), 0, "X unfolds once nothing newer crosses it")


func test_off_axis_anchor_pair_makes_a_diagonal_fold() -> void:
	world.place_pending(0, Vector2i(1, 0))          # (5,12)
	world.player.teleport(Vector2(7.5 * CS, 10.5 * CS), false)
	world.place_pending(1, Vector2i(1, 0))          # (8,10): off-axis, dist ~3.6
	world.commit_or_unfold(Vector2i(0, -1))
	assert_eq(world.mode, world.Mode.SUBSPACE, "Off-axis pinch folds the player in")
	assert_eq(world.sub_fold.orientation, "diagonal", "The committed fold is diagonal")


func test_interior_fold_rides_player_and_persists_on_exit() -> void:
	_pinch_over_pit()
	world.player.teleport(Vector2(11.2 * CS, 12.5 * CS), false)
	# Interior fold PARALLEL to the glue (vertical creases, like the outer's).
	var ok: bool = world.do_sub_fold(Vector2i(12, 8), Vector2i(15, 8))
	assert_true(ok, "Interior fold commits")
	assert_eq(world.level_folds().size(), 1, "Interior fold recorded")
	assert_almost_eq(world.player.global_position.x, 13.2 * CS, 130.0,
		"Player rides the interior A-flap inward")

	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Parallel interior fold does not block exit")
	assert_eq(world.folds.size(), 1, "Interior fold PERSISTS as a world fold")
	assert_eq(world.folds[0].anchor1, Vector2i(12, 8), "It is the interior fold")
	assert_almost_eq(world.player.global_position.x, 13.2 * CS, 130.0,
		"Player emerges exactly where the interior showed them")


func test_exit_blocked_by_glue_crossing_interior_fold() -> void:
	_pinch_over_pit()
	# Interior fold whose band CROSSES the glue (horizontal band in a
	# vertical-band subspace): the outer seam is no longer the newest fold
	# affecting itself, so the exit locks until the inner fold is unfolded.
	var ok: bool = world.do_sub_fold(Vector2i(12, 8), Vector2i(12, 11))
	assert_true(ok, "Crossing interior fold commits")
	world.try_exit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Exit is blocked by the crossing fold")
	assert_eq(world.folds.size(), 1, "Outer fold still applied")

	world.unfold_level_fold(world.level_folds()[0])
	assert_eq(world.level_folds().size(), 0, "Inner fold unfolded from inside")
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exit works once nothing crosses the glue")
	assert_eq(world.folds.size(), 0, "Outer fold gone, no interior folds remained")


func test_pending_anchors_survive_subspace_exit() -> void:
	_pinch_over_pit()
	world.place_pending(0, Vector2i(1, 0))          # pinned INSIDE the fold, cell (14,12)
	assert_eq(world.pending_cell(0), Vector2i(14, 12), "Anchor pinned inside the subspace")
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exited")
	assert_eq(world.pending_cell(0), Vector2i(14, 12),
		"The anchor survived the unfold and landed where the strip content did")


func test_subspace_wrap_teleports_across_the_glue() -> void:
	_pinch_over_pit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Pinched in")
	# Band along x is (10.5, 18.5) cells. Step past the far crease and wrap.
	world.player.teleport(Vector2(18.9 * CS, 12.5 * CS), false)
	world._subspace_wrap_and_turnback()
	assert_almost_eq(world.player.global_position.x, (18.9 - 8.0) * CS, 0.01,
		"Crossing the glue wraps one band width back")
	assert_eq(world.mode, world.Mode.SUBSPACE, "Wrap does not eject")


func test_outside_unfold_splices_interiors() -> void:
	# Rule 4: unfolding a fold from the outside carries its interior folds
	# into the level at its index.
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	var x: Fold = world.folds[0]
	var inner := Fold.create(500, Vector2i(22, 3), Vector2i(25, 3), CS)
	var arr: Array[Fold] = [inner]
	world.interiors[x.fold_id] = arr
	world.unfold_level_fold(x)
	assert_eq(world.folds.size(), 1, "Interior spliced into the world on outside unfold")
	assert_eq(world.folds[0].fold_id, 500, "The spliced fold is the interior one")


func test_door_traversal_between_regions() -> void:
	# W2 (west, cell 42,13) pairs with E2 (east). East's shipped pre-fold has
	# ridden E2's tile 3 cells right, so the door point sits at (5.5c, 9.5c).
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Traversed to the east region")
	assert_eq(world.mode, world.Mode.WORLD, "E2 is in normal space")
	assert_almost_eq(world.player.global_position.x, 5.5 * CS, 130.0,
		"Arrived at E2's point, which rode the shipped fold")


func test_door_into_prefolded_subspace_and_back() -> void:
	# W1's partner E1 was excised by east's shipped fold: the doorway leads
	# INSIDE that fold's subspace.
	world.player.teleport(Vector2(1.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "In the east region")
	assert_eq(world.mode, world.Mode.SUBSPACE, "...inside the shipped fold")
	assert_eq(world.sub_fold.anchor1, Vector2i(10, 6), "It is the authored pre-fold")
	assert_almost_eq(world.player.global_position.x, 13.5 * CS, 130.0,
		"Standing at E1's point inside the strip")

	# Step off the door (unlatch), then walk back through it: out to W1,
	# leaving the fold folded (door exit does not unfold).
	world.player.teleport(Vector2(11.5 * CS, 9.5 * CS), false)
	world._check_doors()
	world.player.teleport(Vector2(13.5 * CS, 9.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "west", "Back in the west region")
	assert_eq(world.mode, world.Mode.WORLD, "In normal space")
	assert_eq(world.regions["east"]["folds"].size(), 1,
		"Door exit left the east fold folded")
	assert_almost_eq(world.player.global_position.x, 1.5 * CS, 130.0,
		"Arrived at W1")


func test_split_door_point_is_dormant() -> void:
	# Cut E2's tile exactly through its center: the door point resolves
	# nowhere, so its partner refuses traversal.
	var east: Dictionary = world.regions["east"]
	var cut := Fold.create(999, Vector2i(2, 9), Vector2i(2, 12), CS)
	east["folds"].append(cut)
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "west", "Dormant far side refuses traversal")
	assert_eq(world.mode, world.Mode.WORLD, "Player stayed put")


func test_pending_anchor_inert_across_regions() -> void:
	world.place_pending(0, Vector2i(1, 0))
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Anchor pinned in west")
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Traversed")
	assert_eq(world.pending_cell(0), null, "West anchor is inert in east")
	assert_true(world.pending_a != null, "...but still pinned, waiting")


func test_no_hud_control_swallows_mouse_input() -> void:
	# Anchor placement relies on _unhandled_input receiving input; any Control
	# with MOUSE_FILTER_STOP covering the screen consumes mouse events first
	# (this bit us: the background ColorRect blocked all anchor clicks).
	var stack: Array = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			assert_ne(node.mouse_filter, Control.MOUSE_FILTER_STOP,
				"%s must not stop mouse events" % node.get_path())
		stack.append_array(node.get_children())
