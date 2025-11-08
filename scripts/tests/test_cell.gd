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


## ============================================================================
## PHASE 5: MULTI-POLYGON SUPPORT TESTS
## ============================================================================

## Test: Cell initializes with one piece
func test_multi_piece_cell_creation():
	var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), CELL_SIZE)

	assert_eq(cell.geometry_pieces.size(), 1, "New cell should have 1 piece")
	assert_not_null(cell.geometry_pieces[0], "First piece should exist")
	assert_eq(cell.geometry_pieces[0].geometry.size(), 4, "First piece should be a square")

	cell.free()


## Test: Add piece to cell
func test_add_piece_to_cell():
	var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), CELL_SIZE)

	var new_geometry = PackedVector2Array([
		Vector2(128, 64), Vector2(192, 64),
		Vector2(192, 128), Vector2(128, 128)
	])
	var new_piece = CellPiece.new(new_geometry, 1, 0)  # Wall

	cell.add_piece(new_piece)

	assert_eq(cell.geometry_pieces.size(), 2, "Cell should have 2 pieces after adding")

	cell.free()


## Test: Get cell types from multi-piece cell
func test_get_cell_types():
	var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), CELL_SIZE)

	# Initial cell has type 0 (empty)
	var types = cell.get_cell_types()
	assert_eq(types.size(), 1, "Should have 1 type initially")
	assert_has(types, 0, "Should contain empty type")

	# Add pieces of different types
	cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 0))  # Wall
	cell.add_piece(CellPiece.new(PackedVector2Array(), 2, 1))  # Water

	types = cell.get_cell_types()
	assert_eq(types.size(), 3, "Should have 3 types")
	assert_has(types, 0, "Should contain empty type")
	assert_has(types, 1, "Should contain wall type")
	assert_has(types, 2, "Should contain water type")

	cell.free()


## Test: Dominant type - Goal dominates all
func test_get_dominant_type_goal():
	var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), CELL_SIZE)

	cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 0))  # Wall
	cell.add_piece(CellPiece.new(PackedVector2Array(), 2, 1))  # Water
	cell.add_piece(CellPiece.new(PackedVector2Array(), 3, 2))  # Goal

	assert_eq(cell.get_dominant_type(), 3, "Goal should dominate")

	cell.free()


## Test: Dominant type - Wall dominates water and empty
func test_get_dominant_type_wall():
	var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), CELL_SIZE)

	cell.add_piece(CellPiece.new(PackedVector2Array(), 2, 0))  # Water

	assert_eq(cell.get_dominant_type(), 2, "Water should dominate empty")

	cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 1))  # Wall

	assert_eq(cell.get_dominant_type(), 1, "Wall should dominate over water")

	cell.free()


## Test: Dominant type - Water dominates empty
func test_get_dominant_type_water():
	var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), CELL_SIZE)

	# Initial piece is empty (type 0)
	assert_eq(cell.get_dominant_type(), 0, "Should be empty initially")

	cell.add_piece(CellPiece.new(PackedVector2Array(), 2, 0))  # Water

	assert_eq(cell.get_dominant_type(), 2, "Water should dominate empty")

	cell.free()


## Test: has_cell_type()
func test_has_cell_type():
	var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), CELL_SIZE)

	# Initial cell has type 0
	assert_true(cell.has_cell_type(0), "Should have empty type")
	assert_false(cell.has_cell_type(1), "Should not have wall type")

	cell.add_piece(CellPiece.new(PackedVector2Array(), 2, 0))  # Water

	assert_true(cell.has_cell_type(0), "Should still have empty type")
	assert_true(cell.has_cell_type(2), "Should have water type")
	assert_false(cell.has_cell_type(1), "Should not have wall type")

	cell.free()


## Test: get_total_area()
func test_get_total_area():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	# Initial square 64x64 = 4096
	var initial_area = cell.get_total_area()
	assert_almost_eq(initial_area, 4096.0, 0.1, "Initial area should be 4096")

	# Add another 64x64 piece
	var piece_geometry = PackedVector2Array([
		Vector2(64, 0), Vector2(128, 0),
		Vector2(128, 64), Vector2(64, 64)
	])
	cell.add_piece(CellPiece.new(piece_geometry, 1, 0))

	var total_area = cell.get_total_area()
	assert_almost_eq(total_area, 8192.0, 0.1, "Total area should be 8192 (two 64x64 squares)")

	cell.free()


## Test: get_center() with multiple pieces
func test_get_center_multi_piece():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	# Initial piece centered at (32, 32)
	var center1 = cell.get_center()
	assert_almost_eq(center1.x, 32.0, 0.1, "Single piece center x should be 32")
	assert_almost_eq(center1.y, 32.0, 0.1, "Single piece center y should be 32")

	# Add piece to the right (64-128, 0-64), centered at (96, 32)
	var piece_geometry = PackedVector2Array([
		Vector2(64, 0), Vector2(128, 0),
		Vector2(128, 64), Vector2(64, 64)
	])
	cell.add_piece(CellPiece.new(piece_geometry, 1, 0))

	# Weighted center should be at (64, 32) - midpoint between two equal-area pieces
	var center2 = cell.get_center()
	assert_almost_eq(center2.x, 64.0, 0.1, "Multi-piece center x should be 64")
	assert_almost_eq(center2.y, 32.0, 0.1, "Multi-piece center y should be 32")

	cell.free()


## Test: Legacy geometry accessor
func test_geometry_accessor_backward_compatibility():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	# Getter should return first piece's geometry
	assert_eq(cell.geometry.size(), 4, "Geometry getter should return 4 vertices")

	# Setter should update first piece
	var new_geometry = PackedVector2Array([
		Vector2(10, 10), Vector2(50, 10),
		Vector2(50, 50), Vector2(10, 50)
	])
	cell.geometry = new_geometry

	assert_eq(cell.geometry_pieces[0].geometry.size(), 4, "First piece should have updated geometry")
	assert_eq(cell.geometry_pieces[0].geometry[0], Vector2(10, 10), "First vertex should match")

	cell.free()


## Test: add_piece updates dominant type
func test_add_piece_updates_dominant_type():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	assert_eq(cell.cell_type, 0, "Initial cell_type should be 0 (empty)")

	# Add wall piece
	cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 0))

	assert_eq(cell.cell_type, 1, "cell_type should update to 1 (wall) after adding wall piece")

	# Add goal piece
	cell.add_piece(CellPiece.new(PackedVector2Array(), 3, 1))

	assert_eq(cell.cell_type, 3, "cell_type should update to 3 (goal) after adding goal piece")

	cell.free()


## ============================================================================
## PHASE 5: VISUAL RENDERING TESTS
## ============================================================================

## Test: Single piece uses legacy rendering
func test_single_piece_uses_legacy_rendering():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)
	add_child_autofree(cell)

	# Single piece should use legacy polygon_visual
	assert_not_null(cell.polygon_visual, "polygon_visual should exist")
	assert_true(cell.polygon_visual.visible, "polygon_visual should be visible for single piece")
	assert_eq(cell.piece_visuals.get_child_count(), 0, "piece_visuals should be empty for single piece")

	cell.free()


## Test: Multi-piece creates separate visuals
func test_multi_piece_creates_separate_visuals():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)
	add_child_autofree(cell)

	# Add second piece
	var piece_geometry = PackedVector2Array([
		Vector2(64, 0), Vector2(128, 0),
		Vector2(128, 64), Vector2(64, 64)
	])
	cell.add_piece(CellPiece.new(piece_geometry, 1, 0))

	# Should now use piece_visuals container
	assert_false(cell.polygon_visual.visible, "polygon_visual should be hidden for multi-piece")
	assert_eq(cell.piece_visuals.get_child_count(), 4, "Should have 4 children (2 polygons + 2 borders)")

	# Check that we have both Polygon2D and Line2D nodes
	var polygon_count = 0
	var line_count = 0
	for child in cell.piece_visuals.get_children():
		if child is Polygon2D:
			polygon_count += 1
		elif child is Line2D:
			line_count += 1

	assert_eq(polygon_count, 2, "Should have 2 Polygon2D nodes")
	assert_eq(line_count, 2, "Should have 2 Line2D borders")

	cell.free()


## Test: Piece visuals have correct colors
func test_piece_visuals_have_correct_colors():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)
	add_child_autofree(cell)

	# Set first piece to wall
	cell.geometry_pieces[0].cell_type = 1

	# Add water piece
	var piece_geometry = PackedVector2Array([
		Vector2(64, 0), Vector2(128, 0),
		Vector2(128, 64), Vector2(64, 64)
	])
	cell.add_piece(CellPiece.new(piece_geometry, 2, 0))  # Water

	# Find the polygon visuals
	var polygons: Array[Polygon2D] = []
	for child in cell.piece_visuals.get_children():
		if child is Polygon2D:
			polygons.append(child)

	assert_eq(polygons.size(), 2, "Should have 2 polygon visuals")

	# Check colors match cell types
	var wall_color = cell.get_cell_color_for_type(1)
	var water_color = cell.get_cell_color_for_type(2)

	# First polygon should be wall (dark gray)
	assert_eq(polygons[0].color, wall_color, "First polygon should have wall color")

	# Second polygon should be water (blue)
	assert_eq(polygons[1].color, water_color, "Second polygon should have water color")

	cell.free()


## Test: Seam visualization creates Line2D nodes
func test_seam_visualization_creates_line_nodes():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)
	add_child_autofree(cell)

	# Add second piece with seam
	var piece_geometry = PackedVector2Array([
		Vector2(64, 0), Vector2(128, 0),
		Vector2(128, 64), Vector2(64, 64)
	])
	var piece = CellPiece.new(piece_geometry, 1, 0)

	# Add seam to piece
	var seam = Seam.new(
		Vector2(64, 0),
		Vector2(1, 0),
		PackedVector2Array([Vector2(64, 0), Vector2(64, 64)]),
		1,
		0,
		"vertical"
	)
	piece.add_seam(seam)

	cell.add_piece(piece)

	# Seam visuals should have been created
	assert_gt(cell.seam_visuals.get_child_count(), 0, "Should have seam visuals")

	# Check that seam line exists
	var seam_lines = 0
	for child in cell.seam_visuals.get_children():
		if child is Line2D:
			seam_lines += 1

	assert_eq(seam_lines, 1, "Should have 1 seam line")

	cell.free()


## Test: Visual cleanup when updating
func test_visual_cleanup_when_updating():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)
	add_child_autofree(cell)

	# Add multiple pieces
	cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 0))
	var initial_count = cell.piece_visuals.get_child_count()
	assert_gt(initial_count, 0, "Should have piece visuals")

	# Update visual again
	cell.update_visual()

	# Should not have duplicated visuals
	assert_eq(cell.piece_visuals.get_child_count(), initial_count, "Should not duplicate visuals on update")

	cell.free()


## Test: get_cell_color_for_type returns correct colors
func test_get_cell_color_for_type():
	var cell = Cell.new(Vector2i(0, 0), Vector2(0, 0), 64.0)

	var empty_color = cell.get_cell_color_for_type(0)
	var wall_color = cell.get_cell_color_for_type(1)
	var water_color = cell.get_cell_color_for_type(2)
	var goal_color = cell.get_cell_color_for_type(3)

	assert_eq(empty_color, Color(0.8, 0.8, 0.8), "Empty should be light gray")
	assert_eq(wall_color, Color(0.2, 0.2, 0.2), "Wall should be dark gray")
	assert_eq(water_color, Color(0.2, 0.4, 1.0), "Water should be blue")
	assert_eq(goal_color, Color(0.2, 1.0, 0.2), "Goal should be green")

	cell.free()
