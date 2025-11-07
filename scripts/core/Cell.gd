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
var border_line: Line2D            # Cell border/outline

## Visual feedback properties (for anchor selection system - Issue #6)
var outline_color: Color = Color.TRANSPARENT
var is_hovered: bool = false
var highlight_overlay: Polygon2D  # Semi-transparent overlay for selection/hover


## Constructor
## Initializes cell with grid position, local position, and size
##
## @param pos: Grid position (e.g., Vector2i(0, 0) for top-left cell)
## @param local_pos: Local position relative to GridManager (top-left corner in local space)
## @param size: Size of the cell (width and height)
func _init(pos: Vector2i, local_pos: Vector2, size: float):
	grid_position = pos

	# Create square geometry using LOCAL coordinates (relative to GridManager)
	# Cells are children of GridManager, so geometry is in local space
	geometry = PackedVector2Array([
		local_pos,                          # Top-left
		local_pos + Vector2(size, 0),       # Top-right
		local_pos + Vector2(size, size),    # Bottom-right
		local_pos + Vector2(0, size)        # Bottom-left
	])

	# Set up visual representation
	polygon_visual = Polygon2D.new()
	add_child(polygon_visual)

	# Set up border/outline
	border_line = Line2D.new()
	border_line.width = 2.0
	border_line.closed = true  # Makes it a closed loop
	add_child(border_line)

	# Set up highlight overlay (for selection/hover feedback)
	highlight_overlay = Polygon2D.new()
	highlight_overlay.polygon = geometry
	highlight_overlay.color = Color.TRANSPARENT
	highlight_overlay.z_index = 1  # Above the main visual
	add_child(highlight_overlay)

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
## the appropriate color based on cell_type. Also updates the border
## outline to follow the cell's perimeter.
func update_visual():
	if polygon_visual:
		polygon_visual.polygon = geometry
		var cell_color = get_cell_color()
		polygon_visual.color = cell_color

		# Update border outline
		if border_line:
			border_line.points = geometry
			border_line.default_color = darken_color(cell_color, 0.6)

		# Update highlight overlay geometry to match cell
		if highlight_overlay:
			highlight_overlay.polygon = geometry


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


## Darken a color by a given factor
##
## @param color: The color to darken
## @param factor: How much to darken (0.0 = black, 1.0 = unchanged)
## @return: Darkened color
func darken_color(color: Color, factor: float = 0.7) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


## Check if a point is inside the cell geometry
##
## Uses polygon containment test to determine if a point is within
## the cell's boundaries. Useful for mouse interaction.
##
## @param point: Point to test in LOCAL coordinates (relative to GridManager)
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
## @param color: Color for the outline (Red for first anchor, Blue for second)
func set_outline_color(color: Color):
	outline_color = color
	update_highlight()


## Set hover highlight state
##
## @param enabled: Whether hover highlight should be shown
func set_hover_highlight(enabled: bool):
	is_hovered = enabled
	update_highlight()


## Clear all visual feedback
func clear_visual_feedback():
	outline_color = Color.TRANSPARENT
	is_hovered = false
	update_highlight()


## Update the highlight overlay based on selection/hover state
func update_highlight():
	if not highlight_overlay:
		return

	# Priority: selection outline > hover
	if outline_color.a > 0:
		# Selected anchor - use semi-transparent version of selection color
		highlight_overlay.color = Color(outline_color.r, outline_color.g, outline_color.b, 0.4)
		highlight_overlay.z_index = 2  # Bring to front
	elif is_hovered:
		# Hovered - use semi-transparent yellow
		highlight_overlay.color = Color(1, 1, 0, 0.3)
		highlight_overlay.z_index = 1  # Slightly above normal
	else:
		# No highlight
		highlight_overlay.color = Color.TRANSPARENT
		highlight_overlay.z_index = 0


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


## ============================================================================
## SERIALIZATION (FOR FOLD HISTORY AND UNDO SYSTEM)
## ============================================================================

## Serialize cell to dictionary (for fold history/save states)
##
## @return: Dictionary containing all cell data
func to_dict() -> Dictionary:
	var geometry_array = []
	for v in geometry:
		geometry_array.append({"x": v.x, "y": v.y})

	return {
		"grid_position": {"x": grid_position.x, "y": grid_position.y},
		"geometry": geometry_array,
		"cell_type": cell_type,
		"is_partial": is_partial,
		"seams": seams.duplicate(true)  # Deep copy
	}


## Create a cell state snapshot (excludes visual nodes)
##
## @return: Dictionary containing cell state data only
func create_state_snapshot() -> Dictionary:
	return to_dict()
