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
var cell_size: float = 0.0         # Size of this cell in pixels (for dot radius, previews)
var geometry_pieces: Array[CellPiece] = []  # PHASE 5: Array of geometric pieces
var cell_type: int = 0             # 0=empty, 1=wall, 2=water, 3=goal, 4=trigger (dominant type)
var tile_data: Dictionary = {}     # F3: per-instance params (trigger channel/anchors), read into BaseTile at base construction
var is_partial: bool = false       # True if cell holds >1 piece (merged by a fold)
var polygon_visual: Polygon2D      # Visual representation (legacy - first piece)
var border_line: Line2D            # Cell border/outline
var piece_visuals: Node2D = null   # PHASE 5: Container for multi-piece visuals

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
	cell_size = size

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

	# Set up highlight dot (for selection/hover feedback)
	# PHASE 8: A dot at the cell's visible center, not a translucent square overlay.
	highlight_overlay = Polygon2D.new()
	highlight_overlay.color = Color.TRANSPARENT
	highlight_overlay.z_index = 3  # Above pieces (0), highlight legacy (1), seams (2)
	add_child(highlight_overlay)

	# PHASE 5: Create containers for multi-piece rendering
	piece_visuals = Node2D.new()
	piece_visuals.name = "PieceVisuals"
	piece_visuals.z_index = 0  # Below highlight
	add_child(piece_visuals)

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


## Get the center point of the cell's VISIBLE (non-null) geometry
##
## Like get_center(), but excludes null pieces so the value never lands inside an
## invisible/void region. Used for placing the highlight dot on real geometry.
##
## @return: Area-weighted centroid of non-null pieces, or get_center() if all null/empty
func get_visible_center() -> Vector2:
	var total_area = 0.0
	var weighted_center = Vector2.ZERO

	for piece in geometry_pieces:
		if piece.cell_type == CellPiece.CELL_TYPE_NULL:
			continue
		var area = piece.get_area()
		weighted_center += piece.get_center() * area
		total_area += area

	if total_area > GeometryCore.EPSILON:
		return weighted_center / total_area

	# No visible area (all null, or degenerate) - fall back to all-pieces center
	return get_center()


## Check if this cell contains any null (void) piece
##
## @return: true if any piece has CELL_TYPE_NULL
func has_null_piece() -> bool:
	for piece in geometry_pieces:
		if piece.cell_type == CellPiece.CELL_TYPE_NULL:
			return true
	return false


## Check if the cell's overall centroid lies within a null piece
##
## Uses get_center() (the all-pieces weighted centroid) and tests whether it falls
## inside any null piece's polygon. Used by the CENTROID_IN_NULL anchor-eligibility rule.
##
## @return: true if the centroid is inside a null region
func is_centroid_in_null() -> bool:
	var centroid = get_center()
	for piece in geometry_pieces:
		if piece.cell_type == CellPiece.CELL_TYPE_NULL:
			if GeometryCore.point_in_polygon(centroid, piece.geometry):
				return true
	return false


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


## DERIVE/REPLAY: Render this cell as a pure VIEW of derived FoldedPieces.
##
## Converts the derived pieces (from FoldReplay/FoldedState) into CellPieces and
## refreshes the visual. Because the existing accessors (get_dominant_type,
## has_cell_type, get_center, contains_point) all read geometry_pieces, downstream
## consumers (Player collision, goal detection, mouse hit-testing) keep working
## unchanged. The new model has no null pieces, so void = a position with no cell.
##
## @param pieces: Array of FoldedPiece (from FoldedState.surface_pieces_at)
func apply_folded_pieces(pieces: Array) -> void:
	geometry_pieces.clear()
	for fp in pieces:
		var cp := CellPiece.new(fp.polygon, fp.type, fp.source_fold_id)
		cp.metadata = {"base_id": fp.base_id}
		geometry_pieces.append(cp)
	cell_type = get_dominant_type()
	is_partial = geometry_pieces.size() > 1
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
		var piece = geometry_pieces[0]

		# Skip rendering if piece is null type (invisible)
		if piece.cell_type == CellPiece.CELL_TYPE_NULL:
			if polygon_visual:
				polygon_visual.visible = false
			if border_line:
				border_line.visible = false
			return

		if polygon_visual:
			polygon_visual.polygon = piece.geometry
			polygon_visual.color = get_cell_color_for_type(piece.cell_type)
			polygon_visual.visible = true

		if border_line:
			border_line.points = piece.geometry
			border_line.default_color = darken_color(polygon_visual.color, 0.6)
			border_line.visible = true
	else:
		# Multi-piece rendering: hide legacy visuals, use piece_visuals container
		if polygon_visual:
			polygon_visual.visible = false
		if border_line:
			border_line.visible = false

		# Create separate visual for each piece
		for i in range(geometry_pieces.size()):
			var piece = geometry_pieces[i]

			# Skip rendering null pieces (invisible)
			if piece.cell_type == CellPiece.CELL_TYPE_NULL:
				continue

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

	# PHASE 8: Re-center the highlight dot after any geometry change
	update_highlight()


## Get the color for the current cell type (using cell_type property)
##
## @return: Color based on cell_type
func get_cell_color() -> Color:
	return get_cell_color_for_type(cell_type)


## Get the color for a specific cell type
##
## Delegates to TileTypes.color_for — the single source of truth for tile appearance.
## Kept as an instance method (same signature) so existing callers/tests don't move.
## @param type: Cell type (-1=null, 0=empty, 1=wall, 2=water, 3=goal, ...)
## @return: Color for the given type
func get_cell_color_for_type(type: int) -> Color:
	return TileTypes.color_for(type)


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
##
## PHASE 8: Tests ALL non-null pieces, not just the first. Merged cells gain pieces
## from other grid positions, so hit-testing only the first piece (via the `geometry`
## getter) missed hovers over merged-in geometry. Null pieces are invisible/unwalkable,
## so hovering empty folded-away space should not register.
func contains_point(point: Vector2) -> bool:
	for piece in geometry_pieces:
		if piece.cell_type == CellPiece.CELL_TYPE_NULL:
			continue
		if GeometryCore.point_in_polygon(point, piece.geometry):
			return true
	return false


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


## Update the highlight dot based on selection/hover state
##
## PHASE 8: The highlight is a dot at the cell's visible center rather than a
## translucent square. Selection color (1st=red, 2nd=blue) takes priority over hover.
func update_highlight():
	if not highlight_overlay:
		return

	# Priority: selection outline > hover > none
	var dot_color: Color
	if outline_color.a > 0:
		# Selected anchor - solid selection color (red for 1st, blue for 2nd)
		dot_color = Color(outline_color.r, outline_color.g, outline_color.b, 0.95)
	elif is_hovered:
		# Hovered - neutral white dot
		dot_color = Color(1, 1, 1, 0.85)
	else:
		# No highlight
		highlight_overlay.color = Color.TRANSPARENT
		return

	# Position the dot at the visible center with a radius scaled to the cell
	var radius := cell_size * 0.18 if cell_size > 0.0 else 8.0
	highlight_overlay.polygon = _make_circle_points(get_visible_center(), radius)
	highlight_overlay.color = dot_color


## Build a regular polygon approximating a circle (LOCAL coords)
##
## @param center: Circle center
## @param radius: Circle radius
## @param segments: Number of segments (more = smoother)
## @return: PackedVector2Array of circle vertices
func _make_circle_points(center: Vector2, radius: float, segments: int = 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## ============================================================================
## MULTI-POLYGON SUPPORT
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


## Get the dominant cell type based on hierarchy: Null > Goal > Wall > Water > Empty
##
## Null type is most dominant because any null piece makes the cell unwalkable
## (it represents missing/void geometry from folds with no merge partner)
##
## @return: Dominant cell type
func get_dominant_type() -> int:
	if geometry_pieces.is_empty():
		return 0  # Empty

	# F1: merge priority (null > goal > wall > water > empty) lives in TileTypes.
	var types: Array = []
	for piece in geometry_pieces:
		types.append(piece.cell_type)
	return TileTypes.dominant_type(types)


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


## Whether this cell is a COMPLETE square (fully covered), vs merged with empty space.
## Incomplete cells (a partial fragment with void alongside) are not walkable.
func is_complete() -> bool:
	return get_total_area() >= cell_size * cell_size - 1.0
