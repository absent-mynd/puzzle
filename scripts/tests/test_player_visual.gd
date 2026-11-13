extends GutTest

## PlayerVisual: the body's face.
##
## The body is a disc. Two dark pixels on it are the whole of the character, and they
## are worth pinning because each thing they do is a thing the player reads: which way
## you face, where you are pointing a hand, and — the blink — that this is somebody.

const PX := PixelArt.WORLD_PER_PIXEL


func _centre(rects: Array) -> Vector2:
	var sum := Vector2.ZERO
	for r in rects:
		sum += (r as Rect2).get_center()
	return sum / float(rects.size())


func test_there_are_two_eyes() -> void:
	assert_eq(PlayerVisual.eyes(1, 0.0, false).size(), 2)


func test_the_eyes_sit_toward_the_side_you_face() -> void:
	assert_gt(_centre(PlayerVisual.eyes(1, 0.0, false)).x, 0.0, "facing right")
	assert_lt(_centre(PlayerVisual.eyes(-1, 0.0, false)).x, 0.0, "facing left")


func test_facing_left_is_the_mirror_of_facing_right() -> void:
	var right := _centre(PlayerVisual.eyes(1, 0.0, false))
	var left := _centre(PlayerVisual.eyes(-1, 0.0, false))
	assert_almost_eq(left, Vector2(-right.x, right.y), Vector2(0.001, 0.001))


func test_they_look_where_you_point() -> void:
	# Up and down are how you aim a hand, so the face says which you are holding.
	var level := _centre(PlayerVisual.eyes(1, 0.0, false)).y
	assert_lt(_centre(PlayerVisual.eyes(1, -1.0, false)).y, level, "up")
	assert_gt(_centre(PlayerVisual.eyes(1, 1.0, false)).y, level, "down")


func test_eyes_are_whole_art_pixels() -> void:
	# Or they shimmer: half a pixel of eye is a pixel that is there on some frames.
	for facing in [-1, 1]:
		for look in [-1.0, 0.0, 1.0]:
			for blink in [false, true]:
				for r in PlayerVisual.eyes(facing, look, blink):
					for v in [r.position.x, r.position.y, r.size.x, r.size.y]:
						assert_almost_eq(fmod(absf(v), PX), 0.0, 0.0001,
							"%s is on the art grid" % r)


func test_the_eyes_stay_on_the_body() -> void:
	for facing in [-1, 1]:
		for look in [-1.0, 0.0, 1.0]:
			for r in PlayerVisual.eyes(facing, look, false):
				for corner in [r.position, r.end, Vector2(r.position.x, r.end.y),
						Vector2(r.end.x, r.position.y)]:
					assert_lt((corner as Vector2).length(), PlayerBody.RADIUS,
						"an eye that leaves the disc is a floating pixel")


func test_a_blink_closes_them() -> void:
	var open: Rect2 = PlayerVisual.eyes(1, 0.0, false)[0]
	var shut: Rect2 = PlayerVisual.eyes(1, 0.0, true)[0]
	assert_lt(shut.size.y, open.size.y, "a shut eye is a line")
	assert_almost_eq(shut.end.y, open.end.y, 0.0001, "...that closes downward, like a lid")


func test_blinks_are_brief_and_rare_and_do_happen() -> void:
	var shut := 0
	var samples := 4000
	for i in range(samples):
		if PlayerVisual.blinking(float(i) * 0.01):
			shut += 1
	assert_gt(shut, 0, "it blinks")
	assert_lt(float(shut) / float(samples), 0.08, "and is mostly looking")


func test_the_blink_is_a_function_of_the_time_it_is_given() -> void:
	# Which is the world's clock (`paint` passes `WorldClock.now()`), so a held world
	# holds the face too: no eye closes while nothing else can move.
	for t in [0.0, 1.3, 7.77, 123.4]:
		assert_eq(PlayerVisual.blinking(t), PlayerVisual.blinking(t), "no hidden state")
