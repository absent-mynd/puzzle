class_name BaseFrame extends RefCounted

## BaseFrame
##
## Exact mapping between BASE space (the immutable grid) and any DERIVED
## configuration (a piece list produced by replaying folds).
##
## Every piece satisfies `polygon == base_polygon + src_offset`, so a point in
## current space maps to base space by subtracting the offset of the piece
## containing it, and maps back into ANY other derived configuration by finding the
## piece with the same `base_id` that contains the base point. That round trip is
## what makes continuous transport — the player, entities, pinned anchors, door
## points — exact through arbitrary fold/unfold sequences, rather than approximate
## crease arithmetic.
##
## This is kernel-level: it depends only on the piece list, so both the world
## view and the pure derivation (trigger cascades) can use it.

## Index pieces by their plane cell for point queries.
static func index_by_pos(pieces: Array) -> Dictionary:
	var out: Dictionary = {}
	for piece in pieces:
		if not out.has(piece.plane_pos):
			out[piece.plane_pos] = []
		out[piece.plane_pos].append(piece)
	return out


## The piece containing a current-space point (strict first, then with a sub-pixel
## edge tolerance), or null if the point lies in void.
static func piece_containing(index: Dictionary, point: Vector2, cell_size: float):
	var cell := Vector2i((point / cell_size).floor())
	for tolerance in [0.0, 0.75]:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for piece in index.get(cell + Vector2i(dx, dy), []):
					if point_hits(piece.polygon, point, tolerance):
						return piece
	return null


## Convenience: the piece containing a point, indexing the list on the fly. Use
## `index_by_pos` + `piece_containing` when querying the same list repeatedly.
static func piece_at(pieces: Array, point: Vector2, cell_size: float):
	return piece_containing(index_by_pos(pieces), point, cell_size)


## Map a base-frame point back into current space via the piece of `base_id` that
## contains it. Returns Vector2, or null if that part of the base tile has no
## surviving piece (it is folded away in this configuration).
static func world_point_from_base(pieces: Array, base_id: int, bp: Vector2):
	for tolerance in [0.0, 0.75]:
		for piece in pieces:
			if piece.base_id != base_id:
				continue
			var base_poly: PackedVector2Array = CollisionCore.shift(piece.polygon, -piece.src_offset)
			if point_hits(base_poly, bp, tolerance):
				return bp + piece.src_offset
	return null


## STRICT point resolution, for warp points (doors). The base-frame point must lie
## strictly inside a piece, `margin` away from every edge. A point exactly on a cut
## — a door split down the middle — resolves nowhere: the door is dormant until its
## halves rejoin. Returns Vector2 (current space) or null.
static func resolve_base_point(pieces: Array, base_id: int, bp: Vector2, margin := 0.5):
	for piece in pieces:
		if piece.base_id != base_id:
			continue
		var base_poly: PackedVector2Array = CollisionCore.shift(piece.polygon, -piece.src_offset)
		if not Geometry2D.is_point_in_polygon(bp, base_poly):
			continue
		if min_edge_distance(base_poly, bp) > margin:
			return bp + piece.src_offset
	return null


## Transport a current-space point from one configuration to another, through base
## space. Returns null if the point is over void in `from_pieces`, or if its base
## location has no surviving piece in `to_pieces`.
static func transport(from_pieces: Array, to_pieces: Array, point: Vector2, cell_size: float):
	var src = piece_at(from_pieces, point, cell_size)
	if src == null:
		return null
	return world_point_from_base(to_pieces, src.base_id, point - src.src_offset)


## Is a point inside a polygon, or within `tolerance` of one of its edges?
static func point_hits(poly: PackedVector2Array, point: Vector2, tolerance: float) -> bool:
	if poly.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(point, poly):
		return true
	if tolerance <= 0.0:
		return false
	for i in range(poly.size()):
		var closest := Geometry2D.get_closest_point_to_segment(
			point, poly[i], poly[(i + 1) % poly.size()])
		if point.distance_to(closest) < tolerance:
			return true
	return false


## Distance from a point to the nearest edge of a polygon.
static func min_edge_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in range(poly.size()):
		var closest := Geometry2D.get_closest_point_to_segment(
			p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(closest))
	return best
