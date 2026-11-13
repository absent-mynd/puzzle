extends GutTest

## TileBatch: every drawn piece of the sheet in as few canvas items as the
## materials allow. It carries the whole look of the world, so its invariants —
## one UV per vertex, indices that point at real vertices, sub-polygons that can
## actually be triangulated, and the wrap baked in — are worth stating.

const CS := 64.0

var batch: TileBatch
var grid: BaseGrid


func before_each() -> void:
	grid = WorldCore.parse_map([
		"....",
		"##.#",
		"####",
	], CS)
	batch = TileBatch.new()
	add_child_autofree(batch)
	batch.setup(TileAtlas.texture(), null, grid)


func _frags(pieces: Array) -> Array:
	var out: Array = []
	for piece in pieces:
		out.append({"piece": piece, "poly": piece.polygon})
	return out


func _all_pieces() -> Array:
	return FoldReplay.identity_pieces(grid)


func test_the_whole_sheet_becomes_two_canvas_items_at_most() -> void:
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	assert_lte(batch.layers().size(), 2,
		"One node for what stops you, one for what you move through — nothing more")
	assert_gt(batch.layers().size(), 0, "...and it did draw something")


func test_pieces_are_grouped_by_what_they_do_not_by_their_type() -> void:
	# Walkability, from the registry: a new blocking tile lands in the foreground
	# group without this file being touched.
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	var walls := 0
	var air := 0
	for piece in _all_pieces():
		if TileTypes.is_walkable(piece.type):
			air += 1
		else:
			walls += 1
	var counts: Array = []
	for vis in batch.layers():
		counts.append(vis.polygons.size())
	counts.sort()
	assert_eq(counts, [mini(walls, air), maxi(walls, air)],
		"Every piece is in exactly one of the two groups")


func test_every_vertex_carries_its_own_uv() -> void:
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	for vis in batch.layers():
		assert_eq(vis.uv.size(), vis.polygon.size(),
			"A piece's art comes from its own base tile, per vertex")


func test_sub_polygons_index_real_vertices_and_can_be_drawn() -> void:
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	for vis in batch.layers():
		var verts: PackedVector2Array = vis.polygon
		for idx in vis.polygons:
			assert_gte(idx.size(), 3, "A drawn shape needs three corners")
			var shape := PackedVector2Array()
			for i in idx:
				assert_between(i, 0, verts.size() - 1, "Index points at a real vertex")
				shape.append(verts[i])
			assert_gt(Geometry2D.triangulate_polygon(shape).size(), 0,
				"...and the shape it makes can actually be triangulated")


func test_the_wrap_is_baked_into_the_vertices() -> void:
	# Static content does not repeat through WrapCanvas — a copy of it costs
	# nothing but vertices, so the copies go in here.
	var one := _frags(_all_pieces())
	batch.rebuild(one, [Vector2.ZERO])
	var single := 0
	for vis in batch.layers():
		single += vis.polygons.size()

	var period := Vector2(4 * CS, 0)
	batch.rebuild(one, [Vector2.ZERO, period, -period])
	var tripled := 0
	for vis in batch.layers():
		tripled += vis.polygons.size()
	assert_eq(tripled, single * 3, "Three copies of the sheet, still in two nodes")


func test_a_copy_sits_exactly_one_period_from_the_original() -> void:
	var piece = _all_pieces()[0]
	var period := Vector2(4 * CS, 0)
	batch.rebuild([{"piece": piece, "poly": piece.polygon}], [Vector2.ZERO, period])
	var verts: PackedVector2Array = batch.layers()[0].polygon
	var n: int = piece.polygon.size()
	for i in range(n):
		assert_almost_eq(verts[n + i] - verts[i], period, Vector2(0.001, 0.001),
			"The copy is the original, moved by the period and nothing else")


func test_a_flap_moves_by_a_position_not_by_its_vertices() -> void:
	# Why the fold transition is cheap: a flap's shift is a translation, so it is
	# one assignment per frame however many pieces it carries.
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	var before: PackedVector2Array = batch.layers()[0].polygon
	batch.shift_group(LightRig.FG, Vector2(100, 0))
	assert_eq(batch.layers()[0].polygon, before, "No vertex was touched")


func test_deforming_applies_about_each_copys_own_position() -> void:
	# The strip of a fold collapses onto the meeting line — and inside a fold every
	# copy collapses onto ITS OWN seam, not all of them onto one. So the copy
	# offset comes off before the deformation and goes back on after.
	var piece = _all_pieces()[0]
	var period := Vector2(4 * CS, 0)
	batch.rebuild([{"piece": piece, "poly": piece.polygon}], [Vector2.ZERO, period])
	batch.deform(func(v: Vector2) -> Vector2: return v * 0.5)
	var verts: PackedVector2Array = batch.layers()[0].polygon
	var n: int = piece.polygon.size()
	for i in range(n):
		assert_almost_eq(verts[i], Vector2(piece.polygon[i]) * 0.5, Vector2(0.001, 0.001),
			"The original halved about the origin")
		assert_almost_eq(verts[n + i], Vector2(piece.polygon[i]) * 0.5 + period,
			Vector2(0.001, 0.001), "...and the copy halved about ITS origin, then replaced")


func test_rebuilding_replaces_rather_than_accumulates() -> void:
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	var first := batch.layers().size()
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	assert_eq(batch.layers().size(), first, "A rebuild is a replacement, not a second sheet")


func test_without_a_tileset_the_flat_colours_travel_per_vertex() -> void:
	# The fallback has to survive batching: a hundred types share one node now, so
	# a single `color` cannot say what each of them is.
	batch.setup(null, null, grid)
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	for vis in batch.layers():
		assert_null(vis.texture, "No tileset")
		assert_eq(vis.vertex_colors.size(), vis.polygon.size(),
			"...so every vertex carries its own type's colour")


func test_degenerate_pieces_are_dropped_rather_than_drawn() -> void:
	var piece = _all_pieces()[0]
	batch.rebuild([{"piece": piece, "poly": PackedVector2Array([Vector2.ZERO, Vector2.ONE])}],
		[Vector2.ZERO])
	assert_eq(batch.layers().size(), 0, "A sliver with two corners is not a shape")


# ---------------------------------------------------------------------------
# Ink: what rides in the vertex colour
# ---------------------------------------------------------------------------
#
# The lit shader draws a rim on what stops you and a contact shadow on what you move
# through. It can only do that from what the batch tells it per vertex, and all of it
# has to be a BASE-space fact — or a tile would be re-inked by whatever a fold happened
# to put beside it, and the seam would stop being a cut.

func _piece_at(cell: Vector2i, pieces: Array = []):
	var tile := grid.tile_at(cell)
	for piece in (pieces if not pieces.is_empty() else _all_pieces()):
		if piece.base_id == tile.base_id:
			return piece
	return null


func test_something_solid_is_inked_where_it_meets_open_space() -> void:
	# (0,1) is wall: air above it, wall to the right and below, the sheet's edge left.
	assert_eq(batch.ink_mask(_piece_at(Vector2i(0, 1))), TileBatch.UP | TileBatch.LEFT,
		"a rim where it faces air, and where the sheet itself ends")
	assert_eq(batch.ink_mask(_piece_at(Vector2i(1, 2))), TileBatch.DOWN,
		"buried on three sides: only the sheet's edge is a face")


func test_air_is_inked_where_something_solid_stands_against_it() -> void:
	# (2,1) is the notch in the wall: solid left, right and below.
	assert_eq(batch.ink_mask(_piece_at(Vector2i(2, 1))),
		TileBatch.RIGHT | TileBatch.DOWN | TileBatch.LEFT,
		"a shadow from each side something stands on")
	assert_eq(batch.ink_mask(_piece_at(Vector2i(0, 0))), TileBatch.DOWN,
		"open air over a floor: the edge of the sheet casts nothing")


func test_ink_does_not_change_when_the_sheet_is_folded() -> void:
	# Fold the notch's column away: the walls either side of it now touch. Their ink
	# must not notice — what was a face is still drawn as a face, which is why a seam
	# shows two rims meeting instead of healing over.
	var before: Dictionary = {}
	for piece in _all_pieces():
		before[piece.base_id] = batch.ink_mask(piece)
	var fold := Fold.create(0, Vector2i(1, 1), Vector2i(3, 1), CS)
	var folded := FoldReplay.derive_pieces(grid, [fold])
	assert_lt(folded.size(), _all_pieces().size(), "the fold took something away")
	for piece in folded:
		assert_eq(batch.ink_mask(piece), before[piece.base_id],
			"tile %d is inked as it was authored" % piece.base_id)


func test_a_vertex_knows_where_in_its_own_tile_it_sits() -> void:
	var piece = _piece_at(Vector2i(1, 1))
	var data := batch.tile_data(piece.polygon, piece)
	assert_eq(data.size(), piece.polygon.size())
	var origin := Vector2(1, 1) * CS
	for i in range(data.size()):
		var want := (Vector2(piece.polygon[i]) - origin) / CS
		assert_almost_eq(Vector2(data[i].b, data[i].a), want, Vector2(0.001, 0.001),
			"a whole tile's corners are the corners of the unit square")


func test_a_moved_or_cut_piece_still_reads_its_place_from_the_base() -> void:
	# The right half of base tile (1,1), carried two cells to the left by a fold. Where
	# it sits in ITS tile has not changed: the right half, 0.5 to 1.
	var piece := FoldedPiece.new(grid.tile_at(Vector2i(1, 1)).base_id, TileTypes.WALL)
	piece.src_offset = Vector2(-2 * CS, 0)
	var half := PackedVector2Array([
		Vector2(-0.5, 1) * CS, Vector2(0, 1) * CS, Vector2(0, 2) * CS, Vector2(-0.5, 2) * CS])
	var data := batch.tile_data(half, piece)
	var xs: Array = []
	for c in data:
		xs.append(snappedf(c.b, 0.01))
	xs.sort()
	assert_eq(xs, [0.5, 0.5, 1.0, 1.0], "the half it was cut from, not the half it landed on")


func test_rock_knows_how_deep_it_is_buried() -> void:
	# Depth is what lets a wall's face read against its mass: the surface is drawn as
	# authored and the rock behind it falls away into the dark.
	grid = WorldCore.parse_map([
		"......",
		"######",
		"######",
		"######",
		"######",
		"######",
	], CS)
	batch.setup(TileAtlas.texture(), null, grid)
	var depths: Array = []
	for y in range(6):
		depths.append(batch.ink_depth(_piece_at(Vector2i(2, y))))
	assert_eq(depths, [0, 0, 1, 2, TileBatch.MAX_DEPTH, TileBatch.MAX_DEPTH],
		"air and the surface are 0, each row behind it one more, and then it stops counting")
	assert_eq(batch.ink_depth(_piece_at(Vector2i(0, 3))), 2,
		"the edge of the sheet is not open air: rock runs dark into it")


func test_depth_travels_with_the_mask() -> void:
	grid = WorldCore.parse_map(["....", "####", "####", "####"], CS)
	batch.setup(TileAtlas.texture(), null, grid)
	var piece = _piece_at(Vector2i(1, 3))
	for c in batch.tile_data(piece.polygon, piece):
		assert_almost_eq(c.g, 2.0 / float(TileBatch.MAX_DEPTH), 0.001)
		assert_almost_eq(c.r, float(TileBatch.DOWN) / 15.0, 0.001)


func test_the_vertex_colour_is_data_only_when_something_will_read_it() -> void:
	# The lit material takes the vertex colour as data and clears it. With no rig
	# there is no such material, so data in that channel would simply tint the art.
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	for vis in batch.layers():
		for c in vis.vertex_colors:
			assert_eq(c, Color.WHITE, "no reader: the tileset arrives untinted")

	var rig := LightRig.new()
	add_child_autofree(rig)
	batch.setup(TileAtlas.texture(), rig, grid)
	batch.rebuild(_frags(_all_pieces()), [Vector2.ZERO])
	var carried := false
	for vis in batch.layers():
		assert_not_null(vis.material, "with a rig, the sheet is lit")
		assert_eq(vis.vertex_colors.size(), vis.polygon.size(), "one record per vertex")
		for c in vis.vertex_colors:
			carried = carried or c.r > 0.0
	assert_true(carried, "...and the ink travels with it")
