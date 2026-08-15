extends GutTest

## The world select: what is in `worlds/`, and the two things you can do with one.
##
## Scene-driven, on the real directory. There is no fixture here on purpose — what
## this screen is FOR is telling you what you actually have in the tree, and a launcher
## tested against a made-up directory would not catch the day it stopped seeing one.

const SCENE := "res://scenes/ui/Launcher.tscn"

var launcher: Launcher


func before_each() -> void:
	launcher = load(SCENE).instantiate()
	add_child_autofree(launcher)


func _row(name: String) -> Dictionary:
	for world in launcher.worlds:
		if String(world["name"]) == name:
			return world
	return {}


func _index_of(name: String) -> int:
	for i in range(launcher.worlds.size()):
		if String(launcher.worlds[i]["name"]) == name:
			return i
	return -1


# ---------------------------------------------------------------------------
# What it finds
# ---------------------------------------------------------------------------

func test_it_lists_the_worlds_that_ship():
	assert_false(_row("overworld").is_empty(), "the shipped world is offered")
	assert_false(_row("testbed").is_empty(), "and the debug world, which is most of the point")


func test_it_does_not_offer_the_suite_fixtures():
	# `worlds/fixtures/` is the test suite's, and editing one of those breaks the spec
	# for sixty tests that have nothing to do with the change. Keeping it out costs
	# nothing here: the scan is one directory deep, so the subdirectory never comes up.
	assert_true(_row("kernel").is_empty(),
		"a fixture is not a world you play — see worlds/fixtures/README.md")


func test_a_world_is_summarised_from_the_file_itself():
	var world := _row("overworld")
	var data := WorldData.load_from(String(world["path"]))
	assert_eq((world["regions"] as Array).size(), data.regions.size(), "region count")
	assert_eq(int(world["doors"]), data.doors.size(), "door count")
	assert_eq(String(world["start"]), data.start_region, "and where it starts")


func test_a_world_opens_with_something_selected():
	assert_true(launcher.selected >= 0, "there is always a selection to act on")
	assert_eq(launcher.selected_region, "",
		"and no region chosen, which means the world's own start")


# ---------------------------------------------------------------------------
# What it asks for
# ---------------------------------------------------------------------------

func test_play_asks_for_the_selected_world_by_path():
	launcher.select(_index_of("testbed"))
	watch_signals(launcher)
	launcher.play()
	assert_eq(get_signal_parameters(launcher, "play_requested"),
		["res://worlds/testbed.json", {}],
		"the launcher has no world in memory, so it names the file")


func test_picking_a_region_starts_the_run_there():
	launcher.select(_index_of("overworld"))
	launcher.select_region("east")
	watch_signals(launcher)
	launcher.play()
	assert_eq(get_signal_parameters(launcher, "play_requested"),
		["res://worlds/overworld.json", {"region": "east"}],
		"a region is the nearest thing this game has to picking a level")


func test_no_cell_is_asked_for():
	# The editor picks cells, because that is where you can see them. A launcher is
	# not standing anywhere, so a region's own spawn is as specific as it can honestly be.
	launcher.select(_index_of("overworld"))
	launcher.select_region("east")
	watch_signals(launcher)
	launcher.play()
	var at: Dictionary = get_signal_parameters(launcher, "play_requested")[1]
	assert_false(at.has("cell"), "a launcher does not name a cell")


func test_choosing_the_same_region_again_clears_it():
	launcher.select(_index_of("overworld"))
	launcher.select_region("east")
	launcher.select_region("east")
	assert_eq(launcher.selected_region, "",
		"which is the way back to starting where the world says")


func test_changing_world_forgets_the_region():
	launcher.select(_index_of("overworld"))
	launcher.select_region("east")
	launcher.select(_index_of("testbed"))
	assert_eq(launcher.selected_region, "",
		"a region of the world you left means nothing in the one you picked")


func test_edit_asks_for_the_world_and_the_region_being_looked_at():
	launcher.select(_index_of("overworld"))
	launcher.select_region("east")
	watch_signals(launcher)
	launcher.edit()
	assert_eq(get_signal_parameters(launcher, "edit_requested"),
		["res://worlds/overworld.json", "east"],
		"picking a region and pressing edit lands you on its card")


func test_enter_plays_and_e_edits():
	watch_signals(launcher)
	launcher._unhandled_key_input(_key(KEY_ENTER))
	assert_signal_emitted(launcher, "play_requested", "⏎ plays")
	launcher._unhandled_key_input(_key(KEY_E))
	assert_signal_emitted(launcher, "edit_requested", "E edits")


func test_escape_leaves():
	watch_signals(launcher)
	launcher._unhandled_key_input(_key(KEY_ESCAPE))
	assert_signal_emitted(launcher, "left",
		"there is nothing under the launcher, which the shell reads as quitting")


# ---------------------------------------------------------------------------
# Coming back to it
# ---------------------------------------------------------------------------

func test_it_rescans_when_it_comes_back_into_the_tree():
	# The reason this screen rescans on `_enter_tree` rather than in `_ready`: the
	# editor you just came back from may have written a world while you were away, and
	# a suspended screen does not run `_ready` again. See `Shell`.
	launcher.worlds = []
	remove_child(launcher)
	add_child(launcher)
	assert_false(launcher.worlds.is_empty(), "coming back is a rescan")


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func test_it_opens_on_the_world_that_ships():
	assert_eq(String(launcher.selected_world()["path"]), WorldData.SHIPPED_WORLD,
		"not whichever world sorts first — the commonest thing to want here is one key away")


func test_coming_back_keeps_what_you_had_chosen():
	# You come back here after every run, and the run you want next is usually the one
	# you just had. Kept by path and by name rather than by position, so a world file
	# appearing in the directory cannot quietly move the selection.
	launcher.select(_index_of("overworld"))
	launcher.select_region("east")
	launcher.scan()
	assert_eq(String(launcher.selected_world()["path"]), "res://worlds/overworld.json",
		"the world you were on")
	assert_eq(launcher.selected_region, "east", "and the region you were going to start in")


func test_a_region_that_stopped_existing_is_forgotten():
	launcher.select(_index_of("overworld"))
	launcher.selected_region = "a-region-that-was-renamed"
	launcher.scan()
	assert_eq(launcher.selected_region, "",
		"a region the world no longer has means start where the world says")
