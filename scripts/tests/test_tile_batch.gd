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
