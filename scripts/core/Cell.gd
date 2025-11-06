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
var grid_position: Vector2i        # Position in grid
var geometry: PackedVector2Array   # Polygon vertices (initially square)
var cell_type: int = 0             # 0=empty, 1=wall, 2=water, 3=goal
var is_partial: bool = false       # True if cell has been split
var seams: Array[Dictionary] = []  # Track seam information
var polygon_visual: Polygon2D      # Visual representation

## Visual feedback properties (for anchor selection system - Issue #6)
var outline_color: Color = Color.TRANSPARENT
var is_hovered: bool = false


## Constructor
## Initializes cell with grid position, world position, and size
##
## @param pos: Grid position (e.g., Vector2i(0, 0) for top-left cell)
## @param world_pos: World position (top-left corner in world space)
## @param size: Size of the cell (width and height)
func _init(pos: Vector2i, world_pos: Vector2, size: float):
	grid_position = pos

	# Create square geometry (counter-clockwise winding)
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
##
## Uses GeometryCore.polygon_centroid() to calculate the geometric center
## of the cell's polygon geometry.
##
## @return: Center point of cell geometry
func get_center() -> Vector2:
	return GeometryCore.polygon_centroid(geometry)


## Add seam information to the cell
##
## Stores seam metadata for tracking how the cell has been affected by folds.
## This is used for multi-seam handling in later phases.
##
## @param seam_data: Dictionary containing seam information
##                   Expected keys: angle, intersection_points, fold_id
func add_seam(seam_data: Dictionary):
	seams.append(seam_data)
	is_partial = true


## Set the cell type and update visual appearance
##
## @param type: Cell type (0=empty, 1=wall, 2=water, 3=goal)
func set_cell_type(type: int):
	cell_type = type
	update_visual()


## Update the visual representation of the cell
##
## Refreshes the Polygon2D node with current geometry and applies
## the appropriate color based on cell_type.
func update_visual():
	if polygon_visual:
		polygon_visual.polygon = geometry
		polygon_visual.color = get_cell_color()


## Get the color for the current cell type
##
## @return: Color based on cell_type
func get_cell_color() -> Color:
	match cell_type:
		0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
		1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
		2: return Color(0.2, 0.4, 1.0)  # Water - blue
		3: return Color(0.2, 1.0, 0.2)  # Goal - green
		_: return Color(1.0, 1.0, 1.0)  # Default - white


## Check if a point is inside the cell geometry
##
## Uses polygon containment test to determine if a point is within
## the cell's boundaries. Useful for mouse interaction.
##
## @param point: Point to test in world coordinates
## @return: true if point is inside cell, false otherwise
func contains_point(point: Vector2) -> bool:
	return GeometryCore.point_in_polygon(point, geometry)


## Check if the cell is still a perfect square
##
## @return: true if geometry is a perfect square, false otherwise
func is_square() -> bool:
	# A square must have exactly 4 vertices
	if geometry.size() != 4:
		return false

	# Calculate side lengths
	var side_lengths: Array[float] = []
	for i in range(4):
		var current = geometry[i]
		var next = geometry[(i + 1) % 4]
		side_lengths.append(current.distance_to(next))

	# All sides should be equal (within epsilon tolerance)
	var first_length = side_lengths[0]
	for length in side_lengths:
		if abs(length - first_length) > GeometryCore.EPSILON:
			return false

	# Check if all angles are 90 degrees
	# This is done by checking if adjacent sides are perpendicular
	for i in range(4):
		var prev_idx = (i - 1 + 4) % 4
		var next_idx = (i + 1) % 4

		var vec1 = (geometry[i] - geometry[prev_idx]).normalized()
		var vec2 = (geometry[next_idx] - geometry[i]).normalized()

		# Dot product should be 0 for perpendicular vectors
		var dot = vec1.dot(vec2)
		if abs(dot) > GeometryCore.EPSILON:
			return false

	return true


## Set outline color for visual feedback (anchor selection)
##
## @param color: Color for the outline
func set_outline_color(color: Color):
	outline_color = color
	queue_redraw()


## Set hover highlight state
##
## @param enabled: Whether hover highlight should be shown
func set_hover_highlight(enabled: bool):
	is_hovered = enabled
	queue_redraw()


## Clear all visual feedback
func clear_visual_feedback():
	outline_color = Color.TRANSPARENT
	is_hovered = false
	queue_redraw()


## Custom draw function for visual feedback
##
## Draws outline and hover effects on top of the polygon visual.
func _draw():
	# Draw hover effect (semi-transparent yellow)
	if is_hovered:
		draw_colored_polygon(geometry, Color(1, 1, 0, 0.3))

	# Draw outline if selected
	if outline_color.a > 0:
		# Create closed polygon for outline by appending first vertex
		var outline_points = geometry.duplicate()
		outline_points.append(geometry[0])
		draw_polyline(outline_points, outline_color, 4.0)


## ============================================================================
## PHASE 4: POLYGON SPLITTING SUPPORT
## ============================================================================

## Split this cell into two cells along a line
##
## Updates this cell's geometry to one half and creates a new cell for the other half.
## Both cells are marked as partial and store seam information.
##
## @param split_result: Result from GeometryCore.split_polygon_by_line()
## @param line_point: Point on the splitting line
## @param line_normal: Normal vector of the splitting line
## @param keep_side: Which side to keep in this cell ("left" or "right")
## @return: New Cell containing the other half, or null if split failed
func apply_split(split_result: Dictionary, line_point: Vector2, line_normal: Vector2, keep_side: String) -> Cell:
	# Validate split result
	if split_result.intersections.size() == 0:
		push_error("apply_split called with no intersections")
		return null

	# Determine which geometry to keep and which to create new cell with
	var kept_geometry: PackedVector2Array
	var new_geometry: PackedVector2Array

	if keep_side == "left":
		kept_geometry = split_result.left
		new_geometry = split_result.right
	else:
		kept_geometry = split_result.right
		new_geometry = split_result.left

	# Validate geometries
	if kept_geometry.size() < 3 or new_geometry.size() < 3:
		push_error("apply_split resulted in degenerate polygon")
		return null

	# Update this cell's geometry
	geometry = kept_geometry
	is_partial = true

	# Create seam data
	var seam_data = {
		"line_point": line_point,
		"line_normal": line_normal,
		"intersection_points": split_result.intersections,
		"timestamp": Time.get_ticks_msec()
	}
	add_seam(seam_data)

	# Update visual
	update_visual()

	# Create new cell for the other half
	var new_cell = Cell.new(grid_position, Vector2.ZERO, 0)  # Temporary values
	new_cell.geometry = new_geometry
	new_cell.cell_type = cell_type
	new_cell.is_partial = true
	new_cell.add_seam(seam_data)
	new_cell.update_visual()

	return new_cell
