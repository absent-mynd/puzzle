extends GutTest

## Add temporary logging to FoldSystem to debug shift loop

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_check_shift_with_logging():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	# Track cells before
	var cells_before = {}
	for pos in grid_manager.cells.keys():
		cells_before[pos] = grid_manager.cells[pos]

	print("\n=== CELLS BEFORE FOLD ===")
	print("Total: ", cells_before.size())

	# Execute fold (this will have the bug)
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("\n=== CELLS AFTER FOLD ===")
	print("Total: ", grid_manager.cells.size())

	# Check which cells still exist
	var survived = 0
	var disappeared = 0

	for old_pos in cells_before.keys():
		var cell = cells_before[old_pos]
		var found = false
		for new_pos in grid_manager.cells.keys():
			if grid_manager.cells[new_pos] == cell:
				found = true
				if new_pos != old_pos:
					print("Cell moved: ", old_pos, " -> ", new_pos)
				break
		if found:
			survived += 1
		else:
			disappeared += 1

	print("\nSurvived: ", survived)
	print("Disappeared: ", disappeared)

	# The issue: We need to manually trace through the shift loop
	# Let me check if cells_to_shift is correctly populated
	print("\n=== MANUAL EXECUTION TRACE ===")

	# Re-create the classification
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	# Hypothesis: Maybe line2_split_halves are including kept_right cells?
	# Or maybe classification is wrong?

	print("Need to add logging INSIDE execute_diagonal_fold to see what's happening")
	print("The issue is that cells disappear during execute_diagonal_fold")
	print("But we can't see what's happening inside the shift loop")
