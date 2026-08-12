class_name HandField extends RefCounted

## Hands that are in the air.
##
## The boundary this draws is the one that already existed in the design and was
## only ever implicit: **a hand is either a ball or an occupant, never both.** In
## flight it has a position of its own and gravity acts on it — that is this class.
## At rest it has no position of its own; where it lies is a question asked of the
## piece list, so it rides flaps and folds away exactly like a door or a lamp —
## that is `FoldWorld`, and it is what keeps ARCHITECTURE.md Decision 10 true.
##
## So this owns the flight and nothing else. The two moments a ball stops being a
## ball are signals rather than calls, because what happens next is the world's
## business: `landed` when it comes to rest, `lost` when it falls out of the world
## entirely. `FoldWorld` answers both by making an occupant.
##
## Everything it needs to know about where it is arrives as a `Space`. Before that
## object existed this could not be lifted out of `FoldWorld` at all — the flight
## depends on the collision geometry, how the space repeats, how far the one
## non-repeating axis runs, and whether this is a subspace, and those were a
## dozen separate members. Passing ten things is not an interface; passing the space
## is.

## A ball came to rest. The world turns it into an occupant of the sheet.
signal landed(ball: Dictionary)

## A ball left the world along the one axis it could leave by. The world puts the
## hand back somewhere findable — never destroys it.
signal lost(kind: int)

## How much slack a ball gets before it counts as having left the strip.
const STRIP_SLACK := 4.0 * WorldCore.CELL

## How far below the sheet counts as having fallen out of the world.
const FALL_OUT_MARGIN := 8.0 * WorldCore.CELL

## Balls in flight. Each is
## `{kind, pos, vel, resting, region, in_sub, seed}`, plus `homeless` once it has
## been through the no-sheet-anywhere path — see `FoldWorld._land_ball`.
var balls: Array = []


func is_empty() -> bool:
	return balls.is_empty()


func size() -> int:
	return balls.size()


func clear() -> void:
	balls.clear()


## Put a hand into the air at `at`, with an optional kick.
##
## `drift_seed` is the ball's drift phase, so two hands in flight together do not bob
## in lockstep. The caller supplies it because the two launch sites seed from
## different things — a dropped hand from its launch point, a woken one from the base
## tile it was lying on — and that is a policy question, not a flight one.
func launch(kind: int, at: Vector2, space: Space, vel: Vector2, drift_seed: float) -> void:
	balls.append({
		"kind": kind,
		"pos": at,
		"vel": vel,
		"resting": false,
		"region": space.region_id,
		"in_sub": space.in_subspace,
		"seed": drift_seed,
	})


## Which way the next tossed hand is kicked. Alternating is what makes two hands out
## of one fold read as a pair rather than a stack.
func next_toss_side() -> float:
	return 1.0 if balls.size() % 2 == 0 else -1.0


## Re-admit a ball the world could not place. Keeps it countable and catchable
## rather than deleting it — the one thing this system must never do.
func readmit(ball: Dictionary) -> void:
	balls.append(ball)


## Step every ball in the CURRENT view.
##
## Only the current view: the overworld and a subspace are different spaces
## with different ground, and a ball must not fall through the other one's floor. A
## ball in the view you are not in simply waits — which is right, because the fold it
## is inside is not a place where time is passing for you either.
func step(space: Space, delta: float) -> void:
	if balls.is_empty():
		return
	var solids := space.wall_polys
	var here := space.in_subspace
	for i in range(balls.size() - 1, -1, -1):
		var ball: Dictionary = balls[i]
		if bool(ball["in_sub"]) != here or String(ball["region"]) != space.region_id:
			continue

		var next := WorldCore.hand_ball_step(ball, solids, delta)
		ball["pos"] = next["pos"]
		ball["vel"] = next["vel"]

		if bool(next["resting"]):
			balls.remove_at(i)
			landed.emit(ball)
		elif here:
			# In a repeating space, a falling thing WRAPS — the same rule the player
			# crosses a glue line by, asked of the same lattice, so it holds at any
			# depth and on a torus it wraps both ways at once. When a wrap axis has a
			# vertical component that is a hand in orbit, indefinitely, and it is a
			# real object in a real place rather than a leak: it is still counted,
			# still catchable, and it still lands the moment a fold puts ground in
			# its way.
			ball["pos"] = space.lattice.wrap(Vector2(ball["pos"]))
			# The one direction a space may NOT repeat in is the one direction a
			# thing can genuinely leave by. Turn it back the way the fold turns the
			# player back — and on a torus there is no such direction, so nothing to
			# do.
			if space.left_the_strip(Vector2(ball["pos"]), STRIP_SLACK):
				ball["pos"] = space.turn_back_point()
				ball["vel"] = Vector2.ZERO
		elif Vector2(ball["pos"]).y > space.base.grid_size.y * WorldCore.CELL + FALL_OUT_MARGIN:
			# In a region there is a bottom to fall off. Rather than lose the hand
			# — the one thing this system must never do — hand it back to the world to
			# put somewhere findable.
			balls.remove_at(i)
			lost.emit(int(ball["kind"]))


## Carry every in-flight ball through a fold, exactly as the player is carried.
##
## A ball is transported by `BaseFrame` like anything else in the world, so a hand in
## flight that a fold sweeps into a subspace goes on flying INSIDE the subspace. Its
## velocity is untouched: a fold is a translation, so the flight it was on is still
## the flight it is on.
##
## `into_sub` says the fold swallowed this view into a strip, so surviving balls
## belong to the subspace from now on. A ball the fold leaves nowhere — its tile
## excised while the view stays put — is one the strip captured, and it flies on in
## there.
func carry_through(space: Space, new_pieces: Array, into_sub: bool) -> void:
	var here := space.in_subspace
	for ball in balls:
		if bool(ball["in_sub"]) != here or String(ball["region"]) != space.region_id:
			continue
		var from = BaseFrame.piece_containing(
			space.pieces_by_pos, Vector2(ball["pos"]), WorldCore.CELL)
		var dest = null
		if from != null:
			dest = BaseFrame.world_point_from_base(
				new_pieces, from.base_id, Vector2(ball["pos"]) - from.src_offset)
		if dest != null:
			ball["pos"] = Vector2(dest)
			if into_sub:
				ball["in_sub"] = true
			continue
		# No home in the new configuration: the fold excised the ground it was over.
		# It is inside the strip now, which is a real place — so it keeps flying, in
		# there.
		ball["in_sub"] = true


## Where the balls of the current view are, for drawing.
func points_in(space: Space) -> Array:
	var out: Array = []
	for ball in balls:
		if bool(ball["in_sub"]) != space.in_subspace \
				or String(ball["region"]) != space.region_id:
			continue
		out.append({
			"kind": int(ball["kind"]),
			"pos": Vector2(ball["pos"]),
			"seed": float(ball["seed"]),
		})
	return out
