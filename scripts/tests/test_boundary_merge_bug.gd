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


func test_diagonal_merge_correct_polygon_orientation():
	print("\n╔════════════════════════════════════════════╗")
	print("║  DIAGONAL MERGE - POLYGON ORIENTATION BUG  ║")
	print("║  Testing (0,0) wall + (1,1) ground merge   ║")
	print("╚════════════════════════════════════════════╝\n")

	# Set up a specific scenario:
	# - Cell (0,0) is a WALL
	# - Cell (1,1) is EMPTY (ground)
	# - Diagonal fold with anchors at (0,0) and (1,1)
	# - Expected: merged cell should have wall piece in TOP-LEFT, ground piece in BOTTOM-RIGHT
	# - Bug: merged cell has wall piece in BOTTOM-RIGHT, ground piece in TOP-LEFT (inverted!)

	var cell_00 = grid_manager.get_cell(Vector2i(0, 0))
	var cell_11 = grid_manager.get_cell(Vector2i(1, 1))

	cell_00.set_cell_type(1)  # Wall
	cell_11.set_cell_type(0)  # Ground (empty)

	print("BEFORE fold:")
	print("  Cell (0,0): type=%d (wall)" % cell_00.cell_type)
	print("  Cell (1,1): type=%d (ground)" % cell_11.cell_type)
	print("")

	# Execute diagonal fold
	var anchor1 = Vector2i(0, 0)
	var anchor2 = Vector2i(1, 1)
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("AFTER fold:")

	# Find which cells still exist
	print("  Searching for cells...")
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		if cell:
			print("    Cell at %s: type=%d, partial=%s, pieces=%d" % [pos, cell.cell_type, cell.is_partial, cell.geometry_pieces.size()])

	# The anchor cells should be merged
	var cell_00_after = grid_manager.get_cell(Vector2i(0, 0))
	var cell_11_after = grid_manager.get_cell(Vector2i(1, 1))

	# At least ONE anchor should have a merged cell
	if not cell_00_after and not cell_11_after:
		print("  ERROR: Both anchor cells are gone!")
		assert_true(cell_00_after != null or cell_11_after != null, "At least one anchor cell should exist")
		return

	# Use whichever cell exists
	var merged_cell = cell_00_after if cell_00_after else cell_11_after
	var merged_pos = Vector2i(0, 0) if cell_00_after else Vector2i(1, 1)

	print("")
	print("  Merged cell is at position %s" % merged_pos)
	print("  Pieces: %d" % merged_cell.geometry_pieces.size())

	print("")

	# Check which piece type is where in the geometry
	var bug_detected = false

	# The merged cell should have 2 pieces (wall + ground)
	if merged_cell.geometry_pieces.size() < 2:
		print("  ERROR: Merged cell only has %d piece(s), expected 2" % merged_cell.geometry_pieces.size())
		return

	# Find the wall piece and ground piece
	var wall_piece = null
	var ground_piece = null

	for piece in merged_cell.geometry_pieces:
		if piece.cell_type == 1:
			wall_piece = piece
		elif piece.cell_type == 0:
			ground_piece = piece

	if not wall_piece or not ground_piece:
		print("  ERROR: Could not find both wall and ground pieces!")
		print("  Pieces found: %s" % [merged_cell.geometry_pieces.map(func(p): return p.cell_type)])
		return

	# Check orientations
	var wall_center = wall_piece.get_center()
	var ground_center = ground_piece.get_center()

	print("  Wall piece center: (%.1f, %.1f)" % [wall_center.x, wall_center.y])
	print("  Ground piece center: (%.1f, %.1f)" % [ground_center.x, ground_center.y])
	print("")

	# The diagonal goes from (0,0) to (64,64)
	# Wall started at (0,0), so wall piece should be in top-left (lower x, lower y)
	# Ground started at (1,1), so ground piece should be in bottom-right (higher x, higher y)

	if wall_center.x > ground_center.x or wall_center.y > ground_center.y:
		print("  ❌ BUG DETECTED: Wall piece is in bottom-right, ground piece is in top-left")
		print("  This is backwards - they should be swapped!")
		bug_detected = true
	else:
		print("  ✅ Correct: Wall piece is in top-left, ground piece is in bottom-right")

	if bug_detected:
		print("❌ BUG CONFIRMED: Split polygons are on wrong side of seam!")
	else:
		print("✅ No polygon orientation bug detected")

	assert_false(bug_detected, "Split polygons should be on correct side of seam")


func test_boundary_merge_keeps_correct_seam_side():
	print("\n╔════════════════════════════════════════════╗")
	print("║  BOUNDARY MERGE BUG TEST                   ║")
	print("║  Wrong polygon half kept after split       ║")
	print("╚════════════════════════════════════════════╝\n")

	# Create a diagonal fold that will shift cells into negative space
	# This should cause some cells to be split, with one half shifted outside the grid
	# anchor1 at (1, 1), anchor2 at (3, 3)
	var anchor1 = Vector2i(1, 1)
	var anchor2 = Vector2i(3, 3)

	print("BEFORE fold:")
	print("  Grid: 5x5")
	for y in range(3):
		print("  Row %d: %s" % [y, _get_row_string(y)])
	print("")

	# Execute diagonal fold
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	print("AFTER fold:")
	print("  Checking cells that merged into 'empty space' (outside grid)...")
	print("")

	# Check cells that are now outside the valid grid positions
	# These cells shifted into negative grid positions
	var bug_detected = false

	# Check for cells with negative grid positions (shifted outside grid)
	for cell_pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[cell_pos]
		if cell and cell.is_partial:
			# Check if this cell position would be outside the original grid bounds
			if cell_pos.x < 0 or cell_pos.y < 0:
				print("  Cell at (%d, %d) is OUTSIDE original grid (shifted into empty space)" % [cell_pos.x, cell_pos.y])
				print("    This cell was split and shifted to a position outside the grid")

				# Check the geometry - it should be positioned correctly for its grid position
				# Calculate expected position range for this cell
				var expected_min_x = cell_pos.x * grid_manager.cell_size
				var expected_max_x = (cell_pos.x + 1) * grid_manager.cell_size
				var expected_min_y = cell_pos.y * grid_manager.cell_size
				var expected_max_y = (cell_pos.y + 1) * grid_manager.cell_size

				# Get actual geometry bounds
				var min_x = INF
				var max_x = -INF
				var min_y = INF
				var max_y = -INF
				for vertex in cell.geometry:
					min_x = min(min_x, vertex.x)
					max_x = max(max_x, vertex.x)
					min_y = min(min_y, vertex.y)
					max_y = max(max_y, vertex.y)

				print("    Expected bounds for position (%d, %d):" % [cell_pos.x, cell_pos.y])
				print("      x: [%.1f, %.1f]" % [expected_min_x, expected_max_x])
				print("      y: [%.1f, %.1f]" % [expected_min_y, expected_max_y])
				print("    Actual geometry bounds:")
				print("      x: [%.1f, %.1f]" % [min_x, max_x])
				print("      y: [%.1f, %.1f]" % [min_y, max_y])

				# The bug: if the geometry is on the wrong side of where it should be
				# For a cell at negative position, the geometry should extend INTO negative space
				# If it doesn't, we kept the wrong half
				var geometry_center_x = (min_x + max_x) / 2
				var geometry_center_y = (min_y + max_y) / 2
				var expected_center_x = (expected_min_x + expected_max_x) / 2
				var expected_center_y = (expected_min_y + expected_max_y) / 2

				# Check if the geometry center is roughly where we expect
				var center_offset_x = abs(geometry_center_x - expected_center_x)
				var center_offset_y = abs(geometry_center_y - expected_center_y)

				print("    Geometry center: (%.1f, %.1f)" % [geometry_center_x, geometry_center_y])
				print("    Expected center: (%.1f, %.1f)" % [expected_center_x, expected_center_y])
				print("    Offset: (%.1f, %.1f)" % [center_offset_x, center_offset_y])

				# If the center is way off (more than half a cell size), wrong half was kept
				if center_offset_x > grid_manager.cell_size * 0.5 or center_offset_y > grid_manager.cell_size * 0.5:
					print("    ❌ BUG: Geometry center is far from expected position!")
					print("    This indicates the wrong half of the split was kept")
					bug_detected = true
				else:
					print("    ✅ Geometry center is reasonably positioned")

	if not bug_detected:
		print("\n✅ No polygon inversion detected")
	else:
		print("\n❌ BUG CONFIRMED: Wrong half of split polygon was kept")

	assert_false(bug_detected, "Split cells should keep the correct polygon half")


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
