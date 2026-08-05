extends GutTest

## Integration tests for the gravity-prototype scene (FoldWorld): exact
## base-frame riding through fold/unfold, pinch-into-subspace (applied for
## real), folding inside a subspace with persistence on exit, glue-crossing
## exit blocking, the one-key tap/hold verb, anchor transport, and the carried
## anchor economy. Runs the real scene with animation disabled; assertions are
## synchronous.

const SCENE := "res://scenes/world/World.tscn"
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

	world.unfold_level_fold(world.folds[0])
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


func test_one_key_places_both_hands_and_the_fuse_does_the_rest() -> void:
	# Player spawns in cell (4,12); reach is the adjacent cell, facing right.
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "First tap puts a hand on the aimed cell")
	assert_eq(world.pending_cell(1), null, "...and only the one")

	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.pending_cell(1), Vector2i(9, 12), "Second tap puts the other one down")
	assert_eq(world.folds.size(), 0, "Placing does not fold")
	assert_true(world.fuse_running(), "...it lights the fuse")

	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.mode, world.Mode.SUBSPACE,
		"The fuse folds it, and the player inside the band is folded in")
	assert_eq(world.pending_a, null, "The hands went from the anchors into the fold")


func test_a_too_close_second_anchor_is_refused_at_placement() -> void:
	# With one key the next tap IS the commit, so an un-committable pair has to be
	# refused while the player can still see which anchor caused it.
	world.tap_action(Vector2i(1, 0))                # (5,12)
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Anchor 1 pinned")

	world.tap_action(Vector2i(0, 1))                # (4,13): dist sqrt(2)
	assert_eq(world.pending_cell(1), null, "The too-close second anchor never lands")
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Anchor 1 is kept for adjustment")
	assert_eq(world.folds.size(), 0, "And nothing commits")


func test_holding_at_a_seam_anchor_unfolds_that_fold() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))  # seam anchor at (24,12)
	assert_eq(world.folds.size(), 1, "Fold active")
	world.player.teleport(Vector2(23.5 * CS, 12.5 * CS), false)
	world.hands[0] = HandTypes.PLAIN                # as if picked up from a cache

	world.tap_action(Vector2i(1, 0))                # aimed at the seam diamond
	assert_eq(world.folds.size(), 1, "A TAP at a seam does not unfold — tap only ever places")
	assert_eq(world.pending_cell(0), Vector2i(24, 12), "...it put a hand there")
	world.hold_action(Vector2i(1, 0))
	assert_eq(world.pending_cell(0), null,
		"A hold aimed at your own hand takes that one back first")

	# Now carrying that spare, there is only one free slot and the fold wants to
	# give back two — so the seam under the same cell will not come out yet.
	world.hold_action(Vector2i(1, 0))
	assert_eq(world.folds.size(), 1, "Holding a spare leaves no room for the fold's pair")

	world.hands[0] = null                           # as if the spare were placed elsewhere
	world.hold_action(Vector2i(1, 0))
	assert_eq(world.folds.size(), 0, "With hands free, the hold unfolds the seam under the cell")
	assert_eq(world.hands_held(), 2, "...and both of its hands come home")


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


func test_stacked_seams_unfold_the_one_that_can_actually_come_out() -> void:
	# Two folds can meet in the SAME cell — a horizontal pair and a vertical pair
	# whose halves happen to join at one spot. The diamond there is one marker for
	# both, and the older of the two is blocked by the newer crossing its seam. F
	# must act on the fold that can come out, not on the buried one.
	world.player.teleport(Vector2(4.5 * CS, 5.5 * CS), false)   # clear of both bands
	world.do_fold(Vector2i(20, 12), Vector2i(24, 12))           # X: seam cell (22,12)
	world.do_fold(Vector2i(22, 10), Vector2i(22, 14))           # Y: the SAME seam cell
	assert_eq(world.folds.size(), 2, "Both folds applied")
	assert_eq(world.folds[0].meeting_pos, world.folds[1].meeting_pos,
		"Their seams land on one cell — one diamond, two folds")
	assert_false(world.can_unfold_fold(world.folds[0]), "The older one is buried by the newer")
	assert_true(world.can_unfold_fold(world.folds[1]), "The newer one is free to come out")

	world.player.teleport(Vector2(22.5 * CS, 12.5 * CS), false) # stand on the diamond
	assert_eq(world.aimed_fold(Vector2i(1, 0)), world.folds[1],
		"The shared diamond resolves to the fold that can actually come out")
	world.hold_action(Vector2i(1, 0))
	assert_eq(world.folds.size(), 1, "A hold on the shared diamond unfolds something")
	assert_eq(world.folds[0].anchor1, Vector2i(20, 12),
		"...the newest one that can come out; the buried one stays")

	# With only the buried fold left, the same diamond now unfolds it: nothing
	# crosses its seam any more.
	world.player.teleport(Vector2(22.5 * CS, 12.5 * CS), false)
	world.hold_action(Vector2i(1, 0))
	assert_eq(world.folds.size(), 0, "Once nothing crosses it, the older fold unfolds too")


func test_a_shared_seam_cell_draws_one_diamond_that_reads_unblocked() -> void:
	# The marker has to promise what F delivers. Two folds meeting in one cell get
	# ONE diamond, and it reads open because pressing F there does unfold something
	# — drawing the buried fold's refusal over the free fold's invitation was the
	# other half of the stacked-seam bug.
	world.player.teleport(Vector2(4.5 * CS, 5.5 * CS), false)
	world.do_fold(Vector2i(20, 12), Vector2i(24, 12))
	world.do_fold(Vector2i(22, 10), Vector2i(22, 14))
	var markers: Dictionary = world.seam_markers()
	assert_eq(markers.size(), 1, "Two folds sharing a meeting cell draw one diamond")
	assert_true(bool(markers[Vector2i(22, 12)]),
		"It reads unblocked, because a hold there unfolds the newer fold")

	world.player.teleport(Vector2(22.5 * CS, 12.5 * CS), false)
	world.hold_action(Vector2i(1, 0))
	assert_eq(world.seam_markers(), {Vector2i(22, 12): true},
		"With one fold left the cell still has its diamond, still open")


func test_off_axis_anchor_pair_makes_a_diagonal_fold() -> void:
	world.tap_action(Vector2i(1, 0))                # (5,12)
	world.player.teleport(Vector2(7.5 * CS, 10.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                # (8,10): off-axis, dist ~3.6
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
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
	world.hands[0] = HandTypes.PLAIN                # as if picked up in there
	world.tap_action(Vector2i(1, 0))                # placed INSIDE the fold, cell (14,12)
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


func test_wrap_moves_the_camera_with_the_body() -> void:
	# The strip repeats with period `gap`, so body and camera must move by the
	# same vector: the frame is then pixel-identical and the seam is invisible.
	# Snapping the camera to the body instead would discard its smoothing lag.
	_pinch_over_pit()
	world.player.teleport(Vector2(18.9 * CS, 12.5 * CS), false)
	var lag: Vector2 = world.player.camera_position() - world.player.global_position
	assert_ne(lag, Vector2.ZERO, "Camera is lagging behind (nothing snapped it here)")

	world._subspace_wrap_and_turnback()
	assert_almost_eq(
		(world.player.camera_position() - world.player.global_position - lag).length(),
		0.0, 0.01, "The wrap preserved the camera's offset from the body exactly")


func test_player_is_drawn_in_every_visible_copy_of_the_strip() -> void:
	_pinch_over_pit()
	assert_eq(world.sub_player_ghosts.size(), 2 * world.sub_copies,
		"One drawn copy of the player per band, minus the one the body is in")

	world.player.teleport(Vector2(15.5 * CS, 12.5 * CS), false)
	world._update_player_ghosts()
	var n: Vector2 = world.sub_fold.crease_normal
	var gap: float = world.sub_fold.gap_distance()
	# Each copy sits at the body's position offset by a whole number of bands.
	for ghost in world.sub_player_ghosts:
		var delta: Vector2 = ghost.global_position - world.player.global_position
		var k: float = delta.dot(n) / gap
		assert_almost_eq(delta.distance_to(n * (k * gap)), 0.0, 0.01,
			"Copy is displaced along the crease normal only")
		assert_almost_eq(k, roundf(k), 0.01,
			"Copy sits a whole number of band widths from the body")
		assert_ne(roundi(k), 0, "...and never on top of it")

	world.try_exit()
	assert_eq(world.sub_player_ghosts.size(), 0, "Copies are gone outside the fold")


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
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Anchor pinned in west")
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Traversed")
	assert_eq(world.pending_cell(0), null, "West anchor is inert in east")
	assert_true(world.pending_a != null, "...but still pinned, waiting")


## Stand in east's normal space, on the surface near door E2.
func _enter_east() -> void:
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Crossed into the east region")
	assert_eq(world.mode, world.Mode.WORLD, "...in normal space")


## Where a base cell of the CURRENT region sits right now, or null if it is folded away.
func _plane_point(cell: Vector2i):
	var tile: BaseTile = world.base.tile_at(cell)
	return BaseFrame.world_point_from_base(
		world.current_pieces, tile.base_id, (Vector2(cell) + Vector2(0.5, 0.5)) * CS)


func test_pinned_pillar_refuses_a_fold_that_spans_it() -> void:
	_enter_east()
	var pin = _plane_point(Vector2i(21, 9))
	assert_not_null(pin, "The pinned pillar stands in normal space")
	var cell := Vector2i((Vector2(pin) / CS).floor())

	var before: int = world.folds.size()
	world.do_fold(cell - Vector2i(2, 0), cell + Vector2i(2, 0))
	assert_eq(world.folds.size(), before,
		"A fold spanning the pinned pillar is refused — you route around, not through")

	world.do_fold(cell + Vector2i(3, 0), cell + Vector2i(6, 0))
	assert_eq(world.folds.size(), before + 1, "A fold clear of the pillar still commits")


func test_pressure_plate_folds_the_wall_away() -> void:
	_enter_east()
	assert_not_null(_plane_point(Vector2i(27, 9)), "The wall stands before the plate is pressed")
	var plate = _plane_point(Vector2i(25, 9))
	assert_not_null(plate, "The plate is reachable in normal space")

	var before: int = world.folds.size()
	world.player.teleport(Vector2(plate), false)
	world._check_triggers()
	assert_eq(world.folds.size(), before + 1, "Standing on the plate fires one fold")
	assert_null(_plane_point(Vector2i(27, 9)), "...which folds the wall away")
	assert_not_null(_plane_point(Vector2i(29, 9)), "The reward behind it survives")
	assert_not_null(_plane_point(Vector2i(21, 9)), "And so does the pinned pillar")


func test_pressure_plate_does_not_re_fire() -> void:
	_enter_east()
	world.player.teleport(Vector2(_plane_point(Vector2i(25, 9))), false)
	world._check_triggers()
	var after_first: int = world.folds.size()

	# Still standing on it: the latch holds.
	world._check_triggers()
	assert_eq(world.folds.size(), after_first, "Standing still does not re-fire the plate")

	# Step off and back on: the channel is already taken, so still nothing.
	world.player.teleport(Vector2(5.5 * CS, 9.5 * CS), false)
	world._check_triggers()
	world.player.teleport(Vector2(_plane_point(Vector2i(25, 9))), false)
	world._check_triggers()
	assert_eq(world.folds.size(), after_first,
		"Re-entering the plate spawns no duplicate for a channel that already folded")


func test_triggered_fold_persists_across_leaving_the_region() -> void:
	_enter_east()
	world.player.teleport(Vector2(_plane_point(Vector2i(25, 9))), false)
	world._check_triggers()
	var east_folds: int = world.regions["east"]["folds"].size()
	assert_gt(east_folds, 1, "The plate's fold joined east's persistent fold list")

	# Door E2 RODE the triggered fold with its flap, so it is no longer where it was —
	# resolve its current point rather than assuming.
	var e2 = _plane_point(Vector2i(2, 9))
	assert_not_null(e2, "E2 survived the triggered fold")
	assert_ne(e2, Vector2(2.5 * CS, 9.5 * CS), "...and moved with the flap that carried it")

	# Arriving through a door latches it; stepping off is what clears the latch (in play
	# that is just the next _physics_process tick away from the doorway).
	world._check_doors()
	world.player.teleport(Vector2(e2), false)
	world._check_doors()
	assert_eq(world.region_id, "west", "Back in west")
	assert_eq(world.regions["east"]["folds"].size(), east_folds,
		"East keeps the triggered fold while you are away")


# ---------------------------------------------------------------------------
# Hands: two slots, typed, conserved
# ---------------------------------------------------------------------------
# A hand is an object with a kind. You hold two; a standing fold holds the two you
# pinned it with; unfolding gives back those same two. Every path below has to
# conserve — the only thing that may raise the total is picking one up.

func _total() -> int:
	return world.hands_total()


func test_you_start_with_a_full_pair_and_nothing_else() -> void:
	assert_eq(world.hands.size(), AnchorStock.SLOTS, "One entry per slot")
	assert_eq(world.hands_held(), 2, "Both slots full at the start")
	assert_eq(world.hands_in_folds(), 0, "Nothing committed yet")
	assert_eq(_total(), 2, "Two hands exist")


func test_placing_a_hand_takes_it_out_of_its_slot() -> void:
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "The tap put a hand down")
	assert_eq(world.hands_held(), 1, "...which left your slots")
	assert_eq(world.hands_free_slots(), 1, "...freeing the slot it came from")
	assert_eq(_total(), 2, "and nothing was created or destroyed")


func test_holding_takes_a_placed_hand_back() -> void:
	world.tap_action(Vector2i(1, 0))
	world.hold_action(Vector2i(1, 0))
	assert_eq(world.pending_cell(0), null, "Holding on your own hand pulls it back")
	assert_eq(world.hands_held(), 2, "...into a slot")
	assert_eq(_total(), 2, "Conserved")


func test_a_second_hand_lights_the_fuse_and_it_folds_itself() -> void:
	world.tap_action(Vector2i(1, 0))                        # (5,12)
	assert_false(world.fuse_running(), "One hand down is not a fold")

	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # (9,12)
	assert_true(world.fuse_running(), "The second hand lights the fuse")
	assert_eq(world.folds.size(), 0, "...which has not gone off yet")
	assert_eq(world.hands_held(), 0, "Both hands are down")

	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.mode, world.Mode.SUBSPACE,
		"The fuse committed the fold with nobody pressing anything")
	assert_false(world.fuse_running(), "And the fuse is spent")
	assert_eq(_total(), 2, "Still two hands, now inside the fold")


func test_the_fuse_ticks_down_rather_than_firing_at_once() -> void:
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))

	world._tick_fuse(HandTypes.BASE_FUSE * 0.5)
	assert_eq(world.folds.size(), 0, "Half way through, nothing has folded")
	assert_almost_eq(world.fuse_progress(), 0.5, 0.02, "...and the pulse knows how far along it is")
	world._tick_fuse(HandTypes.BASE_FUSE * 0.5 + 0.01)
	assert_eq(world.folds.size(), 1, "It fires when the fuse runs out, not before")


func test_pulling_a_hand_back_defuses_the_pair() -> void:
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	assert_true(world.fuse_running(), "Lit")

	world.hold_action(Vector2i(1, 0))
	assert_false(world.fuse_running(), "Taking a hand back puts it out")
	assert_eq(world.folds.size(), 0, "Nothing folded")
	world._tick_fuse(10.0)
	assert_eq(world.folds.size(), 0, "...and it stays out")


func test_the_fuse_waits_while_an_anchor_is_out_of_frame() -> void:
	# Walk through a door mid-count and the fold should wait for you, not fire
	# somewhere you cannot see or fail on an anchor that is merely elsewhere.
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Left the region with a fuse burning")

	world._tick_fuse(10.0)
	assert_eq(world.folds.size(), 1, "East's own pre-fold only — the pair did not fire here")
	assert_true(world.fuse_running(), "The fuse is paused, not cancelled")


func test_a_standing_fold_holds_the_hands_and_unfolding_returns_them() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_eq(world.folds[0].held_hands.size(), 2, "The fold took both hands")
	assert_eq(world.hands_held(), 0, "...so you are holding none")
	assert_eq(_total(), 2, "Conserved")

	world.unfold_level_fold(world.folds[0])
	assert_eq(world.hands_held(), 2, "Unfolding gave them back")
	assert_eq(_total(), 2, "Still conserved")


func test_a_fold_gives_back_the_same_kinds_it_took() -> void:
	# The reason kinds are stored on the fold rather than counted: a mixed pair
	# must come back mixed.
	world.hands[0] = HandTypes.SWIFT
	world.hands[1] = HandTypes.PATIENT
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_eq(world.folds[0].held_hands, [HandTypes.SWIFT, HandTypes.PATIENT] as Array[int],
		"The fold is holding a swift and a patient hand")

	world.unfold_level_fold(world.folds[0])
	var back: Array = world.hands.duplicate()
	back.sort()
	assert_eq(back, [HandTypes.SWIFT, HandTypes.PATIENT], "Both kinds came home")


func test_with_no_hands_a_tap_places_nothing() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_eq(world.hands_held(), 0, "The fold has both hands")
	assert_false(world.can_place_hand(), "Nothing to place")
	assert_eq(world.next_hand_type(), -1, "...and the aim ring knows it")

	world.tap_action(Vector2i(1, 0))
	assert_eq(world.pending_cell(0), null, "A tap with empty hands puts nothing down")


func test_a_refused_fold_does_not_eat_your_hands() -> void:
	# A fold rejected for its span must cost nothing: the hands never went in.
	_enter_east()
	var pin = _plane_point(Vector2i(21, 9))
	var cell := Vector2i((Vector2(pin) / CS).floor())
	var before: int = world.folds.size()

	world.do_fold(cell - Vector2i(2, 0), cell + Vector2i(2, 0))
	assert_eq(world.folds.size(), before, "The pinned pillar refused the fold")
	assert_eq(world.hands_held(), 2, "...and you still have both hands")


func test_world_made_folds_hold_none_of_your_hands() -> void:
	# Authored pre-folds and trigger folds are anchored by the world, not by you.
	assert_eq(world.regions["east"]["folds"][0].held_hands.size(), 0,
		"East's shipped pre-fold holds none of the player's hands")
	assert_eq(world.hands_held(), 2, "So you start with both")

	_enter_east()
	world.player.teleport(Vector2(_plane_point(Vector2i(25, 9))), false)
	world._check_triggers()
	assert_gt(world.folds.size(), 1, "The plate fired its fold")
	assert_eq(world.hands_held(), 2, "A trigger fold costs you nothing either")


func test_unfolding_is_refused_when_there_is_no_room_for_the_hands() -> void:
	# A fold gives back both at once. Carrying a spare picked-up hand leaves nowhere
	# for the second one to go, so the fold stays folded until you put one down.
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_eq(world.hands_held(), 0, "Both hands committed")
	world.hands[0] = HandTypes.SWIFT                        # as if picked up from a cache
	assert_eq(world.hands_free_slots(), 1, "One slot free, two hands coming back")

	world.unfold_level_fold(world.folds[0])
	assert_eq(world.folds.size(), 1, "Refused — there is nowhere to put them")

	world.tap_action(Vector2i(1, 0))                        # put the spare down
	assert_eq(world.hands_free_slots(), 2, "Now there is room")
	world.unfold_level_fold(world.folds[0])
	assert_eq(world.folds.size(), 0, "...and the fold comes apart")
	assert_eq(world.hands_held(), 2, "Both hands are back")


func test_an_interior_fold_holds_hands_across_the_subspace_boundary() -> void:
	_pinch_over_pit()
	assert_eq(world.hands_held(), 0, "The pinch fold took both hands")

	world.hands[0] = HandTypes.SWIFT
	world.hands[1] = HandTypes.SWIFT
	world.player.teleport(Vector2(11.2 * CS, 12.5 * CS), false)
	assert_true(world.do_sub_fold(Vector2i(12, 8), Vector2i(15, 8)), "Interior fold commits")
	assert_eq(world.hands_held(), 0, "It took the pair too")
	assert_eq(_total(), 4, "Four hands exist: two picked up, all four committed")

	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exited")
	assert_eq(world.hands_held(), 2, "The outer fold returned its pair")
	assert_eq(world.hands_in_folds(), 2,
		"The interior fold persisted into the world, still holding its own")


# ---------------------------------------------------------------------------
# Hand caches
# ---------------------------------------------------------------------------

func test_a_cache_gives_one_hand_into_one_free_slot() -> void:
	# Full hands walk straight over a cache: it is the second half of a fold you
	# have already started, not a stockpile you raid on the way past.
	var cache = _plane_point(Vector2i(24, 6))
	assert_not_null(cache, "The pillar-top cache stands in normal space")
	world.player.teleport(Vector2(cache), false)
	world._check_caches()
	assert_eq(world.hands_held(), 2, "With both hands full it gives nothing")
	assert_eq(_total(), 2, "...and nothing was created")

	world.tap_action(Vector2i(1, 0))                        # put one down to free a slot
	assert_eq(world.hands_held(), 1, "One slot free now")
	world.player.teleport(Vector2(cache), false)
	world._check_caches()
	assert_eq(world.hands_held(), 2, "The cache filled it")
	assert_eq(_total(), 3, "A third hand now exists — picking up is the only thing that adds one")


func test_a_cache_gives_the_kind_its_tile_names() -> void:
	world.tap_action(Vector2i(1, 0))                        # free a slot
	world.player.teleport(Vector2(_plane_point(Vector2i(24, 6))), false)
	world._check_caches()
	var got: Array = []
	for h in world.hands:
		if h != null:
			got.append(h)
	assert_true(got.has(HandTypes.SWIFT),
		"The pillar-top cache is authored swift, and a swift hand is what it gave")


func test_a_spent_cache_gives_nothing_twice() -> void:
	world.tap_action(Vector2i(1, 0))
	var cache = _plane_point(Vector2i(24, 6))
	world.player.teleport(Vector2(cache), false)
	world._check_caches()
	assert_eq(_total(), 3, "Taken once")

	world.tap_action(Vector2i(1, 0))                        # free the slot again
	world.player.teleport(Vector2(cache), false)
	world._check_caches()
	assert_eq(_total(), 3, "A spent cache is a husk")


func test_mixed_hands_make_a_fold_whose_fuse_is_between_them() -> void:
	# What allowing a mixed pair is FOR: the fold it makes is neither parent's.
	var plain := HandTypes.fuse_for(HandTypes.PLAIN, HandTypes.PLAIN)
	var swift := HandTypes.fuse_for(HandTypes.SWIFT, HandTypes.SWIFT)
	var mixed := HandTypes.fuse_for(HandTypes.PLAIN, HandTypes.SWIFT)
	assert_lt(mixed, plain, "A swift hand hurries a plain pair along")
	assert_gt(mixed, swift, "...but not all the way to a swift pair")


func test_a_cache_folded_away_is_collectable_inside_the_fold() -> void:
	# East's shipped pre-fold excised the cache at (14,9) along with door E1. A cache
	# inside a fold is not lost — the strip is a real place, and taking it in there counts.
	world.tap_action(Vector2i(1, 0))                        # free a slot first
	var before: int = _total()
	world.player.teleport(Vector2(1.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Through W1, inside the shipped fold")

	world.player.teleport(Vector2(14.5 * CS, 9.5 * CS), false)
	world._check_caches()
	assert_eq(_total(), before + 1,
		"The cache the fold swallowed is collectable from inside it")


func test_reset_puts_both_the_world_and_your_hands_back() -> void:
	# Capacity no longer grows, so there is no progression for a reset to
	# confiscate — and hands are exactly what it must restore, or the escape hatch
	# leaves you worse off than you started.
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(_plane_point(Vector2i(24, 6))), false)
	world._check_caches()
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))

	world._reset()
	assert_eq(world.folds.size(), 0, "The world is back to its authored folds")
	assert_eq(world.hands_held(), 2, "You have your starting pair again")
	assert_eq(world.hands_in_folds(), 0, "Nothing is holding anything")
	assert_eq(_total(), 2, "And the caches respawned with the world")


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


# ---------------------------------------------------------------------------
# Pixel rendering & dynamic lights
# ---------------------------------------------------------------------------

func _light_ids() -> Array:
	var ids: Array = []
	for entry in world.lights_here():
		if not ids.has(entry["id"]):
			ids.append(entry["id"])
	ids.sort()
	return ids


func _light_pos(id: String):
	for entry in world.lights_here():
		if entry["id"] == id:
			return Vector2(entry["pos"])
	return null


func test_the_world_draws_through_the_pixel_viewport() -> void:
	assert_not_null(world.pixel_view, "there is a low-resolution render target")
	# Sized for the CURRENT zoom, not fixed: the frame opens by giving the target
	# more art pixels rather than by moving the lens. See PixelArt.target_size.
	assert_eq(world.pixel_view.size,
		PixelArt.target_size(world.get_viewport_rect().size, world.player.camera_zoom()),
		"sized in art pixels, for the zoom in force")
	# Everything that is part of the WORLD renders inside it; the HUD does not,
	# which is what keeps text legible over chunky tiles.
	for node in [world.world_geo, world.sub_geo, world.player, world.overlay, world.light_rig]:
		assert_eq(node.get_parent(), world.pixel_view,
			"%s draws at art-pixel resolution" % node.name)


func test_opening_the_frame_grows_the_target_and_never_moves_the_lens() -> void:
	# Where the pixel pass and the dynamic camera meet. The lens must NOT move —
	# inside a render target, zoom is what sets the size of an art pixel, so a
	# moving lens would resample the 16px tileset and soften the world. Showing
	# more world is answered with more pixels instead.
	var lens: Vector2 = world.player._cam.zoom
	var small: Vector2i = world.pixel_view.size

	world.player.velocity = Vector2(PlayerBody.RUN_SPEED, PlayerBody.MAX_FALL)
	world._update_camera()
	world.player.snap_camera()
	world._size_pixel_view()

	assert_lt(world.player.camera_zoom(), WorldCore.ZOOM_RESTING, "The frame opened")
	assert_eq(world.player._cam.zoom, lens, "...and the lens did not move a hair")
	assert_gt(world.pixel_view.size.x, small.x, "The target grew instead")

	# The invariant that makes the art crisp: one art pixel is still exactly
	# WORLD_PER_PIXEL world units, so a cell still covers a whole 16px tile.
	var seen: Vector2 = world.get_viewport_rect().size / world.player.camera_zoom()
	var per_px: float = seen.x / float(world.pixel_view.size.x)
	assert_almost_eq(per_px, PixelArt.WORLD_PER_PIXEL, 0.05,
		"An art pixel is the same size wide open as at rest — the tile is not resampled")


func test_tiles_are_drawn_from_the_tileset_and_lit() -> void:
	var textured := 0
	for child in world.world_geo.get_children():
		if not (child is Polygon2D):
			continue
		var vis: Polygon2D = child
		assert_not_null(vis.texture, "every drawn fragment samples the tileset")
		assert_eq(vis.uv.size(), vis.polygon.size(), "with one UV per vertex")
		assert_not_null(vis.material, "and is drawn with a lit material")
		textured += 1
	assert_gt(textured, 0, "the world drew some tiles")


func test_lights_are_placed_in_the_world() -> void:
	assert_eq(_light_ids(), ["w_chamber", "w_pit", "w_spawn"],
		"west's three lamps are all burning at the start")


func test_folding_a_lamp_away_removes_it_from_the_overworld() -> void:
	# Fold the pit shut from outside it: the player rides a flap, and the lamp
	# standing over the pit goes into the excised strip with everything else.
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	assert_eq(world.mode, world.Mode.WORLD, "the player rode a flap rather than being pinched")
	assert_eq(_light_ids(), ["w_chamber", "w_spawn"],
		"the folded-away lamp is not in the world at all — it casts nothing here")

	world.unfold_level_fold(world.folds[0])
	assert_eq(_light_ids(), ["w_chamber", "w_pit", "w_spawn"],
		"unfolding re-derives it back into the world")


func test_a_lamp_rides_the_flap_that_carries_its_tile() -> void:
	var before = _light_pos("w_spawn")
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	var after = _light_pos("w_spawn")
	assert_not_null(after, "the spawn lamp is outside the band and survives")
	assert_almost_eq(Vector2(after).x, Vector2(before).x + 4 * CS, 0.001,
		"it moved by exactly its flap's shift — a light is an occupant, not an overlay")


func test_a_lamp_folded_in_with_you_lights_the_inside() -> void:
	_pinch_over_pit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "the fold swallowed the player")
	assert_eq(_light_ids(), ["w_pit"],
		"the lamp that was over the pit is in here with you, and the ones outside are not")
	# The strip repeats across the glue, so its lights repeat with it — walking
	# through the cylinder must not walk into a dark copy of a lit room.
	var copies: int = 2 * world.SUB_LIGHT_COPIES + 1
	assert_eq(world.lights_here().size(), copies, "one lamp per wrap copy")


func test_the_vault_lamp_is_dark_from_the_overworld() -> void:
	_enter_east()
	assert_eq(_light_ids(), ["e_reward"],
		"east ships pre-folded: the vault's lamp is inside that fold, not in the region")


func test_walking_into_the_folded_vault_finds_its_lamp_burning() -> void:
	# W1's partner is folded away, so the door delivers you INSIDE the fold.
	world._traverse("W1")
	assert_eq(world.region_id, "east", "the door crossed regions")
	assert_eq(world.mode, world.Mode.SUBSPACE, "...and landed inside the pre-placed fold")
	assert_true(_light_ids().has("e_vault"),
		"the lamp that is invisible from the overworld is what lights the vault")


# ---------------------------------------------------------------------------
# Dynamic camera framing
# ---------------------------------------------------------------------------

func test_camera_starts_at_the_resting_zoom() -> void:
	assert_almost_eq(world.player.camera_zoom(), WorldCore.ZOOM_RESTING, 0.001,
		"A fresh world snaps the lens to resting, it does not ease in from 1:1")


func test_running_pulls_the_frame_out() -> void:
	world._update_camera()
	var still: float = world.player.zoom_target
	world.player.velocity.x = PlayerBody.RUN_SPEED
	world._update_camera()
	var running: float = world.player.zoom_target
	assert_lt(running, still, "At a full run the camera shows more ground")

	world.player.velocity.y = PlayerBody.MAX_FALL
	world._update_camera()
	assert_lt(world.player.zoom_target, running, "Falling hard pulls it out further still")


func test_a_far_pinned_anchor_stays_in_frame() -> void:
	world._update_camera()
	var before: float = world.player.zoom_target
	world.place_pending(0, Vector2i(1, 0))              # anchor 1 at (5,12)
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Anchor pinned")

	# Walk 20 cells away: the fold being composed is now wider than the frame.
	world.player.teleport(Vector2(25.5 * CS, 12.5 * CS), false)
	world.player.snap_camera()
	world._update_camera()
	assert_lt(world.player.zoom_target, before,
		"The far half of the fold you are building drags the frame open")

	world.pending_a = null
	world._update_camera()
	assert_almost_eq(world.player.zoom_target, before, 0.001,
		"Clearing the anchor lets the frame settle back")


func test_inside_a_fold_the_band_is_framed_glue_to_glue() -> void:
	_pinch_over_pit()
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	var focus: PackedVector2Array = world._camera_focus()
	var n: Vector2 = world.sub_fold.crease_normal
	var near: float = world.sub_fold.crease_point1.dot(n)
	var far: float = near + world.sub_fold.gap_distance()
	var seen := {}
	for p in focus:
		seen[snappedf(Vector2(p).dot(n), 0.01)] = true
	assert_true(seen.has(snappedf(near, 0.01)), "The near glue line is held in frame")
	assert_true(seen.has(snappedf(far, 0.01)), "...and so is the far one: the band is the room")


func test_the_fold_animation_draws_where_the_world_draws() -> void:
	# The transition replaces the world's geometry for a moment, so it has to be
	# drawn by the same camera through the same render target. Parented outside
	# `pixel_view` it renders in raw window space with no camera transform, which
	# reads as the map flying off to the origin and snapping back when the real
	# geometry returns.
	world.anim_enabled = true
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_true(world.animating(), "The fold is playing")

	var layer: Node2D = world._anim["layer"]
	assert_eq(layer.get_parent(), world.pixel_view,
		"The animation layer draws inside the pixel viewport, like world_geo does")
	assert_eq(layer.get_viewport(), world.world_geo.get_viewport(),
		"...which is to say: the same viewport the geometry it replaces was in")


func test_a_fold_transition_steps_the_camera_back() -> void:
	world.anim_enabled = true
	world._update_camera()
	var before: float = world.player.zoom_target
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_true(world.animating(), "The fold is playing")
	world._update_camera()
	assert_lt(world.player.zoom_target, before, "The world rearranging pulls the lens back")

	world._process(world.ANIM_TIME)                     # play the transition out
	assert_false(world.animating(), "The fold settled")
	world._update_camera()
	assert_almost_eq(world.player.zoom_target, before, 0.001,
		"...and the frame settles back once it has")


func test_a_hard_relocation_cuts_the_lens_as_well_as_the_position() -> void:
	# Falling wide, then warped. Easing into the destination's framing would read
	# as the new room inflating around you, so the cut takes the lens with it.
	world.player.velocity.y = PlayerBody.MAX_FALL
	world._update_camera()
	assert_lt(world.player.zoom_target, WorldCore.ZOOM_RESTING, "The fall opened the frame")

	world.player.velocity = Vector2.ZERO
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	world._cut_camera()
	assert_almost_eq(world.player.camera_zoom(), WorldCore.ZOOM_RESTING, 0.001,
		"The cut lands on the destination's own framing, with nothing left to ease")


# ---------------------------------------------------------------------------
# Camera lookahead
# ---------------------------------------------------------------------------

func test_the_frame_leads_the_direction_you_run() -> void:
	world._update_camera()
	assert_eq(world.player.lookahead_target, Vector2.ZERO, "Standing still: no lead")

	world.player.velocity.x = PlayerBody.RUN_SPEED
	world._update_camera()
	assert_almost_eq(world.player.lookahead_target.x, WorldCore.LOOKAHEAD_RUN, 0.001,
		"A full run right leads a full run's reach right")

	world.player.velocity.x = -PlayerBody.RUN_SPEED
	world._update_camera()
	assert_almost_eq(world.player.lookahead_target.x, -WorldCore.LOOKAHEAD_RUN, 0.001,
		"...and the mirror of that going left")


func test_the_camera_eases_into_a_lead_rather_than_snapping_to_it() -> void:
	# The lead flips sign the moment you turn around. Snapping it would whip the
	# frame across the body on every direction change.
	world.player.velocity.x = PlayerBody.RUN_SPEED
	world._update_camera()
	world.player._process(1.0 / 60.0)
	var partial: Vector2 = world.player.camera_lookahead()
	assert_gt(partial.x, 0.0, "One frame in, the lead has started")
	assert_lt(partial.x, WorldCore.LOOKAHEAD_RUN,
		"...but is nowhere near arrived: it eases")

	for _i in range(240):
		world.player._process(1.0 / 60.0)
	assert_almost_eq(world.player.camera_lookahead().x, WorldCore.LOOKAHEAD_RUN, 1.0,
		"Given time it settles on the full lead")


func test_the_camera_follows_the_led_point_not_the_body() -> void:
	# The lead is what makes the frame show the ground ahead: the follow has to
	# chase body+lead, or easing the lead would change nothing on screen.
	world.player.velocity.x = PlayerBody.RUN_SPEED
	world._update_camera()
	for _i in range(240):
		world.player._process(1.0 / 60.0)
	var ahead: float = world.player.camera_position().x - world.player.global_position.x
	assert_almost_eq(ahead, WorldCore.LOOKAHEAD_RUN, 2.0,
		"The camera settles a run's reach ahead of the body, not on top of it")


func test_a_hard_relocation_cuts_the_lead_too() -> void:
	# Arriving somewhere new with a stale lead would drift the frame sideways as
	# you land, which reads as the camera having lost you.
	world.player.velocity.x = PlayerBody.RUN_SPEED
	world._update_camera()
	for _i in range(240):
		world.player._process(1.0 / 60.0)
	assert_gt(world.player.camera_lookahead().x, 0.0, "Leading hard right")

	world.player.velocity = Vector2.ZERO
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	world._cut_camera()
	assert_eq(world.player.camera_lookahead(), Vector2.ZERO,
		"The cut drops the stale lead")
	assert_eq(world.player.camera_position(), world.player.global_position,
		"...so the camera lands exactly on the body")


func test_the_zoom_is_measured_from_the_led_camera_not_the_body() -> void:
	# The lead moves the camera, and the focus reach is measured from where the
	# camera ENDS UP — so which WAY you are leading changes what the frame has to
	# cover. Running away from a pinned anchor must open the frame wider than
	# running toward it at the same speed. (Same speed in both, so the motion pull
	# is identical and the lead is the only difference.)
	world.place_pending(0, Vector2i(1, 0))                      # anchor at (5,12)
	assert_eq(world.pending_cell(0), Vector2i(5, 12), "Anchor pinned")
	world.player.teleport(Vector2(16.0 * CS, 12.5 * CS), false)

	world.player.velocity.x = PlayerBody.RUN_SPEED              # leading away from it
	world._cut_camera()
	var away: float = world.player.camera_zoom()

	world.player.velocity.x = -PlayerBody.RUN_SPEED             # leading back toward it
	world._cut_camera()
	var toward: float = world.player.camera_zoom()

	assert_lt(away, toward,
		"Leading away from the anchor puts it further off the led frame, so the frame opens")
	assert_gt(away, WorldCore.ZOOM_WIDEST,
		"...and this is a real framing decision, not the floor being hit")


func test_inside_a_fold_the_lead_is_flat_along_the_band() -> void:
	# The strip repeats along the crease normal, so the frame already shows every
	# band there is that way. Leading along it slides the view for nothing.
	_pinch_over_pit()
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.player.velocity = Vector2(PlayerBody.RUN_SPEED, PlayerBody.MAX_FALL)
	world._update_camera()
	var n: Vector2 = world.sub_fold.crease_normal
	assert_almost_eq(world.player.lookahead_target.dot(n), 0.0, 0.001,
		"No lead along the repeating axis")
	assert_gt(world.player.lookahead_target.length(), 0.0,
		"...but the lead across the band survives")


func test_the_lead_holds_still_while_a_fold_plays() -> void:
	world.anim_enabled = true
	world.player.velocity.x = PlayerBody.RUN_SPEED
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	assert_true(world.animating(), "The fold is playing")
	world._update_camera()
	assert_eq(world.player.lookahead_target, Vector2.ZERO,
		"Riding a fold: the transition frames itself from its own endpoints")
