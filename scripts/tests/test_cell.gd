## Space-Folding Puzzle Game - Cell Tests
##
## Test suite for the Cell class covering initialization, geometry,
## cell types, seam tracking, and visual feedback.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends GutTest

const CELL_SIZE = 64.0


## Test: Cell initialization with correct grid position
func test_cell_initialization():
	var grid_pos = Vector2i(5, 3)
	var world_pos = Vector2(100, 200)
	var cell = Cell.new(grid_pos, world_pos, CELL_SIZE)

	assert_eq(cell.grid_position, grid_pos, "Grid position should match")
	assert_eq(cell.cell_type, 0, "Default cell type should be 0 (empty)")
	assert_false(cell.is_partial, "Cell should not be partial initially")
	assert_eq(cell.seams.size(), 0, "Seams array should be empty initially")
	assert_not_null(cell.polygon_visual, "Polygon visual should be created")

	cell.free()


## Test: Square geometry creation (4 vertices in correct positions)
func test_square_geometry():
	var world_pos = Vector2(100, 200)
	var cell = Cell.new(Vector2i(0, 0), world_pos, CELL_SIZE)

	assert_eq(cell.geometry.size(), 4, "Square should have 4 vertices")

	# Check each vertex position
	assert_almost_eq(cell.geometry[0], world_pos, Vector2.ONE * 0.01, "Top-left vertex incorrect")
	assert_almost_eq(cell.geometry[1], world_pos + Vector2(CELL_SIZE, 0), Vector2.ONE * 0.01, "Top-right vertex incorrect")
	assert_almost_eq(cell.geometry[2], world_pos + Vector2(CELL_SIZE, CELL_SIZE), Vector2.ONE * 0.01, "Bottom-right vertex incorrect")
	assert_almost_eq(cell.geometry[3], world_pos + Vector2(0, CELL_SIZE), Vector2.ONE * 0.01, "Bottom-left vertex incorrect")

	cell.free()


## Test: get_center() returns correct centroid
func test_get_center():
	var world_pos = Vector2(100, 200)
	var cell = Cell.new(Vector2i(0, 0), world_pos, CELL_SIZE)

	var center = cell.get_center()
	var expected_center = world_pos + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)

	assert_almost_eq(center, expected_center, Vector2.ONE * 0.01, "Center should be at middle of square")

	cell.free()


## Test: contains_point() for points inside/outside
func test_contains_point():
	var world_pos = Vector2(100, 200)
	var cell = Cell.new(Vector2i(0, 0), world_pos, CELL_SIZE)

	# Point inside
	var point_inside = world_pos + Vector2(CELL_SIZE / 2, CELL_SIZE / 2)
	assert_true(cell.contains_point(point_inside), "Point at center should be inside")

	# Point outside
	var point_outside = world_pos + Vector2(CELL_SIZE + 10, CELL_SIZE + 10)
	assert_false(cell.contains_point(point_outside), "Point outside bounds should not be inside")

	# Point on edge (should be inside due to polygon containment algorithm)
	var point_on_edge = world_pos + Vector2(CELL_SIZE / 2, 0)
	assert_true(cell.contains_point(point_on_edge), "Point on edge should be inside")

	cell.free()


## Test: Cell type changes update correctly
func test_cell_type_changes():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	# Test empty (default)
	assert_eq(cell.cell_type, 0, "Default should be empty")
	assert_eq(cell.get_cell_color(), Color(0.8, 0.8, 0.8), "Empty color should be light gray")

	# Test wall
	cell.set_cell_type(1)
	assert_eq(cell.cell_type, 1, "Cell type should be wall")
	assert_eq(cell.get_cell_color(), Color(0.2, 0.2, 0.2), "Wall color should be dark gray")

	# Test water
	cell.set_cell_type(2)
	assert_eq(cell.cell_type, 2, "Cell type should be water")
	assert_eq(cell.get_cell_color(), Color(0.2, 0.4, 1.0), "Water color should be blue")

	# Test goal
	cell.set_cell_type(3)
	assert_eq(cell.cell_type, 3, "Cell type should be goal")
	assert_eq(cell.get_cell_color(), Color(0.2, 1.0, 0.2), "Goal color should be green")

	cell.free()


## Test: Seam data storage
func test_seam_data_storage():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	# Add first seam
	var seam1 = {
		"angle": 45.0,
		"intersection_points": [Vector2(10, 10), Vector2(20, 20)],
		"fold_id": 1
	}
	cell.add_seam(seam1)

	assert_eq(cell.seams.size(), 1, "Should have 1 seam")
	assert_true(cell.is_partial, "Cell should be marked as partial after adding seam")
	assert_eq(cell.seams[0]["fold_id"], 1, "Seam data should be stored correctly")

	# Add second seam
	var seam2 = {
		"angle": 90.0,
		"intersection_points": [Vector2(30, 30), Vector2(40, 40)],
		"fold_id": 2
	}
	cell.add_seam(seam2)

	assert_eq(cell.seams.size(), 2, "Should have 2 seams")
	assert_eq(cell.seams[1]["fold_id"], 2, "Second seam data should be stored correctly")

	cell.free()


## Test: Visual node creation and updates
func test_visual_node():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	assert_not_null(cell.polygon_visual, "Polygon visual should exist")
	assert_eq(cell.polygon_visual.polygon.size(), 4, "Visual polygon should have 4 vertices")

	# Test visual update after cell type change
	cell.set_cell_type(2)  # Water
	assert_eq(cell.polygon_visual.color, Color(0.2, 0.4, 1.0), "Visual color should update with cell type")

	cell.free()


## Test: is_square() returns true for perfect square
func test_is_square_perfect():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	assert_true(cell.is_square(), "Initial cell should be a perfect square")

	cell.free()


## Test: is_square() returns false for non-square geometry
func test_is_square_modified():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	# Modify geometry to make it not a square (triangle)
	cell.geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(CELL_SIZE, 0),
		Vector2(CELL_SIZE / 2, CELL_SIZE)
	])

	assert_false(cell.is_square(), "Triangle should not be a square")

	cell.free()


## Test: is_square() returns false for irregular quadrilateral
func test_is_square_irregular():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	# Modify to irregular quadrilateral
	cell.geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(CELL_SIZE, 0),
		Vector2(CELL_SIZE, CELL_SIZE),
		Vector2(10, CELL_SIZE)  # Not aligned with first vertex
	])

	assert_false(cell.is_square(), "Irregular quadrilateral should not be a square")

	cell.free()


## Test: Visual feedback - outline color
func test_visual_feedback_outline():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	assert_eq(cell.outline_color, Color.TRANSPARENT, "Outline should be transparent initially")

	cell.set_outline_color(Color.RED)
	assert_eq(cell.outline_color, Color.RED, "Outline color should be set to red")

	cell.free()


## Test: Visual feedback - hover highlight
func test_visual_feedback_hover():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	assert_false(cell.is_hovered, "Should not be hovered initially")

	cell.set_hover_highlight(true)
	assert_true(cell.is_hovered, "Should be hovered after setting to true")

	cell.set_hover_highlight(false)
	assert_false(cell.is_hovered, "Should not be hovered after setting to false")

	cell.free()


## Test: Visual feedback - clear all
func test_visual_feedback_clear():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)

	# Set visual feedback
	cell.set_outline_color(Color.RED)
	cell.set_hover_highlight(true)

	# Clear all
	cell.clear_visual_feedback()

	assert_eq(cell.outline_color, Color.TRANSPARENT, "Outline should be transparent after clear")
	assert_false(cell.is_hovered, "Should not be hovered after clear")

	cell.free()


## Test: Multiple cells don't interfere with each other
func test_multiple_cells_independence():
	var cell1 = Cell.new(Vector2i(0, 0), Vector2(0, 0), CELL_SIZE)
	var cell2 = Cell.new(Vector2i(1, 0), Vector2(CELL_SIZE, 0), CELL_SIZE)

	cell1.set_cell_type(1)  # Wall
	cell2.set_cell_type(2)  # Water

	assert_eq(cell1.cell_type, 1, "Cell 1 should be wall")
	assert_eq(cell2.cell_type, 2, "Cell 2 should be water")

	assert_eq(cell1.grid_position, Vector2i(0, 0), "Cell 1 grid position should be (0, 0)")
	assert_eq(cell2.grid_position, Vector2i(1, 0), "Cell 2 grid position should be (1, 0)")

	cell1.free()
	cell2.free()
