extends GutTest

## Detailed cell lifecycle tracking for diagonal fold

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_track_kept_left_cells():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)

	# Classify all cells BEFORE fold
	print("\n=== CLASSIFICATION BEFORE FOLD ===")
	var kept_left_cells = []
	var kept_right_cells = []
	var removed_cells_classified = []

	for pos in grid_manager.cells.keys():
		var cell = grid_manager.get_cell(pos)
		var region = fold_system.classify_cell_region(cell, cut_lines)

		if region == "kept_left":
			kept_left_cells.append(pos)
		elif region == "kept_right":
			kept_right_cells.append(pos)
		elif region == "removed":
			removed_cells_classified.append(pos)

	print("kept_left cells: ", kept_left_cells.size())
	print("kept_right cells: ", kept_right_cells.size())
	print("removed cells: ", removed_cells_classified.size())

	# Sample kept_left cells to track
	var tracked_left = [Vector2i(0, 5), Vector2i(0, 6), Vector2i(1, 5)]
	print("\nTracking kept_left cells: ", tracked_left)
	for pos in tracked_left:
		if pos in kept_left_cells:
			var cell = grid_manager.get_cell(pos)
			print("  ", pos, ": EXISTS in kept_left, center=", cell.get_center())

	# Execute fold
	fold_system.execute_diagonal_fold(anchor1, anchor2)

	# Check what happened to kept_left cells
	print("\n=== AFTER FOLD ===")
	print("Total cells remaining: ", grid_manager.cells.size())

	print("\nChecking tracked kept_left cells:")
	for pos in tracked_left:
		var exists = grid_manager.cells.has(pos)
		if exists:
			var cell = grid_manager.get_cell(pos)
			print("  ", pos, ": STILL EXISTS, center=", cell.get_center())
		else:
			print("  ", pos, ": MISSING! (should be kept_left)")
			# Check if it moved
			var found_elsewhere = false
			for new_pos in grid_manager.cells.keys():
				var cell = grid_manager.get_cell(new_pos)
				var center = cell.get_center()
				var expected_center = Vector2(pos) * cell_size + Vector2(cell_size/2, cell_size/2)
				if center.distance_to(expected_center) < 1.0:
					print("    -> Found at ", new_pos, " instead!")
					found_elsewhere = true
					break
			if not found_elsewhere:
				print("    -> COMPLETELY LOST")

	# Check sample of kept_right cells
	var tracked_right = [Vector2i(5, 0), Vector2i(6, 0), Vector2i(5, 1)]
	print("\nChecking tracked kept_right cells:")
	for pos in tracked_right:
		if pos in kept_right_cells:
			var exists_after = grid_manager.cells.has(pos)
			if exists_after:
				var cell = grid_manager.get_cell(pos)
				print("  ", pos, ": shifted, new center=", cell.get_center())
			else:
				print("  ", pos, ": MISSING after shift (should be kept_right)")
