## Space-Folding Puzzle Game - Cell Class
##
## Represents individual grid cells with support for polygon geometry,
## cell types, and seam tracking. This is foundational for the grid system
## and folding mechanics.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends Node2D
class_name Cell

## Properties

## Position in grid
var grid_position: Vector2i

## Polygon vertices (initially square)
var geometry: PackedVector2Array

## Cell type: 0=empty, 1=wall, 2=water, 3=goal
var cell_type: int = 0

## True if cell has been split by a fold
var is_partial: bool = false

## Track seam information for multi-seam handling
var seams: Array[Dictionary] = []

## Visual representation
var polygon_visual: Polygon2D

## Visual feedback properties (for anchor selection in Issue 6)
var outline_color: Color = Color.TRANSPARENT
var is_hovered: bool = false


## Initialize cell with grid position, world position, and size
func _init(pos: Vector2i, world_pos: Vector2, size: float):
	grid_position = pos

	# Create square geometry (4 corners in counter-clockwise order)
	geometry = PackedVector2Array([
		world_pos,                          # Top-left
		world_pos + Vector2(size, 0),       # Top-right
		world_pos + Vector2(size, size),    # Bottom-right
		world_pos + Vector2(0, size)        # Bottom-left
	])

	# Set up visual representation
	polygon_visual = Polygon2D.new()
	add_child(polygon_visual)
	update_visual()


## Get the center point of the cell
func get_center() -> Vector2:
	return GeometryCore.polygon_centroid(geometry)


## Add seam data to track fold operations
## @param seam_data: Dictionary with fold metadata (angle, intersection points, fold_id)
func add_seam(seam_data: Dictionary) -> void:
	seams.append(seam_data)


## Set cell type and update visual appearance
## @param type: Cell type (0=empty, 1=wall, 2=water, 3=goal)
func set_cell_type(type: int) -> void:
	cell_type = type
	update_visual()


## Update the visual representation
func update_visual() -> void:
	if polygon_visual:
		polygon_visual.polygon = geometry
		polygon_visual.color = get_cell_color()


## Get color based on cell type
func get_cell_color() -> Color:
	match cell_type:
		0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
		1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
		2: return Color(0.2, 0.4, 1.0)  # Water - blue
		3: return Color(0.2, 1.0, 0.2)  # Goal - green
		_: return Color(1.0, 1.0, 1.0)  # Default - white


## Check if a point is inside the cell
## @param point: World position to test
## @return: true if point is inside cell geometry
func contains_point(point: Vector2) -> bool:
	return GeometryCore.point_in_polygon(point, geometry)


## Check if cell geometry is still a perfect square
## @return: true if geometry is a perfect square
func is_square() -> bool:
	# Check vertex count
	if geometry.size() != 4:
		return false

	# Check if all sides have equal length (within epsilon)
	var side_lengths: Array[float] = []
	for i in range(4):
		var j = (i + 1) % 4
		side_lengths.append(geometry[i].distance_to(geometry[j]))

	# All sides should be equal
	var first_length = side_lengths[0]
	for length in side_lengths:
		if abs(length - first_length) > GeometryCore.EPSILON:
			return false

	# Check if all angles are 90 degrees by checking dot products
	for i in range(4):
		var prev_idx = (i - 1 + 4) % 4
		var next_idx = (i + 1) % 4

		var edge1 = (geometry[i] - geometry[prev_idx]).normalized()
		var edge2 = (geometry[next_idx] - geometry[i]).normalized()

		# Dot product should be 0 for perpendicular edges (90 degrees)
		if abs(edge1.dot(edge2)) > GeometryCore.EPSILON:
			return false

	return true


## Visual feedback methods for anchor selection (Issue 6)

## Set outline color for selected anchors
## @param color: Color to use for outline
func set_outline_color(color: Color) -> void:
	outline_color = color
	queue_redraw()


## Set hover highlight state
## @param enabled: true to show hover effect
func set_hover_highlight(enabled: bool) -> void:
	is_hovered = enabled
	queue_redraw()


## Clear all visual feedback
func clear_visual_feedback() -> void:
	outline_color = Color.TRANSPARENT
	is_hovered = false
	queue_redraw()


## Draw custom visuals (outline and hover effects)
func _draw() -> void:
	# Draw hover effect (semi-transparent yellow highlight)
	if is_hovered:
		draw_colored_polygon(geometry, Color(1.0, 1.0, 0.0, 0.3))

	# Draw outline if selected
	if outline_color.a > 0:
		# Close the polygon by adding first point at the end
		var outline_points = geometry.duplicate()
		outline_points.append(geometry[0])
		draw_polyline(outline_points, outline_color, 4.0)
