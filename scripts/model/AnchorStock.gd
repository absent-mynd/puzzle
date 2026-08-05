class_name AnchorStock extends RefCounted

## AnchorStock
##
## Pure accounting for the anchors the player carries.
##
## An anchor is an OBJECT, not an ability. You carry a finite number of them, and a
## fold that is standing in the world is holding two of yours — the seam diamond is
## where they went. So the budget is not "how many folds may you ever make" but
## **how many folds may stand at once**: you cannot take your bridge with you.
##
## The quantity is CONSERVED. Anchors are never destroyed, only committed:
##
##     free = capacity - held-by-live-folds - pinned-but-uncommitted
##
## Nothing here is stored. `held` is summed from the live fold lists and `pending`
## from the two anchor slots, so the ledger is derived from `(base, folds)` +
## the pending pair exactly like every other piece of state in this project.
## Unfolding refunds automatically, because the fold leaves the list.
##
## CAPACITY is the only part that accumulates: a world's authored starting capacity
## plus the grant of every anchor cache collected so far. Since anchors are never
## spent-to-nothing, "granting anchors" and "raising capacity" are the same act — a
## cache is permanently one more fold you may leave standing.
##
## Kernel: no world/view references. `held_in` takes plain arrays of Folds.

## Anchors a committed fold holds. Two, because a fold is two pinned points; a fold
## is never partially paid for.
const COST_PER_FOLD := 2


## Anchors held by one fold list.
static func held_by(folds: Array) -> int:
	var total := 0
	for f in folds:
		total += f.held_anchors
	return total


## Anchors held across several fold lists (regions, and each fold's interiors).
static func held_in(fold_lists: Array) -> int:
	var total := 0
	for list in fold_lists:
		total += held_by(list)
	return total


## Anchors in hand. Clamped at zero: a fold list may be seeded with more held
## anchors than the capacity accounts for (authored state, tests driving `do_fold`
## directly), and a negative count in hand is not a thing the player can have.
## (Named `available` rather than `free` — `free` is `Object.free()`.)
static func available(capacity: int, held: int, pending: int) -> int:
	return maxi(capacity - held - pending, 0)


## Can one more anchor be pinned?
static func can_pin(capacity: int, held: int, pending: int) -> bool:
	return available(capacity, held, pending) >= 1


## Starting capacity plus every collected cache's grant.
static func capacity_with(base_capacity: int, grants: Array) -> int:
	var total := base_capacity
	for g in grants:
		total += int(g)
	return maxi(total, 0)
