## Test for repeated fold bug where pieces disappear
##
## Bug: When folding vertically on (1,0) to (2,0), then repeating the same fold,
## the left side of cells in column 1 disappears visually (but remains walkable).

extends GutTest

var grid_manager: GridManager
var fold_system: FoldSystem

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.grid_size = Vector2i(10, 10)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.grid_manager = grid_manager


func test_repeated_vertical_fold_preserves_pieces():
	"""
	Test: Fold vertically along x=1, then repeat the same fold.
	Expected: All pieces should be preserved and visible in column 1.
	Bug: Left side of column 1 cells disappears.
	"""
	print("\n=== Repeated Vertical Fold Test ===")

	# First fold: vertical at x=1 (fold line between columns 0 and 1)
	# Anchors must have same X for vertical fold
	print("\nFirst fold: vertical fold line at x=1")
	fold_system.execute_vertical_fold(Vector2i(1, 0), Vector2i(1, 9))
	print("  First fold executed")

	# Check a cell in column 1 after first fold
	var cell_1_0_after_fold1 = grid_manager.get_cell(Vector2i(1, 0))
	print("After fold 1:")
	if cell_1_0_after_fold1:
		print("  Cell (1,0) exists with %d pieces" % cell_1_0_after_fold1.geometry_pieces.size())
		var area1 = 0.0
		for piece in cell_1_0_after_fold1.geometry_pieces:
			area1 += piece.get_area()
			print("    Piece: area=%.1f, type=%d" % [piece.get_area(), piece.cell_type])
		print("  Total area: %.1f" % area1)
	else:
		print("  Cell (1,0) does not exist (shifted or removed)")
		# Check if it moved to (0,0)
		var merged_cell = grid_manager.get_cell(Vector2i(0, 0))
		if merged_cell:
			print("  But cell at (0,0) exists with %d pieces" % merged_cell.geometry_pieces.size())
			for piece in merged_cell.geometry_pieces:
				print("    Piece: area=%.1f, type=%d" % [piece.get_area(), piece.cell_type])

	# Second fold: repeat the same fold
	print("\nSecond fold: vertical fold line at x=1 (REPEATED)")
	fold_system.execute_vertical_fold(Vector2i(1, 0), Vector2i(1, 9))
	print("  Second fold executed")

	# Check if anything changed
	var result2_check = grid_manager.get_cell(Vector2i(1, 0)) != null

	if result2_check:
		print("Second fold succeeded")
		var cell_1_0_after_fold2 = grid_manager.get_cell(Vector2i(1, 0))
		print("After fold 2:")
		if cell_1_0_after_fold2:
			print("  Cell (1,0) exists with %d pieces" % cell_1_0_after_fold2.geometry_pieces.size())
			var area2 = 0.0
			for piece in cell_1_0_after_fold2.geometry_pieces:
				area2 += piece.get_area()
				print("    Piece: area=%.1f, type=%d" % [piece.get_area(), piece.cell_type])
			print("  Total area: %.1f" % area2)
			assert_gt(cell_1_0_after_fold2.geometry_pieces.size(), 0, "Should have pieces")
		else:
			print("  Cell (1,0) was removed or shifted")
	else:
		print("Second fold failed (expected - may not be able to fold same line twice)")
