## Space-Folding Puzzle Game - Core Geometry Utilities
##
## This class provides all geometric calculations needed for the space-folding mechanics.
## All functions are static and thread-safe.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends Node
class_name GeometryCore

## Epsilon value for floating-point comparisons
## Never use == with floats; always use epsilon-based comparisons
const EPSILON = 0.0001


## Determines which side of a line a point is on.
##
## This uses the dot product of the vector from line_point to point with the line_normal.
## The line is defined by a point on the line and a normal vector.
##
## @param point: The point to test
## @param line_point: A point on the line
## @param line_normal: The normal vector of the line (should be normalized)
## @return: 1 if point is on positive side (direction of normal),
##          -1 if on negative side (opposite of normal),
##          0 if on the line (within EPSILON tolerance)
##
## Example:
##   var side = GeometryCore.point_side_of_line(Vector2(10, 10), Vector2(0, 0), Vector2(1, 0))
##   # Returns 1 if point is to the right of a vertical line at x=0
static func point_side_of_line(point: Vector2, line_point: Vector2, line_normal: Vector2) -> int:
	var to_point = point - line_point
	var distance = to_point.dot(line_normal)

	if abs(distance) < EPSILON:
		return 0
	return 1 if distance > 0 else -1


## Finds the intersection point between a line segment and an infinite line.
##
## The line segment is defined by two endpoints. The line is defined by a point
## and a normal vector. Returns null if the segment doesn't intersect the line.
##
## @param seg_start: Start point of the line segment
## @param seg_end: End point of the line segment
## @param line_point: A point on the line
## @param line_normal: The normal vector of the line (should be normalized)
## @return: Vector2 intersection point, or null if no intersection or segment is parallel
##
## Edge cases handled:
##   - Parallel segments return null
##   - Collinear segments return null
##   - Intersections outside segment bounds return null
##
## Example:
##   var intersection = GeometryCore.segment_line_intersection(
##       Vector2(0, 0), Vector2(10, 10),
##       Vector2(5, 0), Vector2(0, 1)
##   )
##   # Returns Vector2(5, 5) for a diagonal segment crossing a horizontal line
static func segment_line_intersection(seg_start: Vector2, seg_end: Vector2,
									  line_point: Vector2, line_normal: Vector2) -> Variant:
	var seg_dir = seg_end - seg_start
	var denominator = seg_dir.dot(line_normal)

	# Check if segment is parallel to line
	if abs(denominator) < EPSILON:
		return null

	# Calculate intersection parameter t (0 to 1 along segment)
	var t = (line_point - seg_start).dot(line_normal) / denominator

	# Check if intersection is within segment bounds
	if t < -EPSILON or t > 1.0 + EPSILON:
		return null

	# Clamp t to valid range and return intersection point
	return seg_start + seg_dir * clamp(t, 0.0, 1.0)


## Calculates the area of a polygon using the shoelace formula.
##
## The shoelace formula (also called the surveyor's formula) computes the area
## by summing the cross products of consecutive vertices.
##
## @param vertices: Array of vertices defining the polygon (counter-clockwise winding)
## @return: Area of the polygon (always positive)
##
## Note: This returns the absolute value, so winding order doesn't affect the result.
##
## Example:
##   var square = PackedVector2Array([
##       Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
##   ])
##   var area = GeometryCore.polygon_area(square)  # Returns 10000.0
static func polygon_area(vertices: PackedVector2Array) -> float:
	if vertices.size() < 3:
		return 0.0

	var area = 0.0
	var n = vertices.size()

	for i in range(n):
		var j = (i + 1) % n
		area += vertices[i].x * vertices[j].y
		area -= vertices[j].x * vertices[i].y

	return abs(area) / 2.0


## Calculates the centroid (geometric center) of a polygon.
##
## Uses the formula for polygon centroid which accounts for the shape's distribution.
## This is NOT the same as the average of vertices for non-convex polygons.
##
## @param vertices: Array of vertices defining the polygon (counter-clockwise winding)
## @return: The centroid point
##
## Note: For degenerate polygons (area ~ 0), returns the average of vertices.
##
## Example:
##   var triangle = PackedVector2Array([
##       Vector2(0, 0), Vector2(100, 0), Vector2(50, 100)
##   ])
##   var center = GeometryCore.polygon_centroid(triangle)
static func polygon_centroid(vertices: PackedVector2Array) -> Vector2:
	if vertices.size() == 0:
		return Vector2.ZERO

	if vertices.size() == 1:
		return vertices[0]

	if vertices.size() == 2:
		return (vertices[0] + vertices[1]) / 2.0

	var centroid = Vector2.ZERO
	var area = 0.0
	var n = vertices.size()

	for i in range(n):
		var j = (i + 1) % n
		var cross = vertices[i].x * vertices[j].y - vertices[j].x * vertices[i].y
		area += cross
		centroid += (vertices[i] + vertices[j]) * cross

	area *= 0.5

	# Handle degenerate polygon (area close to zero)
	if abs(area) < EPSILON:
		# Return average of vertices
		centroid = Vector2.ZERO
		for v in vertices:
			centroid += v
		return centroid / n

	return centroid / (6.0 * area)


## Validates a polygon for basic correctness.
##
## Checks performed:
##   - Minimum 3 vertices
##   - No self-intersections (checks all edge pairs)
##   - No degenerate edges (zero length)
##
## @param vertices: Array of vertices defining the polygon
## @return: true if polygon is valid, false otherwise
##
## Note: This is a thorough but potentially expensive check. Use sparingly.
##
## Example:
##   var valid_square = PackedVector2Array([
##       Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
##   ])
##   var is_valid = GeometryCore.validate_polygon(valid_square)  # Returns true
static func validate_polygon(vertices: PackedVector2Array) -> bool:
	# Check minimum vertex count
	if vertices.size() < 3:
		return false

	var n = vertices.size()

	# Check for degenerate edges (zero length)
	for i in range(n):
		var j = (i + 1) % n
		if vertices[i].distance_to(vertices[j]) < EPSILON:
			return false

	# Check for self-intersection
	# Compare all non-adjacent edge pairs
	for i in range(n):
		var a1 = vertices[i]
		var a2 = vertices[(i + 1) % n]

		# Start at i+2 to skip adjacent edge
		for j in range(i + 2, n):
			# Skip the edge that wraps around and connects to our start
			if j == n - 1 and i == 0:
				continue

			var b1 = vertices[j]
			var b2 = vertices[(j + 1) % n]

			if segments_intersect(a1, a2, b1, b2):
				return false

	return true


## Checks if two line segments intersect.
##
## Helper function for polygon validation. Tests if two segments cross each other.
##
## @param a1: First point of segment A
## @param a2: Second point of segment A
## @param b1: First point of segment B
## @param b2: Second point of segment B
## @return: true if segments intersect (excluding endpoints touching)
static func segments_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	# Calculate cross product for line intersection
	var d = (a2.x - a1.x) * (b2.y - b1.y) - (a2.y - a1.y) * (b2.x - b1.x)

	if abs(d) < EPSILON:
		return false  # Parallel or collinear

	# Calculate intersection parameters
	var t = ((b1.x - a1.x) * (b2.y - b1.y) - (b1.y - a1.y) * (b2.x - b1.x)) / d
	var u = ((b1.x - a1.x) * (a2.y - a1.y) - (b1.y - a1.y) * (a2.x - a1.x)) / d

	# Check if intersection is within both segments (excluding endpoints)
	return t > EPSILON and t < 1.0 - EPSILON and u > EPSILON and u < 1.0 - EPSILON


## Splits a polygon by a line using the Sutherland-Hodgman algorithm.
##
## This is the CRITICAL function for the space-folding mechanic. It divides a polygon
## into two parts: vertices on the left (positive) side and right (negative) side of the line.
##
## Algorithm:
##   1. Iterate through all edges of the polygon
##   2. For each edge, determine which side(s) of the line its vertices are on
##   3. If edge crosses the line, compute intersection point
##   4. Build two output polygons with appropriate vertices and intersections
##
## @param vertices: Array of vertices defining the polygon (counter-clockwise winding)
## @param line_point: A point on the splitting line
## @param line_normal: The normal vector of the line (should be normalized)
## @return: Dictionary with keys:
##          - "left": PackedVector2Array of vertices on positive side
##          - "right": PackedVector2Array of vertices on negative side
##          - "intersections": PackedVector2Array of intersection points
##
## Edge cases handled:
##   - Vertices exactly on the line are added to both sides
##   - Line that doesn't intersect polygon returns one full polygon and one empty
##   - Line through vertices creates proper splits
##
## Example:
##   var square = PackedVector2Array([
##       Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
##   ])
##   var result = GeometryCore.split_polygon_by_line(
##       square, Vector2(50, 0), Vector2(1, 0).normalized()
##   )
##   # Splits square vertically at x=50
##   # result["left"] contains right half (positive x direction)
##   # result["right"] contains left half (negative x direction)
##   # result["intersections"] contains two points where line crosses edges
static func split_polygon_by_line(vertices: PackedVector2Array,
								  line_point: Vector2,
								  line_normal: Vector2) -> Dictionary:
	var left_verts = PackedVector2Array()
	var right_verts = PackedVector2Array()
	var intersections = PackedVector2Array()

	if vertices.size() < 3:
		return {
			"left": PackedVector2Array(),
			"right": PackedVector2Array(),
			"intersections": PackedVector2Array()
		}

	var n = vertices.size()

	# Process each edge of the polygon
	for i in range(n):
		var current = vertices[i]
		var next = vertices[(i + 1) % n]

		var current_side = point_side_of_line(current, line_point, line_normal)
		var next_side = point_side_of_line(next, line_point, line_normal)

		# Add current vertex to appropriate side(s)
		if current_side >= 0:  # On line or positive side
			left_verts.append(current)
		if current_side <= 0:  # On line or negative side
			right_verts.append(current)

		# Check if edge crosses the line
		if current_side * next_side < 0:  # Different sides (not including 0)
			var intersection = segment_line_intersection(current, next, line_point, line_normal)
			if intersection != null:
				intersections.append(intersection)
				left_verts.append(intersection)
				right_verts.append(intersection)

	return {
		"left": left_verts,
		"right": right_verts,
		"intersections": intersections
	}


## Creates vertices for a rectangle.
##
## Utility function for creating rectangular polygons (useful for initial grid cells).
##
## @param center: The center point of the rectangle
## @param size: The width and height of the rectangle
## @return: PackedVector2Array with 4 vertices in counter-clockwise order
##
## Example:
##   var rect_verts = GeometryCore.create_rect_vertices(
##       Vector2(100, 100), Vector2(50, 50)
##   )
##   # Creates a 50x50 rectangle centered at (100, 100)
static func create_rect_vertices(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half_size = size * 0.5
	return PackedVector2Array([
		center + Vector2(-half_size.x, -half_size.y),  # Top-left
		center + Vector2(half_size.x, -half_size.y),   # Top-right
		center + Vector2(half_size.x, half_size.y),    # Bottom-right
		center + Vector2(-half_size.x, half_size.y)    # Bottom-left
	])


## Tests if a point is inside a polygon using ray casting algorithm.
##
## This is useful for checking if the player is inside a cell or for
## other containment tests.
##
## @param point: The point to test
## @param vertices: Array of vertices defining the polygon
## @return: true if point is inside polygon, false otherwise
##
## Example:
##   var square = PackedVector2Array([
##       Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
##   ])
##   var inside = GeometryCore.point_in_polygon(Vector2(50, 50), square)  # Returns true
static func point_in_polygon(point: Vector2, vertices: PackedVector2Array) -> bool:
	if vertices.size() < 3:
		return false

	var inside = false
	var n = vertices.size()
	var p1 = vertices[n - 1]

	for i in range(n):
		var p2 = vertices[i]

		if ((p2.y > point.y) != (p1.y > point.y)) and \
		   (point.x < (p1.x - p2.x) * (point.y - p2.y) / (p1.y - p2.y) + p2.x):
			inside = !inside

		p1 = p2

	return inside
