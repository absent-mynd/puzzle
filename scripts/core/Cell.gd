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

## Position in grid
var grid_position: Vector2i

## Polygon vertices (initially square)
var geometry: PackedVector2Array

## Cell type: 0=empty, 1=wall, 2=water, 3=goal
var cell_type: int = 0

## True if cell has been split
var is_partial: bool = false

## Track seam information
var seams: Array[Dictionary] = []

## Visual representation
var polygon_visual: Polygon2D

## Visual feedback for anchor selection
var outline_color: Color = Color.TRANSPARENT
var is_hovered: bool = false


## Initialize cell with position and geometry
func _init(pos: Vector2i, world_pos: Vector2, size: float):
	grid_position = pos

	# Create square geometry (counter-clockwise winding)
	geometry = PackedVector2Array([
		world_pos,                          # Top-left
		world_pos + Vector2(size, 0),       # Top-right
		world_pos + Vector2(size, size),    # Bottom-right
		world_pos + Vector2(0, size)        # Bottom-left
	])


## Set up visual nodes when added to scene tree
func _ready():
	# Set up visual
	polygon_visual = Polygon2D.new()
	add_child(polygon_visual)
	update_visual()


## Get the center point of the cell
func get_center() -> Vector2:
	return GeometryCore.polygon_centroid(geometry)


## Add seam data to the cell
func add_seam(seam_data: Dictionary):
	seams.append(seam_data)


## Set the cell type and update visual
func set_cell_type(type: int):
	cell_type = type
	update_visual()


## Update visual representation
func update_visual():
	if polygon_visual == null:
		return

	polygon_visual.polygon = geometry
	polygon_visual.color = get_cell_color()

	# Add a subtle border
	polygon_visual.texture = null
	polygon_visual.antialiased = true


## Get the color for the current cell type
func get_cell_color() -> Color:
	match cell_type:
		0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
		1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
		2: return Color(0.2, 0.4, 1.0)  # Water - blue
		3: return Color(0.2, 1.0, 0.2)  # Goal - green
		_: return Color(1.0, 1.0, 1.0)  # Default - white


## Check if point is inside cell geometry
func contains_point(point: Vector2) -> bool:
	return GeometryCore.point_in_polygon(point, geometry)


## Check if geometry is still a perfect square
func is_square() -> bool:
	# A square has exactly 4 vertices
	if geometry.size() != 4:
		return false

	# Check if all sides are equal length
	var side_lengths: Array[float] = []
	for i in range(4):
		var j = (i + 1) % 4
		side_lengths.append(geometry[i].distance_to(geometry[j]))

	# All sides should be equal (within epsilon)
	var first_length = side_lengths[0]
	for length in side_lengths:
		if abs(length - first_length) > GeometryCore.EPSILON:
			return false

	# Check if angles are 90 degrees (dot product of adjacent sides should be ~0)
	for i in range(4):
		var prev_idx = (i - 1 + 4) % 4
		var next_idx = (i + 1) % 4

		var side1 = (geometry[i] - geometry[prev_idx]).normalized()
		var side2 = (geometry[next_idx] - geometry[i]).normalized()

		# For a 90-degree angle, dot product should be ~0
		var dot = abs(side1.dot(side2))
		if dot > GeometryCore.EPSILON:
			return false

	return true


## Set outline color for visual feedback (anchor selection)
func set_outline_color(color: Color):
	outline_color = color
	queue_redraw()


## Set hover highlight for visual feedback
func set_hover_highlight(enabled: bool):
	is_hovered = enabled
	queue_redraw()


## Clear all visual feedback
func clear_visual_feedback():
	outline_color = Color.TRANSPARENT
	is_hovered = false
	queue_redraw()


## Draw outline and hover effects
func _draw():
	# Draw hover effect (semi-transparent yellow)
	if is_hovered:
		draw_colored_polygon(geometry, Color(1, 1, 0, 0.3))

	# Draw outline if selected
	if outline_color.a > 0:
		# Close the polygon by adding first point at the end
		var closed_geometry = geometry.duplicate()
		closed_geometry.append(geometry[0])
		draw_polyline(closed_geometry, outline_color, 4.0, true)
