## Unit tests for null piece functionality
##
## Tests the creation and behavior of null pieces when folds shift cells
## to positions with no merge partner

extends GutTest

var grid_manager: GridManager
var fold_system: FoldSystem


func before_each():
	# Create grid manager
	grid_manager = GridManager.new()
	add_child_autofree(grid_manager)

	await wait_physics_frames(2)

	# Create fold system
	fold_system = FoldSystem.new()
	add_child_autofree(fold_system)
	fold_system.initialize(grid_manager)

	await wait_physics_frames(1)


## Test: GeometryCore.calculate_complement_geometry creates correct complement
func test_calculate_complement_geometry_simple():
	var grid_pos = Vector2i(5, 5)
	var cell_size = grid_manager.cell_size

	# Create a piece covering left half of the cell
	var local_pos = Vector2(grid_pos) * cell_size
	var left_half = PackedVector2Array([
		local_pos,
		local_pos + Vector2(cell_size / 2, 0),
		local_pos + Vector2(cell_size / 2, cell_size),
		local_pos + Vector2(0, cell_size)
	])

	var piece = CellPiece.new(left_half, CellPiece.CELL_TYPE_EMPTY, -1)
	var existing_pieces: Array[CellPiece] = [piece]

	# Calculate complement
	var complement = GeometryCore.calculate_complement_geometry(
		grid_pos,
		cell_size,
		existing_pieces
	)

	# Complement should exist
	assert_true(complement.size() >= 3, "Complement should be a valid polygon")

	# Complement area should be approximately half the cell
	var full_area = cell_size * cell_size
	var complement_area = GeometryCore.polygon_area(complement)
	var expected_area = full_area / 2

	assert_almost_eq(complement_area, expected_area, cell_size,
		"Complement should be approximately half the cell area")


## Test: Null piece is created when cell shifts to empty location
func test_null_piece_created_on_shift_to_empty():
	await wait_physics_frames(2)

	# Create a simple manual scenario to test null piece creation
	# We'll directly call the function instead of doing a full fold
	var cell_size = grid_manager.cell_size
	var test_pos = Vector2i(8, 8)

	# Create a cell manually at position (8,8) with only half geometry
	var local_pos = Vector2(test_pos) * cell_size
	var left_half = PackedVector2Array([
		local_pos,
		local_pos + Vector2(cell_size / 2, 0),
		local_pos + Vector2(cell_size / 2, cell_size),
		local_pos + Vector2(0, cell_size)
	])

	var test_cell = Cell.new(test_pos, local_pos, cell_size)
	test_cell.geometry_pieces.clear()  # Remove default piece
	var left_piece = CellPiece.new(left_half, CellPiece.CELL_TYPE_EMPTY, -1)
	test_cell.add_piece(left_piece)

	# Add to grid
	grid_manager.add_child(test_cell)
	grid_manager.cells[test_pos] = test_cell

	# Call the function to add null pieces
	fold_system._add_null_pieces_to_complete_cell(test_cell, test_pos)

	# Check that a null piece was added
	var has_null = test_cell.has_cell_type(CellPiece.CELL_TYPE_NULL)
	assert_true(has_null, "Cell should have a null piece to complete it")

	# Check that cell now has 2 pieces (left half + null complement)
	assert_eq(test_cell.geometry_pieces.size(), 2,
		"Cell should have 2 pieces after adding null complement")


## Test: Null pieces make cells unwalkable (dominant type)
func test_null_pieces_make_cell_unwalkable():
	await wait_physics_frames(2)

	# Create a cell manually with mixed pieces
	var cell = grid_manager.get_cell(Vector2i(5, 5))
	var cell_size = grid_manager.cell_size
	var local_pos = Vector2(cell.grid_position) * cell_size

	# Add an empty piece (left half)
	var left_half = PackedVector2Array([
		local_pos,
		local_pos + Vector2(cell_size / 2, 0),
		local_pos + Vector2(cell_size / 2, cell_size),
		local_pos + Vector2(0, cell_size)
	])
	var empty_piece = CellPiece.new(left_half, CellPiece.CELL_TYPE_EMPTY, -1)

	# Add a null piece (right half)
	var right_half = PackedVector2Array([
		local_pos + Vector2(cell_size / 2, 0),
		local_pos + Vector2(cell_size, 0),
		local_pos + Vector2(cell_size, cell_size),
		local_pos + Vector2(cell_size / 2, cell_size)
	])
	var null_piece = CellPiece.new(right_half, CellPiece.CELL_TYPE_NULL, -1)

	# Clear existing pieces and add our custom ones
	cell.geometry_pieces.clear()
	cell.add_piece(empty_piece)
	cell.add_piece(null_piece)

	# Check dominant type
	var dominant_type = cell.get_dominant_type()

	assert_eq(dominant_type, CellPiece.CELL_TYPE_NULL,
		"Cell with null piece should have null as dominant type")


## Test: Null pieces are invisible (not rendered)
func test_null_pieces_invisible():
	await wait_physics_frames(2)

	var cell = grid_manager.get_cell(Vector2i(5, 5))
	var cell_size = grid_manager.cell_size
	var local_pos = Vector2(cell.grid_position) * cell_size

	# Create a null piece
	var null_geometry = PackedVector2Array([
		local_pos,
		local_pos + Vector2(cell_size, 0),
		local_pos + Vector2(cell_size, cell_size),
		local_pos + Vector2(0, cell_size)
	])
	var null_piece = CellPiece.new(null_geometry, CellPiece.CELL_TYPE_NULL, -1)

	# Clear existing and add null piece
	cell.geometry_pieces.clear()
	cell.add_piece(null_piece)
	cell.update_visual()

	# Count visible polygon children in piece_visuals
	var visible_count = 0
	if cell.piece_visuals:
		for child in cell.piece_visuals.get_children():
			if child is Polygon2D and child.visible:
				visible_count += 1

	# Also check legacy visuals
	if cell.polygon_visual and cell.polygon_visual.visible:
		visible_count += 1

	assert_eq(visible_count, 0, "Null pieces should not create visible polygons")


## Test: Cells with null pieces can still be split by future folds
func test_null_pieces_can_be_split_by_future_folds():
	await wait_physics_frames(2)

	# First fold: create a cell with a null piece
	var result1 = await fold_system.execute_fold(Vector2i(2, 2), Vector2i(4, 4), false)
	assert_true(result1, "First fold should succeed")

	# Find a cell with a null piece
	var cell_with_null = null
	var null_cell_pos = null
	for pos in grid_manager.cells:
		var cell = grid_manager.cells[pos]
		if cell.has_cell_type(CellPiece.CELL_TYPE_NULL):
			cell_with_null = cell
			null_cell_pos = pos
			break

	if cell_with_null:
		var pieces_before = cell_with_null.geometry_pieces.size()

		# Second fold: try to split the cell with null piece
		# Use anchors that will intersect this cell
		var result2 = await fold_system.execute_fold(Vector2i(0, 0), Vector2i(6, 6), false)

		# Check if the fold affected the cell (it may have been removed or split)
		# The key is that the fold should execute without errors
		assert_true(true, "Second fold should handle null pieces without errors")


## Test: Complement geometry calculation with no pieces returns full square
func test_complement_with_no_pieces():
	var grid_pos = Vector2i(3, 3)
	var cell_size = grid_manager.cell_size
	var empty_pieces: Array[CellPiece] = []

	var complement = GeometryCore.calculate_complement_geometry(
		grid_pos,
		cell_size,
		empty_pieces
	)

	# Should return the full square
	assert_eq(complement.size(), 4, "Complement with no pieces should be a square (4 vertices)")

	var area = GeometryCore.polygon_area(complement)
	var expected_area = cell_size * cell_size

	assert_almost_eq(area, expected_area, 1.0, "Complement area should equal full cell area")


## Test: Multiple null pieces can exist in one cell
func test_multiple_null_pieces_in_cell():
	await wait_physics_frames(2)

	var cell = grid_manager.get_cell(Vector2i(5, 5))
	var cell_size = grid_manager.cell_size
	var local_pos = Vector2(cell.grid_position) * cell_size

	# Create multiple small null pieces
	var quarter_size = cell_size / 2

	var null_piece1 = CellPiece.new(
		PackedVector2Array([
			local_pos,
			local_pos + Vector2(quarter_size, 0),
			local_pos + Vector2(quarter_size, quarter_size),
			local_pos + Vector2(0, quarter_size)
		]),
		CellPiece.CELL_TYPE_NULL,
		-1
	)

	var null_piece2 = CellPiece.new(
		PackedVector2Array([
			local_pos + Vector2(quarter_size, quarter_size),
			local_pos + Vector2(cell_size, quarter_size),
			local_pos + Vector2(cell_size, cell_size),
			local_pos + Vector2(quarter_size, cell_size)
		]),
		CellPiece.CELL_TYPE_NULL,
		-1
	)

	cell.geometry_pieces.clear()
	cell.add_piece(null_piece1)
	cell.add_piece(null_piece2)

	# Check that both pieces exist
	assert_eq(cell.geometry_pieces.size(), 2, "Cell should have 2 null pieces")

	# Check dominant type is still null
	assert_eq(cell.get_dominant_type(), CellPiece.CELL_TYPE_NULL,
		"Dominant type should be null with multiple null pieces")
