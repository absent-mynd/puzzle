## LightSource tests — lights as occupants of the sheet
##
## A light has no world position. It has a base identity and a point inside that tile,
## and where it burns is always a question asked of the current piece list. These
## tests pin the consequences the design rests on: fold a light away and it leaves the
## world entirely, but it is still there inside the fold; fold something else and it
## rides the flap that carried its tile.

extends GutTest

const CELL := 64.0


func _base() -> BaseGrid:
	return BaseGrid.from_types(Vector2i(10, 10), CELL)


func _light_at(cell: Vector2i, base: BaseGrid) -> LightSource:
	var light := LightSource.new()
	light.id = "L"
	light.cell = cell
	light.bind(base)
	return light


func test_bind_takes_the_base_identity_and_the_tile_centre():
	var base := _base()
	var light := _light_at(Vector2i(3, 4), base)
	assert_true(light.is_bound(), "a light on an in-bounds cell binds")
	assert_eq(light.base_id, base.tile_at(Vector2i(3, 4)).base_id, "it takes the tile's id")
	assert_almost_eq(light.bp.distance_to(Vector2(3.5, 4.5) * CELL), 0.0, 0.001,
		"and sits at the tile's centre by default")


func test_bind_refuses_a_cell_outside_the_grid():
	var light := LightSource.new()
	light.cell = Vector2i(99, 99)
	assert_false(light.bind(_base()), "an out-of-bounds light does not bind")
	assert_false(light.is_bound(), "and stays unbound rather than half-placed")


func test_offset_places_the_light_within_its_tile():
	var base := _base()
	var light := LightSource.new()
	light.cell = Vector2i(2, 2)
	light.offset = Vector2(0.25, 0.75)
	light.bind(base)
	assert_almost_eq(light.bp.distance_to(Vector2(2.25, 2.75) * CELL), 0.0, 0.001,
		"the authored offset is in cell units within the tile")


func test_an_unfolded_light_burns_where_it_was_placed():
	var base := _base()
	var light := _light_at(Vector2i(3, 4), base)
	var pos = light.position_in(FoldReplay.derive_pieces(base, []))
	assert_not_null(pos, "with no folds the light resolves")
	assert_almost_eq(Vector2(pos).distance_to(Vector2(3.5, 4.5) * CELL), 0.0, 0.001,
		"at its authored position")


func test_a_folded_away_light_is_not_in_the_world():
	# The strip strictly between the creases is excised: the light goes with it.
	var base := _base()
	var light := _light_at(Vector2i(4, 5), base)
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
	assert_null(light.position_in(FoldReplay.derive_pieces(base, [fold])),
		"a light whose tile is folded away has no place in the world")


func test_a_folded_away_light_burns_inside_the_fold():
	# Same fold, but asked of the strip content — the subspace the player is
	# pinched into. This is the whole point: the lamp did not go out, it moved.
	var base := _base()
	var light := _light_at(Vector2i(4, 5), base)
	var identity := FoldReplay.derive_pieces(base, [])
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
	var strip := WorldCore.capture_strip(identity, fold, CELL)
	var pos = light.position_in(strip)
	assert_not_null(pos, "the light resolves against the excised strip")
	assert_almost_eq(Vector2(pos).distance_to(Vector2(4.5, 5.5) * CELL), 0.0, 0.001,
		"exactly where it stood before the fold swallowed it")


func test_a_light_rides_the_flap_its_tile_rides():
	var base := _base()
	var light := _light_at(Vector2i(8, 5), base)
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	var pos = light.position_in(FoldReplay.derive_pieces(base, [fold]))
	assert_not_null(pos, "a light outside the strip survives the fold")
	var expected := Vector2(8.5, 5.5) * CELL + fold.shift_b_px(CELL)
	assert_almost_eq(Vector2(pos).distance_to(expected), 0.0, 0.001,
		"and is displaced by exactly its flap's shift")


func test_a_light_returns_when_its_fold_is_dropped():
	var base := _base()
	var light := _light_at(Vector2i(4, 5), base)
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
	assert_null(light.position_in(FoldReplay.derive_pieces(base, [fold])), "folded away")
	var pos = light.position_in(FoldReplay.derive_pieces(base, []))
	assert_not_null(pos, "unfolding re-derives the light back into the world")
	assert_almost_eq(Vector2(pos).distance_to(Vector2(4.5, 5.5) * CELL), 0.0, 0.001,
		"at its original place")


func test_a_split_light_still_burns_on_its_half():
	# Unlike a door, a light cut through by a crease is not dormant: it resolves
	# non-strictly, onto whichever piece holds its point.
	var base := _base()
	var light := _light_at(Vector2i(7, 5), base)
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(5, 5), CELL)
	assert_not_null(light.position_in(FoldReplay.derive_pieces(base, [fold])),
		"a light keeps burning through a cut")


func test_resolve_all_skips_lights_that_are_not_here():
	var base := _base()
	var here := _light_at(Vector2i(8, 5), base)
	var gone := _light_at(Vector2i(4, 5), base)
	var fold := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
	var resolved := LightSource.resolve_all(
		FoldReplay.derive_pieces(base, [fold]), [here, gone])
	assert_eq(resolved.size(), 1, "only the surviving light is returned")
	assert_eq(resolved[0]["light"], here, "and it is the one outside the strip")


func test_unbound_lights_resolve_nowhere():
	var light := LightSource.new()
	light.cell = Vector2i(99, 99)
	light.bind(_base())
	assert_null(light.position_in(FoldReplay.derive_pieces(_base(), [])),
		"an unbound light never resolves, rather than resolving at the origin")


func test_radius_is_authored_in_cells():
	var light := LightSource.new()
	light.radius_cells = 5.0
	assert_almost_eq(light.radius_px(CELL), 320.0, 0.001,
		"radius converts to px against the cell size")


func test_round_trip_through_dict():
	var light := LightSource.new()
	light.id = "torch"
	light.cell = Vector2i(4, 7)
	light.offset = Vector2(0.25, 0.9)
	light.color = Color("#ff8844")
	light.radius_cells = 3.5
	light.energy = 1.2
	light.flicker = 0.3
	var copy := LightSource.from_dict(light.to_dict())
	assert_eq(copy.id, "torch", "id survives")
	assert_eq(copy.cell, Vector2i(4, 7), "cell survives")
	assert_almost_eq(copy.offset.distance_to(Vector2(0.25, 0.9)), 0.0, 0.001, "offset survives")
	assert_almost_eq(copy.color.r, light.color.r, 0.01, "colour survives")
	assert_almost_eq(copy.radius_cells, 3.5, 0.001, "radius survives")
	assert_almost_eq(copy.energy, 1.2, 0.001, "energy survives")
	assert_almost_eq(copy.flicker, 0.3, 0.001, "flicker survives")


func test_round_trip_is_json_safe():
	var light := LightSource.new()
	light.id = "torch"
	light.cell = Vector2i(1, 2)
	var parsed = JSON.parse_string(JSON.stringify(light.to_dict()))
	assert_true(parsed is Dictionary, "the authored form encodes to JSON")
	assert_eq(LightSource.from_dict(parsed).cell, Vector2i(1, 2), "and decodes back")


func test_defaults_are_a_plain_steady_lamp():
	var light := LightSource.from_dict({"id": "x", "cell": {"x": 1, "y": 1}})
	assert_almost_eq(light.energy, 1.0, 0.001, "energy defaults to 1")
	assert_almost_eq(light.flicker, 0.0, 0.001, "a light does not flicker unless asked to")
	assert_almost_eq(light.offset.distance_to(Vector2(0.5, 0.5)), 0.0, 0.001,
		"and sits at the centre of its tile")
