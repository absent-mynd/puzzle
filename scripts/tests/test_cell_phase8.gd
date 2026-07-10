extends GutTest
## PHASE 8 unit tests for Cell: multi-piece hit-testing, visible center, null helpers.

const SIZE := 64.0


func _square(origin: Vector2, s: float) -> PackedVector2Array:
	return PackedVector2Array([
		origin,
		origin + Vector2(s, 0),
		origin + Vector2(s, s),
		origin + Vector2(0, s),
	])


func _make_cell() -> Cell:
	# Single empty-square piece at local (0,0)-(64,64)
	return Cell.new(Vector2i(0, 0), Vector2.ZERO, SIZE)


# ===== contains_point across all pieces =====

func test_contains_point_detects_merged_piece():
	var cell = _make_cell()
	# Add a real (walkable) piece offset far from the first piece
	cell.add_piece(CellPiece.new(_square(Vector2(200, 0), SIZE), CellPiece.CELL_TYPE_EMPTY, 1))

	# Point inside the SECOND piece only (first piece getter would miss it)
	assert_true(cell.contains_point(Vector2(230, 30)),
		"contains_point should detect a point inside a merged-in piece")
	# Sanity: point inside first piece still detected
	assert_true(cell.contains_point(Vector2(30, 30)), "First piece still hit-tests")


func test_contains_point_ignores_null_pieces():
	var cell = _make_cell()
	cell.add_piece(CellPiece.new(_square(Vector2(200, 0), SIZE), CellPiece.CELL_TYPE_NULL, 1))

	assert_false(cell.contains_point(Vector2(230, 30)),
		"A point only inside a null piece should not register as contained")


# ===== get_visible_center excludes null =====

func test_get_visible_center_excludes_null():
	var cell = _make_cell()  # real piece center (32,32)
	# Large null piece far away; its area would dominate a naive centroid
	cell.add_piece(CellPiece.new(_square(Vector2(1000, 1000), SIZE), CellPiece.CELL_TYPE_NULL, 1))

	var visible = cell.get_visible_center()
	assert_almost_eq(visible.x, 32.0, 0.5, "Visible center X ignores the null piece")
	assert_almost_eq(visible.y, 32.0, 0.5, "Visible center Y ignores the null piece")

	# The all-pieces center is pulled far toward the null region
	var all = cell.get_center()
	assert_gt(all.distance_to(visible), 100.0,
		"All-pieces center should differ substantially from visible center")


# ===== has_null_piece / is_centroid_in_null =====

func test_has_null_piece():
	var cell = _make_cell()
	assert_false(cell.has_null_piece(), "Fresh cell has no null piece")
	cell.add_piece(CellPiece.new(_square(Vector2(200, 0), SIZE), CellPiece.CELL_TYPE_NULL, 1))
	assert_true(cell.has_null_piece(), "Cell should report the added null piece")


func test_is_centroid_in_null_false_for_plain_cell():
	var cell = _make_cell()
	assert_false(cell.is_centroid_in_null(), "Plain empty cell centroid is not in null")


func test_is_centroid_in_null_true_when_null_dominates():
	# Tiny real piece + large null piece => weighted centroid lands inside the null piece
	var cell = Cell.new(Vector2i(0, 0), Vector2.ZERO, SIZE)
	cell.geometry_pieces.clear()
	cell.add_piece(CellPiece.new(_square(Vector2(0, 0), 4.0), CellPiece.CELL_TYPE_EMPTY, -1))
	cell.add_piece(CellPiece.new(_square(Vector2(50, 50), SIZE), CellPiece.CELL_TYPE_NULL, 1))

	assert_true(cell.is_centroid_in_null(),
		"Centroid dominated by the large null piece should be inside null")
