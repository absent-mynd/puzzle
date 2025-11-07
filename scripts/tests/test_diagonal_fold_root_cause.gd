extends GutTest

# Root cause analysis test for diagonal fold bug
# This test traces through execution with detailed logging

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

## Test the bug case: anchor2 left of anchor1
func test_reversed_anchors_classification():
	var anchor1 = Vector2i(3, 2)  # Right anchor
	var anchor2 = Vector2i(1, 2)  # Left anchor

	# Convert to local coordinates (cell centers)
	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	print("\n=== SCENARIO B: Reversed Anchors ===")
	print("anchor1 (grid):", anchor1, " → (local):", anchor1_local)
	print("anchor2 (grid):", anchor2, " → (local):", anchor2_local)

	# Calculate cut lines
	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)
	print("\nCut lines:")
	print("  line1: point=", cut_lines.line1.point, ", normal=", cut_lines.line1.normal)
	print("  line2: point=", cut_lines.line2.point, ", normal=", cut_lines.line2.normal)
	print("  fold_vector: ", anchor2_local - anchor1_local)

	# Classify cells and print results
	print("\n=== Cell Classification ===")
	var cells_by_region = {
		"kept_left": [],
		"removed": [],
		"kept_right": [],
		"split_line1": [],
		"split_line2": []
	}

	for y in range(grid_manager.grid_size.y):
		for x in range(grid_manager.grid_size.x):
			var pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(pos)
			if cell and pos.y == 2:  # Only check row 2
				var region = fold_system.classify_cell_region(cell, cut_lines)
				cells_by_region[region].append(cell)

				var centroid = cell.get_center()
				var side1 = GeometryCore.point_side_of_line(centroid, cut_lines.line1.point, cut_lines.line1.normal)
				var side2 = GeometryCore.point_side_of_line(centroid, cut_lines.line2.point, cut_lines.line2.normal)

				print("  Cell (%d,%d) center=%s: side1=%d, side2=%d → %s" % [
					x, y, str(centroid), side1, side2, region
				])

	# Print summary
	print("\n=== Classification Summary (Row 2) ===")
	for region in cells_by_region.keys():
		var count = cells_by_region[region].size()
		if count > 0:
			var positions = []
			for cell in cells_by_region[region]:
				if cell.grid_position.y == 2:
					positions.append(cell.grid_position.x)
			print("  %s: %d cells at x=%s" % [region, count, str(positions)])

	# Expected behavior
	print("\n=== Expected vs Actual ===")
	print("EXPECTED:")
	print("  kept_left (x<1): cells at x=0")
	print("  split_line2 (x=1): cell at x=1")
	print("  removed (1<x<3): cell at x=2")
	print("  split_line1 (x=3): cell at x=3")
	print("  kept_right (x>3): cell at x=4")

	print("\nACTUAL:")
	# Check what we actually got
	var kept_left_x = []
	var kept_right_x = []
	for cell in cells_by_region.kept_left:
		if cell.grid_position.y == 2:
			kept_left_x.append(cell.grid_position.x)
	for cell in cells_by_region.kept_right:
		if cell.grid_position.y == 2:
			kept_right_x.append(cell.grid_position.x)

	print("  kept_left: x=%s (expected: [0])" % str(kept_left_x))
	print("  kept_right: x=%s (expected: [4])" % str(kept_right_x))

	# Assertions
	assert_true(kept_left_x.has(0), "Cell at x=0 should be kept_left")
	assert_false(kept_left_x.has(4), "Cell at x=4 should NOT be kept_left (BUG)")
	assert_false(kept_right_x.has(0), "Cell at x=0 should NOT be kept_right")
	assert_true(kept_right_x.has(4), "Cell at x=4 should be kept_right")

## Test the normal case for comparison
func test_normal_anchors_classification():
	var anchor1 = Vector2i(1, 2)  # Left anchor
	var anchor2 = Vector2i(3, 2)  # Right anchor

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	print("\n=== SCENARIO A: Normal Anchors ===")
	print("anchor1 (grid):", anchor1, " → (local):", anchor1_local)
	print("anchor2 (grid):", anchor2, " → (local):", anchor2_local)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)
	print("\nCut lines:")
	print("  line1: point=", cut_lines.line1.point, ", normal=", cut_lines.line1.normal)
	print("  line2: point=", cut_lines.line2.point, ", normal=", cut_lines.line2.normal)

	# Classify cells
	var cells_by_region = {
		"kept_left": [],
		"removed": [],
		"kept_right": [],
		"split_line1": [],
		"split_line2": []
	}

	for y in range(grid_manager.grid_size.y):
		for x in range(grid_manager.grid_size.x):
			var pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(pos)
			if cell and pos.y == 2:
				var region = fold_system.classify_cell_region(cell, cut_lines)
				cells_by_region[region].append(cell)

	# Check results
	var kept_left_x = []
	var kept_right_x = []
	for cell in cells_by_region.kept_left:
		if cell.grid_position.y == 2:
			kept_left_x.append(cell.grid_position.x)
	for cell in cells_by_region.kept_right:
		if cell.grid_position.y == 2:
			kept_right_x.append(cell.grid_position.x)

	print("\nClassification (Row 2):")
	print("  kept_left: x=%s (expected: [0])" % str(kept_left_x))
	print("  kept_right: x=%s (expected: [4])" % str(kept_right_x))

	assert_true(kept_left_x.has(0), "Cell at x=0 should be kept_left")
	assert_true(kept_right_x.has(4), "Cell at x=4 should be kept_right")
