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


func test_understand_keep_side_for_vertical_fold():
	"""
	Understand how keep_side is determined for vertical folds.
	This will help us understand why pieces are disappearing.
	"""
	print("\n=== Keep Side Analysis for Vertical Fold ===")

	# For a vertical fold from (1,0) to (1,4), which side should be kept?
	# In execute_vertical_fold, it chooses the leftmost anchor as target
	var anchor1 = Vector2i(1, 0)
	var anchor2 = Vector2i(1, 4)

	# In a vertical fold, both anchors have the same x, so fold_x = 1
	# The line at x=1 divides the grid into:
	# - Left side (x < 1)
	# - Right side (x > 1)

	# The remove region would be between anchor1.y and anchor2.y
	# Cells outside this y-range should be stationary
	# Cells beyond the line (x > 1 in this case) should shift left

	print("Vertical fold (1,0) to (1,4):")
	print("  Fold line at x=1")
	print("  Left side (x < 1): stationary cells")
	print("  Right side (x > 1): cells that will shift left")

	# After first fold, cells in column 0 stay, cells in column 1+ shift left
	# Cell at (1,0) shifts to (0,0)... but wait, there's already a cell there
	# They merge

	# After merge at (0,0), we have a multi-piece cell
	# Then we fold again at the same line x=1

	# But now cell (0,0) has multiple pieces from the merge
	# The classification needs to handle this correctly

	# Actually, I think I see the issue!
	# After first fold, cell (1,0) shifts to (0,0) and merges
	# So there's no cell at (1,0) after the first fold
	# Therefore, the second fold might be hitting a different cell that was at (1,0) before

	print("\nActually, the bug might be related to which cells are at (1,0) between folds...")
