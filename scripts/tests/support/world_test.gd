extends GutTest

## WorldTest
##
## What every test that drives the real world scene needs, written once: open a world,
## step it, say where a tile has got to, and press keys at it.
##
## Three suites grew their own copies of these — `_frame` in one and `_frames` in the
## next, `_put` and `_stand` for the same teleport — and a helper spelled two ways is
## two things to keep true. Extend this instead of `GutTest` and the vocabulary is the
## same everywhere:
##
##   _open_world(path, region, cell)   boot a world, optionally in a region / at a cell
##   _frames(n)                        the world's own per-frame logic, n times, NOW
##   _fuse()                           one frame, then burn every fuse that is lit
##   _stand(cell)                      put the body standing in a cell
##   _now(base_cell)                   where that tile is, after whatever has folded
##
## and, for tests that play rather than place:
##
##   _hold(key, down)                  a movement key, as state the body polls
##   _send(key, down) / _tap(key)      a key the WORLD listens for, as an event
##   _steps(n) / _until(cond, limit)   let real physics frames go by
##   _charge_and_release()             hold the fold key until loaded, then let go
##
## The first group is synchronous and teleports: it is for asking what the rules do.
## The second runs the engine: it is for asking whether a player's hands can do it.
## A file may use both, and should say which claim each test is making.
##
## `test_fold_world.gd` predates this and keeps its own helpers; it is 2500 lines of
## working tests and not worth the churn.

const SCENE := "res://scenes/world/World.tscn"
const CS := 64.0
const DT := 1.0 / 60.0

var world


func _open_world(path: String, region := "", cell = null) -> void:
	world = load(SCENE).instantiate()
	world.world_override = path
	if region != "":
		world.spawn_override = {"region": region}
		if cell != null:
			world.spawn_override["cell"] = cell
	add_child_autofree(world)
	world.anim_enabled = false


# ---------------------------------------------------------------------------
# Placing: synchronous, for what the rules do
# ---------------------------------------------------------------------------

## The world's per-frame logic, as `_physics_process` runs it. The body is not stepped:
## it is where `_stand` or a fold put it.
func _frames(n := 1) -> void:
	for _i in range(n):
		world._physics_process(DT)


## One frame — so pairs form and plates are read — then burn every fuse.
func _fuse() -> void:
	_frames()
	world._tick_fuse(10.0)


## Put the body standing in a cell: on the floor of it, not floating at its centre.
func _stand(cell: Vector2i) -> void:
	world.player.teleport(world.cell_center(cell) + Vector2(0, 12), false)


## Where a BASE cell of the current region is now, as a cell. Folds slide the sheet —
## the plate you just stood on rode its flap along with you — so anything a test says
## about a tile after a fold has to be said about the tile, not about where it started.
func _now(base_cell: Vector2i) -> Vector2i:
	var tile = world.base.tile_at(base_cell)
	var wp = BaseFrame.world_point_from_base(world.current_pieces, tile.base_id,
		world.cell_center(base_cell))
	assert_not_null(wp, "base cell %s is in this space" % base_cell)
	if wp == null:
		return base_cell
	return Vector2i((Vector2(wp) / CS).floor())


# ---------------------------------------------------------------------------
# Playing: real frames and real keys, for what a player's hands can do
# ---------------------------------------------------------------------------

## The keys this file ever holds, so a test that fails mid-press cannot leave one down
## for the next.
const HELD_KEYS := [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE]


## A movement key, as state the body polls.
func _hold(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release_keys() -> void:
	for code in HELD_KEYS:
		_hold(code, false)


## A key the WORLD listens for, delivered the way the engine delivers it.
func _send(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	world._unhandled_input(ev)


func _tap(code: int) -> void:
	_send(code, true)
	_send(code, false)


func _steps(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


## Run the engine until `done` says so. Returns whether it did, within `limit` steps.
func _until(done: Callable, limit := 900) -> bool:
	for _i in range(limit):
		if done.call():
			return true
		await get_tree().physics_frame
	return done.call()


## Hold the fold key until the burst is loaded, then let go. The charge runs on the
## frame's own time, not the world's, so this waits on process frames.
func _charge_and_release() -> void:
	_send(KEY_F, true)
	for _i in range(600):
		await get_tree().process_frame
		if world.hold_loaded():
			break
	assert_true(world.hold_loaded(), "holding loads the burst")
	_send(KEY_F, false)
