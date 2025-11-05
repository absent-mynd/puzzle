## Unit Tests for GeometryCore
##
## This test suite validates all geometric functions needed for space-folding mechanics.
## Tests cover normal cases, edge cases, and validation of area conservation.
##
## To run these tests:
##   - Once GUT is set up (Issue #3), use the GUT test runner
##   - For manual testing, attach this to a test scene and call run_all_tests()

extends Node
class_name TestGeometryCore

## Test results storage
var tests_passed: int = 0
var tests_failed: int = 0
var test_details: Array = []


## Runs all test suites
func run_all_tests() -> void:
	print("\n=== GeometryCore Test Suite ===\n")

	test_point_side_of_line()
	test_segment_line_intersection()
	test_polygon_area()
	test_polygon_centroid()
	test_validate_polygon()
	test_split_polygon_by_line()
	test_area_conservation()
	test_helper_functions()

	print("\n=== Test Summary ===")
	print("Passed: %d" % tests_passed)
	print("Failed: %d" % tests_failed)
	print("Total: %d" % (tests_passed + tests_failed))

	if tests_failed == 0:
		print("\n✓ All tests passed!")
	else:
		print("\n✗ Some tests failed. See details above.")


## Test suite for point_side_of_line function
func test_point_side_of_line() -> void:
	print("--- Testing point_side_of_line ---")

	# Test 1: Point clearly on positive side (right of vertical line)
	var result = GeometryCore.point_side_of_line(
		Vector2(10, 0),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_equal(result, 1, "Point on positive side")

	# Test 2: Point clearly on negative side (left of vertical line)
	result = GeometryCore.point_side_of_line(
		Vector2(-10, 0),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_equal(result, -1, "Point on negative side")

	# Test 3: Point exactly on line
	result = GeometryCore.point_side_of_line(
		Vector2(0, 100),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_equal(result, 0, "Point exactly on line")

	# Test 4: Point within epsilon of line (should return 0)
	result = GeometryCore.point_side_of_line(
		Vector2(0.00005, 0),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_equal(result, 0, "Point within epsilon of line")

	# Test 5: Diagonal line test
	result = GeometryCore.point_side_of_line(
		Vector2(10, 0),
		Vector2(0, 0),
		Vector2(1, 1).normalized()
	)
	assert_equal(result, -1, "Point below diagonal line")

	print("")


## Test suite for segment_line_intersection function
func test_segment_line_intersection() -> void:
	print("--- Testing segment_line_intersection ---")

	# Test 1: Clear intersection
	var intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(10, 10),
		Vector2(5, 0),
		Vector2(0, 1)
	)
	assert_not_null(intersection, "Segment intersects horizontal line")
	if intersection != null:
		assert_approximately_equal(intersection.x, 5.0, "Intersection X coordinate")
		assert_approximately_equal(intersection.y, 5.0, "Intersection Y coordinate")

	# Test 2: Parallel segments (no intersection)
	intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(10, 0),
		Vector2(0, 5),
		Vector2(1, 0)
	)
	assert_null(intersection, "Parallel segments return null")

	# Test 3: Segment that doesn't reach the line
	intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(10, 0),
		Vector2(0, 1)
	)
	assert_null(intersection, "Segment doesn't reach line")

	# Test 4: Intersection at segment endpoint
	intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(10, 0),
		Vector2(10, -5),
		Vector2(0, 1)
	)
	assert_not_null(intersection, "Intersection at endpoint")
	if intersection != null:
		assert_approximately_equal(intersection.x, 10.0, "Endpoint intersection X")

	# Test 5: Diagonal segment crossing vertical line
	intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(20, 20),
		Vector2(10, 0),
		Vector2(1, 0)
	)
	assert_not_null(intersection, "Diagonal crosses vertical")
	if intersection != null:
		assert_approximately_equal(intersection.x, 10.0, "Diagonal intersection X")
		assert_approximately_equal(intersection.y, 10.0, "Diagonal intersection Y")

	print("")


## Test suite for polygon_area function
func test_polygon_area() -> void:
	print("--- Testing polygon_area ---")

	# Test 1: Simple square (100x100)
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var area = GeometryCore.polygon_area(square)
	assert_approximately_equal(area, 10000.0, "Square area (100x100)")

	# Test 2: Triangle
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	area = GeometryCore.polygon_area(triangle)
	assert_approximately_equal(area, 5000.0, "Triangle area")

	# Test 3: Reversed winding order (should still give positive area)
	var square_reversed = PackedVector2Array([
		Vector2(0, 100),
		Vector2(100, 100),
		Vector2(100, 0),
		Vector2(0, 0)
	])
	area = GeometryCore.polygon_area(square_reversed)
	assert_approximately_equal(area, 10000.0, "Square with reversed winding")

	# Test 4: Small rectangle
	var rect = PackedVector2Array([
		Vector2(0, 0),
		Vector2(50, 0),
		Vector2(50, 20),
		Vector2(0, 20)
	])
	area = GeometryCore.polygon_area(rect)
	assert_approximately_equal(area, 1000.0, "Rectangle area (50x20)")

	# Test 5: Degenerate polygon (too few vertices)
	var line = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0)
	])
	area = GeometryCore.polygon_area(line)
	assert_approximately_equal(area, 0.0, "Degenerate polygon (line)")

	print("")


## Test suite for polygon_centroid function
func test_polygon_centroid() -> void:
	print("--- Testing polygon_centroid ---")

	# Test 1: Square centered at origin
	var square = PackedVector2Array([
		Vector2(-50, -50),
		Vector2(50, -50),
		Vector2(50, 50),
		Vector2(-50, 50)
	])
	var centroid = GeometryCore.polygon_centroid(square)
	assert_approximately_equal(centroid.x, 0.0, "Square centroid X")
	assert_approximately_equal(centroid.y, 0.0, "Square centroid Y")

	# Test 2: Square offset from origin
	var offset_square = PackedVector2Array([
		Vector2(100, 100),
		Vector2(200, 100),
		Vector2(200, 200),
		Vector2(100, 200)
	])
	centroid = GeometryCore.polygon_centroid(offset_square)
	assert_approximately_equal(centroid.x, 150.0, "Offset square centroid X")
	assert_approximately_equal(centroid.y, 150.0, "Offset square centroid Y")

	# Test 3: Triangle
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(90, 0),
		Vector2(0, 90)
	])
	centroid = GeometryCore.polygon_centroid(triangle)
	assert_approximately_equal(centroid.x, 30.0, "Triangle centroid X", 1.0)
	assert_approximately_equal(centroid.y, 30.0, "Triangle centroid Y", 1.0)

	# Test 4: Single point
	var point = PackedVector2Array([Vector2(10, 20)])
	centroid = GeometryCore.polygon_centroid(point)
	assert_approximately_equal(centroid.x, 10.0, "Single point X")
	assert_approximately_equal(centroid.y, 20.0, "Single point Y")

	# Test 5: Two points
	var two_points = PackedVector2Array([Vector2(0, 0), Vector2(100, 100)])
	centroid = GeometryCore.polygon_centroid(two_points)
	assert_approximately_equal(centroid.x, 50.0, "Two points midpoint X")
	assert_approximately_equal(centroid.y, 50.0, "Two points midpoint Y")

	print("")


## Test suite for validate_polygon function
func test_validate_polygon() -> void:
	print("--- Testing validate_polygon ---")

	# Test 1: Valid square
	var valid_square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var is_valid = GeometryCore.validate_polygon(valid_square)
	assert_true(is_valid, "Valid square")

	# Test 2: Valid triangle
	var valid_triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	is_valid = GeometryCore.validate_polygon(valid_triangle)
	assert_true(is_valid, "Valid triangle")

	# Test 3: Too few vertices
	var too_few = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0)
	])
	is_valid = GeometryCore.validate_polygon(too_few)
	assert_false(is_valid, "Too few vertices (2)")

	# Test 4: Self-intersecting polygon (figure-8 shape)
	var self_intersecting = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 100),
		Vector2(100, 0),
		Vector2(0, 100)
	])
	is_valid = GeometryCore.validate_polygon(self_intersecting)
	assert_false(is_valid, "Self-intersecting polygon")

	# Test 5: Degenerate edge (duplicate vertices)
	var degenerate = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 0),  # Duplicate
		Vector2(0, 100)
	])
	is_valid = GeometryCore.validate_polygon(degenerate)
	assert_false(is_valid, "Degenerate edge (duplicate vertex)")

	print("")


## Test suite for split_polygon_by_line function
func test_split_polygon_by_line() -> void:
	print("--- Testing split_polygon_by_line ---")

	# Test 1: Vertical split of square
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(50, 0),
		Vector2(1, 0).normalized()
	)
	assert_true(result["left"].size() >= 3, "Vertical split: left polygon has vertices")
	assert_true(result["right"].size() >= 3, "Vertical split: right polygon has vertices")
	assert_equal(result["intersections"].size(), 2, "Vertical split: two intersections")

	# Test 2: Horizontal split of square
	result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(0, 50),
		Vector2(0, 1).normalized()
	)
	assert_true(result["left"].size() >= 3, "Horizontal split: left polygon has vertices")
	assert_true(result["right"].size() >= 3, "Horizontal split: right polygon has vertices")
	assert_equal(result["intersections"].size(), 2, "Horizontal split: two intersections")

	# Test 3: Diagonal split (45 degrees)
	result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(0, 0),
		Vector2(1, 1).normalized()
	)
	assert_true(result["left"].size() >= 3, "Diagonal split: left polygon has vertices")
	assert_true(result["right"].size() >= 3, "Diagonal split: right polygon has vertices")
	assert_equal(result["intersections"].size(), 2, "Diagonal split: two intersections")

	# Test 4: Cut through vertices
	result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(0, 0),
		Vector2(1, 0).normalized()
	)
	assert_true(result["left"].size() >= 3, "Through-vertex split: left polygon")
	assert_true(result["right"].size() >= 3, "Through-vertex split: right polygon")

	# Test 5: Line that misses polygon entirely
	result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(200, 0),
		Vector2(1, 0).normalized()
	)
	# All vertices should be on one side
	var total_verts = result["left"].size() + result["right"].size()
	assert_true(total_verts >= 4, "Miss: all vertices on one side")
	assert_equal(result["intersections"].size(), 0, "Miss: no intersections")

	# Test 6: Triangle split
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	result = GeometryCore.split_polygon_by_line(
		triangle,
		Vector2(50, 0),
		Vector2(1, 0).normalized()
	)
	assert_true(result["left"].size() >= 3, "Triangle split: left polygon")
	assert_true(result["right"].size() >= 3, "Triangle split: right polygon")

	print("")


## Test area conservation after splitting
func test_area_conservation() -> void:
	print("--- Testing Area Conservation ---")

	# Test 1: Square split vertically
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var original_area = GeometryCore.polygon_area(square)

	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(50, 0),
		Vector2(1, 0).normalized()
	)

	var left_area = GeometryCore.polygon_area(result["left"])
	var right_area = GeometryCore.polygon_area(result["right"])
	var total_area = left_area + right_area

	assert_approximately_equal(total_area, original_area, "Vertical split: area conservation", 1.0)

	# Test 2: Square split horizontally
	result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(0, 50),
		Vector2(0, 1).normalized()
	)

	left_area = GeometryCore.polygon_area(result["left"])
	right_area = GeometryCore.polygon_area(result["right"])
	total_area = left_area + right_area

	assert_approximately_equal(total_area, original_area, "Horizontal split: area conservation", 1.0)

	# Test 3: Square split diagonally
	result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(50, 50),
		Vector2(1, 1).normalized()
	)

	left_area = GeometryCore.polygon_area(result["left"])
	right_area = GeometryCore.polygon_area(result["right"])
	total_area = left_area + right_area

	assert_approximately_equal(total_area, original_area, "Diagonal split: area conservation", 1.0)

	# Test 4: Triangle split
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	original_area = GeometryCore.polygon_area(triangle)

	result = GeometryCore.split_polygon_by_line(
		triangle,
		Vector2(50, 0),
		Vector2(1, 0).normalized()
	)

	left_area = GeometryCore.polygon_area(result["left"])
	right_area = GeometryCore.polygon_area(result["right"])
	total_area = left_area + right_area

	assert_approximately_equal(total_area, original_area, "Triangle split: area conservation", 1.0)

	print("")


## Test helper functions (segments_intersect, create_rect_vertices, point_in_polygon)
func test_helper_functions() -> void:
	print("--- Testing Helper Functions ---")

	# Test 1: segments_intersect - intersecting segments
	var intersects = GeometryCore.segments_intersect(
		Vector2(0, 0), Vector2(10, 10),
		Vector2(0, 10), Vector2(10, 0)
	)
	assert_true(intersects, "Segments intersect (X pattern)")

	# Test 2: segments_intersect - non-intersecting segments
	intersects = GeometryCore.segments_intersect(
		Vector2(0, 0), Vector2(10, 0),
		Vector2(0, 10), Vector2(10, 10)
	)
	assert_false(intersects, "Segments don't intersect (parallel)")

	# Test 3: create_rect_vertices
	var rect_verts = GeometryCore.create_rect_vertices(
		Vector2(50, 50),
		Vector2(100, 100)
	)
	assert_equal(rect_verts.size(), 4, "Rectangle has 4 vertices")
	var rect_area = GeometryCore.polygon_area(rect_verts)
	assert_approximately_equal(rect_area, 10000.0, "Rectangle area correct")

	# Test 4: point_in_polygon - point inside
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var inside = GeometryCore.point_in_polygon(Vector2(50, 50), square)
	assert_true(inside, "Point inside square")

	# Test 5: point_in_polygon - point outside
	inside = GeometryCore.point_in_polygon(Vector2(150, 150), square)
	assert_false(inside, "Point outside square")

	# Test 6: point_in_polygon - point on edge (may vary)
	inside = GeometryCore.point_in_polygon(Vector2(0, 50), square)
	# Point on edge behavior can vary, we just check it doesn't crash
	assert_not_null(inside, "Point on edge doesn't crash")

	print("")


# ===== Assertion Helper Functions =====

func assert_equal(actual, expected, test_name: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		print("  ✗ %s (expected: %s, got: %s)" % [test_name, expected, actual])


func assert_approximately_equal(actual: float, expected: float, test_name: String, tolerance: float = 0.1) -> void:
	if abs(actual - expected) <= tolerance:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		print("  ✗ %s (expected: %.4f, got: %.4f, diff: %.4f)" % [test_name, expected, actual, abs(actual - expected)])


func assert_true(condition: bool, test_name: String) -> void:
	if condition:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		print("  ✗ %s (expected true, got false)" % test_name)


func assert_false(condition: bool, test_name: String) -> void:
	if not condition:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		print("  ✗ %s (expected false, got true)" % test_name)


func assert_null(value, test_name: String) -> void:
	if value == null:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		print("  ✗ %s (expected null, got non-null)" % test_name)


func assert_not_null(value, test_name: String) -> void:
	if value != null:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		print("  ✗ %s (expected non-null, got null)" % test_name)
