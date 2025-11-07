extends GutTest

## Tests for Seam class
## Verifies seam creation, intersection, serialization, and utilities

const Seam = preload("res://scripts/core/Seam.gd")


func test_seam_creation_with_defaults():
	var seam = Seam.new()
	assert_eq(seam.line_point, Vector2.ZERO, "Default line_point should be ZERO")
	assert_eq(seam.line_normal, Vector2.ZERO, "Default line_normal should be ZERO")
	assert_eq(seam.intersection_points.size(), 0, "Default intersection_points should be empty")
	assert_eq(seam.fold_id, -1, "Default fold_id should be -1")
	assert_eq(seam.timestamp, 0, "Default timestamp should be 0")
	assert_eq(seam.fold_type, "", "Default fold_type should be empty")


func test_seam_creation_with_parameters():
	var line_point = Vector2(100, 50)
	var line_normal = Vector2(1, 0).normalized()
	var intersection_points = PackedVector2Array([Vector2(100, 0), Vector2(100, 100)])
	var fold_id = 42
	var timestamp = 12345
	var fold_type = "vertical"

	var seam = Seam.new(line_point, line_normal, intersection_points, fold_id, timestamp, fold_type)

	assert_eq(seam.line_point, line_point, "line_point should match parameter")
	assert_eq(seam.line_normal, line_normal, "line_normal should match parameter")
	assert_eq(seam.intersection_points.size(), 2, "Should have 2 intersection points")
	assert_eq(seam.intersection_points[0], Vector2(100, 0), "First intersection point should match")
	assert_eq(seam.intersection_points[1], Vector2(100, 100), "Second intersection point should match")
	assert_eq(seam.fold_id, fold_id, "fold_id should match parameter")
	assert_eq(seam.timestamp, timestamp, "timestamp should match parameter")
	assert_eq(seam.fold_type, fold_type, "fold_type should match parameter")


func test_get_seam_endpoints():
	var intersection_points = PackedVector2Array([Vector2(100, 0), Vector2(100, 200)])
	var seam = Seam.new(Vector2(100, 100), Vector2(1, 0), intersection_points, 1, 0, "vertical")

	var endpoints = seam.get_seam_endpoints()
	assert_eq(endpoints.size(), 2, "Should return 2 endpoints")
	assert_eq(endpoints[0], Vector2(100, 0), "First endpoint should match")
	assert_eq(endpoints[1], Vector2(100, 200), "Second endpoint should match")


func test_get_seam_endpoints_invalid():
	# Seam with only 1 intersection point (invalid)
	var intersection_points = PackedVector2Array([Vector2(100, 0)])
	var seam = Seam.new(Vector2(100, 100), Vector2(1, 0), intersection_points, 1, 0, "vertical")

	var endpoints = seam.get_seam_endpoints()
	assert_eq(endpoints.size(), 0, "Should return empty array for invalid seam")


func test_get_line_segment():
	var intersection_points = PackedVector2Array([Vector2(50, 0), Vector2(50, 100)])
	var seam = Seam.new(Vector2(50, 50), Vector2(1, 0), intersection_points, 1, 0, "vertical")

	var segment = seam.get_line_segment()
	assert_has(segment, "start", "Segment should have 'start' key")
	assert_has(segment, "end", "Segment should have 'end' key")
	assert_eq(segment["start"], Vector2(50, 0), "Start should match first intersection")
	assert_eq(segment["end"], Vector2(50, 100), "End should match second intersection")


func test_get_line_segment_invalid():
	var seam = Seam.new()  # No intersection points

	var segment = seam.get_line_segment()
	assert_eq(segment["start"], Vector2.ZERO, "Invalid seam should return ZERO start")
	assert_eq(segment["end"], Vector2.ZERO, "Invalid seam should return ZERO end")


func test_is_parallel_to_vertical_seams():
	# Two vertical seams (normal pointing right)
	var seam1 = Seam.new(Vector2(100, 50), Vector2(1, 0), PackedVector2Array([Vector2(100, 0), Vector2(100, 100)]), 1, 0, "vertical")
	var seam2 = Seam.new(Vector2(200, 50), Vector2(1, 0), PackedVector2Array([Vector2(200, 0), Vector2(200, 100)]), 2, 1, "vertical")

	assert_true(seam1.is_parallel_to(seam2), "Vertical seams with same normal should be parallel")


func test_is_parallel_to_horizontal_seams():
	# Two horizontal seams (normal pointing up)
	var seam1 = Seam.new(Vector2(50, 100), Vector2(0, 1), PackedVector2Array([Vector2(0, 100), Vector2(100, 100)]), 1, 0, "horizontal")
	var seam2 = Seam.new(Vector2(50, 200), Vector2(0, 1), PackedVector2Array([Vector2(0, 200), Vector2(100, 200)]), 2, 1, "horizontal")

	assert_true(seam1.is_parallel_to(seam2), "Horizontal seams with same normal should be parallel")


func test_is_parallel_to_opposite_normals():
	# Two vertical seams with opposite normals (still parallel)
	var seam1 = Seam.new(Vector2(100, 50), Vector2(1, 0), PackedVector2Array([Vector2(100, 0), Vector2(100, 100)]), 1, 0, "vertical")
	var seam2 = Seam.new(Vector2(200, 50), Vector2(-1, 0), PackedVector2Array([Vector2(200, 0), Vector2(200, 100)]), 2, 1, "vertical")

	assert_true(seam1.is_parallel_to(seam2), "Seams with opposite normals should still be parallel")


func test_is_parallel_to_perpendicular_seams():
	# Vertical and horizontal seams (perpendicular, not parallel)
	var seam1 = Seam.new(Vector2(100, 50), Vector2(1, 0), PackedVector2Array([Vector2(100, 0), Vector2(100, 100)]), 1, 0, "vertical")
	var seam2 = Seam.new(Vector2(50, 100), Vector2(0, 1), PackedVector2Array([Vector2(0, 100), Vector2(100, 100)]), 2, 1, "horizontal")

	assert_false(seam1.is_parallel_to(seam2), "Perpendicular seams should not be parallel")


func test_is_parallel_to_diagonal_seams():
	# Two diagonal seams at 45 degrees
	var normal1 = Vector2(1, 1).normalized()
	var normal2 = Vector2(1, 1).normalized()
	var seam1 = Seam.new(Vector2(50, 50), normal1, PackedVector2Array([Vector2(0, 100), Vector2(100, 0)]), 1, 0, "diagonal")
	var seam2 = Seam.new(Vector2(150, 150), normal2, PackedVector2Array([Vector2(100, 200), Vector2(200, 100)]), 2, 1, "diagonal")

	assert_true(seam1.is_parallel_to(seam2), "Diagonal seams with same angle should be parallel")


func test_intersects_with_perpendicular_seams():
	# Vertical seam at x=100, horizontal seam at y=100
	var seam1 = Seam.new(Vector2(100, 50), Vector2(1, 0), PackedVector2Array([Vector2(100, 0), Vector2(100, 200)]), 1, 0, "vertical")
	var seam2 = Seam.new(Vector2(50, 100), Vector2(0, 1), PackedVector2Array([Vector2(0, 100), Vector2(200, 100)]), 2, 1, "horizontal")

	var intersection = seam1.intersects_with(seam2)
	assert_ne(intersection, Vector2.INF, "Perpendicular seams should intersect")
	assert_almost_eq(intersection.x, 100, 0.1, "Intersection x should be at 100")
	assert_almost_eq(intersection.y, 100, 0.1, "Intersection y should be at 100")


func test_intersects_with_parallel_seams():
	# Two parallel vertical seams (should not intersect)
	var seam1 = Seam.new(Vector2(100, 50), Vector2(1, 0), PackedVector2Array([Vector2(100, 0), Vector2(100, 100)]), 1, 0, "vertical")
	var seam2 = Seam.new(Vector2(200, 50), Vector2(1, 0), PackedVector2Array([Vector2(200, 0), Vector2(200, 100)]), 2, 1, "vertical")

	var intersection = seam1.intersects_with(seam2)
	assert_eq(intersection, Vector2.INF, "Parallel seams should not intersect")


func test_duplicate_seam():
	var original = Seam.new(
		Vector2(100, 50),
		Vector2(1, 0),
		PackedVector2Array([Vector2(100, 0), Vector2(100, 100)]),
		42,
		12345,
		"vertical"
	)
	original.metadata = {"test_key": "test_value"}

	var duplicate = original.duplicate_seam()

	assert_ne(duplicate, original, "Duplicate should be a different object")
	assert_eq(duplicate.line_point, original.line_point, "line_point should match")
	assert_eq(duplicate.line_normal, original.line_normal, "line_normal should match")
	assert_eq(duplicate.intersection_points.size(), 2, "Should have same intersection points")
	assert_eq(duplicate.fold_id, original.fold_id, "fold_id should match")
	assert_eq(duplicate.timestamp, original.timestamp, "timestamp should match")
	assert_eq(duplicate.fold_type, original.fold_type, "fold_type should match")
	assert_has(duplicate.metadata, "test_key", "Metadata should be copied")
	assert_eq(duplicate.metadata["test_key"], "test_value", "Metadata values should match")


func test_to_dict_serialization():
	var seam = Seam.new(
		Vector2(100, 50),
		Vector2(1, 0),
		PackedVector2Array([Vector2(100, 0), Vector2(100, 200)]),
		42,
		12345,
		"vertical"
	)
	seam.metadata = {"custom": "data"}

	var dict = seam.to_dict()

	assert_has(dict, "line_point", "Dict should have line_point")
	assert_has(dict, "line_normal", "Dict should have line_normal")
	assert_has(dict, "intersection_points", "Dict should have intersection_points")
	assert_has(dict, "fold_id", "Dict should have fold_id")
	assert_has(dict, "timestamp", "Dict should have timestamp")
	assert_has(dict, "fold_type", "Dict should have fold_type")
	assert_has(dict, "metadata", "Dict should have metadata")

	assert_eq(dict["line_point"]["x"], 100, "line_point.x should match")
	assert_eq(dict["line_point"]["y"], 50, "line_point.y should match")
	assert_eq(dict["fold_id"], 42, "fold_id should match")
	assert_eq(dict["fold_type"], "vertical", "fold_type should match")


func test_from_dict_deserialization():
	var dict = {
		"line_point": {"x": 150, "y": 75},
		"line_normal": {"x": 0, "y": 1},
		"intersection_points": [
			{"x": 0, "y": 75},
			{"x": 300, "y": 75}
		],
		"fold_id": 99,
		"timestamp": 54321,
		"fold_type": "horizontal",
		"metadata": {"test": "value"}
	}

	var seam = Seam.from_dict(dict)

	assert_eq(seam.line_point, Vector2(150, 75), "line_point should match dict")
	assert_eq(seam.line_normal, Vector2(0, 1), "line_normal should match dict")
	assert_eq(seam.intersection_points.size(), 2, "Should have 2 intersection points")
	assert_eq(seam.intersection_points[0], Vector2(0, 75), "First intersection should match")
	assert_eq(seam.intersection_points[1], Vector2(300, 75), "Second intersection should match")
	assert_eq(seam.fold_id, 99, "fold_id should match dict")
	assert_eq(seam.timestamp, 54321, "timestamp should match dict")
	assert_eq(seam.fold_type, "horizontal", "fold_type should match dict")
	assert_has(seam.metadata, "test", "Metadata should be copied")


func test_round_trip_serialization():
	var original = Seam.new(
		Vector2(200, 100),
		Vector2(0.707, 0.707),
		PackedVector2Array([Vector2(100, 200), Vector2(300, 0)]),
		77,
		99999,
		"diagonal"
	)
	original.metadata = {"round_trip": "test"}

	var dict = original.to_dict()
	var restored = Seam.from_dict(dict)

	assert_almost_eq(restored.line_point.x, original.line_point.x, 0.01, "line_point.x should survive round trip")
	assert_almost_eq(restored.line_point.y, original.line_point.y, 0.01, "line_point.y should survive round trip")
	assert_eq(restored.fold_id, original.fold_id, "fold_id should survive round trip")
	assert_eq(restored.fold_type, original.fold_type, "fold_type should survive round trip")
	assert_eq(restored.metadata["round_trip"], "test", "Metadata should survive round trip")


func test_metadata_preservation():
	var seam = Seam.new()
	seam.metadata["custom_int"] = 42
	seam.metadata["custom_string"] = "test"
	seam.metadata["custom_bool"] = true

	var duplicate = seam.duplicate_seam()
	assert_eq(duplicate.metadata["custom_int"], 42, "Int metadata should be preserved")
	assert_eq(duplicate.metadata["custom_string"], "test", "String metadata should be preserved")
	assert_eq(duplicate.metadata["custom_bool"], true, "Bool metadata should be preserved")
