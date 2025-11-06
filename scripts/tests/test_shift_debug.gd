extends GutTest

## Debug shifting to see where cells go

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_track_shift_details():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	print("\n=== SHIFT CALCULATION ===")
	print("Anchor1 local: ", anchor1_local)
	print("Anchor2 local: ", anchor2_local)

	var shift_vector = -(anchor2_local - anchor1_local)
	print("Shift vector: ", shift_vector)
	print("  = -(", anchor2_local - anchor1_local, ")")

	# Track a specific kept_right cell
	var test_cell_pos = Vector2i(5, 0)
	var test_cell = grid_manager.get_cell(test_cell_pos)

	if test_cell:
		var old_center = test_cell.get_center()
		print("\n=== BEFORE SHIFT ===")
		print("Cell ", test_cell_pos)
		print("  Old center: ", old_center)
		print("  Old grid_position: ", test_cell.grid_position)

		# Simulate the shift
		var new_center_predicted = old_center + shift_vector
		var new_grid_pos_predicted = Vector2i(
			round(new_center_predicted.x / cell_size),
			round(new_center_predicted.y / cell_size)
		)

		print("\n=== PREDICTED AFTER SHIFT ===")
		print("  New center: ", new_center_predicted)
		print("  New grid_position: ", new_grid_pos_predicted)
		print("  Out of bounds?: ",
			new_grid_pos_predicted.x < 0 or new_grid_pos_predicted.x >= grid_manager.grid_size.x or
			new_grid_pos_predicted.y < 0 or new_grid_pos_predicted.y >= grid_manager.grid_size.y)

	# Now actually execute
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("\n=== AFTER ACTUAL FOLD ===")
	print("Grid has cell at ", test_cell_pos, "?: ", grid_manager.cells.has(test_cell_pos))

	# Check if cell ended up somewhere else
	print("\nSearching for cell in grid...")
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.get_cell(pos)
		if cell == test_cell:
			print("Found at position: ", pos, " center=", cell.get_center())
			return

	print("Cell not found anywhere in grid!")
