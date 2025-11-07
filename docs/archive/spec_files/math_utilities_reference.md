# Space-Folding Puzzle: Critical Mathematical Utilities

## Essential Geometric Functions for Godot Implementation

### Core Mathematical Operations Needed

```gdscript
# GeometryCore.gd - Put this in scripts/utils/

extends Node
class_name GeometryCore

const EPSILON = 0.0001  # For floating-point comparisons

# 1. Point-Line Relationship
static func point_side_of_line(point: Vector2, line_point: Vector2, line_normal: Vector2) -> int:
    """
    Returns: 1 if point is on positive side, -1 if negative side, 0 if on line
    """
    var to_point = point - line_point
    var distance = to_point.dot(line_normal)
    
    if abs(distance) < EPSILON:
        return 0
    return 1 if distance > 0 else -1

# 2. Line-Segment Intersection
static func segment_line_intersection(seg_start: Vector2, seg_end: Vector2, 
                                     line_point: Vector2, line_normal: Vector2) -> Variant:
    """
    Returns: Vector2 intersection point, or null if no intersection
    """
    var seg_dir = seg_end - seg_start
    var denominator = seg_dir.dot(line_normal)
    
    if abs(denominator) < EPSILON:
        return null  # Parallel
    
    var t = (line_point - seg_start).dot(line_normal) / denominator
    
    if t < -EPSILON or t > 1.0 + EPSILON:
        return null  # Outside segment
    
    return seg_start + seg_dir * clamp(t, 0.0, 1.0)

# 3. Polygon Splitting
static func split_polygon_by_line(vertices: PackedVector2Array, 
                                 line_point: Vector2, 
                                 line_normal: Vector2) -> Dictionary:
    """
    Returns: {"left": PackedVector2Array, "right": PackedVector2Array, 
              "intersections": PackedVector2Array}
    """
    var left_verts = PackedVector2Array()
    var right_verts = PackedVector2Array()
    var intersections = PackedVector2Array()
    
    var n = vertices.size()
    for i in range(n):
        var current = vertices[i]
        var next = vertices[(i + 1) % n]
        
        var current_side = point_side_of_line(current, line_point, line_normal)
        var next_side = point_side_of_line(next, line_point, line_normal)
        
        # Add current vertex to appropriate side(s)
        if current_side >= 0:
            left_verts.append(current)
        if current_side <= 0:
            right_verts.append(current)
        
        # Check for intersection
        if current_side * next_side < 0:  # Different sides
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

# 4. Point in Polygon Test (useful for player position checks)
static func point_in_polygon(point: Vector2, vertices: PackedVector2Array) -> bool:
    """
    Ray casting algorithm for point-in-polygon test
    """
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

# 5. Polygon Area (useful for validation)
static func polygon_area(vertices: PackedVector2Array) -> float:
    """
    Shoelace formula for polygon area
    """
    var area = 0.0
    var n = vertices.size()
    
    for i in range(n):
        var j = (i + 1) % n
        area += vertices[i].x * vertices[j].y
        area -= vertices[j].x * vertices[i].y
    
    return abs(area) / 2.0

# 6. Polygon Centroid (useful for anchor points)
static func polygon_centroid(vertices: PackedVector2Array) -> Vector2:
    """
    Calculate the centroid of a polygon
    """
    var centroid = Vector2.ZERO
    var area = 0.0
    var n = vertices.size()
    
    for i in range(n):
        var j = (i + 1) % n
        var cross = vertices[i].x * vertices[j].y - vertices[j].x * vertices[i].y
        area += cross
        centroid += (vertices[i] + vertices[j]) * cross
    
    area *= 0.5
    if abs(area) < EPSILON:
        # Degenerate polygon, return average of vertices
        for v in vertices:
            centroid += v
        return centroid / n
    
    return centroid / (6.0 * area)

# 7. Create Rectangle Vertices (for initial grid cells)
static func create_rect_vertices(center: Vector2, size: Vector2) -> PackedVector2Array:
    """
    Create vertices for a rectangle centered at 'center' with given 'size'
    """
    var half_size = size * 0.5
    return PackedVector2Array([
        center + Vector2(-half_size.x, -half_size.y),  # Top-left
        center + Vector2(half_size.x, -half_size.y),   # Top-right
        center + Vector2(half_size.x, half_size.y),    # Bottom-right
        center + Vector2(-half_size.x, half_size.y)    # Bottom-left
    ])

# 8. Merge Two Polygons Along a Seam
static func merge_split_polygons(poly1: PackedVector2Array, 
                                poly2: PackedVector2Array,
                                seam_points: PackedVector2Array) -> PackedVector2Array:
    """
    Merge two polygons that share a seam
    This is complex and may need refinement based on your specific needs
    """
    # Remove duplicate seam points from both polygons
    # Then concatenate in correct order
    # This is a simplified version - you may need more sophisticated merging
    
    var merged = PackedVector2Array()
    
    # Add all vertices from poly1 except seam duplicates
    for v in poly1:
        var is_seam = false
        for s in seam_points:
            if v.distance_to(s) < EPSILON:
                is_seam = true
                break
        if not is_seam:
            merged.append(v)
    
    # Add seam points once
    for s in seam_points:
        merged.append(s)
    
    # Add vertices from poly2 except seam duplicates  
    for v in poly2:
        var is_seam = false
        for s in seam_points:
            if v.distance_to(s) < EPSILON:
                is_seam = true
                break
        if not is_seam:
            merged.append(v)
    
    return merged

# 9. Validate Polygon (check for self-intersection, correct winding)
static func validate_polygon(vertices: PackedVector2Array) -> bool:
    """
    Basic validation - check if polygon is valid
    """
    if vertices.size() < 3:
        return false
    
    # Check for self-intersection (simplified - only checks adjacent edges)
    var n = vertices.size()
    for i in range(n):
        var a1 = vertices[i]
        var a2 = vertices[(i + 1) % n]
        
        for j in range(i + 2, n):
            if j == (i + n - 1) % n:  # Skip adjacent edge
                continue
                
            var b1 = vertices[j]
            var b2 = vertices[(j + 1) % n]
            
            if segments_intersect(a1, a2, b1, b2):
                return false
    
    return true

static func segments_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
    """
    Check if two line segments intersect
    """
    var d = (a2.x - a1.x) * (b2.y - b1.y) - (a2.y - a1.y) * (b2.x - b1.x)
    
    if abs(d) < EPSILON:
        return false  # Parallel
    
    var t = ((b1.x - a1.x) * (b2.y - b1.y) - (b1.y - a1.y) * (b2.x - b1.x)) / d
    var u = ((b1.x - a1.x) * (a2.y - a1.y) - (b1.y - a1.y) * (a2.x - a1.x)) / d
    
    return t >= 0 and t <= 1 and u >= 0 and u <= 1
```

## Quick Start Usage Examples

### Example 1: Basic Fold Operation

```gdscript
extends Node

func perform_fold(anchor1: Vector2, anchor2: Vector2, cells: Array) -> void:
    # Calculate perpendicular cut lines
    var fold_vector = anchor2 - anchor1
    var perpendicular = Vector2(-fold_vector.y, fold_vector.x).normalized()
    
    var cut_line1_point = anchor1
    var cut_line2_point = anchor2
    
    for cell in cells:
        # Check which region the cell is in
        var center = cell.get_center()
        var side1 = GeometryCore.point_side_of_line(center, cut_line1_point, perpendicular)
        var side2 = GeometryCore.point_side_of_line(center, cut_line2_point, perpendicular)
        
        if side1 <= 0 and side2 >= 0:
            # Cell is in the region to be removed
            cell.mark_for_removal()
        elif side1 * side2 < 0:
            # Cell is split by one of the cut lines
            var split_result = GeometryCore.split_polygon_by_line(
                cell.geometry,
                cut_line1_point if side1 == 0 else cut_line2_point,
                perpendicular
            )
            cell.apply_split(split_result)
```

### Example 2: Cell Class with Geometry

```gdscript
class_name Cell
extends Node2D

var grid_position: Vector2i
var geometry: PackedVector2Array
var seams: Array = []
var cell_type: int = 0
var polygon_visual: Polygon2D

func _init(pos: Vector2i, world_pos: Vector2, size: Vector2):
    grid_position = pos
    position = world_pos
    geometry = GeometryCore.create_rect_vertices(Vector2.ZERO, size)
    
    # Create visual representation
    polygon_visual = Polygon2D.new()
    polygon_visual.polygon = geometry
    polygon_visual.color = Color.WHITE
    add_child(polygon_visual)

func apply_split(split_result: Dictionary) -> Cell:
    # This cell keeps one half
    geometry = split_result["left"]
    polygon_visual.polygon = geometry
    
    # Create new cell for other half
    var new_cell = Cell.new(grid_position, position, Vector2.ZERO)
    new_cell.geometry = split_result["right"]
    new_cell.cell_type = cell_type
    
    # Store seam information
    var seam = {
        "points": split_result["intersections"],
        "timestamp": Time.get_ticks_msec()
    }
    seams.append(seam)
    new_cell.seams.append(seam)
    
    return new_cell

func get_center() -> Vector2:
    return GeometryCore.polygon_centroid(geometry)
```

### Example 3: Testing Utilities

```gdscript
extends Node

func test_polygon_split():
    var square = GeometryCore.create_rect_vertices(Vector2.ZERO, Vector2(100, 100))
    
    # Test diagonal split
    var line_point = Vector2.ZERO
    var line_normal = Vector2(1, 1).normalized()
    
    var result = GeometryCore.split_polygon_by_line(square, line_point, line_normal)
    
    assert(result["left"].size() == 3)  # Triangle
    assert(result["right"].size() == 3)  # Triangle
    assert(result["intersections"].size() == 2)  # Two intersection points
    
    # Verify areas sum to original
    var original_area = GeometryCore.polygon_area(square)
    var left_area = GeometryCore.polygon_area(result["left"])
    var right_area = GeometryCore.polygon_area(result["right"])
    
    assert(abs(original_area - (left_area + right_area)) < 0.01)
```

## Critical Implementation Notes

1. **Always use EPSILON for floating-point comparisons** - Never use == with floats
2. **Vertex winding order matters** - Godot expects counter-clockwise for positive area
3. **Handle degenerate cases** - Always check for zero-length vectors, parallel lines, etc.
4. **Test edge cases extensively** - Cuts through vertices are particularly tricky
5. **Cache calculations** - Don't recalculate centroids/areas unnecessarily
6. **Use Godot's built-in when possible** - Geometry2D class has some useful methods

## Performance Optimizations

- Pre-calculate and store cell centroids
- Use spatial partitioning (quadtree) for large grids
- Batch visual updates after fold operations
- Use object pooling for split cells
- Consider using MultiMesh for rendering many cells

This should give you all the mathematical tools needed to implement the space-folding mechanic!
