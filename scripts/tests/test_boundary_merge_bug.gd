extends GutTest

## Test for boundary merge bug
## When cells merge into positions outside the grid, the wrong side of the seam is kept

var grid_manager: GridManager
var fold_system: FoldSystem


func before_each():
	grid_manager = GridManager.new()
	grid_manager.grid_size = Vector2i(5, 5)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()
	add_child_autofree(grid_manager)

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.grid_manager = grid_manager


func test_boundary_merge_keeps_correct_seam_side():
	print("\n╔════════════════════════════════════════════╗")
	print("║  BOUNDARY MERGE BUG TEST                   ║")
	print("║  Diagonal fold near grid edge              ║")
	print("╚════════════════════════════════════════════╝\n")

	# Create a diagonal fold near the top-left corner
	# anchor1 at (0, 0), anchor2 at (2, 2)
	# This creates a 45-degree fold line
	# Cells will be shifted/clipped at the grid boundary
	var anchor1 = Vector2i(0, 0)
	var anchor2 = Vector2i(2, 2)

	print("BEFORE fold:")
	print("  Grid: 5x5")
	for y in range(3):
		print("  Row %d: %s" % [y, _get_row_string(y)])
	print("")

	# Execute diagonal fold
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("AFTER fold:")
	print("  Checking cells that were split and shifted...")
	print("")

	# Check all cells for boundary violations
	var bug_detected = false
	for y in range(grid_manager.grid_size.y):
		for x in range(grid_manager.grid_size.x):
			var cell = grid_manager.get_cell(Vector2i(x, y))
			if cell and cell.is_partial:
				# Check geometry bounds
				var min_x = INF
				var max_x = -INF
				var min_y = INF
				var max_y = -INF
				for vertex in cell.geometry:
					min_x = min(min_x, vertex.x)
					max_x = max(max_x, vertex.x)
					min_y = min(min_y, vertex.y)
					max_y = max(max_y, vertex.y)

				# Grid bounds in local coordinates
				var grid_max_x = grid_manager.grid_size.x * grid_manager.cell_size
				var grid_max_y = grid_manager.grid_size.y * grid_manager.cell_size

				print("  Cell (%d, %d): geometry bounds" % [x, y])
				print("    x: [%.1f, %.1f] (grid: [0, %.1f])" % [min_x, max_x, grid_max_x])
				print("    y: [%.1f, %.1f] (grid: [0, %.1f])" % [min_y, max_y, grid_max_y])

				# Check if geometry extends outside grid
				if min_x < -0.1 or min_y < -0.1:
					print("    ❌ BUG: Geometry extends below/left of grid origin!")
					bug_detected = true
				elif max_x > grid_max_x + 0.1 or max_y > grid_max_y + 0.1:
					print("    ❌ BUG: Geometry extends beyond grid boundary!")
					bug_detected = true
				else:
					print("    ✅ Geometry is within grid bounds")

	if not bug_detected:
		print("\n✅ No boundary violations detected")
	else:
		print("\n❌ BUG CONFIRMED: Some cells have geometry outside grid bounds")

	assert_false(bug_detected, "Cells should not have geometry outside grid bounds")


func _get_row_string(y: int) -> String:
	var s = ""
	for x in range(grid_manager.grid_size.x):
		var cell = grid_manager.get_cell(Vector2i(x, y))
		if cell:
			if cell.is_partial:
				s += "[P]"
			else:
				s += "[X]"
		else:
			s += " . "
	return s
