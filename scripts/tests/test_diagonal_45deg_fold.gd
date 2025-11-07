extends GutTest

# Test 45-degree diagonal fold to see if the bug appears there

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

func print_full_grid(title: String):
	print("\n=== %s ===" % title)
	for y in range(grid_manager.grid_size.y):
		var row = "  "
		for x in range(grid_manager.grid_size.x):
			var cell = grid_manager.get_cell(Vector2i(x, y))
			if cell:
				row += "[X]"
			else:
				row += " . "
		print("Row %d: %s" % [y, row])
	print("Total cells: %d" % grid_manager.cells.size())

## Test 45-degree fold: anchor1=(1,1), anchor2=(3,3)
func test_diagonal_45_normal():
	print("\n╔════════════════════════════════════════════╗")
	print("║  45° DIAGONAL FOLD: Normal Order          ║")
	print("║  anchor1=(1,1), anchor2=(3,3)             ║")
	print("╚════════════════════════════════════════════╝")

	var anchor1 = Vector2i(1, 1)
	var anchor2 = Vector2i(3, 3)

	# Calculate cut lines to understand the geometry
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	print("\nCut line geometry:")
	print("  anchor1_local: %s" % anchor1_local)
	print("  anchor2_local: %s" % anchor2_local)
	print("  fold_vector: %s" % (anchor2_local - anchor1_local))
	print("  fold_normal: %s" % cut_lines.line1.normal)

	print_full_grid("BEFORE fold")

	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print_full_grid("AFTER fold")

	# Count cells
	var cells_before = 25
	var cells_after = grid_manager.cells.size()
	print("\nCells removed: %d" % (cells_before - cells_after))

## Test 45-degree fold with REVERSED anchors
func test_diagonal_45_reversed():
	print("\n╔════════════════════════════════════════════╗")
	print("║  45° DIAGONAL FOLD: REVERSED Order        ║")
	print("║  anchor1=(3,3), anchor2=(1,1)             ║")
	print("║  (This might trigger the bug!)             ║")
	print("╚════════════════════════════════════════════╝")

	var anchor1 = Vector2i(3, 3)
	var anchor2 = Vector2i(1, 1)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	print("\nCut line geometry:")
	print("  anchor1_local: %s" % anchor1_local)
	print("  anchor2_local: %s" % anchor2_local)
	print("  fold_vector: %s" % (anchor2_local - anchor1_local))
	print("  fold_normal: %s" % cut_lines.line1.normal)

	print_full_grid("BEFORE fold")

	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print_full_grid("AFTER fold")

	# Analyze which region has cells
	print("\nCell distribution analysis:")
	var top_left_cells = 0  # x<2, y<2
	var bottom_right_cells = 0  # x>2, y>2
	var middle_cells = 0  # around the diagonal

	for pos in grid_manager.cells.keys():
		if pos.x < 2 and pos.y < 2:
			top_left_cells += 1
		elif pos.x > 2 and pos.y > 2:
			bottom_right_cells += 1
		else:
			middle_cells += 1

	print("  Top-left quadrant (x<2, y<2): %d cells" % top_left_cells)
	print("  Bottom-right quadrant (x>2, y>2): %d cells" % bottom_right_cells)
	print("  Middle/diagonal cells: %d cells" % middle_cells)

	# Check specific cells that might disappear
	print("\nChecking specific cells:")
	for test_pos in [Vector2i(0,0), Vector2i(0,1), Vector2i(1,0), Vector2i(4,4), Vector2i(4,3), Vector2i(3,4)]:
		var cell = grid_manager.get_cell(test_pos)
		var status = "EXISTS" if cell else "MISSING ❌"
		print("  Cell %s: %s" % [test_pos, status])
