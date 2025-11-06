class_name LevelValidator
extends Node

## LevelValidator
##
## Validates level data to ensure levels are playable and well-formed.
## Checks for required elements, accessibility, and potential issues.

## Cell type constants (should match Cell.gd)
enum CellType {
	EMPTY = 0,
	WALL = 1,
	WATER = 2,
	GOAL = 3
}


## Validates a level and returns a result dictionary
## Returns: {
##   "valid": bool,
##   "errors": Array[String],
##   "warnings": Array[String]
## }
func validate_level(level_data: LevelData) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if level_data == null:
		errors.append("Level data is null")
		return {"valid": false, "errors": errors, "warnings": warnings}

	# Check grid size
	if level_data.grid_size.x <= 0 or level_data.grid_size.y <= 0:
		errors.append("Grid size must be positive (got %dx%d)" % [level_data.grid_size.x, level_data.grid_size.y])

	# Check for level ID (optional warning)
	if level_data.level_id.is_empty():
		warnings.append("Level has no ID")

	# Check player start position is set and within bounds
	if not _is_position_in_grid(level_data.player_start_position, level_data.grid_size):
		errors.append("Player start position is outside grid bounds")

	# Check if player starts on a wall
	if level_data.cell_data.has(level_data.player_start_position):
		var start_cell_type = level_data.cell_data[level_data.player_start_position]
		if start_cell_type == CellType.WALL:
			errors.append("Player cannot start on a wall")

	# Check for at least one goal cell
	var has_goal = false
	var goal_positions: Array[Vector2i] = []

	for pos in level_data.cell_data:
		var cell_type = level_data.cell_data[pos]

		# Check if position is within grid
		if not _is_position_in_grid(pos, level_data.grid_size):
			errors.append("Cell at (%d, %d) is outside grid bounds" % [pos.x, pos.y])
			continue

		# Check for valid cell types
		if cell_type < CellType.EMPTY or cell_type > CellType.GOAL:
			warnings.append("Cell at (%d, %d) has invalid type: %d" % [pos.x, pos.y, cell_type])

		# Track goal cells
		if cell_type == CellType.GOAL:
			has_goal = true
			goal_positions.append(pos)

	if not has_goal:
		errors.append("No goal cell defined")

	# Check goal reachability (warning, not error - folds might make it reachable)
	if has_goal and errors.is_empty():
		if not is_goal_reachable(level_data):
			warnings.append("Goal may not be reachable from start position (without using folds)")

	# Check fold constraints
	if level_data.max_folds > 0 and level_data.max_folds < 2:
		warnings.append("Max folds seems very restrictive (less than 2)")

	if level_data.max_folds > 0 and level_data.par_folds > level_data.max_folds:
		warnings.append("Par folds (%d) is greater than max folds (%d) - impossible to achieve par" % [level_data.par_folds, level_data.max_folds])

	# Check for very large grids (performance warning)
	var total_cells = level_data.grid_size.x * level_data.grid_size.y
	if total_cells > 400:  # 20x20
		warnings.append("Large grid size (%dx%d) may impact performance" % [level_data.grid_size.x, level_data.grid_size.y])

	return {
		"valid": errors.size() == 0,
		"errors": errors,
		"warnings": warnings
	}


## Checks if a goal is reachable from the player start position
## Uses simple BFS pathfinding (ignores folds)
## Returns true if at least one goal is reachable
func is_goal_reachable(level_data: LevelData) -> bool:
	if level_data == null:
		return false

	# Find all goal positions
	var goal_positions: Array[Vector2i] = []
	for pos in level_data.cell_data:
		if level_data.cell_data[pos] == CellType.GOAL:
			goal_positions.append(pos)

	if goal_positions.is_empty():
		return false

	# BFS from player start position
	var queue: Array[Vector2i] = [level_data.player_start_position]
	var visited: Dictionary = {}
	visited[level_data.player_start_position] = true

	var directions = [
		Vector2i(1, 0),   # Right
		Vector2i(-1, 0),  # Left
		Vector2i(0, 1),   # Down
		Vector2i(0, -1)   # Up
	]

	while queue.size() > 0:
		var current = queue.pop_front()

		# Check if we reached a goal
		if current in goal_positions:
			return true

		# Explore neighbors
		for dir in directions:
			var neighbor = current + dir

			# Check if neighbor is in bounds
			if not _is_position_in_grid(neighbor, level_data.grid_size):
				continue

			# Skip if already visited
			if visited.has(neighbor):
				continue

			# Check if neighbor is walkable (not a wall)
			var is_walkable = true
			if level_data.cell_data.has(neighbor):
				var cell_type = level_data.cell_data[neighbor]
				if cell_type == CellType.WALL:
					is_walkable = false

			if is_walkable:
				visited[neighbor] = true
				queue.append(neighbor)

	# No goal was reached
	return false


## Helper function to check if a position is within grid bounds
func _is_position_in_grid(pos: Vector2i, grid_size: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y
