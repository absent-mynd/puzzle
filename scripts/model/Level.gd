class_name Level extends RefCounted

## Everything true about the space the player is standing in right now.
##
## "One space at a time" is the rule the whole game is built on (see FoldWorld's
## header): the region world is simply the level with an empty fold context, a strip
## interior is a level with one, and an interior of an interior is a level with two.
## That was always the design — but the *state* of the current level was scattered
## across a dozen separate members of `FoldWorld`, all written in three places and
## read from everywhere.
##
## The cost of that scattering was not tidiness. It was that nothing could be handed
## "the current level" as an argument, so every collaborator that needed more than
## one or two facts about it had to be handed `FoldWorld` itself — which is how
## `WorldOverlay` ended up holding an untyped back-reference and reaching into two
## dozen members, and why the hand-ball physics could not be lifted out at all.
##
## This is a value: pure, headless, no scene tree, no behaviour that is not a
## question about its own contents. `FoldWorld` builds one in `_apply_context` and
## `rebuild`, and passes it to anything that needs to know where it is.

# --- Which sheet, and where in it ---

## The region this level belongs to. A level is always inside exactly one.
var region_id := ""

## The region's authored grid. The level derives from it but is not it: inside a
## fold, `base_pieces` is the captured strip, while this stays the whole region.
var base: BaseGrid = null

## The region's spawn point, in pixels.
var spawn := Vector2.ZERO

## True when this is a fold interior rather than the region world. Deliberately a
## bool and not `FoldWorld.Mode`: the kernel may not name the view (Decision 9), and
## "is this a subspace" is the only part of the enum anything here needs.
var in_subspace := false

## The fold whose interior this is, or null at region level.
var sub_fold: Fold = null

# --- The geometry, derived ---

## This level's own base: the region's identity pieces at world level, the parent's
## captured strip inside a fold.
var base_pieces: Array = []

## `base_pieces` with this level's fold list replayed over it. What is on screen.
var pieces: Array = []

## `pieces` indexed by plane position, for point lookups.
var pieces_by_pos: Dictionary = {}

## Collision geometry, and the goal tiles, both derived from `pieces`.
var wall_polys: Array = []
var goal_polys: Array = []

# --- How the space repeats ---

## No periods in a region, one inside a fold, two inside a fold whose creases run
## across the fold outside it — at which point you are walking on a torus.
var lattice: FoldLattice = FoldLattice.flat()

## How far the one non-repeating axis runs, as `{"min": float, "max": float}`.
## Empty when there is no such axis (a region, or a torus).
var free_extent: Dictionary = {}

## Where copies of this space are drawn.
var wrap_offsets: Array = [Vector2.ZERO]


## The one direction a thing can genuinely leave by, if there is one.
##
## Only a cylinder has such an end: a torus repeats both ways and has nowhere to go,
## and a region has the fall-out-of-the-world respawn instead. `slack` keeps a thing
## that is merely near the end from counting as past it.
func left_the_band(point: Vector2, slack: float) -> bool:
	var free := lattice.free_axis()
	if free == Vector2.ZERO or free_extent.is_empty():
		return false
	var t := point.dot(free)
	return t < float(free_extent["min"]) - slack or t > float(free_extent["max"]) + slack


## Where something that ran off the end of a band is put back: the middle of the band
## it just left. Only meaningful when `left_the_band` is true, which implies both a
## free axis and a `sub_fold`.
func turn_back_point() -> Vector2:
	if sub_fold == null or lattice.periods().is_empty():
		return Vector2.ZERO
	var period: Vector2 = lattice.periods()[0]
	return sub_fold.crease_point1 + period * 0.5


## How deep in folds this level sits. 0 is the region world.
func depth() -> int:
	return lattice.depth()
