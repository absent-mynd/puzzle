## CompoundCell - Represents all cell fragments at a grid position
##
## CompoundCell is a Node2D that manages multiple CellFragment instances
## and their visual representations. It handles merging, rendering, and
## fold history tracking for undo support.
##
## Hierarchy: CompoundCell (Node2D)
##              ├── Polygon2D (fragment 0 visual)
##              ├── Polygon2D (fragment 1 visual)
##              └── ...
##
## Memory: Node2D → must be explicitly freed with queue_free()
## Coordinates: Child of GridManager → uses LOCAL coordinate space

class_name CompoundCell extends Node2D

## ============================================================================
## PROPERTIES - Core Identity
## ============================================================================

## Current logical grid position
## This is where the cell "lives" in the grid
var grid_position: Vector2i = Vector2i.ZERO

## Cell type determines color and behavior
## 0 = empty, 1 = wall, 2 = water, 3 = goal
var cell_type: int = 0

## Array of original grid positions that merged to create this cell
## Initially just [grid_position], grows during merge operations
## Used for undo and debugging
var source_positions: Array[Vector2i] = []


## ============================================================================
## PROPERTIES - Fragment Management
## ============================================================================

## All geometric fragments at this position
## These are the actual polygon pieces that make up the cell
var fragments: Array[CellFragment] = []

## Visual representation - one Polygon2D per fragment
## IMPORTANT: These are children of this CompoundCell node
## Array indices match fragments array (fragment[i] → polygon_visuals[i])
var polygon_visuals: Array[Polygon2D] = []


## ============================================================================
## PROPERTIES - Fold History (for Undo System)
## ============================================================================

## Chronological list of fold IDs that affected this cell
## Last element is the most recent fold
## Used for undo dependency checking
var fold_history: Array[int] = []


## ============================================================================
## PROPERTIES - Visual Feedback
## ============================================================================

## Outline color for anchor selection
var outline_color: Color = Color.TRANSPARENT

## Whether this cell is currently hovered by mouse
var is_hovered: bool = false

## Outline width for selection visuals
const OUTLINE_WIDTH: float = 4.0

## Hover highlight color (semi-transparent yellow)
const HOVER_COLOR: Color = Color(1, 1, 0, 0.3)


## ============================================================================
## CONSTRUCTOR
## ============================================================================

## Initialize a new CompoundCell
##
## @param pos: Grid position for this cell
## @param initial_type: Cell type (0=empty, 1=wall, 2=water, 3=goal)
func _init(pos: Vector2i, initial_type: int = 0):
	grid_position = pos
	cell_type = initial_type
	source_positions = [pos]  # Initially, just itself


## ============================================================================
## FRAGMENT MANAGEMENT
## ============================================================================

## Add a new fragment to this compound cell
## Creates a corresponding Polygon2D visual automatically
##
## @param frag: CellFragment to add
func add_fragment(frag: CellFragment):
	if frag == null:
		push_error("CompoundCell.add_fragment: null fragment")
		return

	if frag.is_degenerate():
		push_warning("CompoundCell.add_fragment: Degenerate fragment ignored")
		return

	fragments.append(frag)

	# Create visual for this fragment
	var polygon = Polygon2D.new()
	polygon.polygon = frag.geometry
	polygon.color = get_cell_color()
	add_child(polygon)
	polygon_visuals.append(polygon)


## Remove a specific fragment by index
##
## @param index: Index in fragments array
func remove_fragment(index: int):
	if index < 0 or index >= fragments.size():
		push_error("CompoundCell.remove_fragment: Invalid index %d" % index)
		return

	fragments.remove_at(index)

	if index < polygon_visuals.size():
		var poly = polygon_visuals[index]
		polygon_visuals.remove_at(index)
		poly.queue_free()


## Remove all fragments and their visuals
## Used when cell is being deleted
func clear_fragments():
	fragments.clear()

	for poly in polygon_visuals:
		poly.queue_free()
	polygon_visuals.clear()


## Get number of fragments in this cell
##
## @return: Fragment count
func get_fragment_count() -> int:
	return fragments.size()


## Check if cell has no fragments (should be deleted)
##
## @return: true if no fragments
func is_empty() -> bool:
	return fragments.is_empty()


## ============================================================================
## GEOMETRY QUERIES
## ============================================================================

## Get total area of all fragments
##
## @return: Total area in square pixels
func get_total_area() -> float:
	var total = 0.0
	for frag in fragments:
		total += frag.get_area()
	return total


## Get weighted centroid of all fragments
## Used for player positioning and visual centering
##
## @return: Centroid in LOCAL coordinates
func get_center() -> Vector2:
	if fragments.is_empty():
		# Fallback: use grid position
		var cell_size = 64.0
		if get_parent() and get_parent().has("cell_size"):
			cell_size = get_parent().cell_size
		return Vector2(grid_position) * cell_size + Vector2(cell_size/2, cell_size/2)

	# Single fragment - use its centroid
	if fragments.size() == 1:
		return fragments[0].get_centroid()

	# Multiple fragments - weighted average by area
	var weighted_pos = Vector2.ZERO
	var total_area = 0.0

	for frag in fragments:
		var frag_area = frag.get_area()
		var frag_centroid = frag.get_centroid()
		weighted_pos += frag_centroid * frag_area
		total_area += frag_area

	if total_area > GeometryCore.EPSILON:
		return weighted_pos / total_area

	# Fallback for degenerate case
	return fragments[0].get_centroid()


## Check if a point (in LOCAL coordinates) is inside any fragment
##
## @param point: Point to test in LOCAL coordinates
## @return: true if point is inside any fragment
func contains_point(point: Vector2) -> bool:
	for frag in fragments:
		if GeometryCore.point_in_polygon(point, frag.geometry):
			return true
	return false


## Get bounding rectangle of all fragments
##
## @return: Rect2 in LOCAL coordinates
func get_bounding_rect() -> Rect2:
	if fragments.is_empty():
		return Rect2()

	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF

	for frag in fragments:
		for vertex in frag.geometry:
			min_x = min(min_x, vertex.x)
			min_y = min(min_y, vertex.y)
			max_x = max(max_x, vertex.x)
			max_y = max(max_y, vertex.y)

	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


## ============================================================================
## MERGE OPERATIONS
## ============================================================================

## Merge another CompoundCell into this one
## Used when cells shift to overlap during folds
##
## CRITICAL: Caller is responsible for freeing the 'other' cell after merge!
##
## @param other: CompoundCell to merge into this one
## @param fold_id: Fold ID causing this merge
func merge_with(other: CompoundCell, fold_id: int):
	if other == null:
		push_error("CompoundCell.merge_with: null other cell")
		return

	# Merge all fragments
	for frag in other.fragments:
		add_fragment(frag.duplicate_fragment())

	# Merge source positions (union, no duplicates)
	for pos in other.source_positions:
		if pos not in source_positions:
			source_positions.append(pos)

	# Merge fold histories (union, preserving chronological order)
	var all_folds: Array[int] = []

	# Add existing folds from both cells
	for f in fold_history:
		all_folds.append(f)
	for f in other.fold_history:
		all_folds.append(f)
	all_folds.append(fold_id)  # Add the merge fold itself

	# Remove duplicates while preserving order
	var unique_folds: Array[int] = []
	for f_id in all_folds:
		if f_id not in unique_folds:
			unique_folds.append(f_id)
	fold_history = unique_folds

	# Determine merged cell type using priority rules
	cell_type = _merge_cell_types(cell_type, other.cell_type)

	# Update all visuals
	update_all_visuals()


## Determine cell type when merging
## Priority: goal > wall > water > empty
##
## @param type_a: First cell type
## @param type_b: Second cell type
## @return: Merged cell type (higher priority wins)
func _merge_cell_types(type_a: int, type_b: int) -> int:
	const PRIORITY = {3: 4, 1: 3, 2: 2, 0: 1}  # goal, wall, water, empty
	var priority_a = PRIORITY.get(type_a, 0)
	var priority_b = PRIORITY.get(type_b, 0)
	return type_a if priority_a >= priority_b else type_b


## ============================================================================
## FOLD HISTORY TRACKING (for Undo System)
## ============================================================================

## Record that this cell was affected by a fold
##
## @param fold_id: Fold ID to add to history
func add_fold_to_history(fold_id: int):
	if fold_id not in fold_history:
		fold_history.append(fold_id)


## Check if this cell was affected by a specific fold
##
## @param fold_id: Fold ID to check
## @return: true if cell has this fold in history
func is_affected_by_fold(fold_id: int) -> bool:
	return fold_id in fold_history


## Get the newest (most recent) fold that affected this cell
##
## @return: Fold ID, or -1 if no folds have affected this cell
func get_newest_fold() -> int:
	if fold_history.is_empty():
		return -1
	return fold_history[-1]


## Get all folds that affected this cell
##
## @return: Array of fold IDs in chronological order
func get_fold_history() -> Array[int]:
	return fold_history


## ============================================================================
## CELL TYPE & VISUAL UPDATES
## ============================================================================

## Set the cell type and update visuals
##
## @param new_type: New cell type (0=empty, 1=wall, 2=water, 3=goal)
func set_cell_type(new_type: int):
	cell_type = new_type
	update_all_visuals()


## Get color for current cell type
##
## @return: Color for this cell type
func get_cell_color() -> Color:
	match cell_type:
		0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
		1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
		2: return Color(0.2, 0.4, 1.0)  # Water - blue
		3: return Color(0.2, 1.0, 0.2)  # Goal - green
		_: return Color(1.0, 1.0, 1.0)  # Default - white


## Update all fragment visuals (geometry and color)
## Call this after geometry changes or cell type changes
func update_all_visuals():
	var color = get_cell_color()

	for i in range(min(fragments.size(), polygon_visuals.size())):
		polygon_visuals[i].polygon = fragments[i].geometry
		polygon_visuals[i].color = color

	queue_redraw()  # Trigger redraw for outlines/hover


## ============================================================================
## VISUAL FEEDBACK (Selection & Hover)
## ============================================================================

## Set outline color for anchor selection
##
## @param color: Color for outline (Color.TRANSPARENT to hide)
func set_outline_color(color: Color):
	outline_color = color
	queue_redraw()


## Set hover highlight state
##
## @param enabled: true to show hover effect
func set_hover_highlight(enabled: bool):
	is_hovered = enabled
	queue_redraw()


## Clear all visual feedback
func clear_visual_feedback():
	outline_color = Color.TRANSPARENT
	is_hovered = false
	queue_redraw()


## Custom draw function for outlines and hover effects
## Called automatically by Godot when queue_redraw() is called
func _draw():
	# Draw hover effect (semi-transparent yellow over all fragments)
	if is_hovered:
		for frag in fragments:
			draw_colored_polygon(frag.geometry, HOVER_COLOR)

	# Draw outline if selected
	if outline_color.a > 0:
		for frag in fragments:
			# Create closed polygon for outline
			var outline_points = frag.geometry.duplicate()
			outline_points.append(frag.geometry[0])  # Close the loop
			draw_polyline(outline_points, outline_color, OUTLINE_WIDTH)


## ============================================================================
## SPLITTING SUPPORT (for Phase 4 Diagonal Folds)
## ============================================================================

## Split a specific fragment by a fold line
## Returns new fragments for both sides of the line
##
## @param frag_index: Index of fragment to split
## @param line_point: Point on fold line (LOCAL coordinates)
## @param line_normal: Normal vector of fold line
## @param fold_id: Fold ID creating this split
## @return: Dictionary with keys "left", "right", "intersections", or empty dict on failure
func split_fragment(frag_index: int, line_point: Vector2, line_normal: Vector2, fold_id: int) -> Dictionary:
	if frag_index < 0 or frag_index >= fragments.size():
		push_error("CompoundCell.split_fragment: Invalid index %d" % frag_index)
		return {}

	var frag = fragments[frag_index]
	var split_result = GeometryCore.split_polygon_by_line(frag.geometry, line_point, line_normal)

	if split_result.intersections.size() == 0:
		push_warning("CompoundCell.split_fragment: Fragment does not intersect fold line")
		return {}

	# Validate split results
	if split_result.left.size() < 3 or split_result.right.size() < 3:
		push_warning("CompoundCell.split_fragment: Degenerate split result")
		return {}

	# Create new fragments for each side
	var left_frag = CellFragment.new(split_result.left, fold_id)
	var right_frag = CellFragment.new(split_result.right, fold_id)

	# Copy existing seam data to both fragments
	for seam in frag.seam_data:
		left_frag.add_seam(seam.duplicate())
		right_frag.add_seam(seam.duplicate())

	# Add new seam data for this split
	var new_seam = {
		"fold_id": fold_id,
		"line_point": line_point,
		"line_normal": line_normal,
		"intersection_points": split_result.intersections,
		"timestamp": Time.get_ticks_msec()
	}
	left_frag.add_seam(new_seam)
	right_frag.add_seam(new_seam)

	return {
		"left": left_frag,
		"right": right_frag,
		"intersections": split_result.intersections
	}


## Split ALL fragments in this cell by a fold line
## Returns two arrays of fragments (left and right sides)
##
## @param line_point: Point on fold line (LOCAL coordinates)
## @param line_normal: Normal vector of fold line
## @param fold_id: Fold ID creating this split
## @return: Dictionary with keys "left_fragments" (Array), "right_fragments" (Array)
func split_all_fragments(line_point: Vector2, line_normal: Vector2, fold_id: int) -> Dictionary:
	var left_fragments: Array[CellFragment] = []
	var right_fragments: Array[CellFragment] = []

	for i in range(fragments.size()):
		var split_result = split_fragment(i, line_point, line_normal, fold_id)

		if not split_result.is_empty():
			left_fragments.append(split_result.left)
			right_fragments.append(split_result.right)
		else:
			# Fragment not intersected - classify which side it's on
			var centroid = fragments[i].get_centroid()
			var side = GeometryCore.point_side_of_line(centroid, line_point, line_normal)

			if side <= 0:  # Left or on line
				left_fragments.append(fragments[i].duplicate_fragment())
			else:  # Right
				right_fragments.append(fragments[i].duplicate_fragment())

	return {
		"left_fragments": left_fragments,
		"right_fragments": right_fragments
	}


## ============================================================================
## DEBUG & UTILITIES
## ============================================================================

## Get debug string representation
## GDScript convention: use _to_string() to override Object's string conversion
##
## @return: Human-readable string
func _to_string() -> String:
	return "CompoundCell(pos=%s, type=%d, fragments=%d, sources=%d, folds=%s)" % [
		grid_position,
		cell_type,
		fragments.size(),
		source_positions.size(),
		str(fold_history)
	]


## Validate integrity of this cell
## Returns true if cell is in valid state
##
## @return: true if valid, false if integrity issues found
func validate() -> bool:
	# Check fragments match visuals
	if fragments.size() != polygon_visuals.size():
		push_error("CompoundCell.validate: Fragment/visual count mismatch")
		return false

	# Check all fragments are valid
	for frag in fragments:
		if frag.is_degenerate():
			push_error("CompoundCell.validate: Degenerate fragment found")
			return false

	# Check source_positions not empty
	if source_positions.is_empty():
		push_error("CompoundCell.validate: No source positions")
		return false

	return true
