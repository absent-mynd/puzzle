## Tests for GridManager class
##
## Tests grid initialization, cell queries, coordinate conversion,
## and anchor selection functionality.

extends GutTest

const GridManager = preload("res://scripts/core/GridManager.gd")

var grid_manager: GridManager


func before_each():
	grid_manager = GridManager.new()
	# Don't call _ready automatically in tests
	grid_manager.setup_preview_line()
	grid_manager.create_grid()


func after_each():
	if grid_manager:
		grid_manager.free()
		grid_manager = null


func test_grid_initialization():
	assert_eq(grid_manager.cells.size(), 100, "Should create 100 cells (10x10)")


func test_all_cells_have_correct_positions():
	for y in range(10):
		for x in range(10):
			var grid_pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(grid_pos)
			assert_not_null(cell, "Cell at %s should exist" % [grid_pos])
			assert_eq(cell.grid_position, grid_pos, "Cell should have correct grid position")


func test_get_cell_returns_correct_cell():
	var cell = grid_manager.get_cell(Vector2i(5, 5))
	assert_not_null(cell, "Should return cell at valid position")
	assert_eq(cell.grid_position, Vector2i(5, 5), "Should return correct cell")


func test_get_cell_returns_null_for_invalid_position():
	var cell = grid_manager.get_cell(Vector2i(-1, 0))
	assert_null(cell, "Should return null for negative position")

	cell = grid_manager.get_cell(Vector2i(10, 10))
	assert_null(cell, "Should return null for position outside grid")

	cell = grid_manager.get_cell(Vector2i(5, 15))
	assert_null(cell, "Should return null for position outside grid")


func test_is_valid_position():
	assert_true(grid_manager.is_valid_position(Vector2i(0, 0)), "Top-left should be valid")
	assert_true(grid_manager.is_valid_position(Vector2i(9, 9)), "Bottom-right should be valid")
	assert_true(grid_manager.is_valid_position(Vector2i(5, 5)), "Middle should be valid")

	assert_false(grid_manager.is_valid_position(Vector2i(-1, 0)), "Negative x should be invalid")
	assert_false(grid_manager.is_valid_position(Vector2i(0, -1)), "Negative y should be invalid")
	assert_false(grid_manager.is_valid_position(Vector2i(10, 0)), "x=10 should be invalid")
	assert_false(grid_manager.is_valid_position(Vector2i(0, 10)), "y=10 should be invalid")


func test_grid_to_world_local_conversion():
	var world_pos = grid_manager.grid_to_world_local(Vector2i(0, 0))
	assert_eq(world_pos, Vector2(0, 0), "Grid (0,0) should map to world (0,0)")

	world_pos = grid_manager.grid_to_world_local(Vector2i(1, 0))
	assert_eq(world_pos, Vector2(64, 0), "Grid (1,0) should map to world (64,0)")

	world_pos = grid_manager.grid_to_world_local(Vector2i(5, 5))
	assert_eq(world_pos, Vector2(320, 320), "Grid (5,5) should map to world (320,320)")


func test_world_to_grid_conversion():
	# Set grid origin for predictable conversion
	grid_manager.grid_origin = Vector2(100, 100)

	var grid_pos = grid_manager.world_to_grid(Vector2(100, 100))
	assert_eq(grid_pos, Vector2i(0, 0), "World (100,100) should map to grid (0,0)")

	grid_pos = grid_manager.world_to_grid(Vector2(164, 100))
	assert_eq(grid_pos, Vector2i(1, 0), "World (164,100) should map to grid (1,0)")

	grid_pos = grid_manager.world_to_grid(Vector2(420, 420))
	assert_eq(grid_pos, Vector2i(5, 5), "World (420,420) should map to grid (5,5)")


func test_get_neighbors_center_cell():
	var neighbors = grid_manager.get_neighbors(Vector2i(5, 5))
	assert_eq(neighbors.size(), 4, "Center cell should have 4 neighbors")

	# Check that all neighbors are valid
	for neighbor in neighbors:
		assert_not_null(neighbor, "Neighbor should not be null")


func test_get_neighbors_corner_cell():
	var neighbors = grid_manager.get_neighbors(Vector2i(0, 0))
	assert_eq(neighbors.size(), 2, "Corner cell should have 2 neighbors")

	neighbors = grid_manager.get_neighbors(Vector2i(9, 9))
	assert_eq(neighbors.size(), 2, "Bottom-right corner should have 2 neighbors")


func test_get_neighbors_edge_cell():
	var neighbors = grid_manager.get_neighbors(Vector2i(5, 0))
	assert_eq(neighbors.size(), 3, "Top edge cell should have 3 neighbors")

	neighbors = grid_manager.get_neighbors(Vector2i(0, 5))
	assert_eq(neighbors.size(), 3, "Left edge cell should have 3 neighbors")


func test_get_grid_bounds():
	grid_manager.grid_origin = Vector2(100, 100)
	var bounds = grid_manager.get_grid_bounds()

	assert_eq(bounds.position, Vector2(100, 100), "Bounds position should match grid origin")
	assert_eq(bounds.size, Vector2(640, 640), "Bounds size should be 10*64 x 10*64")


func test_select_first_anchor():
	grid_manager.select_cell(Vector2i(5, 5))

	assert_eq(grid_manager.selected_anchors.size(), 1, "Should have 1 selected anchor")
	assert_eq(grid_manager.selected_anchors[0], Vector2i(5, 5), "Anchor should be at (5,5)")

	var cell = grid_manager.get_cell(Vector2i(5, 5))
	assert_eq(cell.outline_color, Color.RED, "First anchor should have red outline")


func test_select_second_anchor():
	grid_manager.select_cell(Vector2i(5, 5))
	grid_manager.select_cell(Vector2i(7, 7))

	assert_eq(grid_manager.selected_anchors.size(), 2, "Should have 2 selected anchors")
	assert_eq(grid_manager.selected_anchors[1], Vector2i(7, 7), "Second anchor should be at (7,7)")

	var cell = grid_manager.get_cell(Vector2i(7, 7))
	assert_eq(cell.outline_color, Color.BLUE, "Second anchor should have blue outline")

	assert_true(grid_manager.preview_line.visible, "Preview line should be visible")


func test_third_click_clears_selection():
	grid_manager.select_cell(Vector2i(5, 5))
	grid_manager.select_cell(Vector2i(7, 7))
	grid_manager.select_cell(Vector2i(3, 3))

	assert_eq(grid_manager.selected_anchors.size(), 1, "Should have 1 anchor after third click")
	assert_eq(grid_manager.selected_anchors[0], Vector2i(3, 3), "New anchor should be at (3,3)")

	# Previous cells should have cleared outlines
	var cell1 = grid_manager.get_cell(Vector2i(5, 5))
	var cell2 = grid_manager.get_cell(Vector2i(7, 7))
	assert_eq(cell1.outline_color, Color.TRANSPARENT, "First cell outline should be cleared")
	assert_eq(cell2.outline_color, Color.TRANSPARENT, "Second cell outline should be cleared")


func test_clear_selection():
	grid_manager.select_cell(Vector2i(5, 5))
	grid_manager.select_cell(Vector2i(7, 7))
	grid_manager.clear_selection()

	assert_eq(grid_manager.selected_anchors.size(), 0, "Should have no selected anchors")
	assert_false(grid_manager.preview_line.visible, "Preview line should be hidden")

	var cell1 = grid_manager.get_cell(Vector2i(5, 5))
	var cell2 = grid_manager.get_cell(Vector2i(7, 7))
	assert_eq(cell1.outline_color, Color.TRANSPARENT, "Cell 1 outline should be cleared")
	assert_eq(cell2.outline_color, Color.TRANSPARENT, "Cell 2 outline should be cleared")


func test_get_selected_anchors():
	grid_manager.select_cell(Vector2i(2, 3))
	grid_manager.select_cell(Vector2i(8, 7))

	var anchors = grid_manager.get_selected_anchors()
	assert_eq(anchors.size(), 2, "Should return 2 anchors")
	assert_eq(anchors[0], Vector2i(2, 3), "First anchor position")
	assert_eq(anchors[1], Vector2i(8, 7), "Second anchor position")


func test_select_invalid_position_ignored():
	grid_manager.select_cell(Vector2i(-1, 0))
	assert_eq(grid_manager.selected_anchors.size(), 0, "Invalid position should be ignored")

	grid_manager.select_cell(Vector2i(10, 10))
	assert_eq(grid_manager.selected_anchors.size(), 0, "Out of bounds position should be ignored")


func test_cells_properly_positioned():
	for y in range(10):
		for x in range(10):
			var cell = grid_manager.get_cell(Vector2i(x, y))
			var expected_world_pos = grid_manager.grid_to_world_local(Vector2i(x, y))

			# Check that cell's geometry starts at the expected position
			assert_eq(cell.geometry[0], expected_world_pos,
				"Cell at (%d,%d) should be positioned at %s" % [x, y, expected_world_pos])


func test_preview_line_points():
	grid_manager.select_cell(Vector2i(0, 0))
	grid_manager.select_cell(Vector2i(9, 9))

	assert_eq(grid_manager.preview_line.points.size(), 2, "Preview line should have 2 points")

	# Get the centers of the cells
	var cell1 = grid_manager.get_cell(Vector2i(0, 0))
	var cell2 = grid_manager.get_cell(Vector2i(9, 9))

	var center1 = grid_manager.to_local(cell1.get_center())
	var center2 = grid_manager.to_local(cell2.get_center())

	assert_almost_eq(grid_manager.preview_line.points[0].x, center1.x, 0.01, "Line point 1 X")
	assert_almost_eq(grid_manager.preview_line.points[0].y, center1.y, 0.01, "Line point 1 Y")
	assert_almost_eq(grid_manager.preview_line.points[1].x, center2.x, 0.01, "Line point 2 X")
	assert_almost_eq(grid_manager.preview_line.points[1].y, center2.y, 0.01, "Line point 2 Y")


func test_multiple_selection_cycles():
	# First cycle
	grid_manager.select_cell(Vector2i(1, 1))
	grid_manager.select_cell(Vector2i(2, 2))
	grid_manager.select_cell(Vector2i(3, 3))  # Reset

	# Second cycle
	grid_manager.select_cell(Vector2i(4, 4))

	assert_eq(grid_manager.selected_anchors.size(), 2, "Should have 2 anchors")
	assert_eq(grid_manager.selected_anchors[0], Vector2i(3, 3), "First anchor from reset")
	assert_eq(grid_manager.selected_anchors[1], Vector2i(4, 4), "Second anchor from new cycle")
