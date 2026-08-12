extends GutTest

## Every authored world in `worlds/` must be playable — including the one the game
## actually boots.
##
## This is the CONTENT half of the split described in `worlds/fixtures/README.md`.
## The scene-driven suites are pinned to a fixture so a world edit cannot break the
## fold model; the price of that is that they no longer notice a broken world either.
## This file is what notices.
##
## It exists because of a specific hole. `test_world_data.gd` validates
## `worlds/overworld.json` by name, so when commit 113c0f0 re-pointed
## `FoldWorld.WORLD_PATH` at a brand-new `worlds/intro.json`, that world went out
## completely unchecked — nothing in the suite had ever looked at it. The checks
## below therefore walk the DIRECTORY rather than a hardcoded filename, and assert
## separately that whatever `WORLD_PATH` names is one of the files they walked.
##
## `worlds/fixtures/` is deliberately excluded: those belong to the suite, not the
## game, and they are allowed to contain whatever a test needs.

const WORLDS_DIR := "res://worlds/"

## FoldWorld has no `class_name` (it is a scene script), so reach its constant
## through the script resource rather than a global identifier.
const FoldWorldScript := preload("res://scripts/world/FoldWorld.gd")


## Every authored world, by res:// path. Fixtures are not authored worlds.
func _world_paths() -> Array:
	var paths: Array = []
	var dir := DirAccess.open(WORLDS_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			paths.append(WORLDS_DIR + name)
		name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


func test_there_is_something_to_check() -> void:
	var paths := _world_paths()
	assert_gt(paths.size(), 0, "worlds/ holds at least one authored world")


func test_the_world_the_game_boots_is_one_we_check() -> void:
	# The whole point. If WORLD_PATH can name a world this file never opens, this
	# file is decoration.
	var shipped: String = FoldWorldScript.WORLD_PATH
	assert_true(FileAccess.file_exists(shipped),
		"FoldWorld.WORLD_PATH (%s) names a file that exists" % shipped)
	assert_true(_world_paths().has(shipped),
		"FoldWorld.WORLD_PATH (%s) is inside worlds/, so the checks below cover it"
			% shipped)


func test_every_authored_world_parses() -> void:
	for path in _world_paths():
		assert_not_null(WorldData.load_from(path), "%s parses" % path)


## A world that declares itself a debug world. `testbed.json` is one — its own note
## opens "A DEBUG WORLD, not a designed one" and says several arrangements in it are
## deliberately unsolvable.
##
## The distinction matters because two different kinds of rule are checked below.
## Rules about what the ENGINE can survive apply everywhere. Rules that encode
## DESIGN intent — a hand placed where the designer meant it rather than wherever it
## rolls to — are meaningless against a world built to hold broken arrangements on
## purpose, and asserting them there only teaches people to add exemptions.
func _is_debug(wd: WorldData) -> bool:
	return bool(wd.metadata.get("debug", false))


## The lowest solid tile under `cell` in its column, or -1 if the column is open all
## the way down.
func _ground_below(base: BaseGrid, cell: Vector2i, height: int) -> int:
	for y in range(cell.y + 1, height):
		var tile := base.tile_at(Vector2i(cell.x, y))
		if tile != null and not TileTypes.is_walkable(tile.type):
			return y
	return -1


func test_every_authored_hand_is_a_real_kind_on_a_real_tile() -> void:
	for path in _world_paths():
		var wd := WorldData.load_from(path)
		if wd == null:
			continue
		for id in wd.regions:
			var base := wd.build_base(id)
			for pickup in wd.hands_of(id):
				assert_true(pickup.bind(base),
					"%s: hand at %s in %s binds to a real tile" % [path, pickup.cell, id])
				assert_true(HandTypes.is_registered(pickup.kind),
					"%s: hand at %s in %s is a real kind" % [path, pickup.cell, id])


func test_every_authored_hand_can_come_to_rest() -> void:
	# Engine rule, every world including debug ones. Hands are objects that fall
	# (see FoldWorld._wake_unsupported_hands), so starting in mid-air is legal —
	# starting above a column with no floor in it is not. Such a hand never lands,
	# and FoldWorld re-reports it on every landing attempt.
	for path in _world_paths():
		var wd := WorldData.load_from(path)
		if wd == null:
			continue
		for id in wd.regions:
			var base := wd.build_base(id)
			var height := wd.region_size(id).y
			for pickup in wd.hands_of(id):
				assert_ne(_ground_below(base, pickup.cell, height), -1,
					"%s: hand at %s in %s has floor somewhere below it to land on"
						% [path, pickup.cell, id])


func test_playable_worlds_place_their_hands_on_the_ground() -> void:
	# Design rule, playable worlds only. A hand resting where the designer put it is
	# a hand the player can walk into; one that has to fall first lands wherever the
	# terrain sends it. Eight of these shipped in overworld's east region once.
	for path in _world_paths():
		var wd := WorldData.load_from(path)
		if wd == null or _is_debug(wd):
			continue
		for id in wd.regions:
			var base := wd.build_base(id)
			for pickup in wd.hands_of(id):
				var below := base.tile_at(pickup.cell + Vector2i(0, 1))
				assert_not_null(below,
					"%s: hand at %s in %s is not at the map edge" % [path, pickup.cell, id])
				if below != null:
					assert_false(TileTypes.is_walkable(below.type),
						"%s: hand at %s in %s lies on solid ground"
							% [path, pickup.cell, id])


func test_every_authored_light_binds_to_a_real_tile() -> void:
	for path in _world_paths():
		var wd := WorldData.load_from(path)
		if wd == null:
			continue
		for id in wd.regions:
			var base := wd.build_base(id)
			for light in wd.lights_of(id):
				assert_not_null(base.tile_at(light.cell),
					"%s: light at %s in %s sits on a real tile" % [path, light.cell, id])


func test_every_door_has_a_partner_on_a_real_tile() -> void:
	# A door whose partner does not exist is a door that eats the player.
	for path in _world_paths():
		var wd := WorldData.load_from(path)
		if wd == null:
			continue
		for door_id in wd.doors:
			var door: Dictionary = wd.doors[door_id]
			var region := String(door.get("region", ""))
			var pair := String(door.get("pair", ""))

			assert_true(wd.has_region(region),
				"%s: door %s is in a region that exists" % [path, door_id])
			assert_true(wd.doors.has(pair),
				"%s: door %s names a partner that exists (%s)" % [path, door_id, pair])
			if wd.doors.has(pair):
				assert_eq(String(wd.doors[pair].get("pair", "")), door_id,
					"%s: door %s and %s point at each other" % [path, door_id, pair])
			if wd.has_region(region):
				assert_not_null(wd.build_base(region).tile_at(door["cell"]),
					"%s: door %s sits on a real tile" % [path, door_id])


func test_every_region_spawn_is_inside_its_grid() -> void:
	for path in _world_paths():
		var wd := WorldData.load_from(path)
		if wd == null:
			continue
		for id in wd.regions:
			var size := wd.region_size(id)
			var spawn := wd.spawn_px(id) / wd.cell_size
			assert_between(spawn.x, 0.0, float(size.x),
				"%s: %s spawns inside the map horizontally" % [path, id])
			assert_between(spawn.y, 0.0, float(size.y),
				"%s: %s spawns inside the map vertically" % [path, id])


func test_the_start_region_exists_everywhere() -> void:
	for path in _world_paths():
		var wd := WorldData.load_from(path)
		if wd == null:
			continue
		assert_true(wd.has_region(wd.start_region),
			"%s: start_region (%s) is a region that exists" % [path, wd.start_region])
