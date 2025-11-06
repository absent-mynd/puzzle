extends GutTest

## Debug test for cell classification

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_classify_cells_for_diagonal_fold():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	print("\n=== FOLD GEOMETRY ===")
	print("Anchor1 local: ", anchor1_local)
	print("Anchor2 local: ", anchor2_local)
	print("Normal: ", cut_lines.line1.normal)

	# Check classification of various cells
	var test_cells = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
		Vector2i(3, 3),
		Vector2i(3, 4),  # anchor1
		Vector2i(4, 3),  # anchor2
		Vector2i(4, 4),
		Vector2i(5, 5),
	]

	print("\n=== CELL CLASSIFICATIONS ===")
	for pos in test_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			var region = fold_system.classify_cell_region(cell, cut_lines)
			var center = cell.get_center()
			var side1 = GeometryCore.point_side_of_line(center, cut_lines.line1.point, cut_lines.line1.normal)
			var side2 = GeometryCore.point_side_of_line(center, cut_lines.line2.point, cut_lines.line2.normal)
			print(pos, ": center=", center, " side1=", side1, " side2=", side2, " region=", region)
