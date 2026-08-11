## TileAtlas tests — the tileset and its base-space UVs
##
## Folds cut tiles into arbitrary polygons, so tiles cannot be blitted on a grid. The
## atlas maps a piece back to its BASE cell and reads the art from there. The tests
## that matter are the invariants that follow from that: a piece carries the patch of
## art it was cut from, a tile's look never changes because it was folded or ridden, and
## a cut piece gets a proper sub-rectangle of its tile — which is what makes the seam
## a clean cut through the art rather than a smear across it.

extends GutTest

const CELL := 64.0
const TP := PixelArt.TILE_PX


func _base() -> BaseGrid:
	return BaseGrid.from_types(Vector2i(10, 10), CELL)


func _piece_of(pieces: Array, base_id: int):
	for p in pieces:
		if p.base_id == base_id:
			return p
	return null


func _uv_of(piece, base: BaseGrid) -> PackedVector2Array:
	return TileAtlas.uv_for(piece.polygon, piece.src_offset,
		TileAtlas.kind_for(piece.type), TileAtlas.variant_for(piece.base_id), base.cell_size)


func _bounds(uv: PackedVector2Array) -> Rect2:
	var r := Rect2(uv[0], Vector2.ZERO)
	for v in uv:
		r = r.expand(v)
	return r


# ---------------------------------------------------------------------------
# Kinds and variants
# ---------------------------------------------------------------------------

func test_every_tile_type_maps_to_a_kind():
	for type in [TileTypes.EMPTY, TileTypes.WALL, TileTypes.WATER, TileTypes.GOAL,
			TileTypes.TRIGGER_FOLD, TileTypes.PIN, TileTypes.UNANCHORABLE_FLOOR,
			TileTypes.UNANCHORABLE_WALL]:
		var kind := TileAtlas.kind_for(type)
		assert_between(kind, 0, TileAtlas.KINDS - 1,
			"type %d draws from a real atlas row" % type)


func test_an_unknown_type_falls_back_to_paper():
	assert_eq(TileAtlas.kind_for(9999), TileAtlas.K_EMPTY,
		"an unregistered type draws as background rather than as garbage")


func test_open_sky_selects_the_edge_kind():
	assert_eq(TileAtlas.kind_for(TileTypes.WALL, true), TileAtlas.K_WALL_TOP,
		"a wall with air above it draws its lit cap")
	assert_eq(TileAtlas.kind_for(TileTypes.WALL, false), TileAtlas.K_WALL,
		"a buried wall does not")
	assert_eq(TileAtlas.kind_for(TileTypes.WATER, true), TileAtlas.K_WATER,
		"the edge kind is a wall affordance only")


func test_variants_are_in_range_and_stable_per_tile():
	for base_id in range(200):
		var v := TileAtlas.variant_for(base_id)
		assert_between(v, 0, TileAtlas.VARIANTS - 1, "variant %d is a real column" % v)
	assert_eq(TileAtlas.variant_for(37), TileAtlas.variant_for(37),
		"the same tile always draws the same variant")


func test_variants_actually_vary():
	var seen := {}
	for base_id in range(64):
		seen[TileAtlas.variant_for(base_id)] = true
	assert_gt(seen.size(), 1, "neighbouring tiles do not all land on one variant")


# ---------------------------------------------------------------------------
# UVs
# ---------------------------------------------------------------------------

func test_a_whole_tile_covers_its_whole_atlas_cell():
	var base := _base()
	var pieces := FoldReplay.derive_pieces(base, [])
	var piece = _piece_of(pieces, base.tile_at(Vector2i(3, 4)).base_id)
	var uv := _uv_of(piece, base)
	var kind := TileAtlas.kind_for(piece.type)
	var variant := TileAtlas.variant_for(piece.base_id)
	var origin := Vector2(variant, kind) * float(TP)
	var b := _bounds(uv)
	assert_almost_eq(b.position.distance_to(origin), 0.0, 0.05,
		"an uncut tile starts at its atlas cell's origin")
	assert_almost_eq(b.size.distance_to(Vector2(TP, TP)), 0.0, 0.05,
		"and spans the whole 16x16 tile")


func test_uvs_are_read_from_the_base_cell_not_the_plane_cell():
	# The piece for base tile (3,4) sits at plane (3,4); its UVs must not
	# depend on that. Same tile, same art, wherever a fold puts it.
	var base := _base()
	var identity := FoldReplay.derive_pieces(base, [])
	var bid: int = base.tile_at(Vector2i(8, 5)).base_id
	var before := _uv_of(_piece_of(identity, bid), base)

	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var folded := FoldReplay.derive_pieces(base, [fold])
	var after := _uv_of(_piece_of(folded, bid), base)

	assert_eq(before.size(), after.size(), "the ridden tile is still whole")
	for i in range(before.size()):
		assert_almost_eq(Vector2(before[i]).distance_to(Vector2(after[i])), 0.0, 0.05,
			"riding a flap moves the geometry and takes the art with it")


func test_a_cut_piece_gets_a_sub_rectangle_of_its_tile():
	# A diagonal crease cuts tiles mid-cell. Each piece must take the part of the
	# art it was cut from — never the whole tile squeezed into the piece.
	var base := _base()
	var fold := Fold.create(0, Vector2i(2, 2), Vector2i(5, 4), CELL)
	var pieces := FoldReplay.derive_pieces(base, [fold])
	var found_partial := false
	for piece in pieces:
		var uv := _uv_of(piece, base)
		if uv.is_empty():
			continue
		var kind := TileAtlas.kind_for(piece.type)
		var variant := TileAtlas.variant_for(piece.base_id)
		var origin := Vector2(variant, kind) * float(TP)
		var b := _bounds(uv)
		assert_true(b.position.x >= origin.x - 0.01 and b.position.y >= origin.y - 0.01,
			"no UV escapes its atlas cell to the left or above")
		assert_true(b.end.x <= origin.x + TP + 0.01 and b.end.y <= origin.y + TP + 0.01,
			"and none bleeds into the neighbouring tile")
		if b.size.x < float(TP) - 0.5 or b.size.y < float(TP) - 0.5:
			found_partial = true
	assert_true(found_partial, "a diagonal fold does produce partial pieces")


func test_a_degenerate_polygon_yields_no_uvs():
	assert_eq(TileAtlas.uv_for(PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
		Vector2.ZERO, TileAtlas.K_WALL, 0, CELL).size(), 0,
		"fewer than three vertices is not a piece")


func test_quad_uv_addresses_one_whole_tile():
	var uv := TileAtlas.quad_uv(TileAtlas.K_LAMP, 2)
	assert_eq(uv.size(), 4, "a quad has four corners")
	var b := _bounds(uv)
	assert_almost_eq(b.position.distance_to(Vector2(2, TileAtlas.K_LAMP) * float(TP)), 0.0, 0.05,
		"the quad starts at the requested row and column")
	assert_almost_eq(b.size.x, float(TP), 0.05, "and spans one tile")


func test_quad_polygon_is_centred_on_its_point():
	var poly := TileAtlas.quad_polygon(Vector2(100, 50), CELL)
	assert_eq(poly.size(), 4, "a quad has four corners")
	assert_almost_eq(GeometryCore.polygon_centroid(poly).distance_to(Vector2(100, 50)), 0.0,
		0.001, "a glyph quad is centred on the point it marks")


# ---------------------------------------------------------------------------
# The generated sheet
# ---------------------------------------------------------------------------

func test_the_sheet_is_laid_out_variants_by_kinds():
	var img := TileAtlas.build_image()
	assert_eq(img.get_width(), TileAtlas.VARIANTS * TP, "one column per variant")
	assert_eq(img.get_height(), TileAtlas.KINDS * TP, "one row per kind")


func test_generation_is_deterministic():
	assert_eq(TileAtlas.build_image().get_data(), TileAtlas.build_image().get_data(),
		"the tileset paints the same bytes every run — no RNG seeding order to depend on")


func test_solid_kinds_are_opaque_and_the_lamp_is_not():
	var img := TileAtlas.build_image()
	assert_almost_eq(img.get_pixel(0, TileAtlas.K_WALL * TP + 8).a, 1.0, 0.01,
		"a wall fills its cell")
	assert_almost_eq(img.get_pixel(0, TileAtlas.K_EMPTY * TP + 4).a, 1.0, 0.01,
		"so does the paper: folded-away space is a hole, unlit space is not")
	assert_almost_eq(img.get_pixel(0, TileAtlas.K_LAMP * TP).a, 0.0, 0.01,
		"the lamp glyph is a sprite on transparent ground")


func test_the_edge_tile_differs_from_the_plain_one():
	var img := TileAtlas.build_image()
	var plain := img.get_pixel(3, TileAtlas.K_WALL * TP)
	var capped := img.get_pixel(3, TileAtlas.K_WALL_TOP * TP)
	assert_gt(capped.get_luminance(), plain.get_luminance(),
		"the sky-facing cap is lit brighter than plain masonry")


func test_the_texture_loads():
	var texture := TileAtlas.texture()
	assert_not_null(texture, "the tileset resolves to a texture")
	assert_eq(texture.get_width(), TileAtlas.VARIANTS * TP, "at the expected size")
	assert_eq(TileAtlas.texture(), texture, "and is built once, then cached")


func test_base_colour_still_answers_for_every_type():
	# The untextured fallback path: if the atlas is unavailable the world still
	# draws, in the flat colours the tileset was painted from.
	assert_ne(TileAtlas.base_color(TileTypes.WALL), TileAtlas.base_color(TileTypes.PIN),
		"types stay distinguishable without the tileset")
	assert_eq(TileAtlas.base_color(9999), TileAtlas.PAPER,
		"an unknown type falls back to paper rather than to magenta")
