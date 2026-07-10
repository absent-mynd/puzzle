extends GutTest

## Tests for CellPiece class (view-layer polygon piece)
## Verifies piece creation, geometry queries, duplication, and validation.

const CellPiece = preload("res://scripts/core/CellPiece.gd")


func test_cell_piece_creation_with_defaults():
	var piece = CellPiece.new()
	assert_eq(piece.geometry.size(), 0, "Default geometry should be empty")
	assert_eq(piece.cell_type, 0, "Default cell_type should be 0 (empty)")
	assert_eq(piece.source_fold_id, -1, "Default source_fold_id should be -1")


func test_cell_piece_creation_with_parameters():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 1, 42)
	assert_eq(piece.geometry.size(), 4, "Should have 4 vertices")
	assert_eq(piece.cell_type, 1, "cell_type should match parameter")
	assert_eq(piece.source_fold_id, 42, "source_fold_id should match parameter")


func test_get_center_square():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)
	var center = piece.get_center()
	assert_almost_eq(center.x, 32, 0.1, "Center x should be 32")
	assert_almost_eq(center.y, 32, 0.1, "Center y should be 32")


func test_get_center_triangle():
	var geometry = PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(30, 60)])
	var piece = CellPiece.new(geometry, 0, -1)
	var center = piece.get_center()
	assert_almost_eq(center.x, 30, 0.1, "Center x should be around 30")
	assert_almost_eq(center.y, 20, 0.1, "Center y should be around 20")


func test_get_center_empty_geometry():
	var piece = CellPiece.new()
	assert_eq(piece.get_center(), Vector2.ZERO, "Empty geometry should return ZERO")


func test_get_area_square():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)
	assert_almost_eq(piece.get_area(), 4096, 0.1, "64x64 square should have area 4096")


func test_get_area_triangle():
	var geometry = PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(0, 60)])
	var piece = CellPiece.new(geometry, 0, -1)
	assert_almost_eq(piece.get_area(), 1800, 0.1, "Triangle area should be 1800")


func test_get_area_empty_geometry():
	var piece = CellPiece.new()
	assert_eq(piece.get_area(), 0.0, "Empty geometry should have area 0")


func test_contains_point_inside():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)
	assert_true(piece.contains_point(Vector2(32, 32)), "Center should be inside")
	assert_true(piece.contains_point(Vector2(10, 10)), "Near corner should be inside")


func test_contains_point_outside():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)
	assert_false(piece.contains_point(Vector2(100, 100)), "Far away should be outside")
	assert_false(piece.contains_point(Vector2(-10, 32)), "Left should be outside")


func test_contains_point_on_edge():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)
	assert_true(piece.contains_point(Vector2(32, 0)), "Bottom edge should be inside")
	assert_true(piece.contains_point(Vector2(64, 32)), "Right edge should be inside")


func test_duplicate_piece():
	var geometry = PackedVector2Array([Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)])
	var original = CellPiece.new(geometry, 2, 99)  # Water, fold 99
	original.metadata = {"test": "value"}

	var duplicate = original.duplicate_piece()
	assert_ne(duplicate, original, "Duplicate should be a different object")
	assert_eq(duplicate.geometry.size(), 3, "Geometry should have same size")
	assert_eq(duplicate.cell_type, 2, "cell_type should match")
	assert_eq(duplicate.source_fold_id, 99, "source_fold_id should match")
	assert_has(duplicate.metadata, "test", "Metadata should be copied")


func test_is_valid_valid_polygon():
	var geometry = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)
	assert_true(piece.is_valid(), "Valid square should be valid")


func test_is_valid_invalid_too_few_vertices():
	var piece = CellPiece.new(PackedVector2Array([Vector2(0, 0), Vector2(64, 0)]), 0, -1)
	assert_false(piece.is_valid(), "Polygon with < 3 vertices should be invalid")


func test_is_valid_empty_geometry():
	assert_false(CellPiece.new().is_valid(), "Empty geometry should be invalid")


func test_get_bounding_box():
	var geometry = PackedVector2Array([
		Vector2(10, 20), Vector2(100, 20), Vector2(100, 80), Vector2(10, 80)
	])
	var bbox = CellPiece.new(geometry, 0, -1).get_bounding_box()
	assert_almost_eq(bbox.position.x, 10, 0.1, "Bounding box x should be 10")
	assert_almost_eq(bbox.position.y, 20, 0.1, "Bounding box y should be 20")
	assert_almost_eq(bbox.size.x, 90, 0.1, "Bounding box width should be 90")
	assert_almost_eq(bbox.size.y, 60, 0.1, "Bounding box height should be 60")


func test_get_bounding_box_empty():
	assert_eq(CellPiece.new().get_bounding_box(), Rect2(), "Empty geometry -> empty Rect2")


func test_metadata_preservation():
	var piece = CellPiece.new()
	piece.metadata["int_value"] = 42
	piece.metadata["array_value"] = [1, 2, 3]
	var duplicate = piece.duplicate_piece()
	assert_eq(duplicate.metadata["int_value"], 42, "Int metadata should be preserved")
	assert_eq(duplicate.metadata["array_value"], [1, 2, 3], "Array metadata should be preserved")
