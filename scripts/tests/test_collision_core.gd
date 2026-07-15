## CollisionCore unit tests (collision engine, Stage 1)
##
## Pins the shared fold-clip helper (incl. the pre-fold-frame convention for the dropped
## between-strip) and the navigable/containment/overlap predicates the movement gate
## relies on, plus determinism of the Geometry2D-backed helpers.

extends GutTest

const CELL := 64.0


func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


func _square(cell: Vector2i) -> PackedVector2Array:
	var o := Vector2(cell) * CELL
	return _rect(o.x, o.y, o.x + CELL, o.y + CELL)


# --- fold_polygons -----------------------------------------------------------

func test_fold_polygons_splits_a_between_b():
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)  # vertical creases x=160,352
	# A wide rect on row 5 spanning both creases -> A + between + B.
	var wide := _rect(100, 320, 400, 384)
	var res := CollisionCore.fold_polygons([wide], fold, CELL)
	assert_eq(res["a"].size(), 1, "one A-side fragment")
	assert_eq(res["b"].size(), 1, "one B-side fragment")
	assert_eq(res["dropped"].size(), 1, "one between fragment (dropped)")


func test_fold_polygons_dropped_is_pre_fold_frame():
	# Un-shifting A and B and re-adding the (pre-fold-frame) dropped strip must
	# reconstruct the original polygon's area — proving dropped is untranslated.
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var wide := _rect(100, 320, 400, 384)
	var orig_area := GeometryCore.polygon_area(wide)
	var res := CollisionCore.fold_polygons([wide], fold, CELL)
	var a_back := CollisionCore.translate_polys(res["a"], -fold.shift_a_px(CELL))
	var b_back := CollisionCore.translate_polys(res["b"], -fold.shift_b_px(CELL))
	var reunited := CollisionCore.union_all(a_back + res["dropped"] + b_back)
	assert_almost_eq(CollisionCore.region_net_area(reunited), orig_area, 1.0,
		"A(un-shifted) + between + B(un-shifted) reconstructs the original area")


func test_fold_polygons_wholly_on_a_flap_untouched_shape():
	# A cell fully on the A-side just translates by shift_a (no between/B).
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var res := CollisionCore.fold_polygons([_square(Vector2i(0, 5))], fold, CELL)
	assert_eq(res["a"].size(), 1, "A-side only")
	assert_eq(res["b"].size(), 0, "no B fragment")
	assert_eq(res["dropped"].size(), 0, "nothing excised")


# --- containment / overlap ---------------------------------------------------

func test_full_square_contained_in_full_navigable():
	var sq := _square(Vector2i(0, 0))
	assert_true(CollisionCore.footprint_contained([sq], [_square(Vector2i(0, 0))]),
		"a full square fits its full cell")


func test_full_square_not_contained_in_half_navigable():
	var sq := _square(Vector2i(0, 0))
	var half := _rect(0, 0, CELL / 2.0, CELL)  # left half only navigable
	assert_false(CollisionCore.footprint_contained([sq], [half]),
		"a full square does NOT fit a half-covered cell")


func test_half_square_contained_in_half_navigable():
	var half := _rect(0, 0, CELL / 2.0, CELL)
	assert_true(CollisionCore.footprint_contained([half], [half]),
		"a half fits the matching half")


func test_offset_half_not_contained_in_wrong_half():
	# Area suffices but SHAPE/position doesn't: a left-half body over a right-half region.
	var left := _rect(0, 0, CELL / 2.0, CELL)
	var right := _rect(CELL / 2.0, 0, CELL, CELL)
	assert_false(CollisionCore.footprint_contained([left], [right]),
		"equal area but disjoint placement -> not contained")


func test_contained_across_two_contiguous_navigable_halves():
	var sq := _square(Vector2i(0, 0))
	var left := _rect(0, 0, CELL / 2.0, CELL)
	var right := _rect(CELL / 2.0, 0, CELL, CELL)
	assert_true(CollisionCore.footprint_contained([sq], [left, right]),
		"a full square fits two contiguous halves (a fold merge seam)")


func test_footprints_overlap():
	var a := _rect(0, 0, 40, 40)
	var b := _rect(20, 20, 60, 60)
	var disjoint := _rect(100, 100, 140, 140)
	assert_true(CollisionCore.footprints_overlap([a], [b]), "overlapping rects overlap")
	assert_false(CollisionCore.footprints_overlap([a], [disjoint]), "disjoint rects don't")


func test_union_all_merges_contiguous_splits_disjoint():
	var left := _rect(0, 0, CELL / 2.0, CELL)
	var right := _rect(CELL / 2.0, 0, CELL, CELL)
	assert_eq(CollisionCore.union_all([left, right]).size(), 1, "contiguous halves merge to one")
	var far := _rect(500, 500, 540, 540)
	assert_eq(CollisionCore.union_all([left, far]).size(), 2, "disjoint pieces stay separate")


# --- centroid / cell / determinism ------------------------------------------

func test_cell_of_point():
	assert_eq(CollisionCore.cell_of_point(Vector2(70, 10), CELL), Vector2i(1, 0), "floors to cell")


func test_canon_is_winding_invariant():
	var cw := PackedVector2Array([Vector2(0, 0), Vector2(0, 64), Vector2(64, 64), Vector2(64, 0)])
	var ccw := PackedVector2Array([Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)])
	assert_eq(str(CollisionCore.canon(cw)), str(CollisionCore.canon(ccw)),
		"canon normalizes winding + start vertex to a single representation")


func test_fold_and_boolean_ops_are_deterministic():
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var wide := _rect(100, 320, 400, 384)
	var r1 := CollisionCore.fold_polygons([wide], fold, CELL)
	var r2 := CollisionCore.fold_polygons([wide], fold, CELL)
	assert_eq(str(r1), str(r2), "fold_polygons is deterministic")
	var u1 := CollisionCore.canon_all(CollisionCore.union_all([_rect(0, 0, 40, 64), _rect(30, 0, 64, 64)]))
	var u2 := CollisionCore.canon_all(CollisionCore.union_all([_rect(0, 0, 40, 64), _rect(30, 0, 64, 64)]))
	assert_eq(str(u1), str(u2), "canonicalized union is deterministic across runs")
