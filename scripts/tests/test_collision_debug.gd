extends GutTest

## Debug cell collisions during shift

var fold_system: FoldSystem
var grid_manager: GridManager

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

func test_check_for_collisions():
	var anchor1 = Vector2i(3, 4)
	var anchor2 = Vector2i(4, 3)

	var cell_size = grid_manager.cell_size
	var anchor1_local = Vector2(anchor1) * cell_size + Vector2(cell_size / 2, cell_size / 2)
	var anchor2_local = Vector2(anchor2) * cell_size + Vector2(cell_size / 2, cell_size / 2)

	var cut_lines = fold_system.calculate_cut_lines(anchor1_local, anchor2_local)
	var shift_vector = -(anchor2_local - anchor1_local)

	print("\n=== SHIFT VECTOR: ", shift_vector, " ===")

	# Find all kept_right cells
	var kept_right_cells = []
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.get_cell(pos)
		var region = fold_system.classify_cell_region(cell, cut_lines)
		if region == "kept_right":
			kept_right_cells.append(pos)

	print("\nKept_right cells: ", kept_right_cells.size())

	# Predict where each will go
	var destination_map = {}  # new_pos -> [old_pos1, old_pos2, ...]

	for old_pos in kept_right_cells:
		var cell = grid_manager.get_cell(old_pos)
		var old_center = cell.get_center()
		var new_center = old_center + shift_vector
		var new_pos = Vector2i(
			round(new_center.x / cell_size),
			round(new_center.y / cell_size)
		)

		if not destination_map.has(new_pos):
			destination_map[new_pos] = []
		destination_map[new_pos].append(old_pos)

	# Check for collisions
	print("\n=== COLLISION ANALYSIS ===")
	var collision_count = 0
	for new_pos in destination_map.keys():
		var sources = destination_map[new_pos]
		if sources.size() > 1:
			collision_count += 1
			print("COLLISION at ", new_pos, ": ", sources.size(), " cells from ", sources)

	print("\nTotal collisions: ", collision_count)

	# Check if kept_right cells collide with kept_left cells
	print("\n=== CHECKING KEPT_RIGHT -> KEPT_LEFT COLLISIONS ===")
	for old_pos in kept_right_cells:
		var cell = grid_manager.get_cell(old_pos)
		var old_center = cell.get_center()
		var new_center = old_center + shift_vector
		var new_pos = Vector2i(
			round(new_center.x / cell_size),
			round(new_center.y / cell_size)
		)

		# Check if there's already a kept_left cell at this position
		var existing = grid_manager.get_cell(new_pos)
		if existing:
			var existing_region = fold_system.classify_cell_region(existing, cut_lines)
			if existing_region == "kept_left":
				print("OVERLAP: kept_right cell ", old_pos, " -> ", new_pos, " (occupied by kept_left)")
