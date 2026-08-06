extends GutTest

## FoldLattice: the periodic structure of a space, and the rule by which it
## descends into a fold inside a fold. This is what makes nesting more than one
## layer deep a thing the renderer and the physics can both just ask about.

const CS := 64.0


func _fold(a: Vector2i, b: Vector2i) -> Fold:
	return Fold.create(0, a, b, CS)


func test_the_region_world_does_not_repeat() -> void:
	var lat := FoldLattice.flat()
	assert_true(lat.is_flat(), "A region is a plane, not a cylinder")
	assert_eq(lat.offsets(10000.0), [Vector2.ZERO], "One copy of everything")
	assert_eq(lat.wrap_delta(Vector2(9999, -9999)), Vector2.ZERO, "Nothing to wrap into")
	assert_eq(lat.free_axis(), Vector2.ZERO, "No band to run off the end of")


func test_one_fold_makes_a_cylinder() -> void:
	var f := _fold(Vector2i(10, 12), Vector2i(18, 12))
	var lat := FoldLattice.flat().push(f, CS)
	assert_eq(lat.depth(), 1, "One period")
	assert_eq(lat.periods()[0], Vector2(8 * CS, 0), "...exactly the span the fold excised")
	assert_almost_eq(lat.free_axis().abs(), Vector2(0, 1), Vector2(0.001, 0.001),
		"The band runs along the crease, and that is the way out of it")


func test_a_period_is_a_whole_number_of_cells_even_diagonally() -> void:
	# n * gap is exactly (anchor_b - anchor_a) * cell_size, so a diagonal crease
	# still lands its copies on the cell grid — and so on the art-pixel grid.
	var lat := FoldLattice.flat().push(_fold(Vector2i(4, 4), Vector2i(7, 9)), CS)
	assert_eq(lat.periods()[0], Vector2(3 * CS, 5 * CS), "Whole cells, not sqrt(34) of them")


func test_wrapping_folds_a_point_back_into_the_band() -> void:
	var f := _fold(Vector2i(10, 12), Vector2i(18, 12))
	var lat := FoldLattice.flat().push(f, CS)
	# The band spans x in [10.5, 18.5) cells.
	var out := Vector2(18.9 * CS, 12.5 * CS)
	assert_almost_eq(lat.wrap(out).x, (18.9 - 8.0) * CS, 0.01, "One band width back")
	assert_almost_eq(lat.wrap(Vector2(10.2 * CS, 0)).x, (10.2 + 8.0) * CS, 0.01,
		"...and the other way across the near glue")
	assert_eq(lat.wrap_delta(Vector2(13.5 * CS, 12.5 * CS)), Vector2.ZERO,
		"A point already in the band does not move")


func test_wrapping_crosses_as_many_copies_as_it_needs_to() -> void:
	# Not one band per call: a body flung far out of the domain (a fold landing it
	# there, a debug teleport) has to come all the way back, not one lap.
	var lat := FoldLattice.flat().push(_fold(Vector2i(10, 12), Vector2i(18, 12)), CS)
	var far := Vector2(10.5 * CS + 8.0 * CS * 5 + 30.0, 0)
	assert_almost_eq(lat.wrap(far).x, 10.5 * CS + 30.0, 0.01, "Five laps back in one step")


func test_a_perpendicular_inner_fold_makes_a_torus() -> void:
	# THE nested case. The outer fold's band runs vertically; folding across it
	# horizontally excises a strip that reaches both outer glue lines, so walking
	# along the outer normal still wraps — and now so does walking across it.
	var outer := _fold(Vector2i(10, 12), Vector2i(18, 12))     # normal +x
	var inner := _fold(Vector2i(12, 8), Vector2i(12, 11))      # normal +y
	var lat := FoldLattice.flat().push(outer, CS).push(inner, CS)
	assert_eq(lat.depth(), 2, "Two independent periods: you are on a torus")
	var ps: Array = lat.periods()
	assert_eq(ps[0], Vector2(8 * CS, 0), "The outer period survived")
	assert_eq(ps[1], Vector2(0, 3 * CS), "...alongside the inner one")
	assert_almost_eq(ps[0].dot(ps[1]), 0.0, 0.001, "Lattice axes are always orthogonal")
	assert_eq(lat.free_axis(), Vector2.ZERO, "Nowhere to run off a torus")


func test_a_parallel_inner_fold_stays_a_cylinder() -> void:
	# A band inside the band, not touching the glue: the outer identification is
	# not part of this space, so only the inner fold's period is left.
	var outer := _fold(Vector2i(10, 12), Vector2i(18, 12))
	var inner := _fold(Vector2i(12, 8), Vector2i(15, 8))       # normal +x, like the outer
	var lat := FoldLattice.flat().push(outer, CS).push(inner, CS)
	assert_eq(lat.depth(), 1, "One period — a cylinder inside a cylinder")
	assert_eq(lat.periods()[0], Vector2(3 * CS, 0), "...and it is the INNER fold's")


func test_a_diagonal_inner_fold_drops_every_inherited_period() -> void:
	var outer := _fold(Vector2i(10, 12), Vector2i(18, 12))
	var lat := FoldLattice.flat().push(outer, CS).push(_fold(Vector2i(2, 2), Vector2i(5, 5)), CS)
	assert_eq(lat.depth(), 1, "A crease at an angle to the glue keeps neither")


func test_a_torus_wraps_on_both_axes_at_once() -> void:
	var lat := FoldLattice.flat() \
		.push(_fold(Vector2i(10, 12), Vector2i(18, 12)), CS) \
		.push(_fold(Vector2i(12, 8), Vector2i(12, 11)), CS)
	# Domain: x in [10.5, 18.5), y in [8.5, 11.5) cells.
	var wrapped: Vector2 = lat.wrap(Vector2(19.0 * CS, 12.0 * CS))
	assert_almost_eq(wrapped.x, 11.0 * CS, 0.01, "Wrapped across x")
	assert_almost_eq(wrapped.y, 9.0 * CS, 0.01, "...and across y, in the same step")


func test_copies_fill_the_frame_and_start_at_home() -> void:
	var lat := FoldLattice.flat().push(_fold(Vector2i(10, 12), Vector2i(18, 12)), CS)
	var offs: Array = lat.offsets(3.0 * 8.0 * CS)
	assert_eq(offs[0], Vector2.ZERO, "The copy you are in is drawn first")
	assert_eq(offs.size(), 7, "Three either side of it")
	for off in offs:
		var k: float = float(off.x) / (8.0 * CS)
		assert_almost_eq(k, roundf(k), 0.001, "Every copy is a whole number of bands out")
		assert_almost_eq(float(off.y), 0.0, 0.001, "...along the period, and nowhere else")


func test_copies_are_capped_so_a_one_cell_torus_cannot_explode() -> void:
	# A one-cell fold repeats every 64 units; two of them square that. The cap is
	# what makes "as many copies as the frame can see" safe to ask for.
	var lat := FoldLattice.flat() \
		.push(_fold(Vector2i(10, 12), Vector2i(11, 12)), CS) \
		.push(_fold(Vector2i(4, 8), Vector2i(4, 9)), CS)
	var offs: Array = lat.offsets(4000.0, 121)
	assert_eq(offs.size(), 121, "Capped")
	assert_eq(offs[0], Vector2.ZERO, "...keeping the copy you are in")
	assert_lt(offs[1].length(), offs[120].length(), "...and the nearest ones first")


func test_neighbour_copies_are_what_the_colliders_need() -> void:
	var flat := FoldLattice.flat()
	assert_eq(flat.neighbour_offsets().size(), 1, "A flat world collides once")
	var cyl := flat.push(_fold(Vector2i(10, 12), Vector2i(18, 12)), CS)
	assert_eq(cyl.neighbour_offsets().size(), 3, "A cylinder needs the band either side")
	var torus := cyl.push(_fold(Vector2i(12, 8), Vector2i(12, 11)), CS)
	assert_eq(torus.neighbour_offsets().size(), 9, "A torus needs all eight around it")


func test_the_domain_edges_are_what_the_camera_frames() -> void:
	var f := _fold(Vector2i(10, 12), Vector2i(18, 12))
	var lat := FoldLattice.flat().push(f, CS)
	var here := Vector2(13.5 * CS, 12.5 * CS)
	var edges: PackedVector2Array = lat.domain_edges(here)
	assert_eq(edges.size(), 2, "A cylinder is framed glue to glue")
	assert_almost_eq(edges[0].x, 10.5 * CS, 0.01, "The near glue")
	assert_almost_eq(edges[1].x, 18.5 * CS, 0.01, "...and the far one")
	assert_eq(FoldLattice.flat().domain_edges(here).size(), 0,
		"A region has no domain to hold in view — only a world")


func test_the_domain_edges_follow_you_into_the_copy_you_are_in() -> void:
	# The body is wrapped every frame, but the camera asks about wherever it is
	# looking: the edges have to be the ones around THAT point, not around home.
	var lat := FoldLattice.flat().push(_fold(Vector2i(10, 12), Vector2i(18, 12)), CS)
	var edges: PackedVector2Array = lat.domain_edges(Vector2((13.5 + 8.0) * CS, 0))
	assert_almost_eq(edges[0].x, (10.5 + 8.0) * CS, 0.01, "One band along")
	assert_almost_eq(edges[1].x, (18.5 + 8.0) * CS, 0.01, "...and its far side")
