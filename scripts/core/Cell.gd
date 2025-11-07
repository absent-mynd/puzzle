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
var geometry_pieces: Array[CellPiece] = []  # PHASE 5: Array of geometric pieces
var cell_type: int = 0             # 0=empty, 1=wall, 2=water, 3=goal (dominant type)
var is_partial: bool = false       # True if cell has been split
var seams: Array[Dictionary] = []  # Track seam information (legacy)
var polygon_visual: Polygon2D      # Visual representation (legacy - first piece)
var border_line: Line2D            # Cell border/outline
var piece_visuals: Node2D = null   # PHASE 5: Container for multi-piece visuals
var seam_visuals: Node2D = null    # PHASE 5: Container for seam lines

## Legacy geometry accessor for backward compatibility
## Returns geometry of first piece, or empty array if no pieces
var geometry: PackedVector2Array:
	get:
		if geometry_pieces.is_empty():
			return PackedVector2Array()
		return geometry_pieces[0].geometry
	set(value):
		# When setting geometry, update first piece or create new piece
		if geometry_pieces.is_empty():
			var piece = CellPiece.new(value, cell_type, -1)
			geometry_pieces.append(piece)
		else:
			geometry_pieces[0].geometry = value

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
	var square_geometry = PackedVector2Array([
		local_pos,                          # Top-left
		local_pos + Vector2(size, 0),       # Top-right
		local_pos + Vector2(size, size),    # Bottom-right
		local_pos + Vector2(0, size)        # Bottom-left
	])

	# PHASE 5: Create initial piece with square geometry
	var initial_piece = CellPiece.new(square_geometry, cell_type, -1)
	geometry_pieces.append(initial_piece)

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
	highlight_overlay.polygon = geometry  # Uses getter which returns first piece
	highlight_overlay.color = Color.TRANSPARENT
	highlight_overlay.z_index = 1  # Above the main visual
	add_child(highlight_overlay)

	# PHASE 5: Create containers for multi-piece rendering
	piece_visuals = Node2D.new()
	piece_visuals.name = "PieceVisuals"
	piece_visuals.z_index = 0  # Below highlight
	add_child(piece_visuals)

	seam_visuals = Node2D.new()
	seam_visuals.name = "SeamVisuals"
	seam_visuals.z_index = 2  # Above everything
	add_child(seam_visuals)

	update_visual()


## Get the center point of the cell
##
## PHASE 5: Calculates weighted centroid of all pieces
##
## @return: Center point of cell geometry (weighted by area)
func get_center() -> Vector2:
	if geometry_pieces.is_empty():
		return Vector2.ZERO

	# If only one piece, use its centroid directly
	if geometry_pieces.size() == 1:
		return geometry_pieces[0].get_center()

	# Calculate weighted centroid based on piece areas
	var total_area = 0.0
	var weighted_center = Vector2.ZERO

	for piece in geometry_pieces:
		var area = piece.get_area()
		var center = piece.get_center()
		weighted_center += center * area
		total_area += area

	if total_area > GeometryCore.EPSILON:
		return weighted_center / total_area
	else:
		# Fallback: average of all centroids
		var avg = Vector2.ZERO
		for piece in geometry_pieces:
			avg += piece.get_center()
		return avg / geometry_pieces.size()


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
##
## PHASE 5: Also updates first piece's type for backward compatibility
func set_cell_type(type: int):
	cell_type = type

	# PHASE 5: Update first piece's type if it exists
	if not geometry_pieces.is_empty():
		geometry_pieces[0].cell_type = type

	update_visual()


## Update the visual representation of the cell
##
## PHASE 5: Renders all pieces with separate visuals for multi-polygon cells.
## Each piece gets its own Polygon2D with type-appropriate coloring and borders.
func update_visual():
	if geometry_pieces.is_empty():
		return

	# Clear existing piece visuals
	if piece_visuals:
		for child in piece_visuals.get_children():
			piece_visuals.remove_child(child)
			child.queue_free()

	# If single piece, use legacy rendering for backward compatibility
	if geometry_pieces.size() == 1:
		if polygon_visual:
			polygon_visual.polygon = geometry_pieces[0].geometry
			polygon_visual.color = get_cell_color_for_type(geometry_pieces[0].cell_type)
			polygon_visual.visible = true

		if border_line:
			border_line.points = geometry_pieces[0].geometry
			border_line.default_color = darken_color(polygon_visual.color, 0.6)
			border_line.visible = true

		# Update highlight overlay
		if highlight_overlay:
			highlight_overlay.polygon = geometry_pieces[0].geometry
	else:
		# Multi-piece rendering: hide legacy visuals, use piece_visuals container
		if polygon_visual:
			polygon_visual.visible = false
		if border_line:
			border_line.visible = false

		# Create separate visual for each piece
		for i in range(geometry_pieces.size()):
			var piece = geometry_pieces[i]

			# Create polygon visual for this piece
			var piece_polygon = Polygon2D.new()
			piece_polygon.polygon = piece.geometry
			piece_polygon.color = get_cell_color_for_type(piece.cell_type)
			piece_polygon.name = "Piece_%d" % i
			piece_visuals.add_child(piece_polygon)

			# Create border for this piece
			var piece_border = Line2D.new()
			piece_border.points = piece.geometry
			piece_border.closed = true
			piece_border.width = 1.5
			piece_border.default_color = darken_color(piece_polygon.color, 0.6)
			piece_border.name = "PieceBorder_%d" % i
			piece_visuals.add_child(piece_border)

		# Update highlight overlay to cover all pieces (use first piece's geometry)
		if highlight_overlay:
			highlight_overlay.polygon = geometry_pieces[0].geometry

	# Visualize seams if multiple pieces exist
	if geometry_pieces.size() > 1:
		visualize_seams()


## Get the color for the current cell type (using cell_type property)
##
## @return: Color based on cell_type
func get_cell_color() -> Color:
	return get_cell_color_for_type(cell_type)


## Get the color for a specific cell type
##
## @param type: Cell type (0=empty, 1=wall, 2=water, 3=goal)
## @return: Color for the given type
func get_cell_color_for_type(type: int) -> Color:
	match type:
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


## Visualize seams between pieces (PHASE 5)
##
## Draws seam lines to show where folds have split the cell.
## Seams are rendered as colored lines based on fold order.
func visualize_seams():
	if not seam_visuals:
		return

	# Clear existing seam visuals
	for child in seam_visuals.get_children():
		seam_visuals.remove_child(child)
		child.queue_free()

	# Collect all unique seams across all pieces
	var all_seams = get_all_seams()

	# Draw each seam as a line
	for seam in all_seams:
		var seam_line = Line2D.new()
		seam_line.points = seam.intersection_points
		seam_line.width = 2.0
		seam_line.default_color = get_seam_color(seam.fold_id)
		seam_line.name = "Seam_Fold_%d" % seam.fold_id
		seam_visuals.add_child(seam_line)


## Get a color for a seam based on fold ID
##
## @param fold_id: ID of the fold that created this seam
## @return: Color for the seam line
func get_seam_color(fold_id: int) -> Color:
	# Cycle through distinct colors for different folds
	var colors = [
		Color(1.0, 0.0, 0.0, 0.8),  # Red
		Color(0.0, 1.0, 0.0, 0.8),  # Green
		Color(0.0, 0.0, 1.0, 0.8),  # Blue
		Color(1.0, 1.0, 0.0, 0.8),  # Yellow
		Color(1.0, 0.0, 1.0, 0.8),  # Magenta
		Color(0.0, 1.0, 1.0, 0.8),  # Cyan
	]
	return colors[fold_id % colors.size()]


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


## ============================================================================
## PHASE 5: MULTI-POLYGON SUPPORT
## ============================================================================

## Add a piece to this cell
##
## @param piece: CellPiece to add
func add_piece(piece: CellPiece) -> void:
	geometry_pieces.append(piece)
	# Update dominant type after adding piece
	cell_type = get_dominant_type()
	# Update visual to show new piece
	update_visual()


## Get all unique cell types present in this cell
##
## @return: Array of unique cell types
func get_cell_types() -> Array[int]:
	var types: Array[int] = []

	for piece in geometry_pieces:
		if piece.cell_type not in types:
			types.append(piece.cell_type)

	return types


## Get the dominant cell type based on hierarchy: Goal > Wall > Water > Empty
##
## @return: Dominant cell type
func get_dominant_type() -> int:
	if geometry_pieces.is_empty():
		return 0  # Empty

	var has_goal = false
	var has_wall = false
	var has_water = false

	for piece in geometry_pieces:
		if piece.cell_type == 3:  # Goal
			has_goal = true
		elif piece.cell_type == 1:  # Wall
			has_wall = true
		elif piece.cell_type == 2:  # Water
			has_water = true

	# Priority: Goal > Wall > Water > Empty
	if has_goal:
		return 3
	elif has_wall:
		return 1
	elif has_water:
		return 2
	else:
		# Return first piece's type if all are empty/other
		return geometry_pieces[0].cell_type


## Check if cell contains a specific type
##
## @param type: Cell type to check for
## @return: true if cell contains this type
func has_cell_type(type: int) -> bool:
	for piece in geometry_pieces:
		if piece.cell_type == type:
			return true
	return false


## Get total area of all pieces
##
## @return: Total area in square pixels
func get_total_area() -> float:
	var total = 0.0
	for piece in geometry_pieces:
		total += piece.get_area()
	return total


## Get all unique seams across all pieces
##
## @return: Array of unique Seam objects
func get_all_seams() -> Array[Seam]:
	var all_seams: Array[Seam] = []
	var seam_ids = []

	for piece in geometry_pieces:
		for seam in piece.seams:
			if seam.fold_id not in seam_ids:
				all_seams.append(seam)
				seam_ids.append(seam.fold_id)

	return all_seams
