## CellFragment - Represents a single geometric piece of a cell
##
## CellFragment is a lightweight data structure (RefCounted) that stores
## the geometry and metadata for one piece of a cell. Multiple fragments
## can exist at the same grid position when cells merge.
##
## Memory: RefCounted → automatically freed when no references remain
## Coordinates: All geometry in LOCAL coordinates (relative to GridManager)

class_name CellFragment extends RefCounted

## ============================================================================
## PROPERTIES
## ============================================================================

## Polygon vertices in LOCAL coordinates (relative to GridManager)
## CRITICAL: These are NOT world coordinates. GridManager.position is added
## automatically by Godot's scene tree when rendering.
var geometry: PackedVector2Array = []

## Array of seam metadata dictionaries
## Each seam dictionary contains:
##   - fold_id: int (which fold created this seam)
##   - line_point: Vector2 (point on fold line, LOCAL coords)
##   - line_normal: Vector2 (normal vector of fold line)
##   - intersection_points: PackedVector2Array (where fold intersected this fragment)
##   - timestamp: int (Time.get_ticks_msec() when created)
var seam_data: Array[Dictionary] = []

## Fold ID that created this fragment
## -1 = original grid cell (created at initialization)
## >= 0 = created by a fold operation
var fold_created: int = -1

## Cached area for performance
## Updated whenever geometry changes
var area: float = 0.0

## Cached centroid for performance
## Updated whenever geometry changes
var centroid: Vector2 = Vector2.ZERO


## ============================================================================
## CONSTRUCTOR
## ============================================================================

## Initialize a new CellFragment
##
## @param geom: Polygon vertices in LOCAL coordinates
## @param fold_id: Fold ID that created this fragment (-1 for original cells)
func _init(geom: PackedVector2Array, fold_id: int = -1):
	geometry = geom
	fold_created = fold_id
	_recalculate_cached_values()


## ============================================================================
## GEOMETRY METHODS
## ============================================================================

## Recalculate cached area and centroid
## Call this whenever geometry changes
func _recalculate_cached_values():
	if geometry.size() < 3:
		area = 0.0
		centroid = Vector2.ZERO
		return

	area = GeometryCore.polygon_area(geometry)
	centroid = GeometryCore.polygon_centroid(geometry)


## Get the centroid of this fragment
##
## @return: Centroid in LOCAL coordinates
func get_centroid() -> Vector2:
	return centroid


## Get the area of this fragment
##
## @return: Area in square pixels
func get_area() -> float:
	return area


## Update the geometry of this fragment
## Use this when shifting/transforming fragments
##
## @param new_geometry: New polygon vertices in LOCAL coordinates
func set_geometry(new_geometry: PackedVector2Array):
	geometry = new_geometry
	_recalculate_cached_values()


## Transform this fragment's geometry by a vector
## Used when shifting cells during folds
##
## @param offset: Vector to add to all vertices (LOCAL coordinates)
func translate_geometry(offset: Vector2):
	var new_geom = PackedVector2Array()
	for vertex in geometry:
		new_geom.append(vertex + offset)
	set_geometry(new_geom)


## Check if this fragment is degenerate (invalid geometry)
##
## @return: true if geometry is invalid (< 3 vertices or zero area)
func is_degenerate() -> bool:
	return geometry.size() < 3 or abs(area) < GeometryCore.EPSILON


## ============================================================================
## SEAM MANAGEMENT
## ============================================================================

## Add seam metadata to this fragment
##
## @param seam: Dictionary with keys: fold_id, line_point, line_normal,
##              intersection_points, timestamp
func add_seam(seam: Dictionary):
	# Validate seam data
	if not seam.has("fold_id") or not seam.has("line_point") or not seam.has("line_normal"):
		push_error("CellFragment.add_seam: Invalid seam dictionary")
		return

	seam_data.append(seam)


## Get all seams affecting this fragment
##
## @return: Array of seam dictionaries
func get_seams() -> Array[Dictionary]:
	return seam_data


## Check if this fragment has a seam from a specific fold
##
## @param fold_id: Fold ID to check
## @return: true if fragment has a seam from this fold
func has_seam_from_fold(fold_id: int) -> bool:
	for seam in seam_data:
		if seam.get("fold_id", -1) == fold_id:
			return true
	return false


## ============================================================================
## DEBUG & SERIALIZATION
## ============================================================================

## Create a duplicate of this fragment
## Used when splitting or copying fragments
##
## @return: New CellFragment with same data
func duplicate_fragment() -> CellFragment:
	var new_frag = CellFragment.new(geometry.duplicate(), fold_created)

	# Deep copy seam data
	for seam in seam_data:
		new_frag.add_seam(seam.duplicate())

	return new_frag


## Get debug string representation
## GDScript convention: use _to_string() to override Object's string conversion
##
## @return: Human-readable string
func _to_string() -> String:
	return "CellFragment(vertices=%d, area=%.2f, fold=%d, seams=%d)" % [
		geometry.size(),
		area,
		fold_created,
		seam_data.size()
	]
