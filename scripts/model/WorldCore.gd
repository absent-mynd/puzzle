class_name WorldCore extends RefCounted

## WorldCore
##
## Pure, testable logic for the side-view gravity world. The world reuses the fold
## kernel (BaseGrid / Fold / FoldReplay / CollisionCore / BaseFrame) unchanged; this
## file adds only what a continuous-physics view needs on top of it: map building,
## side-of-fold classification for a free (non-grid) position, strip capture for
## subspaces, seam/glue geometry for unfold blocking, and circle-vs-polygon
## depenetration so a physics body can ride flaps.
##
## Base-frame transport (the exact mapping that carries the player, entities and pinned
## anchors through folds) lives in `BaseFrame` — it is kernel, not view.
##
## Everything here is static and side-effect free.

const CELL := 64.0

## Map characters -> tile type. The registry (TileTypes) owns what each type DOES;
## this is only the authoring shorthand.
const CHARS := {
	"#": TileTypes.WALL,
	"G": TileTypes.GOAL,
	"~": TileTypes.WATER,
	"P": TileTypes.PIN,
	"_": TileTypes.UNANCHORABLE_FLOOR,
	"X": TileTypes.UNANCHORABLE_WALL,
	"T": TileTypes.TRIGGER_FOLD,
	"B": TileTypes.TRIGGER_BURST,
}


# ---------------------------------------------------------------------------
# Map building
# ---------------------------------------------------------------------------

## Build a BaseGrid from ASCII rows using CHARS; any unlisted character is empty air.
## Rows shorter than the widest row are padded with air, so hand-authored maps don't
## need exact-width literals. `data` optionally maps "x,y" -> per-tile data dictionary
## (trigger channels/anchors, occupant declarations).
static func parse_map(rows: Array, cell_size: float = CELL, data: Dictionary = {}) -> BaseGrid:
	var width := 0
	for r in rows:
		width = max(width, String(r).length())
	var height := rows.size()
	var bg := BaseGrid.new(Vector2i(width, height), cell_size)
	var tiles: Array[BaseTile] = []
	var next_id := 0
	for y in range(height):
		var row := String(rows[y])
		for x in range(width):
			var ch := row[x] if x < row.length() else "."
			var tile := BaseTile.new(next_id, Vector2i(x, y), CHARS.get(ch, TileTypes.EMPTY))
			var key := "%d,%d" % [x, y]
			if data.has(key):
				tile.data = (data[key] as Dictionary).duplicate()
			tiles.append(tile)
			next_id += 1
	bg.tiles = tiles
	bg._rebuild_index()
	return bg


# ---------------------------------------------------------------------------
# Fold classification for a continuous (pixel-space) position
# ---------------------------------------------------------------------------

## Which part of a fold a free point is in: -1 = A-side flap, 0 = the excised strip
## (between the creases), +1 = B-side flap. Mirrors FoldReplay's signed-distance rule
## (d <= 0 is A-side) so the player agrees with the tiles.
static func side_of_fold(pos: Vector2, fold: Fold) -> int:
	var d := (pos - fold.crease_point1).dot(fold.crease_normal)
	var gap := fold.gap_distance()
	if d <= 0.0:
		return -1
	if d >= gap:
		return 1
	return 0


## Pixel displacement a point riding the given side receives when the fold is applied.
static func fold_shift_for_side(side: int, fold: Fold, cell_size: float) -> Vector2:
	return fold.shift_a_px(cell_size) if side == -1 else fold.shift_b_px(cell_size)


## Pixel displacement a point receives when the fold is REMOVED. Sides are judged
## against the meeting line (where the two creases coincide after the fold): everything
## A-side of it slides back by -shift_a, B-side by -shift_b.
static func unfold_shift(pos: Vector2, fold: Fold, cell_size: float) -> Vector2:
	var meeting := fold.crease_point1 + fold.shift_a_px(cell_size)
	var d := (pos - meeting).dot(fold.crease_normal)
	if d <= 0.0:
		return -fold.shift_a_px(cell_size)
	return -fold.shift_b_px(cell_size)


# ---------------------------------------------------------------------------
# Subspace strip capture
# ---------------------------------------------------------------------------

## Everything a fold would excise, in the PRE-fold frame: the subspace's content, as
## real FoldedPieces (keeping base_id / src_offset so identity and base-frame mapping
## survive INTO the subspace). Captured from the current piece list BEFORE the fold
## is applied, so it composes over earlier folds.
static func capture_strip(pieces: Array, fold: Fold, cell_size: float) -> Array:
	return FoldReplay.capture_strip(pieces, fold, cell_size)


## Bounding interval of piece content along a direction (for the subspace's
## along-the-crease extent). Returns {"min": float, "max": float}; zeros if empty.
static func strip_extent(strip: Array, dir: Vector2) -> Dictionary:
	if strip.is_empty():
		return {"min": 0.0, "max": 0.0}
	var lo := INF
	var hi := -INF
	for entry in strip:
		for v in entry.polygon:
			var p := Vector2(v).dot(dir)
			lo = min(lo, p)
			hi = max(hi, p)
	return {"min": lo, "max": hi}


## Collision polygons of the non-walkable pieces in a piece list. Walkability comes
## from the registry, so a new blocking tile type needs no change here.
static func solid_polys_of(pieces: Array) -> Array:
	var out: Array = []
	for piece in pieces:
		if not TileTypes.is_walkable(piece.type):
			out.append(piece.polygon)
	return out


## Collision polygons of pieces of one specific type.
static func polys_of_type(pieces: Array, type: int) -> Array:
	var out: Array = []
	for piece in pieces:
		if piece.type == type:
			out.append(piece.polygon)
	return out


# ---------------------------------------------------------------------------
# Seam segments & unfold blocking
# ---------------------------------------------------------------------------
# Each fold stores its seam SEGMENT (its meeting line, clipped to the tangent extent of
# what it actually excised); a fold cannot be unfolded while any newer fold's excised
# strip crosses that segment. The same test against the outer fold's two crease lines
# (the glue) gates exiting a subspace: inner folds parallel to the glue are fine,
# folds whose strip crosses the glue must be unfolded first.

## The fold's seam segment: its meeting line over the excised content's extent.
static func seam_segment(fold: Fold, dropped: Array, cell_size: float) -> PackedVector2Array:
	var n := fold.crease_normal
	var t := Vector2(-n.y, n.x)
	var ext := strip_extent(dropped, t)
	var m := fold.crease_point1 + fold.shift_a_px(cell_size)
	var mt := m.dot(t)
	return PackedVector2Array([m + t * (ext["min"] - mt), m + t * (ext["max"] - mt)])


## The two glue-line segments of a fold's subspace (its crease lines over the strip
## content's tangent extent) — the outer fold's "seam" seen from inside.
static func glue_segments(fold: Fold, dropped: Array) -> Array:
	var n := fold.crease_normal
	var t := Vector2(-n.y, n.x)
	var ext := strip_extent(dropped, t)
	var out: Array = []
	for cp in [fold.crease_point1, fold.crease_point2]:
		var ct := Vector2(cp).dot(t)
		out.append(PackedVector2Array([
			Vector2(cp) + t * (ext["min"] - ct), Vector2(cp) + t * (ext["max"] - ct)]))
	return out


## How close to a crease still counts as ON it rather than across it. Half a world
## unit — an eighth of an art pixel, and far below anything the grid can express.
##
## Shared on purpose by the three questions that must never disagree about one crease:
## does this fold cross that seam, did it swallow that point, and which flap does the
## point ride out on. Two tolerances would be two answers.
const GRAZE := 0.5

## Does a segment cross a fold's excised strip (the open region strictly between its
## creases)? Grazing a crease doesn't block.
static func segment_intersects_strip(p0: Vector2, p1: Vector2, fold: Fold) -> bool:
	var d0 := (p0 - fold.crease_point1).dot(fold.crease_normal)
	var d1 := (p1 - fold.crease_point1).dot(fold.crease_normal)
	var gap := fold.gap_distance()
	return maxf(d0, d1) > GRAZE and minf(d0, d1) < gap - GRAZE


# ---------------------------------------------------------------------------
# Carrying a mark through a later fold
# ---------------------------------------------------------------------------
# A fold does not only add a seam of its own — it MOVES every mark already standing in
# the space, because it moves the sheet those marks are on. Both flaps slide inward and
# what lay between them is gone. So anything recorded in plane coordinates before a fold
# — an older fold's seam and the meeting cell you unfold it at — has to be carried
# through the folds made after it, in order, or it is a statement about a configuration
# that no longer exists.
#
# This is the fold list replaying, the same as everything else here (Decision 1). It is
# NOT `BaseFrame`: a seam is a property of the FOLD, not a point riding a tile, and it
# has to survive running over a hole in the sheet, where there is no piece to resolve
# against.

## Where a point lands once `fold` is applied — carried with whichever flap it sits on,
## or null if the fold excised it. A point grazing a crease rides that flap out rather
## than vanishing.
static func carry_point(p: Vector2, fold: Fold, cell_size: float):
	var d := (p - fold.crease_point1).dot(fold.crease_normal)
	var gap := fold.gap_distance()
	if d > GRAZE and d < gap - GRAZE:
		return null
	return p + (fold.shift_a_px(cell_size) if d <= GRAZE else fold.shift_b_px(cell_size))


## The same for a SEGMENT, which a fold can do more to than move: the part on each side
## rides that flap and the part between the creases is excised, so a fold laid across an
## older seam CUTS it and hands back the two pieces — now meeting at its own seam.
##
## Returns 0, 1 or 2 segments. Zero when the fold swallowed the whole thing.
static func carry_segment(p0: Vector2, p1: Vector2, fold: Fold, cell_size: float) -> Array:
	var n := fold.crease_normal
	var d0 := (p0 - fold.crease_point1).dot(n)
	var d1 := (p1 - fold.crease_point1).dot(n)
	var gap := fold.gap_distance()
	var out: Array = []
	for side in [[-INF, GRAZE, fold.shift_a_px(cell_size)],
			[gap - GRAZE, INF, fold.shift_b_px(cell_size)]]:
		var part := _span_between(p0, p1, d0, d1, float(side[0]), float(side[1]))
		if part.size() == 2:
			out.append(shift_segment(part, Vector2(side[2])))
	return out


## The stretch of `p0`..`p1` whose depth into the fold lies within `[lo, hi]`, or
## nothing. A segment parallel to the creases has one depth for its whole length and is
## therefore all in or all out — the case that has no intersection to solve for, and
## the one an older seam takes whenever it was folded the same way as the fold now
## crossing it.
static func _span_between(p0: Vector2, p1: Vector2, d0: float, d1: float,
		lo: float, hi: float) -> PackedVector2Array:
	var slope := d1 - d0
	if absf(slope) < GeometryCore.EPSILON:
		return PackedVector2Array([p0, p1]) if d0 >= lo and d0 <= hi \
			else PackedVector2Array()
	var ta := (lo - d0) / slope
	var tb := (hi - d0) / slope
	var t0 := maxf(0.0, minf(ta, tb))
	var t1 := minf(1.0, maxf(ta, tb))
	# Measured along the segment, not across the fold: a seam running almost parallel
	# to a crease covers very little depth over a very long line, and dropping it for
	# that would delete most of what this is here to carry.
	if (t1 - t0) * p0.distance_to(p1) <= GRAZE:
		return PackedVector2Array()          # a graze, not a length of seam
	return PackedVector2Array([p0.lerp(p1, t0), p0.lerp(p1, t1)])


static func shift_segment(seg: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	return PackedVector2Array([seg[0] + by, seg[1] + by])


# ---------------------------------------------------------------------------
# Circle-vs-polygon collision (physics-server-independent)
# ---------------------------------------------------------------------------
# Used for fold-ride placement: the physics server only sees rebuilt colliders on the
# next step, so ride/depenetration checks must be pure geometry.

static func circle_overlaps_polygon(center: Vector2, radius: float, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(center, poly):
		return true
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var closest := Geometry2D.get_closest_point_to_segment(center, a, b)
		if center.distance_to(closest) < radius:
			return true
	return false


static func circle_overlaps_solids(center: Vector2, radius: float, solids: Array) -> bool:
	for poly in solids:
		if circle_overlaps_polygon(center, radius, poly):
			return true
	return false


## Find a free spot for a circle near `center`, trying upward first (gravity game: flaps
## land floors under you, so escaping upward reads as "standing on the new ground"),
## then sideways, then slightly down. Returns the free position, or Vector2.INF if
## nothing nearby fits (caller should revert).
static func depenetrate(center: Vector2, radius: float, solids: Array) -> Vector2:
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for step in range(1, 17):
		offsets.append(Vector2(0, -8.0 * step))       # up, to 128px
	for step in range(1, 7):
		offsets.append(Vector2(-8.0 * step, 0))       # left
		offsets.append(Vector2(8.0 * step, 0))        # right
		offsets.append(Vector2(-8.0 * step, -32.0))
		offsets.append(Vector2(8.0 * step, -32.0))
	for step in range(1, 5):
		offsets.append(Vector2(0, 8.0 * step))        # small downward last resort
	for off in offsets:
		if not circle_overlaps_solids(center + off, radius, solids):
			return center + off
	return Vector2.INF


# ---------------------------------------------------------------------------
# Anchor & fold eligibility
# ---------------------------------------------------------------------------
# Off-axis pairs are allowed — the fold engine handles arbitrary crease angles — and
# so is any distance down to one cell. What is left of "eligibility" is the registry's
# per-type rules and the one degenerate case (both anchors on one cell), and both are
# asked WHEN THE FOLD FIRES rather than when a hand is placed: the fuse is a window
# for making a doubtful fold work, and a refusal at placement would close it.

# ---------------------------------------------------------------------------
# Spring follow (the hands that float beside you)
# ---------------------------------------------------------------------------

## One step of a critically-damped-ish spring toward `target`. Returns
## {"pos": Vector2, "vel": Vector2}.
##
## Used for the hands orbiting the player: they lag, overshoot and settle, which is
## the whole point of them — they are style, not a mechanic, and nothing reads them
## back. Semi-implicit Euler (velocity first, then position) because it stays stable
## at the stiffnesses that look lively; explicit Euler visibly gains energy there.
##
## `delta` is clamped: a long frame (a fold's rebuild, a breakpoint) must not fling a
## hand across the map, and a spring integrated in one huge step does exactly that.
static func spring_step(pos: Vector2, vel: Vector2, target: Vector2,
		stiffness: float, damping: float, delta: float) -> Dictionary:
	var dt := clampf(delta, 0.0, 1.0 / 30.0)
	var next_vel := vel + (target - pos) * stiffness * dt
	next_vel -= next_vel * clampf(damping * dt, 0.0, 1.0)
	return {"pos": pos + next_vel * dt, "vel": next_vel}


## Where a hand in slot `index` of `count` wants to sit relative to the body.
##
## Hands ride slightly above and to either side, and TRAIL the motion: the offset is
## pushed back against `motion`, so running left leaves them strung out to the right.
## That is what makes them read as carried objects rather than pinned decorations.
static func hand_orbit_offset(index: int, count: int, facing: int, motion: Vector2,
		radius: float) -> Vector2:
	var span := maxi(count, 1)
	# Spread the slots over an arc centred above the body: one hand sits dead
	# overhead, two straddle it.
	var t := (float(index) - float(span - 1) * 0.5)
	var angle := -PI * 0.5 + t * 0.72 * (1.0 if facing >= 0 else -1.0)
	return Vector2(cos(angle), sin(angle)) * radius - motion * 0.06


## How far a hand wanders from wherever it is resting.
##
## Small on purpose. A hand's drawn position is a claim about where it is — a loose
## one has to be walked over to be picked up, and a carried one has to read as riding
## the body — so the drift is an idle wobble, not a second orbit. About a third of an
## art pixel at rest, which at this resolution is exactly enough to be alive.
const DRIFT_RADIUS := 6.0

## The drift's four frequencies, in radians/sec: two per axis, deliberately sharing
## no common period. A hand bobbing on one sine has a loop the eye learns in a couple
## of seconds and then reads as an animation; beating two slow ones against each other
## gives a wander with no period at all.
const DRIFT_HZ := [1.7, 2.63, 1.31, 2.11]


## Where a hand sits relative to its resting spot at time `t`, given its own `seed`.
##
## PASSIVE motion: this is not driven by anything the player does and nothing reads it
## back, exactly like the orbit it is added to. It exists because a hand is an object
## in the world rather than a marker on it, and an object that holds perfectly still
## while everything around it breathes reads as part of the HUD.
##
## A function of absolute time, not an integration — so it needs no state, a hand
## dropped and picked back up keeps floating in the same phase it left in, and the
## same hand seen through several wrap copies of a strip floats identically in each.
##
## Weights sum to 1 per axis, so the offset never leaves a `radius`-square around the
## resting spot (at most `sqrt(2) * radius`, at a corner).
static func hand_drift(seed: float, t: float, radius: float = DRIFT_RADIUS) -> Vector2:
	return Vector2(
		0.62 * sin(t * DRIFT_HZ[0] + seed) + 0.38 * sin(t * DRIFT_HZ[1] + seed * 2.7),
		0.58 * sin(t * DRIFT_HZ[2] + seed * 1.9) + 0.42 * sin(t * DRIFT_HZ[3] + seed * 0.7),
	) * radius


# ---------------------------------------------------------------------------
# The hand as a ball: where a dropped hand goes, and how
# ---------------------------------------------------------------------------
# A loose hand behaves like an invisible light ball the size of its floating radius. It
# falls slowly (a lot of air drag), lands, rolls off slopes, and comes to rest.
#
# The simulation is PURE and lives here; the world owns the loop. A hand is only a ball
# while it is IN FLIGHT — the moment it comes to rest it becomes a `HandPickup` again,
# an occupant with no world position of its own.
#
# That boundary is the whole design, and it is what keeps `AGENTS.md` §8 intact. §8
# forbids caching a world position on a thing that lives in the world, because the
# piece list is the only authority on where anything is. A ball in flight does hold
# a position — but it holds it for a second or two and nothing persists it, and while
# it is in flight it is transported through `BaseFrame` exactly as the player is. So
# folds carry a flying hand correctly (a ball folded into a subspace goes on flying
# inside the subspace, velocity intact, because a fold is a translation and this step
# is position-independent — see `test_a_balls_velocity_is_untouched_by_a_translation`),
# and nothing that OUTLIVES the flight has a cached position at all.
#
# A resting hand whose ground a fold takes away wakes up and falls again
# (`hand_ball_supported` is that question). A resting hand whose ground merely MOVES
# rides its flap as it always did, because it is still an occupant of that tile.

## How far above the surface a resting hand hovers, in world units — a bit over an art
## pixel. It never quite touches: a hand is a held thing, and one sitting flush on the
## ground reads as painted onto the tile rather than lying on it.
const HAND_CLEARANCE := 6.0

## How far a dropped hand may fall before it stops looking for a floor. Bounded because
## over void there is no floor to find, and a hand that fell out of the world would be
## the one way this system loses one. Generous enough to clear any authored room.
const HAND_MAX_DROP := 12.0 * CELL

## Step of the coarse fall search, in world units. Fine enough that a hand lands ON a
## one-cell ledge rather than sinking through it. The landing is then refined, so this
## is only how finely the surface is LOOKED for, never how accurately it is found.
const HAND_FALL_STEP := 4.0

## Bisections used to refine a landing. The coarse step brackets the surface; without
## refining, the hover gap would be the clearance plus however much of a step the fall
## happened to have left over — so two hands dropped from different heights would rest
## at visibly different heights above the same floor. Eight halvings of a 4-unit step is
## well under a hundredth of a pixel.
const HAND_LANDING_BISECTIONS := 8

# --- The ball ---------------------------------------------------------------
# Light, draggy and small. The numbers are chosen for a READ — "a hand is barely heavier
# than the air" — not for realism, and they are all here rather than at any call site.

## Gravity on a hand, in units/s². A fraction of the player's `GRAVITY` (1800): a hand is
## a light thing, and a hand that fell at a body's weight would read as a dropped rock.
const HAND_GRAVITY := 520.0

## Air drag, as a fraction of velocity shed per second. High on purpose — this is what
## makes a hand FLOAT down instead of dropping, and what bleeds off the sideways speed a
## burst gave it so a hand never sails off across the map.
const HAND_DRAG := 2.6

## Terminal fall speed. Implied by gravity and drag together, but stated as a constant
## because it is the number the feel actually lives in, and `test_a_hand_is_light_and_
## floats_down` pins it against the player's own `MAX_FALL` to keep "a hand is light"
## true rather than merely intended.
const HAND_TERMINAL_FALL := HAND_GRAVITY / HAND_DRAG

## How much speed a hand keeps when it hits something. Low: a hand is soft and does not
## bounce, it lands. Not zero, because a dead stop on contact looks like a hand being
## switched off mid-air.
const HAND_RESTITUTION := 0.18

## Friction along a surface, per second, once in contact. What makes a roll stop.
const HAND_FRICTION := 3.4

## Below this speed, a supported hand is done and becomes a pickup again. Without a
## floor like this a ball jitters against the ground forever and never converts, and a
## hand that never converts is a hand that never rides a fold.
const HAND_REST_SPEED := 14.0

## Max distance a ball may move in one collision sub-step, in world units. The step is
## SWEPT in slices no longer than this, so a hand fired hard by a burst cannot pass
## through a one-cell floor.
const HAND_SWEEP_STEP := 3.0

## A supported ball that is touching something and got less than this far in a whole
## frame has nowhere left to go, and is at rest whatever its velocity vector says.
##
## This is the corner case made harmless. Contact resolution can leave a ball holding
## speed it cannot spend — pointed into a corner, with every direction it wants to move
## blocked. Judged on VELOCITY alone such a ball never rests; judged on whether it
## actually moved, it does. Progress is the honest test of motion, so it is the one used.
const HAND_STALL_DISTANCE := 0.35


## One step of the ball. `ball` is `{"pos": Vector2, "vel": Vector2, "resting": bool}`;
## returns the next state. Pure — the world holds the list and the loop.
##
## Position-independent: the same ball stepped anywhere behaves identically, which is
## exactly why a fold (a translation) can pick a flying hand up and put it down inside a
## subspace without disturbing its flight.
static func hand_ball_step(ball: Dictionary, solids: Array, delta: float) -> Dictionary:
	if bool(ball.get("resting", false)):
		return ball
	var pos: Vector2 = ball["pos"]
	var vel: Vector2 = ball["vel"]
	# Clamped like the spring's: a long frame (a fold's rebuild, a breakpoint) must not
	# teleport a hand, and a swept step integrated whole would do exactly that.
	var dt := clampf(delta, 0.0, 1.0 / 30.0)

	# A ball that STARTS inside something comes out of it before anything else. This is
	# not a rare case: a hand unpinned from a wall face begins its life inside that wall,
	# and a fold can close geometry around a hand in flight. Contact resolution assumes
	# it is being asked about a surface it is arriving at, so a ball already buried has
	# to be freed first or it will simply fall down the inside of the wall.
	if circle_overlaps_solids(pos, HAND_CLEARANCE, solids):
		var freed := eject_hand(pos, solids)
		if freed != Vector2.INF:
			pos = freed

	vel.y += HAND_GRAVITY * dt
	# Drag on both axes, applied as a fraction of the speed rather than a fixed
	# subtraction, so it never reverses the velocity at low speed.
	vel -= vel * clampf(HAND_DRAG * dt, 0.0, 1.0)

	# Sweep the move in slices, resolving contact in each. Slicing is what makes this
	# safe at speed; resolving per slice is what lets a hand land and then roll in the
	# same frame it touched down.
	var remaining := vel * dt
	var slices := maxi(1, int(ceil(remaining.length() / HAND_SWEEP_STEP)))
	var touched := false
	for _i in range(slices):
		var move := remaining / float(slices)
		var next := pos + move
		if not circle_overlaps_solids(next, HAND_CLEARANCE, solids):
			pos = next
			continue
		touched = true
		var n := hand_contact_normal(next, solids)
		if n == Vector2.ZERO:
			break                # wedged with no way out; stop and let rest catch it
		# Split into "into the surface" and "along it". The normal part bounces (barely),
		# the tangent part keeps going and is what a roll IS — a slope has a sideways
		# tangent, so gravity feeding into it accelerates the hand downhill.
		var into := vel.dot(n)
		if into < 0.0:
			vel -= n * into * (1.0 + HAND_RESTITUTION)
		vel -= (vel - n * vel.dot(n)) * clampf(HAND_FRICTION * dt, 0.0, 1.0)
		# Slide along the surface with what is left of this slice — shortening the slide
		# until it fits. A CORNER is why the shortening exists: there, the tangent curves
		# back into the corner's own radius, so the full slide always collides and a ball
		# that only tried the full slide would pin itself against the corner forever,
		# holding a velocity it could never spend. That is the one failure mode here that
		# a player would actually meet, as a hand stuck in the air that cannot be
		# collected.
		var along := move - n * move.dot(n)
		var slid_ok := false
		for scale: float in [1.0, 0.5, 0.25]:
			var slid: Vector2 = pos + along * scale
			if not circle_overlaps_solids(slid, HAND_CLEARANCE, solids):
				pos = slid
				slid_ok = true
				break
		if not slid_ok:
			# Nowhere along the surface to go. Ease OUT along the normal instead, so the
			# next frame starts free and the hand can leave the corner (over the lip, or
			# off it) rather than being held there.
			var out := pos + n * HAND_SWEEP_STEP * 0.5
			if not circle_overlaps_solids(out, HAND_CLEARANCE, solids):
				pos = out
			break

	var resting := false
	var stalled := touched and pos.distance_to(Vector2(ball["pos"])) < HAND_STALL_DISTANCE
	if touched and hand_ball_supported(pos, solids) \
			and (vel.length() <= HAND_REST_SPEED or stalled):
		# Land it exactly on its floating radius, so every hand at rest hovers by the
		# same gap however it arrived — the hover has to be a property of a hand, not of
		# the frame its fall happened to end on.
		pos = drop_hand(pos, solids)
		vel = Vector2.ZERO
		resting = true
	return {"pos": pos, "vel": vel, "resting": resting}


## The surface normal a ball at `at` is in contact with: the direction that gets it out
## of what it is touching, averaged over everything it touches at once (so a ball landing
## in a corner is pushed out of the corner rather than along one of its walls).
static func hand_contact_normal(at: Vector2, solids: Array) -> Vector2:
	var sum := Vector2.ZERO
	for poly in solids:
		if not circle_overlaps_polygon(at, HAND_CLEARANCE, poly):
			continue
		var closest := hand_closest_point_on(at, poly)
		var away := at - closest
		if away.length_squared() > GeometryCore.EPSILON:
			sum += away.normalized()
		elif poly.size() >= 3:
			# Dead centre on an edge: fall back to away-from-centroid, which is at least
			# outward. Rare, and any outward direction beats none.
			var c := GeometryCore.polygon_centroid(poly)
			if (at - c).length_squared() > GeometryCore.EPSILON:
				sum += (at - c).normalized()
	if sum.length_squared() <= GeometryCore.EPSILON:
		return Vector2.ZERO
	return sum.normalized()


## Nearest point on a polygon's boundary to `at`.
static func hand_closest_point_on(at: Vector2, poly: PackedVector2Array) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for i in range(poly.size()):
		var p := Geometry2D.get_closest_point_to_segment(
			at, poly[i], poly[(i + 1) % poly.size()])
		var d := at.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


## Bring a point back into the strip's fundamental domain, wrapping across the glue.
##
## A subspace IS a cylinder: the strip repeats forever along the crease normal, and the
## two glue lines are the same line. `_subspace_wrap_and_turnback` does this for the
## player; anything else living in a strip has to agree with it, or objects and player
## disagree about where "here" is.
##
## Stated as a modulo rather than the player's one-strip if/elif, because a falling thing
## accelerates: at terminal speed against a one-cell fold a single frame can cross more
## than one strip width, and a single-step wrap would leave it outside. `floor` handles any
## number of laps at the same cost.
##
## The consequence worth knowing: when the wrap axis has a vertical component, an object
## that falls never lands — it comes back around the top and keeps going. That is not a
## bug to guard against but the honest behaviour of a closed space, and it costs nothing
## to support: a ball in orbit is one dot product a frame.
static func wrap_into_strip(pos: Vector2, normal: Vector2, crease1: Vector2,
		gap: float) -> Vector2:
	if gap <= GeometryCore.EPSILON:
		return pos
	var d := (pos - crease1).dot(normal)
	return pos - normal * (floor(d / gap) * gap)


## Is there ground under a hand at `at`? Asked of every resting hand after a fold: if the
## answer has become no, the hand wakes up and falls again.
##
## "Under" is a short probe straight down rather than a contact test, because a resting
## hand hovers clear of its floor by design — it is never actually touching the thing
## holding it up.
static func hand_ball_supported(at: Vector2, solids: Array) -> bool:
	return circle_overlaps_solids(
		at + Vector2(0, HAND_CLEARANCE * 0.75), HAND_CLEARANCE, solids)


## Where a hand dropped at `at` actually comes to rest, given the solid polygons of the
## current view. Pure: it computes a resting place, it does not animate a fall.
##
## Two cases, and they are one question:
##
##   - in the open, it falls straight down to the first surface under it and hovers
##     `HAND_CLEARANCE` above it;
##   - inside a wall, it is pushed out through the nearest face first, and then falls
##     from wherever that put it.
##
## Ejecting BEFORE falling is what makes a hand dropped into a wall come out of it
## rather than sliding down its inside to the floor of the room below. A hand you can
## see is a hand you can go and fetch, which is the only property that has to hold.
##
## Idempotent: settling a hand already at rest returns where it already is, so a
## re-settle on a rebuild cannot walk it a little further each time.
static func settle_hand(at: Vector2, solids: Array) -> Vector2:
	var from := at
	if circle_overlaps_solids(from, HAND_CLEARANCE, solids):
		var out := eject_hand(from, solids)
		if out == Vector2.INF:
			return at            # nowhere to go; leave it where it was asked for
		from = out
	return drop_hand(from, solids)


## Fall straight down from `at` to the first surface under it, coming to rest exactly
## `HAND_CLEARANCE` above it. Returns `at` itself when it is already resting on
## something, and the end of its reach when there is no floor within it.
##
## Coarse steps to find the surface, then bisection to land on it: the gap a hand hovers
## at has to be the same gap every time, or hands dropped from different heights rest at
## different heights above one floor and the clearance stops reading as a property of a
## hand.
static func drop_hand(at: Vector2, solids: Array) -> Vector2:
	var steps := int(HAND_MAX_DROP / HAND_FALL_STEP)
	var pos := at
	for _i in range(steps):
		var next := pos + Vector2(0, HAND_FALL_STEP)
		if circle_overlaps_solids(next, HAND_CLEARANCE, solids):
			# `pos` is clear and `next` is not: the surface is between them. Close the
			# bracket so the hand rests on it rather than up to a step above it.
			var lo := pos
			var hi := next
			for _b in range(HAND_LANDING_BISECTIONS):
				var mid := (lo + hi) * 0.5
				if circle_overlaps_solids(mid, HAND_CLEARANCE, solids):
					hi = mid
				else:
					lo = mid
			return lo
		pos = next
	return pos


## Push a hand out of the solid it is inside, through the nearest face. Searches
## outward in a ring so the shortest way out wins — a hand near the top of a block
## comes out of the top, which is where you would expect to find it. Vector2.INF if
## there is no free spot within a couple of cells.
static func eject_hand(at: Vector2, solids: Array) -> Vector2:
	if not circle_overlaps_solids(at, HAND_CLEARANCE, solids):
		return at
	var dirs: Array[Vector2] = []
	for i in range(16):
		var a := TAU * float(i) / 16.0
		dirs.append(Vector2(cos(a), sin(a)))
	# Radius-major: every direction is tried at a small distance before any is tried at
	# a large one, so "nearest face" means nearest, not first in the list.
	for step in range(1, 17):
		var r := HAND_FALL_STEP * float(step)
		for d in dirs:
			var p := at + d * r
			if not circle_overlaps_solids(p, HAND_CLEARANCE, solids):
				return p
	return Vector2.INF


## A hand's own drift phase, so no two float in step.
##
## Keyed on WHAT the hand is — its base identity and its point on that tile — and never
## on where it sits in a list. Seeding by list index would make every remaining hand
## jump to a new phase the moment a different one was picked up, which is a visible
## twitch caused by an event somewhere else entirely.
static func hand_drift_seed(id: int, point: Vector2) -> float:
	return float(id) * 1.7 + point.x * 0.013 + point.y * 0.0071


## Can these two cells make a fold? The only answer is no when they are the SAME
## cell: two coincident anchors give a zero-length crease normal, and every piece of
## geometry downstream divides by a gap of zero.
##
## There is deliberately no minimum distance. A one-cell fold is a perfectly good
## fold — it excises a one-cell strip and the halves meet — and the rule that used to
## demand two cells was protecting nothing but taste. Whether a fold is worth making
## is the player's call, and they find out by making it.
static func anchors_valid(a: Vector2i, b: Vector2i) -> bool:
	return a != b


## The cells an anchor may be pinned in from where you are standing: a square of
## `reach` cells around your own, **diagonals included**.
##
## A square rather than a circle because what is being chosen is a CELL. A radius
## measured from the body to cell centres admits or refuses a diagonal depending on
## where inside your own cell you happen to be standing, which is a rule whose effects
## a player can see and whose cause they never can. A square around your cell is one
## you can count.
##
## `reach` is arm's length, and it is load bearing in a way worth knowing before
## raising it: a shell one tile thick keeps you out of what it encloses precisely
## because every cell inside it is two away from every cell outside. That is the whole
## of why the sealed chamber is sealed (see `scripts/world/README.md` §beat 4).
static func within_arm_reach(from: Vector2i, cell: Vector2i, reach: int) -> bool:
	return absi(cell.x - from.x) <= reach and absi(cell.y - from.y) <= reach


## `cell` pulled back inside that square.
##
## The placement cursor CLAMPS rather than refusing a step: pushing at the edge of
## your reach should do nothing rather than cost you the press. It also makes "step,
## then clamp" total — there is no direction that can leave the cursor somewhere it is
## not allowed to be, so no caller has to check afterwards.
static func clamp_to_arm_reach(from: Vector2i, cell: Vector2i, reach: int) -> Vector2i:
	return Vector2i(
		clampi(cell.x, from.x - reach, from.x + reach),
		clampi(cell.y, from.y - reach, from.y + reach))


## Can an anchor be pinned on the surface at this plane cell? Refused when the dominant
## piece there is an anchor-blocking type (UNANCHORABLE_*), or when the cell is void.
static func can_anchor_at(pieces_by_pos: Dictionary, cell: Vector2i) -> bool:
	var here: Array = pieces_by_pos.get(cell, [])
	if here.is_empty():
		return false
	var types: Array = []
	for p in here:
		types.append(p.type)
	return not TileTypes.blocks_anchor(TileTypes.dominant_type(types))


## Would a fold excise or cut a fold-proof tile (a PIN)? Delegates to the kernel: the
## rule has to hold for every fold, not just the ones the player commits, so it lives
## next to the derivation (see `FoldReplay.blocked_by_tile`).
static func fold_blocked_by_tile(pieces: Array, fold: Fold, cell_size: float) -> bool:
	return FoldReplay.blocked_by_tile(pieces, fold, cell_size)


# ---------------------------------------------------------------------------
# Camera framing
# ---------------------------------------------------------------------------
# The lens is not fixed. A tight frame reads the BODY and a wide one reads the
# SPACE — and this is a game about the shape of the space, so how much to show
# is a question about what the moment is: how hard you are moving, and what
# would be a mistake to leave off screen (an anchor pinned twenty cells back,
# the strip you are folded inside, the two ends of a fold ride).
#
# Every term can only WIDEN the frame. Resting is the tightest it ever sits, so
# the camera never closes in on you unasked.

## Zoom with nothing happening: standing still, nothing pinned. Camera2D zoom
## semantics — below 1.0 sees more world than the design scale.
const ZOOM_RESTING := 0.80
## The widest the frame may go. A fold can span a whole region; without a floor,
## pinning its far anchor would shrink the world to a postage stamp.
const ZOOM_WIDEST := 0.55
## How much of the frame all-out motion pulls out.
const ZOOM_MOTION_PULL := 0.28
## ...and how much a fold transition does, on top.
const ZOOM_CONTEXT_PULL := 0.10
## Framed points are kept at least this far inside the window edge, so a thing
## that matters never sits half-cropped against the border.
const ZOOM_FOCUS_MARGIN := 2.5 * CELL


## Target zoom for the moment described by `ctx`:
##   `viewport` (Vector2) window size in pixels
##   `center`   (Vector2) where the camera is — focus distances measure from here
##   `motion`   (float 0..1) how hard the body is moving; see PlayerBody.motion_intensity
##   `widen`    (float 0..1) extra context pull (a fold rearranging the world)
##   `focus`    (PackedVector2Array) world points that must stay on screen
static func camera_zoom_for(ctx: Dictionary) -> float:
	var motion := clampf(float(ctx.get("motion", 0.0)), 0.0, 1.0)
	var widen := clampf(float(ctx.get("widen", 0.0)), 0.0, 1.0)
	var zoom := ZOOM_RESTING * (1.0 - ZOOM_MOTION_PULL * motion - ZOOM_CONTEXT_PULL * widen)

	var focus: PackedVector2Array = ctx.get("focus", PackedVector2Array())
	if not focus.is_empty():
		var viewport: Vector2 = ctx.get("viewport", Vector2(1280, 720))
		var center: Vector2 = ctx.get("center", Vector2.ZERO)
		# The camera sits at `center`, not at the middle of the focus set, so what
		# has to fit is the largest distance OUT to a focus point — not the span
		# between them. Two anchors close together but far to one side still need
		# a wide frame.
		var reach := Vector2(ZOOM_FOCUS_MARGIN, ZOOM_FOCUS_MARGIN)
		for p in focus:
			var d := (Vector2(p) - center).abs()
			reach.x = maxf(reach.x, d.x + ZOOM_FOCUS_MARGIN)
			reach.y = maxf(reach.y, d.y + ZOOM_FOCUS_MARGIN)
		zoom = minf(zoom, minf(viewport.x * 0.5 / reach.x, viewport.y * 0.5 / reach.y))
	return clampf(zoom, ZOOM_WIDEST, ZOOM_RESTING)


## Half-diagonal of the world rectangle a viewport shows at `zoom`: how far from
## the camera something can sit and still be drawn. Used to decide how many copies
## of a repeating strip to build — a visible end to the repetition breaks it.
static func camera_view_radius(viewport: Vector2, zoom: float) -> float:
	return (viewport / maxf(zoom, 0.01)).length() * 0.5


# ---------------------------------------------------------------------------
# Camera lookahead
# ---------------------------------------------------------------------------
# Zoom decides how MUCH to show; lookahead decides WHERE to centre it. Sitting
# the body dead centre spends half the frame on ground already crossed, which is
# the wrong half — what you are about to reach is what you need to read.
#
# So the frame leads the way you are going. The asymmetries are the whole design:
# a fall leads much further than a rise (a fall is committed and its landing is
# the thing you need to see; the top of a jump is about to reverse, and leading
# hard there would swing the frame back a moment later), and a held look key
# leads on its own, because wanting to see what is up there is a thing you can
# ask for without moving.

## Horizontal lead at a full run.
const LOOKAHEAD_RUN := 3.5 * CELL
## Vertical lead in a terminal-speed fall — the long drop, framed for its landing.
const LOOKAHEAD_FALL := 5.0 * CELL
## ...and at the start of a jump. Deliberately much shorter; see above.
const LOOKAHEAD_RISE := 1.5 * CELL
## Lead from holding a look direction with no motion at all.
const LOOKAHEAD_PEEK := 3.0 * CELL
## Ceiling on the whole offset. The zoom's focus set keeps the body on screen
## (`camera_zoom_for` measures focus FROM the led camera position), so this is
## about the body not drifting to the edge of its own frame, not about clipping.
const LOOKAHEAD_MAX := 6.0 * CELL


## Where the camera should sit RELATIVE to the body, for the moment in `ctx`:
##   `velocity`  (Vector2) per-axis fraction of the body's own limits, signed —
##               x in units of run speed, y of terminal fall (down) / jump (up).
##               The body normalizes, because the body owns those limits.
##   `look`      (float) held vertical look, -1 up .. +1 down. Vertical only:
##               left/right is what running already says.
##   `flat_axes` (Array[Vector2]) axes to lead nowhere along — the periods of the
##               space (see `FoldLattice`). A repeating space already shows every
##               copy there is along an axis it repeats on, so a lead there slides
##               the view past identical strips for nothing. One axis inside a
##               fold; TWO on the torus you get by folding yourself in twice
##               across the grain, and then the lead is the body's alone.
##   `flat_axis` (Vector2) the single-axis form, for callers with one.
##   `frozen`    (bool) riding a fold — lead nowhere; the transition frames itself
static func camera_lookahead_for(ctx: Dictionary) -> Vector2:
	if bool(ctx.get("frozen", false)):
		return Vector2.ZERO
	var vel: Vector2 = ctx.get("velocity", Vector2.ZERO)
	var look := clampf(float(ctx.get("look", 0.0)), -1.0, 1.0)

	var lead := Vector2.ZERO
	lead.x = LOOKAHEAD_RUN * clampf(vel.x, -1.0, 1.0)
	# Down and up are different reaches, not one signed scale.
	lead.y = (LOOKAHEAD_FALL * clampf(vel.y, 0.0, 1.0)
		- LOOKAHEAD_RISE * clampf(-vel.y, 0.0, 1.0)
		+ LOOKAHEAD_PEEK * look)

	var flats: Array = ctx.get("flat_axes", [])
	var single: Vector2 = ctx.get("flat_axis", Vector2.ZERO)
	if single.length_squared() > GeometryCore.EPSILON:
		flats = flats + [single]
	for axis in flats:
		var v: Vector2 = axis
		if v.length_squared() <= GeometryCore.EPSILON:
			continue
		var n := v.normalized()
		lead -= n * lead.dot(n)
	return lead.limit_length(LOOKAHEAD_MAX)
