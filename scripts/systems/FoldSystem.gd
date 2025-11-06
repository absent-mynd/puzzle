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
## Returns the grid positions of all cells in the ENTIRE RECTANGULAR REGION
## between the two perpendicular lines at the anchors (not including the anchor lines themselves).
##
## For horizontal folds: Two vertical lines at anchor1.x and anchor2.x
##   - Remove ALL cells where left < x < right (across all rows)
## For vertical folds: Two horizontal lines at anchor1.y and anchor2.y
##   - Remove ALL cells where top < y < bottom (across all columns)
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
func create_seam_visual(anchor1: Vector2i, anchor2: Vector2i, orientation: String) -> void:
	var seam_line = Line2D.new()
	seam_line.width = 2.0
	seam_line.default_color = Color.CYAN

	var cell_size = grid_manager.cell_size

	# For axis-aligned folds, draw perpendicular line spanning the entire grid
	# Use LOCAL coordinates since Line2D is a child of GridManager
	if orientation == "horizontal":
		# Horizontal fold: draw VERTICAL line at the merged point (center of left anchor)
		var left_anchor = anchor1 if anchor1.x < anchor2.x else anchor2
		# Seam is at the center of the left anchor (where cells overlap/merge)
		var seam_x = left_anchor.x * cell_size + cell_size / 2

		# Span from top to bottom of grid (local coordinates)
		var top_y = 0.0
		var bottom_y = grid_manager.grid_size.y * cell_size

		seam_line.points = PackedVector2Array([
			Vector2(seam_x, top_y),
			Vector2(seam_x, bottom_y)
		])
	elif orientation == "vertical":
		# Vertical fold: draw HORIZONTAL line at the merged point (center of top anchor)
		var top_anchor = anchor1 if anchor1.y < anchor2.y else anchor2
		# Seam is at the center of the top anchor (where cells overlap/merge)
		var seam_y = top_anchor.y * cell_size + cell_size / 2

		# Span from left to right of grid (local coordinates)
		var left_x = 0.0
		var right_x = grid_manager.grid_size.x * cell_size

		seam_line.points = PackedVector2Array([
			Vector2(left_x, seam_y),
			Vector2(right_x, seam_y)
		])

	# Add to scene tree
	grid_manager.add_child(seam_line)
	seam_lines.append(seam_line)


## Remove seam lines that fall within the removed region
##
## For horizontal folds, removes vertical seams in the removed column range
## For vertical folds, removes horizontal seams in the removed row range
##
## @param start_coord: Start coordinate (x for horizontal, y for vertical)
## @param end_coord: End coordinate (x for horizontal, y for vertical)
## @param seam_orientation: Orientation of seams to check ("vertical" or "horizontal")
func remove_seams_in_removed_region(start_coord: int, end_coord: int, seam_orientation: String) -> void:
	var cell_size = grid_manager.cell_size
	var seams_to_remove: Array[Line2D] = []

	for seam in seam_lines:
		if not seam or not is_instance_valid(seam):
			continue

		# Get seam position based on orientation
		if seam_orientation == "vertical":
			# Vertical seams - check x position
			var seam_x = seam.points[0].x
			# Seam coordinates are already in local coordinates (relative to GridManager)
			var seam_grid_x = int(seam_x / cell_size + 0.5)

			# Remove if seam is between the anchors (exclusive)
			if seam_grid_x > start_coord and seam_grid_x < end_coord:
				seams_to_remove.append(seam)
		elif seam_orientation == "horizontal":
			# Horizontal seams - check y position
			var seam_y = seam.points[0].y
			# Seam coordinates are already in local coordinates (relative to GridManager)
			var seam_grid_y = int(seam_y / cell_size + 0.5)

			# Remove if seam is between the anchors (exclusive)
			if seam_grid_y > start_coord and seam_grid_y < end_coord:
				seams_to_remove.append(seam)

	# Remove the seams
	for seam in seams_to_remove:
		seam_lines.erase(seam)
		seam.queue_free()


## Shift seam lines after cells have been shifted
##
## @param shift_amount: Number of cells to shift
## @param fold_orientation: Direction of fold ("horizontal" or "vertical")
func shift_seam_lines(shift_amount: int, fold_orientation: String) -> void:
	var cell_size = grid_manager.cell_size
	var shift_pixels = shift_amount * cell_size

	for seam in seam_lines:
		if not seam or not is_instance_valid(seam):
			continue

		# Shift seams perpendicular to fold direction
		if fold_orientation == "horizontal":
			# Horizontal fold shifts cells left/right, so shift vertical seams
			var new_points = PackedVector2Array()
			for point in seam.points:
				new_points.append(Vector2(point.x - shift_pixels, point.y))
			seam.points = new_points
		elif fold_orientation == "vertical":
			# Vertical fold shifts cells up/down, so shift horizontal seams
			var new_points = PackedVector2Array()
			for point in seam.points:
				new_points.append(Vector2(point.x, point.y - shift_pixels))
			seam.points = new_points


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
	# 1. Normalize anchor order (ensure anchor1 is leftmost)
	var left_anchor = anchor1 if anchor1.x < anchor2.x else anchor2
	var right_anchor = anchor2 if anchor1.x < anchor2.x else anchor1

	# 2. Calculate removed region (entire rectangular region)
	var removed_cells = calculate_removed_cells(left_anchor, right_anchor)

	# 3. Remove cells from grid and clean up seam lines
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

	# Remove seam lines that are in the removed column range
	remove_seams_in_removed_region(left_anchor.x, right_anchor.x, "vertical")

	# 4. Shift ALL cells from right_anchor onwards (across ALL rows)
	# Cells overlap at the left anchor (merging behavior)
	var shift_distance = right_anchor.x - left_anchor.x

	# Collect cells that need to be shifted
	var cells_to_shift: Array[Dictionary] = []
	for y in range(grid_manager.grid_size.y):
		for x in range(right_anchor.x, grid_manager.grid_size.x):
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

		# Update local position (recalculate geometry using local coords, not world coords!)
		# Cells are children of GridManager, so geometry should be relative to GridManager
		var new_local_pos = Vector2(new_pos) * grid_manager.cell_size
		var cell_size = grid_manager.cell_size
		cell.geometry = PackedVector2Array([
			new_local_pos,
			new_local_pos + Vector2(cell_size, 0),
			new_local_pos + Vector2(cell_size, cell_size),
			new_local_pos + Vector2(0, cell_size)
		])
		cell.update_visual()

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)

		# Remove any existing cell at the target position (overlapping/merging)
		var existing_cell = grid_manager.cells.get(new_pos)
		if existing_cell:
			grid_manager.cells.erase(new_pos)
			if existing_cell.get_parent():
				existing_cell.get_parent().remove_child(existing_cell)
			existing_cell.queue_free()

		grid_manager.cells[new_pos] = cell

	# 5. Update player position if in shifted region
	if player and player.grid_position.x >= right_anchor.x:
		player.grid_position.x -= shift_distance
		# Update player's world position to match new grid position
		var new_cell = grid_manager.get_cell(player.grid_position)
		if new_cell:
			# Convert from local coordinates (relative to GridManager) to world coordinates
			player.global_position = grid_manager.to_global(new_cell.get_center())

	# 6. Record fold operation
	var fold_record = create_fold_record(left_anchor, right_anchor, removed_cells, "horizontal")
	fold_history.append(fold_record)


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
	# 1. Normalize anchor order (ensure anchor1 is topmost)
	var top_anchor = anchor1 if anchor1.y < anchor2.y else anchor2
	var bottom_anchor = anchor2 if anchor1.y < anchor2.y else anchor1

	# 2. Calculate removed region (entire rectangular region)
	var removed_cells = calculate_removed_cells(top_anchor, bottom_anchor)

	# 3. Remove cells from grid and clean up seam lines
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

	# Remove seam lines that are in the removed row range
	remove_seams_in_removed_region(top_anchor.y, bottom_anchor.y, "horizontal")

	# 4. Shift ALL cells from bottom_anchor onwards (across ALL columns)
	# Cells overlap at the top anchor (merging behavior)
	var shift_distance = bottom_anchor.y - top_anchor.y

	# Collect cells that need to be shifted
	var cells_to_shift: Array[Dictionary] = []
	for x in range(grid_manager.grid_size.x):
		for y in range(bottom_anchor.y, grid_manager.grid_size.y):
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

		# Update local position (recalculate geometry using local coords, not world coords!)
		# Cells are children of GridManager, so geometry should be relative to GridManager
		var new_local_pos = Vector2(new_pos) * grid_manager.cell_size
		var cell_size = grid_manager.cell_size
		cell.geometry = PackedVector2Array([
			new_local_pos,
			new_local_pos + Vector2(cell_size, 0),
			new_local_pos + Vector2(cell_size, cell_size),
			new_local_pos + Vector2(0, cell_size)
		])
		cell.update_visual()

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)

		# Remove any existing cell at the target position (overlapping/merging)
		var existing_cell = grid_manager.cells.get(new_pos)
		if existing_cell:
			grid_manager.cells.erase(new_pos)
			if existing_cell.get_parent():
				existing_cell.get_parent().remove_child(existing_cell)
			existing_cell.queue_free()

		grid_manager.cells[new_pos] = cell

	# 5. Update player position if in shifted region
	if player and player.grid_position.y >= bottom_anchor.y:
		player.grid_position.y -= shift_distance
		# Update player's world position to match new grid position
		var new_cell = grid_manager.get_cell(player.grid_position)
		if new_cell:
			# Convert from local coordinates (relative to GridManager) to world coordinates
			player.global_position = grid_manager.to_global(new_cell.get_center())

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

	# 2. Calculate removed region (entire rectangular region)
	var removed_cells = calculate_removed_cells(left_anchor, right_anchor)

	# 3. Collect ALL cells that need to be shifted (across ALL rows)
	# Cells overlap at the left anchor (merging behavior)
	var shift_distance = right_anchor.x - left_anchor.x
	var cells_to_shift: Array[Dictionary] = []
	for y in range(grid_manager.grid_size.y):
		for x in range(right_anchor.x, grid_manager.grid_size.x):
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

	# 5. Remove cells from grid and clean up seam lines
	for pos in removed_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			grid_manager.cells.erase(pos)
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			cell.queue_free()

	# Remove seam lines that are in the removed column range
	remove_seams_in_removed_region(left_anchor.x, right_anchor.x, "vertical")
	# Shift remaining seam lines
	shift_seam_lines(shift_distance, "horizontal")

	# 6. Animate cell shifting
	await shift_cells_animated(cells_to_shift, shift_duration)

	# 7. Update grid positions after animation
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos
		var new_pos = data.new_pos

		# Update cell's grid position
		cell.grid_position = new_pos

		# Update final geometry using local coordinates
		var new_local_pos = Vector2(new_pos) * grid_manager.cell_size
		var cell_size = grid_manager.cell_size
		cell.geometry = PackedVector2Array([
			new_local_pos,
			new_local_pos + Vector2(cell_size, 0),
			new_local_pos + Vector2(cell_size, cell_size),
			new_local_pos + Vector2(0, cell_size)
		])
		cell.update_visual()

		# Reset modulate (in case it was changed)
		cell.modulate = Color.WHITE

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)

		# Remove any existing cell at the target position (overlapping/merging)
		var existing_cell = grid_manager.cells.get(new_pos)
		if existing_cell:
			grid_manager.cells.erase(new_pos)
			if existing_cell.get_parent():
				existing_cell.get_parent().remove_child(existing_cell)
			existing_cell.queue_free()

		grid_manager.cells[new_pos] = cell

	# 8. Update player position if in shifted region
	if player and player.grid_position.x >= right_anchor.x:
		player.grid_position.x -= shift_distance
		# Update player's world position to match new grid position
		var new_cell = grid_manager.get_cell(player.grid_position)
		if new_cell:
			# Convert from local coordinates (relative to GridManager) to world coordinates
			player.global_position = grid_manager.to_global(new_cell.get_center())

	# 9. Create seam visualization
	create_seam_visual(left_anchor, right_anchor, "horizontal")

	# 10. Record fold operation
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

	# 2. Calculate removed region (entire rectangular region)
	var removed_cells = calculate_removed_cells(top_anchor, bottom_anchor)

	# 3. Collect ALL cells that need to be shifted (across ALL columns)
	# Cells overlap at the top anchor (merging behavior)
	var shift_distance = bottom_anchor.y - top_anchor.y
	var cells_to_shift: Array[Dictionary] = []
	for x in range(grid_manager.grid_size.x):
		for y in range(bottom_anchor.y, grid_manager.grid_size.y):
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

	# 5. Remove cells from grid and clean up seam lines
	for pos in removed_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			grid_manager.cells.erase(pos)
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			cell.queue_free()

	# Remove seam lines that are in the removed row range
	remove_seams_in_removed_region(top_anchor.y, bottom_anchor.y, "horizontal")
	# Shift remaining seam lines
	shift_seam_lines(shift_distance, "vertical")

	# 6. Animate cell shifting
	await shift_cells_animated(cells_to_shift, shift_duration)

	# 7. Update grid positions after animation
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos
		var new_pos = data.new_pos

		# Update cell's grid position
		cell.grid_position = new_pos

		# Update final geometry using local coordinates
		var new_local_pos = Vector2(new_pos) * grid_manager.cell_size
		var cell_size = grid_manager.cell_size
		cell.geometry = PackedVector2Array([
			new_local_pos,
			new_local_pos + Vector2(cell_size, 0),
			new_local_pos + Vector2(cell_size, cell_size),
			new_local_pos + Vector2(0, cell_size)
		])
		cell.update_visual()

		# Reset modulate (in case it was changed)
		cell.modulate = Color.WHITE

		# Update grid manager's dictionary
		grid_manager.cells.erase(old_pos)

		# Remove any existing cell at the target position (overlapping/merging)
		var existing_cell = grid_manager.cells.get(new_pos)
		if existing_cell:
			grid_manager.cells.erase(new_pos)
			if existing_cell.get_parent():
				existing_cell.get_parent().remove_child(existing_cell)
			existing_cell.queue_free()

		grid_manager.cells[new_pos] = cell

	# 8. Update player position if in shifted region
	if player and player.grid_position.y >= bottom_anchor.y:
		player.grid_position.y -= shift_distance
		# Update player's world position to match new grid position
		var new_cell = grid_manager.get_cell(player.grid_position)
		if new_cell:
			# Convert from local coordinates (relative to GridManager) to world coordinates
			player.global_position = grid_manager.to_global(new_cell.get_center())

	# 9. Create seam visualization
	create_seam_visual(top_anchor, bottom_anchor, "vertical")

	# 10. Record fold operation
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


## Shift a cell's geometry by a vector
##
## Updates both the geometry coordinates and recalculates the grid position
## based on the new center.
##
## @param cell: The cell to shift
## @param shift_vector: The translation vector (in local coordinates)
func shift_cell_geometry(cell: Cell, shift_vector: Vector2) -> void:
	# Shift all geometry vertices
	var new_geometry = PackedVector2Array()
	for vertex in cell.geometry:
		new_geometry.append(vertex + shift_vector)
	cell.geometry = new_geometry

	# Recalculate grid position based on new center
	var new_center = cell.get_center()
	var cell_size = grid_manager.cell_size
	cell.grid_position = Vector2i(
		round(new_center.x / cell_size),
		round(new_center.y / cell_size)
	)

	# Update visual
	cell.update_visual()


## Check if two cells should merge after a diagonal fold
##
## Two cells should merge if they're at the same grid position after shifting
## and their geometries are adjacent or overlapping.
##
## @param cell1: First cell
## @param cell2: Second cell
## @return: true if cells should merge
func should_merge_cells(cell1: Cell, cell2: Cell) -> bool:
	# Must be at same grid position (after shifting)
	if cell1.grid_position != cell2.grid_position:
		return false

	# Must not be the same cell
	if cell1 == cell2:
		return false

	# Cells at same grid position should merge
	return true


## Merge two cells that have been brought together by a fold
##
## Combines their geometries and metadata, creating a merged cell.
## The merge is performed in-place on cell1, and cell2 is freed.
##
## @param cell1: First cell (will become the merged result)
## @param cell2: Second cell (will be freed)
## @param merge_line: The line where cells merge (from cut_lines.line1)
## @param fold_id: ID of the fold creating this merge
## @return: The merged cell (same as cell1)
func merge_cells(cell1: Cell, cell2: Cell, merge_line: Dictionary, fold_id: int) -> Cell:
	# Safety checks
	if not cell1 or not cell2:
		push_error("merge_cells called with null cell")
		return cell1 if cell1 else null
	if cell1 == cell2:
		push_error("merge_cells called with same cell twice")
		return cell1
	# For now, use simple geometry union: take all unique vertices
	# In the future, this could use proper polygon union algorithms
	var merged_geometry = cell1.geometry.duplicate()

	# Add vertices from cell2 that aren't already in merged_geometry
	var epsilon = 0.001
	for vertex in cell2.geometry:
		var is_duplicate = false
		for existing in merged_geometry:
			if vertex.distance_to(existing) < epsilon:
				is_duplicate = true
				break
		if not is_duplicate:
			merged_geometry.append(vertex)

	# Sort vertices by angle from centroid to create proper polygon
	var centroid = Vector2.ZERO
	for v in merged_geometry:
		centroid += v
	centroid /= merged_geometry.size()

	# Sort by angle - convert to Array first since PackedVector2Array doesn't have sort_custom
	var vertices_array: Array = []
	for v in merged_geometry:
		vertices_array.append(v)

	vertices_array.sort_custom(func(a, b):
		var angle_a = (a - centroid).angle()
		var angle_b = (b - centroid).angle()
		return angle_a < angle_b
	)

	# Convert back to PackedVector2Array
	var sorted_vertices = PackedVector2Array()
	for v in vertices_array:
		sorted_vertices.append(v)

	# Determine merged cell type (prioritize non-empty types)
	var merged_type = max(cell1.cell_type, cell2.cell_type)

	# Create merge metadata for undo support
	var merge_metadata = {
		"type": "merge",
		"fold_id": fold_id,
		"merged_from": [cell1.grid_position, cell2.grid_position],
		"left_type": cell1.cell_type,
		"right_type": cell2.cell_type,
		"merge_line": merge_line,
		"timestamp": Time.get_ticks_msec()
	}

	# Update cell1 to be the merged result
	cell1.geometry = sorted_vertices
	cell1.cell_type = merged_type
	cell1.add_seam(merge_metadata)
	cell1.update_visual()

	# Remove cell2 from grid
	grid_manager.cells.erase(cell2.grid_position)
	if cell2.get_parent():
		cell2.get_parent().remove_child(cell2)
	cell2.queue_free()

	return cell1


## Execute a diagonal fold (Phase 4)
##
## This is the most complex fold operation, handling arbitrary angles.
## Implements full cell merging and grid shifting.
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
func execute_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i):
	# Convert to LOCAL coordinates (cell centers)
	# Cells use LOCAL coordinates relative to GridManager
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	# 1. Calculate cut lines (using LOCAL coordinates)
	var cut_lines = calculate_cut_lines(anchor1_local, anchor2_local)

	# 2. Classify all cells
	var cells_by_region = {
		"kept_left": [],
		"removed": [],
		"kept_right": [],
		"split_line1": [],
		"split_line2": []
	}

	for pos in grid_manager.cells.keys():
		var cell = grid_manager.get_cell(pos)
		if cell:
			var region = classify_cell_region(cell, cut_lines)
			cells_by_region[region].append(cell)

	# 3. Process split cells and store halves for merging
	var line1_split_halves: Array[Cell] = []  # Will merge with line2 halves
	var line2_split_halves: Array[Cell] = []  # Will merge with line1 halves

	for cell in cells_by_region.split_line1:
		var split_result = GeometryCore.split_polygon_by_line(
			cell.geometry, cut_lines.line1.point, cut_lines.line1.normal
		)
		if split_result.intersections.size() > 0:
			# Keep the left half (negative side of normal, away from removed region)
			# Line1 is at the start of the removed region
			var new_cell = cell.apply_split(split_result, cut_lines.line1.point, cut_lines.line1.normal, "left")
			if new_cell:
				# New cell (right half) goes to removed region
				new_cell.queue_free()
			# Cell now contains left half - store for merging
			line1_split_halves.append(cell)

	for cell in cells_by_region.split_line2:
		var split_result = GeometryCore.split_polygon_by_line(
			cell.geometry, cut_lines.line2.point, cut_lines.line2.normal
		)
		if split_result.intersections.size() > 0:
			# Keep the right half (positive side of normal, away from removed region)
			# Line2 is at the end of the removed region
			var new_cell = cell.apply_split(split_result, cut_lines.line2.point, cut_lines.line2.normal, "right")
			if new_cell:
				# New cell (left half) goes to removed region
				new_cell.queue_free()
			# Cell now contains right half - store for merging
			line2_split_halves.append(cell)

	# 4. Remove cells in removed region
	var removed_cells: Array[Vector2i] = []
	for cell in cells_by_region.removed:
		removed_cells.append(cell.grid_position)
		grid_manager.cells.erase(cell.grid_position)
		if cell.get_parent():
			cell.get_parent().remove_child(cell)
		cell.queue_free()

	# 5. Calculate shift vector to collapse the removed region
	# We bring line2 to line1 by shifting along the fold vector
	var shift_vector = -(anchor2_local - anchor1_local)

	# 6. Apply shift to kept_right region (including line2 split halves)
	# Store old positions before shifting to avoid dictionary iteration issues
	var cells_to_shift: Array[Dictionary] = []
	for cell in cells_by_region.kept_right:
		cells_to_shift.append({"cell": cell, "old_pos": cell.grid_position})
	for cell in line2_split_halves:
		cells_to_shift.append({"cell": cell, "old_pos": cell.grid_position})

	# Now shift all cells
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos

		# Remove from old position
		grid_manager.cells.erase(old_pos)

		# Apply shift
		shift_cell_geometry(cell, shift_vector)

		# Handle collision at new position
		var existing_cell = grid_manager.cells.get(cell.grid_position)
		if existing_cell and existing_cell != cell:
			# Free the existing cell - it will be replaced
			grid_manager.cells.erase(cell.grid_position)
			if existing_cell.get_parent():
				existing_cell.get_parent().remove_child(existing_cell)
			existing_cell.queue_free()

		# Add to new position
		grid_manager.cells[cell.grid_position] = cell

	# 7. Merge split halves that are now at the same position
	for left_half in line1_split_halves:
		for right_half in line2_split_halves:
			if should_merge_cells(left_half, right_half):
				var merged = merge_cells(left_half, right_half, cut_lines.line1, next_fold_id)
				# Update grid_manager's reference
				grid_manager.cells[merged.grid_position] = merged
				break  # Only merge once per left_half

	# 8. Update player position if in shifted region
	if player:
		var player_local = grid_manager.to_local(player.global_position)
		var player_side = GeometryCore.point_side_of_line(player_local, cut_lines.line2.point, cut_lines.line2.normal)
		if player_side > 0:  # Player is in shifted region
			player.global_position = grid_manager.to_global(player_local + shift_vector)
			# Recalculate grid position
			var player_center_local = grid_manager.to_local(player.global_position)
			player.grid_position = Vector2i(
				round(player_center_local.x / cell_size),
				round(player_center_local.y / cell_size)
			)

	# 9. Create seam visualization at merge line (line1, where line2 was brought to)
	var seam_line = Line2D.new()
	seam_line.width = 2.0
	seam_line.default_color = Color.CYAN

	# Draw seam along fold axis at line1 position
	var seam_start = cut_lines.line1.point - cut_lines.line1.normal * 1000
	var seam_end = cut_lines.line1.point + cut_lines.line1.normal * 1000
	seam_line.points = PackedVector2Array([seam_start, seam_end])

	grid_manager.add_child(seam_line)
	seam_lines.append(seam_line)

	# 10. Record fold operation
	var fold_record = create_fold_record(anchor1, anchor2, removed_cells, "diagonal")
	fold_history.append(fold_record)
