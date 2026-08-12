class_name Anchor extends RefCounted

## Anchor
##
## A hand pinned to the sheet — the ROLE a hand takes while it is down, and now a
## first-class object rather than a dictionary in one of two lists.
##
## An anchor is an OCCUPANT (ARCHITECTURE Decision 10): it stores a base identity plus
## a point inside that tile, never a world position, so where it is is a question asked
## of the current piece list through `BaseFrame`. That is what carries it through folds,
## into subspaces and back out, with no arithmetic of its own.
##
## What is new here is that the world may pin one too. Before this, "anchor" meant
## three unrelated things — a runtime dict with one of your hands in it, two numbers in
## a trigger tile that existed only for the length of a cascade, and a JSON literal
## consumed at boot — and only the first could be seen, moved or reasoned about. Now
## there is one kind of anchor and three ways one gets placed, and the differences that
## remain are stated in two fields:
##
##   `arms` — what has to be true before this anchor will pair with another.
##   `bond` — whether a burst may take it back.
##
## Everything else about an anchor is the same whoever put it there, which is the whole
## point of the object.

# --- Arming conditions (`arms`) ---

## Pairs with any other proximity anchor whose span reaches it. What a hand you place
## does, and the reason placing hands far apart is now a thing you can do.
const PROXIMITY := "proximity"
## Pairs with nothing, ever. Scenery, or an anchor waiting for a channel it will never
## be given — kept because "inert" must be sayable.
const NEVER := "never"
## Any other value is a CHANNEL NAME: this anchor arms once something makes that
## channel live (a plate, a lever), and not before.

# --- Bonds (`bond`) ---

## Yours. A burst in reach pops it and you get the hand back. Counted by the ledger.
const LOOSE := 0
## Driven in by the world. A burst does nothing to it, and it is not a hand — it does
## not come back, it is not counted, and unfolding a fold it made pays nothing out.
##
## The resistance is not flavour. A bolted anchor is authored world state, and there is
## no way to put one back: letting a burst pop one would let the player quietly delete
## a puzzle for the rest of the session, in exchange for nothing.
const BOLTED := 1

## Assigned by `AnchorField.add`. The fuse of a pair is keyed by the two ids, so an
## anchor's identity has to outlive any particular frame's geometry.
var id := -1

## Where it is pinned, in the BASE frame: a tile and a point inside it.
var base_id := -1
var bp := Vector2.ZERO

## Which region's sheet that base id belongs to. Base ids are per-region and DO
## overlap, so without this a west anchor resolves onto whatever east tile shares
## its number.
var region := ""

## The kind of hand pinned here (`HandTypes`). Decides this anchor's span and its
## half of a pair's fuse — for a bolted anchor too, which has a kind without being
## a hand: the world can drive in something patient and long-reaching.
var hand := HandTypes.PLAIN

var arms: String = PROXIMITY
var bond := LOOSE

## The id of the one anchor this may pair with, or -1 for "whatever is in range".
## Authored pairs and a plate's two cells declare each other; hands you place do not.
var partner := -1


static func make(base_id_: int, bp_: Vector2, region_: String, hand_: int) -> Anchor:
	var a := Anchor.new()
	a.base_id = base_id_
	a.bp = bp_
	a.region = region_
	a.hand = hand_
	return a


## Where this anchor lies in `pieces`, or null if it is not there — wrong region, or
## its base tile is folded away in this configuration.
func point_in(pieces: Array, region_now: String):
	if region != region_now:
		return null
	return BaseFrame.world_point_from_base(pieces, base_id, bp)


## How far this anchor reaches for a partner, in world units. A pair folds when the
## gap between them is within the two spans added together — see `HandTypes.span`.
func span(cell_size: float) -> float:
	return HandTypes.span(hand) * cell_size


## Is this one of your hands? Only these are counted by the ledger, popped by a burst,
## or handed back when the fold they made comes apart.
func is_hand() -> bool:
	return bond == LOOSE


## Is this anchor's arming condition met? `live` is the set of channels something has
## switched on. A proximity anchor is always ready; `NEVER` never is.
func armable(live: Dictionary) -> bool:
	if arms == PROXIMITY:
		return true
	if arms == NEVER:
		return false
	return live.has(arms)
