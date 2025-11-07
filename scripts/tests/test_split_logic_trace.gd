extends GutTest

# Trace the split logic to see which geometry is kept

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

## Trace split logic for cell at x=1 (split_line2) in reversed scenario
func test_split_line2_geometry():
	var anchor1 = Vector2i(3, 2)
	var anchor2 = Vector2i(1, 2)
	var cell_size = grid_manager.cell_size

	# Get the cell at x=1
	var cell = grid_manager.get_cell(Vector2i(1, 2))
	assert_not_null(cell)

	print("\n=== Split Line2 Analysis ===")
	print("Cell at (1,2) geometry:")
	for i in range(cell.geometry.size()):
		print("  vertex[%d]: %s" % [i, cell.geometry[i]])
	print("  centroid: %s" % cell.get_center())

	# Calculate cut lines
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	print("\nline2 (at anchor2):")
	print("  point: %s" % cut_lines.line2.point)
	print("  normal: %s" % cut_lines.line2.normal)

	# Perform the split
	var split_result = GeometryCore.split_polygon_by_line(
		cell.geometry, cut_lines.line2.point, cut_lines.line2.normal
	)

	print("\nSplit result:")
	print("  intersections: %d" % split_result.intersections.size())
	for i in range(split_result.intersections.size()):
		print("    [%d]: %s" % [i, split_result.intersections[i]])

	print("  left (positive side): %d vertices" % split_result.left.size())
	for i in range(split_result.left.size()):
		print("    [%d]: %s" % [i, split_result.left[i]])

	print("  right (negative side): %d vertices" % split_result.right.size())
	for i in range(split_result.right.size()):
		print("    [%d]: %s" % [i, split_result.right[i]])

	# The code keeps "left" for line2
	print("\nHardcoded keep_side for split_line2: 'left'")
	print("  'left' = positive side of normal")
	print("  normal = (-1, 0), so positive side = negative x direction")
	print("  This means: x < 96 (left of cell center)")

	# Check which vertices are actually kept
	print("\nAnalysis:")
	if split_result.left.size() >= 3:
		var min_x = INF
		var max_x = -INF
		for v in split_result.left:
			min_x = min(min_x, v.x)
			max_x = max(max_x, v.x)
		print("  Kept geometry spans x ∈ [%.1f, %.1f]" % [min_x, max_x])
		if max_x <= 96:
			print("  ✅ Keeps LEFT portion (x <= 96) - CORRECT!")
		else:
			print("  ❌ Keeps RIGHT portion - WRONG!")

	# What should be kept?
	print("\nExpected behavior:")
	print("  Removed region: x ∈ (96, 224) - between anchors")
	print("  Cell at x=1 spans x ∈ [64, 128]")
	print("  Should keep: x ∈ [64, 96] (left portion, outside removed region)")
	print("  Should discard: x ∈ [96, 128] (right portion, inside removed region)")

## Trace split logic for cell at x=3 (split_line1) in reversed scenario
func test_split_line1_geometry():
	var anchor1 = Vector2i(3, 2)
	var anchor2 = Vector2i(1, 2)
	var cell_size = grid_manager.cell_size

	var cell = grid_manager.get_cell(Vector2i(3, 2))
	assert_not_null(cell)

	print("\n=== Split Line1 Analysis ===")
	print("Cell at (3,2) geometry:")
	for i in range(cell.geometry.size()):
		print("  vertex[%d]: %s" % [i, cell.geometry[i]])

	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	print("\nline1 (at anchor1):")
	print("  point: %s" % cut_lines.line1.point)
	print("  normal: %s" % cut_lines.line1.normal)

	var split_result = GeometryCore.split_polygon_by_line(
		cell.geometry, cut_lines.line1.point, cut_lines.line1.normal
	)

	print("\nSplit result:")
	print("  left (positive side): %d vertices" % split_result.left.size())
	print("  right (negative side): %d vertices" % split_result.right.size())

	print("\nHardcoded keep_side for split_line1: 'right'")
	print("  'right' = negative side of normal")
	print("  normal = (-1, 0), so negative side = positive x direction")
	print("  This means: x > 224 (right of cell center)")

	if split_result.right.size() >= 3:
		var min_x = INF
		var max_x = -INF
		for v in split_result.right:
			min_x = min(min_x, v.x)
			max_x = max(max_x, v.x)
		print("  Kept geometry spans x ∈ [%.1f, %.1f]" % [min_x, max_x])
		if min_x >= 224:
			print("  ✅ Keeps RIGHT portion (x >= 224) - CORRECT!")
		else:
			print("  ❌ Keeps LEFT portion - WRONG!")

	print("\nExpected behavior:")
	print("  Removed region: x ∈ (96, 224) - between anchors")
	print("  Cell at x=3 spans x ∈ [192, 256]")
	print("  Should keep: x ∈ [224, 256] (right portion, outside removed region)")
	print("  Should discard: x ∈ [192, 224] (left portion, inside removed region)")
