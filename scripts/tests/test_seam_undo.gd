extends GutTest

## Tests for Phase 6: Seam-Based Undo System
##
## CRITICAL DISTINCTION:
## - UNDO (button/keyboard 'U'): Sequential action reversal, NO validation, always succeeds
##   - Restores full game state including player position
##   - Can undo any fold regardless of blocking seams or player position
##   - QoL feature that always works as a safety net
##
## - UNFOLD (seam click): Spatial puzzle mechanic, WITH validation (for future implementation)
##   - Only geometric reversal, does NOT restore player position
##   - Will be blocked by newer intersecting seams
##   - Will be blocked if player is standing on the seam
##   - Validation function can_undo_fold_seam_based() is kept for UNFOLD future use
##
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


## ============================================================================
## TASK 3: SEAM INTERSECTION VALIDATION TESTS
## ============================================================================

func test_can_undo_fold_seam_based_method_exists():
	# Execute a fold to have something to test
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Verify method exists and returns correct structure
	var result = fold_system.can_undo_fold_seam_based(0)

	assert_not_null(result, "can_undo_fold_seam_based should return a value")
	assert_true(result is Dictionary, "Should return a Dictionary")
	assert_true(result.has("valid"), "Should have 'valid' key")
	assert_true(result.has("reason"), "Should have 'reason' key")
	assert_true(result.has("blocking_seams"), "Should have 'blocking_seams' key")


func test_single_fold_is_undoable():
	# Execute a single fold
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Should be able to undo it (no newer intersecting seams)
	var result = fold_system.can_undo_fold_seam_based(0)

	assert_true(result["valid"], "Single fold should be undoable")
	assert_eq(result["blocking_seams"].size(), 0, "Should have no blocking seams")


func test_two_non_intersecting_folds_both_undoable():
	# Execute two folds that don't intersect
	# Use adjacent anchors to avoid removing cells (MIN_FOLD_DISTANCE = 0)
	# Both horizontal folds at different y positions (won't intersect)
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(3, 3), false)  # fold_id 0 (horizontal at y=3)
	fold_system.execute_fold(Vector2i(2, 5), Vector2i(3, 5), false)  # fold_id 1 (horizontal at y=5)

	# Both should be undoable (parallel horizontal lines don't intersect)
	var result_0 = fold_system.can_undo_fold_seam_based(0)
	var result_1 = fold_system.can_undo_fold_seam_based(1)

	assert_true(result_0["valid"], "First fold should be undoable (newer fold doesn't intersect)")
	assert_true(result_1["valid"], "Second fold should be undoable (no newer folds)")


func test_intersecting_folds_older_blocked():
	# Execute two folds that intersect
	# Use adjacent anchors to avoid grid size changes
	# Vertical fold at x=4
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 3), false)  # fold_id 0
	# Horizontal fold at y=4 crossing the vertical one
	fold_system.execute_fold(Vector2i(2, 4), Vector2i(3, 4), false)  # fold_id 1

	# Older fold (0) should be blocked by newer fold (1)
	var result_0 = fold_system.can_undo_fold_seam_based(0)

	assert_false(result_0["valid"], "Older fold should be blocked by intersecting newer fold")
	assert_gt(result_0["blocking_seams"].size(), 0, "Should report blocking seams")

	# Newer fold (1) should be undoable
	var result_1 = fold_system.can_undo_fold_seam_based(1)
	assert_true(result_1["valid"], "Newer fold should be undoable")


func test_parallel_seams_dont_block():
	# Execute two parallel folds (should not intersect geometrically)
	# Two horizontal folds at different y positions, adjacent anchors
	fold_system.execute_fold(Vector2i(2, 3), Vector2i(3, 3), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(2, 5), Vector2i(3, 5), false)  # fold_id 1

	# Both should be undoable (parallel seams don't intersect)
	var result_0 = fold_system.can_undo_fold_seam_based(0)

	assert_true(result_0["valid"], "Parallel seams should not block each other")


func test_three_folds_complex_intersection():
	# Execute three folds with complex intersection pattern
	# Use adjacent anchors to avoid grid size changes
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 3), false)  # fold_id 0 (vertical at x=4)
	fold_system.execute_fold(Vector2i(2, 4), Vector2i(3, 4), false)  # fold_id 1 (horizontal at y=4, crosses 0)
	fold_system.execute_fold(Vector2i(6, 2), Vector2i(6, 3), false)  # fold_id 2 (vertical at x=6)

	# Fold 0 should be blocked by fold 1 (they intersect)
	var result_0 = fold_system.can_undo_fold_seam_based(0)
	assert_false(result_0["valid"], "Fold 0 should be blocked by fold 1")

	# Fold 1 might be blocked by fold 2 if they intersect
	var result_1 = fold_system.can_undo_fold_seam_based(1)
	# Just check it returns valid structure
	assert_true(result_1.has("valid"), "Result should have valid field")

	# Fold 2 should be undoable (newest)
	var result_2 = fold_system.can_undo_fold_seam_based(2)
	assert_true(result_2["valid"], "Newest fold should always be undoable")


func test_invalid_fold_id_returns_invalid():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(7, 2), false)

	# Try to check undo for non-existent fold
	var result = fold_system.can_undo_fold_seam_based(999)

	assert_false(result["valid"], "Non-existent fold should return invalid")
	assert_true(result["reason"].length() > 0, "Should have a reason for invalid")


func test_blocking_seams_array_contains_seam_objects():
	# Execute two intersecting folds
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 7), false)  # fold_id 0 (vertical)
	fold_system.execute_fold(Vector2i(2, 4), Vector2i(7, 4), false)  # fold_id 1 (horizontal, crosses vertical)

	# Check that blocking_seams array contains actual seam objects
	var result = fold_system.can_undo_fold_seam_based(0)

	if result["blocking_seams"].size() > 0:
		var first_blocker = result["blocking_seams"][0]
		assert_true(first_blocker is Seam, "Blocking seams should be Seam objects")
		assert_true(first_blocker.fold_id > 0, "Blocking seam should have newer fold_id")


func test_undo_validation_reason_messages():
	# Execute intersecting folds
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 7), false)  # fold_id 0 (vertical)
	fold_system.execute_fold(Vector2i(2, 4), Vector2i(7, 4), false)  # fold_id 1 (horizontal)

	# Check that blocked fold has descriptive reason
	var result = fold_system.can_undo_fold_seam_based(0)

	if not result["valid"]:
		assert_true(result["reason"].length() > 0, "Should have a reason message")
		# Reason should mention blocking or intersection
		var reason_lower = result["reason"].to_lower()
		var has_meaningful_message = (
			"block" in reason_lower or
			"intersect" in reason_lower or
			"newer" in reason_lower
		)
		assert_true(has_meaningful_message, "Reason should mention blocking/intersection")


## ============================================================================
## TASK 4: MOUSE INPUT FOR SEAM CLICKING TESTS
## ============================================================================

func test_detect_seam_click_method_exists():
	# Verify the method exists
	assert_true(fold_system.has_method("detect_seam_click"),
		"FoldSystem should have detect_seam_click method")


func test_click_on_valid_zone_detects_seam():
	# Execute a horizontal fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)  # fold_id 0

	# Click at the center of a cell that the seam passes through
	# The seam should pass through cells at y=4
	# Get the center of cell (3, 4) in LOCAL coordinates
	var cell_size = grid_manager.cell_size
	var click_pos_local = Vector2(3, 4) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

	# Detect seam at this position
	var result = fold_system.detect_seam_click(click_pos_local)

	assert_not_null(result, "Should detect a seam at valid zone")
	assert_true(result.has("fold_id"), "Result should contain fold_id")
	assert_eq(result["fold_id"], 0, "Should detect fold_id 0")


func test_click_outside_zones_returns_null():
	# Execute a horizontal fold at y=4
	# This creates VERTICAL seam lines at x=3 and x=4
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Click at a position NOT on the seam lines (not at x=3 or x=4)
	var cell_size = grid_manager.cell_size
	var click_pos_local = Vector2(6, 7) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

	var result = fold_system.detect_seam_click(click_pos_local)

	assert_null(result, "Should not detect seam outside clickable zones")


func test_click_tolerance_radius():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Click near but not exactly at zone center
	var cell_size = grid_manager.cell_size
	var zone_center = Vector2(3, 4) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)
	var tolerance = cell_size * 0.25

	# Click just inside tolerance
	var click_inside = zone_center + Vector2(tolerance * 0.9, 0)
	var result_inside = fold_system.detect_seam_click(click_inside)
	assert_not_null(result_inside, "Should detect seam within tolerance radius")

	# Click just outside tolerance
	var click_outside = zone_center + Vector2(tolerance * 1.1, 0)
	var result_outside = fold_system.detect_seam_click(click_outside)
	assert_null(result_outside, "Should not detect seam outside tolerance radius")


func test_multiple_seams_selects_newest():
	# Execute two folds that pass through the same grid cell center
	# Both horizontal folds will have overlapping clickable zones
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(3, 5), Vector2i(4, 5), false)  # fold_id 1

	# Click at a position where both seams might be (test at fold 1's position)
	var cell_size = grid_manager.cell_size
	var click_pos = Vector2(3, 5) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

	var result = fold_system.detect_seam_click(click_pos)

	assert_not_null(result, "Should detect a seam")
	# Should prefer the newer fold (higher fold_id)
	assert_eq(result["fold_id"], 1, "Should select newest fold when multiple seams overlap")


func test_click_returns_complete_fold_info():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Click on the seam
	var cell_size = grid_manager.cell_size
	var click_pos = Vector2(3, 4) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

	var result = fold_system.detect_seam_click(click_pos)

	assert_not_null(result, "Should detect seam")
	assert_true(result.has("fold_id"), "Should have fold_id")
	assert_true(result.has("seam_line"), "Should have seam_line reference")
	assert_true(result.has("can_undo"), "Should have can_undo flag")


func test_click_blocked_seam_returns_blocked_status():
	# Execute two intersecting folds
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 3), false)  # fold_id 0 (vertical)
	fold_system.execute_fold(Vector2i(2, 4), Vector2i(3, 4), false)  # fold_id 1 (horizontal)

	# Click on the older seam (should be blocked)
	var cell_size = grid_manager.cell_size
	var click_pos = Vector2(4, 2) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

	var result = fold_system.detect_seam_click(click_pos)

	assert_not_null(result, "Should detect the seam")
	assert_eq(result["fold_id"], 0, "Should detect fold 0")
	assert_false(result["can_undo"], "Should indicate seam is blocked")


func test_no_seams_returns_null():
	# Don't execute any folds
	# Click anywhere
	var cell_size = grid_manager.cell_size
	var click_pos = Vector2(3, 4) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

	var result = fold_system.detect_seam_click(click_pos)

	assert_null(result, "Should return null when no seams exist")


## ============================================================================
## TASK 5: UNDO EXECUTION TESTS
## ============================================================================

func test_undo_fold_by_id_method_exists():
	# Verify the method exists
	assert_true(fold_system.has_method("undo_fold_by_id"),
		"FoldSystem should have undo_fold_by_id method")


func test_undo_fold_restores_grid_state():
	# Save initial grid state
	var initial_cell_count = grid_manager.cells.size()

	# Execute a fold (even adjacent anchors remove cells due to cut lines)
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Grid will have fewer cells after fold (cells between cut lines are removed)
	var after_fold_count = grid_manager.cells.size()
	assert_true(after_fold_count <= initial_cell_count, "Fold may remove cells")

	# Undo the fold
	var undo_result = fold_system.undo_fold_by_id(0)

	assert_true(undo_result, "Undo should succeed")
	assert_eq(grid_manager.cells.size(), initial_cell_count, "Cell count should be restored to pre-fold state")


func test_undo_fold_removes_seam_visuals():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Should have seam lines
	var seam_count_before = fold_system.seam_lines.size()
	assert_gt(seam_count_before, 0, "Should have seam lines after fold")

	# Undo the fold
	fold_system.undo_fold_by_id(0)

	# Seam lines should be removed
	assert_eq(fold_system.seam_lines.size(), 0, "Seam lines should be removed after undo")


func test_undo_fold_clears_seam_to_fold_map():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Should have entries in seam_to_fold_map
	var map_size_before = fold_system.seam_to_fold_map.size()
	assert_gt(map_size_before, 0, "Should have seam mappings after fold")

	# Undo the fold
	fold_system.undo_fold_by_id(0)

	# Map should be cleared
	assert_eq(fold_system.seam_to_fold_map.size(), 0, "Seam map should be cleared after undo")


func test_undo_fold_restores_player_position():
	# Set initial player position
	player.grid_position = Vector2i(5, 5)
	var initial_pos = player.grid_position

	# Execute a fold that shifts the player
	# Vertical fold - player should shift
	fold_system.execute_fold(Vector2i(3, 2), Vector2i(3, 3), false)

	# Player position should have changed (shifted)
	var after_fold_pos = player.grid_position

	# Undo the fold
	fold_system.undo_fold_by_id(0)

	# Player should be back at initial position
	assert_eq(player.grid_position, initial_pos, "Player position should be restored")


func test_undo_fold_removes_from_history():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Should have 1 fold in history
	var history_size_before = fold_system.fold_history.size()
	assert_eq(history_size_before, 1, "Should have 1 fold in history")

	# Undo the fold
	fold_system.undo_fold_by_id(0)

	# History should be empty
	assert_eq(fold_system.fold_history.size(), 0, "Fold should be removed from history")


func test_undo_invalid_fold_id_returns_false():
	# Execute a fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Try to undo non-existent fold
	var result = fold_system.undo_fold_by_id(999)

	assert_false(result, "Undo of non-existent fold should return false")


func test_undo_fold_with_intersecting_seams_succeeds():
	# Execute two intersecting folds
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 3), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(2, 4), Vector2i(3, 4), false)  # fold_id 1

	# UNDO behavior has NO validation - should succeed even with blocking seams
	# This is different from UNFOLD (seam click) which WILL have validation
	var result = fold_system.undo_fold_by_id(0)

	assert_true(result, "Undo should succeed even with intersecting folds (no validation for UNDO)")
	# Fold should be removed from history
	assert_eq(fold_system.fold_history.size(), 1, "First fold should be undone")


func test_multiple_undos_in_sequence():
	# Execute three folds
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(3, 5), Vector2i(4, 5), false)  # fold_id 1
	fold_system.execute_fold(Vector2i(3, 6), Vector2i(4, 6), false)  # fold_id 2

	assert_eq(fold_system.fold_history.size(), 3, "Should have 3 folds")

	# Undo newest first (fold 2)
	var result1 = fold_system.undo_fold_by_id(2)
	assert_true(result1, "First undo should succeed")
	assert_eq(fold_system.fold_history.size(), 2, "Should have 2 folds remaining")

	# Undo next (fold 1)
	var result2 = fold_system.undo_fold_by_id(1)
	assert_true(result2, "Second undo should succeed")
	assert_eq(fold_system.fold_history.size(), 1, "Should have 1 fold remaining")

	# Undo last (fold 0)
	var result3 = fold_system.undo_fold_by_id(0)
	assert_true(result3, "Third undo should succeed")
	assert_eq(fold_system.fold_history.size(), 0, "Should have no folds remaining")


func test_undo_fold_with_removed_cells():
	# Execute a fold that removes cells (non-adjacent anchors)
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(6, 4), false)

	var after_fold_count = grid_manager.cells.size()

	# Undo the fold
	var result = fold_system.undo_fold_by_id(0)

	assert_true(result, "Undo should succeed")
	# Grid should restore the removed cells
	var after_undo_count = grid_manager.cells.size()
	assert_gt(after_undo_count, after_fold_count, "Cells should be restored")


## ============================================================================
## TASK 6: SEAM VISUAL STATE TESTS
## ============================================================================

func test_update_seam_visual_states_method_exists():
	# Verify the method exists
	assert_true(fold_system.has_method("update_seam_visual_states"),
		"FoldSystem should have update_seam_visual_states method")


func test_undoable_seam_is_green():
	# Execute a single fold
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)

	# Update visual states
	fold_system.update_seam_visual_states()

	# Check that seam lines are green (undoable)
	assert_gt(fold_system.seam_lines.size(), 0, "Should have seam lines")
	for seam_line in fold_system.seam_lines:
		if seam_line and is_instance_valid(seam_line):
			# Should be green for undoable seam
			assert_eq(seam_line.default_color, Color.GREEN, "Undoable seam should be green")


func test_blocked_seam_is_red():
	# Execute two intersecting folds
	fold_system.execute_fold(Vector2i(4, 2), Vector2i(4, 3), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(2, 4), Vector2i(3, 4), false)  # fold_id 1

	# Update visual states
	fold_system.update_seam_visual_states()

	# Find seams for fold 0 (should be red/blocked)
	for seam_line in fold_system.seam_lines:
		if seam_line and is_instance_valid(seam_line):
			var seam_fold_id = seam_line.get_meta("fold_id", -1)
			if seam_fold_id == 0:
				# Older fold should be red (blocked)
				assert_eq(seam_line.default_color, Color.RED, "Blocked seam should be red")
			elif seam_fold_id == 1:
				# Newer fold should be green (undoable)
				assert_eq(seam_line.default_color, Color.GREEN, "Undoable seam should be green")


func test_seam_colors_update_after_undo():
	# Execute three folds
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(4, 4), false)  # fold_id 0
	fold_system.execute_fold(Vector2i(3, 5), Vector2i(4, 5), false)  # fold_id 1
	fold_system.execute_fold(Vector2i(3, 6), Vector2i(4, 6), false)  # fold_id 2

	# Update visual states
	fold_system.update_seam_visual_states()

	# All should be green (non-intersecting parallel folds)
	for seam_line in fold_system.seam_lines:
		if seam_line and is_instance_valid(seam_line):
			assert_eq(seam_line.default_color, Color.GREEN, "All seams should be green initially")

	# Undo the newest fold
	fold_system.undo_fold_by_id(2)

	# Update visual states again
	fold_system.update_seam_visual_states()

	# Remaining seams should still be green
	for seam_line in fold_system.seam_lines:
		if seam_line and is_instance_valid(seam_line):
			assert_eq(seam_line.default_color, Color.GREEN, "Remaining seams should be green after undo")
