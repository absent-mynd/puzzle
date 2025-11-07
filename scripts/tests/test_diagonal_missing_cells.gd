extends GutTest

# Test to reproduce the missing cells issue at old line2 positions after shift

var grid_manager: GridManager
var fold_system: FoldSystem

func before_each():
	grid_manager = GridManager.new()
	grid_manager.grid_size = Vector2i(10, 4)  # 10 columns, 4 rows
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)

func after_each():
	if grid_manager:
		grid_manager.queue_free()
	if fold_system:
		fold_system.queue_free()

func test_diagonal_fold_with_missing_cells():
	print("\n╔════════════════════════════════════════════╗")
	print("║  REPRODUCING MISSING CELLS ISSUE          ║")
	print("║  Anchors: r2,c3 (3,2) and r0,c5 (5,0)    ║")
	print("╚════════════════════════════════════════════╝")

	var anchor1 = Vector2i(3, 2)  # row 2, col 3
	var anchor2 = Vector2i(5, 0)  # row 0, col 5

	print("\nBEFORE fold:")
	print_grid()

	# Execute the fold
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("\nAFTER fold:")
	print_grid()

	# Check the specific cells that user reported as missing
	print("\n╔════════════════════════════════════════════╗")
	print("║  CHECKING SPECIFIC POSITIONS              ║")
	print("╚════════════════════════════════════════════╝")

	# After shifting, cells from line2 should have moved
	# The user reports missing cells at positions like (3,2) and (4,3) after shift
	# Let me check all cells in the expected result region

	var expected_cells = [
		Vector2i(3, 0),
		Vector2i(3, 1),
		Vector2i(3, 2),  # User reports this as missing (!)
		Vector2i(3, 3),
		Vector2i(4, 2),
		Vector2i(4, 3),  # User reports this as missing (!)
	]

	for pos in expected_cells:
		var cell = grid_manager.get_cell(pos)
		if cell:
			print("  (%d,%d): EXISTS %s" % [pos.x, pos.y, "(partial)" if cell.is_partial else ""])
		else:
			print("  (%d,%d): MISSING ❌" % [pos.x, pos.y])

func print_grid():
	# First, find actual bounds
	var min_x = 0
	var max_x = grid_manager.grid_size.x - 1
	var min_y = 0
	var max_y = grid_manager.grid_size.y - 1

	for pos in grid_manager.cells.keys():
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y)
		max_y = max(max_y, pos.y)

	print("  Grid bounds: x=[%d, %d], y=[%d, %d]" % [min_x, max_x, min_y, max_y])
	print("  Total cells: %d" % grid_manager.cells.size())

	for y in range(min_y, max_y + 1):
		var row = "  Row %2d: " % y
		for x in range(min_x, max_x + 1):
			var cell = grid_manager.get_cell(Vector2i(x, y))
			if cell:
				if cell.is_partial:
					row += "[H]"
				else:
					row += "[X]"
			else:
				row += " ! "
		print(row)
