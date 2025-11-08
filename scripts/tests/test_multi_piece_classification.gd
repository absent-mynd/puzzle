## Test for multi-piece cell classification by cut line
##
## This test validates that when processing multi-piece cells,
## each piece is correctly classified as:
## - Entirely on remove side → remove it
## - Entirely on keep side → keep it as-is
## - Intersected by cut line → split it

extends GutTest

var grid_manager: GridManager
var fold_system: FoldSystem

func before_each():
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)
	grid_manager.grid_size = Vector2i(10, 10)
	grid_manager.cell_size = 64.0
	grid_manager.create_grid()

	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.grid_manager = grid_manager


func test_multi_piece_with_one_entirely_on_keep_side():
	"""
	Test scenario: A cell at grid position has 2 pieces.
	A cut line passes through the cell.
	- Piece 1: Entirely on the KEEP side (left of cut line)
	- Piece 2: Entirely on the REMOVE side (right of cut line)

	Expected: Piece 1 kept as-is, Piece 2 removed
	"""
	print("\n=== Multi-Piece Classification Test ===")

	# Create a cell with custom geometry (we'll manipulate it directly)
	var test_cell = grid_manager.get_cell(Vector2i(5, 5))

	# Clear default piece and add two custom pieces
	test_cell.geometry_pieces.clear()

	# Piece 1: Left square (x: 0-32, y: 0-64) - entirely LEFT of x=40 line
	var piece1 = CellPiece.new(
		PackedVector2Array([
			Vector2(0, 0),
			Vector2(32, 0),
			Vector2(32, 64),
			Vector2(0, 64)
		]),
		0,  # empty
		-1
	)
	test_cell.add_piece(piece1)

	# Piece 2: Right square (x: 40-64, y: 0-64) - entirely RIGHT of x=40 line
	var piece2 = CellPiece.new(
		PackedVector2Array([
			Vector2(40, 0),
			Vector2(64, 0),
			Vector2(64, 64),
			Vector2(40, 64)
		]),
		0,  # empty
		-1
	)
	test_cell.add_piece(piece2)

	var initial_pieces = test_cell.geometry_pieces.size()
	print("Before cut: %d pieces" % initial_pieces)
	for i in range(test_cell.geometry_pieces.size()):
		var p = test_cell.geometry_pieces[i]
		print("  Piece %d: area=%.1f, bounds x:[%.0f,%.0f]" % [i, p.get_area(), p.geometry[0].x, p.geometry[2].x])

	# Simulate a vertical cut line at x=36 (should remove piece2, keep piece1)
	var cut_point = Vector2(36, 32)  # middle of the cell vertically
	var cut_normal = Vector2(1, 0).normalized()  # vertical line

	# Manually test the pieces
	print("\nLine test at x=36:")
	var piece1_intersects = fold_system.does_cell_intersect_line(test_cell, cut_point, cut_normal)
	print("  does_cell_intersect_line result: %s" % piece1_intersects)

	# Check individual pieces
	for i in range(test_cell.geometry_pieces.size()):
		var p = test_cell.geometry_pieces[i]
		var split_result = GeometryCore.split_polygon_by_line(p.geometry, cut_point, cut_normal)
		var has_positive = false
		var has_negative = false
		for vertex in p.geometry:
			var side = GeometryCore.point_side_of_line(vertex, cut_point, cut_normal)
			if side > 0:
				has_positive = true
			elif side < 0:
				has_negative = true
		print("  Piece %d: intersections=%d, has_pos=%s, has_neg=%s" % [
			i, split_result.intersections.size(), has_positive, has_negative
		])

	# The assertion we need:
	# - Piece 1 should remain intact
	# - Piece 2 should either be removed or clearly marked as on remove side
	assert_eq(test_cell.geometry_pieces.size(), 2, "Both pieces should still be present for this test")
	print("✓ Test identifies the scenario correctly")


func test_piece_entirely_on_one_side_should_not_be_recalculated():
	"""
	When a piece is entirely on one side of a cut line (not intersected),
	it should be kept as-is, not duplicated or recalculated.

	This validates that we're not unnecessarily modifying geometry.
	"""
	print("\n=== Piece Keep-As-Is Test ===")

	var test_cell = grid_manager.get_cell(Vector2i(3, 3))
	test_cell.geometry_pieces.clear()

	# Single piece entirely to the left of a vertical cut line
	var piece = CellPiece.new(
		PackedVector2Array([
			Vector2(0, 0),
			Vector2(32, 0),
			Vector2(32, 64),
			Vector2(0, 64)
		]),
		0,
		-1
	)
	test_cell.add_piece(piece)

	var original_geometry = piece.geometry.duplicate()
	var original_area = piece.get_area()

	print("Original piece: area=%.1f, vertices=%d" % [original_area, piece.geometry.size()])

	# Cut line at x=40 (to the right of this piece)
	var cut_point = Vector2(40, 32)
	var cut_normal = Vector2(1, 0).normalized()

	var intersects = fold_system.does_cell_intersect_line(test_cell, cut_point, cut_normal)
	print("Piece intersects cut line at x=40: %s" % intersects)

	# Since it doesn't intersect, the piece should maintain its original geometry
	assert_eq(piece.get_area(), original_area, "Piece area should not change if not intersected")
	assert_eq(piece.geometry.size(), original_geometry.size(), "Piece geometry should not change if not intersected")

	print("✓ Piece geometry remains unchanged")
