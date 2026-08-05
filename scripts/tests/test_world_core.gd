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
