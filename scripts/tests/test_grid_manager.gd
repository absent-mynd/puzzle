extends GutTest
## Unit Tests for GridManager
##
## This test suite validates the GridManager class functionality including:
## - Grid initialization (10x10 cells)
## - Cell queries and lookups
## - Coordinate conversions
## - Neighbor finding
## - Anchor selection system

var grid_manager: GridManager


func before_each():
	# Create a fresh GridManager for each test
	grid_manager = GridManager.new()
	# Don't call _ready() as it requires a scene tree
	# Instead, manually initialize for testing
	grid_manager.create_grid()


func after_each():
	if grid_manager:
		# Free all cells first to avoid memory leaks
		for cell in grid_manager.cells.values():
			if cell:
				cell.free()
		grid_manager.cells.clear()

		# Then free the grid manager
		grid_manager.free()
	grid_manager = null


func before_all():
	gut.p("=== GridManager Test Suite ===")


func after_all():
	gut.p("=== GridManager Tests Complete ===")


# ===== Grid Initialization Tests =====

func test_grid_creates_100_cells():
	assert_eq(grid_manager.cells.size(), 100, "Creates 100 cells (10x10)")


func test_all_grid_positions_filled():
	for y in range(10):
		for x in range(10):
			var pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(pos)
			assert_not_null(cell, "Cell exists at position %s" % str(pos))


func test_cells_have_correct_grid_positions():
	for y in range(10):
		for x in range(10):
			var pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(pos)
			assert_eq(cell.grid_position, pos, "Cell at %s has correct grid_position" % str(pos))


# ===== get_cell() Tests =====

func test_get_cell_valid_position():
	var cell = grid_manager.get_cell(Vector2i(5, 5))
	assert_not_null(cell, "Returns cell at valid position")
	assert_eq(cell.grid_position, Vector2i(5, 5), "Returns correct cell")


func test_get_cell_corner_positions():
	assert_not_null(grid_manager.get_cell(Vector2i(0, 0)), "Top-left corner exists")
	assert_not_null(grid_manager.get_cell(Vector2i(9, 0)), "Top-right corner exists")
	assert_not_null(grid_manager.get_cell(Vector2i(0, 9)), "Bottom-left corner exists")
	assert_not_null(grid_manager.get_cell(Vector2i(9, 9)), "Bottom-right corner exists")


func test_get_cell_invalid_position():
	assert_null(grid_manager.get_cell(Vector2i(-1, 5)), "Returns null for negative x")
	assert_null(grid_manager.get_cell(Vector2i(5, -1)), "Returns null for negative y")
	assert_null(grid_manager.get_cell(Vector2i(10, 5)), "Returns null for x >= 10")
	assert_null(grid_manager.get_cell(Vector2i(5, 10)), "Returns null for y >= 10")


# ===== is_valid_position() Tests =====

func test_is_valid_position_valid():
	assert_true(grid_manager.is_valid_position(Vector2i(0, 0)), "Top-left is valid")
	assert_true(grid_manager.is_valid_position(Vector2i(9, 9)), "Bottom-right is valid")
	assert_true(grid_manager.is_valid_position(Vector2i(5, 5)), "Center is valid")


func test_is_valid_position_invalid():
	assert_false(grid_manager.is_valid_position(Vector2i(-1, 0)), "Negative x invalid")
	assert_false(grid_manager.is_valid_position(Vector2i(0, -1)), "Negative y invalid")
	assert_false(grid_manager.is_valid_position(Vector2i(10, 0)), "x=10 invalid")
	assert_false(grid_manager.is_valid_position(Vector2i(0, 10)), "y=10 invalid")
	assert_false(grid_manager.is_valid_position(Vector2i(100, 100)), "Far out of bounds invalid")


# ===== Coordinate Conversion Tests =====

func test_grid_to_world_origin():
	var world_pos = grid_manager.grid_to_world(Vector2i(0, 0))
	# Should be at grid_origin (initially 0,0)
	assert_almost_eq(world_pos.x, 0.0, 0.01, "Origin x")
	assert_almost_eq(world_pos.y, 0.0, 0.01, "Origin y")


func test_grid_to_world_conversion():
	var world_pos = grid_manager.grid_to_world(Vector2i(5, 3))
	# Should be at (5 * 64, 3 * 64) = (320, 192)
	assert_almost_eq(world_pos.x, 320.0, 0.01, "Grid (5,3) -> world x=320")
	assert_almost_eq(world_pos.y, 192.0, 0.01, "Grid (5,3) -> world y=192")


func test_world_to_grid_conversion():
	var grid_pos = grid_manager.world_to_grid(Vector2(320, 192))
	# Should be (320/64, 192/64) = (5, 3)
	assert_eq(grid_pos, Vector2i(5, 3), "World (320,192) -> grid (5,3)")


func test_world_to_grid_within_cell():
	# Point within a cell should map to that cell's grid position
	var grid_pos = grid_manager.world_to_grid(Vector2(330, 200))
	assert_eq(grid_pos, Vector2i(5, 3), "Point within cell (5,3) maps correctly")


func test_coordinate_conversion_roundtrip():
	var original_grid = Vector2i(7, 4)
	var world = grid_manager.grid_to_world(original_grid)
	var back_to_grid = grid_manager.world_to_grid(world)
	assert_eq(back_to_grid, original_grid, "Round-trip conversion preserves position")


# ===== get_neighbors() Tests =====

func test_get_neighbors_center_cell():
	var neighbors = grid_manager.get_neighbors(Vector2i(5, 5))
	assert_eq(neighbors.size(), 4, "Center cell has 4 neighbors")

	# Check that neighbors are adjacent
	var neighbor_positions = []
	for n in neighbors:
		neighbor_positions.append(n.grid_position)

	assert_true(Vector2i(5, 4) in neighbor_positions, "Has top neighbor")
	assert_true(Vector2i(5, 6) in neighbor_positions, "Has bottom neighbor")
	assert_true(Vector2i(4, 5) in neighbor_positions, "Has left neighbor")
	assert_true(Vector2i(6, 5) in neighbor_positions, "Has right neighbor")


func test_get_neighbors_corner_cell():
	var neighbors = grid_manager.get_neighbors(Vector2i(0, 0))
	assert_eq(neighbors.size(), 2, "Corner cell has 2 neighbors")

	var neighbor_positions = []
	for n in neighbors:
		neighbor_positions.append(n.grid_position)

	assert_true(Vector2i(1, 0) in neighbor_positions, "Has right neighbor")
	assert_true(Vector2i(0, 1) in neighbor_positions, "Has bottom neighbor")


func test_get_neighbors_edge_cell():
	var neighbors = grid_manager.get_neighbors(Vector2i(5, 0))
	assert_eq(neighbors.size(), 3, "Top edge cell has 3 neighbors")

	var neighbor_positions = []
	for n in neighbors:
		neighbor_positions.append(n.grid_position)

	assert_true(Vector2i(4, 0) in neighbor_positions, "Has left neighbor")
	assert_true(Vector2i(6, 0) in neighbor_positions, "Has right neighbor")
	assert_true(Vector2i(5, 1) in neighbor_positions, "Has bottom neighbor")


# ===== get_cell_at_world_pos() Tests =====

func test_get_cell_at_world_pos():
	var cell = grid_manager.get_cell_at_world_pos(Vector2(330, 200))
	assert_not_null(cell, "Returns cell at world position")
	assert_eq(cell.grid_position, Vector2i(5, 3), "Returns correct cell")


func test_get_cell_at_world_pos_cell_center():
	# Test at exact cell center
	var world_pos = grid_manager.grid_to_world(Vector2i(3, 3))
	world_pos += Vector2(32, 32)  # Center of 64x64 cell

	var cell = grid_manager.get_cell_at_world_pos(world_pos)
	assert_not_null(cell, "Returns cell at center")
	assert_eq(cell.grid_position, Vector2i(3, 3), "Correct cell at center")


# ===== get_grid_bounds() Tests =====

func test_get_grid_bounds():
	var bounds = grid_manager.get_grid_bounds()
	assert_eq(bounds.position, Vector2.ZERO, "Bounds start at grid origin")
	assert_almost_eq(bounds.size.x, 640.0, 0.01, "Bounds width = 10 * 64")
	assert_almost_eq(bounds.size.y, 640.0, 0.01, "Bounds height = 10 * 64")


# ===== Anchor Selection Tests =====

func test_select_first_anchor():
	grid_manager.select_cell(Vector2i(3, 3))
	assert_eq(grid_manager.selected_anchors.size(), 1, "One anchor selected")
	assert_eq(grid_manager.selected_anchors[0], Vector2i(3, 3), "Correct anchor position")


func test_select_two_anchors():
	grid_manager.select_cell(Vector2i(3, 3))
	grid_manager.select_cell(Vector2i(6, 6))

	assert_eq(grid_manager.selected_anchors.size(), 2, "Two anchors selected")
	assert_eq(grid_manager.selected_anchors[0], Vector2i(3, 3), "First anchor correct")
	assert_eq(grid_manager.selected_anchors[1], Vector2i(6, 6), "Second anchor correct")


func test_select_third_anchor_clears_selection():
	grid_manager.select_cell(Vector2i(1, 1))
	grid_manager.select_cell(Vector2i(2, 2))
	grid_manager.select_cell(Vector2i(3, 3))

	assert_eq(grid_manager.selected_anchors.size(), 1, "Selection reset to 1 anchor")
	assert_eq(grid_manager.selected_anchors[0], Vector2i(3, 3), "New first anchor")


func test_get_selected_anchors():
	grid_manager.select_cell(Vector2i(4, 4))
	grid_manager.select_cell(Vector2i(5, 5))

	var anchors = grid_manager.get_selected_anchors()
	assert_eq(anchors.size(), 2, "Returns 2 anchors")
	assert_eq(anchors[0], Vector2i(4, 4), "First anchor in array")
	assert_eq(anchors[1], Vector2i(5, 5), "Second anchor in array")


func test_clear_selection():
	grid_manager.select_cell(Vector2i(1, 1))
	grid_manager.select_cell(Vector2i(2, 2))

	grid_manager.clear_selection()

	assert_eq(grid_manager.selected_anchors.size(), 0, "Selection cleared")


# ===== Cell Type Tests =====

func test_setup_test_walls():
	grid_manager.setup_test_walls()

	# Check border cells are walls
	assert_eq(grid_manager.get_cell(Vector2i(0, 0)).cell_type, 1, "Top-left is wall")
	assert_eq(grid_manager.get_cell(Vector2i(9, 0)).cell_type, 1, "Top-right is wall")
	assert_eq(grid_manager.get_cell(Vector2i(0, 9)).cell_type, 1, "Bottom-left is wall")
	assert_eq(grid_manager.get_cell(Vector2i(9, 9)).cell_type, 1, "Bottom-right is wall")

	# Check center cell is not a wall
	assert_eq(grid_manager.get_cell(Vector2i(5, 5)).cell_type, 0, "Center is empty")


# ===== Integration Tests =====

func test_grid_manager_lifecycle():
	# Create grid
	assert_eq(grid_manager.cells.size(), 100, "Grid created")

	# Query cells
	var cell = grid_manager.get_cell(Vector2i(5, 5))
	assert_not_null(cell, "Can query cells")

	# Select anchors
	grid_manager.select_cell(Vector2i(3, 3))
	grid_manager.select_cell(Vector2i(7, 7))
	assert_eq(grid_manager.selected_anchors.size(), 2, "Anchors selected")

	# Clear selection
	grid_manager.clear_selection()
	assert_eq(grid_manager.selected_anchors.size(), 0, "Selection cleared")


func test_cells_are_properly_positioned():
	# Verify cells are positioned correctly in world space
	for y in range(10):
		for x in range(10):
			var grid_pos = Vector2i(x, y)
			var cell = grid_manager.get_cell(grid_pos)
			var expected_world_pos = Vector2(x * 64, y * 64)

			# Check that cell geometry starts at expected position
			assert_almost_eq(
				cell.geometry[0].x, expected_world_pos.x, 0.01,
				"Cell (%d,%d) x position" % [x, y]
			)
			assert_almost_eq(
				cell.geometry[0].y, expected_world_pos.y, 0.01,
				"Cell (%d,%d) y position" % [x, y]
			)
