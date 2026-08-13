## Testbed world tests
##
## `worlds/testbed.json` is the DEBUG world: fourteen regions wired star-and-ring,
## one element per themed region, three mashups, and a `kitchen` that crams every
## tile character and occupant kind into one room. It is not a designed world and
## nothing here asserts that it is fun or even finishable — several arrangements in
## it are deliberately unsolvable.
##
## What this file holds is the thing a debug world is worthless without: that it
## still LOADS, that everything in it points at something real, and that it still
## covers the ground it claims to. A world file only the editor ever opens rots
## silently; this is what makes it fail loudly instead.
##
## It is also the widest exercise the loader gets. `overworld.json` has two regions,
## one pre-placed fold and one trigger; this one has thirteen pre-placed folds in
## every orientation, eleven triggers spanning every outcome the resolver has, and
## doors in cases the shipped world never reaches (two in one cell, a pair inside
## one region, one on a crease, one sealed inside a fold).

extends GutTest

const WORLD_PATH := "res://worlds/testbed.json"
const HUB := "hub"

## Region ids the hub must carry a door to. The hub IS the router; a spoke missing
## from here is a region you can only reach the long way round.
const SPOKES := ["plain", "water", "pins", "unanchor", "triggers", "prefold", "lamps",
	"hands", "goals", "mash_a", "mash_b", "mash_c", "kitchen"]


func _world() -> WorldData:
	return WorldData.load_from(WORLD_PATH)


## A region with its pre-placed folds applied, exactly as `FoldWorld._setup_all`
## does it: each fold created from the CURRENT piece list, in order.
func _booted(wd: WorldData, id: String) -> Dictionary:
	var base := wd.build_base(id)
	var pieces: Array = FoldReplay.identity_pieces(base)
	var folds: Array[Fold] = []
	var next_id := 0
	for pair in wd.fold_pairs(id):
		var f := Fold.create(next_id, pair[0], pair[1], wd.cell_size)
		folds.append(f)
		pieces = FoldReplay.apply_one_fold(pieces, f, wd.cell_size)
		next_id += 1
	return {"base": base, "pieces": pieces, "folds": folds}


# ---------------------------------------------------------------------------
# It loads, and every region in it builds
# ---------------------------------------------------------------------------

func test_the_testbed_loads():
	var wd := _world()
	assert_not_null(wd, "worlds/testbed.json parses")
	assert_eq(wd.world_id, "testbed", "it knows what it is")
	assert_true(wd.has_region(wd.start_region), "the start region exists")
	assert_eq(wd.start_region, HUB, "you start in the hub, since that is what routes")


func test_it_is_a_big_world():
	# The point of this file is breadth. If a region is deleted, that is a decision
	# worth making on purpose.
	var wd := _world()
	assert_gte(wd.regions.size(), 14, "fourteen regions or more")
	assert_gte(wd.doors.size(), 60, "and enough doors to wire them star AND ring")


func test_every_region_builds_a_grid():
	var wd := _world()
	for id in wd.regions:
		var base := wd.build_base(id)
		assert_not_null(base, "region %s builds a BaseGrid" % id)
		assert_gt(base.tiles.size(), 0, "region %s has tiles" % id)
		assert_eq(base.tiles.size(), base.grid_size.x * base.grid_size.y,
			"region %s is rectangular — rows padded to the widest" % id)


func test_every_spawn_is_inside_its_region_and_on_something_solid():
	var wd := _world()
	for id in wd.regions:
		var base := wd.build_base(id)
		var cell := Vector2i((wd.regions[id]["spawn"] as Vector2).floor())
		var here := base.tile_at(cell)
		assert_not_null(here, "%s spawns inside its own grid" % id)
		if here == null:
			continue
		assert_true(TileTypes.is_walkable(here.type),
			"%s does not spawn you inside a wall" % id)
		var below := base.tile_at(cell + Vector2i(0, 1))
		assert_not_null(below, "%s does not spawn you off the bottom edge" % id)
		if below != null:
			assert_false(TileTypes.is_walkable(below.type),
				"%s spawns you on ground rather than in mid-air" % id)


# ---------------------------------------------------------------------------
# Doors — the thing the hub exists for
# ---------------------------------------------------------------------------

func test_every_door_points_at_something_real():
	var wd := _world()
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		assert_true(wd.has_region(d["region"]), "door %s names a real region" % id)
		if not wd.has_region(d["region"]):
			continue
		assert_not_null(wd.build_base(d["region"]).tile_at(d["cell"]),
			"door %s sits on a real tile" % id)
		assert_true(wd.doors.has(d["pair"]), "door %s's partner exists" % id)
		if wd.doors.has(d["pair"]):
			assert_eq(wd.doors[d["pair"]]["pair"], id, "door %s's pairing is mutual" % id)


func test_no_door_is_buried_in_something_you_cannot_stand_in():
	# A door inside a wall is a door nothing can ever walk into. Being folded away
	# is fine — that is a case this world is FOR — but being bricked up is a typo.
	var wd := _world()
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		var tile := wd.build_base(d["region"]).tile_at(d["cell"])
		if tile == null:
			continue
		assert_true(TileTypes.is_walkable(tile.type),
			"door %s is in open space, not inside a %s" % [id, TileTypes.type_name(tile.type)])


func test_the_hub_carries_a_door_to_every_other_region():
	var wd := _world()
	var reached := {}
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		if d["region"] != HUB:
			continue
		reached[wd.doors[d["pair"]]["region"]] = true
	for spoke in SPOKES:
		assert_true(reached.has(spoke), "the hub has a door to %s" % spoke)


func test_the_world_is_one_connected_graph():
	# Star AND ring: the hub reaches everything directly, and the regions also chain
	# to each other, so no region is only ever entered one way.
	var wd := _world()
	var adj := {}
	for id in wd.regions:
		adj[id] = {}
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		var far: String = wd.doors[d["pair"]]["region"]
		adj[d["region"]][far] = true
	var seen := {HUB: true}
	var stack: Array = [HUB]
	while not stack.is_empty():
		for far in adj[stack.pop_back()]:
			if not seen.has(far):
				seen[far] = true
				stack.append(far)
	for id in wd.regions:
		assert_true(seen.has(id), "region %s is reachable from the hub" % id)


func test_the_hub_puts_two_doors_in_one_cell():
	# Deliberate: one tile, two partners. The model keys doors by id, not by cell,
	# so nothing stops it — and what happens when you walk in is worth being able
	# to go and look at.
	var wd := _world()
	var by_cell := {}
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		var key := "%s:%s" % [d["region"], d["cell"]]
		by_cell[key] = int(by_cell.get(key, 0)) + 1
	var shared := 0
	for key in by_cell:
		if by_cell[key] > 1:
			shared += 1
	assert_gt(shared, 0, "at least one cell carries more than one door")


func test_a_door_pair_lives_inside_one_region():
	# A door whose partner is in the same region: walking into it moves you across
	# the sheet you are already on.
	var wd := _world()
	var same := 0
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		if wd.doors[d["pair"]]["region"] == d["region"]:
			same += 1
	assert_gt(same, 0, "some door pair goes region -> itself")


# ---------------------------------------------------------------------------
# Occupants
# ---------------------------------------------------------------------------

func test_every_light_binds_to_a_real_tile():
	var wd := _world()
	for id in wd.regions:
		var base := wd.build_base(id)
		for light in wd.lights_of(id):
			assert_true(light.bind(base),
				"light %s in %s binds to a real tile" % [light.id, id])
			assert_gt(light.radius_cells, 0.0, "light %s has a radius" % light.id)


func test_every_loose_hand_binds_and_is_a_real_kind():
	var wd := _world()
	for id in wd.regions:
		var base := wd.build_base(id)
		for pickup in wd.hands_of(id):
			assert_true(pickup.bind(base),
				"hand at %s in %s binds to a real tile" % [pickup.cell, id])
			assert_true(HandTypes.is_registered(pickup.kind),
				"hand at %s in %s is a registered kind" % [pickup.cell, id])


func test_it_lays_out_every_kind_of_hand():
	var wd := _world()
	var kinds := {}
	for id in wd.regions:
		for pickup in wd.hands_of(id):
			kinds[pickup.kind] = true
	for kind in HandTypes.all_types():
		assert_true(kinds.has(kind),
			"a %s hand is somewhere in the world" % HandTypes.type_name(kind))


func test_it_starts_you_with_a_mixed_pair():
	# Two different kinds in your slots, so the mean-of-both fuse is visible from
	# the first fold you make rather than being something you have to go and find.
	var wd := _world()
	var slots := wd.starting_hand_slots()
	assert_eq(HandStock.held_count(slots), HandStock.SLOTS, "both slots are full")
	assert_ne(slots[0], slots[1], "and they are not the same kind")


# ---------------------------------------------------------------------------
# Terrain coverage — the "everything" claim, kept honest
# ---------------------------------------------------------------------------

func test_every_authoring_character_is_used_somewhere():
	var wd := _world()
	var seen := {}
	for id in wd.regions:
		for row in wd.regions[id]["rows"]:
			for i in String(row).length():
				seen[String(row)[i]] = true
	for ch in WorldCore.CHARS:
		assert_true(seen.has(ch),
			"'%s' (%s) is placed somewhere" % [ch, TileTypes.type_name(WorldCore.CHARS[ch])])
	assert_true(seen.has("."), "and so is plain air")


func test_the_kitchen_is_the_room_with_everything_in_it():
	# One room, every tile character, so there is a single place to stand and watch
	# them interact instead of a tour.
	var wd := _world()
	assert_true(wd.has_region("kitchen"), "the kitchen exists")
	var seen := {}
	for row in wd.regions["kitchen"]["rows"]:
		for i in String(row).length():
			seen[String(row)[i]] = true
	for ch in WorldCore.CHARS:
		assert_true(seen.has(ch), "the kitchen has a '%s'" % ch)

	var base := wd.build_base("kitchen")
	var kinds := {}
	for pickup in wd.hands_of("kitchen"):
		kinds[pickup.kind] = true
	assert_eq(kinds.size(), HandTypes.all_types().size(), "...and every kind of hand")
	assert_gt(wd.lights_of("kitchen").size(), 0, "...and lights")
	assert_gt(wd.fold_pairs("kitchen").size(), 0, "...and a pre-placed fold")
	assert_gt((wd.regions["kitchen"]["tile_data"] as Dictionary).size(), 0, "...and a trigger")
	var doors_here := 0
	for id in wd.doors:
		if wd.doors[id]["region"] == "kitchen":
			doors_here += 1
	assert_gt(doors_here, 3, "...and a pile of doors")
	assert_not_null(base, "and it still builds")


# ---------------------------------------------------------------------------
# Triggers
# ---------------------------------------------------------------------------

func test_every_tile_data_entry_sits_on_a_tile_that_takes_parameters():
	# `tile_data` keyed at a cell whose character takes no parameters is data that
	# can never be read — the commonest way to break a world by hand.
	var wd := _world()
	for id in wd.regions:
		var base := wd.build_base(id)
		for key in wd.regions[id]["tile_data"] as Dictionary:
			var tile := base.tile_at(TileParams.cell_of_key(String(key)))
			assert_not_null(tile, "tile_data %s in %s names a real cell" % [key, id])
			if tile == null:
				continue
			assert_true(TileParams.has_params(tile.type),
				"tile_data %s in %s is on a tile that takes parameters" % [key, id])


func test_every_trigger_is_fully_configured():
	var wd := _world()
	var total := 0
	for id in wd.regions:
		var base := wd.build_base(id)
		var size := wd.region_size(id)
		for key in wd.regions[id]["tile_data"] as Dictionary:
			var cell := TileParams.cell_of_key(String(key))
			var tile := base.tile_at(cell)
			if tile == null or tile.type != TileTypes.TRIGGER_FOLD:
				continue
			total += 1
			# Two anchors, both on the grid. `issues` also flags a doubled cell, and
			# ONE plate here is authored that way on purpose — the degenerate case.
			for note in TileParams.issues(tile.type, tile.data, size):
				if String(note).contains("distinct anchors"):
					continue
				fail_test("trigger %s in %s: %s" % [key, id, note])
	assert_gt(total, 8, "the trigger region works the resolver hard")


func test_the_trigger_region_covers_every_outcome_the_resolver_has():
	# Fires / shares a channel / is vetoed by a pin / is degenerate / would swallow
	# whoever fired it / has no channel at all. Each is a plate you can go and step
	# on, so the channels are the index.
	var wd := _world()
	var channels := {}
	var blank := 0
	for key in wd.regions["triggers"]["tile_data"] as Dictionary:
		var data: Dictionary = wd.regions["triggers"]["tile_data"][key]
		var channel := String(data.get("channel", ""))
		if channel.is_empty():
			blank += 1
		else:
			channels[channel] = int(channels.get(channel, 0)) + 1
	for wanted in ["gate_a", "gate_b", "pinned", "degenerate", "swallow", "ghost"]:
		assert_true(channels.has(wanted), "the '%s' plate is there" % wanted)
	assert_eq(int(channels.get("gate_b", 0)), 2,
		"two plates share the 'gate_b' channel, so one fold has two ways to fire")
	assert_gt(blank, 0, "and one plate has no channel, so nothing stops it firing again")


## The trigger/plate pairs this world authors as a LOOP you can walk: step on the
## trigger and a fold stands, step on the plate a cell or two along and the same fold
## comes back out. Listed here because that is what the pairing is; the test says what
## has to be true for it to work.
const PLATE_LOOPS := [
	{"region": "kitchen", "trigger": Vector2i(22, 12), "plate": Vector2i(23, 12)},
	{"region": "triggers", "trigger": Vector2i(17, 16), "plate": Vector2i(26, 16)},
]


func test_every_plate_loop_reaches_the_seam_its_trigger_leaves():
	# A loop works only while the plate's authored REACH covers where the seam actually
	# LANDS — and where it lands is the fold's half-shift, moved again by whatever else
	# the region ships folded. Numbers in three places, and nothing but this would
	# notice them drifting apart.
	var wd := _world()
	for loop in PLATE_LOOPS:
		var id: String = loop["region"]
		var booted := _booted(wd, id)
		var base: BaseGrid = booted["base"]
		var cs := wd.cell_size
		var plate_cell: Vector2i = loop["plate"]
		var plate_tile := base.tile_at(plate_cell)
		assert_eq(plate_tile.type, TileTypes.TRIGGER_BURST,
			"%s %s is a burst plate" % [id, plate_cell])
		var radius := float(TileParams.get_value(plate_tile.type, plate_tile.data, "radius"))

		# The fold the trigger's declared pair makes, built the way the world builds it:
		# its two BASE cells resolved through whatever the region already ships folded.
		var trigger_cell: Vector2i = loop["trigger"]
		var stood_on = BaseFrame.world_point_from_base(booted["pieces"],
			base.tile_at(trigger_cell).base_id, (Vector2(trigger_cell) + Vector2(0.5, 0.5)) * cs)
		assert_not_null(stood_on, "%s's trigger is reachable at boot" % id)
		var fold = _declared_fold(booted, base.tile_at(trigger_cell), cs)
		assert_not_null(fold, "%s's trigger declares a fold that goes" % id)
		var after := FoldReplay.apply_one_fold(booted["pieces"], fold, cs)

		var plate_at = BaseFrame.world_point_from_base(after,
			plate_tile.base_id, (Vector2(plate_cell) + Vector2(0.5, 0.5)) * cs)
		assert_not_null(plate_at, "%s's plate rode the fold rather than being excised" % id)
		var seam := (Vector2(fold.meeting_pos) + Vector2(0.5, 0.5)) * cs
		assert_lte(seam.distance_to(Vector2(plate_at)), radius * cs,
			"%s's plate reaches the seam its trigger leaves behind" % id)


## The fold a trigger tile declares, in the configuration `booted` describes, or null
## if it would not go. The world reaches this by pinning two bolted anchors and letting
## the fuse fold them (`FoldWorld._plant_pair`); here it is the same two base cells,
## resolved the same way, without a scene to boot.
func _declared_fold(booted: Dictionary, tile: BaseTile, cs: float):
	var cells: Array = tile.data.get("anchors", [])
	if cells.size() < 2:
		return null
	var base: BaseGrid = booted["base"]
	var at: Array = []
	for raw in cells.slice(0, 2):
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		var wp = BaseFrame.world_point_from_base(booted["pieces"],
			base.tile_at(cell).base_id, (Vector2(cell) + Vector2(0.5, 0.5)) * cs)
		if wp == null:
			return null
		at.append(Vector2i((Vector2(wp) / cs).floor()))
	if at[0] == at[1]:
		return null
	var f := Fold.create(0, at[0], at[1], cs, String(tile.data.get("channel", "")))
	return null if FoldReplay.blocked_by_tile(booted["pieces"], f, cs) else f


func test_a_pin_still_vetoes_the_fold_a_plate_would_make():
	# The plate is on the floor and the pin is in the sky six rows up: a fold's
	# extent is the whole world, so the nail is in its strip anyway.
	var wd := _world()
	var booted := _booted(wd, "triggers")
	var base: BaseGrid = booted["base"]
	var data: Dictionary = {}
	for key in wd.regions["triggers"]["tile_data"] as Dictionary:
		var entry: Dictionary = wd.regions["triggers"]["tile_data"][key]
		if String(entry.get("channel", "")) == "pinned":
			data = entry
	assert_false(data.is_empty(), "the 'pinned' plate is authored")
	var anchors: Array = data["anchors"]
	var f := Fold.create(0, Vector2i(int(anchors[0][0]), int(anchors[0][1])),
		Vector2i(int(anchors[1][0]), int(anchors[1][1])), wd.cell_size)
	assert_true(FoldReplay.blocked_by_tile(booted["pieces"], f, wd.cell_size),
		"the fold that plate would make is refused")


# ---------------------------------------------------------------------------
# Pre-placed folds
# ---------------------------------------------------------------------------

func test_every_region_survives_booting_its_pre_placed_folds():
	# A region's fold list is applied in order against the ALREADY-FOLDED piece
	# list, so a second fold's anchors are plane cells, not base ones. Getting that
	# wrong is how a region folds itself out of existence.
	var wd := _world()
	for id in wd.regions:
		var booted := _booted(wd, id)
		assert_gt((booted["pieces"] as Array).size(), 0,
			"region %s still has sheet after its pre-placed folds" % id)


func test_the_prefold_region_ships_folded_in_every_orientation():
	var wd := _world()
	var kinds := {}
	for pair in wd.fold_pairs("prefold"):
		kinds[Fold.classify_orientation(pair[0], pair[1])] = true
	for wanted in ["horizontal", "vertical", "diagonal"]:
		assert_true(kinds.has(wanted), "a %s pre-placed fold ships" % wanted)


func test_a_nested_pre_placed_fold_is_authored_and_ignored():
	# `in` is reserved: the editor saves it, the loader skips it. Authoring one here
	# is what stops that contract quietly changing.
	var wd := _world()
	var nested := 0
	var flat := 0
	for entry in wd.regions["prefold"]["folds"]:
		if not (entry.get("in", []) as Array).is_empty():
			nested += 1
		else:
			flat += 1
	assert_gt(nested, 0, "a nested entry is authored")
	assert_eq(wd.fold_pairs("prefold").size(), flat,
		"...and fold_pairs hands back only the region-level ones")


func test_the_routing_doors_survive_the_folds_their_region_ships_with():
	# Doors that are folded away at boot are a case this world is FOR — but only the
	# ones authored for it. Every door on a region's landing run (the clear stretch
	# of walk line the routing doors sit on) has to still be there, or a spoke of the
	# hub leads somewhere you cannot come back from.
	var wd := _world()
	for id in wd.doors:
		var d: Dictionary = wd.doors[id]
		if not (id.ends_with("_HUB") or id.contains("_TO_") or id.contains("_FROM_")):
			continue
		var booted := _booted(wd, d["region"])
		var base: BaseGrid = booted["base"]
		var tile := base.tile_at(d["cell"])
		assert_not_null(tile, "routing door %s is on the grid" % id)
		if tile == null:
			continue
		var here = BaseFrame.world_point_from_base(booted["pieces"], tile.base_id,
			(Vector2(d["cell"]) + Vector2(0.5, 0.5)) * wd.cell_size)
		assert_not_null(here, "routing door %s is not folded away at boot" % id)


func test_the_hub_ships_a_door_split_by_a_crease_and_a_door_inside_a_fold():
	# The two door cases the shipped world cannot show you at once: one whose tile is
	# cut exactly through its centre (dormant — no unambiguous side to arrive on) and
	# one wholly inside the excised strip (its partner delivers you into the subspace).
	var wd := _world()
	var booted := _booted(wd, HUB)
	var base: BaseGrid = booted["base"]
	var cs := wd.cell_size

	var dormant: Vector2i = wd.doors["HUB_DORMANT"]["cell"]
	var dormant_tile := base.tile_at(dormant)
	assert_not_null(dormant_tile, "the dormant door is on the grid")
	assert_null(BaseFrame.resolve_base_point(booted["pieces"], dormant_tile.base_id,
		(Vector2(dormant) + Vector2(0.5, 0.5)) * cs),
		"the dormant door's centre resolves to no unambiguous side")

	var vault: Vector2i = wd.doors["HUB_VAULT"]["cell"]
	var vault_tile := base.tile_at(vault)
	assert_not_null(vault_tile, "the vault door is on the grid")
	assert_null(BaseFrame.world_point_from_base(booted["pieces"], vault_tile.base_id,
		(Vector2(vault) + Vector2(0.5, 0.5)) * cs),
		"the vault door is gone from the region — it is inside the fold")


func test_folding_a_lamp_away_takes_it_out_of_the_overworld():
	# The lamps region ships one lamp inside a one-column pre-fold, so it lights the
	# strip's subspace and nothing else.
	var wd := _world()
	var booted := _booted(wd, "lamps")
	var base: BaseGrid = booted["base"]
	var folded_away := 0
	for light in wd.lights_of("lamps"):
		if not light.bind(base):
			continue
		if light.position_in(booted["pieces"]) == null:
			folded_away += 1
	assert_eq(folded_away, 1, "exactly the one lamp that was authored inside a fold")
