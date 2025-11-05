extends GutTest
## Unit Tests for Cell
##
## This test suite validates the Cell class functionality including:
## - Initialization with correct grid position and geometry
## - Center calculation
## - Point containment
## - Cell type management
## - Visual feedback
## - Seam tracking

func before_all():
	gut.p("=== Cell Test Suite ===")


func after_all():
	gut.p("=== Cell Tests Complete ===")


# ===== Initialization Tests =====

func test_cell_initialization():
	var cell = Cell.new(Vector2i(5, 3), Vector2(100, 100), 64.0)
	assert_eq(cell.grid_position, Vector2i(5, 3), "Grid position set correctly")
	assert_eq(cell.geometry.size(), 4, "Geometry has 4 vertices")
	assert_eq(cell.cell_type, 0, "Default cell type is empty (0)")
	assert_false(cell.is_partial, "Cell not partial by default")
	assert_eq(cell.seams.size(), 0, "No seams initially")


func test_square_geometry_creation():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)

	# Check vertices are in correct positions
	assert_almost_eq(cell.geometry[0], Vector2(0, 0), Vector2(0.01, 0.01), "Top-left corner")
	assert_almost_eq(cell.geometry[1], Vector2(100, 0), Vector2(0.01, 0.01), "Top-right corner")
	assert_almost_eq(cell.geometry[2], Vector2(100, 100), Vector2(0.01, 0.01), "Bottom-right corner")
	assert_almost_eq(cell.geometry[3], Vector2(0, 100), Vector2(0.01, 0.01), "Bottom-left corner")


func test_polygon_visual_created():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)
	assert_not_null(cell.polygon_visual, "Polygon2D visual created")
	assert_eq(cell.polygon_visual.polygon.size(), 4, "Visual has 4 vertices")


# ===== get_center() Tests =====

func test_get_center_square():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)
	var center = cell.get_center()

	# Square centered at (50, 50)
	assert_almost_eq(center.x, 50.0, 0.01, "Center X is 50")
	assert_almost_eq(center.y, 50.0, 0.01, "Center Y is 50")


func test_get_center_offset():
	var cell = Cell.new(Vector2i(2, 3), Vector2(200, 300), 64.0)
	var center = cell.get_center()

	# Square from (200,300) to (264,364), center at (232, 332)
	assert_almost_eq(center.x, 232.0, 0.01, "Center X correct for offset")
	assert_almost_eq(center.y, 332.0, 0.01, "Center Y correct for offset")


# ===== contains_point() Tests =====

func test_contains_point_inside():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)
	assert_true(cell.contains_point(Vector2(50, 50)), "Point inside cell")
	assert_true(cell.contains_point(Vector2(10, 10)), "Point near corner inside")
	assert_true(cell.contains_point(Vector2(99, 99)), "Point near opposite corner inside")


func test_contains_point_outside():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)
	assert_false(cell.contains_point(Vector2(-10, 50)), "Point to the left")
	assert_false(cell.contains_point(Vector2(110, 50)), "Point to the right")
	assert_false(cell.contains_point(Vector2(50, -10)), "Point above")
	assert_false(cell.contains_point(Vector2(50, 110)), "Point below")


func test_contains_point_on_edge():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)
	# Points exactly on edges should be inside (boundary condition)
	assert_true(cell.contains_point(Vector2(0, 50)), "Point on left edge")
	assert_true(cell.contains_point(Vector2(100, 50)), "Point on right edge")


# ===== is_square() Tests =====

func test_is_square_perfect_square():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)
	assert_true(cell.is_square(), "Perfect square geometry")


func test_is_square_modified_geometry():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)

	# Modify geometry to make it not square
	cell.geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(90, 100),  # Skewed
		Vector2(0, 100)
	])

	assert_false(cell.is_square(), "Modified geometry is not square")


func test_is_square_different_vertex_count():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 100.0)

	# Triangle (3 vertices)
	cell.geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])

	assert_false(cell.is_square(), "Triangle is not square")


# ===== Cell Type Tests =====

func test_set_cell_type():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	cell.set_cell_type(1)
	assert_eq(cell.cell_type, 1, "Cell type set to wall")

	cell.set_cell_type(2)
	assert_eq(cell.cell_type, 2, "Cell type set to water")

	cell.set_cell_type(3)
	assert_eq(cell.cell_type, 3, "Cell type set to goal")


func test_cell_colors():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	cell.set_cell_type(0)
	assert_eq(cell.get_cell_color(), Color(0.8, 0.8, 0.8), "Empty is light gray")

	cell.set_cell_type(1)
	assert_eq(cell.get_cell_color(), Color(0.2, 0.2, 0.2), "Wall is dark gray")

	cell.set_cell_type(2)
	assert_eq(cell.get_cell_color(), Color(0.2, 0.4, 1.0), "Water is blue")

	cell.set_cell_type(3)
	assert_eq(cell.get_cell_color(), Color(0.2, 1.0, 0.2), "Goal is green")


# ===== Seam Tracking Tests =====

func test_add_seam():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	var seam_data = {
		"angle": 45.0,
		"intersection_points": [Vector2(10, 10), Vector2(50, 50)],
		"fold_id": 1
	}

	cell.add_seam(seam_data)
	assert_eq(cell.seams.size(), 1, "Seam added")
	assert_eq(cell.seams[0]["angle"], 45.0, "Seam angle stored")
	assert_eq(cell.seams[0]["fold_id"], 1, "Seam fold_id stored")


func test_multiple_seams():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	cell.add_seam({"fold_id": 1})
	cell.add_seam({"fold_id": 2})
	cell.add_seam({"fold_id": 3})

	assert_eq(cell.seams.size(), 3, "Multiple seams tracked")


# ===== Visual Feedback Tests =====

func test_outline_color():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	assert_eq(cell.outline_color, Color.TRANSPARENT, "No outline initially")

	cell.set_outline_color(Color.RED)
	assert_eq(cell.outline_color, Color.RED, "Red outline set")


func test_hover_highlight():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	assert_false(cell.is_hovered, "Not hovered initially")

	cell.set_hover_highlight(true)
	assert_true(cell.is_hovered, "Hover enabled")

	cell.set_hover_highlight(false)
	assert_false(cell.is_hovered, "Hover disabled")


func test_clear_visual_feedback():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	cell.set_outline_color(Color.RED)
	cell.set_hover_highlight(true)

	cell.clear_visual_feedback()

	assert_eq(cell.outline_color, Color.TRANSPARENT, "Outline cleared")
	assert_false(cell.is_hovered, "Hover cleared")


# ===== Integration Tests =====

func test_cell_lifecycle():
	var cell = Cell.new(Vector2i(3, 4), Vector2(100, 200), 64.0)

	# Initialize
	assert_eq(cell.grid_position, Vector2i(3, 4), "Initialized with position")

	# Set type
	cell.set_cell_type(2)
	assert_eq(cell.cell_type, 2, "Type changed to water")

	# Add seam
	cell.add_seam({"fold_id": 1})
	assert_eq(cell.seams.size(), 1, "Seam tracked")

	# Test containment
	var center = cell.get_center()
	assert_true(cell.contains_point(center), "Contains its own center")

	# Visual feedback
	cell.set_outline_color(Color.BLUE)
	assert_eq(cell.outline_color, Color.BLUE, "Visual feedback works")
