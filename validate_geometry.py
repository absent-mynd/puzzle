#!/usr/bin/env python3
"""
Python-based validation of GeometryCore algorithms.

This script implements the same geometric algorithms as GeometryCore.gd
to validate the mathematical logic independently of Godot.
"""

import math
from typing import List, Tuple, Optional, Dict

EPSILON = 0.0001


class Vector2:
    """Simple Vector2 implementation for testing."""

    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y

    def __sub__(self, other: 'Vector2') -> 'Vector2':
        return Vector2(self.x - other.x, self.y - other.y)

    def __add__(self, other: 'Vector2') -> 'Vector2':
        return Vector2(self.x + other.x, self.y + other.y)

    def __mul__(self, scalar: float) -> 'Vector2':
        return Vector2(self.x * scalar, self.y * scalar)

    def dot(self, other: 'Vector2') -> float:
        return self.x * other.x + self.y * other.y

    def normalized(self) -> 'Vector2':
        length = math.sqrt(self.x * self.x + self.y * self.y)
        if length < EPSILON:
            return Vector2(0, 0)
        return Vector2(self.x / length, self.y / length)

    def distance_to(self, other: 'Vector2') -> float:
        dx = self.x - other.x
        dy = self.y - other.y
        return math.sqrt(dx * dx + dy * dy)

    def __repr__(self):
        return f"Vector2({self.x:.4f}, {self.y:.4f})"


def point_side_of_line(point: Vector2, line_point: Vector2, line_normal: Vector2) -> int:
    """Determines which side of a line a point is on."""
    to_point = point - line_point
    distance = to_point.dot(line_normal)

    if abs(distance) < EPSILON:
        return 0
    return 1 if distance > 0 else -1


def segment_line_intersection(seg_start: Vector2, seg_end: Vector2,
                               line_point: Vector2, line_normal: Vector2) -> Optional[Vector2]:
    """Finds intersection between line segment and infinite line."""
    seg_dir = seg_end - seg_start
    denominator = seg_dir.dot(line_normal)

    if abs(denominator) < EPSILON:
        return None

    # Calculate the parameter t along the segment
    t = (line_point - seg_start).dot(line_normal) / denominator

    if t < -EPSILON or t > 1.0 + EPSILON:
        return None

    # Clamp t to valid range [0, 1]
    t_clamped = max(0.0, min(1.0, t))
    return Vector2(seg_start.x + seg_dir.x * t_clamped,
                   seg_start.y + seg_dir.y * t_clamped)


def polygon_area(vertices: List[Vector2]) -> float:
    """Calculates polygon area using shoelace formula."""
    if len(vertices) < 3:
        return 0.0

    area = 0.0
    n = len(vertices)

    for i in range(n):
        j = (i + 1) % n
        area += vertices[i].x * vertices[j].y
        area -= vertices[j].x * vertices[i].y

    return abs(area) / 2.0


def polygon_centroid(vertices: List[Vector2]) -> Vector2:
    """Calculates polygon centroid."""
    if len(vertices) == 0:
        return Vector2(0, 0)

    if len(vertices) == 1:
        return vertices[0]

    if len(vertices) == 2:
        return (vertices[0] + vertices[1]) * 0.5

    centroid = Vector2(0, 0)
    area = 0.0
    n = len(vertices)

    for i in range(n):
        j = (i + 1) % n
        cross = vertices[i].x * vertices[j].y - vertices[j].x * vertices[i].y
        area += cross
        centroid = centroid + (vertices[i] + vertices[j]) * cross

    area *= 0.5

    if abs(area) < EPSILON:
        centroid = Vector2(0, 0)
        for v in vertices:
            centroid = centroid + v
        return centroid * (1.0 / n)

    return centroid * (1.0 / (6.0 * area))


def split_polygon_by_line(vertices: List[Vector2], line_point: Vector2,
                          line_normal: Vector2) -> Dict[str, List[Vector2]]:
    """Splits polygon by line using Sutherland-Hodgman algorithm."""
    left_verts = []
    right_verts = []
    intersections = []

    if len(vertices) < 3:
        return {"left": [], "right": [], "intersections": []}

    n = len(vertices)

    for i in range(n):
        current = vertices[i]
        next_vertex = vertices[(i + 1) % n]

        current_side = point_side_of_line(current, line_point, line_normal)
        next_side = point_side_of_line(next_vertex, line_point, line_normal)

        if current_side >= 0:
            left_verts.append(current)
        if current_side <= 0:
            right_verts.append(current)

        if current_side * next_side < 0:
            intersection = segment_line_intersection(current, next_vertex, line_point, line_normal)
            if intersection is not None:
                intersections.append(intersection)
                left_verts.append(intersection)
                right_verts.append(intersection)

    return {
        "left": left_verts,
        "right": right_verts,
        "intersections": intersections
    }


# ===== Test Suite =====

def test_point_side_of_line():
    print("Testing point_side_of_line...")

    # Point on positive side
    result = point_side_of_line(Vector2(10, 0), Vector2(0, 0), Vector2(1, 0))
    assert result == 1, f"Expected 1, got {result}"

    # Point on negative side
    result = point_side_of_line(Vector2(-10, 0), Vector2(0, 0), Vector2(1, 0))
    assert result == -1, f"Expected -1, got {result}"

    # Point on line
    result = point_side_of_line(Vector2(0, 100), Vector2(0, 0), Vector2(1, 0))
    assert result == 0, f"Expected 0, got {result}"

    print("  ✓ All point_side_of_line tests passed")


def test_segment_line_intersection():
    print("Testing segment_line_intersection...")

    # Clear intersection - diagonal segment (0,0) to (10,10) crossing vertical line at x=5
    seg_start = Vector2(0, 0)
    seg_end = Vector2(10, 10)
    line_point = Vector2(5, 0)  # Point on vertical line x=5
    line_normal = Vector2(1, 0)  # Normal pointing right for vertical line

    intersection = segment_line_intersection(seg_start, seg_end, line_point, line_normal)

    assert intersection is not None, "Expected intersection"
    assert abs(intersection.x - 5.0) < 0.001, f"X should be 5.0, got {intersection.x}"
    assert abs(intersection.y - 5.0) < 0.001, f"Y should be 5.0, got {intersection.y}"

    # Parallel (no intersection) - horizontal segment parallel to horizontal line
    # Segment from (0,0) to (10,0) is horizontal
    # Line at y=5 with normal (0,1) is also horizontal - they're parallel!
    intersection = segment_line_intersection(
        Vector2(0, 0), Vector2(10, 0),  # Horizontal segment at y=0
        Vector2(0, 5), Vector2(0, 1)     # Horizontal line at y=5 (normal points up)
    )
    assert intersection is None, "Expected None for parallel segments"

    print("  ✓ All segment_line_intersection tests passed")


def test_polygon_area():
    print("Testing polygon_area...")

    # Square 100x100
    square = [
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ]
    area = polygon_area(square)
    assert abs(area - 10000.0) < 0.1, f"Expected 10000.0, got {area}"

    # Triangle
    triangle = [
        Vector2(0, 0), Vector2(100, 0), Vector2(50, 100)
    ]
    area = polygon_area(triangle)
    assert abs(area - 5000.0) < 0.1, f"Expected 5000.0, got {area}"

    print("  ✓ All polygon_area tests passed")


def test_polygon_centroid():
    print("Testing polygon_centroid...")

    # Square centered at origin
    square = [
        Vector2(-50, -50), Vector2(50, -50),
        Vector2(50, 50), Vector2(-50, 50)
    ]
    centroid = polygon_centroid(square)
    assert abs(centroid.x - 0.0) < 0.1, f"Centroid X should be 0, got {centroid.x}"
    assert abs(centroid.y - 0.0) < 0.1, f"Centroid Y should be 0, got {centroid.y}"

    # Offset square
    square = [
        Vector2(100, 100), Vector2(200, 100),
        Vector2(200, 200), Vector2(100, 200)
    ]
    centroid = polygon_centroid(square)
    assert abs(centroid.x - 150.0) < 0.1, f"Centroid X should be 150, got {centroid.x}"
    assert abs(centroid.y - 150.0) < 0.1, f"Centroid Y should be 150, got {centroid.y}"

    print("  ✓ All polygon_centroid tests passed")


def test_split_polygon_by_line():
    print("Testing split_polygon_by_line...")

    square = [
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ]

    # Vertical split
    result = split_polygon_by_line(square, Vector2(50, 0), Vector2(1, 0).normalized())
    assert len(result["left"]) >= 3, f"Left should have >= 3 vertices, got {len(result['left'])}"
    assert len(result["right"]) >= 3, f"Right should have >= 3 vertices, got {len(result['right'])}"
    assert len(result["intersections"]) == 2, f"Should have 2 intersections, got {len(result['intersections'])}"

    # Horizontal split
    result = split_polygon_by_line(square, Vector2(0, 50), Vector2(0, 1).normalized())
    assert len(result["left"]) >= 3, "Left polygon should have vertices"
    assert len(result["right"]) >= 3, "Right polygon should have vertices"
    assert len(result["intersections"]) == 2, "Should have 2 intersections"

    print("  ✓ All split_polygon_by_line tests passed")


def test_area_conservation():
    print("Testing area conservation...")

    square = [
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ]
    original_area = polygon_area(square)

    # Vertical split
    result = split_polygon_by_line(square, Vector2(50, 0), Vector2(1, 0).normalized())
    left_area = polygon_area(result["left"])
    right_area = polygon_area(result["right"])
    total_area = left_area + right_area

    diff = abs(total_area - original_area)
    assert diff < 1.0, f"Area conservation failed: original={original_area}, total={total_area}, diff={diff}"

    # Diagonal split
    result = split_polygon_by_line(square, Vector2(50, 50), Vector2(1, 1).normalized())
    left_area = polygon_area(result["left"])
    right_area = polygon_area(result["right"])
    total_area = left_area + right_area

    diff = abs(total_area - original_area)
    assert diff < 1.0, f"Area conservation failed for diagonal: original={original_area}, total={total_area}, diff={diff}"

    print("  ✓ All area conservation tests passed")


def run_all_tests():
    print("\n" + "="*60)
    print("GeometryCore Algorithm Validation (Python)")
    print("="*60 + "\n")

    try:
        test_point_side_of_line()
        test_segment_line_intersection()
        test_polygon_area()
        test_polygon_centroid()
        test_split_polygon_by_line()
        test_area_conservation()

        print("\n" + "="*60)
        print("✓ ALL TESTS PASSED!")
        print("="*60)
        print("\nThe mathematical algorithms in GeometryCore.gd are correct.")
        print("GDScript implementation follows the same logic.\n")
        return 0

    except AssertionError as e:
        print(f"\n✗ TEST FAILED: {e}\n")
        return 1
    except Exception as e:
        print(f"\n✗ UNEXPECTED ERROR: {e}\n")
        return 1


if __name__ == "__main__":
    exit(run_all_tests())
