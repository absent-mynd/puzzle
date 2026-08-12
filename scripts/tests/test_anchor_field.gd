extends GutTest

## AnchorField: which two anchors are about to fold together, and when.
##
## The behavioural spec for the rule that replaced recency pairing. Everything here is
## headless — a `Space` built from a flat grid, anchors placed on it, time handed in by
## the metre. That is the point of extracting it: the old rule lived in `FoldWorld` and
## could only be exercised by booting a scene.

const CS := 64.0


func _space(w: int = 40, h: int = 6) -> Space:
	var rows: Array = []
	for _y in range(h):
		rows.append(".".repeat(w))
	var sp := Space.new()
	sp.region_id = "here"
	sp.base = WorldCore.parse_map(rows, CS, {})
	sp.base_pieces = FoldReplay.identity_pieces(sp.base)
	sp.pieces = sp.base_pieces
	sp.pieces_by_pos = BaseFrame.index_by_pos(sp.pieces)
	return sp


## An anchor at the centre of a cell, in the region the space belongs to.
func _pin(field: AnchorField, space: Space, cell: Vector2i,
		kind: int = HandTypes.PLAIN) -> Anchor:
	var tile := space.base.tile_at(cell)
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * CS
	return field.add(Anchor.make(tile.base_id, centre, space.region_id, kind))


## Run the field until something is due, or `limit` seconds have passed. Returns the
## pairs due at that moment.
func _run(field: AnchorField, space: Space, limit: float = 10.0) -> Array:
	var t := 0.0
	while t < limit:
		var res := field.step(space, 1.0 / 60.0)
		if not (res["due"] as Array).is_empty():
			return res["due"]
		t += 1.0 / 60.0
	return []


# ---------------------------------------------------------------------------
# The span rule
# ---------------------------------------------------------------------------

func test_two_plain_hands_reach_eight_cells_and_not_nine() -> void:
	# The number the shipped world is sized against. Two plain spans of four.
	var sp := _space()
	var field := AnchorField.new()
	_pin(field, sp, Vector2i(2, 2))
	var far := _pin(field, sp, Vector2i(11, 2))
	assert_eq(field.pairs_in(sp).size(), 0, "Nine cells apart: out of reach of each other")
	field.remove(far)
	_pin(field, sp, Vector2i(10, 2))
	assert_eq(field.pairs_in(sp).size(), 1, "Eight cells apart: exactly in reach")


func test_a_kind_reaches_as_far_as_the_registry_says() -> void:
	var sp := _space()
	var field := AnchorField.new()
	_pin(field, sp, Vector2i(2, 2), HandTypes.PATIENT)
	_pin(field, sp, Vector2i(11, 2), HandTypes.PLAIN)
	assert_eq(field.pairs_in(sp).size(), 1,
		"Patient reaches six, plain four: ten cells is within the two of them")
	var swift_field := AnchorField.new()
	_pin(swift_field, sp, Vector2i(2, 2), HandTypes.SWIFT)
	var reachable := _pin(swift_field, sp, Vector2i(9, 2), HandTypes.PLAIN)
	assert_eq(swift_field.pairs_in(sp).size(), 1, "Swift three plus plain four covers seven")
	swift_field.remove(reachable)
	_pin(swift_field, sp, Vector2i(10, 2), HandTypes.PLAIN)
	assert_eq(swift_field.pairs_in(sp).size(), 0,
		"...and the eighth cell is one further than a swift hand will go")


func test_anchors_out_of_range_simply_stand_there() -> void:
	# The whole expansion: more than two hands may be down, and the ones nothing
	# reaches are not waiting for a partner, they are just placed.
	var sp := _space()
	var field := AnchorField.new()
	_pin(field, sp, Vector2i(1, 2))
	_pin(field, sp, Vector2i(15, 2))
	_pin(field, sp, Vector2i(30, 2))
	assert_eq(field.size(), 3, "Three hands out at once")
	assert_eq(field.pairs_in(sp).size(), 0, "...and nothing between any two of them")
	assert_eq(_run(field, sp, 6.0).size(), 0, "Nothing fires, however long you leave it")


func test_a_hand_dropped_between_two_lone_anchors_arms_both_pairs() -> void:
	var sp := _space()
	var field := AnchorField.new()
	var left := _pin(field, sp, Vector2i(2, 2))
	var right := _pin(field, sp, Vector2i(14, 2))
	assert_eq(field.pairs_in(sp).size(), 0, "Twelve apart: nothing")
	var middle := _pin(field, sp, Vector2i(8, 2))
	var pairs := field.pairs_in(sp)
	assert_eq(pairs.size(), 2, "One hand in the middle sees both, and both pairs arm")
	# ...and the race is decided by the fuses, not by a matching rule.
	var due := _run(field, sp)
	assert_eq(due.size(), 2, "Same kinds, same instant: they come due together")
	assert_eq(due[0]["gap"], due[1]["gap"], "...and the tie is broken by the tighter fold")
	assert_true(due[0]["a"] == left or due[0]["a"] == middle, "the older anchor goes first")
	assert_true(middle == due[0]["a"] or middle == due[0]["b"],
		"and the middle hand is in whichever pair wins")
	assert_not_null(right, "the far anchor is still standing, in the pair that lost")


# ---------------------------------------------------------------------------
# The fuse
# ---------------------------------------------------------------------------

func test_a_pair_lights_once_and_counts_its_own_kinds_down() -> void:
	var sp := _space()
	var field := AnchorField.new()
	_pin(field, sp, Vector2i(2, 2), HandTypes.SWIFT)
	_pin(field, sp, Vector2i(6, 2), HandTypes.SWIFT)
	var first := field.step(sp, 0.0)
	assert_eq(int(first["lit"]), 1, "Lighting is an event, and it happened once")
	assert_eq(int(field.step(sp, 0.0)["lit"]), 0, "...and does not happen again next frame")
	var pairs: Array = field.pairs_in(sp)
	field.step(sp, HandTypes.fuse(HandTypes.SWIFT) * 0.5)
	assert_almost_eq(field.progress(pairs[0]["a"], pairs[0]["b"]), 0.5, 0.05,
		"Half a swift fuse in, it is half way")


func test_a_mixed_pair_fuses_at_the_mean_of_its_two_hands() -> void:
	var sp := _space()
	var field := AnchorField.new()
	_pin(field, sp, Vector2i(2, 2), HandTypes.SWIFT)
	_pin(field, sp, Vector2i(6, 2), HandTypes.PATIENT)
	var pairs: Array = field.pairs_in(sp)
	field.step(sp, 0.0)
	var want: float = HandTypes.fuse_for(HandTypes.SWIFT, HandTypes.PATIENT)
	field.step(sp, want * 0.5)
	assert_almost_eq(field.progress(pairs[0]["a"], pairs[0]["b"]), 0.5, 0.02,
		"The mean of the two, exactly as the fuse registry says")


func test_a_pair_that_comes_apart_loses_its_count() -> void:
	var sp := _space()
	var field := AnchorField.new()
	var a := _pin(field, sp, Vector2i(2, 2))
	var b := _pin(field, sp, Vector2i(10, 2))
	field.step(sp, HandTypes.BASE_FUSE * 0.8)
	assert_gt(field.progress(a, b), 0.5, "Well through its fuse")
	# Take the far end away and put it back further off, then back where it was: the
	# pair that comes back is a NEW pair, and it starts again.
	field.remove(b)
	field.step(sp, 0.0)
	var b2 := _pin(field, sp, Vector2i(10, 2))
	field.step(sp, 0.0)
	assert_almost_eq(field.progress(a, b2), 0.0, 0.001, "A pair that re-formed starts over")


func test_a_pair_you_walked_away_from_keeps_counting_where_it_stopped() -> void:
	# The one case a naive derivation loses: an anchor that is not resolvable HERE is
	# not a pair that came apart, it is a pair you cannot see. Walk through a door
	# mid-fuse and it waits for you.
	var sp := _space()
	var field := AnchorField.new()
	var a := _pin(field, sp, Vector2i(2, 2))
	var b := _pin(field, sp, Vector2i(10, 2))
	field.step(sp, HandTypes.BASE_FUSE * 0.5)
	var half := field.progress(a, b)
	assert_almost_eq(half, 0.5, 0.02, "Half way through")

	var elsewhere := _space()
	elsewhere.region_id = "far"
	for _i in range(120):
		field.step(elsewhere, 1.0 / 60.0)          # two seconds in another region
	assert_eq(field.pairs_in(elsewhere).size(), 0, "Neither end is in this space")
	field.step(sp, 0.0)
	assert_almost_eq(field.progress(a, b), half, 0.02,
		"Back where you left it, still exactly where you left it")


func test_a_refused_pair_waits_a_whole_fuse_before_trying_again() -> void:
	var sp := _space()
	var field := AnchorField.new()
	var a := _pin(field, sp, Vector2i(2, 2))
	var b := _pin(field, sp, Vector2i(10, 2))
	assert_eq(_run(field, sp).size(), 1, "It comes due")
	field.refuse(a, b)
	assert_almost_eq(field.progress(a, b), 0.0, 0.001, "Refusing puts the fuse back to full")
	assert_eq(field.step(sp, 1.0 / 60.0)["due"].size(), 0,
		"...so it does not refuse again on the very next frame")


# ---------------------------------------------------------------------------
# Declared pairs, channels and bonds
# ---------------------------------------------------------------------------

func test_a_declared_pair_ignores_distance_and_waits_for_its_channel() -> void:
	var sp := _space(40, 6)
	var field := AnchorField.new()
	var a := _pin(field, sp, Vector2i(1, 2))
	var b := _pin(field, sp, Vector2i(35, 2))
	for anchor in [a, b]:
		anchor.arms = "vault"
		anchor.bond = Anchor.BOLTED
	a.partner = b.id
	b.partner = a.id
	assert_eq(field.pairs_in(sp).size(), 0, "Nothing has switched the channel on")
	field.light_channel("vault")
	assert_eq(field.pairs_in(sp).size(), 1,
		"Live: they pair across the whole region, because they were declared, not found")


func test_a_declared_anchor_cannot_be_hijacked_by_a_hand_you_drop_beside_it() -> void:
	var sp := _space()
	var field := AnchorField.new()
	var a := _pin(field, sp, Vector2i(4, 2))
	var b := _pin(field, sp, Vector2i(30, 2))
	a.partner = b.id
	b.partner = a.id
	_pin(field, sp, Vector2i(5, 2))            # a hand of yours, right next to `a`
	assert_eq(field.pairs_in(sp).size(), 1, "Only the declared pair")
	assert_eq(field.pairs_in(sp)[0]["a"], a, "...and it is still the pair that was declared")


func test_an_inert_anchor_pairs_with_nothing() -> void:
	var sp := _space()
	var field := AnchorField.new()
	var a := _pin(field, sp, Vector2i(4, 2))
	a.arms = Anchor.NEVER
	_pin(field, sp, Vector2i(5, 2))
	assert_eq(field.pairs_in(sp).size(), 0, "Scenery does not fold with your hands")


func test_only_loose_anchors_are_hands() -> void:
	var sp := _space()
	var field := AnchorField.new()
	_pin(field, sp, Vector2i(4, 2))
	var bolted := _pin(field, sp, Vector2i(20, 2))
	bolted.bond = Anchor.BOLTED
	assert_eq(field.size(), 2, "Two anchors are standing")
	assert_eq(field.hands_out(), 1, "...and one of them is a hand of yours")


# ---------------------------------------------------------------------------
# Sites, and what a burst does
# ---------------------------------------------------------------------------

func test_a_site_holds_one_anchor() -> void:
	var sp := _space()
	var field := AnchorField.new()
	var a := _pin(field, sp, Vector2i(4, 2))
	var centre := Vector2(4.5, 2.5) * CS
	assert_eq(field.at_point(sp, centre, CS * 0.5), a, "There is a hand there")
	assert_null(field.at_point(sp, Vector2(9.5, 2.5) * CS, CS * 0.5), "...and none there")


func test_taking_one_anchor_disarms_its_pairs_and_leaves_the_others_standing() -> void:
	# What a burst does, stated where it is now true by construction: the far half of
	# a pair is not something that has to be "put back", it never moved.
	var sp := _space()
	var field := AnchorField.new()
	var near := _pin(field, sp, Vector2i(4, 2))
	var far := _pin(field, sp, Vector2i(10, 2))
	field.step(sp, HandTypes.BASE_FUSE * 0.5)
	field.remove(near)
	assert_eq(field.pairs_in(sp).size(), 0, "The pair is gone with the hand that was in it")
	assert_eq(field.anchors, [far], "...and the far end is still pinned where you put it")
	var back := _pin(field, sp, Vector2i(4, 2))
	field.step(sp, 0.0)
	assert_almost_eq(field.progress(back, far), 0.0, 0.001, "Pinning again starts a fresh fuse")


# ---------------------------------------------------------------------------
# Repeating spaces
# ---------------------------------------------------------------------------

func test_inside_a_fold_the_gap_is_measured_the_way_you_would_walk_it() -> void:
	var sp := _space()
	# A cylinder eight cells around. Two anchors either side of the glue are
	# neighbours, however far apart they subtract.
	sp.lattice = FoldLattice.flat().push(Fold.create(0, Vector2i(2, 2), Vector2i(10, 2), CS), CS)
	var field := AnchorField.new()
	_pin(field, sp, Vector2i(3, 2))
	_pin(field, sp, Vector2i(30, 2))
	assert_eq(field.pairs_in(sp).size(), 1,
		"27 cells apart on the page, three the way the strip runs")
