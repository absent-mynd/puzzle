extends GutTest

## Every room of the shipped world, played.
##
## `test_shipped_worlds.gd` checks that a world is well-formed. This checks that it can
## be DONE — and, as importantly, that it cannot be done by walking. Each room is a
## claim: "this sigil needs that fold". A claim nobody runs is how the first world
## shipped a beat that two plain hands could not reach by three cells.
##
## Each solution is the real thing driven through the real scene: hands are pinned
## with `place_hand`, fuses are run with `_tick_fuse`, doors are walked into. Two rules
## keep it honest, because `place_hand` and `teleport` will happily do what a player
## cannot:
##
##   - **The body only goes where `WorldProbe` says it can walk** (`_walk`), in the
##     STRICT reading — the one that under-states the jump — so a path this file takes
##     is a path a player can take without a perfect input.
##   - **A hand only goes where an arm can put it** (`_pin`, `_pin_jumping`).
##
## And before each room's key move, the GENEROUS reading — the one that over-states
## the jump — is asked whether the sigil can be had without folding at all. It must
## say no. If a room is edited and either reading changes its mind, this is the file
## that says so.
##
## The rooms are solved in ONE test, door to door, because that is the claim — the
## world can be finished — and because a room's solution depends on what you carried
## into it. The tests after it are the wrong turns: each takes one room and shows that
## the obvious other thing to try does not work, which is what makes the room a puzzle
## rather than a corridor.
##
## What this does not prove: that there is no OTHER fold which also works. A cleverer
## solution than the intended one is a thing a player is allowed to find.

const SCENE := "res://scenes/world/World.tscn"
const Probe := preload("res://scripts/tests/support/world_probe.gd")
const CS := 64.0
const DT := 1.0 / 60.0

var world

## One probe per reading, re-sampled only when the geometry it describes has been
## rebuilt. `rebuild()` hands the space a fresh piece list, so the list's identity is
## the stamp.
var _probes: Dictionary = {}
var _probed_pieces = null


func _probe(strict: bool):
	if not is_same(_probed_pieces, world.current_pieces):
		_probes.clear()
		_probed_pieces = world.current_pieces
	if not _probes.has(strict):
		_probes[strict] = Probe.new(world, strict)
	return _probes[strict]


func before_each() -> void:
	_probes.clear()
	_probed_pieces = null


func _open(region := "") -> void:
	world = load(SCENE).instantiate()
	world.world_override = WorldData.SHIPPED_WORLD
	if region != "":
		world.spawn_override = {"region": region}
	add_child_autofree(world)
	world.anim_enabled = false


# ---------------------------------------------------------------------------
# Driving the body honestly
# ---------------------------------------------------------------------------

func _frames(n := 1) -> void:
	for _i in range(n):
		world._physics_process(DT)


func _put(cell: Vector2i) -> void:
	world.player.teleport((Vector2(cell) + Vector2(0.5, 0.5)) * CS + Vector2(0, 12), false)


## Where a BASE cell of this region is now, as a cell. Folds slide the sheet, so every
## place this file names after a fold is named by the tile, not by where it started.
func _now(base_cell: Vector2i) -> Vector2i:
	var tile = world.base.tile_at(base_cell)
	var wp = BaseFrame.world_point_from_base(world.current_pieces, tile.base_id,
		world.cell_center(base_cell))
	assert_not_null(wp, "base cell %s is in this space" % base_cell)
	if wp == null:
		return base_cell
	return Vector2i((Vector2(wp) / CS).floor())


## Walk, jump, drop or swim to `to` — if the strict model says the body can.
func _walk(to: Vector2i, what := "") -> void:
	var probe = _probe(true)
	var from: Vector2i = world.player_cell()
	var ok: bool = probe.can_reach(from, to)
	assert_true(ok, "%s: the body can get from %s to %s" % [what, from, to])
	if not ok:
		print(probe.dump({from: "@", to: "$"}))
	_put(to)


## Is `to` out of reach of the body, however well it is played?
func _unreachable(to: Vector2i, what := "") -> void:
	var probe = _probe(false)
	var from: Vector2i = world.player_cell()
	var got: bool = probe.can_reach(from, to)
	assert_false(got, "%s: %s cannot be reached from %s without folding" % [what, to, from])
	if got:
		print(probe.dump({from: "@", to: "$"}))


## Pin a hand in a cell within arm's reach of where the body stands.
func _pin(cell: Vector2i, what := "") -> void:
	assert_true(WorldCore.within_arm_reach(world.player_cell(), cell, world.ARM_REACH),
		"%s: %s is within arm's reach of %s" % [what, cell, world.player_cell()])
	assert_true(world.place_hand(cell), "%s: a hand goes down at %s" % [what, cell])


## Pin a hand in a cell that takes a jump straight up to reach.
func _pin_jumping(cell: Vector2i, what := "") -> void:
	var probe = _probe(true)
	assert_true(probe.can_pin_from(world.player_cell(), cell, world.ARM_REACH),
		"%s: %s can be pinned from a jump at %s" % [what, cell, world.player_cell()])
	assert_true(world.place_hand(cell), "%s: a hand goes down at %s" % [what, cell])


func _fuse() -> void:
	_frames()
	world._tick_fuse(10.0)


func _through(door: String) -> void:
	var at = world.door_point_here(door)
	assert_not_null(at, "door %s is in this space" % door)
	_walk(Vector2i((Vector2(at) / CS).floor()), "to door %s" % door)
	world._traverse(door)


func _sigil(base_cell: Vector2i, what: String) -> void:
	var before: int = world.sigils_count()
	_walk(_now(base_cell), what)
	_frames()
	assert_eq(world.sigils_count(), before + 1, "%s: the sigil is collected" % what)


## Let the real physics run until the body has landed in `row`, or time runs out. For
## the two places a solution depends on something only gravity can show: the body
## falls, and the world wraps it.
func _fall_to_row(row: int, seconds := 2.0) -> void:
	for _i in range(int(seconds * 60.0)):
		await get_tree().physics_frame
		if world.player.is_on_floor() and world.player_cell().y == row:
			return


# ---------------------------------------------------------------------------
# threshold — a fold is a lift
# ---------------------------------------------------------------------------

func _solve_threshold() -> void:
	_unreachable(Vector2i(18, 7), "threshold")
	_unreachable(Vector2i(26, 7), "threshold's door")

	# Both anchors from one spot: one beside you, one at the top of a jump.
	_walk(Vector2i(11, 11), "to the foot of the ledge")
	_pin(Vector2i(12, 11), "the low anchor")
	_pin_jumping(Vector2i(12, 8), "the high anchor, on the ledge's own end")
	_fuse()
	assert_eq(world.folds.size(), 1, "threshold: the fold goes off")
	assert_eq(world.mode, world.Mode.WORLD, "...and you ride it rather than being taken in")

	# The ledge has come down to a step, and the sigil with it.
	_sigil(Vector2i(18, 7), "threshold")

	# Stand on the ledge's end, on the seam, and let go: the unfold carries you up.
	_walk(_now(Vector2i(12, 7)), "back to the seam")
	world.hold_action()
	assert_eq(world.folds.size(), 0, "threshold: the fold comes apart")
	assert_eq(world.hands_held(), 2, "...both hands come home")
	assert_eq(world.player_cell(), Vector2i(12, 7), "...and you are standing four cells up")


# ---------------------------------------------------------------------------
# span — fold, cross, and take it apart behind you
# ---------------------------------------------------------------------------

func _solve_span() -> void:
	_unreachable(Vector2i(13, 7), "span")
	_unreachable(Vector2i(22, 11), "span's far rim")

	_walk(Vector2i(10, 11), "to the near rim")
	_pin(Vector2i(11, 11), "one hand, on the rim")
	_frames()
	assert_eq(world.armed_pairs().size(), 1, "span: your hand and the world's are a pair")
	_fuse()
	assert_eq(world.folds.size(), 1, "span: the pit closes")
	assert_eq(world.folds[0].held_hands.size(), 1, "...on ONE hand of yours")
	assert_eq(world.hands_held(), 1, "...so you still have the other")

	# The shelf was in the pit's columns: it went into the fold with the pit.
	var shelf = world.base.tile_at(Vector2i(13, 7))
	assert_null(BaseFrame.world_point_from_base(world.current_pieces, shelf.base_id,
		world.cell_center(Vector2i(13, 7))), "span: the sigil is folded away with the pit")

	# Across the seam, then burst from the far side of it.
	_walk(_now(Vector2i(21, 11)), "across the closed pit")
	world.hold_action()
	assert_eq(world.folds.size(), 0, "span: the fold comes apart behind you")
	assert_eq(world.hands_held(), 2)
	assert_eq(world.player_cell(), Vector2i(21, 11), "...and leaves you on the far rim")
	assert_not_null(world.field.at_point(world.space, world.cell_center(Vector2i(20, 11)),
		CS * 0.5), "...with the world's hand back where it was held out")

	_sigil(Vector2i(13, 7), "span")


func test_span_is_nailed_against_lifting_the_shelf() -> void:
	# The elevator from the room before would bring the shelf down to the near rim.
	# The pillar's nails are in exactly those rows, and say no.
	_open("span")
	var hands: int = world.hands_total()
	_walk(Vector2i(10, 11))
	_pin(Vector2i(10, 11))
	_pin_jumping(Vector2i(10, 8))
	_put(Vector2i(8, 11))
	_fuse()
	assert_eq(world.folds.size(), 0, "a fold through the nailed rows is refused")
	assert_eq(world.hands_held(), 0, "...the hands drop where they were pinned")
	assert_eq(world.hands_total(), hands, "...and are still hands")


# ---------------------------------------------------------------------------
# cistern — water climbs, air holds
# ---------------------------------------------------------------------------

func _solve_cistern() -> void:
	_unreachable(Vector2i(21, 5), "cistern")

	# Up the waterfall, and pin in the AIR beside it at the height of the cliff top.
	_walk(Vector2i(9, 5), "up the waterfall")
	_pin(Vector2i(10, 5), "a hand in the air beside the water")
	_frames()
	assert_eq(world.armed_pairs().size(), 1, "cistern: it reaches the world's hand at the lip")
	_fuse()
	assert_eq(world.folds.size(), 1, "cistern: the dry gap folds away")
	assert_true(world.player.in_water or TileTypes.is_swim(
		BaseFrame.piece_containing(world.pieces_by_pos, world.player.global_position, CS).type),
		"...and the water came with you")

	_walk(_now(Vector2i(18, 5)), "off the waterfall onto the cliff")
	world.hold_action()
	assert_eq(world.folds.size(), 0, "cistern: pinned at the top, it comes apart from the top")
	assert_eq(world.hands_held(), 2)
	assert_eq(world.player_cell(), Vector2i(18, 5), "...leaving you on the cliff")

	_sigil(Vector2i(21, 5), "cistern")


func test_cistern_water_will_not_take_the_hand() -> void:
	_open("cistern")
	var hands: int = world.hands_total()
	_walk(Vector2i(9, 5))
	_pin(Vector2i(9, 5), "a hand in the water itself")
	_fuse()
	assert_eq(world.folds.size(), 0, "the fuse finds nothing to grip")
	assert_eq(world.hands_held(), 1, "...and the hand slips out")
	assert_eq(world.hands_total(), hands)


# ---------------------------------------------------------------------------
# press — three things to hold and two hands
# ---------------------------------------------------------------------------

func _solve_press() -> void:
	_unreachable(Vector2i(40, 11), "press")
	_unreachable(Vector2i(17, 11), "the hand past the first gate")

	# A hand on the first plate: the gate folds away and stays away.
	_walk(Vector2i(4, 11), "to the first plate")
	_pin(Vector2i(5, 11), "a hand on the plate")
	_fuse()
	assert_eq(world.folds.size(), 1, "press: the first gate folds")

	# Past it lies the long hand, and the slot the plate emptied takes it.
	_walk(_now(Vector2i(17, 11)), "through the first gate")
	_frames()
	assert_eq(world.next_hand_type(), HandTypes.PATIENT, "press: the patient hand is picked up")

	# Which hand goes on the second plate is the whole room. Any hand is a weight; only
	# the long one reaches across the pit.
	assert_true(world.swap_hands(), "press: the hands can be swapped")
	assert_eq(world.next_hand_type(), HandTypes.PLAIN)
	_walk(_now(Vector2i(18, 11)), "to the second plate")
	_pin(_now(Vector2i(19, 11)), "the plain hand on the plate")
	_fuse()
	assert_eq(world.folds.size(), 2, "press: the second gate folds")

	_walk(_now(Vector2i(27, 11)), "through the second gate to the pit")
	_pin(_now(Vector2i(28, 11)), "the patient hand on the rim")
	_frames()
	assert_eq(world.armed_pairs().size(), 1, "press: patient and plain reach across")
	_fuse()
	assert_eq(world.folds.size(), 3, "press: the pit closes")
	assert_eq(world.hands_held(), 0, "...and every hand you have is holding something")

	_sigil(Vector2i(40, 11), "press")

	# The plate past the sigil lets everything go at once: three hands for two slots.
	var before: int = world.hands_total()
	_walk(_now(Vector2i(42, 11)), "onto the burst plate")
	_frames(90)
	assert_eq(world.folds.size(), 0, "press: every fold has come apart")
	assert_eq(world.hands_held(), 2, "...two hands are back in your slots")
	assert_eq(world.hands_total(), before, "...and the third is on the ground, not gone")
	assert_eq(world.hands_loose(), 1)


func test_press_wants_the_long_hand_at_the_pit() -> void:
	# The naive order — the hand you just picked up goes down next — leaves the plain
	# one for the pit, and plain plus plain does not reach.
	_open("press")
	_walk(Vector2i(4, 11))
	_pin(Vector2i(5, 11))
	_fuse()
	_walk(_now(Vector2i(17, 11)))
	_frames()
	_walk(_now(Vector2i(18, 11)))
	_pin(_now(Vector2i(19, 11)), "the patient hand, on the plate")
	_fuse()
	_walk(_now(Vector2i(27, 11)))
	_pin(_now(Vector2i(28, 11)), "the plain hand, on the rim")
	_frames()
	assert_eq(world.armed_pairs().size(), 0, "plain and plain fall a cell short of the pit")


# ---------------------------------------------------------------------------
# annex — the far end is behind you
# ---------------------------------------------------------------------------

func _solve_annex() -> void:
	_unreachable(Vector2i(19, 11), "annex")

	_walk(Vector2i(12, 11), "to the chamber wall")
	_pin(Vector2i(11, 11), "a hand BEHIND you")
	_frames()
	assert_eq(world.armed_pairs().size(), 1, "annex: it reaches the hand sealed in the chamber")
	_walk(Vector2i(13, 11), "into the strip, against the wall")
	_fuse()
	assert_eq(world.mode, world.Mode.SUBSPACE, "annex: standing in the strip, you are folded in")
	assert_eq(world.lattice.depth(), 1, "...into a cylinder")

	# Inside, the wall is still a wall — but the strip's two ends are one line, and the
	# end behind you is the inside of the chamber. Step back through the glue.
	var behind: Vector2 = world.player.global_position + Vector2(-2.5 * CS, 0)
	var delta: Vector2 = world.lattice.wrap_delta(behind)
	assert_ne(delta, Vector2.ZERO, "annex: a few steps back is through the glue")
	var landed: Vector2 = behind + delta
	assert_false(WorldCore.circle_overlaps_solids(landed, PlayerBody.RADIUS, world.wall_polys),
		"...and there is room to stand on the other side of it")
	world.player.teleport(landed, false)
	assert_eq(world.player_cell(), Vector2i(21, 11), "annex: which is the chamber's east end")

	var before: int = world.sigils_count()
	_put(Vector2i(19, 11))
	_frames()
	assert_eq(world.sigils_count(), before + 1, "annex: the sigil is collected inside the fold")

	# Surface where you walked to: inside the sealed chamber, in flat space.
	_put(Vector2i(20, 11))
	world.hold_action()
	assert_eq(world.mode, world.Mode.WORLD, "annex: the fold opens")
	assert_eq(world.hands_held(), 2, "...your hand comes back")
	assert_eq(world.player_cell(), Vector2i(20, 11), "...and you are inside the chamber")
	_unreachable(Vector2i(12, 11), "the way back out of the chamber")


func test_annex_riding_the_fold_gets_you_nothing() -> void:
	# The same two anchors with you standing clear: the chamber is folded away, sigil
	# and all, and what is left is a wall.
	_open("annex")
	_walk(Vector2i(12, 11))
	_pin(Vector2i(11, 11))
	_walk(Vector2i(9, 11), "clear of the strip")
	_fuse()
	assert_eq(world.mode, world.Mode.WORLD, "you rode it")
	var sigil = world.base.tile_at(Vector2i(19, 11))
	assert_null(BaseFrame.world_point_from_base(world.current_pieces, sigil.base_id,
		world.cell_center(Vector2i(19, 11))), "...and the sigil went into the fold without you")


# ---------------------------------------------------------------------------
# vault — the hole in the floor is the skylight
# ---------------------------------------------------------------------------

## From inside the annex's chamber, with both hands: leave one on the keystone and go
## through.
func _annex_to_vault() -> void:
	_walk(Vector2i(18, 11), "to the keystone")
	_pin(Vector2i(17, 11), "a hand on the keystone")
	_frames()
	assert_true(world.field.is_live("keystone"), "the keystone is held")
	_through("AN_OUT")
	assert_eq(world.region_id, "vault")
	assert_eq(world.hands_held(), 1, "you arrive with one hand")


func _solve_vault() -> void:
	# The gate is held open from the room before: the pair arms as you arrive.
	_frames()
	assert_eq(world.armed_pairs().size(), 1, "vault: the keystone's pair arms a room away")
	_fuse()
	assert_eq(world.folds.size(), 1, "vault: the gate folds")
	_unreachable(_now(Vector2i(19, 5)), "vault")

	# One hand, on the floor under your feet, below the world's hand in the attic.
	_walk(_now(Vector2i(20, 11)), "into the hall, under the attic")
	_pin(_now(Vector2i(20, 12)), "the floor under your feet")
	var hall: Vector2i = world.player_cell()
	_frames()
	assert_eq(world.armed_pairs().size(), 1, "vault: floor and attic are a pair")
	_fuse()
	assert_eq(world.mode, world.Mode.SUBSPACE, "vault: standing between them, you are folded in")
	assert_eq(world.hands_held(), 0)

	# The hole in the floor. In flat space it is a fall out of the world; in here the
	# bottom of the strip is its top, and the top is the attic.
	var hole: Vector2i = hall + Vector2i(2, 0)
	world.player.teleport(world.cell_center(hole) + Vector2(CS * 0.5, 0), false)
	await _fall_to_row(hall.y - 6)
	assert_eq(world.mode, world.Mode.SUBSPACE, "vault: still inside the fold")
	assert_eq(world.player_cell().y, hall.y - 6,
		"vault: you fell through the floor and landed in the attic")

	var before: int = world.sigils_count()
	_put(Vector2i(hall.x - 1, hall.y - 6))
	_frames()
	assert_eq(world.sigils_count(), before + 1, "vault: the last sigil")

	# Out through the hatch, down to the hall, and surface where your hand is.
	world.player.teleport(world.cell_center(Vector2i(hall.x - 4, hall.y - 6))
		+ Vector2(CS * 0.5, 0), false)
	await _fall_to_row(hall.y)
	assert_eq(world.player_cell().y, hall.y, "vault: the hatch drops you back into the hall")
	_put(hall)
	world.hold_action()
	assert_eq(world.mode, world.Mode.WORLD, "vault: the fold opens")
	assert_eq(world.hands_held(), 1, "...and gives back the hand it held")


func test_the_vault_gate_is_shut_without_the_keystone() -> void:
	_open("vault")
	_frames(30)
	assert_eq(world.armed_pairs().size(), 0, "nothing holds the keystone, so nothing arms")
	_unreachable(Vector2i(12, 11), "the hall")


# ---------------------------------------------------------------------------
# The whole world, door to door
# ---------------------------------------------------------------------------

func test_the_whole_world_can_be_finished() -> void:
	_open()
	assert_eq(world.region_id, "threshold")
	assert_eq(world.sigils_total, 6, "six rooms, six sigils")
	var hands: int = world.hands_total()

	_solve_threshold()
	_through("TH_OUT")
	_solve_span()
	_through("SP_OUT")
	_solve_cistern()
	_through("CI_OUT")
	_solve_press()
	_through("PR_OUT")
	_solve_annex()
	_annex_to_vault()
	await _solve_vault()

	assert_eq(world.sigils_count(), 6, "every sigil found")
	assert_eq(world.hands_total(), hands, "and not one hand made or lost on the way")
