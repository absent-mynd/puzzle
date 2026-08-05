## BaseFrame tests — exact base <-> derived transport
##
## Every fragment satisfies `polygon == base_polygon + src_offset`. These tests pin the
## round trip that relies on it: a point in current space maps into base space and back
## into any other configuration. That is what carries the player, entities and pinned
## anchors through arbitrary fold/unfold sequences without crease arithmetic.

extends GutTest

const CELL := 64.0


func _base() -> BaseGrid:
	return BaseGrid.from_types(Vector2i(10, 10), CELL)


func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


func test_piece_at_finds_the_fragment_under_a_point():
	var base := _base()
	var pieces := FoldReplay.derive_pieces(base, [])
	var piece = BaseFrame.piece_at(pieces, _center(Vector2i(3, 4)), CELL)
	assert_not_null(piece, "a point inside the grid lands on a fragment")
	assert_eq(piece.plane_pos, Vector2i(3, 4), "and it is the fragment at that cell")


func test_piece_at_returns_null_over_void():
	var base := _base()
	var pieces := FoldReplay.derive_pieces(base, [])
	assert_null(BaseFrame.piece_at(pieces, Vector2(-500, -500), CELL),
		"a point outside all fragments is over void")


func test_identity_round_trip_is_a_no_op():
	var base := _base()
	var pieces := FoldReplay.derive_pieces(base, [])
	var p := _center(Vector2i(6, 2))
	var back = BaseFrame.transport(pieces, pieces, p, CELL)
	assert_not_null(back, "transport within one configuration resolves")
	assert_almost_eq(Vector2(back).distance_to(p), 0.0, 0.001,
		"transporting into the same configuration returns the same point")


func test_transport_follows_a_ridden_flap():
	# A point on the B-side flap is displaced by the fold's B shift.
	var base := _base()
	var before := FoldReplay.derive_pieces(base, [])
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var after := FoldReplay.derive_pieces(base, [f])
	var p := _center(Vector2i(8, 5))
	var moved = BaseFrame.transport(before, after, p, CELL)
	assert_not_null(moved, "the point survives the fold on its flap")
	assert_almost_eq(Vector2(moved).distance_to(p + f.shift_b_px(CELL)), 0.0, 0.001,
		"it lands exactly where its base tile did")


func test_transport_into_the_excised_strip_returns_null():
	var base := _base()
	var before := FoldReplay.derive_pieces(base, [])
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
	var after := FoldReplay.derive_pieces(base, [f])
	# (4,5) sits strictly between the creases: it is folded away.
	assert_null(BaseFrame.transport(before, after, _center(Vector2i(4, 5)), CELL),
		"a point in the excised strip has no surviving fragment")


func test_transport_survives_fold_then_unfold():
	var base := _base()
	var identity := FoldReplay.derive_pieces(base, [])
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var folded := FoldReplay.derive_pieces(base, [f])
	var p := _center(Vector2i(8, 5))
	var there = BaseFrame.transport(identity, folded, p, CELL)
	var back = BaseFrame.transport(folded, identity, there, CELL)
	assert_almost_eq(Vector2(back).distance_to(p), 0.001, 0.01,
		"a fold/unfold round trip returns the point to where it started")


func test_resolve_base_point_is_strict_about_cuts():
	# A door point exactly on a cut resolves nowhere: dormant until the halves rejoin.
	var base := _base()
	var pieces := FoldReplay.derive_pieces(base, [])
	var bid: int = base.tile_at(Vector2i(4, 4)).base_id
	assert_not_null(BaseFrame.resolve_base_point(pieces, bid, _center(Vector2i(4, 4))),
		"a point well inside its tile resolves")
	# The tile's own corner is on every edge — never strictly interior.
	assert_null(BaseFrame.resolve_base_point(pieces, bid, Vector2(4, 4) * CELL),
		"a point on the tile boundary is not strictly interior")


func test_world_point_from_base_returns_null_for_a_folded_away_tile():
	var base := _base()
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
	var folded := FoldReplay.derive_pieces(base, [f])
	var bid: int = base.tile_at(Vector2i(4, 5)).base_id
	assert_null(BaseFrame.world_point_from_base(folded, bid, _center(Vector2i(4, 5))),
		"an excised base tile has no current-space location")


func test_index_by_pos_groups_fragments_by_cell():
	var base := _base()
	var pieces := FoldReplay.derive_pieces(base, [])
	var index := BaseFrame.index_by_pos(pieces)
	assert_eq(index.size(), 100, "one entry per occupied plane cell")
	assert_eq((index[Vector2i(0, 0)] as Array).size(), 1, "one fragment per cell at identity")
