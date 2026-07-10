class_name CellPiece extends Resource

## CellPiece
##
## Represents a single polygon piece within a Cell (a view node). When the derived
## fold state is materialized into view Cells, each FoldedPiece becomes a CellPiece
## for rendering + collision queries. A Cell may hold several pieces (merged folds).
##
## CELL TYPES:
## -1 = null/void (legacy sentinel; the derive/replay model produces no null pieces)
##  0 = empty (walkable, default)
##  1 = wall (unwalkable)
##  2 = water (walkable)
##  3 = goal (walkable)

## Cell type constants
const CELL_TYPE_NULL: int = -1
const CELL_TYPE_EMPTY: int = 0
const CELL_TYPE_WALL: int = 1
const CELL_TYPE_WATER: int = 2
const CELL_TYPE_GOAL: int = 3

## Polygon vertices (LOCAL coordinates relative to GridManager)
@export var geometry: PackedVector2Array

## Cell type of this piece (0=empty, 1=wall, 2=water, 3=goal)
@export var cell_type: int = 0

## ID of the fold that produced this piece (-1 if original/base geometry)
@export var source_fold_id: int = -1

## Optional metadata (e.g. the base_id this fragment derives from)
@export var metadata: Dictionary = {}


## Constructor
func _init(
	p_geometry: PackedVector2Array = PackedVector2Array(),
	p_cell_type: int = 0,
	p_source_fold_id: int = -1
):
	geometry = p_geometry
	cell_type = p_cell_type
	source_fold_id = p_source_fold_id


## Get the center (centroid) of this piece
func get_center() -> Vector2:
	if geometry.is_empty():
		return Vector2.ZERO
	return GeometryCore.polygon_centroid(geometry)


## Get the area of this piece
func get_area() -> float:
	if geometry.is_empty():
		return 0.0
	return GeometryCore.polygon_area(geometry)


## Check if this piece contains a point (ray casting; edges count as inside)
func contains_point(point: Vector2) -> bool:
	if geometry.is_empty():
		return false

	var count = 0
	var n = geometry.size()
	for i in range(n):
		var j = (i + 1) % n
		var p1 = geometry[i]
		var p2 = geometry[j]
		if ((p1.y > point.y) != (p2.y >= point.y)) and \
		   (point.x <= (p2.x - p1.x) * (point.y - p1.y) / (p2.y - p1.y) + p1.x):
			count += 1
	return count % 2 == 1


## Create a deep copy of this piece
func duplicate_piece() -> CellPiece:
	var new_piece = CellPiece.new()
	new_piece.geometry = geometry.duplicate()
	new_piece.cell_type = cell_type
	new_piece.source_fold_id = source_fold_id
	new_piece.metadata = metadata.duplicate(true)
	return new_piece


## Validate this piece's geometry
func is_valid() -> bool:
	if geometry.size() < 3:
		return false
	return GeometryCore.validate_polygon(geometry)


## Get the bounding box of this piece
func get_bounding_box() -> Rect2:
	if geometry.is_empty():
		return Rect2()

	var min_x = geometry[0].x
	var max_x = geometry[0].x
	var min_y = geometry[0].y
	var max_y = geometry[0].y
	for v in geometry:
		min_x = min(min_x, v.x)
		max_x = max(max_x, v.x)
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
