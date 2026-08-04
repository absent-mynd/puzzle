## Occupant tests — entities that ride base tiles through folds
##
## Consolidates what survived the pivot from the old split-on-unfold / footprint /
## carried-geometry suites. The grid-movement half of those tests went away with the
## step log; what remains is the part that was never about movement: how a body behaves
## when a fold cuts through it.
##
## An occupant "moving" is expressed directly here (its base_ids change), because in the
## continuous world movement is physics, not a replayed step.

extends GutTest

const CELL := 64.0
const FULL := CELL * CELL


func _base(types := {}, grid := Vector2i(10, 10)) -> BaseGrid:
	return BaseGrid.from_types(grid, CELL, types)


func _pieces(base: BaseGrid, folds: Array = []) -> Array:
	return FoldReplay.derive_pieces(base, folds)


func _state(base: BaseGrid, folds: Array = []) -> FoldedState:
	return FoldReplay.state_from_pieces(_pieces(base, folds))


func _occ_at(base: BaseGrid, cell: Vector2i) -> Dictionary:
	return Occupants.make(Occupants.KIND_ENTITY, [base.tile_at(cell).base_id] as Array[int])


func _area(polys: Array) -> float:
	var a := 0.0
	for p in polys:
		a += GeometryCore.polygon_area(p)
	return a


# ---------------------------------------------------------------------------
# Footprint
# ---------------------------------------------------------------------------

func test_whole_occupant_footprint_is_a_full_square():
	var base := _base()
	var occ := _occ_at(base, Vector2i(4, 5))
	var fp := Occupants.footprint(occ, _state(base), CELL)
	assert_eq(fp.size(), 1, "one polygon for a whole, unsplit occupant")
	assert_almost_eq(_area(fp), FULL, 1.0, "footprint area is a full cell")


func test_occupant_that_only_rode_keeps_a_full_footprint():
	var base := _base()
	var occ := _occ_at(base, Vector2i(8, 5))
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var pre := _state(base)
	var post := _state(base, [f])
	occ = Occupants.on_fold(occ, f, pre, post, CELL)
	assert_almost_eq(_area(Occupants.footprint(occ, post, CELL)), FULL, 1.0,
		"a body that rode a flap but was not cut keeps a full footprint")


func test_cut_occupant_footprint_is_the_surviving_flap():
	var base := _base()
	var occ := _occ_at(base, Vector2i(2, 5))
	var f := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	var area := _area(Occupants.footprint(occ, _state(base, [f]), CELL))
	assert_lt(area, FULL - 1.0, "a cut body's footprint is smaller than a full cell")
	assert_gt(area, 0.0, "but non-empty — the flap survives")


# ---------------------------------------------------------------------------
# Split on unfold
# ---------------------------------------------------------------------------

func test_fold_records_a_latent_for_the_hidden_half():
	var base := _base()
	var occ := _occ_at(base, Vector2i(3, 5))
	var f := Fold.create(0, Vector2i(3, 5), Vector2i(6, 5), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	assert_eq(occ["base_ids"].size(), 1, "one active body (the flap) after the fold")
	assert_eq(occ["latents"].size(), 1, "the folded-away half is remembered as a latent")


func test_unfold_after_moving_away_splits_the_occupant():
	# The survivor relocates while folded; unfolding re-materializes the hidden half at
	# its home tile, so the occupant ends up in two places.
	var base := _base()
	var occ := _occ_at(base, Vector2i(3, 5))
	var f := Fold.create(0, Vector2i(3, 5), Vector2i(6, 5), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	# The surviving body walks off to another tile.
	occ["base_ids"] = [base.tile_at(Vector2i(3, 2)).base_id] as Array[int]
	occ = Occupants.on_unfold(occ, f.fold_id, _state(base), CELL)
	assert_eq(occ["base_ids"].size(), 2, "the hidden half reappeared: the occupant is split")


func test_fold_then_unfold_without_moving_rejoins_whole():
	var base := _base()
	var occ := _occ_at(base, Vector2i(3, 5))
	var f := Fold.create(0, Vector2i(3, 5), Vector2i(6, 5), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	occ = Occupants.on_unfold(occ, f.fold_id, _state(base), CELL)
	assert_eq(occ["base_ids"].size(), 1, "rejoined to a single body, not split")
	assert_almost_eq(_area(Occupants.footprint(occ, _state(base), CELL)), FULL, 1.0,
		"and back to the whole cell")


func test_fully_excised_occupant_hides_then_reappears():
	# A body entirely inside the excised strip has no surviving flap: hidden until unfold.
	var base := _base()
	var occ := _occ_at(base, Vector2i(5, 5))
	var f := Fold.create(0, Vector2i(4, 5), Vector2i(6, 5), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	assert_true(Occupants.is_hidden(occ), "hidden while folded away")
	occ = Occupants.on_unfold(occ, f.fold_id, _state(base), CELL)
	assert_eq(Occupants.positions(occ, _state(base)), [Vector2i(5, 5)],
		"reappears exactly where it was")


func test_unrelated_fold_does_not_release_a_latent():
	var base := _base()
	var occ := _occ_at(base, Vector2i(5, 5))
	var f := Fold.create(0, Vector2i(4, 5), Vector2i(6, 5), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	occ = Occupants.on_unfold(occ, 99, _state(base, [f]), CELL)
	assert_true(Occupants.is_hidden(occ), "a different fold's unfold leaves the latent alone")


# ---------------------------------------------------------------------------
# Carried rigid geometry — cuts stay cut
# ---------------------------------------------------------------------------

func test_diagonal_fold_cuts_an_occupant_into_a_triangle():
	var base := _base()
	var occ := _occ_at(base, Vector2i(4, 4))
	var f := Fold.create(0, Vector2i(4, 4), Vector2i(6, 6), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	assert_almost_eq(_area(Occupants.footprint(occ, _state(base, [f]), CELL)), FULL / 2.0, 1.0,
		"the surviving half of a diagonally cut body is a triangle")


func test_unfold_restores_the_missing_half_geometry():
	var base := _base()
	var occ := _occ_at(base, Vector2i(4, 4))
	var f := Fold.create(0, Vector2i(4, 4), Vector2i(6, 6), CELL)
	occ = Occupants.on_fold(occ, f, _state(base), _state(base, [f]), CELL)
	# Survivor moves away, so the reappearing half comes back as its own body carrying
	# the cut geometry rather than rejoining.
	occ["base_ids"] = [base.tile_at(Vector2i(4, 1)).base_id] as Array[int]
	occ = Occupants.on_unfold(occ, f.fold_id, _state(base), CELL)
	assert_eq(occ["base_ids"].size(), 2, "two bodies after the split")
	var total := _area(Occupants.footprint(occ, _state(base), CELL))
	assert_gt(total, FULL / 2.0, "the two pieces together carry more than the surviving flap")


# ---------------------------------------------------------------------------
# Declaration from the base grid
# ---------------------------------------------------------------------------

func test_occupants_declared_in_base_data():
	var base := _base({
		Vector2i(2, 1): {"type": TileTypes.EMPTY, "occupant": "crate"},
		Vector2i(5, 1): {"type": TileTypes.EMPTY, "occupant": "anchor", "channel": "A"},
	})
	var occs := Occupants.from_base(base)
	assert_eq(occs.size(), 2, "both declared occupants materialize")
	assert_eq(Occupants.of_kind(occs, Occupants.KIND_ANCHOR).size(), 1, "one anchor marker")
	var anchor: Dictionary = Occupants.of_kind(occs, Occupants.KIND_ANCHOR)[0]
	assert_eq(anchor["channel"], "A", "anchor carries its channel")
	assert_false(anchor["collides"], "anchors are pure markers — they never collide")
	assert_true(Occupants.of_kind(occs, Occupants.KIND_ENTITY)[0]["collides"],
		"ordinary entities collide")
