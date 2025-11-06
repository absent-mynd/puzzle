extends GutTest

## Test to trace the exact execution order of merge vs shift operations

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_trace_merge_execution():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	# Track specific cells before fold
	var cell_5_0 = grid_manager.get_cell(Vector2i(5, 0))
	var cell_6_0 = grid_manager.get_cell(Vector2i(6, 0))

	print("\n=== BEFORE FOLD ===")
	print("Cell (5,0) exists: ", cell_5_0 != null)
	print("Cell (6,0) exists: ", cell_6_0 != null)
	print("Total cells: ", grid_manager.cells.size())

	# Add instrumentation to FoldSystem by monitoring grid changes
	var cells_before = {}
	for pos in grid_manager.cells.keys():
		cells_before[pos] = grid_manager.cells[pos]

	# Execute fold
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("\n=== AFTER FOLD ===")
	print("Total cells: ", grid_manager.cells.size())

	# Check what happened to tracked cells
	var found_5_0 = false
	var found_6_0 = false

	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		if cell == cell_5_0:
			print("Cell (5,0) now at position: ", pos)
			found_5_0 = true
		if cell == cell_6_0:
			print("Cell (6,0) now at position: ", pos)
			found_6_0 = true

	if not found_5_0:
		print("Cell (5,0) NOT FOUND in grid (disappeared!)")
	if not found_6_0:
		print("Cell (6,0) NOT FOUND in grid (disappeared!)")

	# Check specific positions
	print("\n=== CHECKING EXPECTED POSITIONS ===")
	print("Position (5,2) has cell: ", grid_manager.cells.has(Vector2i(5, 2)))
	print("Position (6,2) has cell: ", grid_manager.cells.has(Vector2i(6, 2)))

	# List all cells that existed before but don't exist after
	print("\n=== CELLS THAT DISAPPEARED ===")
	var disappeared = 0
	for pos in cells_before.keys():
		var cell = cells_before[pos]
		var still_exists = false
		for new_pos in grid_manager.cells.keys():
			if grid_manager.cells[new_pos] == cell:
				still_exists = true
				break
		if not still_exists:
			print("Cell at ", pos, " disappeared")
			disappeared += 1

	print("Total disappeared: ", disappeared)
