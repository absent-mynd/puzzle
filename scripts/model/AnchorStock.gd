class_name AnchorStock extends RefCounted

## AnchorStock
##
## The ledger of HANDS — where each one is, and whether there is room for another.
##
## A hand is an object you carry (see `HandTypes`). You have exactly `SLOTS` of them,
## and a hand is only ever in one of three places:
##
##     your slots  ←→  pinned but uncommitted  ←→  held by a standing fold
##
## Nothing here is stored as a balance. Slot contents live on the world as an array,
## committed hands are read off `Fold.held_hands`, and the pending pair is read off the
## two anchor slots — so unfolding gives hands back by simply removing the fold, with
## no bookkeeping of its own. A separate "hands spent" counter would be a second source
## of truth that could drift from the fold list.
##
## The number you can hold never grows. This is not a capacity you upgrade: pickups in
## the world hand you *another hand* for a slot you have emptied, and what a pickup
## changes is which KINDS you are carrying, not how many. That is why unfolding can be
## refused — two hands are coming back and there may not be room for them.
##
## Kernel: no world/view references. A "hands" array is plain data — one entry per
## slot, either a `HandTypes` id or `null` for empty.

## How many hands you can hold at once. Two, because a fold is two pinned points: you
## can always assemble exactly one fold from a full pair, and never bank a spare one.
const SLOTS := 2

## Hands a fold takes. A fold is two pinned points and is never partially paid for.
const HANDS_PER_FOLD := 2


## An empty pair of slots, for starting a world.
static func empty_slots() -> Array:
	var out: Array = []
	for _i in range(SLOTS):
		out.append(null)
	return out


## How many slots have a hand in them.
static func held_count(hands: Array) -> int:
	var n := 0
	for h in hands:
		if h != null:
			n += 1
	return n


## How many slots are empty — how many hands you could still be given.
static func free_slots(hands: Array) -> int:
	return maxi(hands.size() - held_count(hands), 0)


## Are you carrying anything to pin with?
static func has_hand(hands: Array) -> bool:
	return held_count(hands) > 0


## Index of the first empty slot, or -1. Where an incoming hand goes.
static func first_empty(hands: Array) -> int:
	for i in range(hands.size()):
		if hands[i] == null:
			return i
	return -1


## Index of the first slot holding a hand, or -1. Which hand you pin with next.
static func first_held(hands: Array) -> int:
	for i in range(hands.size()):
		if hands[i] != null:
			return i
	return -1


## Is there room for `n` hands coming back at once? Gates unfolding: a fold returns
## `HANDS_PER_FOLD` hands, and hands that will not fit have nowhere to go.
static func can_receive(hands: Array, n: int) -> bool:
	return free_slots(hands) >= n


## Hands held by one fold list.
static func held_by(folds: Array) -> int:
	var total := 0
	for f in folds:
		total += f.held_hands.size()
	return total


## Hands held across several fold lists (regions, and each fold's interiors).
static func held_in(fold_lists: Array) -> int:
	var total := 0
	for list in fold_lists:
		total += held_by(list)
	return total


## Every hand that exists, wherever it is. Conservation is stated here rather than
## enforced: placing, committing and unfolding must all leave this unchanged, and only
## picking one up may raise it.
static func total(hands: Array, pending: int, fold_lists: Array) -> int:
	return held_count(hands) + pending + held_in(fold_lists)
