extends GutTest

## Check if classified cells are actually processed

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_verify_kept_right_cells_are_shifted():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	# Check specific cells that user reported missing
	var problem_cells = [
		Vector2i(5, 0),
		Vector2i(6, 0),
		Vector2i(5, 1),
		Vector2i(2, 0),
	]

	print("\n=== CLASSIFICATION CHECK ===")
	for pos in problem_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			var region = fold_system.classify_cell_region(cell, cut_lines)
			var center = cell.get_center()
			var side1 = GeometryCore.point_side_of_line(center, cut_lines.line1.point, cut_lines.line1.normal)
			var side2 = GeometryCore.point_side_of_line(center, cut_lines.line2.point, cut_lines.line2.normal)
			print(pos, ": region=", region, " side1=", side1, " side2=", side2, " center=", center)

	# Now let's manually simulate what execute_diagonal_fold does
	print("\n=== SIMULATING FOLD LOGIC ===")

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

	print("Classification counts:")
	print("  kept_left: ", cells_by_region.kept_left.size())
	print("  kept_right: ", cells_by_region.kept_right.size())
	print("  removed: ", cells_by_region.removed.size())
	print("  split_line1: ", cells_by_region.split_line1.size())
	print("  split_line2: ", cells_by_region.split_line2.size())

	# Check if our problem cells are in kept_right
	print("\n=== CHECKING IF PROBLEM CELLS ARE IN KEPT_RIGHT ===")
	for prob_pos in problem_cells:
		var prob_cell = grid_manager.get_cell(prob_pos)
		if prob_cell:
			var found_in_kept_right = false
			for cell in cells_by_region.kept_right:
				if cell == prob_cell:
					found_in_kept_right = true
					break
			print(prob_pos, ": in kept_right list? ", found_in_kept_right)
