extends GutTest

## Tests for WorldCore — the pure logic under the side-view gravity world. Covers map
## parsing, free-position fold classification, strip capture for subspaces, unfold
## displacement, registry-driven anchor/fold eligibility, and the geometry-only
## collision helpers.

const CS := 64.0

const MINI_MAP := [
	"........",
	"..##....",
	"........",
	"########",
]


func _mini_grid() -> BaseGrid:
	return WorldCore.parse_map(MINI_MAP, CS)


func test_parse_map_dimensions_and_types() -> void:
	var bg := _mini_grid()
	assert_eq(bg.grid_size, Vector2i(8, 4), "Grid should be 8x4")
	assert_eq(bg.tiles.size(), 32, "Every position materializes a tile")
	assert_eq(bg.tile_at(Vector2i(2, 1)).type, BaseTile.TYPE_WALL, "# is wall")
	assert_eq(bg.tile_at(Vector2i(0, 0)).type, BaseTile.TYPE_EMPTY, ". is empty")
	assert_eq(bg.tile_at(Vector2i(0, 3)).type, BaseTile.TYPE_WALL, "Ground row is wall")


func test_parse_map_pads_short_rows() -> void:
	var bg := WorldCore.parse_map(["####", "."], CS)
	assert_eq(bg.grid_size, Vector2i(4, 2), "Width comes from the longest row")
	assert_eq(bg.tile_at(Vector2i(3, 1)).type, BaseTile.TYPE_EMPTY,
		"Short rows are padded with air")


func test_parse_map_goal_type() -> void:
	var bg := WorldCore.parse_map(["..G."], CS)
	assert_eq(bg.tile_at(Vector2i(2, 0)).type, BaseTile.TYPE_GOAL, "G is goal")


func test_side_of_fold_classifies_flaps_and_strip() -> void:
	# Horizontal fold: anchors (2,1)-(5,1) => vertical creases at x=160 and x=352.
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)
	assert_eq(WorldCore.side_of_fold(Vector2(100, 100), fold), -1, "Left of crease1 is A-side")
	assert_eq(WorldCore.side_of_fold(Vector2(200, 50), fold), 0, "Between creases is the strip")
	assert_eq(WorldCore.side_of_fold(Vector2(400, 200), fold), 1, "Right of crease2 is B-side")


func test_fold_then_unfold_shift_round_trips() -> void:
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)
	for start in [Vector2(100, 100), Vector2(420, 90)]:
		var side := WorldCore.side_of_fold(start, fold)
		var folded: Vector2 = start + WorldCore.fold_shift_for_side(side, fold, CS)
		var back: Vector2 = folded + WorldCore.unfold_shift(folded, fold, CS)
		assert_almost_eq(back.x, start.x, 0.001, "Unfold returns the ridden point (x)")
		assert_almost_eq(back.y, start.y, 0.001, "Unfold returns the ridden point (y)")


func test_capture_strip_area_matches_excised_band() -> void:
	var bg := _mini_grid()
	var pieces := FoldReplay.identity_pieces(bg)
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)
	var strip := WorldCore.capture_strip(pieces, fold, CS)
	assert_gt(strip.size(), 0, "Strip capture yields pieces")
	var total := 0.0
	var wall_area := 0.0
	for entry in strip:
		var a: float = GeometryCore.polygon_area(entry.polygon)
		total += a
		if entry.type == BaseTile.TYPE_WALL:
			wall_area += a
	# Strip is gap(192px) x full map height(256px); map is fully tiled.
	assert_almost_eq(total, 192.0 * 256.0, 1.0, "Captured area equals the strip")
	# The strip (x in 160..352) cuts the wall pair at (2,1),(3,1): 1.5 cells of
	# wall, and half a ground-row cell per column => 3 cells of ground wall.
	assert_almost_eq(wall_area, 4.5 * CS * CS, 1.0, "Wall content rides into the strip")


func test_capture_strip_preserves_pre_fold_frame() -> void:
	var bg := _mini_grid()
	var pieces := FoldReplay.identity_pieces(bg)
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)
	var strip := WorldCore.capture_strip(pieces, fold, CS)
	var extent := WorldCore.strip_extent(strip, Vector2(1, 0))
	assert_almost_eq(extent["min"], 160.0, 0.01, "Strip starts at crease 1 (unshifted)")
	assert_almost_eq(extent["max"], 352.0, 0.01, "Strip ends at crease 2 (unshifted)")


func test_circle_overlap_and_depenetrate() -> void:
	var box := PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)])
	assert_true(WorldCore.circle_overlaps_polygon(Vector2(32, 32), 20.0, box),
		"Center inside polygon overlaps")
	assert_true(WorldCore.circle_overlaps_polygon(Vector2(70, 32), 20.0, box),
		"Circle straddling an edge overlaps")
	assert_false(WorldCore.circle_overlaps_polygon(Vector2(120, 32), 20.0, box),
		"Distant circle does not overlap")

	var free := WorldCore.depenetrate(Vector2(32, 60), 20.0, [box])
	assert_ne(free, Vector2.INF, "Depenetration finds a free spot")
	assert_false(WorldCore.circle_overlaps_solids(free, 20.0, [box]),
		"Found spot is actually free")


func test_base_frame_mapping_round_trips_through_a_fold() -> void:
	var bg := _mini_grid()
	var pieces := FoldReplay.identity_pieces(bg)
	var index := BaseFrame.index_by_pos(pieces)
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)

	var start := Vector2(100, 100)  # in cell (1,1), A-side
	var piece = BaseFrame.piece_containing(index, start, CS)
	assert_not_null(piece, "Point over a tile resolves to its piece")
	var bp: Vector2 = start - piece.src_offset

	var folded := FoldReplay.apply_one_fold(pieces, fold, CS)
	var mapped = BaseFrame.world_point_from_base(folded, piece.base_id, bp)
	assert_not_null(mapped, "A-side base point survives the fold")
	assert_almost_eq(Vector2(mapped).x, start.x + 128.0, 0.01,
		"Mapped point rides shift_a exactly")

	var strip_point := Vector2(200, 50)  # in the excised strip
	var strip_piece = BaseFrame.piece_containing(index, strip_point, CS)
	var gone = BaseFrame.world_point_from_base(
		folded, strip_piece.base_id, strip_point - strip_piece.src_offset)
	assert_null(gone, "Excised base point has no piece after the fold")


func test_resolve_base_point_strict_disables_split_centers() -> void:
	var bg := _mini_grid()
	var pieces := FoldReplay.identity_pieces(bg)
	var bp := Vector2(96, 96)  # center of cell (1,1)
	var bid: int = bg.tile_at(Vector2i(1, 1)).base_id
	assert_not_null(BaseFrame.resolve_base_point(pieces, bid, bp),
		"Whole tile: center resolves")

	# A fold anchored ON the tile cuts it exactly through its center: the
	# point sits on the cut in every piece -> dormant (null) everywhere.
	var fold := Fold.create(0, Vector2i(1, 1), Vector2i(4, 1), CS)
	var folded := FoldReplay.apply_one_fold(pieces, fold, CS)
	assert_null(BaseFrame.resolve_base_point(folded, bid, bp),
		"Center exactly on a crease resolves nowhere in the world")
	var strip := WorldCore.capture_strip(pieces, fold, CS)
	assert_null(BaseFrame.resolve_base_point(strip, bid, bp),
		"Nor in the strip: the split point is dormant until halves rejoin")


func test_segment_intersects_band() -> void:
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)  # strip x in (160,352)
	assert_true(WorldCore.segment_intersects_strip(
		Vector2(200, 0), Vector2(200, 100), fold), "Segment inside the strip")
	assert_true(WorldCore.segment_intersects_strip(
		Vector2(100, 50), Vector2(400, 50), fold), "Segment crossing the strip")
	assert_false(WorldCore.segment_intersects_strip(
		Vector2(100, 0), Vector2(100, 100), fold), "Segment left of the strip")
	assert_false(WorldCore.segment_intersects_strip(
		Vector2(160, 0), Vector2(160, 100), fold), "Segment ON a crease grazes, no block")


# ---------------------------------------------------------------------------
# Carrying a mark through a later fold
# ---------------------------------------------------------------------------
# A fold moves the sheet, so it moves everything already standing on the sheet. What
# these pin is that a mark recorded before the fold is still describing the same place
# in the world afterwards — or is honestly gone.

## Creases at x=288 and x=544; both flaps slide 128 inward to meet at x=416.
func _mover() -> Fold:
	return Fold.create(0, Vector2i(4, 0), Vector2i(8, 0), CS)


func test_a_point_rides_the_flap_it_is_standing_on() -> void:
	var fold := _mover()
	assert_eq(WorldCore.carry_point(Vector2(160, 50), fold, CS), Vector2(288, 50),
		"A point on the A side slides in with the A flap")
	assert_eq(WorldCore.carry_point(Vector2(672, 50), fold, CS), Vector2(544, 50),
		"...and one on the B side comes the other way")
	assert_eq(WorldCore.carry_point(Vector2(288, 50), fold, CS), Vector2(416, 50),
		"A point ON a crease rides that flap out rather than vanishing")


func test_a_point_the_fold_excises_is_carried_nowhere() -> void:
	# The half of this that matters in the world: a seam swallowed by a later fold has
	# gone into that fold's subspace with the sheet it was cut into, and a marker left
	# behind in the space it came from is pointing at nothing.
	assert_null(WorldCore.carry_point(Vector2(416, 50), _mover(), CS),
		"A point between the creases is excised, not moved")


func test_a_line_across_a_fold_comes_back_in_two_pieces() -> void:
	# A fold does not only move an older seam, it can CUT one — and the two halves it
	# hands back meet at the new fold's own seam, because that is what the fold did to
	# everything else on the sheet too.
	var parts := WorldCore.carry_segment(Vector2(100, 50), Vector2(700, 50), _mover(), CS)
	assert_eq(parts.size(), 2, "Cut in two by the strip it crossed")
	assert_almost_eq(Vector2(parts[0][0]).x, 228.0, 0.6, "The A piece slid inward")
	assert_almost_eq(Vector2(parts[0][1]).x, 416.0, 0.6, "...up to the new seam")
	assert_almost_eq(Vector2(parts[1][0]).x, 416.0, 0.6, "...where the B piece takes over")
	assert_almost_eq(Vector2(parts[1][1]).x, 572.0, 0.6, "...and runs on to its far end")


func test_a_line_the_fold_swallowed_whole_comes_back_as_nothing() -> void:
	assert_eq(WorldCore.carry_segment(
		Vector2(350, 0), Vector2(480, 100), _mover(), CS), [],
		"A line entirely between the creases is excised with the strip")


func test_a_line_parallel_to_the_creases_is_moved_and_never_split() -> void:
	# The common case in the world: folds laid the same way as the ones before them.
	# One depth for the whole length, so there is no crossing to solve for — and a
	# seam that grazes a crease has to survive whole, because the rule that decides
	# whether it BLOCKS that fold has already said it does not cross it.
	var fold := _mover()
	for at in [[100.0, 228.0], [288.0, 416.0], [700.0, 572.0]]:
		var parts := WorldCore.carry_segment(
			Vector2(at[0], 0), Vector2(at[0], 600), fold, CS)
		assert_eq(parts.size(), 1, "One piece at x=%s" % at[0])
		assert_almost_eq(Vector2(parts[0][0]).x, float(at[1]), 0.001,
			"...carried to x=%s" % at[1])
		assert_almost_eq(Vector2(parts[0][1]).y, 600.0, 0.001, "...at its full length")


# ---------------------------------------------------------------------------
# The spring the carried hands float on
# ---------------------------------------------------------------------------

func test_spring_step_moves_toward_the_target() -> void:
	var step := WorldCore.spring_step(
		Vector2.ZERO, Vector2.ZERO, Vector2(100, 0), 120.0, 11.0, 1.0 / 60.0)
	assert_gt(Vector2(step["pos"]).x, 0.0, "One step leans toward the target")
	assert_lt(Vector2(step["pos"]).x, 100.0, "...without arriving — it lags, which is the point")


func test_spring_settles_rather_than_running_away() -> void:
	# Stability is the whole requirement: nothing reads these positions, but a hand
	# flung off the map is very visible.
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var target := Vector2(100, -40)
	for _i in range(400):
		var step := WorldCore.spring_step(pos, vel, target, 120.0, 11.0, 1.0 / 60.0)
		pos = step["pos"]
		vel = step["vel"]
	assert_almost_eq(pos.distance_to(target), 0.0, 2.0, "It comes to rest on the target")
	assert_almost_eq(vel.length(), 0.0, 5.0, "...and stops, rather than orbiting forever")


func test_spring_clamps_a_long_frame() -> void:
	# A rebuild or a breakpoint hands us a huge delta; integrated whole it would
	# fling the hand across the map.
	var step := WorldCore.spring_step(
		Vector2.ZERO, Vector2.ZERO, Vector2(100, 0), 120.0, 11.0, 5.0)
	assert_lt(Vector2(step["pos"]).length(), 200.0, "A five-second frame does not launch it")


func test_hand_orbit_offsets_are_distinct_and_near_the_body() -> void:
	var a := WorldCore.hand_orbit_offset(0, 2, 1, Vector2.ZERO, 34.0)
	var b := WorldCore.hand_orbit_offset(1, 2, 1, Vector2.ZERO, 34.0)
	assert_gt(a.distance_to(b), 1.0, "Two hands do not sit on top of each other")
	for off in [a, b]:
		assert_lt(off.length(), 60.0, "A hand orbits close to the body")
		assert_lt(off.y, 0.0, "...and rides above it, clear of the ground")


func test_hand_orbit_trails_the_motion() -> void:
	var still := WorldCore.hand_orbit_offset(0, 1, 1, Vector2.ZERO, 34.0)
	var running := WorldCore.hand_orbit_offset(0, 1, 1, Vector2(320, 0), 34.0)
	assert_lt(running.x, still.x, "Running right strings the hand out behind you")


# ---------------------------------------------------------------------------
# The idle drift (hands never quite hold still)
# ---------------------------------------------------------------------------

func test_hand_drift_stays_near_where_the_hand_sits() -> void:
	# The whole safety requirement: it is a wander, not a departure. A hand drawn a
	# cell away from where it actually is would be a lie about the world.
	for i in range(600):
		var d := WorldCore.hand_drift(0.0, float(i) * 0.1, 8.0)
		assert_lt(d.length(), 8.0 * 1.5, "Drift stays within its radius")


func test_hand_drift_actually_moves() -> void:
	var a := WorldCore.hand_drift(0.0, 0.0)
	var b := WorldCore.hand_drift(0.0, 1.3)
	assert_gt(a.distance_to(b), 0.5, "A second later it is somewhere else")


func test_hand_drift_hovers_rather_than_migrating() -> void:
	# Over a long window it averages out to where the hand sits, so the drift adds
	# no bias — a hand left alone for a minute is still beside you, not off screen.
	var sum := Vector2.ZERO
	var n := 2000
	for i in range(n):
		sum += WorldCore.hand_drift(0.0, float(i) * 0.02)
	assert_lt((sum / float(n)).length(), 1.0, "Its mean is the resting spot")


func test_hand_drift_does_not_repeat_on_a_short_loop() -> void:
	# Frequencies that share a period would give the eye a cycle to learn, and the
	# float would read as an animation loop instead of as idleness.
	var start := WorldCore.hand_drift(0.0, 0.0)
	var returned := 0
	for i in range(1, 1500):
		if WorldCore.hand_drift(0.0, float(i) * 0.02).distance_to(start) < 0.2:
			returned += 1
	assert_lt(returned, 8, "It does not keep landing back on where it began")


func test_two_hands_drift_independently() -> void:
	# Two hands bobbing in lockstep read as one animated pair, not as two objects.
	var apart := 0
	for i in range(200):
		var t := float(i) * 0.05
		if WorldCore.hand_drift(0.0, t).distance_to(WorldCore.hand_drift(1.0, t)) > 2.0:
			apart += 1
	assert_gt(apart, 100, "Slot 0 and slot 1 are mostly in different places")


# ---------------------------------------------------------------------------
# Where a dropped hand comes to rest
# ---------------------------------------------------------------------------
# A hand let go of in mid-air falls to the floor and hovers just above it; a hand let
# go of inside a wall is pushed out of it. Both are the same question — "where does
# this actually end up" — asked once, so a burst, a scatter and a failed fold cannot
# answer it differently.

func _mini_solids() -> Array:
	# Ground row y=3 (surface at y=192); a wall block at (2,1) and (3,1).
	return WorldCore.solid_polys_of(FoldReplay.derive_pieces(_mini_grid(), []))


# ---------------------------------------------------------------------------
# The hand as a ball: it falls, it rolls, it comes to rest
# ---------------------------------------------------------------------------
# A loose hand is a light ball with a lot of air drag. It floats down rather than
# dropping like a stone, lands, rolls off a slope, and settles. `hand_ball_step` is the
# whole simulation and it is PURE — the world steps it and stores the outcome, so the
# physics can be pinned here without a scene.

## A slope: a right triangle rising to the left, so a ball on it rolls right and down.
func _slope_solids() -> Array:
	return [PackedVector2Array([
		Vector2(0, 256), Vector2(256, 256), Vector2(0, 128),
	])]


## Step a ball to rest (or until `limit` frames), returning the final state.
func _run_ball(pos: Vector2, vel: Vector2, solids: Array, limit := 600) -> Dictionary:
	var ball := {"pos": pos, "vel": vel, "resting": false}
	for _i in range(limit):
		ball = WorldCore.hand_ball_step(ball, solids, 1.0 / 60.0)
		if bool(ball["resting"]):
			break
	return ball


func test_a_dropped_ball_accelerates_downward() -> void:
	var ball := WorldCore.hand_ball_step(
		{"pos": Vector2(32, 32), "vel": Vector2.ZERO, "resting": false},
		_mini_solids(), 1.0 / 60.0)
	assert_gt(Vector2(ball["vel"]).y, 0.0, "Gravity pulls it down")
	assert_gt(Vector2(ball["pos"]).y, 32.0, "...and it has moved down")


func test_a_hand_is_light_and_floats_down() -> void:
	# The requirement is a FEEL: high drag, so it drifts down rather than dropping like
	# a stone. Pinned as a terminal speed well under the player's own MAX_FALL.
	var ball := {"pos": Vector2(32, 0), "vel": Vector2.ZERO, "resting": false}
	for _i in range(240):
		ball = WorldCore.hand_ball_step(ball, [], 1.0 / 60.0)
	assert_lt(Vector2(ball["vel"]).y, WorldCore.HAND_TERMINAL_FALL + 1.0,
		"It never exceeds its terminal speed")
	assert_lt(WorldCore.HAND_TERMINAL_FALL, PlayerBody.MAX_FALL * 0.5,
		"...which is far slower than a falling body: a hand is light")


func test_air_drag_bleeds_off_sideways_speed() -> void:
	var ball := {"pos": Vector2(32, 32), "vel": Vector2(400, 0), "resting": false}
	var first := Vector2(WorldCore.hand_ball_step(ball, [], 1.0 / 60.0)["vel"]).x
	for _i in range(60):
		ball = WorldCore.hand_ball_step(ball, [], 1.0 / 60.0)
	assert_lt(Vector2(ball["vel"]).x, first, "A thrown hand slows in the air")
	assert_gt(Vector2(ball["vel"]).x, 0.0, "...without stopping dead")


func test_a_ball_comes_to_rest_on_the_floor() -> void:
	var ball := _run_ball(Vector2(32, 32), Vector2.ZERO, _mini_solids())
	assert_true(bool(ball["resting"]), "It settles rather than jittering forever")
	assert_almost_eq(Vector2(ball["pos"]).y, 192.0 - WorldCore.HAND_CLEARANCE, 3.0,
		"...just above the floor, on its floating radius")


func test_a_resting_ball_stays_put() -> void:
	var ball := _run_ball(Vector2(32, 32), Vector2.ZERO, _mini_solids())
	var settled: Vector2 = ball["pos"]
	for _i in range(120):
		ball = WorldCore.hand_ball_step(ball, _mini_solids(), 1.0 / 60.0)
	assert_almost_eq(Vector2(ball["pos"]).distance_to(settled), 0.0, 0.5,
		"A hand at rest does not creep")


func test_a_ball_never_ends_a_step_inside_a_solid() -> void:
	# The invariant that matters most: a hand you cannot see is a hand you cannot fetch.
	var ball := {"pos": Vector2(32, 32), "vel": Vector2(600, 900), "resting": false}
	var solids := _mini_solids()
	for _i in range(300):
		ball = WorldCore.hand_ball_step(ball, solids, 1.0 / 60.0)
		assert_false(WorldCore.circle_overlaps_solids(Vector2(ball["pos"]), 1.0, solids),
			"Never inside the ground at %s" % ball["pos"])
		if bool(ball["resting"]):
			break


func test_a_fast_ball_does_not_tunnel_through_the_floor() -> void:
	# Swept, not point-sampled: at terminal speed a frame is a fraction of a cell, but a
	# ball launched hard by a fold must not pass through a one-cell floor.
	var ball := {"pos": Vector2(32, 32), "vel": Vector2(0, 6000), "resting": false}
	for _i in range(120):
		ball = WorldCore.hand_ball_step(ball, _mini_solids(), 1.0 / 60.0)
	assert_lt(Vector2(ball["pos"]).y, 192.0, "Still above the floor it was fired at")


func test_a_ball_rolls_down_a_slope() -> void:
	# Landing on a slope must not stick. This is the whole of "it rolls".
	var ball := _run_ball(Vector2(100, 100), Vector2.ZERO, _slope_solids(), 400)
	assert_gt(Vector2(ball["pos"]).x, 100.0 + 8.0, "It slid downhill, to the right")


func test_a_ball_on_a_slope_ends_up_below_where_it_landed() -> void:
	var ball := _run_ball(Vector2(100, 100), Vector2.ZERO, _slope_solids(), 400)
	assert_gt(Vector2(ball["pos"]).y, 100.0, "Downhill is also downward")


func test_a_ball_on_flat_ground_does_not_roll() -> void:
	# Rolling comes from the slope, not from a drift baked into the step: dropped
	# straight down onto flat floor, it lands where it was dropped.
	var ball := _run_ball(Vector2(32, 32), Vector2.ZERO, _mini_solids())
	assert_almost_eq(Vector2(ball["pos"]).x, 32.0, 2.0, "No sideways wander on the flat")


func test_a_rolling_ball_eventually_settles() -> void:
	# Friction has to actually win, or a hand rolls forever and never becomes a pickup.
	var ball := _run_ball(Vector2(100, 100), Vector2.ZERO, _slope_solids(), 3000)
	assert_true(bool(ball["resting"]), "It stops at the bottom rather than rolling forever")


func test_a_ball_wedged_in_a_corner_still_comes_to_rest() -> void:
	# REGRESSION. A ball rolling into the corner at the foot of a slope used to pin
	# itself there forever: contact resolution left it holding a velocity every
	# direction of which was blocked, so the speed-based rest test never fired and the
	# position never changed either. A hand doing that is a hand that can never be
	# collected. Rest is therefore judged on PROGRESS, not on the velocity vector.
	var ball := _run_ball(Vector2(100, 100), Vector2.ZERO, _slope_solids(), 3000)
	assert_true(bool(ball["resting"]), "It settles in the corner instead of buzzing in it")
	assert_almost_eq(Vector2(ball["vel"]).length(), 0.0, 0.001,
		"...with its velocity actually cleared")


func test_a_ball_with_no_floor_keeps_falling_and_never_rests() -> void:
	# Over void there is nothing to rest on. The WORLD decides what to do about that
	# (it is the same "nowhere to land" case a drop already handles); the physics just
	# must not invent a floor.
	var ball := _run_ball(Vector2(32, 32), Vector2.ZERO, [], 200)
	assert_false(bool(ball["resting"]), "Nothing to come to rest on")
	assert_gt(Vector2(ball["pos"]).y, 32.0, "Still going down")


func test_a_balls_velocity_is_untouched_by_a_translation() -> void:
	# Folds are translations, so a ball folded into a subspace keeps flying exactly as
	# it was. This is what makes transporting one through `BaseFrame` correct: only its
	# POSITION moves, and the physics is position-independent.
	var a := WorldCore.hand_ball_step(
		{"pos": Vector2(32, 32), "vel": Vector2(120, -80), "resting": false}, [], 1.0 / 60.0)
	var shift := Vector2(4096, -2048)
	var b := WorldCore.hand_ball_step(
		{"pos": Vector2(32, 32) + shift, "vel": Vector2(120, -80), "resting": false},
		[], 1.0 / 60.0)
	assert_almost_eq(Vector2(a["vel"]).distance_to(Vector2(b["vel"])), 0.0, 0.001,
		"Same velocity wherever it is")
	assert_almost_eq((Vector2(a["pos"]) + shift).distance_to(Vector2(b["pos"])), 0.0, 0.001,
		"...and the same step")


func test_support_is_lost_when_the_ground_goes_away() -> void:
	# What a fold has to ask of every resting hand afterwards: are you still on
	# something? The answer is what wakes it.
	var ball := _run_ball(Vector2(32, 32), Vector2.ZERO, _mini_solids())
	assert_true(WorldCore.hand_ball_supported(Vector2(ball["pos"]), _mini_solids()),
		"Resting on the floor, it is supported")
	assert_false(WorldCore.hand_ball_supported(Vector2(ball["pos"]), []),
		"Take the floor away and it is not")


func test_a_hand_dropped_in_midair_falls_to_the_floor() -> void:
	var at := WorldCore.settle_hand(Vector2(32, 32), _mini_solids())
	assert_almost_eq(at.x, 32.0, 0.01, "It falls straight down, not sideways")
	assert_almost_eq(at.y, 192.0 - WorldCore.HAND_CLEARANCE, 1.0,
		"It comes to rest just above the floor")


func test_a_landed_hand_hovers_rather_than_sinking_into_the_floor() -> void:
	# "Floating slightly above" is the whole look: a hand half-buried in the ground
	# reads as a bug, and one resting exactly ON it reads as a decal.
	var at := WorldCore.settle_hand(Vector2(32, 32), _mini_solids())
	assert_lt(at.y, 192.0, "Above the surface, not in it")
	assert_gt(WorldCore.HAND_CLEARANCE, 0.0, "...by a real gap")
	assert_false(WorldCore.circle_overlaps_solids(at, 1.0, _mini_solids()),
		"Nothing solid where it rests")


func test_a_hand_dropped_inside_a_wall_is_pushed_out_of_it() -> void:
	# The wall block at (2,1) spans x 128..192, y 64..128.
	var solids := _mini_solids()
	var inside := Vector2(160, 96)
	assert_true(WorldCore.circle_overlaps_solids(inside, WorldCore.HAND_CLEARANCE, solids),
		"The drop point really is inside the wall")
	var at := WorldCore.settle_hand(inside, solids)
	assert_false(WorldCore.circle_overlaps_solids(at, 1.0, solids),
		"It ends up somewhere you can see it")
	assert_lt(at.distance_to(inside), 3.0 * CS, "...and near where it was dropped")


func test_a_hand_ejected_from_a_wall_comes_out_the_nearest_face() -> void:
	# Near the top of the block, so up is much the shortest way out. A hand that
	# squeezed out of the far side would look like a different hand.
	var at := WorldCore.settle_hand(Vector2(160, 70), _mini_solids())
	assert_lt(at.y, 64.0, "Out through the top it was nearly touching")


func test_a_hand_already_at_rest_does_not_move() -> void:
	# Idempotence matters: a hand's resting spot is stored, and re-settling it on a
	# rebuild must not walk it a little further each time.
	var solids := _mini_solids()
	var once := WorldCore.settle_hand(Vector2(32, 32), solids)
	var twice := WorldCore.settle_hand(once, solids)
	assert_almost_eq(once.distance_to(twice), 0.0, 0.5, "Settling a settled hand is a no-op")


func test_a_hand_over_a_long_drop_does_not_fall_forever() -> void:
	# Bounded on purpose: over void there is no floor to find, and a hand that fell
	# out of the world would be the one way this system loses one.
	var at := WorldCore.settle_hand(Vector2(32, 32), [])
	assert_almost_eq(at.y, 32.0 + WorldCore.HAND_MAX_DROP, 1.0,
		"With no floor at all it stops at the end of its reach")


func test_settling_finds_a_ledge_rather_than_the_ground_below_it() -> void:
	# Dropped over the wall block, it lands on TOP of it — the first surface under
	# the hand, not the lowest one.
	var at := WorldCore.settle_hand(Vector2(160, 20), _mini_solids())
	assert_almost_eq(at.y, 64.0 - WorldCore.HAND_CLEARANCE, 1.0, "It rests on the ledge")


func test_hand_drift_seed_is_per_hand_not_per_list_position() -> void:
	# The trap this exists to avoid: seeding by index into `loose_hands` means every
	# remaining hand jumps to a new phase the moment a DIFFERENT one is picked up.
	# A seed made of the tile and the point on it cannot do that.
	var a := WorldCore.hand_drift_seed(7, Vector2(32, 32))
	var b := WorldCore.hand_drift_seed(9, Vector2(32, 32))
	assert_ne(a, b, "Two tiles, two phases")
	var c := WorldCore.hand_drift_seed(7, Vector2(48, 20))
	assert_ne(a, c, "...and two hands on ONE tile still differ")
	assert_eq(a, WorldCore.hand_drift_seed(7, Vector2(32, 32)),
		"The same hand always gets the same phase")


func test_anchors_valid_rejects_only_the_degenerate_pair() -> void:
	# There is no minimum distance any more. The only impossible pair is two anchors
	# on one cell, which has no crease direction at all.
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(6, 3)), "Same row, far apart")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(2, 8)), "Same column")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(4, 5)), "Off-axis (diagonal)")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(0, 3)), "Direction irrelevant")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(3, 3)),
		"Neighbouring cells make a one-cell fold, which is a fold")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(3, 4)),
		"...and so does a diagonal neighbour")
	assert_false(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(2, 3)),
		"Both on one cell has no crease direction — the one refusal left")


func test_arms_reach_is_a_square_of_nine_cells_not_four_directions() -> void:
	# Arm's length is every cell within one of the one you stand in, diagonals and your
	# own included. The four-way version was a limit of the input, not of your arm.
	var here := Vector2i(4, 12)
	var inside := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var d := Vector2i(dx, dy)
			var far := maxi(absi(dx), absi(dy))
			if WorldCore.within_anchor_reach(here, here + d, 1):
				inside += 1
				assert_true(far <= 1, "%s is inside the square" % d)
			else:
				assert_true(far > 1, "%s is outside it" % d)
	assert_eq(inside, 9, "Nine cells: the eight around you and the one you are on")


func test_the_reach_clamp_pulls_a_cell_back_per_axis() -> void:
	# The cursor clamps rather than refusing a step, so pushing at the edge of your
	# reach is a no-op rather than a rejection — and stepping diagonally off a corner
	# still moves along the axis that has room.
	var here := Vector2i(4, 12)
	assert_eq(WorldCore.clamp_to_anchor_reach(here, Vector2i(5, 11), 1), Vector2i(5, 11),
		"A cell already inside the square is left alone")
	assert_eq(WorldCore.clamp_to_anchor_reach(here, Vector2i(6, 12), 1), Vector2i(5, 12),
		"One cell too far right comes back to the edge")
	assert_eq(WorldCore.clamp_to_anchor_reach(here, Vector2i(9, 20), 1), Vector2i(5, 13),
		"Far outside clamps to the nearest corner, per axis")
	assert_eq(WorldCore.clamp_to_anchor_reach(here, Vector2i(6, 11), 1), Vector2i(5, 11),
		"...and the axis with room keeps the step the axis without it lost")


func test_a_one_cell_fold_is_geometrically_sound() -> void:
	# The distance rule used to hide this case; with it gone, the narrowest fold has
	# to actually work.
	var bg := WorldCore.parse_map(["........", "########"], CS)
	var pieces := FoldReplay.identity_pieces(bg)
	var fold := Fold.create(0, Vector2i(2, 0), Vector2i(3, 0), CS)
	assert_gt(fold.gap_distance(), 0.0, "A one-cell pair has a real gap")
	var dropped := WorldCore.capture_strip(pieces, fold, CS)
	assert_gt(dropped.size(), 0, "...and excises a one-cell strip")
	var folded := FoldReplay.apply_one_fold(pieces, fold, CS)
	assert_gt(folded.size(), 0, "...leaving a world behind")


# ---------------------------------------------------------------------------
# Registry-driven tile behavior
# ---------------------------------------------------------------------------

func test_parse_map_reads_every_authoring_character() -> void:
	var bg := WorldCore.parse_map(["#G~P_XT."], CS)
	assert_eq(bg.tile_at(Vector2i(0, 0)).type, TileTypes.WALL, "# is wall")
	assert_eq(bg.tile_at(Vector2i(1, 0)).type, TileTypes.GOAL, "G is goal")
	assert_eq(bg.tile_at(Vector2i(2, 0)).type, TileTypes.WATER, "~ is water")
	assert_eq(bg.tile_at(Vector2i(3, 0)).type, TileTypes.PIN, "P is a pin")
	assert_eq(bg.tile_at(Vector2i(4, 0)).type, TileTypes.UNANCHORABLE_FLOOR, "_ is unanchorable floor")
	assert_eq(bg.tile_at(Vector2i(5, 0)).type, TileTypes.UNANCHORABLE_WALL, "X is unanchorable wall")
	assert_eq(bg.tile_at(Vector2i(6, 0)).type, TileTypes.TRIGGER_FOLD, "T is a fold trigger")
	assert_eq(bg.tile_at(Vector2i(7, 0)).type, TileTypes.EMPTY, ". is air")


func test_parse_map_attaches_per_tile_data() -> void:
	var bg := WorldCore.parse_map(["..T."], CS, {"2,0": {"channel": "A", "anchors": [[0, 0], [3, 0]]}})
	var t := bg.tile_at(Vector2i(2, 0))
	assert_eq(t.data.get("channel", ""), "A", "per-tile params reach the tile")
	assert_eq((t.data.get("anchors", []) as Array).size(), 2, "anchor pair preserved")


func test_solid_polys_follow_the_registry() -> void:
	# Walls and both unanchorable-wall/pin types are solid; floor/water/goal are not.
	var bg := WorldCore.parse_map(["#~G_XP."], CS)
	var pieces := FoldReplay.derive_pieces(bg, [])
	assert_eq(WorldCore.solid_polys_of(pieces).size(), 3,
		"wall, unanchorable wall and pin are solid; floor, water, goal and air are not")


func test_polys_of_type_selects_one_type() -> void:
	var bg := WorldCore.parse_map(["G.G."], CS)
	var pieces := FoldReplay.derive_pieces(bg, [])
	assert_eq(WorldCore.polys_of_type(pieces, TileTypes.GOAL).size(), 2, "both goals selected")


func test_can_anchor_at_rejects_unanchorable_tiles() -> void:
	var bg := WorldCore.parse_map(["#_X."], CS)
	var index := BaseFrame.index_by_pos(FoldReplay.derive_pieces(bg, []))
	assert_true(WorldCore.can_anchor_at(index, Vector2i(0, 0)), "an ordinary wall can be gripped")
	assert_false(WorldCore.can_anchor_at(index, Vector2i(1, 0)), "unanchorable floor refuses a grip")
	assert_false(WorldCore.can_anchor_at(index, Vector2i(2, 0)), "unanchorable wall refuses a grip")
	assert_false(WorldCore.can_anchor_at(index, Vector2i(9, 0)), "void has nothing to grip")


func test_fold_blocked_by_a_pin_in_the_span() -> void:
	# A PIN cannot be excised or cut: the space it holds can never be folded away.
	var bg := WorldCore.parse_map(["...P...."], CS)
	var pieces := FoldReplay.derive_pieces(bg, [])
	var over_pin := Fold.create(0, Vector2i(1, 0), Vector2i(5, 0), CS)
	assert_true(WorldCore.fold_blocked_by_tile(pieces, over_pin, CS),
		"a fold whose strip swallows the pin is refused")
	var clear := Fold.create(1, Vector2i(4, 0), Vector2i(7, 0), CS)
	assert_false(WorldCore.fold_blocked_by_tile(pieces, clear, CS),
		"a fold clear of the pin is allowed")


func test_ordinary_walls_do_not_block_folds() -> void:
	var bg := WorldCore.parse_map(["...#...."], CS)
	var pieces := FoldReplay.derive_pieces(bg, [])
	var f := Fold.create(0, Vector2i(1, 0), Vector2i(5, 0), CS)
	assert_false(WorldCore.fold_blocked_by_tile(pieces, f, CS),
		"only blocks_fold types stop a fold — walls fold away normally")


# ---------------------------------------------------------------------------
# Camera framing
# ---------------------------------------------------------------------------

const VIEW := Vector2(1280, 720)


func _zoom(ctx: Dictionary) -> float:
	var full := {"viewport": VIEW, "center": Vector2.ZERO}
	full.merge(ctx, true)
	return WorldCore.camera_zoom_for(full)


func test_camera_rests_wider_than_one_to_one() -> void:
	var z := _zoom({})
	assert_eq(z, WorldCore.ZOOM_RESTING, "Nothing happening: the camera sits at its resting zoom")
	assert_lt(z, 1.0, "Resting shows MORE than the raw design scale")


func test_camera_widens_with_motion() -> void:
	var still := _zoom({"motion": 0.0})
	var running := _zoom({"motion": 0.45})
	var falling := _zoom({"motion": 1.0})
	assert_lt(running, still, "Moving pulls the frame out")
	assert_lt(falling, running, "All-out motion pulls it out further")
	assert_gt(falling, WorldCore.ZOOM_WIDEST * 0.999, "Motion alone never blows past the floor")


func test_camera_ignores_focus_points_that_already_fit() -> void:
	# A couple of cells away is well inside the resting frame; the camera should
	# not twitch for every anchor pinned at arm's length.
	var near := _zoom({"focus": PackedVector2Array([Vector2(2.0 * CS, 0)])})
	assert_eq(near, WorldCore.ZOOM_RESTING, "A point already on screen changes nothing")


func test_camera_widens_to_keep_a_far_focus_point_on_screen() -> void:
	var far := Vector2(13.0 * CS, 0)
	var z := _zoom({"focus": PackedVector2Array([far])})
	assert_lt(z, WorldCore.ZOOM_RESTING, "A distant anchor pulls the frame out")
	assert_lt(far.x + WorldCore.ZOOM_FOCUS_MARGIN, VIEW.x * 0.5 / z + 0.01,
		"...far enough out that the point is actually in frame, with its margin")


func test_camera_framing_is_governed_by_the_tightest_axis() -> void:
	# The window is wider than it is tall, so the same offset in y binds harder
	# than it does in x.
	var o := 7.0 * CS
	var wide := _zoom({"focus": PackedVector2Array([Vector2(o, 0)])})
	var tall := _zoom({"focus": PackedVector2Array([Vector2(0, o)])})
	assert_lt(tall, wide, "Height is the binding constraint at 16:9")
	assert_eq(_zoom({"focus": PackedVector2Array([Vector2(o, o)])}), tall,
		"Both at once is governed by whichever axis is tightest")


func test_camera_measures_focus_from_the_camera_not_the_span() -> void:
	# The camera sits at `center`, not at the middle of the focus set: two points
	# 5 cells apart but both well off to one side must be framed by their
	# DISTANCE, not by the 5-cell span between them.
	var pair := PackedVector2Array([Vector2(8.0 * CS, 0), Vector2(13.0 * CS, 0)])
	var offset := _zoom({"center": Vector2.ZERO, "focus": pair})
	var centred := _zoom({"center": Vector2(10.5 * CS, 0), "focus": pair})
	assert_lt(offset, centred, "Points far from the camera need a wider frame than a tight span")


func test_camera_never_leaves_its_bounds() -> void:
	var absurd := _zoom({"motion": 1.0, "widen": 1.0,
		"focus": PackedVector2Array([Vector2(400.0 * CS, 400.0 * CS)])})
	assert_eq(absurd, WorldCore.ZOOM_WIDEST, "A region-spanning fold clamps at the floor")
	assert_eq(_zoom({"motion": -5.0, "widen": -5.0}), WorldCore.ZOOM_RESTING,
		"Nothing can pull the frame TIGHTER than resting")


func test_camera_widen_pulls_out_during_a_fold() -> void:
	assert_lt(_zoom({"widen": 1.0}), _zoom({"widen": 0.0}),
		"The world rearranging is its own reason to step back")


func test_camera_view_radius_covers_the_frame_corner() -> void:
	# Everything drawn must reach the corner of the frame, or the repeated copies
	# inside a fold would visibly run out.
	var r := WorldCore.camera_view_radius(VIEW, 0.5)
	assert_almost_eq(r, Vector2(1280.0, 720.0).length(), 0.01,
		"At half zoom the visible half-diagonal is the full-scale diagonal")
	assert_gt(WorldCore.camera_view_radius(VIEW, 0.5), WorldCore.camera_view_radius(VIEW, 1.0),
		"Zooming out sees further")


# ---------------------------------------------------------------------------
# Camera lookahead
# ---------------------------------------------------------------------------

func _lead(ctx: Dictionary) -> Vector2:
	return WorldCore.camera_lookahead_for(ctx)


func test_standing_still_the_camera_leads_nowhere() -> void:
	assert_eq(_lead({}), Vector2.ZERO, "Nothing moving: the body sits in the middle")
	assert_eq(_lead({"velocity": Vector2.ZERO}), Vector2.ZERO, "Explicitly still, too")


func test_the_camera_leads_the_way_you_are_running() -> void:
	var right := _lead({"velocity": Vector2(1, 0)})
	assert_gt(right.x, 0.0, "Running right shows you what is to your right")
	assert_almost_eq(right.y, 0.0, 0.001, "...and nothing vertical, because you are level")
	assert_almost_eq(_lead({"velocity": Vector2(-1, 0)}).x, -right.x, 0.001,
		"Leftward is the mirror of rightward")


func test_lookahead_saturates_rather_than_tracking_speed_forever() -> void:
	# The lead is a FRACTION of full speed, not a multiple of velocity: past the
	# body's own limit there is nothing more to show, and a lead that kept growing
	# would push the body off its own frame.
	var half := _lead({"velocity": Vector2(0.5, 0)})
	var full := _lead({"velocity": Vector2(1.0, 0)})
	var absurd := _lead({"velocity": Vector2(9.0, 0)})
	assert_gt(full.x, half.x, "Faster leads further")
	assert_almost_eq(absurd.x, full.x, 0.001, "Beyond full speed the lead stops growing")
	assert_almost_eq(full.x, WorldCore.LOOKAHEAD_RUN, 0.001,
		"At a full run the lead is exactly its horizontal reach")


func test_falling_leads_further_than_rising() -> void:
	# Asymmetric on purpose: a fall is committed and you need to see the landing,
	# while the top of a jump is about to reverse — leading up there would swing
	# the frame down again a moment later.
	var down := _lead({"velocity": Vector2(0, 1)})
	var up := _lead({"velocity": Vector2(0, -1)})
	assert_gt(down.y, 0.0, "Falling shows you the ground you are heading for")
	assert_lt(up.y, 0.0, "Rising still leads up, a little")
	assert_gt(down.y, absf(up.y), "But a fall leads further than a rise")
	assert_almost_eq(down.y, WorldCore.LOOKAHEAD_FALL, 0.001,
		"A full-speed fall leads exactly its fall reach")


func test_holding_a_look_direction_leads_that_way_on_its_own() -> void:
	# Peering: hold up or down while standing still and the frame leans that way,
	# because wanting to see up there is a thing you can ask for without moving.
	var up := _lead({"look": -1.0})
	assert_lt(up.y, 0.0, "Holding up leans the frame up while you stand still")
	assert_almost_eq(up.y, -WorldCore.LOOKAHEAD_PEEK, 0.001, "...by its peek reach")
	assert_almost_eq(_lead({"look": 1.0}).y, WorldCore.LOOKAHEAD_PEEK, 0.001,
		"Holding down leans it down by the same amount")


func test_peeking_and_moving_add_but_stay_bounded() -> void:
	var both := _lead({"velocity": Vector2(0, 1), "look": 1.0})
	assert_gt(both.y, WorldCore.LOOKAHEAD_PEEK,
		"Looking down while falling leads further than either alone")
	assert_lt(both.y, WorldCore.LOOKAHEAD_FALL + WorldCore.LOOKAHEAD_PEEK + 0.001,
		"...but never past the sum of the two reaches")


func test_lookahead_is_flat_along_a_folded_band() -> void:
	# Inside a fold the strip repeats along the crease normal, so the frame is
	# already showing every copy there is in that direction: leading along it
	# would slide the view for nothing. Across the strip is what still moves.
	var n := Vector2(1, 0)
	var lead := _lead({"velocity": Vector2(1, 1), "flat_axis": n})
	assert_almost_eq(lead.dot(n), 0.0, 0.001, "No lead along the repeating axis")
	assert_gt(lead.y, 0.0, "The tangential component survives")


func test_lookahead_holds_still_while_the_world_rearranges() -> void:
	assert_eq(_lead({"velocity": Vector2(1, 1), "frozen": true}), Vector2.ZERO,
		"Riding a fold: the transition frames itself, and stale velocity leads nowhere")
