class_name FoldedPiece extends RefCounted

## FoldedPiece
##
## A derived fragment of a base tile in the current (folded) configuration.
## One base tile can contribute several pieces after being clipped by fold creases.
## Each piece carries its base identity plus its current-space geometry.
##
## FoldedPieces are produced fresh by FoldReplay.derive() every time; they are
## never mutated in place by gameplay and hold no persistent state.

## Which base tile this is a fragment of (stable identity for player-riding & merge).
var base_id: int = -1

## Type inherited from the base tile (0 empty, 1 wall, 2 water, 3 goal). No null.
var type: int = 0

## Polygon vertices in CURRENT-space coords (world px).
var polygon: PackedVector2Array = PackedVector2Array()

## The integer grid cell this fragment currently occupies.
var plane_pos: Vector2i = Vector2i.ZERO

## The last fold that produced/moved this fragment (-1 if untouched base geometry).
var source_fold_id: int = -1

## Reserved for future true-occlusion mechanics. Always false under current ruleset
## (between-anchor fragments are dropped, not buried).
var occluded: bool = false

## 0 = topmost surface; larger = deeper. Deterministic ordering set by FoldReplay.
var stack_order: int = 0

## Cumulative translation (px) applied to this fragment across all folds so far, i.e.
## current_polygon = base_polygon + src_offset. Lets a current-space point be mapped
## back to base space (point - src_offset) so anchors can be re-derived stably.
var src_offset: Vector2 = Vector2.ZERO


func _init(p_base_id: int = -1, p_type: int = 0, p_polygon: PackedVector2Array = PackedVector2Array(),
		p_plane_pos: Vector2i = Vector2i.ZERO, p_source_fold_id: int = -1):
	base_id = p_base_id
	type = p_type
	polygon = p_polygon
	plane_pos = p_plane_pos
	source_fold_id = p_source_fold_id


func area() -> float:
	return GeometryCore.polygon_area(polygon)


func center() -> Vector2:
	return GeometryCore.polygon_centroid(polygon)


func translated(offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in polygon:
		out.append(v + offset)
	return out
