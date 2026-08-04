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
	wd.regions = {
		"a": {
			"rows": ["....", "####"],
			"spawn": Vector2(1.5, 0.5),
			"tile_data": {"2,0": {"channel": "A"}},
			"folds": [{"anchor1": {"x": 0, "y": 1}, "anchor2": {"x": 3, "y": 1}}],
		},
	}
	wd.doors = {"D1": {"region": "a", "cell": Vector2i(1, 1), "pair": "D2"}}
	return wd


func test_round_trip_through_dict():
	var wd := _sample()
	var copy := WorldData.new()
	copy.from_dict(wd.to_dict())
	assert_eq(copy.world_id, "t", "id survives")
	assert_eq(copy.start_region, "a", "start region survives")
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
