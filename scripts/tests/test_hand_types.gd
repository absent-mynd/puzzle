extends GutTest

## HandTypes tests — the registry of kinds of hand.
##
## The contract is small on purpose: a kind has a colour you can tell it by and a fuse
## it gives the fold it makes, and NOTHING else about a fold depends on which hands
## made it. These tests pin that smallness as much as they pin the values, so the day
## a kind grows a second behaviour it is a deliberate change and not a drift.

const PLAIN := HandTypes.PLAIN
const SWIFT := HandTypes.SWIFT
const PATIENT := HandTypes.PATIENT


func test_every_kind_is_registered():
	for t in [PLAIN, SWIFT, PATIENT]:
		assert_true(HandTypes.is_registered(t), "kind %d should be registered" % t)
	assert_eq(HandTypes.all_types().size(), 3, "three kinds ship")


func test_kinds_are_told_apart_by_colour():
	# The colour IS the identity — it is what the player reads on the hand, on the
	# pending ring and on a hand lying in the world — so two kinds sharing one would be a bug
	# you could only find by playing.
	var seen: Array = []
	for t in HandTypes.all_types():
		var c: Color = HandTypes.color(t)
		for other in seen:
			assert_gt(Vector3(c.r, c.g, c.b).distance_to(other), 0.2,
				"kind %d's colour is distinguishable from every other" % t)
		seen.append(Vector3(c.r, c.g, c.b))


func test_the_fuse_is_what_a_kind_changes():
	assert_almost_eq(HandTypes.fuse(PLAIN), HandTypes.BASE_FUSE, 0.001, "plain is the baseline")
	assert_lt(HandTypes.fuse(SWIFT), HandTypes.fuse(PLAIN), "swift goes off sooner")
	assert_gt(HandTypes.fuse(PATIENT), HandTypes.fuse(PLAIN), "patient gives you longer")


func test_every_fuse_is_a_usable_length():
	for t in HandTypes.all_types():
		assert_gt(HandTypes.fuse(t), 0.0, "kind %d has a fuse you can react to" % t)
		assert_lt(HandTypes.fuse(t), 10.0, "kind %d does not stall the game" % t)


func test_a_mixed_pair_lands_between_its_parents():
	# The whole reason a fold may take two different kinds. Taking the max would make
	# a swift hand worthless when paired; taking the min would erase the patient one.
	var swift_pair := HandTypes.fuse_for(SWIFT, SWIFT)
	var patient_pair := HandTypes.fuse_for(PATIENT, PATIENT)
	var mixed := HandTypes.fuse_for(SWIFT, PATIENT)
	assert_gt(mixed, swift_pair, "a patient hand slows a swift one down")
	assert_lt(mixed, patient_pair, "a swift hand hurries a patient one along")


func test_a_pair_of_one_kind_is_just_that_kind_s_fuse():
	for t in HandTypes.all_types():
		assert_almost_eq(HandTypes.fuse_for(t, t), HandTypes.fuse(t), 0.001,
			"an unmixed pair of kind %d fuses at its own rate" % t)


func test_fuse_for_does_not_care_which_hand_went_down_first():
	assert_almost_eq(HandTypes.fuse_for(SWIFT, PATIENT), HandTypes.fuse_for(PATIENT, SWIFT),
		0.001, "the pair is a pair — placement order is not a hidden input")


func test_authoring_keys_round_trip():
	for t in HandTypes.all_types():
		assert_eq(HandTypes.from_name(HandTypes.type_name(t)), t,
			"kind %d survives a trip through its authoring key" % t)


func test_key_lookup_is_forgiving_of_case_and_space():
	assert_eq(HandTypes.from_name("  SWIFT "), SWIFT, "keys are trimmed and case-folded")


func test_an_unknown_key_or_id_behaves_as_plain():
	# A typo in a world file should yield an ordinary hand, not a broken one.
	assert_eq(HandTypes.from_name("nonsense"), PLAIN, "unknown key falls back to plain")
	assert_almost_eq(HandTypes.fuse(999), HandTypes.BASE_FUSE, 0.001,
		"an unregistered id still fuses like a plain hand")
	assert_false(HandTypes.is_registered(999), "...while still reporting itself unknown")
