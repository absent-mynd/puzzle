## Space-Folding Puzzle Game - FoldSystem Class
##
## Unified folding system supporting folds at any angle.
## Horizontal and vertical folds are special cases (0° and 90°).
##
## @author: Space-Folding Puzzle Team
## @version: 2.0 - CompoundCell integration
## @phase: 4 - Unified Geometric Folding

extends Node
class_name FoldSystem

## ============================================================================
## PROPERTIES
## ============================================================================

## Reference to the GridManager
var grid_manager: GridManager

## Reference to the Player (optional - for fold validation)
var player: Player = null

## History of fold operations (for undo system later)
var fold_history: Array[Dictionary] = []

## Next fold ID counter
var next_fold_id: int = 0

## Animation flag to block user input during fold animations
var is_animating: bool = false

## Animation durations
var fade_duration: float = 0.3  # Fade out duration for removed cells
var shift_duration: float = 0.5  # Shift duration for moved cells

## Seam lines for visualization
var seam_lines: Array[Line2D] = []

## Minimum fold distance (anchors can be adjacent)
const MIN_FOLD_DISTANCE = 0


## ============================================================================
## INITIALIZATION
## ============================================================================

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


## ============================================================================
## MAIN FOLD EXECUTION
## ============================================================================

## Execute a fold between two anchors
## Automatically determines fold type (horizontal, vertical, or diagonal)
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param animated: Whether to use animations (default true)
## @return: true on success, false on failure
func execute_fold(anchor1: Vector2i, anchor2: Vector2i, animated: bool = true) -> bool:
	if not grid_manager:
		push_error("FoldSystem: GridManager not initialized")
		return false

	# Block if already animating
	if is_animating:
		push_warning("FoldSystem: Cannot execute fold while animation is in progress")
		return false

	# Validate fold before execution
	var validation = validate_fold(anchor1, anchor2)
	if not validation.valid:
		push_warning("FoldSystem: Fold validation failed: " + validation.reason)
		AudioManager.play_sfx("error")
		return false

	# Validate with player position
	var player_validation = validate_fold_with_player(anchor1, anchor2)
	if not player_validation.valid:
		push_warning("FoldSystem: Player validation failed: " + player_validation.reason)
		AudioManager.play_sfx("error")
		return false

	# Set animating flag if using animations
	if animated:
		is_animating = true

	# Play fold sound effect
	AudioManager.play_sfx("fold")

	# Execute the fold (handles all angles uniformly)
	_execute_fold_internal(anchor1, anchor2, animated)

	if animated:
		is_animating = false

	return true


## Internal fold execution (unified algorithm for all angles)
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param animated: Whether to use animations
func _execute_fold_internal(anchor1: Vector2i, anchor2: Vector2i, animated: bool):
	# Generate fold ID
	var fold_id = next_fold_id
	next_fold_id += 1

	# Calculate fold line geometry
	var fold_line = _calculate_fold_line(anchor1, anchor2)

	# Classify all cells relative to fold line
	var classification = _classify_all_cells(fold_line, anchor1, anchor2)

	# Step 1: Remove cells in removed region
	_remove_cells(classification.removed_cells, animated)

	# Step 2: Shift cells (handles both split and unsplit cells)
	_shift_and_merge_cells(classification.shifted_cells, fold_line, anchor1, anchor2, fold_id, animated)

	# Step 3: Create seam line visual
	_create_seam_line(fold_line, anchor1, anchor2)

	# Step 4: Update player position if in shifted region
	if player and player.grid_position in classification.shifted_cells:
		_update_player_position(player.grid_position, fold_line, anchor1, anchor2)

	# Step 5: Record fold in history
	_record_fold(fold_id, anchor1, anchor2, classification)


## ============================================================================
## FOLD LINE CALCULATION
## ============================================================================

## Calculate fold line geometry from two anchors
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Dictionary with fold line data
func _calculate_fold_line(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	# Convert anchors to LOCAL coordinates (cell centers)
	var anchor1_local = (Vector2(anchor1) + Vector2(0.5, 0.5)) * grid_manager.cell_size
	var anchor2_local = (Vector2(anchor2) + Vector2(0.5, 0.5)) * grid_manager.cell_size

	# Midpoint between anchors (fold line passes through this)
	var midpoint = (anchor1_local + anchor2_local) / 2.0

	# Calculate fold line direction and normal
	# Fold line is perpendicular to the line connecting anchors
	var anchor_vector = anchor2_local - anchor1_local
	var line_normal = anchor_vector.normalized()
	var line_direction = Vector2(-line_normal.y, line_normal.x)  # Perpendicular

	# Calculate endpoints for seam line visualization (extended beyond grid)
	var line_length = 1000.0
	var point1 = midpoint - line_direction * line_length
	var point2 = midpoint + line_direction * line_length

	return {
		"point": midpoint,
		"normal": line_normal,
		"direction": line_direction,
		"point1": point1,
		"point2": point2,
		"anchor1_local": anchor1_local,
		"anchor2_local": anchor2_local
	}


## ============================================================================
## CELL CLASSIFICATION
## ============================================================================

## Classify all cells relative to fold line
##
## @param fold_line: Fold line data from _calculate_fold_line()
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Dictionary with cell classifications
func _classify_all_cells(fold_line: Dictionary, anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	var shifted_cells = []
	var removed_cells = []

	# Determine which side is being removed and which is shifting
	# The "right" side (positive normal direction) shifts, "left" side stays
	var anchor1_side = GeometryCore.point_side_of_line(
		fold_line.anchor1_local,
		fold_line.point,
		fold_line.normal
	)

	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]

		# Skip anchor1 (stationary side), but include anchor2 (will shift to anchor1)
		if pos == anchor1:
			continue

		# Get cell center
		var cell_center = cell.get_center()

		# Determine which side of fold line
		var side = GeometryCore.point_side_of_line(cell_center, fold_line.point, fold_line.normal)

		# Cells on same side as anchor1 stay, opposite side shifts
		if (anchor1_side < 0 and side < 0) or (anchor1_side >= 0 and side >= 0):
			# Same side as anchor1 - stationary
			pass
		elif (anchor1_side < 0 and side > 0) or (anchor1_side >= 0 and side < 0):
			# Opposite side from anchor1 - shifts
			shifted_cells.append(pos)

	# Determine removed region (cells between anchors)
	removed_cells = _determine_removed_region(anchor1, anchor2, shifted_cells)

	return {
		"shifted_cells": shifted_cells,
		"removed_cells": removed_cells,
		"stationary_cells": []  # All cells not in shifted or removed
	}


## Determine which cells are in the removed region (between fold lines)
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param shifted_cells: List of cells that will shift
## @return: Array of grid positions to remove
func _determine_removed_region(anchor1: Vector2i, anchor2: Vector2i, shifted_cells: Array) -> Array:
	var removed = []

	# Determine bounds of removed region
	var min_x = min(anchor1.x, anchor2.x)
	var max_x = max(anchor1.x, anchor2.x)
	var min_y = min(anchor1.y, anchor2.y)
	var max_y = max(anchor1.y, anchor2.y)

	# Check if horizontal or vertical fold
	if anchor1.y == anchor2.y:
		# Horizontal fold - remove ENTIRE COLUMNS between anchors (all rows)
		for x in range(min_x + 1, max_x):
			for y in range(grid_manager.grid_size.y):
				var pos = Vector2i(x, y)
				if grid_manager.cells.has(pos):
					removed.append(pos)
	elif anchor1.x == anchor2.x:
		# Vertical fold - remove ENTIRE ROWS between anchors (all columns)
		for y in range(min_y + 1, max_y):
			for x in range(grid_manager.grid_size.x):
				var pos = Vector2i(x, y)
				if grid_manager.cells.has(pos):
					removed.append(pos)
	else:
		# Diagonal fold - more complex removed region
		# For now, use simplified approach: cells in bounding box between anchors
		for x in range(min_x + 1, max_x):
			for y in range(min_y + 1, max_y):
				var pos = Vector2i(x, y)
				if grid_manager.cells.has(pos) and pos not in shifted_cells:
					removed.append(pos)

	return removed


## ============================================================================
## CELL SHIFTING AND MERGING
## ============================================================================

## Shift cells to new positions and handle merging
##
## @param cell_positions: Array of Vector2i positions to shift
## @param fold_line: Fold line data
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param fold_id: Fold ID for tracking
## @param animated: Whether to use animations
func _shift_and_merge_cells(cell_positions: Array, fold_line: Dictionary, anchor1: Vector2i, anchor2: Vector2i, fold_id: int, animated: bool):
	# Calculate shift vector
	var shift_vector = _calculate_shift_vector(anchor1, anchor2)

	# Shift each cell
	for pos in cell_positions:
		if not grid_manager.cells.has(pos):
			continue

		var cell = grid_manager.cells[pos]
		var new_pos = pos + Vector2i(shift_vector)

		# Update cell metadata
		cell.grid_position = new_pos
		cell.add_fold_to_history(fold_id)

		# Shift all fragment geometries
		for frag in cell.fragments:
			frag.translate_geometry(shift_vector * grid_manager.cell_size)

		cell.update_all_visuals()

		# Update dictionary
		grid_manager.cells.erase(pos)

		# Handle merging at new position
		if grid_manager.cells.has(new_pos):
			var existing = grid_manager.cells[new_pos]
			existing.merge_with(cell, fold_id)
			cell.queue_free()
		else:
			grid_manager.cells[new_pos] = cell


## Calculate shift vector for cells
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Shift vector in grid coordinates
func _calculate_shift_vector(anchor1: Vector2i, anchor2: Vector2i) -> Vector2:
	# Shift vector brings anchor2 to anchor1 position
	return Vector2(anchor1 - anchor2)


## ============================================================================
## CELL REMOVAL
## ============================================================================

## Remove cells from grid
##
## @param cell_positions: Array of Vector2i positions to remove
## @param animated: Whether to use fade animation
func _remove_cells(cell_positions: Array, animated: bool):
	for pos in cell_positions:
		if animated:
			# TODO: Add fade animation
			pass

		grid_manager.remove_cell(pos)


## ============================================================================
## SEAM LINE MANAGEMENT
## ============================================================================

## Create visual seam line for fold
##
## @param fold_line: Fold line data
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func _create_seam_line(fold_line: Dictionary, anchor1: Vector2i, anchor2: Vector2i):
	var seam_line = Line2D.new()
	seam_line.points = PackedVector2Array([fold_line.point1, fold_line.point2])
	seam_line.width = 3.0
	seam_line.default_color = Color.WHITE
	grid_manager.add_child(seam_line)
	seam_lines.append(seam_line)


## ============================================================================
## PLAYER POSITION UPDATES
## ============================================================================

## Update player position after fold
##
## @param old_grid_pos: Player's old grid position
## @param fold_line: Fold line data
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func _update_player_position(old_grid_pos: Vector2i, fold_line: Dictionary, anchor1: Vector2i, anchor2: Vector2i):
	if not player:
		return

	var shift_vector = _calculate_shift_vector(anchor1, anchor2)
	var new_grid_pos = old_grid_pos + Vector2i(shift_vector)

	# Update player grid position
	player.grid_position = new_grid_pos

	# Update player world position
	var new_cell = grid_manager.get_cell(new_grid_pos)
	if new_cell:
		player.position = grid_manager.to_global(new_cell.get_center())


## ============================================================================
## FOLD HISTORY
## ============================================================================

## Record fold in history
##
## @param fold_id: Fold ID
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param classification: Cell classification data
func _record_fold(fold_id: int, anchor1: Vector2i, anchor2: Vector2i, classification: Dictionary):
	fold_history.append({
		"fold_id": fold_id,
		"anchor1": anchor1,
		"anchor2": anchor2,
		"affected_cells": classification.shifted_cells,
		"removed_cells": classification.removed_cells,
		"timestamp": Time.get_ticks_msec()
	})


## ============================================================================
## VALIDATION METHODS
## ============================================================================

## Validate a fold before execution
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Dictionary with 'valid' (bool) and 'reason' (String) keys
func validate_fold(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	# Check anchors exist
	if not validate_anchors_exist(anchor1, anchor2):
		return {"valid": false, "reason": "One or both anchors are out of bounds"}

	# Check not same cell
	if not validate_not_same_cell(anchor1, anchor2):
		return {"valid": false, "reason": "Cannot fold on same cell"}

	# Check minimum distance (allow adjacent cells)
	if not validate_minimum_distance(anchor1, anchor2):
		return {"valid": false, "reason": "Anchors must be at least MIN_FOLD_DISTANCE apart"}

	return {"valid": true, "reason": ""}


## Check if both anchors exist in grid
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if both anchors are valid positions AND cells exist at those positions
func validate_anchors_exist(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	# Check if positions are within grid bounds AND cells actually exist
	return grid_manager.is_valid_position(anchor1) and grid_manager.cells.has(anchor1) and \
		   grid_manager.is_valid_position(anchor2) and grid_manager.cells.has(anchor2)


## Check if anchors are not the same cell
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if anchors are different cells
func validate_not_same_cell(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	return anchor1 != anchor2


## Check if anchors meet minimum distance requirement
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: true if distance >= MIN_FOLD_DISTANCE
func validate_minimum_distance(anchor1: Vector2i, anchor2: Vector2i) -> bool:
	var distance = max(abs(anchor2.x - anchor1.x), abs(anchor2.y - anchor1.y))
	return distance >= MIN_FOLD_DISTANCE


## Validate fold with player position
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Dictionary with 'valid' (bool) and 'reason' (String) keys
func validate_fold_with_player(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
	if not player:
		return {"valid": true, "reason": ""}

	var player_pos = player.grid_position

	# Check if player is on an anchor
	if player_pos == anchor1 or player_pos == anchor2:
		return {"valid": false, "reason": "Player cannot be on anchor cell"}

	# Calculate fold line
	var fold_line = _calculate_fold_line(anchor1, anchor2)

	# Check if player is in removed region
	var removed_cells = _determine_removed_region(anchor1, anchor2, [])
	if player_pos in removed_cells:
		return {"valid": false, "reason": "Player is in removed region"}

	# For now, allow all other cases
	# TODO: Add validation for player on cells that would be split (Phase 4)

	return {"valid": true, "reason": ""}


## ============================================================================
## UTILITY METHODS
## ============================================================================

## Get fold orientation (for backward compatibility / debugging)
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: "horizontal", "vertical", or "diagonal"
func get_fold_orientation(anchor1: Vector2i, anchor2: Vector2i) -> String:
	if anchor1.y == anchor2.y:
		return "horizontal"
	elif anchor1.x == anchor2.x:
		return "vertical"
	else:
		return "diagonal"
