extends GutTest

# Detailed debugging test for diagonal fold

var grid_manager: GridManager
var fold_system: FoldSystem

func before_each():
	grid_manager = GridManager.new()
	grid_manager.grid_size = Vector2i(5, 5)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	fold_system.initialize(grid_manager)

func after_each():
	if grid_manager:
		grid_manager.queue_free()
	if fold_system:
		fold_system.queue_free()

## Test simple horizontal diagonal fold (really axis-aligned)
func test_horizontal_diagonal_fold():
	print("\n╔════════════════════════════════════════════╗")
	print("║  HORIZONTAL FOLD via execute_diagonal_fold║")
	print("║  anchor1=(1,2), anchor2=(3,2)             ║")
	print("╚════════════════════════════════════════════╝")

	var anchor1 = Vector2i(1, 2)
	var anchor2 = Vector2i(3, 2)

	print("\nBEFORE fold:")
	print_grid_row_2()

	# Call diagonal fold directly
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("\nAFTER fold:")
	print_grid_row_2()

	# Check results
	print("\nExpected after fold (anchor1 to anchor2 = 2 units):")
	print("  x=0: stationary (LEFT of line1)")
	print("  x=1: split on line1, keep left half")
	print("  x=2: REMOVED (between lines)")
	print("  x=3: shift left by 2, merge with split cell at x=1")
	print("  x=4: shift left by 2 to position x=2")

	assert_not_null(grid_manager.get_cell(Vector2i(0, 2)), "Cell at x=0 should exist")
	assert_not_null(grid_manager.get_cell(Vector2i(1, 2)), "Cell at x=1 should exist (merged)")
	# Cell x=2 might have shifted cell from x=4
	assert_not_null(grid_manager.get_cell(Vector2i(2, 2)), "Cell at x=2 should have shifted cell")

## Test with reversed anchor order
func test_horizontal_diagonal_fold_reversed():
	print("\n╔════════════════════════════════════════════╗")
	print("║  REVERSED: anchor1=(3,2), anchor2=(1,2)   ║")
	print("╚════════════════════════════════════════════╝")

	var anchor1 = Vector2i(3, 2)
	var anchor2 = Vector2i(1, 2)

	print("\nBEFORE fold:")
	print_grid_row_2()

	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("\nAFTER fold:")
	print_grid_row_2()

	print("\nExpected: SAME result as normal order!")
	print("  Both should have same cells at same positions")

	# Should have same structure as normal order
	assert_not_null(grid_manager.get_cell(Vector2i(0, 2)), "Cell at x=0 should exist")
	assert_not_null(grid_manager.get_cell(Vector2i(1, 2)), "Cell at x=1 should exist")

func print_grid_row_2():
	var row = "  Row 2: "
	for x in range(grid_manager.grid_size.x):
		var cell = grid_manager.get_cell(Vector2i(x, 2))
		if cell:
			if cell.is_partial:
				row += "[P]"
			else:
				row += "[X]"
		else:
			row += " . "
	print(row)

## Test truly diagonal fold
func test_true_diagonal_fold():
	print("\n╔════════════════════════════════════════════╗")
	print("║  TRUE DIAGONAL: anchor1=(1,1), anchor2=(3,3)║")
	print("╚════════════════════════════════════════════╝")

	var anchor1 = Vector2i(1, 1)
	var anchor2 = Vector2i(3, 3)

	var cells_before = grid_manager.cells.size()
	print("Cells before: %d" % cells_before)

	fold_system.execute_diagonal_fold(anchor1, anchor2)

	var cells_after = grid_manager.cells.size()
	print("Cells after: %d" % cells_after)
	print("Cells removed: %d" % (cells_before - cells_after))

	# Should have removed some cells
	assert_lt(cells_after, cells_before, "Should have removed some cells")
	assert_gt(cells_after, 0, "Should still have some cells")
