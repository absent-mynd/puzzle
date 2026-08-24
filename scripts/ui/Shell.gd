class_name Shell extends Node

## Shell
##
## The app. One node that owns what is running, and a stack of SCREENS under it — the
## launcher, the editor, a run of the game. Whole scenes, each of which also runs
## perfectly well on its own.
##
## **Opening a screen SUSPENDS the one below rather than replacing it.** The suspended
## screen leaves the tree and is kept: not drawn, not stepped, not asked about input,
## and otherwise untouched. That is the whole trick behind testing a world from the
## editor — you come back to your camera, your selection, your undo history and your
## unsaved edits, because none of them were ever taken apart. Leaving the tree is what
## does it, rather than a list of properties to disable and put back: a property you
## forget to restore is a bug that shows up an hour later, and there is no such list
## here to forget.
##
## **Where "back" goes is not stored.** It is whatever is under you on the stack, which
## is why a run launched from the editor returns to the editor and the same run
## launched from the launcher returns to the launcher, with neither of them holding a
## field that says so. Same argument as the fold list: a relationship you can derive
## is a relationship that cannot go stale.
##
## **Screens never name this file.** They say what they want by signal — `left`,
## `play_requested`, `edit_requested` — and the shell decides what that means. Two
## reasons, and the second is the load-bearing one:
##
##   - `WorldEditor` and `EditorUI` already record what a mutual `class_name`
##     reference costs, and this would be that shape again.
##   - **A screen must run without a shell.** `godot --path . scenes/world/World.tscn`
##     is a documented way to start the game, `run_editor.sh` was the only way to start
##     the editor for months, and every scene-driven test instantiates a screen
##     directly. With nothing connected, `left` and `play_requested` go nowhere and the
##     screen behaves exactly as it did before this file existed.
##
## See `docs/features/SHELL.md`.

## Boot straight into the editor rather than the launcher: `-- --edit`. Pairs with
## `--world=`, which `WorldData` owns for the game and the editor alike.
const EDIT_FLAG := "--edit"

const LAUNCHER_SCENE := "res://scenes/ui/Launcher.tscn"
const EDITOR_SCENE := "res://scenes/editor/WorldEditor.tscn"
const WORLD_SCENE := "res://scenes/world/World.tscn"

## The screens, bottom first. Exactly one of them — the last — is in the tree.
var _stack: Array[Node] = []


func _ready() -> void:
	open(_screen_for(startup_plan(OS.get_cmdline_user_args())))


## A suspended screen is out of the tree, so nothing else will ever free it — this
## array is the only thing holding it. The shell going away has to take them with it.
##
## On PREDELETE rather than `_exit_tree`, and freeing rather than queueing: this is
## about the shell being DESTROYED, not about it leaving the tree, and by the time a
## queued free came round there would be nothing left to run it.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for screen in _stack:
		if is_instance_valid(screen) and screen.get_parent() == null:
			screen.free()


# ---------------------------------------------------------------------------
# The stack
# ---------------------------------------------------------------------------

## Put a screen on top. Whatever was running is suspended, not discarded.
func open(screen: Node) -> void:
	if screen == null:
		return
	if not _stack.is_empty():
		remove_child(_stack.back())
	_stack.append(screen)
	_wire(screen)
	add_child(screen)


## Leave the top screen and wake the one under it. False when there is nothing under
## it — see `_on_left`, which is where that means something.
func close_top() -> bool:
	if _stack.size() <= 1:
		return false
	var top: Node = _stack.pop_back()
	remove_child(top)
	top.queue_free()
	add_child(_stack.back())
	return true


func depth() -> int:
	return _stack.size()


## What is running, or null before the first screen opens.
func top() -> Node:
	return _stack.back() if not _stack.is_empty() else null


## Connect what a screen has. Not every screen has all three — a run of the game can
## be left but cannot open anything, and asking rather than requiring is what keeps a
## screen free to be a plain scene.
func _wire(screen: Node) -> void:
	if screen.has_signal("left"):
		screen.connect("left", _on_left)
	if screen.has_signal("play_requested"):
		screen.connect("play_requested", _on_play_requested)
	if screen.has_signal("edit_requested"):
		screen.connect("edit_requested", _on_edit_requested)


## Leaving the BOTTOM of the stack is quitting: it is the screen the app opened with,
## and there is nothing underneath it to go back to. Which is why `--edit` boots into
## the editor rather than pushing one — Esc out of the world you came here to edit
## should close the app, not drop you into a launcher you never asked for.
func _on_left() -> void:
	if not close_top():
		get_tree().quit()


func _on_play_requested(source, at: Dictionary) -> void:
	open(play_screen(source, at, back_hint()))


func _on_edit_requested(path: String, region: String) -> void:
	open(edit_screen(path, region, back_hint()))


# ---------------------------------------------------------------------------
# Building a screen
# ---------------------------------------------------------------------------
# One home for how a screen is set up, because the launcher and the editor both open
# runs and they must open the same kind of run.

## A run of the game.
##
## `source` is the two ways there are to have a world: a path to a file, or a
## `WorldData` already in memory. That single difference is the whole distance between
## "play the shipped world" and "playtest the one being edited, unsaved".
static func play_screen(source, at: Dictionary, hint: String) -> Node:
	var run = load(WORLD_SCENE).instantiate()
	if source is WorldData:
		run.data_override = source
	else:
		run.world_override = String(source)
	run.spawn_override = at
	run.session_hint = hint
	return run


static func edit_screen(path: String, region: String, hint: String) -> Node:
	var ed = load(EDITOR_SCENE).instantiate()
	ed.world_override = path
	ed.open_region = region
	ed.session_hint = hint
	return ed


static func launcher_screen() -> Node:
	return load(LAUNCHER_SCENE).instantiate()


## What a screen opened right now should say about leaving. Read off the stack rather
## than passed down, for the same reason the return path is.
func back_hint() -> String:
	var below := top()
	if below is WorldEditor:
		return "Esc — back to the editor"
	if below is Launcher:
		return "Esc — back to the worlds"
	return "Esc — quit"


func _screen_for(plan: Dictionary) -> Node:
	match String(plan.get("open", "launcher")):
		"play":
			return play_screen(String(plan["world"]), {}, back_hint())
		"edit":
			return edit_screen(String(plan["world"]), "", back_hint())
		_:
			return launcher_screen()


# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------

## What to open on boot, as `{"open": "launcher"|"play"|"edit", "world": path}`.
##
## Pure, so the flags' spelling is testable without a process to pass them to — the
## same split `WorldData.path_from_args` makes, and it delegates `--world=` to it
## rather than learning to read it a second way.
##
## Naming a world says you already know which one you want, so you get it. Naming none
## is the question this app opens by asking, and the launcher is where it is asked.
static func startup_plan(args) -> Dictionary:
	var edit := false
	for arg in args:
		if String(arg).strip_edges() == EDIT_FLAG:
			edit = true
	var world := WorldData.path_from_args(args, "")
	if edit:
		return {"open": "edit",
			"world": world if not world.is_empty() else WorldEditor.WORLD_PATH}
	if world.is_empty():
		return {"open": "launcher", "world": ""}
	return {"open": "play", "world": world}
