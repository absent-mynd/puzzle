## WorldData tests
##
## The authored world format: regions of ASCII terrain, doors between them, pre-placed
## folds per region. Covers the round trip, the accessors the world boots from, and the
## shipped `worlds/overworld.json`.

extends GutTest

const WORLD_PATH := "res://worlds/overworld.json"


func _sample() -> WorldData:
	var wd := WorldData.new()
	wd.world_id = "t"
	wd.world_name = "Test World"
	wd.cell_size = 64.0
	wd.start_region = "a"
	wd.starting_hands = ["swift", "patient"]
	wd.regions = {
		"a": {
			"rows": ["....", "####"],
			"spawn": Vector2(1.5, 0.5),
			"tile_data": {"2,0": {"channel": "A"}},
			"folds": [{"anchor1": {"x": 0, "y": 1}, "anchor2": {"x": 3, "y": 1}}],
		},
	}
	wd.regions["a"]["hands"] = [HandPickup.from_dict({"kind": "swift", "cell": {"x": 1, "y": 0}})]
	wd.doors = {"D1": {"region": "a", "cell": Vector2i(1, 1), "pair": "D2"}}
	return wd


func test_round_trip_through_dict():
	var wd := _sample()
	var copy := WorldData.new()
	copy.from_dict(wd.to_dict())
	assert_eq(copy.world_id, "t", "id survives")
	assert_eq(copy.start_region, "a", "start region survives")
	assert_eq(copy.starting_hands, ["swift", "patient"], "the starting hands survive")
	assert_eq((copy.regions["a"]["hands"] as Array).size(), 1, "authored loose hands survive")
	assert_eq(copy.regions["a"]["hands"][0].kind, HandTypes.SWIFT, "...with their kind")
	assert_almost_eq(copy.cell_size, 64.0, 0.001, "cell size survives")
	assert_eq((copy.regions["a"]["rows"] as Array).size(), 2, "rows survive")
	assert_eq(copy.regions["a"]["spawn"], Vector2(1.5, 0.5), "spawn survives as a Vector2")
	assert_eq(copy.doors["D1"]["cell"], Vector2i(1, 1), "door cell survives as a Vector2i")
	assert_eq(copy.doors["D1"]["pair"], "D2", "door pairing survives")


func test_round_trip_is_json_safe():
	# to_dict must contain only JSON-encodable values (no Vector2/Vector2i).
	var text := JSON.stringify(_sample().to_dict())
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "to_dict survives a JSON encode/decode cycle")
	var copy := WorldData.new()
	copy.from_dict(parsed)
	assert_eq(copy.regions["a"]["spawn"], Vector2(1.5, 0.5), "spawn decodes back to a Vector2")


func test_build_base_reads_the_ascii_rows():
	var base := _sample().build_base("a")
	assert_eq(base.grid_size, Vector2i(4, 2), "grid size comes from the row shape")
	assert_eq(base.tile_at(Vector2i(0, 1)).type, TileTypes.WALL, "'#' is a wall")
	assert_eq(base.tile_at(Vector2i(0, 0)).type, TileTypes.EMPTY, "'.' is air")


func test_build_base_attaches_tile_data():
	var base := _sample().build_base("a")
	assert_eq(base.tile_at(Vector2i(2, 0)).data.get("channel", ""), "A",
		"per-tile params reach the BaseTile")


func test_spawn_px_scales_by_cell_size():
	assert_eq(_sample().spawn_px("a"), Vector2(96.0, 32.0), "spawn is authored in cell units")


func test_fold_pairs_are_anchor_vectors():
	var pairs := _sample().fold_pairs("a")
	assert_eq(pairs.size(), 1, "one pre-placed fold")
	assert_eq(pairs[0][0], Vector2i(0, 1), "anchor 1")
	assert_eq(pairs[0][1], Vector2i(3, 1), "anchor 2")


func test_missing_region_accessors_are_safe():
	var wd := _sample()
	assert_false(wd.has_region("nope"), "unknown region reported missing")
	assert_null(wd.build_base("nope"), "no base for an unknown region")
	assert_eq(wd.spawn_px("nope"), Vector2.ZERO, "no spawn for an unknown region")
	assert_eq(wd.fold_pairs("nope"), [], "no folds for an unknown region")


func test_clone_is_independent():
	var wd := _sample()
	var copy := wd.clone()
	copy.regions["a"]["rows"][0] = "XXXX"
	assert_ne(wd.regions["a"]["rows"][0], "XXXX", "mutating the clone leaves the original alone")


# ---------------------------------------------------------------------------
# The shipped world
# ---------------------------------------------------------------------------

func test_shipped_world_loads():
	var wd := WorldData.load_from(WORLD_PATH)
	assert_not_null(wd, "worlds/overworld.json parses")
	assert_true(wd.has_region(wd.start_region), "the start region exists")
	assert_eq(wd.regions.size(), 2, "two regions ship")


func test_shipped_world_starts_you_with_a_full_pair():
	var wd := WorldData.load_from(WORLD_PATH)
	var slots := wd.starting_hand_slots()
	assert_eq(slots.size(), AnchorStock.SLOTS, "one entry per slot, always")
	assert_eq(AnchorStock.held_count(slots), AnchorStock.SLOTS,
		"the shipped world starts you able to make exactly one fold")


func test_starting_hand_slots_pads_and_truncates():
	var wd := WorldData.new()
	wd.starting_hands = []
	assert_eq(wd.starting_hand_slots(), [null, null], "an empty list starts you empty-handed")
	wd.starting_hands = ["swift"]
	assert_eq(wd.starting_hand_slots(), [HandTypes.SWIFT, null], "a short list leaves slots empty")
	wd.starting_hands = ["plain", "plain", "plain", "plain"]
	assert_eq(wd.starting_hand_slots().size(), AnchorStock.SLOTS,
		"hands you could not hold are dropped rather than overflowing")


func test_starting_hand_keys_resolve_and_typos_fall_back():
	var wd := WorldData.new()
	wd.starting_hands = ["patient", "nonsense"]
	assert_eq(wd.starting_hand_slots(),
		[HandTypes.PATIENT, HandTypes.PLAIN],
		"a typo yields an ordinary hand rather than a broken one")


func test_shipped_world_places_loose_hands():
	# Loose hands are the only source of a hand beyond the pair you start with, so a
	# world with none is a world where your starting pair is the whole game.
	var wd := WorldData.load_from(WORLD_PATH)
	var total := 0
	for id in wd.regions:
		total += wd.hands_of(id).size()
	assert_gt(total, 0, "the shipped world lays out at least one loose hand")


func test_shipped_loose_hands_bind_and_stand_on_ground():
	# A hand in mid-air is a hand you cannot walk into, and one off the grid binds
	# to nothing at all.
	var wd := WorldData.load_from(WORLD_PATH)
	for id in wd.regions:
		var base := wd.build_base(id)
		for pickup in wd.hands_of(id):
			assert_true(pickup.bind(base),
				"hand at %s in %s binds to a real tile" % [pickup.cell, id])
			assert_true(HandTypes.is_registered(pickup.kind),
				"hand at %s in %s is a real kind" % [pickup.cell, id])
			var below := base.tile_at(pickup.cell + Vector2i(0, 1))
			assert_not_null(below, "hand at %s in %s is not at the map edge" % [pickup.cell, id])
			assert_false(TileTypes.is_walkable(below.type),
				"hand at %s in %s lies on solid ground" % [pickup.cell, id])


func test_hands_of_hands_out_copies():
	# Same reasoning as lights: binding writes into a pickup, and the authored world
	# must stay the authored world so a reset re-binds from scratch.
	var wd := WorldData.load_from(WORLD_PATH)
	var first: Array = wd.hands_of("west")
	if first.is_empty():
		return
	first[0].kind = HandTypes.PATIENT
	first[0].base_id = 999
	var second: Array = wd.hands_of("west")
	assert_ne(second[0].base_id, 999, "the authored pickup was not written through")


func test_shipped_world_regions_build():
	var wd := WorldData.load_from(WORLD_PATH)
	for id in wd.regions:
		var base := wd.build_base(id)
		assert_not_null(base, "region %s builds a BaseGrid" % id)
		assert_gt(base.tiles.size(), 0, "region %s has tiles" % id)


func test_shipped_doors_reference_real_tiles():
	var wd := WorldData.load_from(WORLD_PATH)
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		assert_true(wd.has_region(d["region"]), "door %s names a real region" % id)
		var base := wd.build_base(d["region"])
		assert_not_null(base.tile_at(d["cell"]), "door %s sits on a real tile" % id)
		assert_true(wd.doors.has(d["pair"]), "door %s's partner exists" % id)
		assert_eq(wd.doors[d["pair"]]["pair"], id, "door %s's pairing is mutual" % id)


# ---------------------------------------------------------------------------
# The shipped world's pin / trigger wing (east, base x >= 20)
# ---------------------------------------------------------------------------

## East with its pre-placed folds applied, as the world boots it.
func _east() -> Dictionary:
	var wd := WorldData.load_from(WORLD_PATH)
	var base := wd.build_base("east")
	var pieces: Array = FoldReplay.identity_pieces(base)
	var folds: Array[Fold] = []
	var next_id := 0
	for pair in wd.fold_pairs("east"):
		var f := Fold.create(next_id, pair[0], pair[1], wd.cell_size)
		folds.append(f)
		pieces = FoldReplay.apply_one_fold(pieces, f, wd.cell_size)
		next_id += 1
	return {"wd": wd, "base": base, "pieces": pieces, "folds": folds}


## Where a base cell's centre currently sits, or null if it is folded away.
func _plane_centre(e: Dictionary, cell: Vector2i):
	var tile: BaseTile = e["base"].tile_at(cell)
	if tile == null:
		return null
	var cs: float = e["wd"].cell_size
	return BaseFrame.world_point_from_base(
		e["pieces"], tile.base_id, (Vector2(cell) + Vector2(0.5, 0.5)) * cs)


func test_shipped_world_places_pins_and_a_trigger():
	var base := WorldData.load_from(WORLD_PATH).build_base("east")
	var pins := 0
	var triggers := 0
	for t in base.tiles:
		if t.type == TileTypes.PIN:
			pins += 1
		elif t.type == TileTypes.TRIGGER_FOLD:
			triggers += 1
	assert_gt(pins, 0, "the shipped world places at least one pin")
	assert_gt(triggers, 0, "the shipped world places at least one fold trigger")


func test_shipped_trigger_is_fully_specified():
	var base := WorldData.load_from(WORLD_PATH).build_base("east")
	for t in base.tiles:
		if t.type != TileTypes.TRIGGER_FOLD:
			continue
		assert_ne(str(t.data.get("channel", "")), "",
			"trigger at %s names a channel" % t.grid_position)
		var anchors: Array = t.data.get("anchors", [])
		assert_eq(anchors.size(), 2, "trigger at %s names two anchors" % t.grid_position)
		for a in anchors:
			var cell := Vector2i(int(a[0]), int(a[1]))
			assert_not_null(base.tile_at(cell),
				"trigger anchor %s is a real tile" % cell)


func test_shipped_pins_survive_the_preplaced_fold():
	# A pin inside a pre-folded band would be excised, contradicting what a pin is.
	var e := _east()
	for t in (e["base"] as BaseGrid).tiles:
		if t.type != TileTypes.PIN:
			continue
		assert_not_null(_plane_centre(e, t.grid_position),
			"pin at %s is not folded away by the shipped pre-fold" % t.grid_position)


func test_shipped_pin_refuses_a_fold_spanning_it():
	var e := _east()
	var base: BaseGrid = e["base"]
	var cs: float = e["wd"].cell_size
	var pin_cell := Vector2i(21, 9)
	assert_eq(base.tile_at(pin_cell).type, TileTypes.PIN, "the pillar is where we expect")

	var here = _plane_centre(e, pin_cell)
	assert_not_null(here, "the pin is present in normal space")
	var plane := Vector2i((Vector2(here) / cs).floor())

	var across := Fold.create(0, plane - Vector2i(2, 0), plane + Vector2i(2, 0), cs)
	assert_true(FoldReplay.blocked_by_tile(e["pieces"], across, cs),
		"a fold spanning the pinned pillar is refused")

	var clear := Fold.create(1, plane + Vector2i(3, 0), plane + Vector2i(6, 0), cs)
	assert_false(FoldReplay.blocked_by_tile(e["pieces"], clear, cs),
		"a fold clear of the pillar still commits")


func test_shipped_trigger_opens_the_wall():
	var e := _east()
	var cs: float = e["wd"].cell_size
	var base: BaseGrid = e["base"]
	var wall_cell := Vector2i(27, 9)
	assert_eq(base.tile_at(wall_cell).type, TileTypes.WALL, "the wall is where we expect")
	assert_not_null(_plane_centre(e, wall_cell), "and it is standing before the plate fires")

	var plate = _plane_centre(e, Vector2i(25, 9))
	assert_not_null(plate, "the plate is reachable in normal space")

	var out := TriggerResolver.resolve(base, {
		"folds": e["folds"],
		"pieces": e["pieces"],
		"player_pos": plate,
		"next_trigger_id": TriggerResolver.TRIGGER_FOLD_ID_BASE,
	})
	assert_eq((out["folds"] as Array).size(), (e["folds"] as Array).size() + 1,
		"standing on the plate fires exactly one fold")

	var wall_bid: int = base.tile_by_id(base.tile_at(wall_cell).base_id).base_id
	var still_there := false
	for p in out["pieces"]:
		if p.base_id == wall_bid:
			still_there = true
			break
	assert_false(still_there, "the triggered fold excised the wall")


func test_shipped_trigger_leaves_the_pin_and_the_reward_alone():
	var e := _east()
	var base: BaseGrid = e["base"]
	var out := TriggerResolver.resolve(base, {
		"folds": e["folds"],
		"pieces": e["pieces"],
		"player_pos": _plane_centre(e, Vector2i(25, 9)),
		"next_trigger_id": TriggerResolver.TRIGGER_FOLD_ID_BASE,
	})
	var survivors := {}
	for p in out["pieces"]:
		survivors[p.base_id] = true
	assert_true(survivors.has(base.tile_at(Vector2i(21, 9)).base_id),
		"the pinned pillar survives the triggered fold")
	assert_true(survivors.has(base.tile_at(Vector2i(29, 9)).base_id),
		"and so does the reward behind the wall")


func test_shipped_trigger_carries_the_player():
	# A trigger that would swallow the player is refused; this one must ride them.
	var e := _east()
	var plate = _plane_centre(e, Vector2i(25, 9))
	var out := TriggerResolver.resolve(e["base"], {
		"folds": e["folds"],
		"pieces": e["pieces"],
		"player_pos": plate,
		"next_trigger_id": TriggerResolver.TRIGGER_FOLD_ID_BASE,
	})
	assert_ne(out["player_pos"], plate, "the plate's fold rides the player with its flap")


func test_shipped_preplaced_folds_are_applicable():
	var wd := WorldData.load_from(WORLD_PATH)
	var applied := 0
	for id in wd.regions:
		var base := wd.build_base(id)
		var pieces: Array = FoldReplay.identity_pieces(base)
		for pair in wd.fold_pairs(id):
			var f := Fold.create(0, pair[0], pair[1], wd.cell_size)
			var dropped := WorldCore.capture_strip(pieces, f, wd.cell_size)
			assert_gt(dropped.size(), 0,
				"pre-placed fold in %s actually excises content" % id)
			pieces = FoldReplay.apply_one_fold(pieces, f, wd.cell_size)
			applied += 1
	assert_gt(applied, 0, "the shipped world uses at least one pre-placed fold")


# ---------------------------------------------------------------------------
# Lights
# ---------------------------------------------------------------------------

func _with_light() -> WorldData:
	var wd := _sample()
	var light := LightSource.new()
	light.id = "lamp"
	light.cell = Vector2i(2, 0)
	light.color = Color("#ffcc88")
	light.radius_cells = 4.0
	light.flicker = 0.2
	wd.regions["a"]["lights"] = [light]
	return wd


func test_lights_round_trip_through_dict():
	var copy := WorldData.new()
	copy.from_dict(_with_light().to_dict())
	var lights: Array = copy.regions["a"]["lights"]
	assert_eq(lights.size(), 1, "the region's light survives the round trip")
	assert_eq(lights[0].id, "lamp", "with its id")
	assert_eq(lights[0].cell, Vector2i(2, 0), "and its cell")
	assert_almost_eq(lights[0].radius_cells, 4.0, 0.001, "and its radius")
	assert_eq(lights[0].region, "a", "a decoded light knows which region it belongs to")


func test_lights_round_trip_is_json_safe():
	var parsed = JSON.parse_string(JSON.stringify(_with_light().to_dict()))
	assert_true(parsed is Dictionary, "lights encode to JSON")
	var copy := WorldData.new()
	copy.from_dict(parsed)
	assert_eq((copy.regions["a"]["lights"] as Array).size(), 1, "and decode back")


func test_lights_of_hands_out_copies():
	# Binding writes base_id/bp into a light; the authored world must not be
	# edited by the act of loading it, so a reset can re-bind from scratch.
	var wd := _with_light()
	var taken: Array = wd.lights_of("a")
	assert_eq(taken.size(), 1, "the region's light comes back")
	taken[0].bind(wd.build_base("a"))
	assert_true(taken[0].is_bound(), "the copy binds")
	assert_false((wd.regions["a"]["lights"][0] as LightSource).is_bound(),
		"and the authored light is untouched")


func test_regions_without_lights_are_fine():
	assert_eq(_sample().lights_of("a").size(), 0, "lights are optional in a region")
	assert_eq(_sample().lights_of("nope").size(), 0, "and a missing region yields none")


func test_shipped_world_places_lights_in_both_regions():
	var wd := WorldData.load_from(WORLD_PATH)
	for id in wd.regions:
		var lights: Array = wd.lights_of(id)
		assert_gt(lights.size(), 0, "region %s is lit" % id)
		var base := wd.build_base(id)
		for light in lights:
			assert_true(light.bind(base),
				"light %s in %s sits on a real base tile" % [light.id, id])
			assert_gt(light.radius_cells, 0.0, "light %s has a radius" % light.id)


func test_shipped_east_hides_a_lamp_inside_its_preplaced_fold():
	# The teaching case: east ships folded, and the lamp inside that fold is not
	# in the region at all until you get in there.
	var wd := WorldData.load_from(WORLD_PATH)
	var base := wd.build_base("east")
	var pieces: Array = FoldReplay.identity_pieces(base)
	for pair in wd.fold_pairs("east"):
		pieces = FoldReplay.apply_one_fold(
			pieces, Fold.create(0, pair[0], pair[1], wd.cell_size), wd.cell_size)
	var resolved: Array = []
	for light in wd.lights_of("east"):
		light.bind(base)
		if light.position_in(pieces) != null:
			resolved.append(light.id)
	assert_true(resolved.has("e_reward"), "the lamp over the reward is in the region")
	assert_false(resolved.has("e_vault"), "the vault's lamp is folded away with the vault")
