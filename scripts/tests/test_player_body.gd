extends GutTest

## Tests for PlayerBody's camera-facing readings — the things the camera asks the
## body for, because only the body knows its own limits and its own input:
## the held look direction (which also aims anchors), velocity as a fraction of
## those limits, and the motion scalar the zoom reads.
##
## Physics itself (coyote time, jump buffer, squash) is exercised through the real
## scene in `test_fold_world.gd`; this file is about the readings, so it drives
## `velocity` directly and presses keys with `Input.parse_input_event`.

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
	for k in [KEY_W, KEY_S, KEY_UP, KEY_DOWN]:
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
