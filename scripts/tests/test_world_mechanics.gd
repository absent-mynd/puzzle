extends GutTest

## The mechanics that make the hand economy reach past folding: weight plates and the
## channels they keep live, the world's bolts coming back when its folds come apart, water,
## sigils, and the room reset.
##
## Scene-driven like `test_fold_world.gd`, and pinned to a fixture of its own for the
## same reason that one is (see `worlds/fixtures/README.md`): these assert against a
## plate HERE and a wall THERE, and must not inherit whichever world is shipping.
##
##   lab   y=9 is the walk line.  G(2)  H(5)=gate  wall(12)  T(30)=latch  H(40)=far  G(42)
##         bolts: gate pair at 10 & 14 (swift), a patient socket at 24, latch pair at 33 & 36
##         a loose swift hand at 27, a door at 38
##   pool  y=11 is the walk line. water x 6..9, y 5..11.  far pair at 12 & 15.  G(17)

const SCENE := "res://scenes/world/World.tscn"
const FIXTURE := "res://worlds/fixtures/mechanics.json"
const CS := 64.0
const DT := 1.0 / 60.0

var world
var _start_total := 0


func before_each() -> void:
	world = load(SCENE).instantiate()
	world.world_override = FIXTURE
	add_child_autofree(world)
	world.anim_enabled = false
	_start_total = world.hands_total()


func _stand(cell: Vector2i) -> void:
	world.player.teleport((Vector2(cell) + Vector2(0.5, 0.5)) * CS + Vector2(0, 12), false)


## Where a BASE cell of the current region is right now. Folds slide the sheet — the
## plate you just stood on rode its flap along with you — so anything said about "the
## plate" after a fold has to be said about the tile, not about where it started.
func _now(base_cell: Vector2i) -> Vector2i:
	var tile = world.base.tile_at(base_cell)
	var wp = BaseFrame.world_point_from_base(world.current_pieces, tile.base_id,
		world.cell_center(base_cell))
	assert_not_null(wp, "base cell %s is in this space" % base_cell)
	return Vector2i((Vector2(wp) / CS).floor())


## One frame of the world's own logic, as `_physics_process` runs it.
func _frame(n := 1) -> void:
	for _i in range(n):
		world._physics_process(DT)


## Long enough for a plate that has come up to be believed. A plate forgives a hop
## (`FoldWorld.PLATE_GRACE`), so "I stepped off" is only true a moment after you did.
func _wait_out_the_grace() -> void:
	_frame(int(ceil(world.PLATE_GRACE / DT)) + 2)


func _bolts_here() -> int:
	var n := 0
	for anchor in world.field.anchors:
		if not anchor.is_hand() and world.anchor_here(anchor):
			n += 1
	return n


func _gate_fold():
	for fold in world.folds:
		if fold.channel == "gate":
			return fold
	return null


## Stand on the gate plate until its fold has gone off.
func _hold_gate_with_body() -> void:
	_stand(Vector2i(5, 9))
	_frame()
	world._tick_fuse(1.0)
	_frame()


# ---------------------------------------------------------------------------
# The registry
# ---------------------------------------------------------------------------

func test_a_weight_plate_is_a_registered_walkable_tile_with_a_channel() -> void:
	var t := TileTypes.TRIGGER_WEIGHT
	assert_true(TileTypes.is_registered(t), "the weight plate is in the registry")
	assert_true(TileTypes.is_walkable(t), "...you can stand in it")
	assert_true(TileTypes.is_weighable(t), "...and it is the one tile a weight does something to")
	assert_eq(TileTypes.on_enter_kind(t), "", "it is a state, not an event: nothing fires on entering")
	assert_eq(WorldCore.CHARS.get("H"), t, "authored as H")
	assert_false(TileParams.is_complete(t, {}), "a plate with no channel drives nothing, and says so")
	assert_true(TileParams.is_complete(t, {"channel": "gate"}), "...a channel is all it needs")


func test_water_is_the_mirror_of_air() -> void:
	assert_true(TileTypes.is_swim(TileTypes.WATER), "you swim in water")
	assert_true(TileTypes.blocks_anchor(TileTypes.WATER), "...and your hands slip in it")
	assert_false(TileTypes.is_swim(TileTypes.EMPTY), "you fall through air")
	assert_false(TileTypes.blocks_anchor(TileTypes.EMPTY), "...and your hands hold in it")


# ---------------------------------------------------------------------------
# Weights (pure)
# ---------------------------------------------------------------------------

func test_weights_reads_plates_and_what_is_on_them() -> void:
	var base := WorldCore.parse_map(["H.H", "###"], CS,
		{"0,0": {"channel": "a"}, "2,0": {"channel": "a"}})
	var plates := Weights.plates_by_channel(base)
	assert_eq(plates.keys(), ["a"], "two plates on one channel are one channel")
	assert_eq((plates["a"] as Array).size(), 2)
	var left: int = base.tile_at(Vector2i(0, 0)).base_id
	var mid: int = base.tile_at(Vector2i(1, 0)).base_id
	assert_false(Weights.channel_states(plates, {})["a"], "nothing on either: not down")
	assert_false(Weights.channel_states(plates, {mid: true})["a"], "standing BETWEEN them weighs nothing")
	assert_true(Weights.channel_states(plates, {left: true})["a"], "either plate keeps the channel live")
	assert_eq(Weights.plates_down(plates, {left: true}), [left], "...and only that one is down")


func test_a_plate_with_no_channel_drives_nothing() -> void:
	var base := WorldCore.parse_map(["H", "#"], CS, {})
	assert_true(Weights.plates_by_channel(base).is_empty())


# ---------------------------------------------------------------------------
# Weight plates in the world
# ---------------------------------------------------------------------------

func test_standing_on_a_plate_arms_the_worlds_pair_and_the_fuse_folds_it() -> void:
	assert_eq(world.armed_pairs().size(), 0, "nothing is armed before anything is weighed down")
	_stand(Vector2i(5, 9))
	_frame()
	assert_true(world.field.is_live("gate"), "your weight keeps the channel live")
	assert_eq(world.armed_pairs().size(), 1, "...and the world's pair arms on it")
	assert_eq(world.folds.size(), 0, "pressing a plate does not fold; it lights a fuse")

	world._tick_fuse(1.0)
	assert_eq(world.folds.size(), 1, "the ordinary fuse makes the fold")
	assert_eq(world.folds[0].channel, "gate", "...tagged with the channel keeping it")
	assert_eq(world.folds[0].held_hands.size(), 0, "the world paid for it, so it holds none of yours")
	assert_eq(world.hands_total(), _start_total, "conservation")


func test_stepping_off_lets_the_fold_go_and_the_bolts_come_back() -> void:
	_hold_gate_with_body()
	assert_not_null(_gate_fold(), "the gate is folded while you stand there")
	var bolts_while_folded := _bolts_here()

	_stand(_now(Vector2i(3, 9)))
	_wait_out_the_grace()
	assert_false(world.field.is_live("gate"), "no weight, no channel")
	assert_null(_gate_fold(), "...and the fold lets go by itself")
	assert_eq(_bolts_here(), bolts_while_folded + 2,
		"the two bolts that made it are standing in the sheet again")
	assert_eq(world.armed_pairs().size(), 0, "...and wait, unarmed, for the next weight")


func test_a_plates_fold_can_be_made_again_and_again() -> void:
	for _round in range(3):
		_hold_gate_with_body()
		assert_not_null(_gate_fold(), "down: folded")
		_stand(_now(Vector2i(3, 9)))
		_wait_out_the_grace()
		assert_null(_gate_fold(), "up: open")
	assert_eq(world.hands_total(), _start_total, "none of which cost or made a hand")


func test_a_hand_on_the_plate_weighs_it_and_reaches_for_nothing() -> void:
	_stand(Vector2i(4, 9))
	assert_true(world.place_hand(Vector2i(5, 9)), "a hand goes down on the plate")
	var weight: Anchor = world.field.anchors.back()
	assert_eq(weight.arms, Anchor.NEVER, "a hand on a plate is pressing, not gripping")

	# The second hand goes down well inside two spans of the first. Were the first an
	# ordinary anchor they would be a pair; a weight is not looking for one.
	_stand(Vector2i(7, 9))
	assert_true(world.place_hand(Vector2i(8, 9)))
	_frame()
	var pairs: Array = world.armed_pairs()
	assert_eq(pairs.size(), 1, "exactly one pair is armed")
	assert_false(pairs[0]["a"].is_hand() or pairs[0]["b"].is_hand(),
		"...and it is the world's — your two hands did not pair with each other")

	world._tick_fuse(1.0)
	_stand(Vector2i(20, 9))
	_frame()
	assert_not_null(_gate_fold(), "you walked away and the fold is still standing")
	assert_eq(world.hands_held(), 0, "which is what the hand on the plate is paying for")
	assert_eq(world.hands_total(), _start_total, "conservation")


func test_a_weight_has_no_span_ring_and_previews_no_partner() -> void:
	_stand(Vector2i(7, 9))
	world.place_hand(Vector2i(8, 9))
	assert_true(world.aim_partners(world.cell_center(Vector2i(6, 9)), HandTypes.PLAIN).size() > 0,
		"a hand beside the plate would reach the one already down")
	assert_eq(world.aim_partners(world.cell_center(Vector2i(5, 9)), HandTypes.PLAIN).size(), 0,
		"a hand ON the plate would reach nothing, and the preview says so")
	_stand(Vector2i(4, 9))
	world.place_hand(Vector2i(5, 9))
	var view = world._build_overlay_view()
	var spans: Array = []
	for entry in view.hands_down:
		if not entry["bolted"]:
			spans.append(float(entry["span"]))
	spans.sort()
	assert_eq(spans[0], 0.0, "the weight draws no reach")
	assert_gt(spans[1], 0.0, "...the anchor still draws its own")


func test_taking_the_hand_back_lets_the_fold_go() -> void:
	_stand(Vector2i(4, 9))
	world.place_hand(Vector2i(5, 9))
	_frame()
	world._tick_fuse(1.0)
	_frame()
	assert_not_null(_gate_fold())

	world.hold_action()             # a burst, standing next to the plate
	assert_eq(world.hands_held(), 2, "the hand comes home")
	_stand(Vector2i(3, 9))
	_wait_out_the_grace()
	assert_null(_gate_fold(), "...and with nothing on the plate the fold lets go")


func test_a_hop_on_the_plate_does_not_spring_the_fold() -> void:
	# You weigh a plate by being in its cell, and a hop leaves by the top of it. The
	# world's fold must not notice.
	_hold_gate_with_body()
	var plate: Vector2i = _now(Vector2i(5, 9))
	world.player.teleport((Vector2(plate) + Vector2(0.5, -0.6)) * CS, false)
	_frame(6)                       # a tenth of a second in the air above it
	assert_not_null(_gate_fold(), "a hop is not stepping off")
	_stand(plate)
	_frame(30)
	assert_not_null(_gate_fold(), "...and landing back on it starts nothing over")
	assert_eq(world.armed_pairs().size(), 0, "no fuse was lit by any of that")


func test_a_real_jump_off_the_plate_lets_it_go() -> void:
	_hold_gate_with_body()
	var plate: Vector2i = _now(Vector2i(5, 9))
	world.player.teleport((Vector2(plate) + Vector2(0.5, -1.5)) * CS, false)
	_wait_out_the_grace()
	assert_null(_gate_fold(), "longer than a hop, and the plate believes you have gone")


func test_leaving_the_room_settles_its_plates_on_what_is_really_there() -> void:
	# Stand on the far plate and walk straight through the door beside it. The grace
	# must not follow you out: nothing is on that plate, and a room away is exactly
	# where a stale "down" would never be corrected.
	_stand(Vector2i(40, 9))
	_frame()
	assert_true(world.field.is_live("far"), "your weight has it down")
	world._traverse("LAB_POOL")
	assert_false(world.field.is_live("far"), "you took your weight with you")
	_frame(30)
	assert_eq(world.armed_pairs().size(), 0, "...so nothing arms in the next room")


func test_a_hand_lying_loose_on_the_plate_weighs_it_too() -> void:
	# A hand is a weight whether it is pinned or merely lying there.
	var plate := (Vector2(5, 9) + Vector2(0.5, 0.5)) * CS
	world._land_ball({"kind": HandTypes.PLAIN, "pos": plate + Vector2(0, 20), "region": "lab"})
	_stand(Vector2i(20, 9))
	_frame()
	assert_true(world.field.is_live("gate"), "a loose hand on the plate keeps the channel live")
	assert_eq(world.plates_down_here().size(), 1, "...and the plate is drawn down")


func test_a_hand_in_flight_over_the_plate_does_not_press_it() -> void:
	var plate := (Vector2(5, 9) + Vector2(0.5, 0.5)) * CS
	world.hand_field.launch(HandTypes.PLAIN, plate - Vector2(0, 5 * CS), world.space,
		Vector2.ZERO, 0.0)
	_stand(Vector2i(20, 9))
	world._tick_plates(DT)
	assert_false(world.field.is_live("gate"), "falling past a plate is not resting on it")


func test_bursting_a_plates_fold_opens_it_only_for_a_fuse() -> void:
	# The weight is still on the plate, so the world still wants the fold: taking it
	# apart by hand buys you one fuse of open space, not a different room.
	_stand(Vector2i(4, 9))
	world.place_hand(Vector2i(5, 9))
	_frame()
	world._tick_fuse(1.0)
	assert_not_null(_gate_fold())

	assert_true(world.unfold_space_fold(_gate_fold()), "a plate's fold can be taken apart")
	assert_null(_gate_fold(), "...and is, for a moment")
	_frame()
	assert_eq(world.armed_pairs().size(), 1, "but its bolts are back and the plate is still down")
	world._tick_fuse(1.0)
	assert_not_null(_gate_fold(), "so it folds itself again")


func test_a_fold_of_your_own_made_after_it_wedges_a_plates_fold_open() -> void:
	_hold_gate_with_body()
	var gate = _gate_fold()
	assert_not_null(gate)
	# Any fold at all, so long as it is NEWER. This one is nowhere near the gate and
	# crosses nothing of it: the world lets go newest-first, and this is in the way.
	assert_true(world.do_fold(Vector2i(30, 2), Vector2i(34, 2)), "a fold of your own, afterwards")

	_stand(_now(Vector2i(3, 9)))
	_frame(30)
	assert_false(world.field.is_live("gate"), "nothing is on the plate")
	assert_not_null(_gate_fold(), "...and the fold stands anyway: yours is on top of it")
	assert_eq(world.hud.flash_text().find("Blocked"), -1,
		"a fold the WORLD cannot let go of is not a refusal anyone asked for")

	var mine: Fold = world.folds.back()
	assert_true(world.unfold_space_fold(mine))
	_frame(30)
	assert_null(_gate_fold(), "take the wedge out and the spring goes")


# ---------------------------------------------------------------------------
# What the world gets back
# ---------------------------------------------------------------------------

func test_a_socket_is_still_there_after_its_fold_comes_apart() -> void:
	# A proximity bolt is half a fold held out for you. It must survive being used.
	for _round in range(2):
		_stand(Vector2i(19, 9))
		assert_true(world.place_hand(Vector2i(20, 9)))
		_frame()
		assert_eq(world.armed_pairs().size(), 1, "one hand of yours and the patient socket")
		world._tick_fuse(5.0)
		assert_eq(world.folds.size(), 1)
		assert_eq(world.folds[0].held_hands.size(), 1, "the fold holds the ONE hand you spent")
		assert_eq(world.folds[0].bolts.size(), 1, "...and is looking after the world's")

		assert_true(world.unfold_space_fold(world.folds[0]))
		assert_eq(world.hands_held(), 2, "your hand comes back to you")
		var socket = world.field.at_point(world.space, world.cell_center(Vector2i(24, 9)), CS * 0.5)
		assert_not_null(socket, "the socket comes back to the world")
		assert_false(socket.is_hand())
		_frame()
		assert_eq(world.armed_pairs().size(), 0, "alone again, it folds with nothing")
	assert_eq(world.hands_total(), _start_total)


func test_a_trip_plate_with_only_a_channel_latches_the_worlds_pair() -> void:
	_stand(Vector2i(30, 9))
	_frame()
	assert_true(world.field.is_live("latch"), "stepping on it latches the channel")
	world._tick_fuse(5.0)
	assert_eq(world.folds.size(), 1)
	assert_eq(world.folds[0].channel, "latch")

	_stand(Vector2i(27, 9))
	_frame(30)
	assert_eq(world.folds.size(), 1, "a latch is not a hold: walking off changes nothing")

	# Taking the fold apart resets the plate, and its bolts wait for the next step.
	assert_true(world.unfold_space_fold(world.folds[0]))
	assert_false(world.field.is_live("latch"), "the latch drops with the fold")
	_frame(30)
	world._tick_fuse(5.0)
	assert_eq(world.folds.size(), 0, "...so it does not fold itself again")

	_stand(Vector2i(28, 9))
	_frame()
	_stand(Vector2i(30, 9))
	_frame()
	world._tick_fuse(5.0)
	assert_eq(world.folds.size(), 1, "step on it again and it does")


func test_a_plate_in_one_room_keeps_a_fold_in_another() -> void:
	_stand(Vector2i(39, 9))
	assert_true(world.place_hand(Vector2i(40, 9)), "a hand left on the far plate")
	_frame()
	assert_true(world.field.is_live("far"))

	world._traverse("LAB_POOL")
	assert_eq(world.region_id, "pool")
	_frame()
	assert_true(world.field.is_live("far"), "the hand is still on that plate, a room away")
	assert_eq(world.armed_pairs().size(), 1, "...and this room's pair arms on it")
	world._tick_fuse(1.0)
	assert_eq(world.folds.size(), 1, "the fold stands here, kept from there")
	assert_eq(world.hands_total(), _start_total)


# ---------------------------------------------------------------------------
# Water
# ---------------------------------------------------------------------------

func test_the_swim_settles_sinks_and_rises() -> void:
	var vy := 900.0                 # a dive
	for _i in range(60):
		vy = PlayerBody.swim_step(vy, false, DT)
	assert_almost_eq(vy, PlayerBody.SWIM_SINK, 0.01, "left alone you settle to a slow sink")
	for _i in range(60):
		vy = PlayerBody.swim_step(vy, true, DT)
	assert_almost_eq(vy, -PlayerBody.SWIM_RISE, 0.01, "holding the key carries you up")
	assert_lt(PlayerBody.SWIM_SINK, PlayerBody.MAX_FALL * 0.2, "sinking is far slower than falling")


func test_a_stroke_is_not_dragged_back_by_the_water() -> void:
	# A fresh press launches a jump; the water must not eat it in one frame, or you
	# could never push off the surface onto a ledge.
	var vy := PlayerBody.swim_step(PlayerBody.JUMP_VELOCITY, true, DT)
	assert_lt(vy, -PlayerBody.SWIM_RISE, "a stroke outruns the swim")
	assert_gt(vy, PlayerBody.JUMP_VELOCITY, "...and weight is what slows it")


func test_the_world_tells_the_body_when_it_is_in_water() -> void:
	world._traverse("LAB_POOL")
	_frame()
	assert_false(world.player.in_water, "on the bank")
	world.player.teleport((Vector2(7, 8) + Vector2(0.5, 0.5)) * CS, false)
	_frame()
	assert_true(world.player.in_water, "in the pool")
	world.player.teleport((Vector2(7, 3) + Vector2(0.5, 0.5)) * CS, false)
	_frame()
	assert_false(world.player.in_water, "above it")


func test_hands_slip_in_water() -> void:
	world._traverse("LAB_POOL")
	world.player.teleport((Vector2(5, 11) + Vector2(0.5, 0.5)) * CS, false)
	assert_true(world.place_hand(Vector2i(6, 11)), "placement asks only that there be sheet")
	world.player.teleport((Vector2(10, 11) + Vector2(0.5, 0.5)) * CS, false)
	assert_true(world.place_hand(Vector2i(9, 11)))
	world.player.teleport((Vector2(2, 11) + Vector2(0.5, 0.5)) * CS, false)
	world._tick_fuse(5.0)
	assert_eq(world.folds.size(), 0, "the fuse finds nothing to grip, and the fold does not go")
	assert_eq(world.hands_pending(), 0, "the hands came loose")
	assert_eq(world.hands_total(), _start_total, "...and are still hands")


# ---------------------------------------------------------------------------
# Sigils
# ---------------------------------------------------------------------------

func test_sigils_are_counted_and_collected_once() -> void:
	assert_eq(world.sigils_total, 3, "two in the lab, one by the pool")
	assert_eq(world.sigils_count(), 0)
	_stand(Vector2i(2, 9))
	_frame()
	assert_eq(world.sigils_count(), 1, "touching one collects it")
	assert_string_contains(world.hud.flash_text(), "1 of 3")
	_stand(Vector2i(6, 9))
	_frame()
	_stand(Vector2i(2, 9))
	_frame()
	assert_eq(world.sigils_count(), 1, "walking back onto it collects nothing more")
	assert_eq(world.found_sigil_polys().size(), 1, "the found one is dimmed where it stands")


# ---------------------------------------------------------------------------
# The room reset
# ---------------------------------------------------------------------------

func test_a_room_reset_hands_back_what_you_spent_in_the_room() -> void:
	# One hand in a fold with the socket, one on the gate plate: both slots empty.
	_stand(Vector2i(19, 9))
	world.place_hand(Vector2i(20, 9))
	_frame()
	world._tick_fuse(5.0)
	_stand(_now(Vector2i(4, 9)))
	world.place_hand(_now(Vector2i(5, 9)))
	_frame()
	world._tick_fuse(5.0)
	assert_eq(world.hands_held(), 0)
	assert_eq(world.folds.size(), 2)

	world._reset_region()
	assert_eq(world.folds.size(), 0, "the room is as it shipped")
	assert_eq(world.hands_held(), 2, "and both hands are back in your slots")
	assert_eq(world.hands_pending(), 0)
	assert_eq(world.hands_total(), _start_total, "nothing was made and nothing was lost")
	assert_false(world.field.is_live("gate"), "no plate is down")
	assert_eq(_bolts_here(), 5, "every bolt the room was authored with is standing")


func test_a_room_reset_keeps_what_you_know_and_what_you_carried_off() -> void:
	_stand(Vector2i(2, 9))
	_frame()
	assert_eq(world.sigils_count(), 1)
	# Spend a hand, then take the room's loose swift one into the slot it freed.
	_stand(Vector2i(19, 9))
	world.place_hand(Vector2i(20, 9))
	_stand(Vector2i(27, 9))
	_frame()
	assert_eq(world.loose_hands.size(), 0, "the swift hand is yours now")

	world._reset_region()
	assert_eq(world.sigils_count(), 1, "a reset undoes configuration, not having been somewhere")
	assert_eq(world.hands_total(), _start_total, "the swift hand was not minted a second time")
	assert_eq(world.hands_loose(), 1, "the hand that did not fit a slot is on the ground")
	assert_eq(world.hands_held(), 2)


func test_a_room_reset_leaves_other_rooms_alone() -> void:
	_stand(Vector2i(19, 9))
	world.place_hand(Vector2i(20, 9))
	_frame()
	world._tick_fuse(5.0)
	assert_eq(world.folds.size(), 1)
	world._traverse("LAB_POOL")
	world._reset_region()
	assert_eq(world.region_id, "pool")
	assert_eq(world.hands_held(), 1, "the hand in the lab's fold is still in the lab's fold")
	world._traverse("POOL_LAB")
	assert_eq(world.folds.size(), 1, "...which is still standing")
	assert_eq(world.hands_total(), _start_total)


func test_you_wake_at_the_door_you_came_in_by() -> void:
	world._traverse("LAB_POOL")
	var door := (Vector2(3, 11) + Vector2(0.5, 0.5)) * CS
	world.player.teleport((Vector2(15, 11) + Vector2(0.5, 0.5)) * CS, false)
	world._reset_region()
	assert_almost_eq(world.player.global_position.x, door.x, 1.0, "back at the way in")
	_frame()
	assert_eq(world.region_id, "pool", "...and arriving on a door is not walking into it")

	# A fall is the same question.
	world.player.teleport(Vector2(15.5 * CS, 40 * CS), false)
	_frame()
	assert_almost_eq(world.player.global_position.x, door.x, 1.0, "a fall puts you there too")


func test_the_world_reset_is_the_other_key() -> void:
	_stand(Vector2i(2, 9))
	_frame()
	world._reset()
	assert_eq(world.sigils_count(), 0, "the whole world, sigils and all")
	assert_eq(world.hands_total(), _start_total)


# ---------------------------------------------------------------------------
# The swim, for real
# ---------------------------------------------------------------------------
# Everything above asks the model. This runs the body: real physics frames, a real
# key held down, a real pool.

func _press(keycode: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func after_each() -> void:
	_press(KEY_SPACE, false)


func test_holding_the_jump_key_carries_the_body_up_through_water() -> void:
	world._traverse("LAB_POOL")
	var floor_y := (11.0 + 0.5) * CS
	world.player.teleport(Vector2(7.5 * CS, floor_y), false)
	_press(KEY_SPACE, true)
	for _i in range(240):
		await get_tree().physics_frame
		if world.player.global_position.y < 6.5 * CS:
			break
	assert_lt(world.player.global_position.y, 6.5 * CS,
		"five cells of water climbed without touching a floor")
	_press(KEY_SPACE, false)


func test_left_alone_in_water_the_body_sinks_slowly_and_stops_on_the_bottom() -> void:
	world._traverse("LAB_POOL")
	world.player.teleport(Vector2(7.5 * CS, 6.5 * CS), false)
	var fastest := 0.0
	for _i in range(60):
		await get_tree().physics_frame
		fastest = maxf(fastest, world.player.velocity.y)
	assert_true(world.player.in_water, "still in the pool a second later")
	assert_almost_eq(fastest, PlayerBody.SWIM_SINK, 5.0, "sinking at the swim's own pace")
	assert_gt(world.player.global_position.y, 6.5 * CS, "...and it is a sink, not a hover")


# ---------------------------------------------------------------------------
# Which hand
# ---------------------------------------------------------------------------

func test_swapping_changes_which_hand_goes_down_next() -> void:
	world.hands = [HandTypes.PLAIN, HandTypes.PATIENT]
	assert_eq(world.next_hand_type(), HandTypes.PLAIN)
	assert_true(world.swap_hands(), "two different hands trade places")
	assert_eq(world.next_hand_type(), HandTypes.PATIENT, "the other one is next")
	assert_eq(world.hands_held(), 2, "nothing moved in the ledger")


func test_swapping_two_alike_or_none_is_nothing() -> void:
	assert_false(world.swap_hands(), "two plain hands: nothing to choose between")
	world.hands = [null, null]
	assert_false(world.swap_hands(), "no hands: nothing to swap")


func test_swapping_with_one_hand_moves_it_to_the_front() -> void:
	world.hands = [null, HandTypes.SWIFT]
	assert_true(world.swap_hands())
	assert_eq(world.hands, [HandTypes.SWIFT, null])
	assert_eq(world.next_hand_type(), HandTypes.SWIFT, "it is still the hand you would place")


func test_a_raised_hand_can_be_swapped_for_the_other() -> void:
	world.hands = [HandTypes.PLAIN, HandTypes.PATIENT]
	assert_true(world.begin_aim(Vector2i(1, 0)))
	world.swap_hands()
	world.finish_aim()
	var down: Anchor = world.field.anchors.back()
	assert_eq(down.hand, HandTypes.PATIENT, "the hand that went down is the one you swapped to")
