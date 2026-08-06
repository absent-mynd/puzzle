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
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "First tap puts a hand on the aimed cell")
	assert_false(world.fuse_running(), "...and one hand is not a pair")

	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	assert_true(world.anchor_cells().has(Vector2i(9, 12)), "Second tap puts the other one down")
	assert_eq(world.folds.size(), 0, "Placing does not fold")
	assert_true(world.fuse_running(), "...it lights the fuse")

	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.mode, world.Mode.SUBSPACE,
		"The fuse folds it, and the player inside the band is folded in")
	assert_eq(world.hands_pending(), 0, "The hands went from the anchors into the fold")


func test_neighbouring_hands_make_a_perfectly_good_fold() -> void:
	# There is no minimum distance. A one-cell fold is a fold.
	world.tap_action(Vector2i(1, 0))                # (5,12)
	world.player.teleport(Vector2(5.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                # (6,12): the very next cell
	assert_true(world.anchor_cells().has(Vector2i(6, 12)), "The neighbouring hand lands")
	assert_true(world.fuse_running(), "...and lights the fuse like any pair")

	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.hands_in_folds(), 2, "It folded, holding both hands")


func test_placement_asks_nothing_of_the_fold() -> void:
	# The player may put hands anywhere there is sheet to pin to, valid pair or not.
	# Whether it makes a fold is the fuse's question, not placement's.
	world.tap_action(Vector2i(1, 0))                # (5,12)
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "First hand down")

	world.tap_action(Vector2i(0, 1))                # (4,13): would once have been refused
	assert_true(world.anchor_cells().has(Vector2i(4, 13)),
		"The second lands wherever it was aimed")
	assert_true(world.fuse_running(), "...and the pair is counting down")


func test_a_fold_that_cannot_go_drops_both_hands_where_they_stood() -> void:
	# Both hands on ONE cell is the one pair with no crease direction at all. The
	# fuse still runs — you had that long to move one of them — and when it fires
	# the hands fall on the spots you chose rather than returning to you.
	world.tap_action(Vector2i(1, 0))                # (5,12)
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                # (5,12) again: the same cell
	assert_eq(world.anchor_cells(), [Vector2i(5, 12), Vector2i(5, 12)],
		"Both hands on one cell")
	assert_true(world.fuse_running(), "The pair still counts down")

	var loose_before: int = world.hands_loose()
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.folds.size(), 0, "Nothing folded")
	assert_eq(world.hands_pending(), 0, "Neither hand is still pinned")
	assert_eq(world.hands_held(), 0, "...and neither came back to you")
	assert_eq(world.hands_loose(), loose_before + 2, "Both fell where they were placed")
	assert_eq(_total(), 5, "Conserved, as ever")


func test_dropped_hands_land_on_the_cells_they_were_pinned_to() -> void:
	world.tap_action(Vector2i(1, 0))                # (5,12)
	var at = _plane_point(Vector2i(5, 12))
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                # (5,12) again — degenerate
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)

	var near := 0
	for entry in world.loose_hand_points():
		if Vector2(entry["pos"]).distance_to(Vector2(at)) < 0.01:
			near += 1
	assert_eq(near, 2, "Both hands are lying on the cell they were pinned to")


func test_the_fuse_is_a_window_to_make_a_doubtful_fold_work() -> void:
	# The point of checking late: put both hands down from a spot the fold cannot
	# put you, then move somewhere it can before it fires.
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)   # mid-air over the pit
	world.tap_action(Vector2i(-1, 0))               # (12,12)
	world.tap_action(Vector2i(1, 0))                # (14,12) — you are inside the band
	assert_true(world.fuse_running(), "Both down, counting")

	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)    # run clear of the band
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.mode, world.Mode.WORLD,
		"Having left the band before it fired, you ride a flap instead of being swallowed")
	assert_eq(world.folds.size(), 1, "And the fold went ahead")


# ---------------------------------------------------------------------------
# Several folds armed at once
# ---------------------------------------------------------------------------
# There is no fixed number of placed hands. Pairs arm independently and go off in
# the order their fuses run out, not the order they were laid.

func test_a_hand_left_in_another_region_does_not_wedge_you() -> void:
	# The bug this replaced two fixed anchor registers to fix. A hand placed in west
	# used to sit in one of them forever: every pair formed afterwards contained a
	# partner that could not be reached, so nothing ever fired and only one hand was
	# ever placeable again.
	world.tap_action(Vector2i(1, 0))                        # a hand down in west
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "Placed in west")

	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Crossed to east")
	assert_eq(world.anchor_cells(), [], "The west hand is not here")

	# The remaining hand starts a FRESH pair in east rather than being wasted on the
	# unreachable one.
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.hands_pending(), 2, "Both hands are out — one west, one east")
	assert_false(world.fuse_running(), "...but the east one has no partner yet, so nothing is armed")

	# Pick a hand up and the east pair completes and fires, with the west hand still
	# waiting patiently where it was left.
	world.hands[0] = HandTypes.PLAIN
	world.tap_action(Vector2i(-1, 0))
	assert_true(world.fuse_running(), "The east pair armed")
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.hands_pending(), 1, "The east pair spent itself; the west hand is untouched")


func test_two_pairs_can_be_armed_at_once() -> void:
	world.tap_action(Vector2i(1, 0))                        # (5,12)
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # (9,12) — pair one is armed
	assert_eq(world.primed.size(), 1, "One pair counting down")

	world.hands[0] = HandTypes.PLAIN                        # as if picked up
	world.hands[1] = HandTypes.PLAIN
	world.player.teleport(Vector2(20.5 * CS, 5.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # (21,5)
	world.player.teleport(Vector2(25.5 * CS, 5.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # (26,5) — pair two is armed
	assert_eq(world.primed.size(), 2, "Two folds armed at the same time")
	assert_eq(world.hands_pending(), 4, "Four hands are out")


func test_pairs_fire_in_fuse_order_not_placement_order() -> void:
	# The behaviour that falls out of per-pair fuses: a swift pair laid SECOND goes
	# off before a patient pair laid first.
	world.hands[0] = HandTypes.PATIENT
	world.hands[1] = HandTypes.PATIENT
	world.player.teleport(Vector2(20.5 * CS, 5.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(25.5 * CS, 5.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # patient pair, laid first

	world.hands[0] = HandTypes.SWIFT
	world.hands[1] = HandTypes.SWIFT
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # swift pair, laid second
	assert_eq(world.primed.size(), 2, "Both armed")

	# Stand clear of the swift band, or its fold swallows you and the patient pair —
	# left at world level — stops resolving and quietly pauses.
	world.player.teleport(Vector2(2.5 * CS, 12.5 * CS), false)

	# Long enough for swift (0.65s), nowhere near patient (3.2s).
	world._tick_fuse(HandTypes.fuse(HandTypes.SWIFT) + 0.01)
	assert_eq(world.primed.size(), 1, "The swift pair went first, though it was laid second")
	assert_eq(world.folds.size(), 1, "...and its fold is in the world")

	world._tick_fuse(HandTypes.fuse(HandTypes.PATIENT) + 0.01)
	assert_eq(world.primed.size(), 0, "The patient pair follows in its own time")


func test_an_armed_pair_in_another_region_waits_for_you() -> void:
	world.tap_action(Vector2i(1, 0))                        # (5,12)
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # (9,12) — armed in west
	assert_eq(world.primed.size(), 1, "Armed")

	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Left the region with a fold ticking")
	world._tick_fuse(100.0)
	assert_eq(world.primed.size(), 1, "It waits rather than firing where you cannot see")

	# Arriving through a door latches it; stepping off is what clears the latch.
	world.player.teleport(Vector2(6.5 * CS, 9.5 * CS), false)
	world._check_doors()
	world.player.teleport(Vector2(_plane_point(Vector2i(2, 9))), false)
	world._check_doors()
	assert_eq(world.region_id, "west", "Back in west")
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	assert_eq(world.primed.size(), 0, "...and it resumes and fires when you return")


func test_a_burst_into_an_armed_pair_breaks_the_whole_pair() -> void:
	# You cannot half-defuse a fold. What you can reach comes back; the far hand
	# drops where it was pinned, so reaching into an armed pair always costs you one.
	world.tap_action(Vector2i(1, 0))                        # (5,12)
	world.player.teleport(Vector2(20.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                        # (21,12), far from the first
	assert_eq(world.primed.size(), 1, "Armed")
	var loose_before: int = world.hands_loose()

	world.player.teleport(Vector2(5.5 * CS, 12.5 * CS), false)   # stand on the near hand
	world.hold_action()
	assert_eq(world.primed.size(), 0, "The pair is broken")
	assert_eq(world.hands_held(), 1, "The hand you reached came back")
	assert_eq(world.hands_loose(), loose_before + 1, "...and the far one fell where it was")
	assert_eq(_total(), 5, "Conserved")


func test_a_tap_at_a_seam_places_and_the_burst_clears_everything() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))  # seam anchor at (24,12)
	assert_eq(world.folds.size(), 1, "Fold active")
	world.player.teleport(Vector2(23.5 * CS, 12.5 * CS), false)
	world.hands[0] = HandTypes.PLAIN                # as if picked up from a cache

	world.tap_action(Vector2i(1, 0))                # a tap only ever places
	assert_eq(world.folds.size(), 1, "A TAP at a seam does not unfold")
	assert_eq(world.anchor_cells(), [Vector2i(24, 12)], "...it put a hand there")

	# The burst is not aimed: it takes the placed hand AND opens the seam, both
	# being within reach of where you stand.
	world.hold_action()
	assert_eq(world.anchor_cells(), [], "The burst took the placed hand back")
	assert_eq(world.folds.size(), 0, "...and opened the seam under the same cell")
	assert_eq(world.hands_held(), 2, "Two hands in your slots")
	assert_eq(world.hands_loose(), 4, "...and the one with nowhere to go joined the world's three")


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
	world.hold_action()
	assert_eq(world.folds.size(), 1,
		"One burst clears one layer — releasing the newer fold is what unblocks the older")
	assert_eq(world.folds[0].anchor1, Vector2i(20, 12),
		"...the newest one that can come out; the buried one stays")

	# With only the buried fold left, a second burst takes it — after walking back,
	# since the first unfold carried you off the diamond with its flap.
	world.player.teleport(Vector2(22.5 * CS, 12.5 * CS), false)
	world.hold_action()
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
	world.hold_action()
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


func test_placed_hands_survive_subspace_exit() -> void:
	_pinch_over_pit()
	world.hands[0] = HandTypes.PLAIN                # as if picked up in there
	world.tap_action(Vector2i(1, 0))                # placed INSIDE the fold, cell (14,12)
	assert_eq(world.anchor_cells(), [Vector2i(14, 12)], "Hand pinned inside the subspace")
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exited")
	assert_eq(world.anchor_cells(), [Vector2i(14, 12)],
		"The hand survived the unfold and landed where the strip content did")


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


func test_a_placed_hand_is_inert_across_regions() -> void:
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "Hand pinned in west")
	world.player.teleport(Vector2(42.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.region_id, "east", "Traversed")
	assert_eq(world.anchor_cells(), [], "The west hand is nowhere to be seen in east")
	assert_eq(world.hands_pending(), 1, "...but it is still out there, waiting")


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


func test_you_start_with_a_full_pair() -> void:
	assert_eq(world.hands.size(), AnchorStock.SLOTS, "One entry per slot")
	assert_eq(world.hands_held(), 2, "Both slots full at the start")
	assert_eq(world.hands_in_folds(), 0, "Nothing committed yet")
	assert_eq(world.hands_loose(), 3, "...and the world's three lie where it put them")


func test_placing_a_hand_takes_it_out_of_its_slot() -> void:
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "The tap put a hand down")
	assert_eq(world.hands_held(), 1, "...which left your slots")
	assert_eq(world.hands_free_slots(), 1, "...freeing the slot it came from")
	assert_eq(_total(), 5, "and nothing was created or destroyed")


func test_holding_takes_a_placed_hand_back() -> void:
	world.tap_action(Vector2i(1, 0))
	world.hold_action()
	assert_eq(world.anchor_cells(), [], "The burst pulls it back")
	assert_eq(world.hands_held(), 2, "...into a slot")
	assert_eq(_total(), 5, "Conserved")


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
	assert_eq(_total(), 5, "Still five hands; two of them are now inside the fold")


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

	world.hold_action()
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
	assert_eq(_total(), 5, "Conserved")

	world.unfold_level_fold(world.folds[0])
	assert_eq(world.hands_held(), 2, "Unfolding gave them back")
	assert_eq(_total(), 5, "Still conserved")


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
	assert_eq(world.anchor_cells(), [], "A tap with empty hands puts nothing down")


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


func test_an_interior_fold_holds_hands_across_the_subspace_boundary() -> void:
	_pinch_over_pit()
	assert_eq(world.hands_held(), 0, "The pinch fold took both hands")

	world.hands[0] = HandTypes.SWIFT
	world.hands[1] = HandTypes.SWIFT
	world.player.teleport(Vector2(11.2 * CS, 12.5 * CS), false)
	assert_true(world.do_sub_fold(Vector2i(12, 8), Vector2i(15, 8)), "Interior fold commits")
	assert_eq(world.hands_held(), 0, "It took the pair too")
	assert_eq(_total(), 7, "Seven hands exist; four of them committed")

	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD, "Exited")
	assert_eq(world.hands_held(), 2, "The outer fold returned its pair")
	assert_eq(world.hands_in_folds(), 2,
		"The interior fold persisted into the world, still holding its own")


# ---------------------------------------------------------------------------
# Loose hands
# ---------------------------------------------------------------------------
# A cache the world shipped and a hand that popped out of a burst are the same
# object, in the same list, drawn the same way.

func _loose_count() -> int:
	return world.loose_hands.size()


func test_a_loose_hand_gives_one_hand_into_one_free_slot() -> void:
	# Full hands walk straight over one: it is the second half of a fold you have
	# already started, not a stockpile you raid on the way past.
	var spot = _plane_point(Vector2i(24, 6))
	assert_not_null(spot, "The pillar-top hand lies in normal space")
	world.player.teleport(Vector2(spot), false)
	world._check_pickups()
	assert_eq(world.hands_held(), 2, "With both hands full it is left where it is")
	assert_eq(_loose_count(), 2, "...and stays in the world")

	world.tap_action(Vector2i(1, 0))                        # put one down to free a slot
	world.player.teleport(Vector2(spot), false)
	world._check_pickups()
	assert_eq(world.hands_held(), 2, "The free slot took it")
	assert_eq(_loose_count(), 1, "...and it is gone from the ground")
	assert_eq(_total(), 5, "Nothing created — a hand moved from the ground to your slot")


func test_a_loose_hand_gives_the_kind_it_was_authored_with() -> void:
	world.tap_action(Vector2i(1, 0))                        # free a slot
	world.player.teleport(Vector2(_plane_point(Vector2i(24, 6))), false)
	world._check_pickups()
	var got: Array = []
	for h in world.hands:
		if h != null:
			got.append(h)
	assert_true(got.has(HandTypes.SWIFT),
		"The pillar-top hand is authored swift, and a swift hand is what it gave")


## Where the loose hand of a given kind lies in the current view, or null. West's two
## are one swift and one patient, so the kind names them.
func _loose_pos_of(kind: int):
	for entry in world.loose_hand_points():
		if entry["pickup"].kind == kind:
			return Vector2(entry["pos"])
	return null


func test_a_loose_hand_rides_folds_like_any_occupant() -> void:
	# It is stored as a base identity, not a position, so it moves with its flap —
	# nobody wrote that; it falls out of asking the fragment list where it is.
	var before = _loose_pos_of(HandTypes.SWIFT)
	assert_not_null(before, "The pillar-top hand is in the world")
	assert_almost_eq(Vector2(before).distance_to(Vector2(_plane_point(Vector2i(24, 6)))),
		0.0, 0.01, "...lying on its authored cell")

	# A fold clear of the player (spawn is at x=4.5c, west of the band) so nobody
	# gets pinched: the hand is B-side and rides inward.
	world.do_fold(Vector2i(14, 6), Vector2i(20, 6))
	assert_eq(world.mode, world.Mode.WORLD, "The player rode a flap rather than being folded in")
	var after = _loose_pos_of(HandTypes.SWIFT)
	assert_not_null(after, "The hand survived the fold")
	assert_almost_eq(Vector2(after).x, Vector2(before).x - 3 * CS, 0.01,
		"...and moved by exactly its flap's shift")


func test_a_hand_folded_away_is_collectable_inside_the_fold() -> void:
	# East's shipped pre-fold excised the hand at (14,9) along with door E1. A hand
	# inside a fold is not lost — the strip is a real place, and taking it counts.
	world.tap_action(Vector2i(1, 0))                        # free a slot first
	var before: int = _total()
	world.player.teleport(Vector2(1.5 * CS, 13.5 * CS), false)
	world._check_doors()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Through W1, inside the shipped fold")

	world.player.teleport(Vector2(14.5 * CS, 9.5 * CS), false)
	world._check_pickups()
	assert_eq(world.hands_held(), 2, "The hand the fold swallowed went into the free slot")
	assert_eq(_total(), before, "...and taking it created nothing")


func test_reset_puts_both_the_world_and_your_hands_back() -> void:
	# Nothing you can hold grows, so a reset has no progression to confiscate — and
	# hands are exactly what it must restore, or the escape hatch leaves you worse off.
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(_plane_point(Vector2i(24, 6))), false)
	world._check_pickups()
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))

	world._reset()
	assert_eq(world.folds.size(), 0, "The world is back to its authored folds")
	assert_eq(world.hands_held(), 2, "You have your starting pair again")
	assert_eq(world.hands_in_folds(), 0, "Nothing is holding anything")
	assert_eq(_loose_count(), 2, "And west's authored hands are lying out again")


# ---------------------------------------------------------------------------
# The release burst
# ---------------------------------------------------------------------------
# Not an aimed action: a small sphere around the body. Everything of yours inside
# it comes loose, and anything with nowhere to go lands on the ground.

func test_the_burst_takes_back_a_hand_you_placed_in_reach() -> void:
	world.tap_action(Vector2i(1, 0))                        # (5,12), one cell away
	assert_eq(world.hands_held(), 1, "A hand is down")

	world.hold_action()
	assert_eq(world.anchor_cells(), [], "The burst took it back")
	assert_eq(world.hands_held(), 2, "...into a slot")
	assert_eq(_total(), 5, "Conserved")


func test_the_burst_leaves_a_hand_out_of_reach_alone() -> void:
	world.tap_action(Vector2i(1, 0))                        # (5,12)
	world.player.teleport(Vector2(20.5 * CS, 12.5 * CS), false)   # walk well away

	world.hold_action()
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "Out of reach, so it stays put")
	assert_eq(world.hands_held(), 1, "...and you are still short a hand")


func test_the_burst_unfolds_a_seam_in_reach() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))       # seam anchor at (24,12)
	world.player.teleport(Vector2(24.5 * CS, 12.5 * CS), false)

	world.hold_action()
	assert_eq(world.folds.size(), 0, "The seam under you came apart")
	assert_eq(world.hands_held(), 2, "...and gave both hands back")


func test_the_burst_leaves_a_seam_out_of_reach_folded() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)

	world.hold_action()
	assert_eq(world.folds.size(), 1, "A seam across the map is not in the burst")


func test_the_burst_pops_hands_into_the_world_when_your_slots_are_full() -> void:
	# The clause that lets the burst be fired blind: a hand that cannot be caught is
	# a hand on the ground, not a hand destroyed and not an action refused.
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))       # both hands into the fold
	assert_eq(world.hands_held(), 0, "Both committed")
	world.hands[0] = HandTypes.SWIFT                        # as if picked up meanwhile
	world.hands[1] = HandTypes.SWIFT
	var loose_before: int = _loose_count()
	var total_before: int = _total()

	world.player.teleport(Vector2(24.5 * CS, 12.5 * CS), false)
	world.hold_action()
	assert_eq(world.folds.size(), 0, "The fold came apart anyway — nothing is refused for room")
	assert_eq(world.hands_held(), 2, "Your slots are still full")
	assert_eq(_loose_count(), loose_before + 2, "Both freed hands popped into the world")
	assert_eq(_total(), total_before, "Nothing was created or destroyed")


func test_a_popped_hand_can_be_picked_straight_back_up() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	world.hands[0] = HandTypes.SWIFT
	world.hands[1] = HandTypes.SWIFT
	world.player.teleport(Vector2(24.5 * CS, 12.5 * CS), false)
	world.hold_action()

	world.tap_action(Vector2i(1, 0))                        # free a slot
	world._check_pickups()
	assert_eq(world.hands_held(), 2, "A hand you dropped is a hand you can take again")


func test_a_popped_hand_keeps_its_kind() -> void:
	world.hands[0] = HandTypes.PATIENT
	world.hands[1] = HandTypes.PATIENT
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))       # the fold takes both patients
	world.hands[0] = HandTypes.SWIFT                        # fill up with something else
	world.hands[1] = HandTypes.SWIFT
	world.player.teleport(Vector2(24.5 * CS, 12.5 * CS), false)
	world.hold_action()

	var near := 0
	for entry in world.loose_hand_points():
		if entry["pickup"].kind == HandTypes.PATIENT \
				and Vector2(entry["pos"]).distance_to(world.player.global_position) < 2.0 * CS:
			near += 1
	assert_eq(near, 2, "Both patient hands are on the ground at your feet, still patient")


func test_the_burst_exits_a_subspace_from_the_glue() -> void:
	_pinch_over_pit()
	assert_eq(world.mode, world.Mode.SUBSPACE, "Pinched in")
	world.player.teleport(Vector2(10.5 * CS, 12.5 * CS), false)   # at the glue anchor
	assert_true(world.glue_within_burst(), "The glue anchor is in reach")

	world.hold_action()
	assert_eq(world.mode, world.Mode.WORLD, "The burst opened the fold from inside")


func test_the_burst_says_so_when_it_finds_nothing() -> void:
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	world.hold_action()
	assert_eq(world.folds.size(), 0, "Nothing to release, nothing released")
	assert_eq(world.hands_held(), 2, "...and nothing taken from you")


func test_the_burst_reports_the_seams_it_would_reach() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	assert_eq(world.seams_within_burst().size(), 0, "Nothing in reach from over here")

	world.player.teleport(Vector2(24.5 * CS, 12.5 * CS), false)
	assert_eq(world.seams_within_burst().size(), 1, "Standing on it, the seam is in reach")


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
	world.place_hand(Vector2i(1, 0))                    # a hand at (5,12)
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "Hand placed")

	# Walk 20 cells away: the fold being composed is now wider than the frame.
	world.player.teleport(Vector2(25.5 * CS, 12.5 * CS), false)
	world.player.snap_camera()
	world._update_camera()
	assert_lt(world.player.zoom_target, before,
		"The far half of the fold you are building drags the frame open")

	world.unpaired.clear()
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
	world.place_hand(Vector2i(1, 0))                            # a hand at (5,12)
	assert_eq(world.anchor_cells(), [Vector2i(5, 12)], "Hand placed")
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
