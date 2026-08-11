extends GutTest

## HandStock tests — the slot ledger behind the hands you carry.
##
## A hand is only ever in one of three places: your slots, pinned but uncommitted, or
## held by a standing fold. The property that matters is CONSERVATION — placing,
## committing and unfolding move a hand between those places and never create or
## destroy one. Only picking a hand up may raise the total.
##
## Nothing here stores a balance; every number is summed from where the hands actually
## are, which is what lets unfolding give them back by simply removing the fold.

const PLAIN := HandTypes.PLAIN
const SWIFT := HandTypes.SWIFT


func _fold(held: Array) -> Fold:
	var f := Fold.create(0, Vector2i(0, 0), Vector2i(4, 0), 64.0)
	var typed: Array[int] = []
	for h in held:
		typed.append(int(h))
	f.held_hands = typed
	return f


func test_you_can_hold_exactly_one_fold_s_worth() -> void:
	assert_eq(HandStock.SLOTS, HandStock.HANDS_PER_FOLD,
		"Slots and the cost of a fold are the same number, so a full pair is always " \
		+ "exactly one fold and a spare can never be banked")


func test_empty_slots_start_empty() -> void:
	var slots := HandStock.empty_slots()
	assert_eq(slots.size(), HandStock.SLOTS, "One entry per slot")
	assert_eq(HandStock.held_count(slots), 0, "Nothing in them")
	assert_eq(HandStock.free_slots(slots), HandStock.SLOTS, "All of them free")
	assert_false(HandStock.has_hand(slots), "Nothing to place")


func test_counting_what_is_in_your_slots() -> void:
	assert_eq(HandStock.held_count([PLAIN, SWIFT]), 2, "Both slots full")
	assert_eq(HandStock.held_count([null, SWIFT]), 1, "One down, one held")
	assert_eq(HandStock.free_slots([null, SWIFT]), 1, "...so one slot is free")
	assert_true(HandStock.has_hand([null, SWIFT]), "One hand is enough to place with")


func test_first_empty_and_first_held_pick_the_obvious_slot() -> void:
	assert_eq(HandStock.first_empty([PLAIN, null]), 1, "The empty one takes an arrival")
	assert_eq(HandStock.first_empty([PLAIN, SWIFT]), -1, "No room reports -1, not slot 0")
	assert_eq(HandStock.first_held([null, SWIFT]), 1, "The full one is what you place")
	assert_eq(HandStock.first_held([null, null]), -1, "Nothing to place reports -1")


func test_can_receive_gates_hands_coming_home() -> void:
	# A fold gives back everything it holds AT ONCE, so the question is never
	# "is there a slot" but "is there room for all of them".
	assert_true(HandStock.can_receive([null, null], 2), "Empty hands can take a whole fold back")
	assert_false(HandStock.can_receive([null, SWIFT], 2),
		"Carrying a spare leaves nowhere for the second hand to go")
	assert_true(HandStock.can_receive([null, SWIFT], 1), "...but one would fit")
	assert_false(HandStock.can_receive([PLAIN, SWIFT], 1), "Full hands can take nothing")


func test_a_fresh_fold_holds_nothing() -> void:
	assert_eq(Fold.create(0, Vector2i(0, 0), Vector2i(4, 0), 64.0).held_hands, [] as Array[int],
		"Folds hold no hands unless someone says so — world folds are free")


func test_held_by_counts_hands_in_one_list() -> void:
	assert_eq(HandStock.held_by([]), 0, "No folds hold nothing")
	assert_eq(HandStock.held_by([_fold([PLAIN, SWIFT])]), 2, "A standing fold holds two")
	assert_eq(HandStock.held_by([_fold([PLAIN, PLAIN]), _fold([])]), 2,
		"A world-made fold in the list contributes nothing")


func test_held_in_counts_across_lists() -> void:
	# Regions and each fold's interiors are separate lists; all of them count.
	assert_eq(HandStock.held_in([[_fold([PLAIN, PLAIN])], [_fold([SWIFT, SWIFT])], []]), 4,
		"Hands are counted wherever the fold lives")
	assert_eq(HandStock.held_in([]), 0, "No lists, nothing held")


func test_a_fold_remembers_which_hands_not_just_how_many() -> void:
	# The whole reason kinds are stored: unfolding must return the same two hands
	# that went in, so a mixed pair comes back mixed.
	var f := _fold([SWIFT, HandTypes.PATIENT])
	assert_eq(f.held_hands, [SWIFT, HandTypes.PATIENT] as Array[int],
		"A mixed pair keeps both kinds, in order")


func test_the_three_places_always_sum_to_the_same_total() -> void:
	# The invariant the design rests on, walked through one fold's life:
	# slots -> pinned -> fold -> slots.
	var slots: Array = [PLAIN, SWIFT]
	var lists: Array = [[]]

	assert_eq(HandStock.total(slots, 0, lists), 2, "Two hands exist, both in your slots")

	slots = [null, SWIFT]                                   # placed one
	assert_eq(HandStock.total(slots, 1, lists), 2, "Placing moved one, it did not spend it")

	slots = [null, null]                                    # placed the other
	assert_eq(HandStock.total(slots, 2, lists), 2, "Both down, both still yours")

	lists[0].append(_fold([PLAIN, SWIFT]))                  # the pair committed
	assert_eq(HandStock.total(slots, 0, lists), 2,
		"Committing handed the same two to the fold")

	(lists[0] as Array).clear()                             # unfolded it
	slots = [PLAIN, SWIFT]
	assert_eq(HandStock.total(slots, 0, lists), 2,
		"Unfolding gave them back by removing the fold, with no bookkeeping of its own")


func test_picking_one_up_is_the_only_thing_that_raises_the_total() -> void:
	var lists: Array = [[_fold([PLAIN, PLAIN])]]
	assert_eq(HandStock.total([null, null], 0, lists), 2, "Two hands, both committed")
	assert_eq(HandStock.total([SWIFT, null], 0, lists), 3,
		"A cache put a third hand in the world — the only way the count goes up")
