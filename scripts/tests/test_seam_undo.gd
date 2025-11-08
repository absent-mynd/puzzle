extends GutTest

## Tests for Phase 6: Seam-Based Undo System
## Task 1: Seam-to-Fold Mapping

var grid_manager: GridManager
var fold_system: FoldSystem
var player: Player


func before_each():
	# Create GridManager
	grid_manager = GridManager.new()
	grid_manager.grid_size = Vector2i(10, 10)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()
	add_child_autofree(grid_manager)

	# Create FoldSystem
	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

	# Create Player (position in corner to not block folds)
	player = Player.new()
	add_child_autofree(player)
	player.grid_position = Vector2i(0, 0)
	fold_system.set_player(player)


## ============================================================================
## TASK 1: SEAM-TO-FOLD MAPPING TESTS
## ============================================================================

func test_seam_to_fold_map_exists():
	# Verify seam_to_fold_map property exists by accessing it
	var map = fold_system.seam_to_fold_map
	assert_not_null(map, "FoldSystem should have seam_to_fold_map property")
	assert_true(map is Dictionary, "seam_to_fold_map should be a Dictionary")


func test_seam_to_fold_map_initialized_empty():
	assert_not_null(fold_system.seam_to_fold_map, "seam_to_fold_map should be initialized")
	assert_eq(fold_system.seam_to_fold_map.size(), 0, "seam_to_fold_map should start empty")


func test_horizontal_fold_creates_seam_mapping():
	# Execute a horizontal fold
	var anchor1 = Vector2i(2, 3)
	var anchor2 = Vector2i(6, 3)
	fold_system.execute_fold(anchor1, anchor2, false)

	# Should have 2 seam lines (one at each anchor)
	assert_eq(fold_system.seam_lines.size(), 2, "Should have 2 seam lines after horizontal fold")

	# Each seam should be mapped to the fold
	for seam_line in fold_system.seam_lines:
		var fold_id = fold_system.seam_to_fold_map.get(seam_line.get_instance_id())
		assert_not_null(fold_id, "Seam line should be in seam_to_fold_map")
		assert_eq(fold_id, 0, "First fold should have fold_id 0")


func test_vertical_fold_creates_seam_mapping():
	# Execute a vertical fold
	var anchor1 = Vector2i(4, 2)
	var anchor2 = Vector2i(4, 7)
	fold_system.execute_fold(anchor1, anchor2, false)

	# Should have 2 seam lines
	assert_eq(fold_system.seam_lines.size(), 2, "Should have 2 seam lines after vertical fold")

	# Each seam should be mapped
	for seam_line in fold_system.seam_lines:
		var fold_id = fold_system.seam_to_fold_map.get(seam_line.get_instance_id())
		assert_not_null(fold_id, "Seam line should be in seam_to_fold_map")


func test_diagonal_fold_creates_seam_mapping():
	# Execute a diagonal fold
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(6, 6)
	fold_system.execute_fold(anchor1, anchor2, false)

	# Should have 2 seam lines
	assert_eq(fold_system.seam_lines.size(), 2, "Should have 2 seam lines after diagonal fold")

	# Each seam should be mapped
	for seam_line in fold_system.seam_lines:
		var fold_id = fold_system.seam_to_fold_map.get(seam_line.get_instance_id())
		assert_not_null(fold_id, "Seam line should be in seam_to_fold_map")


func test_multiple_folds_create_multiple_mappings():
	# Execute multiple folds
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(6, 3), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(3, 1), Vector2i(3, 4), false)  # fold_id 1

	# Should have 4 seam lines total (2 per fold)
	assert_eq(fold_system.seam_lines.size(), 4, "Should have 4 seam lines after 2 folds")

	# Count seams for each fold
	var fold_0_count = 0
	var fold_1_count = 0

	for seam_line in fold_system.seam_lines:
		var fold_id = fold_system.seam_to_fold_map.get(seam_line.get_instance_id())
		if fold_id == 0:
			fold_0_count += 1
		elif fold_id == 1:
			fold_1_count += 1

	assert_eq(fold_0_count, 2, "Fold 0 should have 2 seams")
	assert_eq(fold_1_count, 2, "Fold 1 should have 2 seams")


func test_get_fold_for_seam_returns_correct_record():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Get the first seam line
	assert_gt(fold_system.seam_lines.size(), 0, "Should have at least one seam line")
	var seam_line = fold_system.seam_lines[0]

	# Get fold record for this seam
	var fold_record = fold_system.get_fold_for_seam(seam_line)

	assert_not_null(fold_record, "Should return a fold record")
	assert_has(fold_record, "fold_id", "Fold record should have fold_id")
	assert_eq(fold_record["fold_id"], 0, "Should return fold record with correct fold_id")


func test_get_fold_for_seam_returns_null_for_unmapped_seam():
	# Create a standalone Line2D (not from a fold)
	var fake_seam = Line2D.new()
	add_child_autofree(fake_seam)

	# Try to get fold for unmapped seam
	var fold_record = fold_system.get_fold_for_seam(fake_seam)

	assert_true(fold_record.is_empty(), "Should return empty dictionary for unmapped seam")


func test_get_fold_for_seam_with_multiple_folds():
	# Execute two folds
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(6, 3), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(3, 1), Vector2i(3, 4), false)  # fold_id 1

	# Check that each seam maps to correct fold
	var fold_0_seams = []
	var fold_1_seams = []

	for seam_line in fold_system.seam_lines:
		var fold_record = fold_system.get_fold_for_seam(seam_line)
		assert_not_null(fold_record, "All seams should map to a fold")

		if fold_record["fold_id"] == 0:
			fold_0_seams.append(seam_line)
		elif fold_record["fold_id"] == 1:
			fold_1_seams.append(seam_line)

	assert_eq(fold_0_seams.size(), 2, "Fold 0 should have 2 seams")
	assert_eq(fold_1_seams.size(), 2, "Fold 1 should have 2 seams")


func test_remove_seam_from_map():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Get a seam line
	var seam_line = fold_system.seam_lines[0]
	var seam_id = seam_line.get_instance_id()

	# Verify it's in the map
	assert_true(fold_system.seam_to_fold_map.has(seam_id), "Seam should be in map")

	# Remove seam from map
	fold_system.remove_seam_from_map(seam_line)

	# Verify it's removed
	assert_false(fold_system.seam_to_fold_map.has(seam_id), "Seam should be removed from map")


func test_remove_all_seams_for_fold():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Get fold_id
	var fold_id = 0

	# Verify seams exist
	var initial_seam_count = fold_system.seam_lines.size()
	assert_gt(initial_seam_count, 0, "Should have seams after fold")

	# Remove all seams for this fold
	fold_system.remove_seams_for_fold(fold_id)

	# Verify all seams removed from map
	for seam_line in fold_system.seam_lines:
		var mapped_fold_id = fold_system.seam_to_fold_map.get(seam_line.get_instance_id())
		assert_true(mapped_fold_id == null or mapped_fold_id != fold_id,
			"Fold's seams should be removed from map")


func test_clear_all_seams_clears_map():
	# Execute multiple folds
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(6, 3), false)
	fold_system.execute_fold(Vector2i(3, 1), Vector2i(3, 4), false)

	# Verify map has entries
	assert_gt(fold_system.seam_to_fold_map.size(), 0, "Map should have entries")

	# Clear all seams
	fold_system.clear_all_seams()

	# Verify map is empty
	assert_eq(fold_system.seam_to_fold_map.size(), 0, "Map should be empty after clearing seams")
	assert_eq(fold_system.seam_lines.size(), 0, "seam_lines array should be empty")


func test_seam_metadata_includes_fold_id():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Check that seam Line2D has fold_id metadata
	for seam_line in fold_system.seam_lines:
		assert_true(seam_line.has_meta("fold_id"), "Seam should have fold_id metadata")
		var fold_id = seam_line.get_meta("fold_id")
		assert_eq(fold_id, 0, "Seam metadata should have correct fold_id")


## ============================================================================
## TASK 2: CLICKABLE ZONE CALCULATION TESTS
## ============================================================================

func test_calculate_clickable_zones_method_exists():
	# Verify method exists by calling it
	var zones = fold_system.calculate_clickable_zones(Vector2(100, 100), Vector2(1, 0))
	assert_not_null(zones, "calculate_clickable_zones should return a value")
	assert_true(zones is Array, "calculate_clickable_zones should return an Array")


func test_horizontal_seam_clickable_zones():
	# Execute a horizontal fold
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(6, 3), false)

	# Get one of the seams (vertical lines for horizontal fold)
	assert_gt(fold_system.seam_lines.size(), 0, "Should have seam lines")
	var seam_line = fold_system.seam_lines[0]

	# Check that seam has clickable_zones metadata
	assert_true(seam_line.has_meta("clickable_zones"), "Seam should have clickable_zones metadata")

	var zones = seam_line.get_meta("clickable_zones")
	assert_true(zones is Array, "clickable_zones should be an Array")

	# Horizontal fold creates vertical seams, which pass through multiple cell centers vertically
	# Should have zones for all rows (y=0 to y=9) at the seam's x position
	assert_gt(zones.size(), 0, "Should have at least one clickable zone")


func test_vertical_seam_clickable_zones():
	# Execute a vertical fold
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 7), false)

	# Get one of the seams (horizontal lines for vertical fold)
	assert_gt(fold_system.seam_lines.size(), 0, "Should have seam lines")
	var seam_line = fold_system.seam_lines[0]

	# Check metadata
	assert_true(seam_line.has_meta("clickable_zones"), "Seam should have clickable_zones metadata")

	var zones = seam_line.get_meta("clickable_zones")
	assert_true(zones is Array, "clickable_zones should be an Array")

	# Vertical fold creates horizontal seams, which pass through multiple cell centers horizontally
	assert_gt(zones.size(), 0, "Should have at least one clickable zone")


func test_diagonal_seam_clickable_zones():
	# Execute a diagonal fold
	fold_system.execute_fold(Vector2i(2, 2), Vector2i(6, 6), false)

	# Get seams
	assert_eq(fold_system.seam_lines.size(), 2, "Should have 2 seam lines")

	for seam_line in fold_system.seam_lines:
		assert_true(seam_line.has_meta("clickable_zones"), "Seam should have clickable_zones metadata")
		var zones = seam_line.get_meta("clickable_zones")
		assert_true(zones is Array, "clickable_zones should be an Array")
		# Diagonal seams may pass through fewer cell centers
		# Some seams might have zero zones if they don't pass through any centers


func test_clickable_zones_are_within_grid():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 3), Vector2i(7, 3), false)

	for seam_line in fold_system.seam_lines:
		var zones = seam_line.get_meta("clickable_zones")

		# All zones should be within grid bounds
		for zone in zones:
			assert_true(zone is Vector2i, "Zone should be Vector2i")
			assert_true(zone.x >= 0, "Zone x should be >= 0")
			assert_true(zone.x < grid_manager.grid_size.x, "Zone x should be < grid_size.x")
			assert_true(zone.y >= 0, "Zone y should be >= 0")
			assert_true(zone.y < grid_manager.grid_size.y, "Zone y should be < grid_size.y")


func test_seam_line_geometry_metadata():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Check that seam has line geometry metadata
	for seam_line in fold_system.seam_lines:
		assert_true(seam_line.has_meta("line_point"), "Seam should have line_point metadata")
		assert_true(seam_line.has_meta("line_normal"), "Seam should have line_normal metadata")

		var line_point = seam_line.get_meta("line_point")
		var line_normal = seam_line.get_meta("line_normal")

		assert_true(line_point is Vector2, "line_point should be Vector2")
		assert_true(line_normal is Vector2, "line_normal should be Vector2")


func test_calculate_clickable_zones_horizontal_seam():
	# Horizontal fold creates VERTICAL seams (perpendicular to fold axis)
	# Vertical seam at x=160 (center of grid cell at x=2, cell_size=64)
	# Should pass through all cell centers with x=160 (y varies)

	var line_point = Vector2(160, 160)  # Point on vertical line
	var line_normal = Vector2(1, 0)     # Normal pointing right (vertical line)

	var zones = fold_system.calculate_clickable_zones(line_point, line_normal)

	# Should find all cells whose center has x ≈ 160
	# Cell centers are at: x = grid_pos.x * 64 + 32
	# For x=160: 160 = grid_pos.x * 64 + 32 → grid_pos.x = 2
	# So should find all cells at x=2 (y=0 to y=9)

	assert_gt(zones.size(), 0, "Should find clickable zones for vertical seam")

	# All zones should have x=2
	for zone in zones:
		assert_eq(zone.x, 2, "All zones should be at x=2 for vertical seam at x=160")


func test_calculate_clickable_zones_vertical_seam():
	# Vertical fold creates HORIZONTAL seams
	# Horizontal seam at y=160 should pass through all cells with y=2

	var line_point = Vector2(160, 160)  # Point on horizontal line
	var line_normal = Vector2(0, 1)     # Normal pointing down (horizontal line)

	var zones = fold_system.calculate_clickable_zones(line_point, line_normal)

	assert_gt(zones.size(), 0, "Should find clickable zones for horizontal seam")

	# All zones should have y=2
	for zone in zones:
		assert_eq(zone.y, 2, "All zones should be at y=2 for horizontal seam at y=160")


func test_calculate_clickable_zones_tolerance():
	# Test that zones are found within tolerance but not beyond

	var cell_size = grid_manager.cell_size
	var tolerance = cell_size * 0.15  # Default tolerance

	# Line exactly through cell center at (2, 2)
	var cell_center = Vector2(2, 2) * cell_size + Vector2(cell_size/2, cell_size/2)
	var line_point = cell_center
	var line_normal = Vector2(1, 0)  # Vertical line

	var zones = fold_system.calculate_clickable_zones(line_point, line_normal)

	# Should find cell at (2, 2)
	assert_true(Vector2i(2, 2) in zones, "Should find cell whose center is exactly on the line")


func test_clickable_zones_empty_for_seam_missing_centers():
	# Create a seam that doesn't pass through any cell centers
	# Place it between cell centers

	var cell_size = grid_manager.cell_size
	# Place line at x=64 (exactly at cell boundary, not center)
	var line_point = Vector2(64, 160)
	var line_normal = Vector2(1, 0)  # Vertical line

	var zones = fold_system.calculate_clickable_zones(line_point, line_normal)

	# This should find zero or very few zones (depending on tolerance)
	# Cell centers are at x=32, 96, 160, 224, etc.
	# Line at x=64 is 32 pixels from nearest center (tolerance is ~9.6 pixels for 64-pixel cells)
	# So should NOT find any zones
	assert_eq(zones.size(), 0, "Should find no zones for line between cell centers")


func test_multiple_folds_all_have_clickable_zones():
	# Execute multiple folds
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(6, 3), false)
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(3, 7), false)

	# All seams should have clickable_zones metadata
	for seam_line in fold_system.seam_lines:
		assert_true(seam_line.has_meta("clickable_zones"),
			"All seams should have clickable_zones metadata")

		var zones = seam_line.get_meta("clickable_zones")
		assert_true(zones is Array, "clickable_zones should be an Array")
