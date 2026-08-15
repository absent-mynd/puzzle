extends GutTest

## The screen stack: how you get from the launcher to a world, from a world to a run
## of it, and back — with what you were doing still there when you land.
##
## The stack tests drive FAKE screens, because what is being asserted is what happens
## to a screen and not what any particular screen is. The round trip at the bottom
## uses the real editor and the real game, because that is the thing this all exists
## for and a fake cannot be wrong in the way it could be.
##
## Nothing here leaves the bottom screen. Doing that quits the app (`Shell._on_left`),
## which in a test run means quitting the test run.

## A screen that is nothing but the three things a screen can say.
class FakeScreen extends Node:
	signal left
	signal play_requested(source, at)
	signal edit_requested(path, region)

	var entries := 0
	var exits := 0
	## Something a suspended screen must still have when it comes back.
	var work: String = ""

	func _enter_tree() -> void:
		entries += 1

	func _exit_tree() -> void:
		exits += 1


const FIXTURE := "res://worlds/fixtures/kernel.json"

var shell: Shell


## The shell boots into the launcher, which is the bottom of every stack here — and
## the thing that makes popping safe to test.
func before_each() -> void:
	shell = Shell.new()
	add_child_autofree(shell)


# ---------------------------------------------------------------------------
# Booting
# ---------------------------------------------------------------------------

func test_no_flags_opens_the_launcher():
	assert_eq(Shell.startup_plan([]), {"open": "launcher", "world": ""},
		"with no world named, the app opens by asking which one")
	assert_true(shell.top() is Launcher, "and that is what it really opened")


func test_naming_a_world_plays_it():
	var plan := Shell.startup_plan(["--world=testbed"])
	assert_eq(String(plan["open"]), "play", "naming a world says you know which one you want")
	assert_eq(String(plan["world"]), "res://worlds/testbed.json",
		"spelled the one way — WorldData owns the flag, for the game and the editor alike")


func test_the_edit_flag_opens_the_editor_on_it():
	var plan := Shell.startup_plan(["--world=testbed", "--edit"])
	assert_eq(String(plan["open"]), "edit", "--edit says which side of the world you want")
	assert_eq(String(plan["world"]), "res://worlds/testbed.json", "and it is still that world")


func test_the_edit_flag_alone_edits_the_shipped_world():
	assert_eq(Shell.startup_plan(["--edit"]),
		{"open": "edit", "world": WorldEditor.WORLD_PATH},
		"--edit with no world is the old ./run_editor.sh with no argument")


# ---------------------------------------------------------------------------
# The stack
# ---------------------------------------------------------------------------

func test_opening_a_screen_suspends_the_one_below():
	var below: Node = shell.top()
	shell.open(FakeScreen.new())
	assert_eq(shell.depth(), 2, "two screens are on the stack")
	assert_null(below.get_parent(), "and the one below has left the tree — not drawn, not stepped")


func test_a_suspended_screen_is_kept_exactly_as_it_was():
	var screen := FakeScreen.new()
	shell.open(screen)
	screen.work = "half-finished"
	shell.open(FakeScreen.new())
	shell.close_top()
	await get_tree().process_frame     # the screen you left is a queued free
	assert_eq(shell.top(), screen, "the screen underneath came back")
	assert_eq(screen.work, "half-finished",
		"and it is the same object, with what you were doing still in it")
	assert_eq(screen.entries, 2, "it re-entered the tree rather than being rebuilt")


func test_leaving_frees_the_screen_you_left():
	var screen := FakeScreen.new()
	shell.open(screen)
	shell.close_top()
	await get_tree().process_frame
	assert_false(is_instance_valid(screen), "a screen you have left is gone, not stashed")


func test_the_bottom_of_the_stack_cannot_be_popped():
	assert_false(shell.close_top(), "there is nothing under the first screen")
	assert_eq(shell.depth(), 1, "so the stack is unchanged")


func test_a_screen_asking_to_leave_pops_it():
	var screen := FakeScreen.new()
	shell.open(screen)
	screen.left.emit()
	await get_tree().process_frame
	assert_eq(shell.depth(), 1, "saying `left` is how a screen gets closed")


# ---------------------------------------------------------------------------
# What a request opens
# ---------------------------------------------------------------------------

func test_a_play_request_with_a_path_opens_a_run_of_that_file():
	var screen := FakeScreen.new()
	shell.open(screen)
	screen.play_requested.emit(FIXTURE, {})
	assert_eq(shell.depth(), 3, "a run opened on top")
	assert_eq(shell.top().world_override, FIXTURE, "of the world that was named")
	assert_null(shell.top().data_override, "read from disk, since a path is all there was")


func test_a_play_request_with_a_document_opens_a_run_of_what_is_in_memory():
	var doc := WorldData.load_from(FIXTURE)
	var screen := FakeScreen.new()
	shell.open(screen)
	screen.play_requested.emit(doc, {"region": "west"})
	assert_eq(shell.top().data_override, doc, "the run plays the document it was handed")
	assert_eq(shell.top().spawn_override, {"region": "west"}, "starting where it was told")


func test_an_edit_request_opens_the_editor_on_the_region_it_names():
	var screen := FakeScreen.new()
	shell.open(screen)
	screen.edit_requested.emit(FIXTURE, "west")
	assert_true(shell.top() is WorldEditor, "the editor opened")
	assert_eq(shell.top().world_override, FIXTURE, "on the world that was named")
	assert_eq(shell.top().open_region, "west", "looking at the region that was named")


func test_what_leaving_goes_back_to_is_read_off_the_stack():
	assert_eq(shell.back_hint(), "Esc — back to the worlds",
		"opened from the launcher, a screen says so")
	shell.open(Shell.edit_screen(FIXTURE, "", ""))
	assert_eq(shell.back_hint(), "Esc — back to the editor",
		"and opened from the editor it says that instead — nothing stored either time")


# ---------------------------------------------------------------------------
# The round trip, for real
# ---------------------------------------------------------------------------

func test_playtesting_from_the_editor_and_coming_back():
	var editor := Shell.edit_screen(FIXTURE, "", "")
	shell.open(editor)
	await get_tree().process_frame
	await get_tree().process_frame

	editor.doc.paint("west", Vector2i(4, 4), "#")
	editor.doc.end_gesture()
	editor.select_region("east")
	editor.set_tool(editor.Tool.LIGHT)
	editor.zoom_at(Vector2.ZERO, 2.0)
	assert_true(editor.doc.dirty, "an edit that has not been saved")
	var history: bool = editor.doc.can_undo()
	var view := [editor.cam.position, editor.cam.zoom]

	editor.playtest({"region": "west"})
	assert_eq(shell.depth(), 3, "F5 put a run of the game on top")
	assert_eq(shell.top().world_data.world_id, editor.doc.world.world_id,
		"and it is playing the world that was being edited")

	shell.top().left.emit()
	await get_tree().process_frame     # the run leaving is a queued free
	assert_eq(shell.top(), editor, "Escape came back to the editor that launched it")
	assert_true(editor.doc.dirty, "with the unsaved edit still unsaved")
	assert_eq(editor.doc.can_undo(), history, "and the undo history still behind it")
	assert_eq(editor.doc.char_at("west", Vector2i(4, 4)), "#", "and the edit still there")
	assert_eq(editor.selected_region, "east", "the card you were working on still selected")
	assert_eq(editor.tool, editor.Tool.LIGHT, "the tool you had in your hand still armed")
	assert_eq([editor.cam.position, editor.cam.zoom], view, "and the view exactly where you left it")
	assert_true(editor.cam.is_current(), "with its camera driving the screen again")
