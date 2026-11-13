extends GutTest

## The first room, played on the keys.
##
## `test_overworld_solutions.gd` proves every room CAN be done, by putting hands where
## an arm could put them and the body where a model says it could walk. That is a claim
## about the world. This is the other claim, the one a model cannot make: that the
## thing a player actually does — hold a key, tap a key, let go — does it.
##
## So nothing here calls `place_hand` or `teleport`. Movement is real key state read by
## the real body under real physics; the fold key goes to the world as key events; the
## fuse burns in the world's own frames and the fold plays its own animation. If the
## cursor could not reach the cell, or the top of a jump were not a place a hand can be
## raised, or the unfold did not carry you, this is what would say so.
##
## One room, because it is slow by this suite's standards and because one is what it
## takes: `threshold` is the room that teaches the verb, and it uses every part of the
## gesture — a pin beside you, a pin from the top of a jump, the fuse, the ride, the
## charged release.
##
## Time is run four times faster and the step kept the same size (`Engine.time_scale`
## with `physics_ticks_per_second` scaled to match), so the simulation is the one a
## player gets and the wait is not.

const SCENE := "res://scenes/world/World.tscn"
const CS := 64.0
const SPEED := 4

var world
var _ticks := 60


func before_each() -> void:
	_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = _ticks * SPEED
	Engine.time_scale = float(SPEED)
	world = load(SCENE).instantiate()
	world.world_override = WorldData.SHIPPED_WORLD
	world.spawn_override = {"region": "threshold"}
	add_child_autofree(world)


func after_each() -> void:
	for code in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE]:
		_hold(code, false)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = _ticks


## A movement key, as state the body polls.
func _hold(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


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


## Run the world until `done` says so. Returns whether it did, within `limit` steps.
func _until(done: Callable, limit := 900) -> bool:
	for _i in range(limit):
		if done.call():
			return true
		await get_tree().physics_frame
	return done.call()


func test_threshold_played_on_the_keys() -> void:
	await _steps(20)
	assert_true(world.player.is_on_floor(), "you start standing")

	# Run to the foot of the ledge.
	_hold(KEY_D, true)
	await _until(func() -> bool: return world.player.global_position.x >= 11.3 * CS)
	_hold(KEY_D, false)
	await _steps(30)
	assert_eq(world.player_cell(), Vector2i(11, 11), "stopped under the ledge's end")

	# One hand beside you: raise, and it is already on the cell you face.
	_tap(KEY_F)
	assert_true(world.placing(), "a tap raises a hand and stops the clock")
	assert_eq(world.aim_cell(), Vector2i(12, 11), "the cursor starts where you point")
	_tap(KEY_F)
	assert_false(world.placing(), "a second tap pins it")
	assert_true(world.anchor_cells().has(Vector2i(12, 11)))

	# The other from the top of a jump. Raising it there holds you there.
	_hold(KEY_SPACE, true)
	var near_apex := func() -> bool:
		return not world.player.is_on_floor() and world.player.velocity.y > -150.0
	assert_true(await _until(near_apex, 120), "the jump has a top")
	_tap(KEY_F)
	assert_true(world.placing(), "a hand can be raised in mid-air")
	var hung: Vector2 = world.player.global_position
	for _i in range(3):
		if world.aim_cell().y <= 8:
			break
		_tap(KEY_W)
	assert_eq(world.aim_cell(), Vector2i(12, 8), "the cursor walks up to the ledge's own end")
	await _steps(30)
	assert_eq(world.player.global_position, hung, "and the world waited while it did")
	_tap(KEY_F)
	_hold(KEY_SPACE, false)
	assert_eq(world.armed_pairs().size(), 1, "two hands within reach: a pair, and a fuse")

	# Nothing commits it. The fuse does, and you ride.
	var folded := func() -> bool:
		return world.folds.size() == 1 and not world.animating()
	assert_true(await _until(folded, 400), "the fuse folds it without another press")
	assert_eq(world.mode, world.Mode.WORLD, "you landed before it went, so you rode it")

	# The ledge is a step now. Up, and along to the sigil.
	_hold(KEY_D, true)
	_hold(KEY_SPACE, true)
	assert_true(await _until(func() -> bool: return world.sigils_count() == 1, 900),
		"a jump and a run reach the sigil on the lowered ledge")
	_hold(KEY_SPACE, false)
	_hold(KEY_D, false)

	# Back to the ledge's end, which is where you pinned and so where the seam is.
	_hold(KEY_A, true)
	await _until(func() -> bool: return world.player.global_position.x <= 12.8 * CS)
	_hold(KEY_A, false)
	await _steps(30)
	assert_eq(world.player_cell().x, 12, "standing on the ledge's end")

	# Hold until the body turns, then let go: the burst is the release.
	_send(KEY_F, true)
	var loaded := false
	for _i in range(600):
		await get_tree().process_frame
		if world.hold_loaded():
			loaded = true
			break
	assert_true(loaded, "holding loads the burst")
	assert_eq(world.folds.size(), 1, "...and loading it does nothing yet")
	_send(KEY_F, false)

	var unfolded := func() -> bool:
		return world.folds.is_empty() and not world.animating()
	assert_true(await _until(unfolded, 400), "letting go takes the fold apart")
	await _steps(30)
	assert_eq(world.hands_held(), 2, "both hands come home")
	assert_eq(world.player_cell(), Vector2i(12, 7), "and the unfold has carried you up the ledge")
