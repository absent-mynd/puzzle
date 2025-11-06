extends GutTest
## Unit Tests for GeometryCore
##
## This test suite validates all geometric functions needed for space-folding mechanics.
## Tests cover normal cases, edge cases, and validation of area conservation.


func before_all():
	gut.p("=== GeometryCore Test Suite ===")


func after_all():
	gut.p("=== GeometryCore Tests Complete ===")


# ===== point_side_of_line Tests =====

func test_point_on_positive_side():
	var result = GeometryCore.point_side_of_line(
		Vector2(10, 0),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_eq(result, 1, "Point on positive side")


func test_point_on_negative_side():
	var result = GeometryCore.point_side_of_line(
		Vector2(-10, 0),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_eq(result, -1, "Point on negative side")


func test_point_exactly_on_line():
	var result = GeometryCore.point_side_of_line(
		Vector2(0, 100),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_eq(result, 0, "Point exactly on line")


func test_point_within_epsilon_of_line():
	var result = GeometryCore.point_side_of_line(
		Vector2(0.00005, 0),
		Vector2(0, 0),
		Vector2(1, 0)
	)
	assert_eq(result, 0, "Point within epsilon of line")


func test_point_diagonal_line():
	var result = GeometryCore.point_side_of_line(
		Vector2(10, 0),
		Vector2(0, 0),
		Vector2(-1, 1).normalized()
	)
	assert_eq(result, -1, "Point below diagonal line")


# ===== segment_line_intersection Tests =====

func test_segment_clear_intersection():
	var intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(10, 10),
		Vector2(5, 0),
		Vector2(1, 0)
	)
	assert_not_null(intersection, "Segment intersects vertical line")
	if intersection != null:
		assert_almost_eq(intersection.x, 5.0, 0.001, "Intersection X coordinate")
		assert_almost_eq(intersection.y, 5.0, 0.001, "Intersection Y coordinate")


func test_segment_parallel_no_intersection():
	var intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(10, 0),
		Vector2(0, 5),
		Vector2(0, 1)
	)
	assert_null(intersection, "Parallel segments return null")


func test_segment_doesnt_reach_line():
	var intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(10, 0),
		Vector2(0, 1)
	)
	assert_null(intersection, "Segment doesn't reach line")


func test_segment_intersection_at_endpoint():
	var intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(10, 0),
		Vector2(10, -5),
		Vector2(1, 0)
	)
	assert_not_null(intersection, "Intersection at endpoint")
	if intersection != null:
		assert_almost_eq(intersection.x, 10.0, 0.001, "Endpoint intersection X")


func test_segment_diagonal_crossing_vertical():
	var intersection = GeometryCore.segment_line_intersection(
		Vector2(0, 0),
		Vector2(20, 20),
		Vector2(10, 0),
		Vector2(1, 0)
	)
	assert_not_null(intersection, "Diagonal crosses vertical")
	if intersection != null:
		assert_almost_eq(intersection.x, 10.0, 0.001, "Diagonal intersection X")
		assert_almost_eq(intersection.y, 10.0, 0.001, "Diagonal intersection Y")


# ===== polygon_area Tests =====

func test_area_simple_square():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var area = GeometryCore.polygon_area(square)
	assert_almost_eq(area, 10000.0, 0.1, "Square area (100x100)")


func test_area_triangle():
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	var area = GeometryCore.polygon_area(triangle)
	assert_almost_eq(area, 5000.0, 0.1, "Triangle area")


func test_area_reversed_winding():
	var square_reversed = PackedVector2Array([
		Vector2(0, 100),
		Vector2(100, 100),
		Vector2(100, 0),
		Vector2(0, 0)
	])
	var area = GeometryCore.polygon_area(square_reversed)
	assert_almost_eq(area, 10000.0, 0.1, "Square with reversed winding")


func test_area_small_rectangle():
	var rect = PackedVector2Array([
		Vector2(0, 0),
		Vector2(50, 0),
		Vector2(50, 20),
		Vector2(0, 20)
	])
	var area = GeometryCore.polygon_area(rect)
	assert_almost_eq(area, 1000.0, 0.1, "Rectangle area (50x20)")


func test_area_degenerate_polygon():
	var line = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0)
	])
	var area = GeometryCore.polygon_area(line)
	assert_almost_eq(area, 0.0, 0.1, "Degenerate polygon (line)")


# ===== polygon_centroid Tests =====

func test_centroid_square_at_origin():
	var square = PackedVector2Array([
		Vector2(-50, -50),
		Vector2(50, -50),
		Vector2(50, 50),
		Vector2(-50, 50)
	])
	var centroid = GeometryCore.polygon_centroid(square)
	assert_almost_eq(centroid.x, 0.0, 0.1, "Square centroid X")
	assert_almost_eq(centroid.y, 0.0, 0.1, "Square centroid Y")


func test_centroid_offset_square():
	var offset_square = PackedVector2Array([
		Vector2(100, 100),
		Vector2(200, 100),
		Vector2(200, 200),
		Vector2(100, 200)
	])
	var centroid = GeometryCore.polygon_centroid(offset_square)
	assert_almost_eq(centroid.x, 150.0, 0.1, "Offset square centroid X")
	assert_almost_eq(centroid.y, 150.0, 0.1, "Offset square centroid Y")


func test_centroid_triangle():
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(90, 0),
		Vector2(0, 90)
	])
	var centroid = GeometryCore.polygon_centroid(triangle)
	assert_almost_eq(centroid.x, 30.0, 1.0, "Triangle centroid X")
	assert_almost_eq(centroid.y, 30.0, 1.0, "Triangle centroid Y")


func test_centroid_single_point():
	var point = PackedVector2Array([Vector2(10, 20)])
	var centroid = GeometryCore.polygon_centroid(point)
	assert_almost_eq(centroid.x, 10.0, 0.1, "Single point X")
	assert_almost_eq(centroid.y, 20.0, 0.1, "Single point Y")


func test_centroid_two_points():
	var two_points = PackedVector2Array([Vector2(0, 0), Vector2(100, 100)])
	var centroid = GeometryCore.polygon_centroid(two_points)
	assert_almost_eq(centroid.x, 50.0, 0.1, "Two points midpoint X")
	assert_almost_eq(centroid.y, 50.0, 0.1, "Two points midpoint Y")


# ===== validate_polygon Tests =====

func test_validate_valid_square():
	var valid_square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var is_valid = GeometryCore.validate_polygon(valid_square)
	assert_true(is_valid, "Valid square")


func test_validate_valid_triangle():
	var valid_triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	var is_valid = GeometryCore.validate_polygon(valid_triangle)
	assert_true(is_valid, "Valid triangle")


func test_validate_too_few_vertices():
	var too_few = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0)
	])
	var is_valid = GeometryCore.validate_polygon(too_few)
	assert_false(is_valid, "Too few vertices (2)")


func test_validate_self_intersecting():
	var self_intersecting = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 100),
		Vector2(100, 0),
		Vector2(0, 100)
	])
	var is_valid = GeometryCore.validate_polygon(self_intersecting)
	assert_false(is_valid, "Self-intersecting polygon")


func test_validate_degenerate_edge():
	var degenerate = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 0),  # Duplicate
		Vector2(0, 100)
	])
	var is_valid = GeometryCore.validate_polygon(degenerate)
	assert_false(is_valid, "Degenerate edge (duplicate vertex)")


# ===== split_polygon_by_line Tests =====

func test_split_vertical():
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
	assert_eq(result["intersections"].size(), 2, "Vertical split: two intersections")


func test_split_horizontal():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(0, 50),
		Vector2(0, 1).normalized()
	)
	assert_true(result["left"].size() >= 3, "Horizontal split: left polygon has vertices")
	assert_true(result["right"].size() >= 3, "Horizontal split: right polygon has vertices")
	assert_eq(result["intersections"].size(), 2, "Horizontal split: two intersections")


func test_split_diagonal_45_degrees():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	# Split along diagonal y = x through corners (0,0) and (100,100)
	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(0, 0),
		Vector2(1, -1).normalized()
	)
	assert_true(result["left"].size() >= 3, "Diagonal split: left polygon has vertices")
	assert_true(result["right"].size() >= 3, "Diagonal split: right polygon has vertices")
	# Line passes through existing vertices (0,0) and (100,100), which are counted as intersections
	assert_eq(result["intersections"].size(), 2, "Diagonal through corners: 2 vertex intersections")


func test_split_through_vertices():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	# Split through center at 45-degree angle passing through opposite corners
	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(50, 50),
		Vector2(1, -1).normalized()
	)
	assert_true(result["left"].size() >= 3, "Through-vertex split: left polygon")
	assert_true(result["right"].size() >= 3, "Through-vertex split: right polygon")


func test_split_line_misses_polygon():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(200, 0),
		Vector2(1, 0).normalized()
	)
	var total_verts = result["left"].size() + result["right"].size()
	assert_true(total_verts >= 4, "Miss: all vertices on one side")
	assert_eq(result["intersections"].size(), 0, "Miss: no intersections")


func test_split_triangle():
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	var result = GeometryCore.split_polygon_by_line(
		triangle,
		Vector2(50, 0),
		Vector2(1, 0).normalized()
	)
	assert_true(result["left"].size() >= 3, "Triangle split: left polygon")
	assert_true(result["right"].size() >= 3, "Triangle split: right polygon")


# ===== Area Conservation Tests =====

func test_area_conservation_vertical_split():
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

	assert_almost_eq(total_area, original_area, 1.0, "Vertical split: area conservation")


func test_area_conservation_horizontal_split():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var original_area = GeometryCore.polygon_area(square)

	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(0, 50),
		Vector2(0, 1).normalized()
	)

	var left_area = GeometryCore.polygon_area(result["left"])
	var right_area = GeometryCore.polygon_area(result["right"])
	var total_area = left_area + right_area

	assert_almost_eq(total_area, original_area, 1.0, "Horizontal split: area conservation")


func test_area_conservation_diagonal_split():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var original_area = GeometryCore.polygon_area(square)

	var result = GeometryCore.split_polygon_by_line(
		square,
		Vector2(50, 50),
		Vector2(1, -1).normalized()
	)

	var left_area = GeometryCore.polygon_area(result["left"])
	var right_area = GeometryCore.polygon_area(result["right"])
	var total_area = left_area + right_area

	assert_almost_eq(total_area, original_area, 1.0, "Diagonal split: area conservation")


func test_area_conservation_triangle_split():
	var triangle = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(50, 100)
	])
	var original_area = GeometryCore.polygon_area(triangle)

	var result = GeometryCore.split_polygon_by_line(
		triangle,
		Vector2(50, 0),
		Vector2(1, 0).normalized()
	)

	var left_area = GeometryCore.polygon_area(result["left"])
	var right_area = GeometryCore.polygon_area(result["right"])
	var total_area = left_area + right_area

	assert_almost_eq(total_area, original_area, 1.0, "Triangle split: area conservation")


# ===== Helper Functions Tests =====

func test_segments_intersect_crossing():
	var intersects = GeometryCore.segments_intersect(
		Vector2(0, 0), Vector2(10, 10),
		Vector2(0, 10), Vector2(10, 0)
	)
	assert_true(intersects, "Segments intersect (X pattern)")


func test_segments_intersect_parallel():
	var intersects = GeometryCore.segments_intersect(
		Vector2(0, 0), Vector2(10, 0),
		Vector2(0, 10), Vector2(10, 10)
	)
	assert_false(intersects, "Segments don't intersect (parallel)")


func test_create_rect_vertices():
	var rect_verts = GeometryCore.create_rect_vertices(
		Vector2(50, 50),
		Vector2(100, 100)
	)
	assert_eq(rect_verts.size(), 4, "Rectangle has 4 vertices")
	var rect_area = GeometryCore.polygon_area(rect_verts)
	assert_almost_eq(rect_area, 10000.0, 0.1, "Rectangle area correct")


func test_point_in_polygon_inside():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var inside = GeometryCore.point_in_polygon(Vector2(50, 50), square)
	assert_true(inside, "Point inside square")


func test_point_in_polygon_outside():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var inside = GeometryCore.point_in_polygon(Vector2(150, 150), square)
	assert_false(inside, "Point outside square")


func test_point_in_polygon_on_edge():
	var square = PackedVector2Array([
		Vector2(0, 0),
		Vector2(100, 0),
		Vector2(100, 100),
		Vector2(0, 100)
	])
	var inside = GeometryCore.point_in_polygon(Vector2(0, 50), square)
	# Point on edge behavior can vary, we just check it doesn't crash
	assert_not_null(inside, "Point on edge doesn't crash")
