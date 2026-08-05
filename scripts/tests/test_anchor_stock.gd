extends GutTest

## AnchorStock tests — the pure accounting behind the carried anchor resource.
##
## The property that matters is CONSERVATION: anchors move between three places
## (your pocket, the two pending slots, the folds standing in the world) and the
## three always sum to capacity. Nothing here stores a balance; `held` is summed
## from the fold lists, so unfolding refunds by simply removing the fold.


func _fold(held: int) -> Fold:
	var f := Fold.create(0, Vector2i(0, 0), Vector2i(4, 0), 64.0)
	f.held_anchors = held
	return f


func test_a_fresh_fold_holds_nothing() -> void:
	assert_eq(Fold.create(0, Vector2i(0, 0), Vector2i(4, 0), 64.0).held_anchors, 0,
		"Folds hold no player anchors unless someone says so — world folds are free")


func test_held_by_sums_one_list() -> void:
	assert_eq(AnchorStock.held_by([]), 0, "No folds hold nothing")
	assert_eq(AnchorStock.held_by([_fold(2), _fold(2)]), 4, "Two standing folds hold four")
	assert_eq(AnchorStock.held_by([_fold(2), _fold(0)]), 2,
		"A world-made fold in the list contributes nothing")


func test_held_in_sums_across_lists() -> void:
	# Regions and each fold's interiors are separate lists; all of them count.
	assert_eq(AnchorStock.held_in([[_fold(2)], [_fold(2), _fold(2)], []]), 6,
		"Anchors are counted wherever the fold lives")
	assert_eq(AnchorStock.held_in([]), 0, "No lists, nothing held")


func test_available_is_capacity_minus_what_is_out() -> void:
	assert_eq(AnchorStock.available(4, 0, 0), 4, "Nothing out: everything is in hand")
	assert_eq(AnchorStock.available(4, 2, 0), 2, "A standing fold is holding two")
	assert_eq(AnchorStock.available(4, 2, 1), 1, "A pinned-but-uncommitted anchor is out too")
	assert_eq(AnchorStock.available(4, 2, 2), 0, "All four accounted for")


func test_available_never_goes_negative() -> void:
	# A fold list can be seeded with more than the capacity accounts for (authored
	# state, or a test driving `do_fold` directly). "Minus one anchor" is not a
	# thing the player can carry.
	assert_eq(AnchorStock.available(4, 8, 0), 0, "Overdrawn reads as empty, not negative")


func test_can_pin_needs_one_in_hand() -> void:
	assert_true(AnchorStock.can_pin(4, 2, 1), "One left is enough to pin with")
	assert_false(AnchorStock.can_pin(4, 2, 2), "An empty pocket cannot pin")
	assert_false(AnchorStock.can_pin(0, 0, 0), "Nor can a capacity of nothing")


func test_capacity_accumulates_cache_grants() -> void:
	assert_eq(AnchorStock.capacity_with(4, []), 4, "No caches: the authored start stands")
	assert_eq(AnchorStock.capacity_with(4, [2, 2]), 8, "Each cache raises the ceiling")
	assert_eq(AnchorStock.capacity_with(0, [2]), 2, "A cache is worth its grant on its own")


func test_capacity_is_never_negative() -> void:
	assert_eq(AnchorStock.capacity_with(2, [-8]), 0, "A nonsense grant cannot go below empty")


func test_cost_is_two_because_a_fold_is_two_points() -> void:
	assert_eq(AnchorStock.COST_PER_FOLD, 2,
		"A fold is two pinned points; it is never partially paid for")


func test_the_three_places_always_sum_to_capacity() -> void:
	# The invariant the whole design rests on, walked through one fold's life:
	# pocket -> pending -> fold -> pocket.
	var capacity := 4
	var lists: Array = [[]]
	var pending := 0

	assert_eq(AnchorStock.available(capacity, AnchorStock.held_in(lists), pending), 4, "start")
	pending = 2                                             # pinned both anchors
	assert_eq(AnchorStock.available(capacity, AnchorStock.held_in(lists), pending), 2, "pinned")
	lists[0].append(_fold(2))                               # committed the pair
	pending = 0
	assert_eq(AnchorStock.available(capacity, AnchorStock.held_in(lists), pending), 2,
		"committing moves the same two anchors — the free count does not move")
	(lists[0] as Array).clear()                             # unfolded it
	assert_eq(AnchorStock.available(capacity, AnchorStock.held_in(lists), pending), 4,
		"unfolding refunds by removing the fold, with no bookkeeping of its own")
