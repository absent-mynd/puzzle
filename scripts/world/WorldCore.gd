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
## survive INTO the subspace). Captured from the current fragment list BEFORE the fold
## is applied, so it composes over earlier folds.
static func capture_strip(pieces: Array, fold: Fold, cell_size: float) -> Array:
	var out: Array = []
	for piece in pieces:
		var res := CollisionCore.fold_polygons([piece.polygon], fold, cell_size)
		for poly in res["dropped"]:
			var fp := FoldedPiece.new(
				piece.base_id, piece.type, poly, piece.plane_pos, piece.source_fold_id)
			fp.src_offset = piece.src_offset
			out.append(fp)
	return out


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


## Collision polygons of the non-walkable pieces in a fragment list. Walkability comes
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
# what it actually excised); a fold cannot be unfolded while any newer fold's excision
# band crosses that segment. The same test against the outer fold's two crease lines
# (the glue) gates exiting a subspace: interior folds parallel to the glue are fine,
# folds whose band crosses the glue must be unfolded first.

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


## Does a segment cross a fold's excision band (the open region strictly between its
## creases)? Half-pixel epsilon: grazing a crease doesn't block.
static func segment_intersects_band(p0: Vector2, p1: Vector2, fold: Fold) -> bool:
	var d0 := (p0 - fold.crease_point1).dot(fold.crease_normal)
	var d1 := (p1 - fold.crease_point1).dot(fold.crease_normal)
	var gap := fold.gap_distance()
	return maxf(d0, d1) > 0.5 and minf(d0, d1) < gap - 0.5


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


## Can these two cells make a fold? The only answer is no when they are the SAME
## cell: two coincident anchors give a zero-length crease normal, and every piece of
## geometry downstream divides by a gap of zero.
##
## There is deliberately no minimum distance. A one-cell fold is a perfectly good
## fold — it excises a one-cell band and the halves meet — and the rule that used to
## demand two cells was protecting nothing but taste. Whether a fold is worth making
## is the player's call, and they find out by making it.
static func anchors_valid(a: Vector2i, b: Vector2i) -> bool:
	return a != b


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
# the band you are folded inside, the two ends of a fold ride).
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
##   `flat_axis` (Vector2) unit axis to lead nowhere along (a fold's crease
##               normal: the strip already repeats that way, so a lead along it
##               slides the view past identical bands for nothing)
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

	var flat: Vector2 = ctx.get("flat_axis", Vector2.ZERO)
	if flat.length_squared() > GeometryCore.EPSILON:
		var n := flat.normalized()
		lead -= n * lead.dot(n)
	return lead.limit_length(LOOKAHEAD_MAX)
