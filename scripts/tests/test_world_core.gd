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
	assert_gt(strip.size(), 0, "Strip capture yields fragments")
	var total := 0.0
	var wall_area := 0.0
	for entry in strip:
		var a: float = GeometryCore.polygon_area(entry.polygon)
		total += a
		if entry.type == BaseTile.TYPE_WALL:
			wall_area += a
	# Band is gap(192px) x full map height(256px); map is fully tiled.
	assert_almost_eq(total, 192.0 * 256.0, 1.0, "Captured area equals the band")
	# The band (x in 160..352) cuts the wall pair at (2,1),(3,1): 1.5 cells of
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
	assert_not_null(piece, "Point over a tile resolves to its fragment")
	var bp: Vector2 = start - piece.src_offset

	var folded := FoldReplay.apply_one_fold(pieces, fold, CS)
	var mapped = BaseFrame.world_point_from_base(folded, piece.base_id, bp)
	assert_not_null(mapped, "A-side base point survives the fold")
	assert_almost_eq(Vector2(mapped).x, start.x + 128.0, 0.01,
		"Mapped point rides shift_a exactly")

	var strip_point := Vector2(200, 50)  # in the excised band
	var strip_piece = BaseFrame.piece_containing(index, strip_point, CS)
	var gone = BaseFrame.world_point_from_base(
		folded, strip_piece.base_id, strip_point - strip_piece.src_offset)
	assert_null(gone, "Excised base point has no fragment after the fold")


func test_resolve_base_point_strict_disables_split_centers() -> void:
	var bg := _mini_grid()
	var pieces := FoldReplay.identity_pieces(bg)
	var bp := Vector2(96, 96)  # center of cell (1,1)
	var bid: int = bg.tile_at(Vector2i(1, 1)).base_id
	assert_not_null(BaseFrame.resolve_base_point(pieces, bid, bp),
		"Whole tile: center resolves")

	# A fold anchored ON the tile cuts it exactly through its center: the
	# point sits on the cut in every fragment -> dormant (null) everywhere.
	var fold := Fold.create(0, Vector2i(1, 1), Vector2i(4, 1), CS)
	var folded := FoldReplay.apply_one_fold(pieces, fold, CS)
	assert_null(BaseFrame.resolve_base_point(folded, bid, bp),
		"Center exactly on a crease resolves nowhere in the world")
	var strip := WorldCore.capture_strip(pieces, fold, CS)
	assert_null(BaseFrame.resolve_base_point(strip, bid, bp),
		"Nor in the strip: the split point is dormant until halves rejoin")


func test_segment_intersects_band() -> void:
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)  # band x in (160,352)
	assert_true(WorldCore.segment_intersects_band(
		Vector2(200, 0), Vector2(200, 100), fold), "Segment inside the band")
	assert_true(WorldCore.segment_intersects_band(
		Vector2(100, 50), Vector2(400, 50), fold), "Segment crossing the band")
	assert_false(WorldCore.segment_intersects_band(
		Vector2(100, 0), Vector2(100, 100), fold), "Segment left of the band")
	assert_false(WorldCore.segment_intersects_band(
		Vector2(160, 0), Vector2(160, 100), fold), "Segment ON a crease grazes, no block")


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


func test_anchors_valid_rules() -> void:
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(6, 3)), "Same row, gap>=2")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(2, 8)), "Same column, gap>=2")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(4, 5)),
		"Off-axis pair 2+ apart is a valid (diagonal) fold")
	assert_true(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(0, 3)), "Direction irrelevant")
	assert_false(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(3, 4)),
		"Adjacent diagonal (dist sqrt(2)) is too close")
	assert_false(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(3, 3)), "Gap 1 rejected")
	assert_false(WorldCore.anchors_valid(Vector2i(2, 3), Vector2i(2, 3)), "Same cell rejected")


# ---------------------------------------------------------------------------
# Registry-driven tile behavior
# ---------------------------------------------------------------------------

func test_parse_map_reads_every_authoring_character() -> void:
	var bg := WorldCore.parse_map(["#G~P_XTA."], CS)
	assert_eq(bg.tile_at(Vector2i(0, 0)).type, TileTypes.WALL, "# is wall")
	assert_eq(bg.tile_at(Vector2i(1, 0)).type, TileTypes.GOAL, "G is goal")
	assert_eq(bg.tile_at(Vector2i(2, 0)).type, TileTypes.WATER, "~ is water")
	assert_eq(bg.tile_at(Vector2i(3, 0)).type, TileTypes.PIN, "P is a pin")
	assert_eq(bg.tile_at(Vector2i(4, 0)).type, TileTypes.UNANCHORABLE_FLOOR, "_ is unanchorable floor")
	assert_eq(bg.tile_at(Vector2i(5, 0)).type, TileTypes.UNANCHORABLE_WALL, "X is unanchorable wall")
	assert_eq(bg.tile_at(Vector2i(6, 0)).type, TileTypes.TRIGGER_FOLD, "T is a fold trigger")
	assert_eq(bg.tile_at(Vector2i(7, 0)).type, TileTypes.ANCHOR_CACHE, "A is an anchor cache")
	assert_eq(bg.tile_at(Vector2i(8, 0)).type, TileTypes.EMPTY, ". is air")


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
		"a fold whose band swallows the pin is refused")
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
	# Everything drawn must reach the corner of the frame, or the repeated bands
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
	# already showing every band there is in that direction: leading along it
	# would slide the view for nothing. Across the band is what still moves.
	var n := Vector2(1, 0)
	var lead := _lead({"velocity": Vector2(1, 1), "flat_axis": n})
	assert_almost_eq(lead.dot(n), 0.0, 0.001, "No lead along the repeating axis")
	assert_gt(lead.y, 0.0, "The tangential component survives")


func test_lookahead_holds_still_while_the_world_rearranges() -> void:
	assert_eq(_lead({"velocity": Vector2(1, 1), "frozen": true}), Vector2.ZERO,
		"Riding a fold: the transition frames itself, and stale velocity leads nowhere")
