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


## The authored cell, for one the world places. Runtime anchors bind directly from
## the piece under the cursor and never look at this.
var cell: Vector2i = Vector2i.ZERO

## The authoring name of this anchor and of the one it is declared with. Resolved to
## `partner` (an id) once both are in a field, exactly as a door pairs by id.
var key := ""
var pair_key := ""


static func make(base_id_: int, bp_: Vector2, region_: String, hand_: int) -> Anchor:
	var a := Anchor.new()
	a.base_id = base_id_
	a.bp = bp_
	a.region = region_
	a.hand = hand_
	return a


## Attach an authored anchor to its base tile, at that tile's centre. False if the
## cell lies outside the grid, in which case it stays unbound and is skipped.
func bind(base: BaseGrid) -> bool:
	if base == null:
		return false
	var tile := base.tile_at(cell)
	if tile == null:
		base_id = -1
		return false
	base_id = tile.base_id
	bp = (Vector2(cell) + Vector2(0.5, 0.5)) * base.cell_size
	return true


func is_bound() -> bool:
	return base_id >= 0


# ---------------------------------------------------------------------------
# Serialization (the authored form; `base_id`/`bp` are bound at load, not stored)
# ---------------------------------------------------------------------------
#
# An authored anchor is always BOLTED, and that is not stored either. A world that
# could author a LOOSE one would be handing out free hands the moment the player
# walked past with a burst charged, which is the payout this design says no to.

static func from_dict(d: Dictionary) -> Anchor:
	var a := Anchor.new()
	var c: Dictionary = d.get("cell", {})
	a.cell = Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))
	a.hand = HandTypes.from_name(String(d.get("kind", "plain")))
	a.arms = String(d.get("arms", PROXIMITY))
	a.key = String(d.get("id", ""))
	a.pair_key = String(d.get("pair", ""))
	a.bond = BOLTED
	return a


func to_dict() -> Dictionary:
	var out := {"cell": {"x": cell.x, "y": cell.y}, "kind": HandTypes.type_name(hand)}
	if arms != PROXIMITY:
		out["arms"] = arms
	if key != "":
		out["id"] = key
	if pair_key != "":
		out["pair"] = pair_key
	return out


## A fresh unbound copy — same reasoning as `LightSource.duplicate_light`: binding
## writes into an anchor, and a reset must re-bind from the authored world rather
## than from whatever the last session did to it.
func duplicate_anchor() -> Anchor:
	var copy := Anchor.from_dict(to_dict())
	copy.region = region
	return copy


## Resolve `pair_key` names into `partner` ids, over a list of anchors that have
## already been given ids. An anchor naming a partner that is not there keeps its
## declaration and simply never pairs — which is what a half-authored fold IS.
static func link_pairs(anchors: Array) -> void:
	var by_key: Dictionary = {}
	for a in anchors:
		if a.key != "":
			by_key[a.key] = a
	for a in anchors:
		if a.pair_key != "" and by_key.has(a.pair_key):
			a.partner = (by_key[a.pair_key] as Anchor).id


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
