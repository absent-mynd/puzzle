class_name CollisionCore extends RefCounted

## CollisionCore
##
## The geometry layer for the collision engine: folding polygon sets, and the
## navigable/containment/overlap predicates that gate movement. Sits above the
## primitive `GeometryCore` (Sutherland-Hodgman clip, area, centroid) and wraps
## Godot's built-in `Geometry2D` booleans (`clip_polygons` = A−B, `intersect_polygons`,
## `merge_polygons`). All static & pure.
##
## DETERMINISM: `Geometry2D` output vertex order/winding is canonicalized and quantized
## (`canon`) before any result is stored in the replay checkpoint, so the pure
## derive/replay stays byte-identical across runs.

const MIN_AREA := 0.01       # drop sub-pixel slivers (matches FoldReplay._MIN_AREA)
const CONTAIN_EPS := 1.0     # px² remainder tolerance for "fully contained"
const SWEEP_MAX_STEP := 8.0  # px; max gap between swept collision samples
const QUANT := 0.001         # px vertex quantization for determinism


# ---------------------------------------------------------------------------
# Fold transform (shared by tile pieces AND occupant footprints)
# ---------------------------------------------------------------------------

## Clip a set of polygons by a fold's two parallel creases, meet-in-the-middle:
##   a       = A-side pieces (d<=0), translated by shift_a  (kept, moved inward)
##   b       = B-side pieces (d>=gap), translated by shift_b (kept, moved inward)
##   dropped = the between-strip pieces (0<d<gap), in the PRE-fold frame (untranslated)
## Tiles keep a+b and discard dropped; occupants keep a+b as footprint and store dropped
## as a latent (restored, in its original frame, on unfold).
static func fold_polygons(polys: Array, fold: Fold, cell_size: float) -> Dictionary:
	var out_a: Array = []
	var out_b: Array = []
	var dropped: Array = []
	var p1 := fold.crease_point1
	var p2 := fold.crease_point2
	var normal := fold.crease_normal
	var shift_a := fold.shift_a_px(cell_size)
	var shift_b := fold.shift_b_px(cell_size)
	for poly in polys:
		var s1 := GeometryCore.split_polygon_by_line(poly, p1, normal)
		var a_frag: PackedVector2Array = s1["left"]
		var rest: PackedVector2Array = s1["right"]
		if _valid(a_frag):
			out_a.append(_translate(a_frag, shift_a))
		if not _valid(rest):
			continue
		var s2 := GeometryCore.split_polygon_by_line(rest, p2, normal)
		var between: PackedVector2Array = s2["left"]
		var b_frag: PackedVector2Array = s2["right"]
		if _valid(between):
			dropped.append(between)  # pre-fold frame — no shift
		if _valid(b_frag):
			out_b.append(_translate(b_frag, shift_b))
	return {"a": out_a, "b": out_b, "dropped": dropped}


static func _valid(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and GeometryCore.polygon_area(poly) > MIN_AREA


static func _translate(poly: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(v + offset)
	return out


static func translate_polys(polys: Array, offset: Vector2) -> Array:
	var out: Array = []
	for p in polys:
		out.append(_translate(p, offset))
	return out


## Public single-polygon translate.
static func shift(poly: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	return _translate(poly, offset)


# ---------------------------------------------------------------------------
# Boolean helpers over Geometry2D (single-poly-in / array-out) → multi-poly
# ---------------------------------------------------------------------------

## poly minus the union of `region` polygons (successive clip). Returns remainder
## polygons (outers CCW, holes CW — use region_net_area to measure leftover).
static func poly_minus_region(poly: PackedVector2Array, region: Array) -> Array:
	var rem: Array = [poly]
	for r in region:
		if rem.is_empty():
			break
		var nxt: Array = []
		for piece in rem:
			for res in Geometry2D.clip_polygons(piece, r):
				nxt.append(res)
		rem = nxt
	return rem


## Net (signed) area of a polygon set: outers (CCW) positive, holes (CW) negative.
static func region_net_area(polys: Array) -> float:
	var total := 0.0
	for p in polys:
		var a := GeometryCore.polygon_area(p)
		total += (-a if Geometry2D.is_polygon_clockwise(p) else a)
	return total


## Every footprint polygon lies within the navigable union (leftover ≤ CONTAIN_EPS).
static func footprint_contained(footprint: Array, navigable: Array) -> bool:
	for poly in footprint:
		if not _valid(poly):
			continue
		if region_net_area(poly_minus_region(poly, navigable)) > CONTAIN_EPS:
			return false
	return true


## Any polygon of A overlaps any polygon of B with area > MIN_AREA.
static func footprints_overlap(a: Array, b: Array) -> bool:
	for pa in a:
		for pb in b:
			for res in Geometry2D.intersect_polygons(pa, pb):
				if GeometryCore.polygon_area(res) > MIN_AREA:
					return true
	return false


## Convenience alias for "footprint touches a region" (goal / trigger tests).
static func footprint_intersects(footprint: Array, region: Array) -> bool:
	return footprints_overlap(footprint, region)


## Union of many polygons into a set of disjoint outer polygons. Contiguous inputs
## merge to one; disjoint inputs stay separate (used to rejoin an occupant on unfold).
static func union_all(polys: Array) -> Array:
	var acc: Array = []
	for p in polys:
		if not _valid(p):
			continue
		acc = _merge_into(acc, p)
	return acc


static func _merge_into(acc: Array, p: PackedVector2Array) -> Array:
	var current := p
	var result: Array = []
	for a in acc:
		var merged := Geometry2D.merge_polygons(current, a)
		var outers: Array = []
		for poly in merged:
			if not Geometry2D.is_polygon_clockwise(poly):
				outers.append(poly)
		if outers.size() == 1:
			current = outers[0]  # combined with `a`
		else:
			result.append(a)     # disjoint from `current` so far
	result.append(current)
	return result


# ---------------------------------------------------------------------------
# Centroid / cell / canonicalization
# ---------------------------------------------------------------------------

## Area-weighted centroid across a footprint's polygons (cell center fallback if empty).
static func footprint_centroid(footprint: Array) -> Vector2:
	var total := 0.0
	var weighted := Vector2.ZERO
	for p in footprint:
		var a := GeometryCore.polygon_area(p)
		weighted += GeometryCore.polygon_centroid(p) * a
		total += a
	if total > GeometryCore.EPSILON:
		return weighted / total
	return Vector2.ZERO


static func cell_of_point(p: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(int(floor(p.x / cell_size)), int(floor(p.y / cell_size)))


## Canonicalize a polygon for deterministic storage: quantize vertices, force CCW
## winding, and rotate so the lexicographically-smallest vertex is first.
static func canon(poly: PackedVector2Array) -> PackedVector2Array:
	var q := PackedVector2Array()
	for v in poly:
		q.append(Vector2(snappedf(v.x, QUANT), snappedf(v.y, QUANT)))
	if q.size() < 3:
		return q
	if Geometry2D.is_polygon_clockwise(q):
		q.reverse()
	var min_i := 0
	for i in range(1, q.size()):
		if q[i].x < q[min_i].x or (q[i].x == q[min_i].x and q[i].y < q[min_i].y):
			min_i = i
	if min_i == 0:
		return q
	var out := PackedVector2Array()
	for i in range(q.size()):
		out.append(q[(min_i + i) % q.size()])
	return out


static func canon_all(polys: Array) -> Array:
	var out: Array = []
	for p in polys:
		out.append(canon(p))
	return out


# ---------------------------------------------------------------------------
# Destruction-on-intersection (DEFERRED — hook only, per the collision-engine plan)
# ---------------------------------------------------------------------------

## Future extension point: subtract a destructive region from a footprint (the part
## that intersects is destroyed; the rest survives, possibly split). Called nowhere
## yet — destruction behavior is deferred; this pins the intended geometry (footprint
## minus region) so wiring it later is a one-liner in the derivation.
static func subtract_region(footprint: Array, region: Array) -> Array:
	var out: Array = []
	for poly in footprint:
		for rem in poly_minus_region(poly, region):
			if not Geometry2D.is_polygon_clockwise(rem) and _valid(rem):
				out.append(rem)
	return out
