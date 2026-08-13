class_name HandTypes extends RefCounted

## HandTypes
##
## The registry of HANDS — the things you pin space with.
##
## A hand is an object, not an ability. You can hold two at a time; a fold that is
## standing in the world is holding the two specific hands you pinned it with, and
## unfolding gives those same two back. What makes a hand more than a token is its
## VARIANT: hands come in kinds, a kind is read off its colour, and the kind changes
## how the fold it makes behaves.
##
## A kind changes two things, and they are the two halves of what a fold is: how long
## it waits (`fuse`) and how far it reaches (`span`).
##
## Per-type definition fields:
##   name  : the authoring key, as it appears in a world file's tile data
##   color : the hand's identity, not its styling — you tell kinds apart by colour,
##           so it belongs with the kind rather than in a palette elsewhere. This is
##           the one place a `Color` appears in the kernel, and the reason is that
##           adding a variant must mean editing ONE file (see AGENTS.md decision 2).
##   fuse  : seconds a pair of THIS kind waits before committing.
##   span  : how far, in CELLS, an anchor of this kind reaches for a partner.
##
## A fold may be pinned with two DIFFERENT kinds, so both are functions of the pair —
## see `fuse_for`, and the note on `span`.

## Canonical ids.
const PLAIN := 0
## Quick to go off, and short in the arm: a swift pair folds before you have finished
## thinking about it, and it will not reach far to do it.
const SWIFT := 1
## Slow to go off, and long in the arm: a patient pair gives you time to get somewhere
## before it fires, and it can gather ground a plain pair cannot.
const PATIENT := 2

## Fuse for a pair of plain hands. The others are read against this.
const BASE_FUSE := 1.6
## Span of a plain hand, in cells. Two of them reach `2 * BASE_SPAN`, which is what
## the shipped world's folds are sized against.
const BASE_SPAN := 4.0

const _REGISTRY := {
	PLAIN:   {"name": "plain",   "color": Color(1.00, 0.62, 0.36), "fuse": BASE_FUSE, "span": BASE_SPAN},
	SWIFT:   {"name": "swift",   "color": Color(0.36, 0.86, 1.00), "fuse": 0.65,      "span": 3.0},
	PATIENT: {"name": "patient", "color": Color(0.72, 0.55, 1.00), "fuse": 3.20,      "span": 6.0},
}

## An unregistered id behaves as plain rather than as nothing: a hand that does not
## know what it is should still be usable.
const _DEFAULT := {"name": "plain", "color": Color(1.00, 0.62, 0.36),
	"fuse": BASE_FUSE, "span": BASE_SPAN}


static func get_def(type: int) -> Dictionary:
	return _REGISTRY.get(type, _DEFAULT)


static func is_registered(type: int) -> bool:
	return _REGISTRY.has(type)


## Every kind, in id order. For iterating in tests and UI.
static func all_types() -> Array:
	return _REGISTRY.keys()


## The hand's colour — how you tell one kind from another, on the hand itself, on
## the pending anchor ring and on the pickup tile.
static func color(type: int) -> Color:
	return get_def(type)["color"]


static func type_name(type: int) -> String:
	return get_def(type)["name"]


## Seconds a pair of this kind waits before folding.
static func fuse(type: int) -> float:
	return get_def(type)["fuse"]


## How far an anchor of this kind reaches for a partner, in CELLS.
##
## A pair folds when the gap between its two anchors is within `span(a) + span(b)` —
## the two reaches added, which is the same test as "their circles touch" and the same
## test as "the MEAN of the two spans covers half the gap". That last equivalence is
## why there is no `span_for` beside `fuse_for`: mixed pairs already obey the mean
## here, and stating it twice would be two places to disagree.
##
## Cells rather than world units, because a span is a fact about the world's scale and
## the registry is read by authors. `Anchor.span` multiplies by the cell size.
##
## The physical reading: a fold slides BOTH flaps inward by half the gap, so a span is
## how much sheet this hand can drag toward itself. Under the sum, a long hand does
## some of a short partner's pulling for it — deliberately, for the same reason
## `fuse_for` takes the mean. Taking `min` instead would make the weakest hand of a
## pair decide everything about it, and there would be no reason ever to mix.
static func span(type: int) -> float:
	return get_def(type)["span"]


## The authoring key -> id ("swift" -> SWIFT). Unknown keys fall back to PLAIN, so a
## typo in a world file yields an ordinary hand rather than a broken one.
static func from_name(key: String) -> int:
	var wanted := key.strip_edges().to_lower()
	for type in _REGISTRY:
		if _REGISTRY[type]["name"] == wanted:
			return type
	return PLAIN


## How long a fold pinned with these two hands waits before it commits.
##
## The MEAN of the two, so a mixed pair lands genuinely between its parents rather
## than being decided by one of them. Taking the max would make a swift hand worthless
## the moment it was paired with a patient one; taking the min would make the patient
## hand's whole character vanish for the price of one swift pickup. Averaging is what
## makes pinning two different kinds a decision instead of a rounding error.
static func fuse_for(type_a: int, type_b: int) -> float:
	return (fuse(type_a) + fuse(type_b)) * 0.5
