extends GutTest

## The handoff between the editor and a run of the game.
##
## Two facts make a playtest a playtest, and everything here is one of them:
##
##   - **It runs the DOCUMENT, not the file.** Unsaved edits are the ones you want to
##     try, and a save you did not ask for is a save you cannot take back. So the run
##     is handed a `WorldData` in memory and never reads the disk.
##   - **It drops you where you were looking.** The beat you are editing is rarely the
##     one the world spawns you in.
##
## The world used here is BUILT IN MEMORY rather than loaded, which is not a
## convenience: a run that would still work if the file were deleted is the only proof
## that the in-memory path is really in memory. It is deliberately tiny — a floor, a
## wall to fall off, and two named regions — because nothing here is about geometry.

const SCENE := "res://scenes/world/World.tscn"
const CS := 64.0

var world = null


## A two-region world with a floor along the bottom of each, and nothing else.
func _doc() -> WorldData:
	var rows := [
		"..........",
		"..........",
		"..........",
		"##########",
	]
	var data := WorldData.new()
	data.world_id = "handoff"
	data.world_name = "Handoff"
	data.cell_size = CS
	data.start_region = "first"
	data.starting_hands = ["plain", "plain"]
	for id in ["first", "second"]:
		data.regions[id] = {
			"rows": rows.duplicate(),
			"spawn": Vector2(1.5, 2.5),
			"tile_data": {}, "folds": [], "lights": [], "hands": [], "anchors": [],
			"editor": {},
		}
	return data


## Start a run on a document, the way `Shell.play_screen` does.
func _run(data: WorldData, at: Dictionary = {}) -> Node:
	var node = load(SCENE).instantiate()
	node.data_override = data
	node.spawn_override = at
	add_child_autofree(node)
	node.anim_enabled = false
	return node


func _cell_of(point: Vector2) -> Vector2i:
	return Vector2i((point / CS).floor())


# ---------------------------------------------------------------------------
# Running a document
# ---------------------------------------------------------------------------

func test_a_run_plays_a_world_that_is_only_in_memory():
	world = _run(_doc())
	assert_eq(world.world_data.world_id, "handoff",
		"the run is of the document it was handed, with no file behind it")
	assert_eq(world.region_id, "first", "and it started in the document's start region")


func test_a_document_beats_the_path_and_the_flag():
	world = _run(_doc())
	assert_eq(world.world_data.regions.size(), 2,
		"a world handed over in memory wins over --world= and the shipped world")


func test_a_run_does_not_write_back_into_the_document_it_was_given():
	# A run BINDS lights, loose hands and anchors — it writes a base id and a point
	# into each. The editor is still holding the original, so what a run binds has to
	# be its own copy of everything.
	var doc := _doc()
	var before := doc.to_dict()
	world = _run(doc)
	world._reset()
	assert_eq(doc.to_dict(), before,
		"playing a world, and resetting it, leaves the editor's document untouched")


func test_reset_re_derives_from_the_document():
	var doc := _doc()
	world = _run(doc)
	world.tap_action(Vector2i(1, 0))
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.hands_pending(), 1, "a hand is down")
	world._reset()
	assert_eq(world.hands_pending(), 0, "and R put the world back the way the document has it")
	assert_eq(world.hands_total(), 2, "with the hands the document starts you holding")


# ---------------------------------------------------------------------------
# Where a run drops you
# ---------------------------------------------------------------------------

func test_naming_a_region_starts_the_run_there():
	world = _run(_doc(), {"region": "second"})
	assert_eq(world.region_id, "second", "the run started in the region it was told to")
	assert_almost_eq(world.player.global_position.x, 1.5 * CS, 1.0,
		"at that region's own authored spawn, since no cell was named")


func test_naming_a_cell_drops_the_player_on_it():
	world = _run(_doc(), {"region": "first", "cell": Vector2i(7, 1)})
	assert_eq(_cell_of(world.player.global_position), Vector2i(7, 1),
		"the player starts in the cell that was picked, not at the region's spawn")


func test_the_run_spawn_survives_a_reset():
	# The point of playing from a cell is trying the same thing again from the same
	# place. A reset that sent you back to the authored spawn would make the second
	# attempt a walk.
	world = _run(_doc(), {"region": "second", "cell": Vector2i(6, 1)})
	world._reset()
	assert_eq(world.region_id, "second", "R keeps the run in the region it started in")
	assert_eq(_cell_of(world.player.global_position), Vector2i(6, 1), "and at its cell")


func test_a_region_that_does_not_exist_falls_back_to_the_world_start():
	# The editor can only name a region it is showing you, but a stale board position
	# or a renamed card must not leave the run with nowhere to be.
	var doc := _doc()
	world = _run(doc, {"region": "nowhere"})
	assert_eq(world.region_id, doc.start_region,
		"an unknown region starts the run where the world says instead")


func test_a_cell_folded_away_falls_back_to_the_region_spawn():
	# A pre-placed fold has taken this cell out of the region entirely. It is not a
	# place yet, so it cannot be started in — and saying so is better than starting
	# the run somewhere that only looks right.
	var doc := _doc()
	doc.regions["first"]["folds"] = [
		{"anchor1": {"x": 5, "y": 0}, "anchor2": {"x": 8, "y": 0}},
	]
	world = _run(doc, {"region": "first", "cell": Vector2i(6, 1)})
	assert_almost_eq(world.player.global_position.x, 1.5 * CS, 1.0,
		"the run started at the region's spawn")
	assert_string_contains(world.hud.flash_text(), "folded away",
		"and said why, rather than starting somewhere silently wrong")


func test_a_cell_carried_by_a_fold_is_resolved_through_the_pieces():
	# The sheet right of the fold has SLID left. Asking for a base cell there and
	# spawning at its base coordinates would drop the player where that ground used to
	# be — which is now thin air, or somebody else's wall.
	var doc := _doc()
	doc.regions["first"]["folds"] = [
		{"anchor1": {"x": 4, "y": 0}, "anchor2": {"x": 6, "y": 0}},
	]
	world = _run(doc, {"region": "first", "cell": Vector2i(8, 1)})
	var at: Vector2 = world.player.global_position
	var piece = BaseFrame.piece_at(world.current_pieces, at, CS)
	assert_not_null(piece, "the player starts inside a piece that is really on screen")
	if piece != null:
		assert_eq(piece.base_id, world.base.tile_at(Vector2i(8, 1)).base_id,
			"and it is the piece of the cell that was asked for, wherever the fold put it")


# ---------------------------------------------------------------------------
# Leaving
# ---------------------------------------------------------------------------

func test_escape_asks_to_leave():
	world = _run(_doc())
	watch_signals(world)
	world._unhandled_input(_key(KEY_ESCAPE))
	assert_signal_emitted(world, "left", "Escape asks whoever opened the run to end it")


func test_escape_asks_to_leave_even_mid_placement():
	# Every other key is refused while a hand is up, because they all move the world.
	# Leaving does not, and a run you have to finish a gesture to get out of is one
	# you will be stuck in on the frame you wanted to leave.
	world = _run(_doc())
	world.tap_action(Vector2i(1, 0))
	assert_true(world.placing(), "a hand is up and the world is stopped")
	watch_signals(world)
	world._unhandled_input(_key(KEY_ESCAPE))
	assert_signal_emitted(world, "left", "and Escape still gets you out")


func test_a_run_nobody_opened_carries_no_session_chrome():
	world = _run(_doc())
	assert_eq(world.hud.session_hint(), "",
		"a world played on its own says nothing about going back, because there is no back")


func test_a_run_says_how_to_leave_when_it_was_opened_by_something():
	var node = load(SCENE).instantiate()
	node.data_override = _doc()
	node.session_hint = "Esc — back to the editor"
	add_child_autofree(node)
	world = node
	assert_eq(world.hud.session_hint(), "Esc — back to the editor",
		"a run opened from somewhere says how to get back there")


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event
