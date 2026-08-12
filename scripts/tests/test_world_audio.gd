extends GutTest

## What the world SOUNDS like.
##
## `test_audio_manager` pins the playback engine; this pins the wiring — that
## the fold vocabulary reaches the audio system at the right moments, and that
## refusals are audibly different from the things they refuse.
##
## The suite needs this file specifically because the last audio system rotted
## in the gap it fills: `AudioManager` was tested, complete and correct, and
## absolutely nothing in the game called it. A test of the engine alone cannot
## tell you that.
##
## Everything here reads `AudioManager.sfx_played`, which fires only when a
## voice actually starts — so these assert what the player would HEAR, not what
## the code asked for.

const SCENE := "res://scenes/world/World.tscn"
## The suite's OWN world, not the shipped one. These tests assert against concrete
## geometry — a pit here, a wall there, a door with that partner — so they must not
## inherit whichever level happens to be shipping. See worlds/fixtures/README.md.
const FIXTURE := "res://worlds/fixtures/kernel.json"
const CS := 64.0

var world
var heard: Array = []


func before_each() -> void:
	world = load(SCENE).instantiate()
	world.world_override = FIXTURE
	add_child_autofree(world)
	world.anim_enabled = false
	# The retrigger floors are wall-clock, and a whole test file runs inside a
	# few of their windows — without this, the second test to refuse something
	# is silently throttled and asserts nothing.
	AudioManager._last_played.clear()
	AudioManager._warned.clear()
	AudioManager.sfx_played.connect(_on_sfx)


func after_each() -> void:
	if AudioManager.sfx_played.is_connected(_on_sfx):
		AudioManager.sfx_played.disconnect(_on_sfx)


func _on_sfx(name: String) -> void:
	heard.append(name)


## Forget everything heard so far. Called immediately before the action under
## test, so that setting a scenario up does not colour its assertions.
func _listen() -> void:
	heard.clear()


func _heard(name: String) -> bool:
	return heard.has(name)


func _count(name: String) -> int:
	var n := 0
	for h in heard:
		if h == name:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Placing hands
# ---------------------------------------------------------------------------

func test_placing_a_hand_is_heard() -> void:
	_listen()
	world.tap_action(Vector2i(1, 0))
	assert_true(_heard(Sounds.HAND_PLACE), "a tap that places should be heard")


func test_a_tap_at_nothing_is_refused_not_placed() -> void:
	# Off the sheet entirely: an anchor is a base identity, and void has none.
	world.player.teleport(Vector2(-6.5 * CS, 12.5 * CS), false)
	_listen()
	world.tap_action(Vector2i(1, 0))
	assert_eq(world.anchor_cells(), [], "nothing was pinned")
	assert_true(_heard(Sounds.DENY), "a refused tap should say so")
	assert_false(_heard(Sounds.HAND_PLACE), "...and must not sound like a placement")


func test_a_tap_with_no_hands_left_is_refused() -> void:
	world.hands[0] = null
	world.hands[1] = null
	_listen()
	world.tap_action(Vector2i(1, 0))
	assert_true(_heard(Sounds.DENY), "no hand to place is a refusal")
	assert_false(_heard(Sounds.HAND_PLACE))


## The fuse is the only warning the player gets that a fold is coming, so
## completing a pair has to be audible in its own right — not just as a second
## copy of the placement sound.
func test_completing_a_pair_lights_an_audible_fuse() -> void:
	world.tap_action(Vector2i(1, 0))
	assert_false(world.fuse_running(), "one hand is not a pair")

	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	_listen()
	world.tap_action(Vector2i(1, 0))
	assert_true(world.fuse_running(), "the pair armed")
	assert_true(_heard(Sounds.PAIR_ARMED), "arming should be heard")
	assert_true(_heard(Sounds.HAND_PLACE), "...over the hand that armed it")


func test_the_first_hand_of_a_pair_does_not_light_a_fuse() -> void:
	_listen()
	world.tap_action(Vector2i(1, 0))
	assert_false(_heard(Sounds.PAIR_ARMED), "one hand down is not a fuse")


# ---------------------------------------------------------------------------
# Folding
# ---------------------------------------------------------------------------

func test_a_committed_fold_is_heard() -> void:
	_listen()
	assert_true(world.do_fold(Vector2i(20, 12), Vector2i(28, 12)), "the fold goes")
	assert_true(_heard(Sounds.FOLD), "a fold that commits should be heard")
	assert_false(_heard(Sounds.FOLD_REFUSED), "...and must not sound refused")


## Being swallowed is not the same event as riding a flap, and it does not
## sound like one: the world closed over you rather than under you.
func test_a_pinch_sounds_different_from_a_ride() -> void:
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	_listen()
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	assert_eq(world.mode, world.Mode.SUBSPACE, "the player was pinched in")
	assert_true(_heard(Sounds.PINCH), "a pinch should be heard as a pinch")
	assert_false(_heard(Sounds.FOLD), "...not as an ordinary fold")


## A fuse that fires and produces no fold: the refusal is heard once, and both
## hands are heard hitting the ground. The two together are the whole message —
## the fold did not happen, and here is where your hands are now.
func test_a_fold_that_will_not_go_is_heard_to_fail_and_scatter() -> void:
	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))            # the same cell: no crease direction
	_listen()
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)

	assert_eq(world.folds.size(), 0, "nothing folded")
	assert_eq(_count(Sounds.FOLD_REFUSED), 1, "refused exactly once, not once per check")
	assert_eq(_count(Sounds.HAND_DROP), 2, "both hands are heard to land")
	assert_false(_heard(Sounds.FOLD), "a refusal must never sound like a fold")


func test_a_hand_caught_by_a_burst_is_silent_but_a_dropped_one_is_not() -> void:
	# One anchor in reach, one far away: the burst catches the near hand and
	# drops the far one. Only the drop should be heard.
	world.tap_action(Vector2i(1, 0))                            # (5,12)
	world.player.teleport(Vector2(20.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))                            # (21,12)
	world.player.teleport(Vector2(5.5 * CS, 12.5 * CS), false)
	_listen()
	world.hold_action()

	assert_eq(world.hands_held(), 1, "the reachable hand came back")
	assert_eq(_count(Sounds.HAND_DROP), 1,
		"only the hand that reached the ground is heard")


# ---------------------------------------------------------------------------
# Unfolding, bursting, surfacing
# ---------------------------------------------------------------------------

func test_unfolding_is_heard() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	_listen()
	world.unfold_level_fold(world.folds[0])
	assert_eq(world.folds.size(), 0, "it came out")
	assert_true(_heard(Sounds.UNFOLD))


func test_a_blocked_unfold_is_refused_not_unfolded() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(24, 12))
	world.do_fold(Vector2i(30, 8), Vector2i(30, 11))   # crosses the first's seam
	_listen()
	world.unfold_level_fold(world.folds[0])

	assert_eq(world.folds.size(), 2, "blocked: nothing moved")
	assert_true(_heard(Sounds.DENY), "a blocked unfold should be refused audibly")
	assert_false(_heard(Sounds.UNFOLD), "...and must not sound like it worked")


func test_a_burst_that_releases_something_is_heard() -> void:
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	world.player.teleport(Vector2(23.5 * CS, 12.5 * CS), false)
	_listen()
	world.hold_action()

	assert_eq(world.folds.size(), 0, "the seam opened")
	assert_true(_heard(Sounds.BURST), "the gesture is heard")
	assert_true(_heard(Sounds.UNFOLD), "...and so is what it released")
	assert_false(_heard(Sounds.DENY), "something happened; nothing was refused")


## The burst is fired blind by design, so firing it into empty air is an
## ordinary thing to do — and it must sound like nothing happening, not like
## the gesture succeeding.
func test_a_burst_into_empty_air_is_refused_not_burst() -> void:
	world.player.teleport(Vector2(4.5 * CS, 12.5 * CS), false)
	_listen()
	world.hold_action()
	assert_true(_heard(Sounds.DENY))
	assert_false(_heard(Sounds.BURST))


func test_surfacing_from_a_fold_is_heard() -> void:
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	assert_eq(world.mode, world.Mode.SUBSPACE, "inside")
	world.player.teleport(Vector2(15.5 * CS, 12.5 * CS), false)
	_listen()
	world.try_exit()

	assert_eq(world.mode, world.Mode.WORLD, "out again")
	assert_true(_heard(Sounds.SURFACE), "coming out is heard")
	assert_false(_heard(Sounds.PINCH), "...and is not going in")


# ---------------------------------------------------------------------------
# Hands, and the rest of the world
# ---------------------------------------------------------------------------

func test_picking_a_hand_up_is_heard() -> void:
	# Drop one at the player's feet, then walk onto it. Standing ON the floor is the
	# point of the teleport: a dropped hand FALLS now, so dropping one from the spawn
	# point (which hangs a cell and a half up) leaves it on the ground below and out of
	# reach — and this test is about the pickup, not about the fall.
	world.player.teleport(Vector2(4.5 * CS, 14.0 * CS - PlayerBody.RADIUS), false)
	world.hands[0] = null
	world._drop_hand(HandTypes.PLAIN, world.player.global_position)
	_listen()
	world._check_pickups()
	assert_true(_heard(Sounds.HAND_PICKUP), "taking a hand should be heard")


func test_dropping_a_hand_into_the_world_is_heard() -> void:
	_listen()
	world._drop_hand(HandTypes.PLAIN, world.player.global_position)
	assert_true(_heard(Sounds.HAND_DROP))


func test_reset_is_heard() -> void:
	_listen()
	world._reset()
	assert_true(_heard(Sounds.RESET))


# ---------------------------------------------------------------------------
# Music follows where you are
# ---------------------------------------------------------------------------

func test_the_overworld_bed_starts_with_the_world() -> void:
	assert_eq(AudioManager.current_music_track, Sounds.MUSIC_OVERWORLD,
		"the world should come up with its bed playing")


## A subspace is meant to read as a PLACE. Its own bed is the cheapest
## thing that says so, and crossing the boundary should swap it both ways.
func test_the_bed_changes_inside_a_fold_and_back() -> void:
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	assert_eq(world.mode, world.Mode.SUBSPACE)
	assert_eq(AudioManager.current_music_track, Sounds.MUSIC_SUBSPACE,
		"inside a fold has its own bed")

	world.player.teleport(Vector2(15.5 * CS, 12.5 * CS), false)
	world.try_exit()
	assert_eq(world.mode, world.Mode.WORLD)
	assert_eq(AudioManager.current_music_track, Sounds.MUSIC_OVERWORLD,
		"surfacing brings the overworld bed back")


# ---------------------------------------------------------------------------
# The vocabulary is whole
# ---------------------------------------------------------------------------

## Nothing the world asks for may be missing. `AudioManager` warns once per
## unknown name, so an empty warning set after exercising the verb is proof
## that every name the world reached for exists — which is the failure a typo
## in a sound id would otherwise produce silently, months later.
func test_the_world_never_asks_for_a_sound_that_is_not_there() -> void:
	AudioManager._warned.clear()

	world.tap_action(Vector2i(1, 0))
	world.player.teleport(Vector2(8.5 * CS, 12.5 * CS), false)
	world.tap_action(Vector2i(1, 0))
	world._tick_fuse(HandTypes.BASE_FUSE + 0.01)
	world.hold_action()
	world.do_fold(Vector2i(20, 12), Vector2i(28, 12))
	world.unfold_level_fold(world.folds[0])
	world.player.teleport(Vector2(13.5 * CS, 12.5 * CS), false)
	world.do_fold(Vector2i(10, 12), Vector2i(18, 12))
	world.try_exit()
	world._check_pickups()
	world._check_goal()
	world._reset()

	assert_eq(AudioManager._warned, {},
		"the world asked for a sound that does not exist: %s"
			% str(AudioManager._warned.keys()))
