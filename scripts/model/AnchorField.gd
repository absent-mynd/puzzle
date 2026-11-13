class_name AnchorField extends RefCounted

## AnchorField
##
## Every anchor standing in the world, and the one question worth asking about them:
## **which two are about to fold together?**
##
## ## Pairing is DERIVED
##
## There used to be two lists — `unpaired` and `armed` — with traffic running both
## ways, and pairing was an EVENT: the hand you put down married the last unpaired
## anchor you could see, at any distance, and the marriage was then stored. Two lists
## that have to agree is the shape ARCHITECTURE Decision 1 exists to refuse, and every
## rule about keeping them in step (what a burst does to half a pair, which survivor
## your next tap finds) was a rule about the bookkeeping rather than about the game.
##
## So there is one list, and a pair is a PREDICATE over it — recomputed from where the
## anchors actually are, every frame. A pair comes apart because the anchors moved
## apart, not because something remembered to unmarry them.
##
## Two anchors pair when both are resolvable in this frame, both are armable, and
## either
##
##   - they DECLARE each other (an authored pair, a plate's two cells), or
##   - both take proximity partners and `gap <= span(a) + span(b)`.
##
## The gap is measured through the lattice (`FoldLattice.shortest_delta`), because
## inside a fold the space is identified across its glue lines and the way you would
## walk it is the only distance that means anything.
##
## ## The fuse is the only thing stored, and it is keyed by the pair
##
## Time cannot be derived. So a countdown per edge, keyed by the two anchor ids, and
## three states rather than two:
##
##   - **live** — both ends resolvable, still in range: tick it down.
##   - **broken** — both ends resolvable, out of range: drop it. A pair that came apart
##     and came back together is a NEW pair and starts again.
##   - **suspended** — an end is not resolvable here at all (another region, folded
##     away): keep it, do not tick. This is what makes "leave a pair armed, walk
##     through a door, come back and find it still counting" true, and the naive
##     derivation loses it — no edge, no fuse.
##
## Every pair that exists arms. Where three anchors are all in range of each other,
## all three edges light and the first fuse to run out takes its two anchors with it,
## which deletes the others. **The matching is emergent and first-past-the-post**, so
## nothing here has to choose a matching, and what the player sees — several pairs
## beating at their own rates — is the whole of the rule.
##
## ## Why the cascade cannot run away
##
## Firing consumes two anchors and nothing in here creates one. So the anchor count is
## non-increasing while the player does nothing, at most `floor(N/2)` folds can follow
## from N anchors, and a fixpoint cap has nothing to guard against.
##
## That holds only while taking a fold apart never hands back a pair that is still
## armable. A fold does give back the world's own anchors (`restore`), so the condition
## is kept case by case rather than by returning nothing — the cases are written where
## the decision is made, in `FoldWorld._give_back_to_world`.
##
## ## Channels
##
## An anchor may wait on a named channel instead of on proximity (`Anchor.arms`). A
## channel is LIVE when it is **latched** — a trip plate was stepped on; stored, because
## history cannot be derived — or **weighted** — a weight plate is down right now;
## handed in every frame by the world, which derives it (`Weights`). Two sets rather than
## one so that lifting a weight cannot drop a latch of the same name.
##
## Pure kernel: anchors, a `Space` to resolve them in, and time in. No view types.

## Slack on the span test, in world units. The shipped beats sit exactly on the limit
## of two plain hands by design — a fold you can only just make is the clearest way to
## teach what a span is — and a limit that fails on a float's last bit is not a limit,
## it is a coin toss. Same discipline as `GeometryCore.EPSILON`, at the scale this
## comparison happens on.
const SPAN_EPSILON := 0.01

## Anchors standing in the world, in the order they were placed.
var anchors: Array = []

## Channels that are LATCHED. A trip plate latches one, and it stays live until the
## fold it made is taken apart again (`unlatch_channel`). Stored, because "was this plate ever
## stepped on" is history and history cannot be derived.
var latched_channels: Dictionary = {}

## Channels being WEIGHTED live right now, by something resting on a plate (`Weights`). Not history
## at all: the world overwrites these every frame from where the body and the hands
## are, so this is a cache of a derivation and never the authority on it.
##
## Kept apart from `latched_channels` so that letting go of a plate cannot un-latch a
## channel a trip plate latched under the same name, and vice versa.
var weighted_channels: Dictionary = {}

## pair key (Vector2i of the two ids, lower first) -> {"left": float, "total": float}.
var _fuses: Dictionary = {}

var _next_id := 0


func size() -> int:
	return anchors.size()


func is_empty() -> bool:
	return anchors.is_empty()


func clear() -> void:
	anchors.clear()
	_fuses.clear()
	latched_channels.clear()
	weighted_channels.clear()
	_next_id = 0


## Put an anchor down and give it its identity. Returns the same object.
func add(anchor: Anchor) -> Anchor:
	anchor.id = _next_id
	_next_id += 1
	anchors.append(anchor)
	return anchor


## Put back an anchor that was taken out, as itself: same object, SAME id.
##
## What a world-made fold does with its bolts when it comes apart. The id is kept
## because a declared pair names its partner by id, and two bolts that came back as
## strangers would never fold again. Ids are handed out once and never reused, so the
## one coming back cannot collide with anything placed since.
func restore(anchor: Anchor) -> Anchor:
	if anchor.id < 0:
		return add(anchor)
	if not anchors.has(anchor):
		anchors.append(anchor)
	return anchor


## Take an anchor out — popped by a burst, or spent on a fold. Every fuse it was part
## of goes with it, which is how reaching one half of an armed pair disarms the pair
## while leaving the other half pinned exactly where it was.
func remove(anchor: Anchor) -> void:
	anchors.erase(anchor)
	for key in _fuses.keys():
		if key.x == anchor.id or key.y == anchor.id:
			_fuses.erase(key)


## The hands you have out — the anchors that are hands at all. Bolted ones are the
## world's and are not part of the ledger.
func hands_out() -> int:
	var n := 0
	for a in anchors:
		if a.is_hand():
			n += 1
	return n


## Latch a channel, so anchors waiting on it can pair. Idempotent.
func latch_channel(channel: String) -> void:
	if channel != "":
		latched_channels[channel] = true


## Drop a latch. What taking a trip plate's fold apart does: the plate is back to
## not-yet-stepped-on, and its anchors wait for it again.
func unlatch_channel(channel: String) -> void:
	latched_channels.erase(channel)


## Say whether a channel has a plate down, this frame. See `weighted_channels`.
func weigh_channel(channel: String, down: bool) -> void:
	if channel == "":
		return
	if down:
		weighted_channels[channel] = true
	else:
		weighted_channels.erase(channel)


## Is a channel live — latched, or weighted?
func is_live(channel: String) -> bool:
	return latched_channels.has(channel) or weighted_channels.has(channel)


## Every live channel, as the set `Anchor.armable` reads.
func live_set() -> Dictionary:
	if weighted_channels.is_empty():
		return latched_channels
	var out := latched_channels.duplicate()
	out.merge(weighted_channels)
	return out


# ---------------------------------------------------------------------------
# Where they are, and which of them can fold together
# ---------------------------------------------------------------------------

## Every anchor that resolves in this space right now: id -> world point. An anchor
## missing from this is not "far away", it is NOT HERE — a different region, or a tile
## this configuration has folded out of sight.
func points_in(space: Space) -> Dictionary:
	var out: Dictionary = {}
	for a in anchors:
		var wp = a.point_in(space.pieces, space.region_id)
		if wp != null:
			out[a.id] = Vector2(wp)
	return out


## The anchor standing at a point in this frame, or null. What "there is already a
## hand there" is asked of: a site holds one anchor, whichever way it got there.
##
## Asked in the CURRENT frame rather than of base identities, because two different
## base tiles can be folded onto the same spot, and two anchors on one spot is a pair
## at zero gap — guaranteed to arm and guaranteed to be refused.
func at_point(space: Space, point: Vector2, within: float):
	var lat: FoldLattice = space.lattice
	for a in anchors:
		var wp = a.point_in(space.pieces, space.region_id)
		if wp != null and lat.distance(Vector2(wp), point) <= within:
			return a
	return null


## The pairs that could fold together in this frame, given already-resolved `points`.
## Each is `{"a": Anchor, "b": Anchor, "gap": float}`.
##
## Deterministic: anchors are walked in placement order, so the same field in the same
## configuration always yields the same list in the same order.
func pairs_from(space: Space, points: Dictionary) -> Array:
	var out: Array = []
	var cs: float = space.base.cell_size if space.base != null else WorldCore.CELL
	var lat: FoldLattice = space.lattice
	var live := live_set()
	for i in range(anchors.size()):
		var a: Anchor = anchors[i]
		if not points.has(a.id) or not a.armable(live):
			continue
		for j in range(i + 1, anchors.size()):
			var b: Anchor = anchors[j]
			if not points.has(b.id) or not b.armable(live):
				continue
			var gap: float = lat.distance(points[a.id], points[b.id])
			if not _may_pair(a, b, gap, cs):
				continue
			out.append({"a": a, "b": b, "gap": gap})
	return out


func pairs_in(space: Space) -> Array:
	return pairs_from(space, points_in(space))


## Declared pairs ignore distance; undeclared ones are exactly the span test. An
## anchor that names a partner pairs with that one and nothing else — otherwise a
## plate's two cells could be hijacked by a hand you happened to drop between them.
func _may_pair(a: Anchor, b: Anchor, gap: float, cell_size: float) -> bool:
	if a.partner >= 0 or b.partner >= 0:
		return a.partner == b.id and b.partner == a.id
	if a.arms != Anchor.PROXIMITY or b.arms != Anchor.PROXIMITY:
		return false
	return gap <= a.span(cell_size) + b.span(cell_size) + SPAN_EPSILON


# ---------------------------------------------------------------------------
# The fuses
# ---------------------------------------------------------------------------

static func _key(a: Anchor, b: Anchor) -> Vector2i:
	return Vector2i(mini(a.id, b.id), maxi(a.id, b.id))


## Run the world on by `delta`: recompute the pairs, bring the fuses into line with
## them, and count down.
##
## Returns `{"pairs": Array, "due": Array, "lit": int}` — every pair in this frame, the
## ones whose fuse has run out (soonest-armed first, and the caller fires ONE, because
## a fold owns the frame it starts in), and how many lit this frame, which is what a
## sound belongs on.
func step(space: Space, delta: float) -> Dictionary:
	var points := points_in(space)
	var pairs := pairs_from(space, points)
	var lit := 0

	var seen: Dictionary = {}
	for pair in pairs:
		var key := _key(pair["a"], pair["b"])
		seen[key] = true
		if not _fuses.has(key):
			var total: float = HandTypes.fuse_for(
				(pair["a"] as Anchor).hand, (pair["b"] as Anchor).hand)
			_fuses[key] = {"left": total, "total": total}
			lit += 1
	# A fuse with no pair is either broken or merely out of sight, and the difference
	# is whether both its ends are HERE. Broken loses its count; suspended keeps it.
	for key in _fuses.keys():
		if seen.has(key):
			continue
		if points.has(key.x) and points.has(key.y):
			_fuses.erase(key)

	var due: Array = []
	for pair in pairs:
		var fuse: Dictionary = _fuses[_key(pair["a"], pair["b"])]
		fuse["left"] = maxf(float(fuse["left"]) - delta, 0.0)
		if fuse["left"] <= 0.0:
			due.append(pair)
	# Two pairs coming due in one frame is a tie, and it has to break the same way
	# every run: the tighter fold first, then by the older anchor.
	due.sort_custom(func(x, y) -> bool:
		if not is_equal_approx(float(x["gap"]), float(y["gap"])):
			return float(x["gap"]) < float(y["gap"])
		return _key(x["a"], x["b"]) < _key(y["a"], y["b"]))
	return {"pairs": pairs, "due": due, "lit": lit}


## A pair that fired and was refused. Its fuse goes back to full rather than being
## dropped: the anchors have not moved, so the pair still exists, and a fuse sitting at
## zero would refuse again on every frame instead of every fuse.
func refuse(a: Anchor, b: Anchor) -> void:
	var key := _key(a, b)
	if _fuses.has(key):
		_fuses[key]["left"] = _fuses[key]["total"]


## How far through its fuse a pair is: 0 just lit, 1 folding now.
func progress(a: Anchor, b: Anchor) -> float:
	var fuse = _fuses.get(_key(a, b))
	if fuse == null or float(fuse["total"]) <= 0.0:
		return 0.0
	return clampf(1.0 - float(fuse["left"]) / float(fuse["total"]), 0.0, 1.0)


## The progress of the nearest-due pair this anchor is part of, or -1 when it is in
## none. What the overlay throbs it on — an anchor in two pairs beats on the one that
## is going to take it.
func progress_of(anchor: Anchor, pairs: Array) -> float:
	var best := -1.0
	for pair in pairs:
		if pair["a"] == anchor or pair["b"] == anchor:
			best = maxf(best, progress(pair["a"], pair["b"]))
	return best


## Is anything counting down at all?
func any_armed(pairs: Array) -> bool:
	return not pairs.is_empty()


## The progress of whichever pair is closest to firing.
func nearest_progress(pairs: Array) -> float:
	var best := 0.0
	for pair in pairs:
		best = maxf(best, progress(pair["a"], pair["b"]))
	return best
