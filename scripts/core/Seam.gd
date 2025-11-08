class_name Seam extends Resource

## Seam
##
## Represents a fold line within a cell. Stores metadata about the fold
## that created this seam and the geometric properties of the seam line.

## Point on the seam line (LOCAL coordinates relative to GridManager)
@export var line_point: Vector2

## Normal vector of the seam line (perpendicular to fold axis)
@export var line_normal: Vector2

## Points where seam intersects the cell boundary
## Should always have exactly 2 points for a valid seam
@export var intersection_points: PackedVector2Array

## ID of the fold that created this seam
@export var fold_id: int

## Timestamp when seam was created (for ordering)
@export var timestamp: int

## Type of fold that created this seam
@export var fold_type: String  # "horizontal", "vertical", "diagonal"

## Optional metadata for future use
@export var metadata: Dictionary = {}


## Constructor
func _init(
	p_line_point: Vector2 = Vector2.ZERO,
	p_line_normal: Vector2 = Vector2.ZERO,
	p_intersection_points: PackedVector2Array = PackedVector2Array(),
	p_fold_id: int = -1,
	p_timestamp: int = 0,
	p_fold_type: String = ""
):
	line_point = p_line_point
	line_normal = p_line_normal
	intersection_points = p_intersection_points
	fold_id = p_fold_id
	timestamp = p_timestamp
	fold_type = p_fold_type


## Get the two endpoints of the seam within the cell
##
## @return: Array with 2 Vector2 points, or empty if invalid
func get_seam_endpoints() -> Array[Vector2]:
	if intersection_points.size() < 2:
		return []
	return [intersection_points[0], intersection_points[1]]


## Get the seam as a line segment (for visualization)
##
## @return: Dictionary with "start" and "end" keys
func get_line_segment() -> Dictionary:
	var endpoints = get_seam_endpoints()
	if endpoints.is_empty():
		return {"start": Vector2.ZERO, "end": Vector2.ZERO}
	return {"start": endpoints[0], "end": endpoints[1]}


## Check if this seam is parallel to another seam
##
## @param other: Another Seam to compare with
## @param epsilon: Tolerance for parallel check
## @return: true if seams are parallel
func is_parallel_to(other: Seam, epsilon: float = 0.0001) -> bool:
	# Two lines are parallel if their normals are parallel
	var dot = abs(line_normal.dot(other.line_normal))
	return abs(dot - 1.0) < epsilon


## Check if this seam intersects another seam
##
## @param other: Another Seam to check intersection with
## @return: Vector2 intersection point, or Vector2.INF if no intersection
func intersects_with(other: Seam) -> Vector2:
	# Find intersection of two line segments
	var endpoints1 = get_seam_endpoints()
	var endpoints2 = other.get_seam_endpoints()

	if endpoints1.is_empty() or endpoints2.is_empty():
		return Vector2.INF

	# Use segment_intersects_segment for proper segment-segment intersection
	var p1 = endpoints1[0]
	var p2 = endpoints1[1]
	var p3 = endpoints2[0]
	var p4 = endpoints2[1]

	# Calculate denominators for line equations
	var denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)

	# Check if lines are parallel
	if abs(denom) < GeometryCore.EPSILON:
		return Vector2.INF

	# Calculate intersection parameters
	var t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom
	var u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denom

	# Check if intersection is within both segments (0 <= t <= 1 and 0 <= u <= 1)
	if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
		# Calculate intersection point
		var intersection = Vector2(
			p1.x + t * (p2.x - p1.x),
			p1.y + t * (p2.y - p1.y)
		)
		return intersection

	# No intersection within segment bounds
	return Vector2.INF


## Create a deep copy of this seam
##
## @return: New Seam with duplicate data
func duplicate_seam() -> Seam:
	var new_seam = Seam.new()
	new_seam.line_point = line_point
	new_seam.line_normal = line_normal
	new_seam.intersection_points = intersection_points.duplicate()
	new_seam.fold_id = fold_id
	new_seam.timestamp = timestamp
	new_seam.fold_type = fold_type
	new_seam.metadata = metadata.duplicate(true)
	return new_seam


## Serialize seam to dictionary (for save/load)
##
## @return: Dictionary containing all seam data
func to_dict() -> Dictionary:
	return {
		"line_point": {"x": line_point.x, "y": line_point.y},
		"line_normal": {"x": line_normal.x, "y": line_normal.y},
		"intersection_points": _pack_to_array(intersection_points),
		"fold_id": fold_id,
		"timestamp": timestamp,
		"fold_type": fold_type,
		"metadata": metadata
	}


## Deserialize seam from dictionary
##
## @param dict: Dictionary containing seam data
static func from_dict(dict: Dictionary) -> Seam:
	var seam = Seam.new()

	if dict.has("line_point"):
		var lp = dict["line_point"]
		seam.line_point = Vector2(lp.x, lp.y)

	if dict.has("line_normal"):
		var ln = dict["line_normal"]
		seam.line_normal = Vector2(ln.x, ln.y)

	if dict.has("intersection_points"):
		seam.intersection_points = _array_to_pack(dict["intersection_points"])

	seam.fold_id = dict.get("fold_id", -1)
	seam.timestamp = dict.get("timestamp", 0)
	seam.fold_type = dict.get("fold_type", "")
	seam.metadata = dict.get("metadata", {})

	return seam


## Helper: Convert PackedVector2Array to array of dicts
static func _pack_to_array(packed: PackedVector2Array) -> Array:
	var result = []
	for v in packed:
		result.append({"x": v.x, "y": v.y})
	return result


## Helper: Convert array of dicts to PackedVector2Array
static func _array_to_pack(arr: Array) -> PackedVector2Array:
	var result = PackedVector2Array()
	for item in arr:
		result.append(Vector2(item.x, item.y))
	return result
