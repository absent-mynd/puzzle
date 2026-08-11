extends GutTest

## Tests for PlayerBody's readings and its jump arithmetic — the things that can
## be asked of the body without running it: the held look direction (which also
## aims anchors), the jump press EDGE, velocity as a fraction of the body's own
## limits, the motion scalar the zoom reads, and the gravity the jump is shaped by.
##
## The jump is variable-height, and its shape is `gravity_scale` — a pure function
## of "which way am I going" and "am I still holding it". `jump_height_for_hold`
## integrates the very step the body takes, so the heights asserted here are the
## heights you get in the world, and the level-design bounds (a tap clears one
## cell, a full hold two, nothing clears three) are pinned rather than hoped for.
##
## The rest of the physics (coyote time, buffering, squash) is exercised through
## the real scene in `test_fold_world.gd`; this file drives `velocity` directly
## and presses keys with `Input.parse_input_event`.

var body: PlayerBody


func before_each() -> void:
	body = PlayerBody.new()
	add_child_autofree(body)


func after_each() -> void:
	_release_all()


func _press(keycode: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release_all() -> void:
	for k in [KEY_W, KEY_S, KEY_UP, KEY_DOWN, KEY_SPACE]:
		_press(k, false)


# ---------------------------------------------------------------------------
# Held look direction — shared by anchor aiming and the camera's lead
# ---------------------------------------------------------------------------

func test_look_dir_is_zero_with_nothing_held() -> void:
	assert_eq(body.look_dir(), 0.0, "No vertical keys: no vertical intent")
	assert_eq(body.point_dir(), Vector2i(1, 0), "...so you point where you face")


func test_look_dir_reads_both_key_sets() -> void:
	for up in [KEY_W, KEY_UP]:
		_press(up, true)
		assert_eq(body.look_dir(), -1.0, "Up is negative (key %d)" % up)
		assert_eq(body.point_dir(), Vector2i(0, -1), "Held up aims the anchor up")
		_press(up, false)
	for down in [KEY_S, KEY_DOWN]:
		_press(down, true)
		assert_eq(body.look_dir(), 1.0, "Down is positive (key %d)" % down)
		assert_eq(body.point_dir(), Vector2i(0, 1), "Held down aims the anchor down")
		_press(down, false)


func test_up_wins_when_both_are_held() -> void:
	# Not a cancel: a player mashing both should still get a definite direction,
	# and anchor placement has always resolved this as up.
	_press(KEY_W, true)
	_press(KEY_S, true)
	assert_eq(body.look_dir(), -1.0, "Both held resolves to up, not to nothing")
	assert_eq(body.point_dir(), Vector2i(0, -1), "The anchor aims up too")


func test_pointing_follows_facing_when_you_hold_nothing() -> void:
	body.facing = -1
	assert_eq(body.point_dir(), Vector2i(-1, 0), "Facing left, you point left")
	body.facing = 1
	assert_eq(body.point_dir(), Vector2i(1, 0), "Facing right, you point right")


# ---------------------------------------------------------------------------
# The jump press is an edge
# ---------------------------------------------------------------------------

func test_the_jump_press_is_an_edge_not_a_held_state() -> void:
	assert_false(body.take_jump_press(), "Nothing held is not a press")
	_press(KEY_SPACE, true)
	assert_true(body.take_jump_press(), "Pressing it is a press")
	assert_false(body.take_jump_press(), "...and keeping it down is not another one")
	assert_false(body.take_jump_press(), "...however many frames you hold it for")


func test_releasing_and_pressing_again_is_a_fresh_press() -> void:
	# The whole point of the edge: hold does not mean "jump again the moment you
	# land". Bouncing off the floor with the key down would spend the hold that
	# was supposed to be shaping the jump you are already in.
	_press(KEY_SPACE, true)
	assert_true(body.take_jump_press(), "First press")
	_press(KEY_SPACE, false)
	assert_false(body.take_jump_press(), "Letting go is not a press")
	_press(KEY_SPACE, true)
	assert_true(body.take_jump_press(), "Pressing again is")


# ---------------------------------------------------------------------------
# The gravity the jump is shaped by
# ---------------------------------------------------------------------------

func test_a_held_rise_gets_plain_gravity() -> void:
	# Holding it is the full jump — the arc everything else is measured against.
	assert_almost_eq(PlayerBody.gravity_scale(-400.0, true), 1.0, 0.001,
		"Rising with the key held is the unmodified arc")


func test_letting_go_mid_rise_makes_gravity_bite() -> void:
	var held := PlayerBody.gravity_scale(-400.0, true)
	var released := PlayerBody.gravity_scale(-400.0, false)
	assert_gt(released, held, "Releasing mid-rise pulls you down sooner")
	assert_almost_eq(released, PlayerBody.JUMP_CUT_GRAVITY, 0.001,
		"...by exactly the cut multiplier")


func test_falling_is_heavier_than_rising() -> void:
	assert_gt(PlayerBody.gravity_scale(400.0, false), PlayerBody.gravity_scale(-400.0, true),
		"A landing should arrive sooner than the rise that earned it")


func test_holding_does_nothing_once_you_are_falling() -> void:
	# Sustain is a rise-only affordance; a held key must never slow a fall.
	assert_almost_eq(PlayerBody.gravity_scale(400.0, true),
		PlayerBody.gravity_scale(400.0, false), 0.001,
		"Falling weighs the same whether or not you are still holding it")


func test_the_apex_is_lighter_than_either_side_of_it() -> void:
	# The hang at the top: the frames where you are barely moving vertically are
	# the frames you steer in, so they are the ones worth having more of.
	assert_lt(PlayerBody.gravity_scale(-40.0, true), PlayerBody.gravity_scale(-400.0, true),
		"The last of the rise is lighter than the start of it")
	assert_lt(PlayerBody.gravity_scale(40.0, false), PlayerBody.gravity_scale(400.0, false),
		"...and the first of the fall lighter than the rest of it")


# ---------------------------------------------------------------------------
# Tap versus hold — the jump height that falls out of all of that
# ---------------------------------------------------------------------------

func test_a_tap_is_a_shorter_jump_than_a_hold() -> void:
	assert_lt(PlayerBody.jump_height_for_hold(0.0), PlayerBody.jump_height_for_hold(1.0),
		"Tapping gets you less height than holding")


func test_height_grows_with_how_long_you_held_it() -> void:
	# Not two jumps but a continuum: every millisecond of hold you spend buys
	# height, which is what makes "how long did you tap for" an input at all.
	var last := 0.0
	for i in range(10):
		var h := PlayerBody.jump_height_for_hold(i * 0.04)
		assert_gt(h, last, "Holding %0.2fs beats holding %0.2fs" % [i * 0.04, (i - 1) * 0.04])
		last = h


func test_holding_past_the_apex_buys_nothing_more() -> void:
	# The hold window is the rise itself; there is no charge that keeps paying,
	# and no second jump waiting at the end of a long press.
	assert_almost_eq(PlayerBody.jump_height_for_hold(1.0),
		PlayerBody.jump_height_for_hold(5.0), 0.001,
		"Once the rise is over, more hold is just more hold")


func test_a_tap_clears_one_cell_and_a_full_hold_two_but_never_three() -> void:
	# The world is authored against these: the pinned pillar is two tiles and is
	# meant to be jumped, the plate's wall is three and is meant to need a fold.
	# Both bounds are level design, not feel — changing them changes the world.
	var tap := PlayerBody.jump_height_for_hold(0.0)
	var full := PlayerBody.jump_height_for_hold(1.0)
	assert_gt(tap, WorldCore.CELL, "A tap clears a one-tile step")
	assert_lt(tap, 2.0 * WorldCore.CELL, "...and no more than that")
	assert_gt(full, 2.0 * WorldCore.CELL, "A full hold clears the two-tile pillar")
	assert_lt(full, 3.0 * WorldCore.CELL, "...and never the three-tile wall")


func test_a_long_fall_still_stops_at_terminal_speed() -> void:
	# The heavier fall multiplier gets you TO terminal sooner; it must not carry
	# you past it, or `motion_fraction` would report more than a full fall.
	var vy := 0.0
	for _i in range(600):
		vy = PlayerBody.step_fall(vy, false, 1.0 / 60.0)
	assert_almost_eq(vy, PlayerBody.MAX_FALL, 0.001, "Ten seconds of falling is terminal, not more")


# ---------------------------------------------------------------------------
# Velocity as a fraction of the body's own limits
# ---------------------------------------------------------------------------

func test_motion_fraction_is_signed_and_normalized_per_axis() -> void:
	body.velocity = Vector2(PlayerBody.RUN_SPEED, 0)
	assert_almost_eq(body.motion_fraction().x, 1.0, 0.001, "A full run reads as 1")
	body.velocity = Vector2(-PlayerBody.RUN_SPEED, 0)
	assert_almost_eq(body.motion_fraction().x, -1.0, 0.001, "...and -1 going the other way")
	body.velocity = Vector2(PlayerBody.RUN_SPEED * 0.5, 0)
	assert_almost_eq(body.motion_fraction().x, 0.5, 0.001, "Half speed reads as half")


func test_motion_fraction_uses_a_different_limit_up_than_down() -> void:
	# Terminal fall and jump launch are different speeds; "all-out" has to mean
	# each of them, or a jump would read as a fraction of a fall.
	body.velocity = Vector2(0, PlayerBody.MAX_FALL)
	assert_almost_eq(body.motion_fraction().y, 1.0, 0.001, "Terminal fall is a full 1 down")
	body.velocity = Vector2(0, PlayerBody.JUMP_VELOCITY)
	assert_almost_eq(body.motion_fraction().y, -1.0, 0.001,
		"A fresh jump is a full -1 up, measured against the launch not the fall")


func test_motion_fraction_never_leaves_the_unit_box() -> void:
	body.velocity = Vector2(99999, 99999)
	var f := body.motion_fraction()
	assert_almost_eq(f.x, 1.0, 0.001, "Absurd speeds clamp")
	assert_almost_eq(f.y, 1.0, 0.001, "...on both axes")


# ---------------------------------------------------------------------------
# The motion scalar the zoom reads
# ---------------------------------------------------------------------------

func test_motion_intensity_weights_falling_heaviest() -> void:
	body.velocity = Vector2(PlayerBody.RUN_SPEED, 0)
	var running := body.motion_intensity()
	body.velocity = Vector2(0, PlayerBody.MAX_FALL)
	var falling := body.motion_intensity()
	body.velocity = Vector2(0, PlayerBody.JUMP_VELOCITY)
	var rising := body.motion_intensity()
	assert_gt(falling, running, "A fall opens the frame more than a run")
	assert_gt(running, rising, "...and a run more than a rise")
	assert_almost_eq(body.motion_intensity(), rising, 0.001, "Reading it twice is stable")


func test_motion_intensity_is_bounded_and_still_at_rest() -> void:
	body.velocity = Vector2.ZERO
	assert_eq(body.motion_intensity(), 0.0, "Standing still is not moving")
	body.velocity = Vector2(99999, 99999)
	assert_almost_eq(body.motion_intensity(), 1.0, 0.001, "It saturates at 1")


func test_frozen_reports_still_however_stale_the_velocity_is() -> void:
	# Riding a fold, the velocity is left over from before the transition and the
	# transition frames itself from its own endpoints.
	body.velocity = Vector2(PlayerBody.RUN_SPEED, PlayerBody.MAX_FALL)
	assert_gt(body.motion_intensity(), 0.0, "Moving hard while free")
	body.frozen = true
	assert_eq(body.motion_intensity(), 0.0, "Frozen reads as still")


# ---------------------------------------------------------------------------
# The release charge, worn as a colour
# ---------------------------------------------------------------------------
# The body is the burst indicator. It is handed a 0..1 charge by the world and
# knows nothing else about folding; the SHAPE of the blend is the whole of what a
# player reads off it, so the shape is what these pin.


## How far along BODY_COLOR -> CHARGE_COLOR a given charge lands, 0..1. Read off
## blue, which is the channel the two colours are furthest apart in.
func _tint(charge: float) -> float:
	var col := PlayerBody.charge_color(charge)
	return (col.b - PlayerBody.BODY_COLOR.b) \
		/ (PlayerBody.CHARGE_COLOR.b - PlayerBody.BODY_COLOR.b)


func test_an_uncharged_body_is_its_own_colour() -> void:
	assert_eq(PlayerBody.charge_color(0.0), PlayerBody.BODY_COLOR,
		"Nothing held, nothing to say")
	assert_eq(body.visual_color(), PlayerBody.BODY_COLOR, "...and that is the default state")


func test_the_charge_shows_late_rather_than_early() -> void:
	# Squared on the way up, on purpose: taps are the common press by a wide margin,
	# and a body that flickered on every hand you put down would be noise. The tint
	# arrives near the threshold, which is where the thing it warns about is.
	assert_lt(_tint(0.25), 0.05, "A quarter in — the length of a tap — is invisible")
	assert_gt(_tint(0.9), _tint(0.5) * 2.0, "...and it is well underway by the end")
	assert_lt(_tint(0.99), PlayerBody.LOADED_TINT,
		"Never as far as loaded until it actually is")


func test_loaded_is_a_step_and_not_the_top_of_the_ramp() -> void:
	# "Ready" is a different fact from "nearly ready", and the pop waits for your
	# finger now — so it has to be legible with nothing to compare against.
	assert_almost_eq(_tint(1.0), PlayerBody.LOADED_TINT, 0.001, "Loaded wears the full tint")
	assert_gt(_tint(1.0) - _tint(0.99), 0.3, "...and arrives in a step you cannot miss")


func test_the_charge_is_clamped_at_both_ends() -> void:
	assert_eq(PlayerBody.charge_color(-1.0), PlayerBody.BODY_COLOR, "Below zero is idle")
	assert_eq(PlayerBody.charge_color(4.0), PlayerBody.charge_color(1.0),
		"Holding longer does not tint harder — loaded is loaded")


func test_the_body_wears_whatever_charge_it_is_handed() -> void:
	body.fold_charge = 1.0
	assert_eq(body.visual_color(), PlayerBody.charge_color(1.0),
		"visual_color is the charge, and nothing else feeds it")
