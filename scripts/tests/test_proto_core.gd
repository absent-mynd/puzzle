extends GutTest

## Tests for ProtoCore — the pure logic under the side-view (gravity)
## metroidvania prototype. Covers map parsing, free-position fold
## classification, strip capture for the subspace, unfold displacement,
## and the geometry-only collision helpers.

const CS := 64.0

const MINI_MAP := [
	"........",
	"..##....",
	"........",
	"########",
]


func _mini_grid() -> BaseGrid:
	return ProtoCore.parse_map(MINI_MAP, CS)


func test_parse_map_dimensions_and_types() -> void:
	var bg := _mini_grid()
	assert_eq(bg.grid_size, Vector2i(8, 4), "Grid should be 8x4")
	assert_eq(bg.tiles.size(), 32, "Every position materializes a tile")
	assert_eq(bg.tile_at(Vector2i(2, 1)).type, BaseTile.TYPE_WALL, "# is wall")
	assert_eq(bg.tile_at(Vector2i(0, 0)).type, BaseTile.TYPE_EMPTY, ". is empty")
	assert_eq(bg.tile_at(Vector2i(0, 3)).type, BaseTile.TYPE_WALL, "Ground row is wall")


func test_parse_map_pads_short_rows() -> void:
	var bg := ProtoCore.parse_map(["####", "."], CS)
	assert_eq(bg.grid_size, Vector2i(4, 2), "Width comes from the longest row")
	assert_eq(bg.tile_at(Vector2i(3, 1)).type, BaseTile.TYPE_EMPTY,
		"Short rows are padded with air")


func test_parse_map_goal_type() -> void:
	var bg := ProtoCore.parse_map(["..G."], CS)
	assert_eq(bg.tile_at(Vector2i(2, 0)).type, BaseTile.TYPE_GOAL, "G is goal")


func test_side_of_fold_classifies_flaps_and_strip() -> void:
	# Horizontal fold: anchors (2,1)-(5,1) => vertical creases at x=160 and x=352.
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)
	assert_eq(ProtoCore.side_of_fold(Vector2(100, 100), fold), -1, "Left of crease1 is A-side")
	assert_eq(ProtoCore.side_of_fold(Vector2(200, 50), fold), 0, "Between creases is the strip")
	assert_eq(ProtoCore.side_of_fold(Vector2(400, 200), fold), 1, "Right of crease2 is B-side")


func test_fold_then_unfold_shift_round_trips() -> void:
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)
	for start in [Vector2(100, 100), Vector2(420, 90)]:
		var side := ProtoCore.side_of_fold(start, fold)
		var folded: Vector2 = start + ProtoCore.fold_shift_for_side(side, fold, CS)
		var back: Vector2 = folded + ProtoCore.unfold_shift(folded, fold, CS)
		assert_almost_eq(back.x, start.x, 0.001, "Unfold returns the ridden point (x)")
		assert_almost_eq(back.y, start.y, 0.001, "Unfold returns the ridden point (y)")


func test_capture_strip_area_matches_excised_band() -> void:
	var bg := _mini_grid()
	var pieces := FoldReplay.identity_pieces(bg)
	var fold := Fold.create(0, Vector2i(2, 1), Vector2i(5, 1), CS)
	var strip := ProtoCore.capture_strip(pieces, fold, CS)
	assert_gt(strip.size(), 0, "Strip capture yields fragments")
	var total := 0.0
	var wall_area := 0.0
	for entry in strip:
		var a: float = GeometryCore.polygon_area(entry["polygon"])
		total += a
		if entry["type"] == BaseTile.TYPE_WALL:
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
	var strip := ProtoCore.capture_strip(pieces, fold, CS)
	var extent := ProtoCore.strip_extent(strip, Vector2(1, 0))
	assert_almost_eq(extent["min"], 160.0, 0.01, "Strip starts at crease 1 (unshifted)")
	assert_almost_eq(extent["max"], 352.0, 0.01, "Strip ends at crease 2 (unshifted)")


func test_circle_overlap_and_depenetrate() -> void:
	var box := PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)])
	assert_true(ProtoCore.circle_overlaps_polygon(Vector2(32, 32), 20.0, box),
		"Center inside polygon overlaps")
	assert_true(ProtoCore.circle_overlaps_polygon(Vector2(70, 32), 20.0, box),
		"Circle straddling an edge overlaps")
	assert_false(ProtoCore.circle_overlaps_polygon(Vector2(120, 32), 20.0, box),
		"Distant circle does not overlap")

	var free := ProtoCore.depenetrate(Vector2(32, 60), 20.0, [box])
	assert_ne(free, Vector2.INF, "Depenetration finds a free spot")
	assert_false(ProtoCore.circle_overlaps_solids(free, 20.0, [box]),
		"Found spot is actually free")


func test_anchors_valid_rules() -> void:
	assert_true(ProtoCore.anchors_valid(Vector2i(2, 3), Vector2i(6, 3)), "Same row, gap>=2")
	assert_true(ProtoCore.anchors_valid(Vector2i(2, 3), Vector2i(2, 8)), "Same column, gap>=2")
	assert_false(ProtoCore.anchors_valid(Vector2i(2, 3), Vector2i(3, 4)), "Diagonal rejected")
	assert_false(ProtoCore.anchors_valid(Vector2i(2, 3), Vector2i(3, 3)), "Gap 1 rejected")
	assert_false(ProtoCore.anchors_valid(Vector2i(2, 3), Vector2i(2, 3)), "Same cell rejected")
