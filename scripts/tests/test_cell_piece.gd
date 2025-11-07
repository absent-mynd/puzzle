extends GutTest

## Tests for CellPiece class
## Verifies piece creation, geometry, seam tracking, and serialization

const CellPiece = preload("res://scripts/core/CellPiece.gd")
const Seam = preload("res://scripts/core/Seam.gd")


func test_cell_piece_creation_with_defaults():
	var piece = CellPiece.new()
	assert_eq(piece.geometry.size(), 0, "Default geometry should be empty")
	assert_eq(piece.cell_type, 0, "Default cell_type should be 0 (empty)")
	assert_eq(piece.source_fold_id, -1, "Default source_fold_id should be -1")
	assert_eq(piece.seams.size(), 0, "Default seams should be empty")


func test_cell_piece_creation_with_parameters():
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64),
		Vector2(0, 64)
	])
	var cell_type = 1  # Wall
	var source_fold_id = 42

	var piece = CellPiece.new(geometry, cell_type, source_fold_id)

	assert_eq(piece.geometry.size(), 4, "Should have 4 vertices")
	assert_eq(piece.cell_type, cell_type, "cell_type should match parameter")
	assert_eq(piece.source_fold_id, source_fold_id, "source_fold_id should match parameter")


func test_get_center_square():
	# Create a square from (0,0) to (64,64)
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64),
		Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	var center = piece.get_center()
	assert_almost_eq(center.x, 32, 0.1, "Center x should be 32")
	assert_almost_eq(center.y, 32, 0.1, "Center y should be 32")


func test_get_center_triangle():
	# Create a triangle
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(60, 0),
		Vector2(30, 60)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	var center = piece.get_center()
	assert_almost_eq(center.x, 30, 0.1, "Center x should be around 30")
	assert_almost_eq(center.y, 20, 0.1, "Center y should be around 20")


func test_get_center_empty_geometry():
	var piece = CellPiece.new()
	var center = piece.get_center()
	assert_eq(center, Vector2.ZERO, "Empty geometry should return ZERO")


func test_get_area_square():
	# 64x64 square
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64),
		Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	var area = piece.get_area()
	assert_almost_eq(area, 4096, 0.1, "64x64 square should have area 4096")


func test_get_area_triangle():
	# Right triangle with base 60, height 60
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(60, 0),
		Vector2(0, 60)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	var area = piece.get_area()
	assert_almost_eq(area, 1800, 0.1, "Triangle area should be 0.5 * 60 * 60 = 1800")


func test_get_area_empty_geometry():
	var piece = CellPiece.new()
	var area = piece.get_area()
	assert_eq(area, 0.0, "Empty geometry should have area 0")


func test_add_seam():
	var piece = CellPiece.new()
	var seam = Seam.new(Vector2(50, 0), Vector2(0, 1), PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), 1, 0, "horizontal")

	piece.add_seam(seam)
	assert_eq(piece.seams.size(), 1, "Should have 1 seam")
	assert_eq(piece.seams[0], seam, "Seam should match added seam")


func test_remove_seam():
	var piece = CellPiece.new()
	var seam1 = Seam.new(Vector2(50, 0), Vector2(0, 1), PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), 1, 0, "horizontal")
	var seam2 = Seam.new(Vector2(0, 50), Vector2(1, 0), PackedVector2Array([Vector2(0, 0), Vector2(0, 100)]), 2, 1, "vertical")

	piece.add_seam(seam1)
	piece.add_seam(seam2)
	assert_eq(piece.seams.size(), 2, "Should have 2 seams")

	piece.remove_seam(seam1)
	assert_eq(piece.seams.size(), 1, "Should have 1 seam after removal")
	assert_eq(piece.seams[0], seam2, "Remaining seam should be seam2")


func test_get_seams():
	var piece = CellPiece.new()
	var seam = Seam.new()
	piece.add_seam(seam)

	var seams = piece.get_seams()
	assert_eq(seams.size(), 1, "Should return 1 seam")
	assert_eq(seams[0], seam, "Returned seam should match")


func test_contains_point_inside():
	# Square from (0,0) to (64,64)
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64),
		Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	assert_true(piece.contains_point(Vector2(32, 32)), "Point at center should be inside")
	assert_true(piece.contains_point(Vector2(10, 10)), "Point near corner should be inside")


func test_contains_point_outside():
	# Square from (0,0) to (64,64)
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64),
		Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	assert_false(piece.contains_point(Vector2(100, 100)), "Point far away should be outside")
	assert_false(piece.contains_point(Vector2(-10, 32)), "Point to the left should be outside")


func test_contains_point_on_edge():
	# Square from (0,0) to (64,64)
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64),
		Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	# Points on edges should be considered inside
	assert_true(piece.contains_point(Vector2(32, 0)), "Point on bottom edge should be inside")
	assert_true(piece.contains_point(Vector2(64, 32)), "Point on right edge should be inside")


func test_duplicate_piece():
	var geometry = PackedVector2Array([Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)])
	var original = CellPiece.new(geometry, 2, 99)  # Water, fold 99
	original.metadata = {"test": "value"}

	var seam = Seam.new(Vector2(32, 0), Vector2(0, 1), PackedVector2Array([Vector2(0, 0), Vector2(64, 0)]), 1, 0, "horizontal")
	original.add_seam(seam)

	var duplicate = original.duplicate_piece()

	assert_ne(duplicate, original, "Duplicate should be a different object")
	assert_eq(duplicate.geometry.size(), 3, "Geometry should have same size")
	assert_eq(duplicate.cell_type, 2, "cell_type should match")
	assert_eq(duplicate.source_fold_id, 99, "source_fold_id should match")
	assert_eq(duplicate.seams.size(), 1, "Should have same number of seams")
	assert_has(duplicate.metadata, "test", "Metadata should be copied")


func test_to_dict_serialization():
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64)
	])
	var piece = CellPiece.new(geometry, 3, 42)  # Goal, fold 42
	piece.metadata = {"custom": "data"}

	var seam = Seam.new(Vector2(32, 0), Vector2(0, 1), PackedVector2Array([Vector2(0, 0), Vector2(64, 0)]), 1, 0, "horizontal")
	piece.add_seam(seam)

	var dict = piece.to_dict()

	assert_has(dict, "geometry", "Dict should have geometry")
	assert_has(dict, "cell_type", "Dict should have cell_type")
	assert_has(dict, "source_fold_id", "Dict should have source_fold_id")
	assert_has(dict, "seams", "Dict should have seams")
	assert_has(dict, "metadata", "Dict should have metadata")

	assert_eq(dict["geometry"].size(), 3, "Geometry should have 3 vertices")
	assert_eq(dict["cell_type"], 3, "cell_type should be 3")
	assert_eq(dict["source_fold_id"], 42, "source_fold_id should be 42")
	assert_eq(dict["seams"].size(), 1, "Should have 1 seam")


func test_from_dict_deserialization():
	var dict = {
		"geometry": [
			{"x": 0, "y": 0},
			{"x": 100, "y": 0},
			{"x": 100, "y": 100},
			{"x": 0, "y": 100}
		],
		"cell_type": 1,
		"source_fold_id": 77,
		"seams": [
			{
				"line_point": {"x": 50, "y": 0},
				"line_normal": {"x": 0, "y": 1},
				"intersection_points": [{"x": 0, "y": 0}, {"x": 100, "y": 0}],
				"fold_id": 1,
				"timestamp": 0,
				"fold_type": "horizontal",
				"metadata": {}
			}
		],
		"metadata": {"test": "value"}
	}

	var piece = CellPiece.from_dict(dict)

	assert_eq(piece.geometry.size(), 4, "Should have 4 vertices")
	assert_eq(piece.geometry[0], Vector2(0, 0), "First vertex should match")
	assert_eq(piece.geometry[3], Vector2(0, 100), "Last vertex should match")
	assert_eq(piece.cell_type, 1, "cell_type should be 1")
	assert_eq(piece.source_fold_id, 77, "source_fold_id should be 77")
	assert_eq(piece.seams.size(), 1, "Should have 1 seam")
	assert_has(piece.metadata, "test", "Metadata should be restored")


func test_round_trip_serialization():
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(50, 0),
		Vector2(50, 50),
		Vector2(0, 50)
	])
	var original = CellPiece.new(geometry, 2, 99)
	original.metadata = {"round_trip": "test"}

	var dict = original.to_dict()
	var restored = CellPiece.from_dict(dict)

	assert_eq(restored.geometry.size(), original.geometry.size(), "Geometry size should survive round trip")
	assert_eq(restored.cell_type, original.cell_type, "cell_type should survive round trip")
	assert_eq(restored.source_fold_id, original.source_fold_id, "source_fold_id should survive round trip")
	assert_eq(restored.metadata["round_trip"], "test", "Metadata should survive round trip")


func test_is_valid_valid_polygon():
	var geometry = PackedVector2Array([
		Vector2(0, 0),
		Vector2(64, 0),
		Vector2(64, 64),
		Vector2(0, 64)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	assert_true(piece.is_valid(), "Valid square should be valid")


func test_is_valid_invalid_too_few_vertices():
	var geometry = PackedVector2Array([Vector2(0, 0), Vector2(64, 0)])
	var piece = CellPiece.new(geometry, 0, -1)

	assert_false(piece.is_valid(), "Polygon with < 3 vertices should be invalid")


func test_is_valid_empty_geometry():
	var piece = CellPiece.new()
	assert_false(piece.is_valid(), "Empty geometry should be invalid")


func test_get_bounding_box():
	var geometry = PackedVector2Array([
		Vector2(10, 20),
		Vector2(100, 20),
		Vector2(100, 80),
		Vector2(10, 80)
	])
	var piece = CellPiece.new(geometry, 0, -1)

	var bbox = piece.get_bounding_box()
	assert_almost_eq(bbox.position.x, 10, 0.1, "Bounding box x should be 10")
	assert_almost_eq(bbox.position.y, 20, 0.1, "Bounding box y should be 20")
	assert_almost_eq(bbox.size.x, 90, 0.1, "Bounding box width should be 90")
	assert_almost_eq(bbox.size.y, 60, 0.1, "Bounding box height should be 60")


func test_get_bounding_box_empty():
	var piece = CellPiece.new()
	var bbox = piece.get_bounding_box()
	assert_eq(bbox, Rect2(), "Empty geometry should return empty Rect2")


func test_metadata_preservation():
	var piece = CellPiece.new()
	piece.metadata["int_value"] = 42
	piece.metadata["string_value"] = "test"
	piece.metadata["bool_value"] = true
	piece.metadata["array_value"] = [1, 2, 3]

	var duplicate = piece.duplicate_piece()
	assert_eq(duplicate.metadata["int_value"], 42, "Int metadata should be preserved")
	assert_eq(duplicate.metadata["string_value"], "test", "String metadata should be preserved")
	assert_eq(duplicate.metadata["bool_value"], true, "Bool metadata should be preserved")
	assert_eq(duplicate.metadata["array_value"], [1, 2, 3], "Array metadata should be preserved")
