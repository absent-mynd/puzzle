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

## Seam-to-fold mapping for undo system (Phase 6)
## Maps Line2D instance IDs to fold IDs
var seam_to_fold_map: Dictionary = {}


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
## PHASE 6: SEAM-TO-FOLD MAPPING (TASK 1)
## ============================================================================

## Get the fold record for a given seam Line2D
##
## @param seam_line: The Line2D seam to look up
## @return: Dictionary containing fold record, or null if not found
func get_fold_for_seam(seam_line: Line2D) -> Dictionary:
	if not seam_line:
		return {}

	var seam_id = seam_line.get_instance_id()
	var fold_id = seam_to_fold_map.get(seam_id)

	if fold_id == null:
		return {}

	# Find fold record with matching ID
	for record in fold_history:
		if record["fold_id"] == fold_id:
			return record

	return {}


## Remove a seam from the mapping
##
## @param seam_line: The Line2D seam to remove from map
func remove_seam_from_map(seam_line: Line2D) -> void:
	if not seam_line:
		return

	var seam_id = seam_line.get_instance_id()
	seam_to_fold_map.erase(seam_id)


## Remove all seams for a specific fold from the mapping
## UPDATED FOR PHASE 6 TASK 5: Also removes visual seam Line2D nodes
##
## @param fold_id: The fold ID whose seams should be removed
func remove_seams_for_fold(fold_id: int) -> void:
	# Find all seam Line2D nodes with this fold_id
	var seam_lines_to_remove = []
	for seam_line in seam_lines:
		if seam_line and is_instance_valid(seam_line):
			if seam_line.get_meta("fold_id", -1) == fold_id:
				seam_lines_to_remove.append(seam_line)

	# Remove each seam visual
	for seam_line in seam_lines_to_remove:
		# Remove from scene tree
		if seam_line.get_parent():
			seam_line.get_parent().remove_child(seam_line)

		# Remove from seam_lines array
		var index = seam_lines.find(seam_line)
		if index >= 0:
			seam_lines.remove_at(index)

		# Remove from seam_to_fold_map
		var seam_id = seam_line.get_instance_id()
		seam_to_fold_map.erase(seam_id)

		# Free the node
		seam_line.queue_free()


## Clear all seams (visuals and mapping)
##
## Removes all seam Line2D nodes and clears the seam-to-fold map
func clear_all_seams() -> void:
	# Remove all seam visuals from scene tree
	for seam_line in seam_lines:
		if seam_line and is_instance_valid(seam_line):
			if seam_line.get_parent():
				seam_line.get_parent().remove_child(seam_line)
			seam_line.queue_free()

	# Clear arrays and dictionaries
	seam_lines.clear()
	seam_to_fold_map.clear()


## ============================================================================
## PHASE 6: CLICKABLE ZONE CALCULATION (TASK 2)
## ============================================================================

## Calculate which grid cell centers a seam line passes through
##
## A seam is clickable at grid cells whose center is within tolerance distance
## of the seam line. This creates spatial constraints for player interaction.
##
## @param line_point: A point on the seam line (LOCAL coordinates)
## @param line_normal: Normal vector of the seam line (perpendicular to line)
## @return: Array[Vector2i] of grid positions whose centers the seam passes through
func calculate_clickable_zones(line_point: Vector2, line_normal: Vector2) -> Array[Vector2i]:
	var zones: Array[Vector2i] = []

	if not grid_manager:
		return zones

	var cell_size = grid_manager.cell_size
	var tolerance = cell_size * 0.15  # Generous tolerance for debug/testing

	# Iterate through all grid positions
	for y in range(grid_manager.grid_size.y):
		for x in range(grid_manager.grid_size.x):
			# Calculate grid cell center in LOCAL coordinates
			# Center = grid_pos * cell_size + (cell_size/2, cell_size/2)
			var cell_center = Vector2(x, y) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

			# Calculate distance from cell center to seam line
			# Distance from point P to line (point + t*normal) is: |(P - point) · normal|
			var distance = abs((cell_center - line_point).dot(line_normal))

			# If center is within tolerance of the line, it's a clickable zone
			if distance <= tolerance:
				zones.append(Vector2i(x, y))

	return zones


## Add Seam objects to cells affected by a diagonal fold
##
## Creates Seam objects for the fold lines and adds them to all cells
## that the seam lines pass through. This enables intersection validation.
##
## @param cut_lines: Dictionary from calculate_cut_lines()
## @param fold_id: ID of the fold creating these seams
func add_seams_to_cells(cut_lines: Dictionary, fold_id: int) -> void:
	var timestamp = Time.get_ticks_msec()

	# Calculate seam endpoints spanning the entire grid
	# This creates line segments that can be checked for intersection
	var grid_span = grid_manager.grid_size.x * grid_manager.cell_size

	# Line 1 endpoints
	var line1_start = cut_lines.line1.point - cut_lines.line1.normal * grid_span
	var line1_end = cut_lines.line1.point + cut_lines.line1.normal * grid_span
	var line1_points = PackedVector2Array([line1_start, line1_end])

	# Line 2 endpoints
	var line2_start = cut_lines.line2.point - cut_lines.line2.normal * grid_span
	var line2_end = cut_lines.line2.point + cut_lines.line2.normal * grid_span
	var line2_points = PackedVector2Array([line2_start, line2_end])

	# Create Seam objects for both cut lines
	var seam1 = Seam.new(
		cut_lines.line1.point,
		cut_lines.line1.normal,
		line1_points,
		fold_id,
		timestamp,
		"diagonal"
	)

	var seam2 = Seam.new(
		cut_lines.line2.point,
		cut_lines.line2.normal,
		line2_points,
		fold_id,
		timestamp,
		"diagonal"
	)

	# Add seams to all cells (they'll be stored in the cells' pieces)
	# NOTE: This adds seams to ALL cells for simplicity. Could be optimized
	# to only add to cells the seam actually passes through.
	for cell_pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[cell_pos]

		# Add seams to the first non-null piece in each cell
		for piece in cell.geometry_pieces:
			if piece.cell_type != CellPiece.CELL_TYPE_NULL:
				piece.add_seam(seam1.duplicate_seam())
				piece.add_seam(seam2.duplicate_seam())
				break  # Only add once per cell


## ============================================================================
## PHASE 6: SEAM INTERSECTION VALIDATION (TASK 3)
## ============================================================================

## Check if a fold can be undone based on seam intersection rules
##
## A fold can be undone iff no newer seams intersect with its seams.
## This prevents undoing folds that have been "cut" by subsequent folds.
##
## @param fold_id: The ID of the fold to check for undo
## @return: Dictionary with {valid: bool, reason: String, blocking_seams: Array[Seam]}
func can_undo_fold_seam_based(fold_id: int) -> Dictionary:
	# Find the fold record
	var target_fold = null
	for record in fold_history:
		if record["fold_id"] == fold_id:
			target_fold = record
			break

	if target_fold == null:
		return {
			"valid": false,
			"reason": "Fold ID %d not found in history" % fold_id,
			"blocking_seams": []
		}

	# Collect all seams from all current cells
	var target_seams: Array[Seam] = []
	var potential_blockers: Array[Seam] = []

	for cell_pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[cell_pos]
		var cell_seams = cell.get_all_seams()

		for seam in cell_seams:
			if seam.fold_id == fold_id:
				# This is a seam from the target fold
				target_seams.append(seam)
			elif seam.timestamp > target_fold["timestamp"]:
				# This is a newer seam that might block
				potential_blockers.append(seam)

	# If there are no seams from this fold, it can be undone (fold already removed or no seams left)
	if target_seams.is_empty():
		return {
			"valid": true,
			"reason": "",
			"blocking_seams": []
		}

	# Check if any potential blocker intersects with any target seam
	var blocking_seams: Array[Seam] = []
	var seen_blockers = {}  # Track unique blockers by fold_id

	for target_seam in target_seams:
		for blocker in potential_blockers:
			# Skip if we've already identified this fold as blocking
			if seen_blockers.has(blocker.fold_id):
				continue

			# Check if they intersect
			var intersection = target_seam.intersects_with(blocker)
			if intersection != Vector2.INF:
				# They intersect! This blocks the undo
				blocking_seams.append(blocker)
				seen_blockers[blocker.fold_id] = true

	# If we found blocking seams, undo is not allowed
	if not blocking_seams.is_empty():
		var blocker_ids = []
		for seam in blocking_seams:
			if seam.fold_id not in blocker_ids:
				blocker_ids.append(seam.fold_id)

		return {
			"valid": false,
			"reason": "Blocked by newer intersecting fold(s): %s" % str(blocker_ids),
			"blocking_seams": blocking_seams
		}

	# No blocking seams found, undo is allowed
	return {
		"valid": true,
		"reason": "",
		"blocking_seams": []
	}


## Check if player is standing on a seam (for unfold validation)
##
## A player is considered to be on a seam if their grid position is in the
## seam's clickable zones.
##
## @param fold_id: The ID of the fold whose seams to check
## @return: true if player is standing on any seam from this fold
func is_player_on_seam(fold_id: int) -> bool:
	if not player:
		return false

	var player_pos = player.grid_position

	# Check all seam lines for this fold
	for seam_line in seam_lines:
		if not seam_line or not is_instance_valid(seam_line):
			continue

		var seam_fold_id = seam_line.get_meta("fold_id", -1)
		if seam_fold_id != fold_id:
			continue

		# Check if player position is in this seam's clickable zones
		var zones = seam_line.get_meta("clickable_zones", [])
		if player_pos in zones:
			return true

	return false


## PHASE 6 TASK 4: Mouse Input for Seam Clicking
##
## Detects if a mouse click (in LOCAL coordinates) is on a seam's clickable zone.
## Returns information about the clicked seam, or null if no seam was clicked.
##
## @param click_pos_local: Mouse click position in LOCAL coordinates (relative to GridManager)
## @return: Dictionary with {fold_id, seam_line, can_undo} or null if no seam clicked
func detect_seam_click(click_pos_local: Vector2):
	if not grid_manager:
		return null

	var cell_size = grid_manager.cell_size
	var zone_radius = cell_size * 0.25  # Click tolerance

	# Track best match (highest fold_id if multiple seams overlap)
	var best_match = null
	var best_fold_id = -1

	# Check all seam lines
	for seam_line in seam_lines:
		if not seam_line or not is_instance_valid(seam_line):
			continue

		# Get clickable zones for this seam
		var zones = seam_line.get_meta("clickable_zones", [])
		if zones.is_empty():
			continue

		# Check each clickable zone
		for zone_grid_pos in zones:
			# Calculate zone center in LOCAL coordinates
			var zone_center = Vector2(zone_grid_pos) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

			# Check if click is within tolerance of zone center
			var distance = click_pos_local.distance_to(zone_center)
			if distance <= zone_radius:
				# Clicked on this seam!
				var fold_id = seam_line.get_meta("fold_id", -1)

				# If this is the first match, or has higher fold_id, use it
				if fold_id > best_fold_id:
					best_fold_id = fold_id

					# Check if this seam can be undone
					var validation = can_undo_fold_seam_based(fold_id)

					best_match = {
						"fold_id": fold_id,
						"seam_line": seam_line,
						"can_undo": validation["valid"]
					}

				# No need to check other zones for this seam
				break

	return best_match


## PHASE 6 TASK 6: Seam Visual State Updates
##
## Updates the visual appearance of all seam lines based on their undoable state.
## Undoable seams are shown in green, blocked seams in red.
## Should be called after executing or undoing a fold.
func update_seam_visual_states() -> void:
	# Update color for each seam based on whether it can be undone
	for seam_line in seam_lines:
		if not seam_line or not is_instance_valid(seam_line):
			continue

		var fold_id = seam_line.get_meta("fold_id", -1)
		if fold_id < 0:
			continue

		# Check if this seam can be undone
		var validation = can_undo_fold_seam_based(fold_id)

		if validation["valid"]:
			# Undoable: Green
			seam_line.default_color = Color.GREEN
		else:
			# Blocked: Red
			seam_line.default_color = Color.RED


## PHASE 6 TASK 5: Undo Execution
##
## Undoes a fold by restoring grid state from the fold record.
## Only allows undo if the fold passes seam intersection validation.
##
## @param fold_id: The ID of the fold to undo
## @return: true if undo succeeded, false if validation failed or fold not found
func undo_fold_by_id(fold_id: int) -> bool:
	if not grid_manager:
		push_error("FoldSystem: GridManager not initialized")
		return false

	# Find the fold record
	var target_fold = null
	var fold_index = -1
	for i in range(fold_history.size()):
		if fold_history[i]["fold_id"] == fold_id:
			target_fold = fold_history[i]
			fold_index = i
			break

	if target_fold == null:
		push_warning("FoldSystem: Fold ID %d not found in history" % fold_id)
		return false

	# Validate that this fold can be undone (check seam intersections)
	var validation = can_undo_fold_seam_based(fold_id)
	if not validation["valid"]:
		push_warning("FoldSystem: Cannot undo fold %d: %s" % [fold_id, validation["reason"]])
		return false

	# 1. Remove seam visuals for this fold
	remove_seams_for_fold(fold_id)

	# 2. Restore grid state from fold record
	# CRITICAL: Free all existing cells first to prevent memory leaks
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		if cell and is_instance_valid(cell):
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			cell.queue_free()

	grid_manager.cells.clear()

	# 3. Deserialize and recreate cells from saved state
	var cells_state = target_fold["cells_state"]
	var cell_size = grid_manager.cell_size

	for pos_str in cells_state.keys():
		var cell_data = cells_state[pos_str]

		# Parse grid position from string
		var pos = str_to_var(pos_str) as Vector2i

		# Calculate local position for this cell
		var local_pos = Vector2(pos) * cell_size

		# Create new Cell node with required constructor arguments
		var cell = Cell.new(pos, local_pos, cell_size)

		# PHASE 6 BUG FIX: Restore all geometry pieces if available
		if cell_data.has("geometry_pieces") and not cell_data["geometry_pieces"].is_empty():
			# New format: Restore all pieces
			cell.geometry_pieces.clear()  # Clear the default piece

			for piece_data in cell_data["geometry_pieces"]:
				# Restore piece geometry
				var piece_geometry = PackedVector2Array()
				for point_dict in piece_data["geometry"]:
					piece_geometry.append(Vector2(point_dict["x"], point_dict["y"]))

				# Create CellPiece
				var piece = CellPiece.new(piece_geometry, piece_data["cell_type"], piece_data["source_fold_id"])

				# Restore piece seams
				for seam_data in piece_data.get("seams", []):
					# Deserialize intersection points
					var intersection_points = PackedVector2Array()
					for point_dict in seam_data["intersection_points"]:
						intersection_points.append(Vector2(point_dict["x"], point_dict["y"]))

					# Create Seam object
					var seam = Seam.new(
						Vector2(seam_data["line_point"]["x"], seam_data["line_point"]["y"]),
						Vector2(seam_data["line_normal"]["x"], seam_data["line_normal"]["y"]),
						intersection_points,
						seam_data["fold_id"],
						seam_data["timestamp"],
						seam_data["fold_type"]
					)
					piece.add_seam(seam)

				cell.geometry_pieces.append(piece)

			# Update dominant type
			cell.cell_type = cell.get_dominant_type()
			cell.is_partial = cell_data.get("is_partial", false)

		else:
			# Legacy format: Single geometry piece
			var geometry_array = cell_data.get("geometry", [])
			var geometry_points = PackedVector2Array()
			for point_dict in geometry_array:
				geometry_points.append(Vector2(point_dict["x"], point_dict["y"]))
			cell.geometry = geometry_points

			cell.cell_type = cell_data.get("cell_type", 0)
			cell.is_partial = cell_data.get("is_partial", false)
			cell.seams = cell_data.get("seams", [])

		# Add cell to grid
		grid_manager.add_child(cell)
		grid_manager.cells[pos] = cell

		# Update cell visual
		cell.update_visual()

	# 4. Restore player position
	if player and target_fold.has("player_position"):
		var saved_player_pos = target_fold["player_position"]
		if saved_player_pos != Vector2i(-1, -1):
			player.grid_position = saved_player_pos
			var cell_at_pos = grid_manager.get_cell(saved_player_pos)
			if cell_at_pos:
				player.global_position = grid_manager.to_global(cell_at_pos.get_center())

	# 5. Remove fold from history
	fold_history.remove_at(fold_index)

	# 6. Update GameManager fold count if it exists
	if GameManager:
		GameManager.fold_count -= 1

	# 7. Update seam visual states (PHASE 6)
	update_seam_visual_states()

	# 8. Play undo sound effect (if available)
	if AudioManager:
		AudioManager.play_sfx("undo")

	return true


## UNFOLD SEAM (geometric reversal without state restoration)
##
## Unfolds a seam by reversing the geometric fold operation WITHOUT restoring
## player position or full grid state. This behaves like unfolding paper:
## - Cells shifted by the fold are shifted back
## - Cells removed by the fold are reintroduced
## - Player position is NOT restored (unless they were on a shifted region)
## - Other folds' effects are preserved
##
## @param fold_id: The ID of the fold to unfold
## @return: true if unfold succeeded, false if validation failed or fold not found
func unfold_seam(fold_id: int) -> bool:
	if not grid_manager:
		push_error("FoldSystem: GridManager not initialized")
		return false

	# Check if player is standing on the seam
	if is_player_on_seam(fold_id):
		push_warning("FoldSystem: Cannot unfold - player is standing on the seam")
		return false

	# Find the fold record
	var target_fold = null
	var fold_index = -1
	for i in range(fold_history.size()):
		if fold_history[i]["fold_id"] == fold_id:
			target_fold = fold_history[i]
			fold_index = i
			break

	if target_fold == null:
		push_warning("FoldSystem: Fold ID %d not found in history" % fold_id)
		return false

	# Validate that this fold can be undone (check seam intersections)
	var validation = can_undo_fold_seam_based(fold_id)
	if not validation["valid"]:
		push_warning("FoldSystem: Cannot unfold fold %d: %s" % [fold_id, validation["reason"]])
		return false

	# Get fold metadata
	var anchor1 = target_fold["anchor1"]
	var anchor2 = target_fold["anchor2"]
	var orientation = target_fold["orientation"]
	var removed_cells_data = target_fold["cells_state"]
	var removed_cell_positions = target_fold["removed_cells"]

	# Calculate the shift vector (reverse of original fold)
	# Original fold: shifted from anchor2 to anchor1
	# Unfold: shift from anchor1 back to anchor2
	var shift_vector = anchor2 - anchor1

	# 1. Identify cells that were shifted by the original fold
	# These need to be shifted back to their original positions
	var cells_to_shift_back: Array[Cell] = []

	# For axis-aligned folds, determine which cells were shifted
	# During fold: target is leftmost (horizontal) or topmost (vertical), source is the other
	# Cells past source shifted toward target
	# During unfold: cells that are currently in the "gap" positions need to shift back

	if orientation == "horizontal":
		# Horizontal fold: target=leftmost, cells from right shifted left
		# Currently, cells at positions between min_x and max_x (exclusive of min_x) are shifted
		# They need to shift back right
		var min_x = min(anchor1.x, anchor2.x)
		var max_x = max(anchor1.x, anchor2.x)
		# Cells currently at x > min_x up to and including x=max_x were shifted and need to go back
		for pos in grid_manager.cells.keys():
			if pos.x > min_x and pos.x <= max_x:
				cells_to_shift_back.append(grid_manager.cells[pos])
	elif orientation == "vertical":
		# Vertical fold: target=topmost, cells from bottom shifted up
		# Currently, cells at positions between min_y and max_y (exclusive of min_y) are shifted
		# They need to shift back down
		var min_y = min(anchor1.y, anchor2.y)
		var max_y = max(anchor1.y, anchor2.y)
		# Cells currently at y > min_y up to and including y=max_y were shifted and need to go back
		for pos in grid_manager.cells.keys():
			if pos.y > min_y and pos.y <= max_y:
				cells_to_shift_back.append(grid_manager.cells[pos])
	else:
		# Diagonal fold: more complex - need to check which side of lines cells are on
		# For simplicity, we'll shift all cells that would have been shifted in the original fold
		# This is determined by checking if they're on the source side of the fold
		var cell_size = grid_manager.cell_size
		var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
		var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)
		var cut_lines = calculate_cut_lines(anchor1_local, anchor2_local)

		# Cells past line1 (on the anchor1 side) should be shifted back
		for pos in grid_manager.cells.keys():
			var cell = grid_manager.cells[pos]
			var cell_center = cell.get_center()
			var dist_from_line1 = (cell_center - cut_lines.line1.point).dot(cut_lines.line1.normal)

			# If on the anchor1 side (negative distance), it was shifted and needs to shift back
			if dist_from_line1 < 0:
				cells_to_shift_back.append(cell)

	# 2. Shift cells back to their original positions
	# Use two-pass approach to avoid false collisions
	var cells_with_new_pos: Array[Dictionary] = []

	# Pass 1: Remove from old positions and update properties
	for cell in cells_to_shift_back:
		var old_pos = cell.grid_position
		var new_pos = old_pos + shift_vector

		# Remove from old position
		grid_manager.cells.erase(old_pos)

		# Update cell position
		cell.grid_position = new_pos

		# Translate geometry for ALL pieces
		var shift_pixels = Vector2(shift_vector) * grid_manager.cell_size
		for piece in cell.geometry_pieces:
			var new_geometry = PackedVector2Array()
			for vertex in piece.geometry:
				new_geometry.append(vertex + shift_pixels)
			piece.geometry = new_geometry
		cell.update_visual()

		cells_with_new_pos.append({"cell": cell, "old_pos": old_pos, "new_pos": new_pos})

	# Pass 2: Place cells at new positions
	for data in cells_with_new_pos:
		var cell = data.cell
		var new_pos = data.new_pos

		# Check if there's a cell at the destination
		var existing = grid_manager.get_cell(new_pos)
		if existing:
			# Merge with existing cell
			_merge_cells_multi_polygon(existing, cell, new_pos)
		else:
			# No collision, just place the cell
			grid_manager.cells[new_pos] = cell

	# 3. Reintroduce removed cells at their original positions
	var cell_size = grid_manager.cell_size
	for pos_str in removed_cells_data.keys():
		var pos = str_to_var(pos_str) as Vector2i

		# Only reintroduce if this cell was in the removed region
		if pos not in removed_cell_positions:
			continue

		# Skip if a cell already exists at this position
		if grid_manager.get_cell(pos):
			continue

		var cell_data = removed_cells_data[pos_str]

		# Calculate local position for this cell
		var local_pos = Vector2(pos) * cell_size

		# Create new Cell node
		var cell = Cell.new(pos, local_pos, cell_size)

		# Restore geometry pieces if available
		if cell_data.has("geometry_pieces") and not cell_data["geometry_pieces"].is_empty():
			cell.geometry_pieces.clear()

			for piece_data in cell_data["geometry_pieces"]:
				# Restore piece geometry
				var piece_geometry = PackedVector2Array()
				for point_dict in piece_data["geometry"]:
					piece_geometry.append(Vector2(point_dict["x"], point_dict["y"]))

				# Create CellPiece (excluding null pieces and seams from this fold)
				var piece_type = piece_data["cell_type"]
				var piece_source_fold = piece_data["source_fold_id"]

				# Skip null pieces created by this fold
				if piece_type == CellPiece.CELL_TYPE_NULL and piece_source_fold == fold_id:
					continue

				var piece = CellPiece.new(piece_geometry, piece_type, piece_source_fold)

				# Restore seams (excluding seams from this fold)
				for seam_data in piece_data.get("seams", []):
					if seam_data["fold_id"] == fold_id:
						continue  # Don't restore seams from this fold

					# Deserialize intersection points
					var intersection_points = PackedVector2Array()
					for point_dict in seam_data["intersection_points"]:
						intersection_points.append(Vector2(point_dict["x"], point_dict["y"]))

					# Create Seam object
					var seam = Seam.new(
						Vector2(seam_data["line_point"]["x"], seam_data["line_point"]["y"]),
						Vector2(seam_data["line_normal"]["x"], seam_data["line_normal"]["y"]),
						intersection_points,
						seam_data["fold_id"],
						seam_data["timestamp"],
						seam_data["fold_type"]
					)
					piece.add_seam(seam)

				cell.geometry_pieces.append(piece)

			# Update dominant type
			cell.cell_type = cell.get_dominant_type()
			cell.is_partial = cell_data.get("is_partial", false)
		else:
			# Legacy format
			var geometry_array = cell_data.get("geometry", [])
			var geometry_points = PackedVector2Array()
			for point_dict in geometry_array:
				geometry_points.append(Vector2(point_dict["x"], point_dict["y"]))
			cell.geometry = geometry_points

			cell.cell_type = cell_data.get("cell_type", 0)
			cell.is_partial = cell_data.get("is_partial", false)

		# Add cell to grid
		grid_manager.add_child(cell)
		grid_manager.cells[pos] = cell
		cell.update_visual()

	# 4. Update player position if they were on a shifted cell
	if player:
		var player_old_pos = player.grid_position
		# Check if player's current cell was shifted
		for data in cells_with_new_pos:
			if data.old_pos == player_old_pos:
				# Player was on a shifted cell, move them with it
				player.grid_position = data.new_pos
				var new_cell = grid_manager.get_cell(player.grid_position)
				if new_cell:
					player.global_position = grid_manager.to_global(new_cell.get_center())
				break

	# 5. Remove seam visuals for this fold
	remove_seams_for_fold(fold_id)

	# 6. Remove fold from history
	fold_history.remove_at(fold_index)

	# 7. Update GameManager fold count
	if GameManager:
		GameManager.fold_count -= 1

	# 8. Update seam visual states
	update_seam_visual_states()

	# 9. Play unfold sound effect
	if AudioManager:
		AudioManager.play_sfx("unfold")

	# 10. Clean up any freed cell references
	grid_manager.cleanup_freed_cells()

	return true


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
## PHASE 5: Checks ALL pieces in multi-piece cells, not just the first.
##
## @param cell: The cell to test
## @param line_point: A point on the line
## @param line_normal: The normal vector of the line
## @return: true if cell is truly split by the line
func does_cell_intersect_line(cell: Cell, line_point: Vector2, line_normal: Vector2) -> bool:
	# Check if there are vertices on both sides of the line
	var has_positive = false
	var has_negative = false

	# PHASE 5: Check ALL pieces, not just first piece (which is what cell.geometry returns)
	for piece in cell.geometry_pieces:
		for vertex in piece.geometry:
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
	# Get current fold_id (will be incremented after fold record is created)
	var current_fold_id = next_fold_id

	# For diagonal folds, we create two seam lines (at each cut)
	var seam_line1 = Line2D.new()
	seam_line1.width = 2.0
	seam_line1.default_color = Color.CYAN

	# Calculate seam endpoints spanning the grid
	var line1_start = cut_lines.line1.point - cut_lines.line1.normal * 1000
	var line1_end = cut_lines.line1.point + cut_lines.line1.normal * 1000
	seam_line1.points = PackedVector2Array([line1_start, line1_end])

	# PHASE 6: Add metadata for fold_id tracking
	seam_line1.set_meta("fold_id", current_fold_id)

	# PHASE 6 TASK 2: Add line geometry metadata
	seam_line1.set_meta("line_point", cut_lines.line1.point)
	seam_line1.set_meta("line_normal", cut_lines.line1.normal)

	grid_manager.add_child(seam_line1)
	seam_lines.append(seam_line1)

	# PHASE 6: Add to seam-to-fold mapping
	seam_to_fold_map[seam_line1.get_instance_id()] = current_fold_id

	# PHASE 6 TASK 2: Calculate and store clickable zones
	var zones1 = calculate_clickable_zones(cut_lines.line1.point, cut_lines.line1.normal)
	seam_line1.set_meta("clickable_zones", zones1)

	# Second seam line
	var seam_line2 = Line2D.new()
	seam_line2.width = 2.0
	seam_line2.default_color = Color.CYAN

	var line2_start = cut_lines.line2.point - cut_lines.line2.normal * 1000
	var line2_end = cut_lines.line2.point + cut_lines.line2.normal * 1000
	seam_line2.points = PackedVector2Array([line2_start, line2_end])

	# PHASE 6: Add metadata for fold_id tracking
	seam_line2.set_meta("fold_id", current_fold_id)

	# PHASE 6 TASK 2: Add line geometry metadata
	seam_line2.set_meta("line_point", cut_lines.line2.point)
	seam_line2.set_meta("line_normal", cut_lines.line2.normal)

	grid_manager.add_child(seam_line2)
	seam_lines.append(seam_line2)

	# PHASE 6: Add to seam-to-fold mapping
	seam_to_fold_map[seam_line2.get_instance_id()] = current_fold_id

	# PHASE 6 TASK 2: Calculate and store clickable zones
	var zones2 = calculate_clickable_zones(cut_lines.line2.point, cut_lines.line2.normal)
	seam_line2.set_meta("clickable_zones", zones2)

	# PHASE 6 TASK 3: Add Seam objects to affected cells for intersection validation
	add_seams_to_cells(cut_lines, current_fold_id)


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

	# PHASE 6: Save grid state BEFORE fold operations (for undo functionality)
	var pre_fold_grid_state = serialize_grid_state()
	var pre_fold_player_pos = player.grid_position if player else Vector2i(-1, -1)

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

	# PHASE 6: Update seam visual states after creating new seams
	update_seam_visual_states()

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

	# Create fold record using PRE-fold state (saved earlier)
	var fold_record = {
		"fold_id": next_fold_id,
		"anchor1": anchor1,
		"anchor2": anchor2,
		"removed_cells": removed_positions.duplicate(),
		"orientation": orientation,
		"timestamp": Time.get_ticks_msec(),
		"cells_state": pre_fold_grid_state,  # Use pre-saved state
		"player_position": pre_fold_player_pos,  # Use pre-saved player position
		"fold_count": GameManager.fold_count if GameManager else 0
	}
	next_fold_id += 1
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
## PHASE 5: Now processes ALL pieces in multi-piece cells, not just the first one.
## This fixes the multi-seam merging bug where pieces would disappear.
##
## @param cells: Array of cells intersecting line1
## @param cut_lines: Cut line data
## @param anchor1: First anchor position
## @param anchor2: Second anchor position
## @return: Array of split cell geometries to merge at anchor1
## Classify a piece relative to a cut line
##
## For multi-piece cells, we need to know:
## - "split": Piece is intersected by the line (has vertices on both sides)
## - "keep": Piece is entirely on the keep side (all vertices on keep side)
## - "remove": Piece is entirely on the remove side (all vertices on remove side)
##
## @param piece: The piece to classify
## @param line_point: A point on the cut line
## @param line_normal: The normal of the cut line
## @param keep_side: Which side should be kept ("left" or "right")
## @return: String indicating classification
func _classify_piece_relative_to_line(piece: CellPiece, line_point: Vector2, line_normal: Vector2, keep_side: String) -> String:
	var has_positive = false
	var has_negative = false

	# Check all vertices
	for vertex in piece.geometry:
		var side = GeometryCore.point_side_of_line(vertex, line_point, line_normal)
		if side > GeometryCore.EPSILON:
			has_positive = true
		elif side < -GeometryCore.EPSILON:
			has_negative = true

	# If vertices on both sides, piece is split
	if has_positive and has_negative:
		return "split"

	# All vertices on one side - determine which side
	# Normal vector points to the RIGHT/positive side
	var keep_is_positive = (keep_side == "right")  # "right" is positive side (normal points there)

	if has_positive and not has_negative:
		# All on positive side
		return "keep" if keep_is_positive else "remove"
	elif has_negative and not has_positive:
		# All on negative side
		return "keep" if not keep_is_positive else "remove"
	else:
		# All vertices on the line (degenerate case)
		return "keep"


func _process_split_cells_on_line1(cells: Array, cut_lines: Dictionary, anchor1: Vector2i, anchor2: Vector2i) -> Array:
	var split_parts = []

	# Determine which side of line1 to keep (away from anchor2)
	var anchor2_local = Vector2(anchor2) * grid_manager.cell_size + Vector2(grid_manager.cell_size / 2, grid_manager.cell_size / 2)
	var anchor2_side = GeometryCore.point_side_of_line(anchor2_local, cut_lines.line1.point, cut_lines.line1.normal)
	var keep_side = "right" if anchor2_side < 0 else "left"

	for cell in cells:
		# PHASE 5: Process ALL pieces in the cell, not just the first one
		# This fixes the multi-seam bug where only cell.geometry (first piece) was split
		var new_pieces: Array[CellPiece] = []
		var pieces_to_remove: Array[int] = []

		for i in range(cell.geometry_pieces.size()):
			var piece = cell.geometry_pieces[i]

			# Classify this piece relative to line1
			var classification = _classify_piece_relative_to_line(
				piece, cut_lines.line1.point, cut_lines.line1.normal, keep_side
			)

			if classification == "keep":
				# Piece is entirely on the keep side - keep as-is, no duplication needed
				new_pieces.append(piece)
				pieces_to_remove.append(i)

			elif classification == "remove":
				# Piece is entirely on the remove side - discard it
				pieces_to_remove.append(i)

			else:  # classification == "split"
				# This piece is split by line1 - need to split and keep only one part
				var split_result = GeometryCore.split_polygon_by_line(
					piece.geometry, cut_lines.line1.point, cut_lines.line1.normal
				)

				var kept_geometry: PackedVector2Array

				# Get the appropriate side based on keep_side
				if keep_side == "left":
					kept_geometry = split_result.left
				else:
					kept_geometry = split_result.right

				# Create new piece with kept geometry
				var kept_piece = CellPiece.new(kept_geometry, piece.cell_type, piece.source_fold_id)
				# Copy seams from original piece
				for seam in piece.seams:
					kept_piece.add_seam(seam.duplicate_seam())
				new_pieces.append(kept_piece)
				pieces_to_remove.append(i)

		# Remove old pieces (in reverse order to avoid index shifts)
		for i in range(pieces_to_remove.size() - 1, -1, -1):
			cell.geometry_pieces.remove_at(pieces_to_remove[i])

		# Add new pieces
		for piece in new_pieces:
			cell.geometry_pieces.append(piece)

		# Update cell state
		if cell.geometry_pieces.size() > 0:
			cell.is_partial = true
			cell.cell_type = cell.get_dominant_type()
			cell.update_visual()

			# Store the cell for potential merging
			split_parts.append({
				"cell": cell,
				"geometry": cell.geometry_pieces[0].geometry,
				"position": anchor1
			})
		else:
			# No pieces left - cell becomes empty
			if DEBUG_FOLD_EXECUTION:
				print("  WARNING: Cell at %s has no pieces after splitting on line1" % cell.grid_position)

	return split_parts


## Process cells on line2 (at anchor2) - split and prepare for shifting
##
## PHASE 5: Now processes ALL pieces in multi-piece cells, not just the first one.
## This fixes the multi-seam merging bug where pieces would disappear.
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
		# PHASE 5: Process ALL pieces in the cell, not just the first one
		# This fixes the multi-seam bug where only cell.geometry (first piece) was split
		var new_pieces: Array[CellPiece] = []
		var pieces_to_remove: Array[int] = []

		for i in range(cell.geometry_pieces.size()):
			var piece = cell.geometry_pieces[i]

			# Classify this piece relative to line2
			var classification = _classify_piece_relative_to_line(
				piece, cut_lines.line2.point, cut_lines.line2.normal, keep_side
			)

			if classification == "keep":
				# Piece is entirely on the keep side - keep as-is, no duplication needed
				new_pieces.append(piece)
				pieces_to_remove.append(i)

			elif classification == "remove":
				# Piece is entirely on the remove side - discard it
				pieces_to_remove.append(i)

			else:  # classification == "split"
				# This piece is split by line2 - need to split and keep only one part
				var split_result = GeometryCore.split_polygon_by_line(
					piece.geometry, cut_lines.line2.point, cut_lines.line2.normal
				)

				var kept_geometry: PackedVector2Array

				# Get the appropriate side based on keep_side
				if keep_side == "left":
					kept_geometry = split_result.left
				else:
					kept_geometry = split_result.right

				# Create new piece with kept geometry
				var kept_piece = CellPiece.new(kept_geometry, piece.cell_type, piece.source_fold_id)
				# Copy seams from original piece
				for seam in piece.seams:
					kept_piece.add_seam(seam.duplicate_seam())
				new_pieces.append(kept_piece)
				pieces_to_remove.append(i)

		# Remove old pieces (in reverse order to avoid index shifts)
		for i in range(pieces_to_remove.size() - 1, -1, -1):
			cell.geometry_pieces.remove_at(pieces_to_remove[i])

		# Add new pieces
		for piece in new_pieces:
			cell.geometry_pieces.append(piece)

		# Update cell state
		if cell.geometry_pieces.size() > 0:
			cell.is_partial = true
			cell.cell_type = cell.get_dominant_type()
			cell.update_visual()

			# This cell will shift - store it
			split_parts.append(cell)
		else:
			# No pieces left - mark for debug
			if DEBUG_FOLD_EXECUTION:
				print("  WARNING: Cell at %s has no pieces after splitting on line2" % cell.grid_position)

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
			# No cell at destination - create null pieces to complete the cell
			_add_null_pieces_to_complete_cell(cell, new_pos)

			# Place cell at new position
			grid_manager.cells[new_pos] = cell


## Add null pieces to complete a cell when it has no merge partner
##
## When a split cell shifts to a position with no existing cell, we need to
## create "null" pieces to represent the missing/void geometry. This maintains
## the invariant that all cells are geometrically complete.
##
## @param cell: The cell to complete with null pieces
## @param pos: Grid position of the cell
func _add_null_pieces_to_complete_cell(cell: Cell, pos: Vector2i):
	# Calculate the complement geometry (the missing piece)
	var complement_geometry = GeometryCore.calculate_complement_geometry(
		pos,
		grid_manager.cell_size,
		cell.geometry_pieces
	)

	# If there's no complement (cell is already complete), do nothing
	if complement_geometry.is_empty() or complement_geometry.size() < 3:
		return

	# Create a null piece with the complement geometry
	var null_piece = CellPiece.new(
		complement_geometry,
		CellPiece.CELL_TYPE_NULL,
		next_fold_id - 1  # Track which fold created this null piece (current fold)
	)

	# Add the null piece to the cell
	cell.add_piece(null_piece)

	# Update dominant type (will be null if any null pieces exist)
	cell.cell_type = cell.get_dominant_type()

	# Mark as partial since it contains null geometry
	cell.is_partial = true

	# Update visual (null pieces are invisible)
	cell.update_visual()

	if DEBUG_FOLD_EXECUTION:
		print("  Added null piece to cell at %s (complement area: %.1f)" % [
			pos,
			GeometryCore.polygon_area(complement_geometry)
		])


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
