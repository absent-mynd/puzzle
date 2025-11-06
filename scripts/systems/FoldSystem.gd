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

## Minimum fold distance constant (at least 1 cell between anchors)
const MIN_FOLD_DISTANCE = 1

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

	# Check axis-aligned (Phase 3 only) - Must come before minimum distance
	# because minimum distance check returns wrong error for diagonals
	if not validate_same_row_or_column(anchor1, anchor2):
		return {valid = false, reason = "Only horizontal and vertical folds supported (for now)"}

	# Check minimum distance
	if not validate_minimum_distance(anchor1, anchor2):
		return {valid = false, reason = "Anchors must have at least one cell between them"}

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

	# Check if player is in removed region
	if is_player_in_removed_region(anchor1, anchor2):
		return {valid = false, reason = "Cannot fold - player in the way"}

	# Future (Phase 4): Check if player's cell would be split
	# if would_split_player_cell(anchor1, anchor2):
	#     return {valid = false, reason = "Cannot fold - player's cell would be split"}

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


## Helper Methods

## Calculate which cells will be removed by a fold
##
## Returns the grid positions of all cells between the two anchors
## (not including the anchor cells themselves).
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @return: Array of grid positions that will be removed
func calculate_removed_cells(anchor1: Vector2i, anchor2: Vector2i) -> Array[Vector2i]:
	var removed_cells: Array[Vector2i] = []

	if is_horizontal_fold(anchor1, anchor2):
		# Ensure anchor1 is leftmost
		var left = min(anchor1.x, anchor2.x)
		var right = max(anchor1.x, anchor2.x)
		var y = anchor1.y

		# Add all cells between anchors (exclusive)
		for x in range(left + 1, right):
			removed_cells.append(Vector2i(x, y))

	elif is_vertical_fold(anchor1, anchor2):
		# Ensure anchor1 is topmost
		var top = min(anchor1.y, anchor2.y)
		var bottom = max(anchor1.y, anchor2.y)
		var x = anchor1.x

		# Add all cells between anchors (exclusive)
		for y in range(top + 1, bottom):
			removed_cells.append(Vector2i(x, y))

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


## Create a fold record for the history system
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param removed_cells: Array of cells that were removed
## @param orientation: Fold orientation ("horizontal" or "vertical")
## @return: Dictionary containing fold metadata
func create_fold_record(anchor1: Vector2i, anchor2: Vector2i, removed_cells: Array[Vector2i], orientation: String) -> Dictionary:
	var record = {
		"fold_id": next_fold_id,
		"anchor1": anchor1,
		"anchor2": anchor2,
		"removed_cells": removed_cells.duplicate(),
		"orientation": orientation,
		"timestamp": Time.get_ticks_msec()
	}

	next_fold_id += 1
	return record


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

	for data in cells_to_shift:
		var cell = data.cell
		var new_pos = data.new_pos

		# Calculate new world position
		var new_world_pos = grid_manager.grid_to_world(new_pos)
		var cell_size = grid_manager.cell_size

		# Calculate center of new cell position (for visual reference)
		var target_center = new_world_pos + Vector2(cell_size / 2, cell_size / 2)

		# We need to tween the cell's polygon geometry, not just position
		# For now, we'll calculate the new geometry and tween each vertex
		var new_geometry = PackedVector2Array([
			new_world_pos,
			new_world_pos + Vector2(cell_size, 0),
			new_world_pos + Vector2(cell_size, cell_size),
			new_world_pos + Vector2(0, cell_size)
		])

		# Create tween for this cell
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)

		# Tween the geometry by interpolating each vertex
		# We'll use a property tweener with a custom interpolation
		var start_geometry = cell.geometry.duplicate()
		var steps = int(duration * 60)  # 60 FPS approximation

		# Simple approach: directly update geometry over time
		for i in range(steps + 1):
			var t = float(i) / float(steps)
			await get_tree().create_timer(duration / steps).timeout

			# Interpolate geometry
			var interpolated = PackedVector2Array()
			for j in range(start_geometry.size()):
				interpolated.append(start_geometry[j].lerp(new_geometry[j], t))

			cell.geometry = interpolated
			cell.update_visual()

		tweens.append(tween)

	# Wait for all tweens to complete
	for tween in tweens:
		if tween:
			await tween.finished


## Create visual seam line after fold completion
##
## @param anchor1: First anchor position
## @param anchor2: Second anchor position
## @param orientation: Fold orientation ("horizontal" or "vertical")
func create_seam_visual(anchor1: Vector2i, anchor2: Vector2i, orientation: String) -> void:
	var seam_line = Line2D.new()
	seam_line.width = 2.0
	seam_line.default_color = Color.CYAN

	# Get world positions of anchor points
	var pos1 = grid_manager.grid_to_world(anchor1)
	var pos2 = grid_manager.grid_to_world(anchor2)

	# Adjust to center of cells
	var cell_size = grid_manager.cell_size
	var offset = Vector2(cell_size / 2, cell_size / 2)
	pos1 += offset
	pos2 += offset

	# For axis-aligned folds, draw perpendicular line at fold point
	if orientation == "horizontal":
		# Draw vertical line at the merged point
		var fold_x = pos1.x
		var y = pos1.y
		seam_line.points = PackedVector2Array([
			Vector2(fold_x, y - cell_size / 2),
			Vector2(fold_x, y + cell_size / 2)
		])
	elif orientation == "vertical":
		# Draw horizontal line at the merged point
		var x = pos1.x
		var fold_y = pos1.y
		seam_line.points = PackedVector2Array([
			Vector2(x - cell_size / 2, fold_y),
			Vector2(x + cell_size / 2, fold_y)
		])

	# Add to scene tree
	grid_manager.add_child(seam_line)
	seam_lines.append(seam_line)


## Horizontal Fold Implementation

## Execute a horizontal fold between two anchors
##
## Algorithm:
## 1. Normalize anchor order (ensure anchor1 is leftmost)
## 2. Calculate removed region
## 3. Remove cells
## 4. Shift cells to the right of anchor2
## 5. Update world positions
## 6. Create merged anchor point
## 7. Record fold operation
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_horizontal_fold(anchor1: Vector2i, anchor2: Vector2i):
	# 1. Normalize anchor order (ensure anchor1 is leftmost)
	var left_anchor = anchor1 if anchor1.x < anchor2.x else anchor2
	var right_anchor = anchor2 if anchor1.x < anchor2.x else anchor1

	var y = left_anchor.y  # Row where fold occurs

	# 2. Calculate removed region
	var removed_cells = calculate_removed_cells(left_anchor, right_anchor)

	# 3. Remove cells from grid
	for pos in removed_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			# Remove from dictionary first
			grid_manager.cells.erase(pos)
			# Remove from scene tree
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			# Free the cell
			cell.queue_free()

	# 4. Shift cells to the right of right_anchor
	var shift_distance = right_anchor.x - left_anchor.x

	# Collect cells that need to be shifted
	var cells_to_shift: Array[Dictionary] = []
	for x in range(right_anchor.x + 1, grid_manager.grid_size.x):
		var old_pos = Vector2i(x, y)
		var cell = grid_manager.get_cell(old_pos)
		if cell:
			var new_x = x - shift_distance
			var new_pos = Vector2i(new_x, y)
			cells_to_shift.append({
				"cell": cell,
				"old_pos": old_pos,
				"new_pos": new_pos
			})

	# Actually move the cells
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos
		var new_pos = data.new_pos

		# Update cell's grid position
		cell.grid_position = new_pos

		# Update cell's world position (geometry stays relative, just move the cell node)
		var new_world_pos = grid_manager.grid_to_world(new_pos)
		cell.position = new_world_pos
		# No need to update geometry - it's already relative to cell position
		# Geometry stays as: [Vector2.ZERO, Vector2(size,0), Vector2(size,size), Vector2(0,size)]

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)
		grid_manager.cells[new_pos] = cell

	# 6. Record fold operation
	var fold_record = create_fold_record(left_anchor, right_anchor, removed_cells, "horizontal")
	fold_history.append(fold_record)


## Vertical Fold Implementation

## Execute a vertical fold between two anchors
##
## Algorithm:
## 1. Normalize anchor order (ensure anchor1 is topmost)
## 2. Calculate removed region
## 3. Remove cells
## 4. Shift cells below anchor2
## 5. Update world positions
## 6. Create merged anchor point
## 7. Record fold operation
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_vertical_fold(anchor1: Vector2i, anchor2: Vector2i):
	# 1. Normalize anchor order (ensure anchor1 is topmost)
	var top_anchor = anchor1 if anchor1.y < anchor2.y else anchor2
	var bottom_anchor = anchor2 if anchor1.y < anchor2.y else anchor1

	var x = top_anchor.x  # Column where fold occurs

	# 2. Calculate removed region
	var removed_cells = calculate_removed_cells(top_anchor, bottom_anchor)

	# 3. Remove cells from grid
	for pos in removed_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			# Remove from dictionary first
			grid_manager.cells.erase(pos)
			# Remove from scene tree
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			# Free the cell
			cell.queue_free()

	# 4. Shift cells below bottom_anchor
	var shift_distance = bottom_anchor.y - top_anchor.y

	# Collect cells that need to be shifted
	var cells_to_shift: Array[Dictionary] = []
	for y in range(bottom_anchor.y + 1, grid_manager.grid_size.y):
		var old_pos = Vector2i(x, y)
		var cell = grid_manager.get_cell(old_pos)
		if cell:
			var new_y = y - shift_distance
			var new_pos = Vector2i(x, new_y)
			cells_to_shift.append({
				"cell": cell,
				"old_pos": old_pos,
				"new_pos": new_pos
			})

	# Actually move the cells
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos
		var new_pos = data.new_pos

		# Update cell's grid position
		cell.grid_position = new_pos

		# Update cell's world position (geometry stays relative, just move the cell node)
		var new_world_pos = grid_manager.grid_to_world(new_pos)
		cell.position = new_world_pos
		# No need to update geometry - it's already relative to cell position
		# Geometry stays as: [Vector2.ZERO, Vector2(size,0), Vector2(size,size), Vector2(0,size)]

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)
		grid_manager.cells[new_pos] = cell

	# 6. Record fold operation
	var fold_record = create_fold_record(top_anchor, bottom_anchor, removed_cells, "vertical")
	fold_history.append(fold_record)


## Execute a horizontal fold with animation (Issue #9)
##
## Same as execute_horizontal_fold but with visual animations
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_horizontal_fold_animated(anchor1: Vector2i, anchor2: Vector2i) -> void:
	# 1. Normalize anchor order (ensure anchor1 is leftmost)
	var left_anchor = anchor1 if anchor1.x < anchor2.x else anchor2
	var right_anchor = anchor2 if anchor1.x < anchor2.x else anchor1

	var y = left_anchor.y  # Row where fold occurs

	# 2. Calculate removed region
	var removed_cells = calculate_removed_cells(left_anchor, right_anchor)

	# 3. Collect cells that need to be shifted
	var shift_distance = right_anchor.x - left_anchor.x
	var cells_to_shift: Array[Dictionary] = []
	for x in range(right_anchor.x + 1, grid_manager.grid_size.x):
		var old_pos = Vector2i(x, y)
		var cell = grid_manager.get_cell(old_pos)
		if cell:
			var new_x = x - shift_distance
			var new_pos = Vector2i(new_x, y)
			cells_to_shift.append({
				"cell": cell,
				"old_pos": old_pos,
				"new_pos": new_pos
			})

	# 4. Animate fade out of removed cells
	await fade_out_cells(removed_cells, fade_duration)

	# 5. Remove cells from grid
	for pos in removed_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			grid_manager.cells.erase(pos)
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			cell.queue_free()

	# 6. Animate cell shifting
	await shift_cells_animated(cells_to_shift, shift_duration)

	# 7. Update grid positions after animation
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos
		var new_pos = data.new_pos

		# Update cell's grid position
		cell.grid_position = new_pos

		# Update final position (geometry stays relative)
		var new_world_pos = grid_manager.grid_to_world(new_pos)
		cell.position = new_world_pos
		# Geometry is already relative, no need to update

		# Reset modulate (in case it was changed)
		cell.modulate = Color.WHITE

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)
		grid_manager.cells[new_pos] = cell

	# 8. Create seam visualization
	create_seam_visual(left_anchor, right_anchor, "horizontal")

	# 9. Record fold operation
	var fold_record = create_fold_record(left_anchor, right_anchor, removed_cells, "horizontal")
	fold_history.append(fold_record)


## Execute a vertical fold with animation (Issue #9)
##
## Same as execute_vertical_fold but with visual animations
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_vertical_fold_animated(anchor1: Vector2i, anchor2: Vector2i) -> void:
	# 1. Normalize anchor order (ensure anchor1 is topmost)
	var top_anchor = anchor1 if anchor1.y < anchor2.y else anchor2
	var bottom_anchor = anchor2 if anchor1.y < anchor2.y else anchor1

	var x = top_anchor.x  # Column where fold occurs

	# 2. Calculate removed region
	var removed_cells = calculate_removed_cells(top_anchor, bottom_anchor)

	# 3. Collect cells that need to be shifted
	var shift_distance = bottom_anchor.y - top_anchor.y
	var cells_to_shift: Array[Dictionary] = []
	for y in range(bottom_anchor.y + 1, grid_manager.grid_size.y):
		var old_pos = Vector2i(x, y)
		var cell = grid_manager.get_cell(old_pos)
		if cell:
			var new_y = y - shift_distance
			var new_pos = Vector2i(x, new_y)
			cells_to_shift.append({
				"cell": cell,
				"old_pos": old_pos,
				"new_pos": new_pos
			})

	# 4. Animate fade out of removed cells
	await fade_out_cells(removed_cells, fade_duration)

	# 5. Remove cells from grid
	for pos in removed_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			grid_manager.cells.erase(pos)
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			cell.queue_free()

	# 6. Animate cell shifting
	await shift_cells_animated(cells_to_shift, shift_duration)

	# 7. Update grid positions after animation
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos
		var new_pos = data.new_pos

		# Update cell's grid position
		cell.grid_position = new_pos

		# Update final position (geometry stays relative)
		var new_world_pos = grid_manager.grid_to_world(new_pos)
		cell.position = new_world_pos
		# Geometry is already relative, no need to update

		# Reset modulate (in case it was changed)
		cell.modulate = Color.WHITE

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)
		grid_manager.cells[new_pos] = cell

	# 8. Create seam visualization
	create_seam_visual(top_anchor, bottom_anchor, "vertical")

	# 9. Record fold operation
	var fold_record = create_fold_record(top_anchor, bottom_anchor, removed_cells, "vertical")
	fold_history.append(fold_record)


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
		return false

	# Validate with player position
	var player_validation = validate_fold_with_player(anchor1, anchor2)

	if not player_validation.valid:
		push_warning("FoldSystem: Player validation failed: " + player_validation.reason)
		return false

	var orientation = get_fold_orientation(anchor1, anchor2)

	# Set animating flag if using animations
	if animated:
		is_animating = true

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
			if animated:
				is_animating = false
			push_warning("FoldSystem: Diagonal folds not yet supported (Phase 3 limitation)")
			return false
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
