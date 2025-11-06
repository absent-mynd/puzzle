extends GutTest

## Detailed trace of shift operation to find where cells disappear

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_manual_simulation_of_fold():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	# Calculate cut lines
	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	print("\n=== CUT LINES ===")
	print("Line1 point: ", cut_lines.line1.point)
	print("Line1 normal: ", cut_lines.line1.normal)
	print("Line2 point: ", cut_lines.line2.point)
	print("Line2 normal: ", cut_lines.line2.normal)

	# Classify cells
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
			var region = fold_system.classify_cell_region(cell, cut_lines)
			cells_by_region[region].append(cell)

	print("\n=== CLASSIFICATION ===")
	print("kept_left: ", cells_by_region.kept_left.size())
	print("kept_right: ", cells_by_region.kept_right.size())
	print("removed: ", cells_by_region.removed.size())
	print("split_line1: ", cells_by_region.split_line1.size())
	print("split_line2: ", cells_by_region.split_line2.size())

	# Calculate shift vector
	var shift_vector = -(anchor2_local - anchor1_local)
	print("\n=== SHIFT VECTOR ===")
	print("Shift vector: ", shift_vector)
	print("Shift in cells: ", shift_vector / cell_size)

	# Track specific cells
	var track_cells = [Vector2i(5, 0), Vector2i(6, 0), Vector2i(5, 1)]
	print("\n=== TRACKING SPECIFIC CELLS ===")
	for pos in track_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			var region = fold_system.classify_cell_region(cell, cut_lines)
			var is_in_kept_right = cell in cells_by_region.kept_right
			print(pos, ": region=", region, ", in kept_right list=", is_in_kept_right)

	# Simulate shift phase
	print("\n=== SIMULATING SHIFT PHASE ===")
	var cells_to_shift: Array[Dictionary] = []
	for cell in cells_by_region.kept_right:
		cells_to_shift.append({"cell": cell, "old_pos": cell.grid_position})

	print("Number of cells to shift: ", cells_to_shift.size())

	# Check if tracked cells are in the list
	for pos in track_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			var found = false
			for data in cells_to_shift:
				if data.cell == cell:
					found = true
					print(pos, " is in cells_to_shift")
					break
			if not found:
				print(pos, " is NOT in cells_to_shift")

	# Now simulate what happens during shift
	print("\n=== SIMULATING CELL SHIFTS ===")
	var shift_index = 0
	for data in cells_to_shift:
		var cell = data.cell
		var old_pos = data.old_pos

		# Track our specific cells
		var is_tracked = old_pos in track_cells
		if is_tracked or shift_index < 5:
			# Calculate new position
			var old_center = cell.get_center()
			var new_center = old_center + shift_vector
			var new_grid_pos = Vector2i(
				round(new_center.x / cell_size),
				round(new_center.y / cell_size)
			)

			# Check for collision
			var existing_cell = grid_manager.cells.get(old_pos)
			if existing_cell == cell:
				print("Shift #", shift_index, ": ", old_pos, " -> ", new_grid_pos)
				if is_tracked:
					print("  [TRACKED CELL]")
			shift_index += 1

	print("\n=== KEY QUESTION ===")
	print("Do any kept_right cells shift to positions occupied by line1_split_halves?")
	print("Line1 split halves (NOT shifted):")
	for cell in cells_by_region.split_line1:
		print("  Position: ", cell.grid_position)

	print("\nLine2 split halves (WILL BE shifted):")
	print("Before shift:")
	for cell in cells_by_region.split_line2:
		print("  Position: ", cell.grid_position)

	print("After shift (predicted):")
	for cell in cells_by_region.split_line2:
		var old_center = cell.get_center()
		var new_center = old_center + shift_vector
		var new_grid_pos = Vector2i(
			round(new_center.x / cell_size),
			round(new_center.y / cell_size)
		)
		print("  ", cell.grid_position, " -> ", new_grid_pos)

	print("\n=== COLLISION CHECK ===")
	# Check if any kept_right cell will collide with a line2_split_half after both are shifted
	for data in cells_to_shift:
		var cell = data.cell
		if cell in cells_by_region.kept_right:
			var old_center = cell.get_center()
			var new_center = old_center + shift_vector
			var new_grid_pos = Vector2i(
				round(new_center.x / cell_size),
				round(new_center.y / cell_size)
			)

			# Check if any line2_split_half will shift to same position
			for split_cell in cells_by_region.split_line2:
				var split_old_center = split_cell.get_center()
				var split_new_center = split_old_center + shift_vector
				var split_new_grid_pos = Vector2i(
					round(split_new_center.x / cell_size),
					round(split_new_center.y / cell_size)
				)

				if new_grid_pos == split_new_grid_pos:
					print("COLLISION: kept_right cell at ", cell.grid_position, " and line2_split_half at ", split_cell.grid_position)
					print("  Both shift to: ", new_grid_pos)
