class_name ProtoCore extends RefCounted

## ProtoCore
##
## Pure, testable logic for the side-view (gravity) metroidvania prototype.
## The prototype reuses the real fold model (BaseGrid / Fold / FoldReplay /
## CollisionCore) unchanged; this file adds only what the continuous-physics
## view layer needs: map building, side-of-fold classification for a free
## (non-grid) player position, strip capture for the subspace, and simple
## circle-vs-polygon depenetration so the player can ride flaps.
##
## Everything here is static and side-effect free.

const CELL := 64.0


# ---------------------------------------------------------------------------
# Map building
# ---------------------------------------------------------------------------

## Build a BaseGrid from ASCII rows. '#'=wall, 'G'=goal, anything else = empty
## air. Rows shorter than the widest row are padded with air, so hand-authored
## maps don't need exact-width literals.
static func parse_map(rows: Array, cell_size: float = CELL) -> BaseGrid:
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
			var type := BaseTile.TYPE_EMPTY
			match ch:
				"#": type = BaseTile.TYPE_WALL
				"G": type = BaseTile.TYPE_GOAL
			tiles.append(BaseTile.new(next_id, Vector2i(x, y), type))
			next_id += 1
	bg.tiles = tiles
	bg._rebuild_index()
	return bg


# ---------------------------------------------------------------------------
# Fold classification for a continuous (pixel-space) position
# ---------------------------------------------------------------------------

## Which part of a fold a free point is in: -1 = A-side flap, 0 = the excised
## strip (between the creases), +1 = B-side flap. Mirrors FoldReplay's signed-
## distance rule (d <= 0 is A-side) so the player agrees with the tiles.
static func side_of_fold(pos: Vector2, fold: Fold) -> int:
	var d := (pos - fold.crease_point1).dot(fold.crease_normal)
	var gap := fold.gap_distance()
	if d <= 0.0:
		return -1
	if d >= gap:
		return 1
	return 0


## Pixel displacement a point riding the given side receives when the fold is
## applied.
static func fold_shift_for_side(side: int, fold: Fold, cell_size: float) -> Vector2:
	return fold.shift_a_px(cell_size) if side == -1 else fold.shift_b_px(cell_size)


## Pixel displacement a point receives when the fold is REMOVED. Sides are
## judged against the meeting line (where the two creases coincide after the
## fold): everything A-side of it slides back by -shift_a, B-side by -shift_b.
static func unfold_shift(pos: Vector2, fold: Fold, cell_size: float) -> Vector2:
	var meeting := fold.crease_point1 + fold.shift_a_px(cell_size)
	var d := (pos - meeting).dot(fold.crease_normal)
	if d <= 0.0:
		return -fold.shift_a_px(cell_size)
	return -fold.shift_b_px(cell_size)


# ---------------------------------------------------------------------------
# Subspace strip capture
# ---------------------------------------------------------------------------

## Everything a fold would excise, in the PRE-fold frame: the subspace's
## content. Each entry is {"polygon": PackedVector2Array, "type": int}.
## Captured from the current fragment list BEFORE the fold is applied, so it
## composes correctly over earlier folds.
static func capture_strip(pieces: Array, fold: Fold, cell_size: float) -> Array:
	var out: Array = []
	for piece in pieces:
		var res := CollisionCore.fold_polygons([piece.polygon], fold, cell_size)
		for poly in res["dropped"]:
			out.append({"polygon": poly, "type": piece.type})
	return out


## Bounding interval of strip content along a direction (for the subspace's
## along-the-crease extent). Returns {"min": float, "max": float}; zeros if empty.
static func strip_extent(strip: Array, dir: Vector2) -> Dictionary:
	if strip.is_empty():
		return {"min": 0.0, "max": 0.0}
	var lo := INF
	var hi := -INF
	for entry in strip:
		for v in entry["polygon"]:
			var p := Vector2(v).dot(dir)
			lo = min(lo, p)
			hi = max(hi, p)
	return {"min": lo, "max": hi}


# ---------------------------------------------------------------------------
# Circle-vs-polygon collision (physics-server-independent)
# ---------------------------------------------------------------------------
# Used for fold-ride placement: the physics server only sees rebuilt colliders
# on the next step, so ride/depenetration checks must be pure geometry.

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


## Find a free spot for a circle near `center`, trying upward first (gravity
## game: flaps land floors under you, so escaping upward reads as "standing on
## the new ground"), then sideways, then slightly down. Returns the free
## position, or Vector2.INF if nothing nearby fits (caller should revert).
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
# Anchor validation (prototype rules: axis-aligned, gap >= 2 cells)
# ---------------------------------------------------------------------------

static func anchors_valid(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return false
	if a.x != b.x and a.y != b.y:
		return false
	var gap := absi(a.x - b.x) + absi(a.y - b.y)
	return gap >= 2
