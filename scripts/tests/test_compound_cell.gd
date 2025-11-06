## Unit tests for CompoundCell class
##
## Tests the Node2D container that manages multiple CellFragment instances
## and provides rendering, merging, and fold tracking functionality.

extends GutTest


## ============================================================================
## BASIC CREATION AND PROPERTIES
## ============================================================================

func test_create_compound_cell():
	var cell = CompoundCell.new(Vector2i(5, 3), 0)

	assert_not_null(cell, "Cell should be created")
	assert_eq(cell.grid_position, Vector2i(5, 3), "Position should match")
	assert_eq(cell.cell_type, 0, "Type should be 0 (empty)")
	assert_eq(cell.source_positions.size(), 1, "Should have 1 source position initially")
	assert_eq(cell.source_positions[0], Vector2i(5, 3), "Source position should match grid position")
	assert_eq(cell.get_fragment_count(), 0, "Should have no fragments initially")


func test_create_compound_cell_with_type():
	var cell = CompoundCell.new(Vector2i(2, 4), 1)  # Wall type

	assert_eq(cell.cell_type, 1, "Type should be 1 (wall)")


## ============================================================================
## FRAGMENT MANAGEMENT
## ============================================================================

func test_add_fragment():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var frag = CellFragment.new(geometry, -1)

	# Add to scene tree first (CompoundCell needs to be in tree to add children)
	add_child_autofree(cell)

	cell.add_fragment(frag)

	assert_eq(cell.get_fragment_count(), 1, "Should have 1 fragment")
	assert_eq(cell.polygon_visuals.size(), 1, "Should have 1 visual")
	assert_false(cell.is_empty(), "Cell should not be empty")


func test_add_multiple_fragments():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geom1 = PackedVector2Array([
		Vector2(0, 0), Vector2(32, 0), Vector2(32, 64), Vector2(0, 64)
	])
	var geom2 = PackedVector2Array([
		Vector2(32, 0), Vector2(64, 0), Vector2(64, 64), Vector2(32, 64)
	])

	cell.add_fragment(CellFragment.new(geom1, -1))
	cell.add_fragment(CellFragment.new(geom2, -1))

	assert_eq(cell.get_fragment_count(), 2, "Should have 2 fragments")
	assert_eq(cell.polygon_visuals.size(), 2, "Should have 2 visuals")


func test_add_degenerate_fragment_is_rejected():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	# Create degenerate fragment (only 2 vertices)
	var bad_geometry = PackedVector2Array([Vector2(0, 0), Vector2(64, 0)])
	var bad_frag = CellFragment.new(bad_geometry, -1)

	cell.add_fragment(bad_frag)

	assert_eq(cell.get_fragment_count(), 0, "Degenerate fragment should be rejected")


func test_clear_fragments():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geometry, -1))

	assert_eq(cell.get_fragment_count(), 1, "Should have 1 fragment before clear")

	cell.clear_fragments()

	assert_eq(cell.get_fragment_count(), 0, "Should have 0 fragments after clear")
	assert_eq(cell.polygon_visuals.size(), 0, "Should have 0 visuals after clear")
	assert_true(cell.is_empty(), "Cell should be empty after clear")


## ============================================================================
## GEOMETRY QUERIES
## ============================================================================

func test_get_total_area_single_fragment():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geometry, -1))

	assert_almost_eq(cell.get_total_area(), 4096.0, 1.0, "Total area should be 64x64")


func test_get_total_area_multiple_fragments():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	# Two 32x64 rectangles = 2048 each, total 4096
	var geom1 = PackedVector2Array([
		Vector2(0, 0), Vector2(32, 0), Vector2(32, 64), Vector2(0, 64)
	])
	var geom2 = PackedVector2Array([
		Vector2(32, 0), Vector2(64, 0), Vector2(64, 64), Vector2(32, 64)
	])

	cell.add_fragment(CellFragment.new(geom1, -1))
	cell.add_fragment(CellFragment.new(geom2, -1))

	assert_almost_eq(cell.get_total_area(), 4096.0, 1.0, "Total area should be sum of fragments")


func test_get_center_single_fragment():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geometry, -1))

	var center = cell.get_center()

	assert_almost_eq(center.x, 32.0, 0.1, "Center X should be 32")
	assert_almost_eq(center.y, 32.0, 0.1, "Center Y should be 32")


func test_get_center_multiple_fragments_weighted():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	# Two fragments of equal area - center should be at midpoint
	var geom1 = PackedVector2Array([
		Vector2(0, 0), Vector2(32, 0), Vector2(32, 64), Vector2(0, 64)
	])
	var geom2 = PackedVector2Array([
		Vector2(32, 0), Vector2(64, 0), Vector2(64, 64), Vector2(32, 64)
	])

	cell.add_fragment(CellFragment.new(geom1, -1))
	cell.add_fragment(CellFragment.new(geom2, -1))

	var center = cell.get_center()

	# Weighted centroid should be at (32, 32) since equal areas
	assert_almost_eq(center.x, 32.0, 1.0, "Weighted center X should be 32")
	assert_almost_eq(center.y, 32.0, 1.0, "Weighted center Y should be 32")


func test_contains_point():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geometry, -1))

	assert_true(cell.contains_point(Vector2(32, 32)), "Point inside should be contained")
	assert_true(cell.contains_point(Vector2(10, 10)), "Point inside should be contained")
	assert_false(cell.contains_point(Vector2(100, 100)), "Point outside should not be contained")
	assert_false(cell.contains_point(Vector2(-10, -10)), "Point outside should not be contained")


func test_get_bounding_rect():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geometry = PackedVector2Array([
		Vector2(10, 20), Vector2(50, 20), Vector2(50, 80), Vector2(10, 80)
	])
	cell.add_fragment(CellFragment.new(geometry, -1))

	var bounds = cell.get_bounding_rect()

	assert_almost_eq(bounds.position.x, 10.0, 0.1, "Bounds min X should be 10")
	assert_almost_eq(bounds.position.y, 20.0, 0.1, "Bounds min Y should be 20")
	assert_almost_eq(bounds.size.x, 40.0, 0.1, "Bounds width should be 40")
	assert_almost_eq(bounds.size.y, 60.0, 0.1, "Bounds height should be 60")


## ============================================================================
## MERGING OPERATIONS
## ============================================================================

func test_merge_cells_basic():
	var cell1 = CompoundCell.new(Vector2i(0, 0), 0)  # Empty
	var cell2 = CompoundCell.new(Vector2i(1, 0), 1)  # Wall

	add_child_autofree(cell1)
	add_child_autofree(cell2)

	var geom1 = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var geom2 = PackedVector2Array([
		Vector2(64, 0), Vector2(128, 0), Vector2(128, 64), Vector2(64, 64)
	])

	cell1.add_fragment(CellFragment.new(geom1, -1))
	cell2.add_fragment(CellFragment.new(geom2, 2))

	cell1.merge_with(cell2, 5)

	assert_eq(cell1.get_fragment_count(), 2, "Cell1 should have 2 fragments after merge")
	assert_eq(cell1.source_positions.size(), 2, "Cell1 should have 2 source positions")
	assert_true(Vector2i(0, 0) in cell1.source_positions, "Should have original source position")
	assert_true(Vector2i(1, 0) in cell1.source_positions, "Should have merged source position")


func test_merge_cells_type_priority():
	var cell_empty = CompoundCell.new(Vector2i(0, 0), 0)  # Empty
	var cell_wall = CompoundCell.new(Vector2i(1, 0), 1)   # Wall
	var cell_water = CompoundCell.new(Vector2i(2, 0), 2)  # Water
	var cell_goal = CompoundCell.new(Vector2i(3, 0), 3)   # Goal

	add_child_autofree(cell_empty)
	add_child_autofree(cell_wall)
	add_child_autofree(cell_water)
	add_child_autofree(cell_goal)

	var geom = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell_empty.add_fragment(CellFragment.new(geom, -1))
	cell_wall.add_fragment(CellFragment.new(geom, -1))
	cell_water.add_fragment(CellFragment.new(geom, -1))
	cell_goal.add_fragment(CellFragment.new(geom, -1))

	# Goal > Wall
	cell_goal.merge_with(cell_wall, 1)
	assert_eq(cell_goal.cell_type, 3, "Goal should remain when merging with wall")

	# Wall > Water
	cell_wall.merge_with(cell_water, 2)
	assert_eq(cell_wall.cell_type, 1, "Wall should remain when merging with water")

	# Water > Empty
	cell_water.merge_with(cell_empty, 3)
	assert_eq(cell_water.cell_type, 2, "Water should remain when merging with empty")


func test_merge_adds_fold_to_history():
	var cell1 = CompoundCell.new(Vector2i(0, 0), 0)
	var cell2 = CompoundCell.new(Vector2i(1, 0), 0)

	add_child_autofree(cell1)
	add_child_autofree(cell2)

	var geom = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell1.add_fragment(CellFragment.new(geom, -1))
	cell2.add_fragment(CellFragment.new(geom, -1))

	cell1.add_fold_to_history(3)
	cell2.add_fold_to_history(7)

	cell1.merge_with(cell2, 10)

	# Should have folds 3, 7, and 10
	assert_true(cell1.is_affected_by_fold(3), "Should have fold 3")
	assert_true(cell1.is_affected_by_fold(7), "Should have fold 7")
	assert_true(cell1.is_affected_by_fold(10), "Should have fold 10 (merge fold)")


## ============================================================================
## FOLD HISTORY TRACKING
## ============================================================================

func test_add_fold_to_history():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	cell.add_fold_to_history(5)
	cell.add_fold_to_history(10)

	assert_eq(cell.fold_history.size(), 2, "Should have 2 folds in history")
	assert_eq(cell.fold_history[0], 5, "First fold should be 5")
	assert_eq(cell.fold_history[1], 10, "Second fold should be 10")


func test_add_fold_to_history_no_duplicates():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	cell.add_fold_to_history(5)
	cell.add_fold_to_history(5)  # Duplicate

	assert_eq(cell.fold_history.size(), 1, "Should not add duplicate fold")


func test_is_affected_by_fold():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	cell.add_fold_to_history(5)
	cell.add_fold_to_history(10)

	assert_true(cell.is_affected_by_fold(5), "Should be affected by fold 5")
	assert_true(cell.is_affected_by_fold(10), "Should be affected by fold 10")
	assert_false(cell.is_affected_by_fold(99), "Should not be affected by fold 99")


func test_get_newest_fold():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	assert_eq(cell.get_newest_fold(), -1, "Should return -1 when no folds")

	cell.add_fold_to_history(3)
	assert_eq(cell.get_newest_fold(), 3, "Newest fold should be 3")

	cell.add_fold_to_history(7)
	assert_eq(cell.get_newest_fold(), 7, "Newest fold should be 7")


func test_get_fold_history():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	cell.add_fold_to_history(1)
	cell.add_fold_to_history(5)
	cell.add_fold_to_history(10)

	var history = cell.get_fold_history()

	assert_eq(history.size(), 3, "History should have 3 folds")
	assert_eq(history[0], 1, "First fold should be 1")
	assert_eq(history[1], 5, "Second fold should be 5")
	assert_eq(history[2], 10, "Third fold should be 10")


## ============================================================================
## CELL TYPE & VISUALS
## ============================================================================

func test_set_cell_type():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geom = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geom, -1))

	cell.set_cell_type(1)  # Wall

	assert_eq(cell.cell_type, 1, "Type should be updated to wall")
	# Visual should be updated (color changed)
	assert_eq(cell.polygon_visuals[0].color, cell.get_cell_color(), "Visual color should match cell type")


func test_get_cell_color():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	assert_eq(cell.get_cell_color(), Color(0.8, 0.8, 0.8), "Empty should be light gray")

	cell.cell_type = 1
	assert_eq(cell.get_cell_color(), Color(0.2, 0.2, 0.2), "Wall should be dark gray")

	cell.cell_type = 2
	assert_eq(cell.get_cell_color(), Color(0.2, 0.4, 1.0), "Water should be blue")

	cell.cell_type = 3
	assert_eq(cell.get_cell_color(), Color(0.2, 1.0, 0.2), "Goal should be green")


## ============================================================================
## SPLITTING SUPPORT
## ============================================================================

func test_split_fragment_diagonal():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geometry, -1))

	# Split diagonally
	var line_point = Vector2(32, 32)
	var line_normal = Vector2(0.707, 0.707).normalized()
	var result = cell.split_fragment(0, line_point, line_normal, 5)

	assert_false(result.is_empty(), "Split should succeed")
	assert_not_null(result.get("left"), "Should have left fragment")
	assert_not_null(result.get("right"), "Should have right fragment")
	assert_gt(result.left.get_area(), 0, "Left fragment should have area")
	assert_gt(result.right.get_area(), 0, "Right fragment should have area")


func test_split_fragment_invalid_index():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geometry, -1))

	var result = cell.split_fragment(999, Vector2(32, 32), Vector2(1, 0), 5)

	assert_true(result.is_empty(), "Split with invalid index should return empty dict")


func test_split_all_fragments():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	# Add two fragments
	var geom1 = PackedVector2Array([
		Vector2(0, 0), Vector2(32, 0), Vector2(32, 64), Vector2(0, 64)
	])
	var geom2 = PackedVector2Array([
		Vector2(32, 0), Vector2(64, 0), Vector2(64, 64), Vector2(32, 64)
	])
	cell.add_fragment(CellFragment.new(geom1, -1))
	cell.add_fragment(CellFragment.new(geom2, -1))

	# Split vertically at x=32
	var line_point = Vector2(32, 32)
	var line_normal = Vector2(1, 0)
	var result = cell.split_all_fragments(line_point, line_normal, 5)

	assert_true(result.has("left_fragments"), "Should have left_fragments key")
	assert_true(result.has("right_fragments"), "Should have right_fragments key")

	# Both fragments intersect the line, so we should get splits
	var left_count = result.left_fragments.size()
	var right_count = result.right_fragments.size()

	assert_gt(left_count + right_count, 0, "Should have fragments after split")


## ============================================================================
## VALIDATION
## ============================================================================

func test_validate_valid_cell():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	var geom = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geom, -1))

	assert_true(cell.validate(), "Valid cell should pass validation")


func test_validate_detects_fragment_visual_mismatch():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)
	add_child_autofree(cell)

	# Manually create mismatch by adding fragment without going through add_fragment
	var geom = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.fragments.append(CellFragment.new(geom, -1))

	# Now fragments and polygon_visuals are out of sync
	assert_false(cell.validate(), "Should detect fragment/visual mismatch")


## ============================================================================
## EDGE CASES
## ============================================================================

func test_empty_cell_get_center_fallback():
	var cell = CompoundCell.new(Vector2i(5, 3), 0)

	# No fragments, should use fallback calculation
	var center = cell.get_center()

	# Should return approximately (5*64 + 32, 3*64 + 32) = (352, 224) with 64px cells
	# But since cell is not in tree, it won't know cell_size, so will use default 64
	assert_not_null(center, "Should return a center even without fragments")


func test_get_total_area_empty_cell():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	assert_eq(cell.get_total_area(), 0.0, "Empty cell should have zero area")


func test_contains_point_empty_cell():
	var cell = CompoundCell.new(Vector2i(0, 0), 0)

	assert_false(cell.contains_point(Vector2(32, 32)), "Empty cell should not contain points")


func test_to_string():
	var cell = CompoundCell.new(Vector2i(5, 3), 1)
	add_child_autofree(cell)

	var geom = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	cell.add_fragment(CellFragment.new(geom, -1))
	cell.add_fold_to_history(7)

	var str_repr = str(cell)

	assert_string_contains(str_repr, "CompoundCell", "String should contain class name")
	assert_string_contains(str_repr, "5", "String should contain grid position X")
	assert_string_contains(str_repr, "3", "String should contain grid position Y")
	assert_string_contains(str_repr, "1", "String should contain cell type")
