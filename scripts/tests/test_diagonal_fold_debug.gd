extends GutTest

## Debug test for diagonal fold cell disappearance
## Testing fold from r4,c3 to r3,c4 (0-indexed: (3,4) to (4,3))

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_diagonal_fold_cell_tracking():
	# User reported fold: r4,c3 to r3,c4
	# Assuming 0-indexed grid positions
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	print("\n=== BEFORE FOLD ===")
	print("Total cells: ", grid_manager.cells.size())
	print("Grid size: ", grid_manager.grid_size)

	# Count cells in various regions
	var cells_before = {}
	for pos in grid_manager.cells.keys():
		cells_before[pos] = grid_manager.get_cell(pos)

	# Execute fold
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("\n=== AFTER FOLD ===")
	print("Total cells: ", grid_manager.cells.size())

	# Check what happened to each cell
	var kept = 0
	var removed = 0
	for pos in cells_before.keys():
		var still_exists = false
		# Check if cell still exists anywhere in grid
		for new_pos in grid_manager.cells.keys():
			if grid_manager.cells[new_pos] == cells_before[pos]:
				still_exists = true
				if new_pos != pos:
					print("Cell moved from ", pos, " to ", new_pos)
				break

		if still_exists:
			kept += 1
		else:
			removed += 1
			print("Cell REMOVED: ", pos)

	print("\nSummary:")
	print("  Kept: ", kept)
	print("  Removed: ", removed)
	print("  Final cell count: ", grid_manager.cells.size())

	# Check specific cells user reported missing
	var test_positions = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	]

	print("\nChecking specific positions:")
	for pos in test_positions:
		var exists = grid_manager.cells.has(pos)
		print("  ", pos, ": ", "EXISTS" if exists else "MISSING")
