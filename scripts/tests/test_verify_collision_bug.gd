extends GutTest

## Verify that line2_split_halves collide with line1_split_halves during shift

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_line2_splits_overwrite_line1_splits():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

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

	var shift_vector = -(anchor2_local - anchor1_local)

	print("\n=== COLLISION ANALYSIS ===")
	print("Checking if line2_split_halves will collide with line1_split_halves after shift...")

	var collisions = []

	for line1_cell in cells_by_region.split_line1:
		var line1_pos = line1_cell.grid_position

		for line2_cell in cells_by_region.split_line2:
			var line2_old_center = line2_cell.get_center()
			var line2_new_center = line2_old_center + shift_vector
			var line2_new_pos = Vector2i(
				round(line2_new_center.x / cell_size),
				round(line2_new_center.y / cell_size)
			)

			if line1_pos == line2_new_pos:
				collisions.append({
					"line1_pos": line1_pos,
					"line2_old_pos": line2_cell.grid_position,
					"line2_new_pos": line2_new_pos
				})

	print("Found ", collisions.size(), " collisions:")
	for collision in collisions:
		print("  line1_split_half at ", collision.line1_pos, " will be OVERWRITTEN")
		print("    by line2_split_half shifting from ", collision.line2_old_pos, " to ", collision.line2_new_pos)

	print("\n=== BUG EXPLANATION ===")
	if collisions.size() > 0:
		print("When line2_split_halves shift, they overwrite line1_split_halves!")
		print("The collision handling code (FoldSystem.gd lines 1371-1377) FREES the existing cell.")
		print("Then in the merge phase (step 7), we try to merge with FREED cells.")
		print("This causes the line1_split_halves to be lost, and no merging happens.")
		print("\nFURTHERMORE:")
		print("Since line1_split_halves are at the same positions as some kept_left cells,")
		print("and line2_split_halves shift to those positions,")
		print("we might be accidentally freeing cells that should be kept!")

	# Check if line1_split_halves and kept_left overlap
	print("\n=== CHECKING KEPT_LEFT vs LINE1_SPLITS ===")
	for line1_cell in cells_by_region.split_line1:
		for kept_left_cell in cells_by_region.kept_left:
			if line1_cell.grid_position == kept_left_cell.grid_position:
				print("WARNING: split_line1 and kept_left both at ", line1_cell.grid_position)
