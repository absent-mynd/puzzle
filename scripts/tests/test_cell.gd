## Tests for Cell class
##
## Tests cell initialization, geometry, cell types, visual feedback,
## and other cell functionality.

extends GutTest

const Cell = preload("res://scripts/core/Cell.gd")

var cell: Cell


func before_each():
	# Create a cell at grid position (5, 5) with world position (100, 100) and size 64
	cell = Cell.new(Vector2i(5, 5), Vector2(100, 100), 64.0)


func after_each():
	if cell:
		cell.free()
		cell = null


func test_cell_initialization():
	assert_eq(cell.grid_position, Vector2i(5, 5), "Grid position should be set correctly")
	assert_eq(cell.cell_type, 0, "Cell type should default to 0 (empty)")
	assert_false(cell.is_partial, "Cell should not be partial initially")
	assert_eq(cell.seams.size(), 0, "Cell should have no seams initially")


func test_square_geometry_creation():
	assert_eq(cell.geometry.size(), 4, "Cell should have 4 vertices")

	# Check vertices are in correct positions
	assert_eq(cell.geometry[0], Vector2(100, 100), "Top-left vertex")
	assert_eq(cell.geometry[1], Vector2(164, 100), "Top-right vertex")
	assert_eq(cell.geometry[2], Vector2(164, 164), "Bottom-right vertex")
	assert_eq(cell.geometry[3], Vector2(100, 164), "Bottom-left vertex")


func test_get_center():
	var center = cell.get_center()
	assert_almost_eq(center.x, 132.0, 0.01, "Center X should be 132")
	assert_almost_eq(center.y, 132.0, 0.01, "Center Y should be 132")


func test_contains_point_inside():
	# Point inside the cell
	assert_true(cell.contains_point(Vector2(132, 132)), "Should contain center point")
	assert_true(cell.contains_point(Vector2(110, 110)), "Should contain point near top-left")
	assert_true(cell.contains_point(Vector2(150, 150)), "Should contain point in middle")


func test_contains_point_outside():
	# Points outside the cell
	assert_false(cell.contains_point(Vector2(50, 50)), "Should not contain point to the left")
	assert_false(cell.contains_point(Vector2(200, 200)), "Should not contain point to the right")
	assert_false(cell.contains_point(Vector2(132, 50)), "Should not contain point above")
	assert_false(cell.contains_point(Vector2(132, 200)), "Should not contain point below")


func test_contains_point_on_edge():
	# Points on the edge (should be inside due to polygon algorithm)
	assert_true(cell.contains_point(Vector2(100, 132)), "Point on left edge")
	assert_true(cell.contains_point(Vector2(132, 100)), "Point on top edge")


func test_is_square():
	assert_true(cell.is_square(), "Initial geometry should be a perfect square")


func test_is_not_square_after_modification():
	# Modify geometry to make it not a square
	cell.geometry[2] = Vector2(170, 164)  # Change one vertex
	assert_false(cell.is_square(), "Modified geometry should not be a square")


func test_set_cell_type():
	cell.set_cell_type(1)
	assert_eq(cell.cell_type, 1, "Cell type should update to 1 (wall)")

	cell.set_cell_type(2)
	assert_eq(cell.cell_type, 2, "Cell type should update to 2 (water)")

	cell.set_cell_type(3)
	assert_eq(cell.cell_type, 3, "Cell type should update to 3 (goal)")


func test_get_cell_color():
	assert_eq(cell.get_cell_color(), Color(0.8, 0.8, 0.8), "Empty cell should be light gray")

	cell.set_cell_type(1)
	assert_eq(cell.get_cell_color(), Color(0.2, 0.2, 0.2), "Wall cell should be dark gray")

	cell.set_cell_type(2)
	assert_eq(cell.get_cell_color(), Color(0.2, 0.4, 1.0), "Water cell should be blue")

	cell.set_cell_type(3)
	assert_eq(cell.get_cell_color(), Color(0.2, 1.0, 0.2), "Goal cell should be green")


func test_add_seam():
	var seam_data = {
		"angle": 45.0,
		"intersection_points": [Vector2(100, 100), Vector2(164, 164)],
		"fold_id": 1
	}

	cell.add_seam(seam_data)
	assert_eq(cell.seams.size(), 1, "Should have 1 seam after adding")
	assert_eq(cell.seams[0]["angle"], 45.0, "Seam data should be stored correctly")


func test_set_outline_color():
	cell.set_outline_color(Color.RED)
	assert_eq(cell.outline_color, Color.RED, "Outline color should be set to red")

	cell.set_outline_color(Color.BLUE)
	assert_eq(cell.outline_color, Color.BLUE, "Outline color should be set to blue")


func test_set_hover_highlight():
	cell.set_hover_highlight(true)
	assert_true(cell.is_hovered, "Cell should be marked as hovered")

	cell.set_hover_highlight(false)
	assert_false(cell.is_hovered, "Cell should not be hovered")


func test_clear_visual_feedback():
	cell.set_outline_color(Color.RED)
	cell.set_hover_highlight(true)

	cell.clear_visual_feedback()

	assert_eq(cell.outline_color, Color.TRANSPARENT, "Outline color should be transparent")
	assert_false(cell.is_hovered, "Cell should not be hovered")


func test_multiple_seams():
	cell.add_seam({"fold_id": 1})
	cell.add_seam({"fold_id": 2})
	cell.add_seam({"fold_id": 3})

	assert_eq(cell.seams.size(), 3, "Should track multiple seams")
