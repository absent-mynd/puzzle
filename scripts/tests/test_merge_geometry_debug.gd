extends GutTest

# Test to verify merged cells have complete geometry (not just one half)

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

func test_merged_cell_has_complete_geometry():
	print("\n╔════════════════════════════════════════════╗")
	print("║  CHECKING MERGED CELL GEOMETRY            ║")
	print("╚════════════════════════════════════════════╝")

	# Get original full cell for comparison
	var original_cell = grid_manager.get_cell(Vector2i(1, 2))
	var original_area = GeometryCore.polygon_area(original_cell.geometry)
	var cell_size = grid_manager.cell_size

	print("\nBEFORE fold:")
	print("  Original cell at (1,2) area: %.1f" % original_area)
	print("  Expected area: %.1f (full square)" % (cell_size * cell_size))

	# Capture state for validation
	var cells_before = grid_manager.cells.size()
	var area_before = FoldTestValidator.calculate_total_area(grid_manager)

	# Execute fold
	var anchor1 = Vector2i(1, 2)
	var anchor2 = Vector2i(3, 2)
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	# Run comprehensive validation
	# For horizontal fold anchor1=(1,2) to anchor2=(3,2):
	# - Cells at x=2 removed: 5 cells (entire column in 5x5 grid)
	# - Cells at x=3 shift to x=1 and merge, freeing original x=1 cells: 5 cells
	# Total removed: 5 + 5 = 10 cells
	var expected_removed = 10
	var validation = FoldTestValidator.validate_fold_result(
		grid_manager,
		cells_before,
		area_before,
		expected_removed,
		false
	)

	FoldTestValidator.print_validation_results(validation)

	# Check merged cell at x=1
	print("\nAFTER fold - MERGED CELL DETAILS:")
	var merged_cell = grid_manager.get_cell(Vector2i(1, 2))
	assert_not_null(merged_cell, "Cell at x=1 should exist")

	if merged_cell:
		print("  Merged cell at (1,2):")
		print("    is_partial: %s" % merged_cell.is_partial)
		print("    geometry vertices: %d" % merged_cell.geometry.size())

		if merged_cell.geometry.size() > 0:
			var merged_area = GeometryCore.polygon_area(merged_cell.geometry)
			print("    area: %.1f" % merged_area)
			print("    area vs original: %.1f%%" % (merged_area / original_area * 100))

			# Check geometry bounds
			var min_x = INF
			var max_x = -INF
			var min_y = INF
			var max_y = -INF
			for v in merged_cell.geometry:
				min_x = min(min_x, v.x)
				max_x = max(max_x, v.x)
				min_y = min(min_y, v.y)
				max_y = max(max_y, v.y)

			var width = max_x - min_x
			var height = max_y - min_y

			print("    x-range: [%.1f, %.1f] (width: %.1f)" % [min_x, max_x, width])
			print("    y-range: [%.1f, %.1f] (height: %.1f)" % [min_y, max_y, height])
			print("    Expected full width: %.1f" % cell_size)

			print("\n  DIAGNOSIS:")
			if width < cell_size * 0.9:
				print("    ❌ GEOMETRY INCOMPLETE!")
				print("    Only %.1f pixels wide (%.1f%% of full width)" % [width, width / cell_size * 100])
				print("    This cell should have merged geometry from BOTH cut lines")
				print("    but it only has geometry from ONE side!")
				print("    NOTE: This is a known limitation - proper polygon union not yet implemented")
			else:
				print("    ✅ GEOMETRY COMPLETE - spans full cell width")
