extends GutTest

## Test for cell geometry not shifting with cells during diagonal fold

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


func test_cell_geometry_shifts_with_position():
	print("\n╔════════════════════════════════════════════╗")
	print("║  CELL GEOMETRY SHIFT BUG TEST              ║")
	print("║  Geometry should move with cell position   ║")
	print("╚════════════════════════════════════════════╝\n")

	# Get a cell that will be shifted
	# With diagonal fold from (1,1) to (3,3), cell (2,2) should shift
	var cell_22_before = grid_manager.get_cell(Vector2i(2, 2))

	print("BEFORE fold:")
	print("  Cell (2,2) geometry bounds:")
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	for vertex in cell_22_before.geometry:
		min_x = min(min_x, vertex.x)
		max_x = max(max_x, vertex.x)
		min_y = min(min_y, vertex.y)
		max_y = max(max_y, vertex.y)
	print("    x: [%.1f, %.1f]" % [min_x, max_x])
	print("    y: [%.1f, %.1f]" % [min_y, max_y])
	print("    Expected for position (2,2): x=[128, 192], y=[128, 192]")
	print("")

	# Execute diagonal fold
	var anchor1 = Vector2i(1, 1)
	var anchor2 = Vector2i(3, 3)
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("AFTER fold:")

	# Find where cell ended up
	var found_cell = null
	var found_pos = Vector2i(-999, -999)

	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		if cell and cell == cell_22_before:
			found_cell = cell
			found_pos = pos
			break

	if not found_cell:
		print("  ERROR: Could not find cell (2,2) after fold!")
		assert_not_null(found_cell, "Cell should still exist after fold")
		return

	print("  Cell shifted from (2,2) to %s" % found_pos)

	# Calculate expected geometry bounds for new position
	var expected_min_x = found_pos.x * grid_manager.cell_size
	var expected_max_x = (found_pos.x + 1) * grid_manager.cell_size
	var expected_min_y = found_pos.y * grid_manager.cell_size
	var expected_max_y = (found_pos.y + 1) * grid_manager.cell_size

	# Get actual geometry bounds
	min_x = INF
	max_x = -INF
	min_y = INF
	max_y = -INF
	for vertex in found_cell.geometry:
		min_x = min(min_x, vertex.x)
		max_x = max(max_x, vertex.x)
		min_y = min(min_y, vertex.y)
		max_y = max(max_y, vertex.y)

	print("  Actual geometry bounds:")
	print("    x: [%.1f, %.1f]" % [min_x, max_x])
	print("    y: [%.1f, %.1f]" % [min_y, max_y])
	print("  Expected geometry bounds for position %s:" % found_pos)
	print("    x: [%.1f, %.1f]" % [expected_min_x, expected_max_x])
	print("    y: [%.1f, %.1f]" % [expected_min_y, expected_max_y])
	print("")

	# Check if geometry is roughly where it should be (within 10% of cell size)
	var tolerance = grid_manager.cell_size * 0.1
	var x_offset = abs((min_x + max_x) / 2 - (expected_min_x + expected_max_x) / 2)
	var y_offset = abs((min_y + max_y) / 2 - (expected_min_y + expected_max_y) / 2)

	print("  Center offset: (%.1f, %.1f)" % [x_offset, y_offset])
	print("  Tolerance: %.1f" % tolerance)
	print("")

	var bug_detected = false
	if x_offset > tolerance or y_offset > tolerance:
		print("  ❌ BUG: Geometry center is far from expected position!")
		print("  Geometry was not shifted with the cell!")
		bug_detected = true
	else:
		print("  ✅ Geometry is correctly positioned for new cell location")

	assert_false(bug_detected, "Cell geometry should shift with cell position")


func test_player_shifts_with_cell():
	print("\n╔════════════════════════════════════════════╗")
	print("║  PLAYER SHIFT BUG TEST                     ║")
	print("║  Player should move with cell during shift ║")
	print("╚════════════════════════════════════════════╝\n")

	# Create player at position (2, 2)
	var player = Player.new()
	add_child_autofree(player)
	player.grid_manager = grid_manager
	player.grid_position = Vector2i(2, 2)
	fold_system.player = player

	# Position player in world
	var cell_center = grid_manager.get_cell(Vector2i(2, 2)).get_center()
	player.position = grid_manager.to_global(cell_center)

	print("BEFORE fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("  Player world position: %s" % player.position)
	print("")

	# Execute diagonal fold
	var anchor1 = Vector2i(1, 1)
	var anchor2 = Vector2i(3, 3)
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("AFTER fold:")
	print("  Player grid position: %s" % player.grid_position)
	print("  Player world position: %s" % player.position)

	# Player should have shifted
	# Original position (2,2), with shift vector from anchor1 to anchor2 = (2, 2)
	# So player should be at (2,2) - (2,2) = (0,0)
	var expected_grid_pos = Vector2i(0, 0)

	print("  Expected grid position: %s" % expected_grid_pos)
	print("")

	# Check if player position matches cell position
	var player_cell = grid_manager.get_cell(player.grid_position)
	if not player_cell:
		print("  ❌ BUG: Player's grid position doesn't have a cell!")
		assert_not_null(player_cell, "Player should be on a valid cell")
		return

	var cell_center_world = grid_manager.to_global(player_cell.get_center())
	var position_offset = player.position.distance_to(cell_center_world)

	print("  Player position offset from cell center: %.1f" % position_offset)
	print("  Tolerance: %.1f" % (grid_manager.cell_size * 0.5))

	var bug_detected = false
	if position_offset > grid_manager.cell_size * 0.5:
		print("  ❌ BUG: Player position is far from cell center!")
		print("  Player was not shifted correctly!")
		bug_detected = true
	else:
		print("  ✅ Player is correctly positioned on shifted cell")

	assert_false(bug_detected, "Player should shift with cell")
