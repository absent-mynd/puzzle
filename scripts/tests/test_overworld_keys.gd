extends GutTest

## The shipped world, played on the keys.
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
## `threshold` is played whole, because it is the room that teaches the verb and it
## uses every part of the gesture — a pin beside you, a pin from the top of a jump, the
## fuse, the ride, the charged release.
##
## Two more rooms are played for the one move in each that the model only ASSERTS.
## `WorldProbe` treats water as free movement and has no idea a space can wrap, so
## "swim out of the waterfall onto the cliff" and "walk back through the glue into the
## chamber" were claims nobody had run. Those tests set the fold up directly — that
## part is already proved — and then put down the API and pick up the keys.
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


func _open(region: String) -> void:
	world = load(SCENE).instantiate()
	world.world_override = WorldData.SHIPPED_WORLD
	world.spawn_override = {"region": region}
	add_child_autofree(world)


## Where a BASE cell of this region is now, as a cell.
func _now(base_cell: Vector2i) -> Vector2i:
	var tile = world.base.tile_at(base_cell)
	var wp = BaseFrame.world_point_from_base(world.current_pieces, tile.base_id,
		world.cell_center(base_cell))
	assert_not_null(wp, "base cell %s is in this space" % base_cell)
	return Vector2i((Vector2(wp) / CS).floor()) if wp != null else base_cell


## Hold the fold key until the burst is loaded, then let go.
func _burst() -> void:
	_send(KEY_F, true)
	for _i in range(600):
		await get_tree().process_frame
		if world.hold_loaded():
			break
	assert_true(world.hold_loaded(), "holding loads the burst")
	_send(KEY_F, false)


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
	_open("threshold")
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


func test_cistern_the_swim_out_onto_the_cliff() -> void:
	_open("cistern")
	world.anim_enabled = false
	await _steps(5)
	# The fold, set up directly: a hand in the air beside the water, at the lip's height.
	world.player.teleport(world.cell_center(Vector2i(9, 5)), false)
	assert_true(world.place_hand(Vector2i(10, 5)))
	world._physics_process(1.0 / 60.0)
	world._tick_fuse(10.0)
	assert_eq(world.folds.size(), 1, "the dry gap is folded away")

	# From down in the waterfall: up past the lip on the jump key, then over.
	var deep: Vector2i = _now(Vector2i(9, 9))
	var lip: Vector2i = _now(Vector2i(18, 5))
	world.player.teleport(world.cell_center(deep), false)
	await _steps(3)
	assert_true(world.player.in_water, "you start in the water")
	_hold(KEY_SPACE, true)
	assert_true(await _until(func() -> bool:
		return world.player.global_position.y < (float(lip.y) + 0.2) * CS, 600),
		"the jump key carries you up the waterfall, past the height of the lip")
	_hold(KEY_D, true)
	var on_the_cliff := func() -> bool:
		return world.player.is_on_floor() and not world.player.in_water \
			and world.player_cell().x >= lip.x and world.player_cell().y == lip.y
	assert_true(await _until(on_the_cliff, 600), "and holding right puts you on the cliff")
	_hold(KEY_D, false)
	_hold(KEY_SPACE, false)

	# Pinned at the top, so it comes apart from the top.
	_hold(KEY_A, true)
	await _until(func() -> bool:
		return world.player.global_position.x <= (float(lip.x) + 0.75) * CS, 300)
	_hold(KEY_A, false)
	await _steps(20)
	await _burst()
	assert_true(await _until(func() -> bool: return world.folds.is_empty(), 300),
		"a burst from the cliff's edge reaches the seam")
	await _steps(20)
	assert_eq(world.hands_held(), 2)
	assert_true(world.player.is_on_floor(), "and leaves you standing")
	assert_eq(world.player_cell().y, 5, "...on top of the cliff")


func test_annex_the_walk_back_through_the_glue() -> void:
	_open("annex")
	world.anim_enabled = false
	await _steps(5)
	# Folded in, set up directly: a hand behind you, and you against the chamber wall.
	world.player.teleport(world.cell_center(Vector2i(12, 11)) + Vector2(0, 12), false)
	assert_true(world.place_hand(Vector2i(11, 11)))
	world.player.teleport(world.cell_center(Vector2i(13, 11)) + Vector2(0, 12), false)
	world._physics_process(1.0 / 60.0)
	world._tick_fuse(10.0)
	assert_eq(world.mode, world.Mode.SUBSPACE, "standing in the strip, you are folded in")
	await _steps(5)

	# Now just walk the WRONG way — away from the wall, back the way you came.
	var started: float = world.player.global_position.x
	_hold(KEY_A, true)
	assert_true(await _until(func() -> bool: return world.sigils_count() == 1, 900),
		"walking away from the chamber wall brings you to the sigil inside it")
	_hold(KEY_A, false)
	assert_gt(world.player.global_position.x, started,
		"you walked left and ended up to the RIGHT of where you began: through the glue")
	assert_eq(world.mode, world.Mode.SUBSPACE, "still inside the fold")

	# Back toward the glue you came through, and surface beside it.
	await _steps(20)
	_hold(KEY_D, true)
	await _until(func() -> bool: return world.player.global_position.x >= 20.7 * CS, 600)
	_hold(KEY_D, false)
	await _steps(20)
	assert_true(world.glue_within_burst(), "the way out is in reach")
	await _burst()
	assert_true(await _until(func() -> bool: return world.mode == world.Mode.WORLD, 300),
		"the fold opens")
	await _steps(20)
	assert_eq(world.hands_held(), 2, "your hand comes back")
	assert_between(world.player_cell().x, 16, 21, "and you are inside the sealed chamber")
	assert_true(world.player.is_on_floor())
