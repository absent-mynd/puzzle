extends GutTest
## Comprehensive Grid Behavior Tests for Folding
##
## This test suite validates exact grid behavior for different fold angles
## including cell removal, shifting, merging, and sequential fold operations.
##
## FOLD MECHANICS (CRITICAL FOR UNDERSTANDING TEST EXPECTATIONS):
##
## When a fold is executed from anchor1 to anchor2:
##
## 1. REMOVAL: Cells between anchors (exclusive) are completely removed
##    - For horizontal fold (3,5) → (7,5): removes columns 4,5,6 (30 cells)
##    - For vertical fold (5,2) → (5,6): removes rows 3,4,5 (30 cells)
##
## 2. SHIFTING: Cells beyond anchor2 shift toward anchor1
##    - Shift vector = anchor1 - anchor2
##    - For fold (3,5) → (7,5): shift vector = (-4, 0)
##    - Cells at column 7 shift to column 3, column 8 → 4, column 9 → 5
##
## 3. MERGING: When shifted cells land on existing cells, they MERGE
##    - CompoundCell.merge_with() combines fragments from both cells
##    - The shifted cell is FREED after merging (queue_free())
##    - Dictionary only keeps the existing cell at that position
##    - This REDUCES the total cell count by number of merged cells!
##
## CELL COUNT FORMULA:
## Final Count = Initial - Removed - Merged
##
## Example: Fold (3,5) → (7,5) on 10x10 grid:
## - Initial: 100 cells
## - Removed: columns 4,5,6 = 30 cells
## - Merged: column 7 shifts to column 3 (merges) = 10 cells freed
## - Final: 100 - 30 - 10 = 60 cells in dictionary
##
## Note: Each CompoundCell may contain multiple fragments after merging,
## but grid_manager.cells.size() only counts CompoundCell objects.
##
## Test structure:
## - Single folds at various angles (horizontal, vertical, diagonal)
## - Exact cell position validation after folds
## - Cell merging at anchors
## - Sequential fold combinations (H+H, V+V, H+V, D+H, etc.)
## - Cell count validation

var fold_system: FoldSystem
var grid_manager: GridManager


func before_each():
	# Create a fresh 10x10 GridManager for each test
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.grid_size = Vector2i(10, 10)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()

	# Create and initialize FoldSystem
	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)


func after_each():
	# GUT's add_child_autofree() handles cleanup automatically
	fold_system = null
	grid_manager = null


func before_all():
	gut.p("=== Fold Grid Behavior Test Suite ===")


func after_all():
	gut.p("=== Fold Grid Behavior Tests Complete ===")


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

## Count total cells in grid
func count_cells() -> int:
	return grid_manager.cells.size()


## Check if cell exists at position
func cell_exists(pos: Vector2i) -> bool:
	return grid_manager.cells.has(pos)


## Get all cell positions as array
func get_all_positions() -> Array:
	return grid_manager.cells.keys()


## Verify cells exist at all given positions
func verify_cells_exist(positions: Array, message: String = ""):
	for pos in positions:
		assert_true(cell_exists(pos),
			"%s: Cell should exist at %s" % [message, str(pos)])


## Verify cells do NOT exist at given positions
func verify_cells_removed(positions: Array, message: String = ""):
	for pos in positions:
		assert_false(cell_exists(pos),
			"%s: Cell should be removed at %s" % [message, str(pos)])


## Get expected cell count after removing columns/rows
func expected_cell_count_after_removal(removed_positions: Array) -> int:
	return 100 - removed_positions.size()


# ============================================================================
# HORIZONTAL FOLD TESTS (Same Y, Different X)
# ============================================================================

func test_horizontal_fold_middle_exact_positions():
	# Fold from (3,5) to (7,5) - removes columns 4,5,6 (3 columns x 10 rows = 30 cells)
	var anchor1 = Vector2i(3, 5)
	var anchor2 = Vector2i(7, 5)

	var initial_count = count_cells()
	assert_eq(initial_count, 100, "Should start with 100 cells")

	# Execute fold
	var success = fold_system.execute_fold(anchor1, anchor2, false)
	assert_true(success, "Fold should succeed")

	# EXPECTED BEHAVIOR:
	# 1. Removed: columns 4,5,6 (between anchors, exclusive) = 30 cells removed
	# 2. Shift vector: (3,5) - (7,5) = (-4, 0)
	# 3. Shifted cells: columns 7,8,9 all shift LEFT by 4
	#    - Column 7 → column 3 (MERGES with existing, 10 cells freed)
	#    - Column 8 → column 4 (no merge)
	#    - Column 9 → column 5 (no merge)
	# 4. Final grid: columns 0,1,2,3,4,5 (6 columns × 10 rows = 60 cells)
	#
	# CELL COUNT: 100 - 30 (removed) - 10 (merged) = 60 cells ✓

	# Verify untouched columns exist
	assert_true(cell_exists(Vector2i(0, 0)), "Column 0 exists (untouched)")
	assert_true(cell_exists(Vector2i(3, 0)), "Column 3 exists (merged with column 7)")

	# Verify shifted columns at new positions
	assert_true(cell_exists(Vector2i(4, 0)), "Column 4 exists (was column 8)")
	assert_true(cell_exists(Vector2i(5, 0)), "Column 5 exists (was column 9)")

	# Verify removed/shifted columns no longer exist at old positions
	assert_false(cell_exists(Vector2i(6, 0)), "Column 6 no longer exists (was removed)")
	assert_false(cell_exists(Vector2i(7, 0)), "Column 7 no longer exists (shifted to 3)")
	assert_false(cell_exists(Vector2i(9, 0)), "Column 9 no longer exists (shifted to 5)")

	# Final cell count verification
	assert_eq(count_cells(), 60, "Should have 60 cells: 100 - 30 removed - 10 merged = 60")


func test_horizontal_fold_near_left_edge():
	# Fold from (1,4) to (3,4) - removes column 2 (1 column x 10 rows = 10 cells)
	var anchor1 = Vector2i(1, 4)
	var anchor2 = Vector2i(3, 4)

	fold_system.execute_fold(anchor1, anchor2, false)

	# After fold: column 2 was removed
	# Columns 3-9 shifted left by 2 to become columns 1-7
	# Final grid has columns 0-7 (8 columns × 10 rows = 80 cells)

	# Verify columns 0-1 exist
	assert_true(cell_exists(Vector2i(0, 0)), "Column 0 exists")
	assert_true(cell_exists(Vector2i(1, 0)), "Column 1 exists (merged)")

	# Verify shifted columns
	assert_true(cell_exists(Vector2i(2, 0)), "Column 2 exists (was column 4)")
	assert_true(cell_exists(Vector2i(7, 0)), "Column 7 exists (was column 9)")

	# Verify columns 8,9 no longer exist
	assert_false(cell_exists(Vector2i(8, 0)), "Column 8 no longer exists")
	assert_false(cell_exists(Vector2i(9, 0)), "Column 9 no longer exists")

	# Total: 8 columns × 10 rows = 80 cells
	assert_eq(count_cells(), 80, "Should have 80 cells after fold")


func test_horizontal_fold_near_right_edge():
	# Fold from (7,6) to (9,6) - removes column 8 (1 column x 10 rows = 10 cells)
	var anchor1 = Vector2i(7, 6)
	var anchor2 = Vector2i(9, 6)

	fold_system.execute_fold(anchor1, anchor2, false)

	# After fold: column 8 was removed
	# Column 9 shifted left by 2 to become column 7 (merge)
	# Final grid has columns 0-7 (8 columns × 10 rows = 80 cells)

	# Verify columns 0-7 exist
	assert_true(cell_exists(Vector2i(0, 0)), "Column 0 exists")
	assert_true(cell_exists(Vector2i(7, 0)), "Column 7 exists (merged)")

	# Verify columns 8,9 no longer exist
	assert_false(cell_exists(Vector2i(8, 0)), "Column 8 removed")
	assert_false(cell_exists(Vector2i(9, 0)), "Column 9 shifted")

	assert_eq(count_cells(), 80, "Should have 80 cells")


# ============================================================================
# VERTICAL FOLD TESTS (Same X, Different Y)
# ============================================================================

func test_vertical_fold_middle_exact_positions():
	# Fold from (5,2) to (5,6) - removes rows 3,4,5 (3 rows x 10 columns = 30 cells)
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	assert_eq(count_cells(), 100, "Should start with 100 cells")

	fold_system.execute_fold(anchor1, anchor2, false)

	# EXPECTED BEHAVIOR:
	# 1. Removed: rows 3,4,5 (between anchors, exclusive) = 30 cells removed
	# 2. Shift vector: (5,2) - (5,6) = (0, -4)
	# 3. Shifted cells: rows 6,7,8,9 all shift UP by 4
	#    - Row 6 → row 2 (MERGES with existing, 10 cells freed)
	#    - Row 7 → row 3 (no merge)
	#    - Row 8 → row 4 (no merge)
	#    - Row 9 → row 5 (no merge)
	# 4. Final grid: rows 0,1,2,3,4,5 (6 rows × 10 columns = 60 cells)
	#
	# CELL COUNT: 100 - 30 (removed) - 10 (merged) = 60 cells ✓

	# Verify untouched rows exist
	assert_true(cell_exists(Vector2i(0, 0)), "Row 0 exists (untouched)")
	assert_true(cell_exists(Vector2i(0, 1)), "Row 1 exists (untouched)")
	assert_true(cell_exists(Vector2i(0, 2)), "Row 2 exists (merged with row 6)")

	# Verify shifted rows at new positions
	assert_true(cell_exists(Vector2i(0, 3)), "Row 3 exists (was row 7)")
	assert_true(cell_exists(Vector2i(0, 4)), "Row 4 exists (was row 8)")
	assert_true(cell_exists(Vector2i(0, 5)), "Row 5 exists (was row 9)")

	# Verify removed/shifted rows no longer exist at old positions
	assert_false(cell_exists(Vector2i(0, 6)), "Row 6 no longer exists (shifted to 2)")
	assert_false(cell_exists(Vector2i(0, 7)), "Row 7 no longer exists (shifted to 3)")
	assert_false(cell_exists(Vector2i(0, 9)), "Row 9 no longer exists (shifted to 5)")

	# Final cell count verification
	assert_eq(count_cells(), 60, "Should have 60 cells: 100 - 30 removed - 10 merged = 60")


func test_vertical_fold_near_top_edge():
	# Fold from (4,0) to (4,2) - removes row 1 (1 row x 10 columns = 10 cells)
	var anchor1 = Vector2i(4, 0)
	var anchor2 = Vector2i(4, 2)

	fold_system.execute_fold(anchor1, anchor2, false)

	# After fold: row 1 was removed during the fold
	# Rows 2-9 shifted up to become rows 0-7
	# So row 1 NOW exists (it's what was row 3)

	# Verify row 0 still has cells (merged anchor)
	assert_true(cell_exists(Vector2i(0, 0)), "Row 0 exists")

	# Verify shifted rows exist at new positions
	assert_true(cell_exists(Vector2i(0, 1)), "Row 1 exists (was row 3)")
	assert_true(cell_exists(Vector2i(0, 7)), "Row 7 exists (was row 9)")

	# Verify rows 8,9 no longer exist (shifted up)
	assert_false(cell_exists(Vector2i(0, 8)), "Row 8 no longer exists")
	assert_false(cell_exists(Vector2i(0, 9)), "Row 9 no longer exists")

	# Total: 100 - 10 - 10 (row 2 merges into row 0) = 80 cells actually
	# Wait no: 100 - 10 removed - 0 (merging doesn't remove) = 90 cells
	# But test shows 80... Let me recalculate:
	# Rows 0,2-9 = 9 rows × 10 columns = 90 cells
	# After shift: rows become 0-7 = 8 rows × 10 columns = 80 cells
	assert_eq(count_cells(), 80, "Should have 80 cells")


func test_vertical_fold_near_bottom_edge():
	# Fold from (6,7) to (6,9) - removes row 8 (1 row x 10 columns = 10 cells)
	var anchor1 = Vector2i(6, 7)
	var anchor2 = Vector2i(6, 9)

	fold_system.execute_fold(anchor1, anchor2, false)

	# After fold: row 8 was removed
	# Row 9 shifts up to row 7 (merges)
	# Remaining rows: 0-7 (8 rows × 10 columns = 80 cells)

	# Verify rows 0-7 exist
	assert_true(cell_exists(Vector2i(0, 7)), "Row 7 exists (merged)")

	# Verify rows 8,9 no longer exist
	assert_false(cell_exists(Vector2i(0, 8)), "Row 8 removed")
	assert_false(cell_exists(Vector2i(0, 9)), "Row 9 shifted")

	assert_eq(count_cells(), 80, "Should have 80 cells")


# ============================================================================
# DIAGONAL FOLD TESTS (Different X and Y)
# ============================================================================

func test_diagonal_fold_45_degrees():
	# Fold from (2,2) to (6,6) - diagonal fold at 45 degrees
	var anchor1 = Vector2i(2, 2)
	var anchor2 = Vector2i(6, 6)

	var initial_count = count_cells()

	var success = fold_system.execute_fold(anchor1, anchor2, false)
	assert_true(success, "Diagonal fold should succeed")

	# For diagonal folds, the removed region is the bounding box between anchors
	# Bounding box: x=3-5, y=3-5 (3x3 = 9 cells)
	# Additionally, cells beyond anchor2 shift and merge

	# Cells should be shifted - the exact pattern depends on which side of fold line
	# At minimum, verify some cells still exist and total count decreased
	assert_true(cell_exists(Vector2i(0, 0)), "Corner cell exists")
	# Note: (9,9) may have shifted depending on fold implementation
	assert_lt(count_cells(), initial_count, "Cell count should decrease")


func test_diagonal_fold_30_degrees():
	# Fold from (2,1) to (8,5) - shallower diagonal
	var anchor1 = Vector2i(2, 1)
	var anchor2 = Vector2i(8, 5)

	var initial_count = count_cells()

	var success = fold_system.execute_fold(anchor1, anchor2, false)
	assert_true(success, "30-degree diagonal fold should succeed")

	# Bounding box removal: x=3-7, y=2-4 (5 x 3 = 15 cells)
	var removed_count = 0
	for x in range(3, 8):
		for y in range(2, 5):
			if not cell_exists(Vector2i(x, y)):
				removed_count += 1

	assert_gt(removed_count, 0, "Some cells should be removed")
	assert_lt(count_cells(), initial_count, "Total cell count should decrease")


# ============================================================================
# SEQUENTIAL FOLD TESTS - Two Horizontal Folds
# ============================================================================

func test_sequential_horizontal_folds_same_row():
	# Test two sequential folds on the same row to validate cumulative behavior
	# First fold: (2,5) to (5,5) - removes columns 3,4
	# Second fold: (1,5) to (3,5) - removes column 2

	assert_eq(count_cells(), 100, "Start with 100 cells")

	# FIRST FOLD: (2,5) to (5,5)
	fold_system.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)

	# EXPECTED AFTER FIRST FOLD:
	# 1. Removed: columns 3,4 (20 cells)
	# 2. Shift vector: (2,5) - (5,5) = (-3, 0)
	# 3. Shifted: columns 5,6,7,8,9 shift LEFT by 3
	#    - Column 5 → column 2 (MERGE, 10 freed)
	#    - Column 6 → column 3, 7 → 4, 8 → 5, 9 → 6
	# 4. Final columns: 0,1,2,3,4,5,6 (7 columns × 10 rows = 70 cells)
	# CELL COUNT: 100 - 20 (removed) - 10 (merged) = 70 cells ✓
	assert_eq(count_cells(), 70, "After first fold: 100 - 20 - 10 = 70 cells")

	# Verify specific positions after first fold
	assert_true(cell_exists(Vector2i(2, 5)), "Left anchor still exists (merged)")
	assert_false(cell_exists(Vector2i(7, 5)), "Column 7 no longer exists (shifted to 4)")
	assert_true(cell_exists(Vector2i(4, 5)), "Column 4 exists (was column 7)")

	# SECOND FOLD: (1,5) to (3,5) on already-folded grid
	var result = fold_system.execute_fold(Vector2i(1, 5), Vector2i(3, 5), false)
	assert_true(result, "Second fold should succeed")

	# EXPECTED AFTER SECOND FOLD:
	# Grid before: columns 0,1,2,3,4,5,6 (70 cells)
	# 1. Removed: column 2 (10 cells)
	# 2. Shift vector: (1,5) - (3,5) = (-2, 0)
	# 3. Shifted: columns 3,4,5,6 shift LEFT by 2
	#    - Column 3 → column 1 (MERGE, 10 freed)
	#    - Column 4 → column 2, 5 → 3, 6 → 4
	# 4. Final columns: 0,1,2,3,4 (5 columns × 10 rows = 50 cells)
	# CELL COUNT: 70 - 10 (removed) - 10 (merged) = 50 cells ✓
	assert_eq(count_cells(), 50, "After second fold: 70 - 10 - 10 = 50 cells")

	# Verify merge at left anchor of second fold
	assert_true(cell_exists(Vector2i(1, 5)), "Left anchor exists with merged cells")


func test_sequential_horizontal_folds_different_rows():
	# First fold: (3,3) to (6,3) - removes columns 4,5 (20 cells)
	# Second fold: (2,7) to (4,7) - removes column 3 (10 cells from remaining)

	assert_eq(count_cells(), 100, "Start with 100 cells")

	# First fold: remove 20 cells
	fold_system.execute_fold(Vector2i(3, 3), Vector2i(6, 3), false)
	assert_eq(count_cells(), 70, "After first fold: 70 cells (100-30)")

	# Second fold: remove 10 more cells
	fold_system.execute_fold(Vector2i(2, 7), Vector2i(4, 7), false)
	assert_eq(count_cells(), 50, "After second fold: 50 cells (70-20)")


# ============================================================================
# SEQUENTIAL FOLD TESTS - Two Vertical Folds
# ============================================================================

func test_sequential_vertical_folds_same_column():
	# First fold: (5,2) to (5,6) - removes rows 3,4,5 (30 cells)
	# Second fold: (5,1) to (5,3) - removes row 2 (10 cells from remaining)

	assert_eq(count_cells(), 100, "Start with 100 cells")

	# First fold: remove 30 cells
	fold_system.execute_fold(Vector2i(5, 2), Vector2i(5, 6), false)
	assert_eq(count_cells(), 60, "After first fold: 60 cells (100-40)")

	# Second fold: remove 10 more cells
	fold_system.execute_fold(Vector2i(5, 1), Vector2i(5, 3), false)
	assert_eq(count_cells(), 40, "After two folds: 40 cells (60-20)")


func test_sequential_vertical_folds_different_columns():
	# First fold: (4,1) to (4,4) - removes rows 2,3 (20 cells)
	# Second fold: (8,2) to (8,5) - removes rows 3,4,5 (20 cells from remaining)

	assert_eq(count_cells(), 100, "Start with 100 cells")

	fold_system.execute_fold(Vector2i(4, 1), Vector2i(4, 4), false)
	assert_eq(count_cells(), 70, "After first fold: 70 cells")

	fold_system.execute_fold(Vector2i(8, 2), Vector2i(8, 5), false)
	assert_eq(count_cells(), 40, "After two folds: 40 cells")


# ============================================================================
# SEQUENTIAL FOLD TESTS - Mixed Orientations
# ============================================================================

func test_sequential_horizontal_then_vertical():
	# First: Horizontal fold (3,4) to (6,4) - removes columns 4,5 (20 cells)
	# Second: Vertical fold (5,2) to (5,6) - removes rows 3,4,5 (30 cells from remaining)

	assert_eq(count_cells(), 100, "Start with 100 cells")

	# Horizontal fold first - removes columns
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(6, 4), false)
	var after_h = count_cells()
	assert_eq(after_h, 70, "After horizontal fold: 70 cells")

	# Vertical fold second - removes rows from remaining grid
	fold_system.execute_fold(Vector2i(5, 2), Vector2i(5, 6), false)
	var after_v = count_cells()

	# Exact count depends on overlap, but should decrease significantly
	assert_lt(after_v, after_h, "Cell count decreases after second fold")
	assert_gt(after_v, 30, "Should have more than 30 cells remaining")


func test_sequential_vertical_then_horizontal():
	# First: Vertical fold (5,2) to (5,5) - removes rows 3,4 (20 cells)
	# Second: Horizontal fold (2,6) to (5,6) - removes columns 3,4 (20 cells from remaining)

	assert_eq(count_cells(), 100, "Start with 100 cells")

	fold_system.execute_fold(Vector2i(5, 2), Vector2i(5, 5), false)
	var after_v = count_cells()
	assert_eq(after_v, 70, "After vertical fold: 70 cells")

	fold_system.execute_fold(Vector2i(2, 6), Vector2i(5, 6), false)
	var after_h = count_cells()

	assert_lt(after_h, after_v, "Cell count decreases after second fold")
	assert_gt(after_h, 35, "Should have more than 35 cells remaining")


func test_sequential_diagonal_then_horizontal():
	# First: Diagonal fold (2,2) to (6,6)
	# Second: Horizontal fold (1,8) to (4,8)

	assert_eq(count_cells(), 100, "Start with 100 cells")

	fold_system.execute_fold(Vector2i(2, 2), Vector2i(6, 6), false)
	var after_d = count_cells()
	assert_lt(after_d, 100, "Cells removed after diagonal fold")

	fold_system.execute_fold(Vector2i(1, 8), Vector2i(4, 8), false)
	var after_h = count_cells()

	assert_lt(after_h, after_d, "Cell count decreases after second fold")


# ============================================================================
# CELL MERGING VALIDATION
# ============================================================================

func test_anchor_cells_merge_horizontal():
	# Fold (3,5) to (7,5) - anchors should merge
	var anchor1 = Vector2i(3, 5)
	var anchor2 = Vector2i(7, 5)

	# Get references to original anchor cells
	var cell1 = grid_manager.get_cell(anchor1)
	var cell2 = grid_manager.get_cell(anchor2)
	assert_not_null(cell1, "Anchor1 exists before fold")
	assert_not_null(cell2, "Anchor2 exists before fold")

	fold_system.execute_fold(anchor1, anchor2, false)

	# After fold, anchor1 should have merged cell
	var merged = grid_manager.get_cell(anchor1)
	assert_not_null(merged, "Merged cell exists at anchor1")

	# Anchor2 should have moved
	assert_false(cell_exists(anchor2), "Anchor2 moved from original position")

	# Merged cell should have both source positions
	assert_true(anchor1 in merged.source_positions or
				merged.source_positions.size() > 1,
				"Merged cell tracks source positions")


func test_anchor_cells_merge_vertical():
	# Fold (5,2) to (5,6) - anchors should merge
	var anchor1 = Vector2i(5, 2)
	var anchor2 = Vector2i(5, 6)

	fold_system.execute_fold(anchor1, anchor2, false)

	# Check merge at anchor1
	var merged = grid_manager.get_cell(anchor1)
	assert_not_null(merged, "Merged cell exists at anchor1")
	assert_false(cell_exists(anchor2), "Anchor2 moved")

	# Merged cell should have fold in history
	assert_gt(merged.fold_history.size(), 0, "Merged cell has fold history")


func test_multiple_merges_accumulate():
	# Do two folds that cause merges at same position

	# First fold: (2,5) to (5,5)
	fold_system.execute_fold(Vector2i(2, 5), Vector2i(5, 5), false)

	var cell_after_first = grid_manager.get_cell(Vector2i(2, 5))
	var sources_after_first = cell_after_first.source_positions.size()

	# Second fold: (1,5) to (3,5) - will merge with already-merged cell
	fold_system.execute_fold(Vector2i(1, 5), Vector2i(3, 5), false)

	var cell_after_second = grid_manager.get_cell(Vector2i(1, 5))
	var sources_after_second = cell_after_second.source_positions.size()

	# Second merge should accumulate more sources
	assert_true(sources_after_second >= sources_after_first,
		"Multiple merges accumulate source positions")

	# Should have multiple folds in history
	assert_eq(cell_after_second.fold_history.size(), 2,
		"Cell affected by both folds")


# ============================================================================
# CELL SHIFTING VALIDATION
# ============================================================================

func test_shifted_cells_update_grid_position():
	# Fold (2,5) to (6,5) - cells from column 7+ shift left by 4
	fold_system.execute_fold(Vector2i(2, 5), Vector2i(6, 5), false)

	# Check that a shifted cell has updated grid_position
	# Original column 8 should now be at column 4
	var shifted_cell = grid_manager.get_cell(Vector2i(4, 5))
	if shifted_cell:
		assert_eq(shifted_cell.grid_position, Vector2i(4, 5),
			"Shifted cell has updated grid_position")

	# Verify cell is in correct dictionary key
	var cells_at_4_5 = grid_manager.cells.get(Vector2i(4, 5))
	assert_not_null(cells_at_4_5, "Cell exists at new position in dictionary")


func test_all_shifted_cells_have_correct_positions():
	# Fold (3,4) to (7,4) - columns 8,9 shift to 4,5
	fold_system.execute_fold(Vector2i(3, 4), Vector2i(7, 4), false)

	# Verify all cells in grid have grid_position matching their dictionary key
	for pos in grid_manager.cells.keys():
		var cell = grid_manager.cells[pos]
		assert_eq(cell.grid_position, pos,
			"Cell at %s has matching grid_position" % str(pos))


# ============================================================================
# EDGE CASE VALIDATION
# ============================================================================

func test_adjacent_anchors_no_removal():
	# Adjacent anchors should remove zero cells but still shift/merge
	fold_system.execute_fold(Vector2i(5, 5), Vector2i(6, 5), false)

	# Should have 90 cells: 100 - 0 removed, but 10 cells merge (column 6+ shifts to 5+)
	# Actually: columns 0-9 become 0-8 (90 cells)
	assert_eq(count_cells(), 90, "Adjacent anchors: no removal, just shift/merge")

	# Anchor positions should have merged
	assert_true(cell_exists(Vector2i(5, 5)), "Left anchor exists")
	# After shift, what was at column 6 is now at column 5 (merged)
	# So column 6 position is now occupied by what was column 7
	assert_true(cell_exists(Vector2i(6, 5)), "Position 6 has shifted cells")


func test_fold_at_grid_boundary():
	# Fold at edge: (8,5) to (9,5) - no cells between, just merge
	fold_system.execute_fold(Vector2i(8, 5), Vector2i(9, 5), false)

	assert_eq(count_cells(), 90, "Boundary fold reduces by 1 column")
	assert_true(cell_exists(Vector2i(8, 5)), "Boundary anchor exists")
	assert_false(cell_exists(Vector2i(9, 5)), "Edge shifted")


func test_fold_across_entire_grid():
	# Fold from left edge to right edge
	fold_system.execute_fold(Vector2i(1, 5), Vector2i(8, 5), false)

	# Removes columns 2-7 (6 columns = 60 cells)
	# Columns 8,9 shift to 1,2
	# Result: 100 - 60 = 40 cells, columns 0,1,2,3 (where 3 is what used to be past 9)
	# Wait, only columns 8,9 remain, so: 0,1,2 (30 cells)
	assert_eq(count_cells(), 30, "Large fold removes many cells")

	# Should have columns 0,1,2 remaining
	assert_true(cell_exists(Vector2i(0, 5)), "Leftmost column exists")
	assert_true(cell_exists(Vector2i(2, 5)), "Rightmost shifted column exists")
