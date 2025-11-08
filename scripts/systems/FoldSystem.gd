## Space-Folding Puzzle Game - FoldSystem Class
##
## Handles axis-aligned (horizontal and vertical) folding operations.
## This is the foundation for the full geometric folding system.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0
## @phase: 3 - Simple Axis-Aligned Folding

extends Node
class_name FoldSystem

## Properties

## Debug flag to control diagnostic output during fold execution
## Set to true to see detailed fold execution logs (useful for debugging diagonal folds)
const DEBUG_FOLD_EXECUTION: bool = false

## Reference to the GridManager
var grid_manager: GridManager

## Reference to the Player (optional - for fold validation)
var player: Player = null

## History of fold operations (for undo system later)
var fold_history: Array[Dictionary] = []

## Next fold ID counter
var next_fold_id: int = 0

## Animation flag to block user input during fold animations (Issue #9)
var is_animating: bool = false

## Animation durations (Issue #9)
var fade_duration: float = 0.3  # Fade out duration for removed cells
var shift_duration: float = 0.5  # Shift duration for moved cells

## Seam lines for visualization (Issue #9)
var seam_lines: Array[Line2D] = []


## Initialize the FoldSystem with a reference to GridManager
##
## @param grid: The GridManager instance to operate on
func initialize(grid: GridManager):
	grid_manager = grid


## Set the player reference for fold validation
##
## @param p: The Player instance
func set_player(p: Player):
	player = p


## Fold Detection Methods

## Check if the fold between two anchors is horizontal
##
## A fold is horizontal if both anchors have the same Y coordinate.
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if fold is horizontal
func is_horizontal_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	return anchor1.y == anchor2.y


## Check if the fold between two anchors is vertical
##
## A fold is vertical if both anchors have the same X coordinate.
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if fold is vertical
func is_vertical_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	return anchor1.x == anchor2.x


## Get the orientation of a fold
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: "horizontal", "vertical", or "diagonal"
func get_fold_orientation(anchor1: Vector2i, anchor2: Vector2i) -> String:
	if is_horizontal_fold(anchor1, anchor2):
		return "horizontal"
	elif is_vertical_fold(anchor1, anchor2):
		return "vertical"
	else:
		return "diagonal"


## Validation Methods

## Minimum fold distance constant (anchors can be adjacent - no cell required between them)
const MIN_FOLD_DISTANCE = 0

## Validate a fold before execution
##
## Checks all validation rules and returns a result dictionary.
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Dictionary with keys {valid: bool, reason: String}
func validate_fold(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	# Check anchors exist
	if not validate_anchors_exist(anchor1, anchor2):
		return {valid = false, reason = "One or both anchors are invalid"}

	# Check not same cell
	if not validate_not_same_cell(anchor1, anchor2):
		return {valid = false, reason = "Cannot fold a cell onto itself"}

	# Phase 4: Diagonal folds are now supported!
	# We no longer reject non-axis-aligned folds

	# For axis-aligned folds, check minimum distance
	# Note: MIN_FOLD_DISTANCE = 0, so adjacent anchors are allowed
	if is_horizontal_fold(anchor1, anchor2) or is_vertical_fold(anchor1, anchor2):
		if not validate_minimum_distance(anchor1, anchor2):
			return {valid = false, reason = "Invalid anchor distance"}

	return {valid = true, reason = ""}


## Check if both anchors exist and are within grid bounds
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if both anchors are valid
func validate_anchors_exist(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	# Check if grid_manager is initialized
	if not grid_manager:
		return false

	# Check if anchors are within grid bounds
	if anchor1.x < 0 or anchor1.x >= grid_manager.grid_size.x:
		return false
	if anchor1.y < 0 or anchor1.y >= grid_manager.grid_size.y:
		return false
	if anchor2.x < 0 or anchor2.x >= grid_manager.grid_size.x:
		return false
	if anchor2.y < 0 or anchor2.y >= grid_manager.grid_size.y:
		return false

	# Check if anchor cells exist
	if not grid_manager.get_cell(anchor1):
		return false
	if not grid_manager.get_cell(anchor2):
		return false

	return true


## Check if anchors are not the same cell
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if anchors are different cells
func validate_not_same_cell(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	return anchor1 != anchor2


## Check if anchors meet minimum distance requirement
##
## Anchors must have at least MIN_FOLD_DISTANCE cells between them.
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if minimum distance is met
func validate_minimum_distance(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	var distance = get_fold_distance(anchor1, anchor2)

	# get_fold_distance returns -1 for invalid (diagonal) folds
	if distance < 0:
		return false

	return distance >= MIN_FOLD_DISTANCE


## Check if fold is axis-aligned (horizontal or vertical)
##
## For Phase 3, only axis-aligned folds are supported.
## Phase 4: This validation is now optional/informational
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if fold is horizontal or vertical
func validate_same_row_or_column(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	return is_horizontal_fold(anchor1, anchor2) or is_vertical_fold(anchor1, anchor2)


## Player Validation Methods

## Validate fold with respect to player position
##
## Checks if the fold would affect the player in any way:
## 1. Player is in the region that would be removed (between anchors)
## 2. Player's cell would be split by the fold seam (Phase 4+ only)
##
## For Phase 3, we only check rule #1 since cells aren't split.
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Dictionary with keys {valid: bool, reason: String}
func validate_fold_with_player(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	# If no player reference, validation passes
	if not player:
		return {valid = true, reason = ""}

	# Check if player is in removed region (between fold lines)
	if is_player_in_removed_region(anchor1, anchor2):
		return {valid = false, reason = "Cannot fold - player in the way"}

	# Check if player's cell would be split by the fold (Phase 4+)
	# This is critical for diagonal folds where cells can be split by cut lines
	if is_player_cell_split_by_fold(anchor1, anchor2):
		return {valid = false, reason = "Cannot fold - player in the way"}

	return {valid = true, reason = ""}


## Check if player is in the region that would be removed by the fold
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if player's position is in the removed region
func is_player_in_removed_region(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	if not player:
		return false

	var removed_cells = calculate_removed_cells(anchor1, anchor2)
	return player.grid_position in removed_cells


## Check if player's cell would be split by the fold
##
## All fold types (horizontal, vertical, diagonal) create cut lines that can split cells.
## - Horizontal folds create VERTICAL cut lines (perpendicular to the fold axis)
## - Vertical folds create HORIZONTAL cut lines (perpendicular to the fold axis)
## - Diagonal folds create DIAGONAL cut lines
##
## This checks if the player is on a cell that would be split by either cut line.
## Players on anchor positions are also blocked (cannot fold from where you stand).
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if player's cell would be split by the fold
func is_player_cell_split_by_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	if not player:
		return false

	# Get the player's current cell
	var player_cell = grid_manager.get_cell(player.grid_position)
	if not player_cell:
		return false

	# Calculate cut lines for the fold
	# NOTE: All fold types (horizontal, vertical, diagonal) use the same algorithm
	# since execute_horizontal_fold and execute_vertical_fold both call execute_diagonal_fold
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var cut_lines = calculate_cut_lines(anchor1_local, anchor2_local)

	# Check if player's cell would be split by either cut line
	if does_cell_intersect_line(player_cell, cut_lines.line1.point, cut_lines.line1.normal):
		return true
	if does_cell_intersect_line(player_cell, cut_lines.line2.point, cut_lines.line2.normal):
		return true

	return false


## Helper Methods

## Calculate which cells will be removed by a fold
##
## Returns the grid positions of all cells in the ENTIRE RECTANGULAR REGION
## between the two perpendicular lines at the anchors (not including the anchor lines themselves).
##
## For horizontal folds: Two vertical lines at anchor1.x and anchor2.x
##   - Remove ALL cells where left < x < right (across all rows)
## For vertical folds: Two horizontal lines at anchor1.y and anchor2.y
##   - Remove ALL cells where top < y < bottom (across all columns)
## For diagonal folds: Uses geometric classification to determine removed region
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Array of grid positions that will be removed
func calculate_removed_cells(anchor1: Vector2i, anchor2: Vector2i) -> Array[Vector2i]:
	var removed_cells: Array[Vector2i] = []

	if is_horizontal_fold(anchor1, anchor2):
		# Horizontal fold: perpendicular lines are VERTICAL
		# Ensure anchor1 is leftmost
		var left = min(anchor1.x, anchor2.x)
		var right = max(anchor1.x, anchor2.x)

		# Remove entire rectangular region between the two vertical lines
		for y in range(grid_manager.grid_size.y):
			for x in range(left + 1, right):
				removed_cells.append(Vector2i(x, y))

	elif is_vertical_fold(anchor1, anchor2):
		# Vertical fold: perpendicular lines are HORIZONTAL
		# Ensure anchor1 is topmost
		var top = min(anchor1.y, anchor2.y)
		var bottom = max(anchor1.y, anchor2.y)

		# Remove entire rectangular region between the two horizontal lines
		for x in range(grid_manager.grid_size.x):
			for y in range(top + 1, bottom):
				removed_cells.append(Vector2i(x, y))
	else:
		# Diagonal fold: Use geometric classification
		# Calculate cut lines (same logic as execute_diagonal_fold)
		var cell_size = grid_manager.cell_size
		var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
		var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)
		var cut_lines = calculate_cut_lines(anchor1_local, anchor2_local)

		# Check all cells to see which are in removed region
		for pos in grid_manager.cells.keys():
			var cell = grid_manager.get_cell(pos)
			if not cell:
				continue

			# Skip cells that intersect cut lines
			if does_cell_intersect_line(cell, cut_lines.line1.point, cut_lines.line1.normal):
				continue
			if does_cell_intersect_line(cell, cut_lines.line2.point, cut_lines.line2.normal):
				continue

			# Check if cell is between the two lines
			var cell_center = cell.get_center()
			var dist1 = (cell_center - cut_lines.line1.point).dot(cut_lines.line1.normal)
			var dist2 = (cell_center - cut_lines.line2.point).dot(cut_lines.line2.normal)

			# Cell is BETWEEN lines if on opposite sides of each line
			var between_lines = (dist1 > 0 and dist2 < 0) or (dist1 < 0 and dist2 > 0)

			if between_lines:
				removed_cells.append(pos)

	return removed_cells


## Get the distance between two anchors (number of cells between them)
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Number of cells between anchors
func get_fold_distance(anchor1: Vector2i, anchor2: Vector2i) -> int:
	if is_horizontal_fold(anchor1, anchor2):
		return abs(anchor2.x - anchor1.x) - 1
	elif is_vertical_fold(anchor1, anchor2):
		return abs(anchor2.y - anchor1.y) - 1
	else:
		return -1  # Invalid for diagonal folds


## Create a fold record for the history system (ENHANCED for Phase 5/6)
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param removed_cells: Array of cells that were removed
## @param orientation: Fold orientation ("horizontal", "vertical", "diagonal")
## @return: Dictionary containing fold metadata and complete grid state
func create_fold_record(anchor1: Vector2i, anchor2: Vector2i, removed_cells: Array[Vector2i], orientation: String) -> Dictionary:
	# Serialize all cells in the grid (BEFORE the fold)
	var cells_state = serialize_grid_state()

	# Store player position (if player exists)
	var player_position = Vector2i(-1, -1)
	if player:
		player_position = player.grid_position

	var record = {
		"fold_id": next_fold_id,
		"anchor1": anchor1,
		"anchor2": anchor2,
		"removed_cells": removed_cells.duplicate(),
		"orientation": orientation,
		"timestamp": Time.get_ticks_msec(),
		"cells_state": cells_state,  # Complete cell state snapshot
		"player_position": player_position,  # Player position before fold
		"fold_count": GameManager.fold_count if GameManager else 0  # Global fold counter
	}

	next_fold_id += 1
	return record


## Serialize the entire grid state (all cells)
##
## @return: Dictionary mapping grid positions to cell state dictionaries
func serialize_grid_state() -> Dictionary:
	var state = {}

	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		if cell:
			state[var_to_str(pos)] = cell.to_dict()

	return state


## Deserialize grid state from a fold record
##
## @param state: Dictionary mapping grid positions to cell state dictionaries
## @return: Dictionary of restored cell states (without visual nodes)
func deserialize_grid_state(state: Dictionary) -> Dictionary:
	var restored_cells = {}

	for pos_str in state.keys():
		var cell_data = state[pos_str]
		# Store the cell data - actual Cell node creation happens in undo system
		restored_cells[pos_str] = cell_data

	return restored_cells


## Animation Methods (Issue #9)

## Fade out cells before removal
##
## @param cell_positions: Array of grid positions to fade out
## @param duration: Duration of fade animation
func fade_out_cells(cell_positions: Array[Vector2i], duration: float) -> void:
	var tweens: Array[Tween] = []

	for pos in cell_positions:
		var cell = grid_manager.get_cell(pos)
		if cell:
			var tween = create_tween()
			tween.tween_property(cell, "modulate:a", 0.0, duration)
			tweens.append(tween)

	# Wait for all tweens to complete
	for tween in tweens:
		await tween.finished


## Shift cells to new positions with animation
##
## @param cells_to_shift: Array of dictionaries with cell, old_pos, new_pos keys
## @param duration: Duration of shift animation
func shift_cells_animated(cells_to_shift: Array[Dictionary], duration: float) -> void:
	var tweens: Array[Tween] = []

	# Start all tweens in parallel
	for data in cells_to_shift:
		var cell = data.cell
		var new_pos = data.new_pos

		# Calculate new local position (not world - cells are children of GridManager!)
		var new_local_pos = Vector2(new_pos) * grid_manager.cell_size
		var cell_size = grid_manager.cell_size

		# Calculate new geometry using local coordinates
		var new_geometry = PackedVector2Array([
			new_local_pos,
			new_local_pos + Vector2(cell_size, 0),
			new_local_pos + Vector2(cell_size, cell_size),
			new_local_pos + Vector2(0, cell_size)
		])

		# Store start and end geometry for interpolation
		var start_geometry = cell.geometry.duplicate()

		# Create tween for this cell
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)

		# Use a method callback to update geometry over time
		# Create a callable that captures the necessary variables
		var interpolate_geometry = func(t: float):
			var interpolated = PackedVector2Array()
			for j in range(start_geometry.size()):
				interpolated.append(start_geometry[j].lerp(new_geometry[j], t))
			cell.geometry = interpolated
			cell.update_visual()

		tween.tween_method(interpolate_geometry, 0.0, 1.0, duration)

		tweens.append(tween)

	# Wait for all tweens to complete (in parallel)
	for tween in tweens:
		if tween:
			await tween.finished


## Create visual seam line after fold completion
##
## Seam spans the entire grid perpendicular to the fold direction
##
## @param anchor1: First anchor position
## @param anchor2: Second anchor position
## @param orientation: Fold orientation ("horizontal" or "vertical")
## Horizontal Fold Implementation

## Execute a horizontal fold between two anchors
##
## Algorithm:
## 1. Normalize anchor order (ensure anchor1 is leftmost)
## 2. Calculate removed region (entire rectangular region between vertical lines)
## 3. Remove cells
## 4. Shift ALL cells to the right of right_anchor (across ALL rows)
## 5. Update world positions
## 6. Record fold operation
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_horizontal_fold(anchor1: Vector2i, anchor2: Vector2i):
	# Horizontal folds are just a special case of diagonal folds
	# where both anchors have the same y-coordinate
	execute_diagonal_fold(anchor1, anchor2)


## Vertical Fold Implementation

## Execute a vertical fold between two anchors
##
## Algorithm:
## 1. Normalize anchor order (ensure anchor1 is topmost)
## 2. Calculate removed region (entire rectangular region between horizontal lines)
## 3. Remove cells
## 4. Shift ALL cells below bottom_anchor (across ALL columns)
## 5. Update world positions
## 6. Record fold operation
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_vertical_fold(anchor1: Vector2i, anchor2: Vector2i):
	# Vertical folds are just a special case of diagonal folds
	# where both anchors have the same x-coordinate
	execute_diagonal_fold(anchor1, anchor2)


## Execute a horizontal fold with animation (Issue #9)
##
## Same as execute_horizontal_fold but with visual animations
## NOTE: Currently animations are not supported for diagonal folds,
## so this falls back to non-animated diagonal fold
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_horizontal_fold_animated(anchor1: Vector2i, anchor2: Vector2i) -> void:
	# TODO: Implement animated diagonal fold and use it here
	# For now, use non-animated diagonal fold
	execute_diagonal_fold(anchor1, anchor2)


## Execute a vertical fold with animation (Issue #9)
##
## Same as execute_vertical_fold but with visual animations
## NOTE: Currently animations are not supported for diagonal folds,
## so this falls back to non-animated diagonal fold
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_vertical_fold_animated(anchor1: Vector2i, anchor2: Vector2i) -> void:
	# TODO: Implement animated diagonal fold and use it here
	# For now, use non-animated diagonal fold
	execute_diagonal_fold(anchor1, anchor2)


## Main Fold Execution Method

## Execute a fold between two anchor points
##
## This is the main entry point for fold execution. It validates the fold,
## determines the fold orientation, and routes to the appropriate handler.
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param animated: Whether to use animations (default true for Issue #9)
## @return: true on success, false on failure
func execute_fold(anchor1: Vector2i, anchor2: Vector2i, animated: bool = true) -> bool:
	if not grid_manager:
		push_error("FoldSystem: GridManager not initialized")
		return false

	# Block if already animating (Issue #9)
	if is_animating:
		push_warning("FoldSystem: Cannot execute fold while animation is in progress")
		return false

	# Validate fold before execution (basic validation)
	var validation = validate_fold(anchor1, anchor2)

	if not validation.valid:
		push_warning("FoldSystem: Fold validation failed: " + validation.reason)
		# Play error sound
		AudioManager.play_sfx("error")
		return false

	# Validate with player position
	var player_validation = validate_fold_with_player(anchor1, anchor2)

	if not player_validation.valid:
		push_warning("FoldSystem: Player validation failed: " + player_validation.reason)
		# Play error sound
		AudioManager.play_sfx("error")
		return false

	var orientation = get_fold_orientation(anchor1, anchor2)

	# Set animating flag if using animations
	if animated:
		is_animating = true

	# Play fold sound effect
	AudioManager.play_sfx("fold")

	match orientation:
		"horizontal":
			if animated:
				await execute_horizontal_fold_animated(anchor1, anchor2)
			else:
				execute_horizontal_fold(anchor1, anchor2)
			if animated:
				is_animating = false
			return true
		"vertical":
			if animated:
				await execute_vertical_fold_animated(anchor1, anchor2)
			else:
				execute_vertical_fold(anchor1, anchor2)
			if animated:
				is_animating = false
			return true
		"diagonal":
			# Phase 4: Diagonal folds are now supported!
			execute_diagonal_fold(anchor1, anchor2)
			if animated:
				is_animating = false
			return true
		_:
			if animated:
				is_animating = false
			push_error("FoldSystem: Unknown fold orientation")
			return false


## Get the fold history
##
## @return: Array of fold records
func get_fold_history() -> Array[Dictionary]:
	return fold_history


## Clear fold history (useful for testing)
func clear_fold_history():
	fold_history.clear()
	next_fold_id = 0


## ============================================================================
## PHASE 4: GEOMETRIC FOLDING (DIAGONAL FOLDS)
## ============================================================================

## Calculate perpendicular cut lines for diagonal folds
##
## For diagonal folds, we create two perpendicular lines at the anchor points.
## These lines define the region to be removed.
##
## The cut lines should be PERPENDICULAR to the fold axis (the line connecting the anchors).
## For a line to be perpendicular to the fold axis, its normal should point along the fold axis.
##
## @param anchor1: First anchor position (LOCAL coordinates - relative to GridManager)
## @param anchor2: Second anchor position (LOCAL coordinates - relative to GridManager)
## @return: Dictionary with line1, line2, and fold_axis information
func calculate_cut_lines(anchor1: Vector2, anchor2: Vector2) -> Dictionary:
	# Fold axis vector (direction between anchors)
	var fold_vector = anchor2 - anchor1

	# A line with normal n consists of points where (p - point)·n = 0.
	# This constraint defines a line perpendicular to the normal n.
	# Therefore, to create cut lines perpendicular to the fold axis, we use the fold vector as the normal, ensuring the resulting lines are perpendicular to that direction.
	# So if we want a line perpendicular to fold_vector, we use fold_vector as the normal
	var fold_normal = fold_vector.normalized()

	return {
		"line1": {"point": anchor1, "normal": fold_normal},
		"line2": {"point": anchor2, "normal": fold_normal},
		"fold_axis": {"start": anchor1, "end": anchor2}
	}


## Check if a cell's geometry intersects a line
##
## A cell is only considered "split" if the line actually divides it into
## two regions (vertices on both sides of the line). Cells that just touch
## the line at a vertex or edge are not considered split.
##
## @param cell: The cell to test
## @param line_point: A point on the line
## @param line_normal: The normal vector of the line
## @return: true if cell is truly split by the line
func does_cell_intersect_line(cell: Cell, line_point: Vector2, line_normal: Vector2) -> bool:
	# Check if there are vertices on both sides of the line
	var has_positive = false
	var has_negative = false

	for vertex in cell.geometry:
		var side = GeometryCore.point_side_of_line(vertex, line_point, line_normal)
		if side > 0:
			has_positive = true
		elif side < 0:
			has_negative = true

		# If we have vertices on both sides, the cell is truly split
		if has_positive and has_negative:
			return true

	# Cell is not split - all vertices are on one side or on the line
	return false


## Classify a cell's region relative to the fold lines
##
## Determines which region a cell is in:
## - "kept_left": Cell is entirely on the left (before line1)
## - "removed": Cell is entirely in the removed region (between lines)
## - "kept_right": Cell is entirely on the right (after line2)
## - "split_line1": Cell is split by line1
## - "split_line2": Cell is split by line2
##
## @param cell: The cell to classify
## @param cut_lines: Dictionary from calculate_cut_lines()
## @return: String indicating the region
func classify_cell_region(cell: Cell, cut_lines: Dictionary) -> String:
	var centroid = cell.get_center()
	var line1 = cut_lines.line1
	var line2 = cut_lines.line2

	# Check for splits first (most important)
	if does_cell_intersect_line(cell, line1.point, line1.normal):
		return "split_line1"
	if does_cell_intersect_line(cell, line2.point, line2.normal):
		return "split_line2"

	# No splits - classify based on centroid position
	var side1 = GeometryCore.point_side_of_line(centroid, line1.point, line1.normal)
	var side2 = GeometryCore.point_side_of_line(centroid, line2.point, line2.normal)

	# Classify based on which side of the lines the centroid is on
	if side1 < 0:
		# Left of line1 (kept)
		return "kept_left"
	elif side2 > 0:
		# Right of line2 (kept)
		return "kept_right"
	else:
		# Between line1 and line2 (removed)
		return "removed"


## Create visual seam line for diagonal fold
##
## Creates a Line2D showing where the diagonal fold occurred
##
## @param cut_lines: Dictionary from calculate_cut_lines()
func create_diagonal_seam_visual(cut_lines: Dictionary) -> void:
	# For diagonal folds, we create two seam lines (at each cut)
	var seam_line1 = Line2D.new()
	seam_line1.width = 2.0
	seam_line1.default_color = Color.CYAN

	# Calculate seam endpoints spanning the grid
	var line1_start = cut_lines.line1.point - cut_lines.line1.normal * 1000
	var line1_end = cut_lines.line1.point + cut_lines.line1.normal * 1000
	seam_line1.points = PackedVector2Array([line1_start, line1_end])

	grid_manager.add_child(seam_line1)
	seam_lines.append(seam_line1)

	# Second seam line
	var seam_line2 = Line2D.new()
	seam_line2.width = 2.0
	seam_line2.default_color = Color.CYAN

	var line2_start = cut_lines.line2.point - cut_lines.line2.normal * 1000
	var line2_end = cut_lines.line2.point + cut_lines.line2.normal * 1000
	seam_line2.points = PackedVector2Array([line2_start, line2_end])

	grid_manager.add_child(seam_line2)
	seam_lines.append(seam_line2)


## Execute a diagonal fold (Phase 4)
##
## Implements the full two-cut-line algorithm with merging and shifting:
## 1. Two perpendicular cut lines at anchor positions
## 2. Cells between lines are removed
## 3. Cells on cut lines are split and parts merge
## 4. Cells past anchor2 shift toward anchor1
## 5. Overlapping cells merge together
##
## @param anchor1: First anchor grid position (stationary side)
## @param anchor2: Second anchor grid position (shifting side)
func execute_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i):
	# NORMALIZE ANCHORS to avoid negative coordinate shifts
	# Paper-folding interpretation: one cut line stays fixed, other moves toward it
	# Strategy: Choose target anchor to keep all shifted cells in positive quadrant (no negative rows/columns)
	var target_anchor: Vector2i
	var source_anchor: Vector2i

	# Check if this is axis-aligned (horizontal or vertical fold)
	var is_horizontal = anchor1.y == anchor2.y
	var is_vertical = anchor1.x == anchor2.x

	if is_horizontal:
		# Horizontal fold - always shift toward LEFT-most anchor (simple, no negatives possible)
		if anchor1.x < anchor2.x:
			target_anchor = anchor1
			source_anchor = anchor2
		else:
			target_anchor = anchor2
			source_anchor = anchor1
		if DEBUG_FOLD_EXECUTION:
			print("\n=== Axis-Aligned Horizontal Fold ===")
			print("Chose left-most anchor: target=%s, source=%s" % [target_anchor, source_anchor])
	elif is_vertical:
		# Vertical fold - always shift toward TOP-most anchor (simple, no negatives possible)
		if anchor1.y < anchor2.y:
			target_anchor = anchor1
			source_anchor = anchor2
		else:
			target_anchor = anchor2
			source_anchor = anchor1
		if DEBUG_FOLD_EXECUTION:
			print("\n=== Axis-Aligned Vertical Fold ===")
			print("Chose top-most anchor: target=%s, source=%s" % [target_anchor, source_anchor])
	else:
		# TRUE DIAGONAL FOLD - use negative-avoidance algorithm
		# Calculate both possible shift vectors
		var shift_if_anchor1_target = anchor1 - anchor2  # anchor2 side shifts toward anchor1
		var shift_if_anchor2_target = anchor2 - anchor1  # anchor1 side shifts toward anchor2

		# Get actual grid bounds from existing cells
		var min_existing_x = 0
		var max_existing_x = grid_manager.grid_size.x - 1
		var min_existing_y = 0
		var max_existing_y = grid_manager.grid_size.y - 1

		for pos in grid_manager.cells.keys():
			min_existing_x = min(min_existing_x, pos.x)
			max_existing_x = max(max_existing_x, pos.x)
			min_existing_y = min(min_existing_y, pos.y)
			max_existing_y = max(max_existing_y, pos.y)

		# For each option, calculate if x or y would go negative
		# We want to avoid BOTH negative x AND negative y
		var min_x_option1 = min_existing_x + shift_if_anchor1_target.x
		var min_y_option1 = min_existing_y + shift_if_anchor1_target.y
		var creates_negative_option1 = (min_x_option1 < 0) or (min_y_option1 < 0)

		var min_x_option2 = min_existing_x + shift_if_anchor2_target.x
		var min_y_option2 = min_existing_y + shift_if_anchor2_target.y
		var creates_negative_option2 = (min_x_option2 < 0) or (min_y_option2 < 0)

		# Also calculate maximum coordinates (for positive expansion preference)
		var max_x_option1 = max_existing_x + shift_if_anchor1_target.x
		var max_y_option1 = max_existing_y + shift_if_anchor1_target.y
		var max_x_option2 = max_existing_x + shift_if_anchor2_target.x
		var max_y_option2 = max_existing_y + shift_if_anchor2_target.y

		# DEBUG: Print normalization decision
		if DEBUG_FOLD_EXECUTION:
			print("\n=== Diagonal Fold Normalization ===")
			print("anchor1=%s, anchor2=%s" % [anchor1, anchor2])
			print("shift_if_anchor1_target=%s, shift_if_anchor2_target=%s" % [shift_if_anchor1_target, shift_if_anchor2_target])
			print("Grid bounds: x=[%d,%d], y=[%d,%d]" % [min_existing_x, max_existing_x, min_existing_y, max_existing_y])
			print("Option1: min_x=%d, min_y=%d, creates_negative=%s" % [min_x_option1, min_y_option1, creates_negative_option1])
			print("Option2: min_x=%d, min_y=%d, creates_negative=%s" % [min_x_option2, min_y_option2, creates_negative_option2])
			print("Option1: max_x=%d, max_y=%d" % [max_x_option1, max_y_option1])
			print("Option2: max_x=%d, max_y=%d" % [max_x_option2, max_y_option2])

		# Choose the option that avoids negative coordinates
		# If only one avoids negatives, choose it
		# If both avoid or both create negatives, prefer positive expansion over negative
		if not creates_negative_option1 and creates_negative_option2:
			# Option 1 avoids negatives
			target_anchor = anchor1
			source_anchor = anchor2
			if DEBUG_FOLD_EXECUTION:
				print("→ Chose anchor1 as target (avoids negatives)")
		elif not creates_negative_option2 and creates_negative_option1:
			# Option 2 avoids negatives
			target_anchor = anchor2
			source_anchor = anchor1
			if DEBUG_FOLD_EXECUTION:
				print("→ Chose anchor2 as target (avoids negatives)")
		else:
			# Both create negatives OR both avoid negatives
			# Prefer positive expansion (larger max) over negative expansion (negative min)
			# Calculate "badness" score: negative values are bad, positive expansion is ok
			var badness1 = 0
			if min_x_option1 < 0:
				badness1 += abs(min_x_option1)
			if min_y_option1 < 0:
				badness1 += abs(min_y_option1)

			var badness2 = 0
			if min_x_option2 < 0:
				badness2 += abs(min_x_option2)
			if min_y_option2 < 0:
				badness2 += abs(min_y_option2)

			if badness1 < badness2:
				target_anchor = anchor1
				source_anchor = anchor2
				if DEBUG_FOLD_EXECUTION:
					print("→ Chose anchor1 (less negative expansion: %d vs %d)" % [badness1, badness2])
			elif badness2 < badness1:
				target_anchor = anchor2
				source_anchor = anchor1
				if DEBUG_FOLD_EXECUTION:
					print("→ Chose anchor2 (less negative expansion: %d vs %d)" % [badness2, badness1])
			else:
				# Equal badness - prefer positive expansion
				var expansion1 = max(max_x_option1, max_y_option1)
				var expansion2 = max(max_x_option2, max_y_option2)
				if expansion1 <= expansion2:
					target_anchor = anchor1
					source_anchor = anchor2
				else:
					target_anchor = anchor2
					source_anchor = anchor1
				if DEBUG_FOLD_EXECUTION:
					print("→ Equal badness, chose based on expansion")

	# Convert to LOCAL coordinates (cell centers)
	var cell_size = grid_manager.cell_size
	var target_local = Vector2(target_anchor) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var source_local = Vector2(source_anchor) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	# 1. Calculate cut lines (perpendicular to fold axis)
	var cut_lines = calculate_cut_lines(target_local, source_local)

	# 2. Classify all cells relative to cut lines
	# Now classification always treats target_anchor as stationary side
	var classification = _classify_cells_for_diagonal_fold(target_anchor, source_anchor, cut_lines)

	# DEBUG: Print classification results
	if DEBUG_FOLD_EXECUTION:
		print("\n=== Diagonal Fold Classification ===")
		print("anchor1: %s, anchor2: %s (original parameters)" % [anchor1, anchor2])
		print("target_anchor: %s, source_anchor: %s (normalized)" % [target_anchor, source_anchor])
		
		var stationary_positions = []
		for c in classification.stationary:
			stationary_positions.append(c.grid_position)
		print("stationary: %d cells at %s" % [classification.stationary.size(), stationary_positions])
		
		var line1_positions = []
		for c in classification.on_line1:
			line1_positions.append(c.grid_position)
		print("on_line1: %d cells at %s" % [classification.on_line1.size(), line1_positions])
		
		var removed_pos_debug = []
		for c in classification.removed:
			removed_pos_debug.append(c.grid_position)
		print("removed: %d cells at %s" % [classification.removed.size(), removed_pos_debug])
		
		var line2_positions = []
		for c in classification.on_line2:
			line2_positions.append(c.grid_position)
		print("on_line2: %d cells at %s" % [classification.on_line2.size(), line2_positions])
		
		var shift_positions = []
		for c in classification.to_shift:
			shift_positions.append(c.grid_position)
		print("to_shift: %d cells at %s" % [classification.to_shift.size(), shift_positions])

	# 3. Split cells on cut lines and store split parts
	var split_parts_line1 = _process_split_cells_on_line1(classification.on_line1, cut_lines, target_anchor, source_anchor)
	var split_parts_line2 = _process_split_cells_on_line2(classification.on_line2, cut_lines, target_anchor, source_anchor)

	# 4. Remove cells in removed region
	_remove_cells_in_region(classification.removed)

	# 5. Shift cells from source side toward target
	var shift_vector = target_anchor - source_anchor  # Grid units

	# IMPORTANT: Build list of shifting positions BEFORE shifting cells
	# (cells will have their grid_position updated during shift)
	var shifting_positions: Array[Vector2i] = []
	for cell in classification.to_shift:
		shifting_positions.append(cell.grid_position)

	_shift_cells_with_merge(classification.to_shift, shift_vector, split_parts_line2)

	# 6. Cells on line1 are already split in-place at anchor1
	# The merge happens automatically in _shift_cells_with_merge when cells shift to anchor1
	# No additional merge step needed for line1 cells

	# 7. Create seam visualization
	create_diagonal_seam_visual(cut_lines)

	# 8. Update player position if affected
	if player:
		# Check if player is on a shifting cell (using positions from BEFORE shift)
		if player.grid_position in shifting_positions:
			player.grid_position += Vector2i(shift_vector)
			var new_cell = grid_manager.get_cell(player.grid_position)
			if new_cell:
				player.global_position = grid_manager.to_global(new_cell.get_center())

	# 9. Record fold operation
	var removed_positions: Array[Vector2i] = []
	for cell in classification.removed:
		removed_positions.append(cell.grid_position)

	# Determine orientation for fold record (use specific orientation for axis-aligned folds)
	var orientation = "diagonal"
	if is_horizontal:
		orientation = "horizontal"
	elif is_vertical:
		orientation = "vertical"

	var fold_record = create_fold_record(anchor1, anchor2, removed_positions, orientation)
	fold_history.append(fold_record)

	# 10. Clean up any freed cell references from the dictionary
	grid_manager.cleanup_freed_cells()

## Classify all cells for diagonal fold algorithm
##
## Returns cells organized by their role in the fold:
## - stationary: Cells on anchor1 side that don't move
## - on_line1: Cells intersecting line1 (at anchor1)
## - removed: Cells strictly between the two lines
## - on_line2: Cells intersecting line2 (at anchor2)
## - to_shift: Cells past line2 (away from line1) that need to shift
##
## @param anchor1: First anchor (stationary side)
## @param anchor2: Second anchor (shifting side)
## @param cut_lines: Cut line data from calculate_cut_lines()
## @return: Dictionary with cell arrays
func _classify_cells_for_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i, cut_lines: Dictionary) -> Dictionary:
	var stationary = []
	var on_line1 = []
	var removed = []
	var on_line2 = []
	var to_shift = []

	for pos in grid_manager.cells.keys():
		var cell = grid_manager.get_cell(pos)
		if not cell:
			continue

		# Don't skip any cells - even anchors need to be classified and split
		# Check if cell intersects cut lines
		var intersects_line1 = does_cell_intersect_line(cell, cut_lines.line1.point, cut_lines.line1.normal)
		var intersects_line2 = does_cell_intersect_line(cell, cut_lines.line2.point, cut_lines.line2.normal)

		if intersects_line1:
			on_line1.append(cell)
		elif intersects_line2:
			on_line2.append(cell)
		else:
			# Cell doesn't intersect - classify by which region it's in
			var cell_center = cell.get_center()

			# Calculate signed distance from each line
			var dist1 = (cell_center - cut_lines.line1.point).dot(cut_lines.line1.normal)
			var dist2 = (cell_center - cut_lines.line2.point).dot(cut_lines.line2.normal)

			# Cell is BETWEEN lines if it's on opposite sides of each line
			# (one positive, one negative distance)
			var between_lines = (dist1 > 0 and dist2 < 0) or (dist1 < 0 and dist2 > 0)

			if between_lines:
				# Cell is in the removed region
				removed.append(cell)
			else:
				# Cell is on one side or the other
				# Determine which side of line1 has anchor2
				var anchor2_center = Vector2(anchor2) * grid_manager.cell_size + Vector2(grid_manager.cell_size / 2, grid_manager.cell_size / 2)
				var anchor2_dist = (anchor2_center - cut_lines.line1.point).dot(cut_lines.line1.normal)

				# If cell is on same side as anchor2, it needs to shift
				# Same side means same sign of distance
				if (dist1 > 0 and anchor2_dist > 0) or (dist1 < 0 and anchor2_dist < 0):
					to_shift.append(cell)
				else:
					# Cell is on opposite side from anchor2 (anchor1 side) - stationary
					stationary.append(cell)

	return {
		"stationary": stationary,
		"on_line1": on_line1,
		"removed": removed,
		"on_line2": on_line2,
		"to_shift": to_shift
	}


## Process cells on line1 (at anchor1) - split and keep anchor1 side
##
## @param cells: Array of cells intersecting line1
## @param cut_lines: Cut line data
## @param anchor1: First anchor position
## @param anchor2: Second anchor position
## @return: Array of split cell geometries to merge at anchor1
func _process_split_cells_on_line1(cells: Array, cut_lines: Dictionary, anchor1: Vector2i, anchor2: Vector2i) -> Array:
	var split_parts = []

	# Determine which side of line1 to keep (away from anchor2)
	var anchor2_local = Vector2(anchor2) * grid_manager.cell_size + Vector2(grid_manager.cell_size / 2, grid_manager.cell_size / 2)
	var anchor2_side = GeometryCore.point_side_of_line(anchor2_local, cut_lines.line1.point, cut_lines.line1.normal)
	var keep_side = "right" if anchor2_side < 0 else "left"

	for cell in cells:
		var split_result = GeometryCore.split_polygon_by_line(
			cell.geometry, cut_lines.line1.point, cut_lines.line1.normal
		)

		if split_result.intersections.size() > 0:
			# Update cell geometry to kept side
			# NOTE: GeometryCore naming is inverted: "left" = positive side, "right" = negative side
			# So we swap the assignment to get the correct polygon half
			if keep_side == "left":
				cell.geometry = split_result.right  # SWAPPED: use right for left
			else:
				cell.geometry = split_result.left   # SWAPPED: use left for right

			cell.is_partial = true
			cell.update_visual()

			# Store the kept part for potential merging
			split_parts.append({
				"cell": cell,
				"geometry": cell.geometry,
				"position": anchor1
			})

	return split_parts


## Process cells on line2 (at anchor2) - split and prepare for shifting
##
## @param cells: Array of cells intersecting line2
## @param cut_lines: Cut line data
## @param anchor1: First anchor position
## @param anchor2: Second anchor position
## @return: Array of split cell data to shift and merge
func _process_split_cells_on_line2(cells: Array, cut_lines: Dictionary, anchor1: Vector2i, anchor2: Vector2i) -> Array:
	var split_parts = []

	# Determine which side of line2 to keep (away from anchor1, toward shifting direction)
	var anchor1_local = Vector2(anchor1) * grid_manager.cell_size + Vector2(grid_manager.cell_size / 2, grid_manager.cell_size / 2)
	var anchor1_side = GeometryCore.point_side_of_line(anchor1_local, cut_lines.line2.point, cut_lines.line2.normal)
	var keep_side = "right" if anchor1_side < 0 else "left"

	for cell in cells:
		var split_result = GeometryCore.split_polygon_by_line(
			cell.geometry, cut_lines.line2.point, cut_lines.line2.normal
		)

		if split_result.intersections.size() > 0:
			# Update cell geometry to kept side
			# NOTE: GeometryCore naming is inverted: "left" = positive side, "right" = negative side
			# So we swap the assignment to get the correct polygon half
			if keep_side == "left":
				cell.geometry = split_result.right  # SWAPPED: use right for left
			else:
				cell.geometry = split_result.left   # SWAPPED: use left for right

			cell.is_partial = true
			cell.update_visual()

			# This cell will shift - store it
			split_parts.append(cell)

	return split_parts


## Remove cells in the removed region
##
## @param cells: Array of cells to remove
func _remove_cells_in_region(cells: Array):
	for cell in cells:
		var pos = cell.grid_position
		grid_manager.cells.erase(pos)
		if cell.get_parent():
			cell.get_parent().remove_child(cell)
		cell.queue_free()


## Shift cells and handle merging when they overlap
##
## @param cells_to_shift: Array of cells that need to shift
## @param shift_vector: Vector2i shift amount in grid coordinates
## @param additional_cells: Additional cells from line2 splits to include
func _shift_cells_with_merge(cells_to_shift: Array, shift_vector: Vector2i, additional_cells: Array):
	# Combine regular cells with split cells from line2
	var all_shifting = cells_to_shift + additional_cells

	# TWO-PASS APPROACH to avoid false collisions:
	# Pass 1: Remove all cells from old positions and update their properties
	# Pass 2: Place all cells at new positions (checking for REAL collisions)

	# PASS 1: Remove from old positions and update cell data
	for cell in all_shifting:
		var old_pos = cell.grid_position
		var new_pos = old_pos + shift_vector

		# Remove from old position
		grid_manager.cells.erase(old_pos)

		# Update cell position
		cell.grid_position = new_pos

		# Translate geometry for ALL pieces (Phase 5 multi-polygon support)
		var shift_pixels = Vector2(shift_vector) * grid_manager.cell_size
		for piece in cell.geometry_pieces:
			var new_geometry = PackedVector2Array()
			for vertex in piece.geometry:
				new_geometry.append(vertex + shift_pixels)
			piece.geometry = new_geometry
		cell.update_visual()

	# PASS 2: Place cells at new positions and handle REAL merges
	for cell in all_shifting:
		var new_pos = cell.grid_position

		# Check if new position is already occupied (by a cell NOT in shift queue)
		var existing = grid_manager.get_cell(new_pos)
		if existing:
			# Merge with existing cell (this is a REAL collision, not a false one)
			_merge_cells_multi_polygon(existing, cell, new_pos)
		else:
			# Place cell at new position
			grid_manager.cells[new_pos] = cell


## Merge split parts from line1 with any cells at anchor1
##
## @param split_parts: Array of split cell data from line1
## @param anchor1: Position where merging occurs
func _merge_split_parts_at_anchor1(split_parts: Array, anchor1: Vector2i):
	# Check if there are shifted cells at anchor1 that need merging
	var cell_at_anchor1 = grid_manager.get_cell(anchor1)

	if cell_at_anchor1 and split_parts.size() > 0:
		# Merge all split parts into the cell at anchor1
		for part_data in split_parts:
			var part_cell = part_data.cell
			if part_cell != cell_at_anchor1:
				# Simple merge: mark both as partial with seams
				cell_at_anchor1.is_partial = true
				# In a full implementation, would combine geometries
				# For now, keep the existing cell
				part_cell.queue_free()


## PHASE 5: Multi-polygon cell merge
##
## Merges two cells by transferring all pieces from incoming to existing.
## This maintains visual distinction between different cell types instead
## of performing geometric union.
##
## @param existing: Cell already at the position
## @param incoming: Cell being moved to this position
## @param pos: Grid position where merge occurs
func _merge_cells_multi_polygon(existing: Cell, incoming: Cell, pos: Vector2i):
	# Mark both as affected by merge
	existing.is_partial = true
	incoming.is_partial = true

	# Transfer all pieces from incoming to existing
	for piece in incoming.geometry_pieces:
		var piece_copy = piece.duplicate_piece()
		existing.add_piece(piece_copy)

	# Update dominant cell type based on new composition
	# (add_piece already does this, but be explicit)
	existing.cell_type = existing.get_dominant_type()

	# Update visual to show all pieces
	existing.update_visual()

	# Free the incoming cell (its pieces are now in existing)
	incoming.queue_free()

	# Log merge for debugging (if enabled)
	if DEBUG_FOLD_EXECUTION:
		print("  Merged cells at %s: now has %d pieces with types %s" % [
			pos,
			existing.geometry_pieces.size(),
			existing.get_cell_types()
		])
