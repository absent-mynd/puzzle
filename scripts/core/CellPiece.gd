class_name CellPiece extends Resource

## CellPiece
##
## Represents a single polygon piece within a Cell. When cells are split by folds,
## each resulting piece is stored as a CellPiece. Cells can contain multiple
## CellPiece objects to represent complex merged geometry.
##
## CELL TYPES:
## -1 = null/void (unwalkable, invisible, represents absence of geometry)
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

## Cell type of this piece (-1=null, 0=empty, 1=wall, 2=water, 3=goal)
@export var cell_type: int = 0

## ID of the fold that created this piece (-1 if original cell)
@export var source_fold_id: int = -1

## Seams within this piece (fold lines)
@export var seams: Array[Seam] = []

## Optional metadata for future use
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
##
## @return: Vector2 centroid position
func get_center() -> Vector2:
	if geometry.is_empty():
		return Vector2.ZERO
	return GeometryCore.polygon_centroid(geometry)


## Get the area of this piece
##
## @return: float area in square pixels
func get_area() -> float:
	if geometry.is_empty():
		return 0.0
	return GeometryCore.polygon_area(geometry)


## Add a seam to this piece
##
## @param seam: Seam to add
func add_seam(seam: Seam) -> void:
	seams.append(seam)


## Remove a seam from this piece
##
## @param seam: Seam to remove
func remove_seam(seam: Seam) -> void:
	seams.erase(seam)


## Get all seams in this piece
##
## @return: Array of Seam objects
func get_seams() -> Array[Seam]:
	return seams


## Check if this piece contains a point
##
## @param point: Point to check (LOCAL coordinates)
## @return: true if point is inside or on the boundary of the piece
func contains_point(point: Vector2) -> bool:
	if geometry.is_empty():
		return false

	# Use ray casting algorithm
	var count = 0
	var n = geometry.size()

	for i in range(n):
		var j = (i + 1) % n
		var p1 = geometry[i]
		var p2 = geometry[j]

		# Ray casting: check if horizontal ray from point crosses this edge
		# This also handles points on edges by using >= and <= comparisons
		if ((p1.y > point.y) != (p2.y >= point.y)) and \
		   (point.x <= (p2.x - p1.x) * (point.y - p1.y) / (p2.y - p1.y) + p1.x):
			count += 1

	return count % 2 == 1


## Create a deep copy of this piece
##
## @return: New CellPiece with duplicate data
func duplicate_piece() -> CellPiece:
	var new_piece = CellPiece.new()
	new_piece.geometry = geometry.duplicate()
	new_piece.cell_type = cell_type
	new_piece.source_fold_id = source_fold_id
	new_piece.metadata = metadata.duplicate(true)

	# Duplicate seams
	for seam in seams:
		new_piece.seams.append(seam.duplicate_seam())

	return new_piece


## Serialize piece to dictionary (for save/load)
##
## @return: Dictionary containing all piece data
func to_dict() -> Dictionary:
	var geometry_array = []
	for v in geometry:
		geometry_array.append({"x": v.x, "y": v.y})

	var seams_array = []
	for seam in seams:
		seams_array.append(seam.to_dict())

	return {
		"geometry": geometry_array,
		"cell_type": cell_type,
		"source_fold_id": source_fold_id,
		"seams": seams_array,
		"metadata": metadata
	}


## Deserialize piece from dictionary
##
## @param dict: Dictionary containing piece data
## @return: New CellPiece restored from dictionary
static func from_dict(dict: Dictionary) -> CellPiece:
	var piece = CellPiece.new()

	# Restore geometry
	if dict.has("geometry"):
		var geometry_array = dict["geometry"]
		var packed_geometry = PackedVector2Array()
		for v in geometry_array:
			packed_geometry.append(Vector2(v.x, v.y))
		piece.geometry = packed_geometry

	piece.cell_type = dict.get("cell_type", 0)
	piece.source_fold_id = dict.get("source_fold_id", -1)
	piece.metadata = dict.get("metadata", {})

	# Restore seams
	if dict.has("seams"):
		var seams_array = dict["seams"]
		for seam_dict in seams_array:
			piece.seams.append(Seam.from_dict(seam_dict))

	return piece


## Validate this piece's geometry
##
## @return: true if geometry is valid
func is_valid() -> bool:
	if geometry.size() < 3:
		return false
	return GeometryCore.validate_polygon(geometry)


## Get the bounding box of this piece
##
## @return: Rect2 bounding box
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
