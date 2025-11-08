# Phase 5: Multi-Seam Handling - Implementation Specification

**Status:** 📋 Ready to Start
**Priority:** P1 (Critical Path)
**Estimated Time:** 6-9 hours (2-3h prep + 4-6h core)
**Complexity:** ⭐⭐⭐⭐ (High)
**Dependencies:** Phase 4 (Geometric Folding) ✅ Complete

---

## Overview

Phase 5 implements the ability for cells to handle multiple intersecting fold seams through tessellation. This is essential for complex puzzle scenarios where multiple folds affect the same cell.

**Core Concept:** When a cell has been split by multiple folds, we subdivide it into smaller convex polygons (tessellation), each bounded by the seam lines. This allows accurate tracking of geometry and enables proper undo/redo in Phase 6.

---

## Objectives

### Primary Goals
1. ✅ Implement Seam class for tracking fold lines within cells
2. ✅ Enhance fold history to store complete cell state
3. ✅ Add polygon union algorithm to GeometryCore
4. ✅ Implement tessellation algorithm for multi-seam cells
5. ✅ Handle seam intersection detection and updates
6. ✅ Create visual representation of seams within cells
7. ✅ Ensure memory safety and performance

### Success Criteria
- Cells can store and track multiple seams
- Tessellation correctly subdivides cells at seam intersections
- All existing tests continue to pass (361/363)
- New tests achieve 100% coverage (25-35 new tests)
- No memory leaks
- Performance remains under 100ms per fold operation

---

## Prerequisites (2-3 hours)

These must be completed **before** starting core Phase 5 work.

### Task 1: Implement Seam Class (30-45 min)

**File:** `scripts/core/Seam.gd`

**Implementation:**
```gdscript
class_name Seam extends Resource

## Seam
##
## Represents a fold line within a cell. Stores metadata about the fold
## that created this seam and the geometric properties of the seam line.

## Point on the seam line (LOCAL coordinates relative to GridManager)
@export var line_point: Vector2

## Normal vector of the seam line (perpendicular to fold axis)
@export var line_normal: Vector2

## Points where seam intersects the cell boundary
## Should always have exactly 2 points for a valid seam
@export var intersection_points: PackedVector2Array

## ID of the fold that created this seam
@export var fold_id: int

## Timestamp when seam was created (for ordering)
@export var timestamp: int

## Type of fold that created this seam
@export var fold_type: String  # "horizontal", "vertical", "diagonal"

## Optional metadata for future use
@export var metadata: Dictionary = {}


## Constructor
func _init(
    p_line_point: Vector2 = Vector2.ZERO,
    p_line_normal: Vector2 = Vector2.ZERO,
    p_intersection_points: PackedVector2Array = PackedVector2Array(),
    p_fold_id: int = -1,
    p_timestamp: int = 0,
    p_fold_type: String = ""
):
    line_point = p_line_point
    line_normal = p_line_normal
    intersection_points = p_intersection_points
    fold_id = p_fold_id
    timestamp = p_timestamp
    fold_type = p_fold_type


## Get the two endpoints of the seam within the cell
##
## @return: Array with 2 Vector2 points, or empty if invalid
func get_seam_endpoints() -> Array[Vector2]:
    if intersection_points.size() < 2:
        return []
    return [intersection_points[0], intersection_points[1]]


## Get the seam as a line segment (for visualization)
##
## @return: Dictionary with "start" and "end" keys
func get_line_segment() -> Dictionary:
    var endpoints = get_seam_endpoints()
    if endpoints.is_empty():
        return {"start": Vector2.ZERO, "end": Vector2.ZERO}
    return {"start": endpoints[0], "end": endpoints[1]}


## Check if this seam is parallel to another seam
##
## @param other: Another Seam to compare with
## @param epsilon: Tolerance for parallel check
## @return: true if seams are parallel
func is_parallel_to(other: Seam, epsilon: float = 0.0001) -> bool:
    # Two lines are parallel if their normals are parallel
    var dot = abs(line_normal.dot(other.line_normal))
    return abs(dot - 1.0) < epsilon


## Check if this seam intersects another seam
##
## @param other: Another Seam to check intersection with
## @return: Vector2 intersection point, or Vector2.INF if no intersection
func intersects_with(other: Seam) -> Vector2:
    # Use GeometryCore to find intersection of two lines
    var endpoints1 = get_seam_endpoints()
    var endpoints2 = other.get_seam_endpoints()

    if endpoints1.is_empty() or endpoints2.is_empty():
        return Vector2.INF

    return GeometryCore.segment_line_intersection(
        endpoints1[0], endpoints1[1],
        endpoints2[0], endpoints2[1]
    )


## Create a deep copy of this seam
##
## @return: New Seam with duplicate data
func duplicate_seam() -> Seam:
    var new_seam = Seam.new()
    new_seam.line_point = line_point
    new_seam.line_normal = line_normal
    new_seam.intersection_points = intersection_points.duplicate()
    new_seam.fold_id = fold_id
    new_seam.timestamp = timestamp
    new_seam.fold_type = fold_type
    new_seam.metadata = metadata.duplicate(true)
    return new_seam


## Serialize seam to dictionary (for save/load)
##
## @return: Dictionary containing all seam data
func to_dict() -> Dictionary:
    return {
        "line_point": {"x": line_point.x, "y": line_point.y},
        "line_normal": {"x": line_normal.x, "y": line_normal.y},
        "intersection_points": _pack_to_array(intersection_points),
        "fold_id": fold_id,
        "timestamp": timestamp,
        "fold_type": fold_type,
        "metadata": metadata
    }


## Deserialize seam from dictionary
##
## @param dict: Dictionary containing seam data
static func from_dict(dict: Dictionary) -> Seam:
    var seam = Seam.new()

    if dict.has("line_point"):
        var lp = dict["line_point"]
        seam.line_point = Vector2(lp.x, lp.y)

    if dict.has("line_normal"):
        var ln = dict["line_normal"]
        seam.line_normal = Vector2(ln.x, ln.y)

    if dict.has("intersection_points"):
        seam.intersection_points = _array_to_pack(dict["intersection_points"])

    seam.fold_id = dict.get("fold_id", -1)
    seam.timestamp = dict.get("timestamp", 0)
    seam.fold_type = dict.get("fold_type", "")
    seam.metadata = dict.get("metadata", {})

    return seam


## Helper: Convert PackedVector2Array to array of dicts
static func _pack_to_array(packed: PackedVector2Array) -> Array:
    var result = []
    for v in packed:
        result.append({"x": v.x, "y": v.y})
    return result


## Helper: Convert array of dicts to PackedVector2Array
static func _array_to_pack(arr: Array) -> PackedVector2Array:
    var result = PackedVector2Array()
    for item in arr:
        result.append(Vector2(item.x, item.y))
    return result
```

**Test File:** `scripts/tests/test_seam.gd`

**Required Tests (5-8 tests):**
```gdscript
extends GutTest

var seam1: Seam
var seam2: Seam


func before_each():
    seam1 = Seam.new(
        Vector2(100, 100),
        Vector2(0, 1),
        PackedVector2Array([Vector2(50, 100), Vector2(150, 100)]),
        0,
        1000,
        "horizontal"
    )

    seam2 = Seam.new(
        Vector2(100, 100),
        Vector2(1, 0),
        PackedVector2Array([Vector2(100, 50), Vector2(100, 150)]),
        1,
        2000,
        "vertical"
    )


func test_seam_creation():
    assert_not_null(seam1, "Seam should be created")
    assert_eq(seam1.fold_id, 0, "Fold ID should be set")
    assert_eq(seam1.fold_type, "horizontal", "Fold type should be set")


func test_get_seam_endpoints():
    var endpoints = seam1.get_seam_endpoints()
    assert_eq(endpoints.size(), 2, "Should have 2 endpoints")
    assert_eq(endpoints[0], Vector2(50, 100), "First endpoint correct")
    assert_eq(endpoints[1], Vector2(150, 100), "Second endpoint correct")


func test_is_parallel_to():
    var seam3 = Seam.new(
        Vector2(200, 200),
        Vector2(0, 1),  # Same normal as seam1
        PackedVector2Array([Vector2(150, 200), Vector2(250, 200)]),
        2,
        3000,
        "horizontal"
    )

    assert_true(seam1.is_parallel_to(seam3), "Horizontal seams should be parallel")
    assert_false(seam1.is_parallel_to(seam2), "Horizontal and vertical not parallel")


func test_intersects_with():
    var intersection = seam1.intersects_with(seam2)

    assert_ne(intersection, Vector2.INF, "Seams should intersect")
    assert_almost_eq(intersection.x, 100.0, 0.01, "Intersection X correct")
    assert_almost_eq(intersection.y, 100.0, 0.01, "Intersection Y correct")


func test_duplicate_seam():
    var dup = seam1.duplicate_seam()

    assert_not_null(dup, "Duplicate should be created")
    assert_eq(dup.fold_id, seam1.fold_id, "Fold ID should match")
    assert_eq(dup.line_point, seam1.line_point, "Line point should match")
    assert_ne(dup, seam1, "Should be different objects")


func test_to_dict_and_from_dict():
    var dict = seam1.to_dict()

    assert_has(dict, "fold_id", "Dictionary should have fold_id")
    assert_has(dict, "fold_type", "Dictionary should have fold_type")

    var restored = Seam.from_dict(dict)

    assert_eq(restored.fold_id, seam1.fold_id, "Fold ID should be restored")
    assert_eq(restored.fold_type, seam1.fold_type, "Fold type should be restored")
    assert_eq(restored.line_point, seam1.line_point, "Line point should be restored")


func test_invalid_seam_endpoints():
    var invalid_seam = Seam.new()
    invalid_seam.intersection_points = PackedVector2Array([Vector2(0, 0)])  # Only 1 point

    var endpoints = invalid_seam.get_seam_endpoints()
    assert_eq(endpoints.size(), 0, "Invalid seam should return empty endpoints")


func test_seam_metadata():
    seam1.metadata["custom_data"] = "test_value"

    var dup = seam1.duplicate_seam()
    assert_eq(dup.metadata["custom_data"], "test_value", "Metadata should be duplicated")
```

**Acceptance Criteria:**
- ✅ Seam class compiles without errors
- ✅ All 5-8 tests pass
- ✅ Seam can serialize/deserialize correctly
- ✅ Intersection detection works
- ✅ Memory safe (no leaks in duplicate/free cycles)

---

### Task 2: Enhanced Fold History (45-60 min)

**File:** `scripts/systems/FoldSystem.gd`

**Current Implementation (line 300-311):**
```gdscript
func create_fold_record(...) -> Dictionary:
    return {
        "fold_id": next_fold_id,
        "anchor1": anchor1,
        "anchor2": anchor2,
        "removed_cells": removed_cells.duplicate(),  # Only positions!
        "orientation": orientation,
        "timestamp": Time.get_ticks_msec()
    }
```

**Enhanced Implementation:**

Add these helper functions first:

```gdscript
## Serialize a cell to a dictionary for storage
##
## @param cell: Cell to serialize
## @return: Dictionary containing complete cell state
func serialize_cell(cell: Cell) -> Dictionary:
    if not cell:
        return {}

    return {
        "grid_position": {
            "x": cell.grid_position.x,
            "y": cell.grid_position.y
        },
        "geometry": _serialize_geometry(cell.geometry),
        "cell_type": cell.cell_type,
        "is_partial": cell.is_partial,
        "seams": _serialize_seams(cell.seams)
    }


## Serialize multiple cells to array of dictionaries
##
## @param cells: Array of cells to serialize
## @return: Array of cell dictionaries
func serialize_cells(cells: Array) -> Array:
    var result = []
    for cell in cells:
        if cell:
            result.append(serialize_cell(cell))
    return result


## Serialize geometry (PackedVector2Array) to array
func _serialize_geometry(geometry: PackedVector2Array) -> Array:
    var result = []
    for vertex in geometry:
        result.append({"x": vertex.x, "y": vertex.y})
    return result


## Serialize seams array
func _serialize_seams(seams: Array) -> Array:
    var result = []
    for seam in seams:
        if seam is Seam:
            result.append(seam.to_dict())
    return result


## Deserialize a cell from dictionary
##
## @param dict: Dictionary containing cell data
## @return: Restored Cell object
func deserialize_cell(dict: Dictionary) -> Cell:
    if dict.is_empty():
        return null

    var grid_pos = Vector2i(
        dict.grid_position.x,
        dict.grid_position.y
    )

    var cell = Cell.new(grid_pos, Vector2.ZERO, grid_manager.cell_size)
    cell.geometry = _deserialize_geometry(dict.geometry)
    cell.cell_type = dict.cell_type
    cell.is_partial = dict.is_partial

    # Deserialize seams
    if dict.has("seams"):
        for seam_dict in dict.seams:
            var seam = Seam.from_dict(seam_dict)
            cell.seams.append(seam)

    cell.update_visual()
    return cell


## Deserialize geometry array to PackedVector2Array
func _deserialize_geometry(geo_array: Array) -> PackedVector2Array:
    var result = PackedVector2Array()
    for vertex in geo_array:
        result.append(Vector2(vertex.x, vertex.y))
    return result
```

Then update `create_fold_record()`:

```gdscript
## Create an enhanced fold record with complete cell state
##
## This enhanced version stores all data needed for undo and multi-seam tracking
##
## @param anchor1: First anchor position
## @param anchor2: Second anchor position
## @param removed_cells: Array of cells that were removed
## @param modified_cells: Array of cells that were split/modified
## @param shifted_cells: Array of cells that were shifted
## @param shift_vector: Vector that cells were shifted by (if applicable)
## @param seams_created: Array of Seam objects created by this fold
## @param orientation: Fold orientation string
## @return: Dictionary containing complete fold metadata
func create_fold_record_enhanced(
    anchor1: Vector2i,
    anchor2: Vector2i,
    removed_cells: Array,
    modified_cells: Array,
    shifted_cells: Array,
    shift_vector: Vector2i,
    seams_created: Array,
    orientation: String
) -> Dictionary:
    var record = {
        "fold_id": next_fold_id,
        "anchor1": {"x": anchor1.x, "y": anchor1.y},
        "anchor2": {"x": anchor2.x, "y": anchor2.y},

        # Complete cell data for undo
        "removed_cells": serialize_cells(removed_cells),
        "modified_cells": serialize_cells(modified_cells),
        "shifted_cells": {
            "cells": serialize_cells(shifted_cells),
            "shift_vector": {"x": shift_vector.x, "y": shift_vector.y}
        },

        # Seam data
        "seams_created": _serialize_seams(seams_created),

        # Metadata
        "orientation": orientation,
        "timestamp": Time.get_ticks_msec(),
        "player_position_before": {
            "x": player.grid_position.x if player else 0,
            "y": player.grid_position.y if player else 0
        }
    }

    next_fold_id += 1
    return record
```

**Update existing fold functions** to use enhanced record:

Add at the end of each fold function (horizontal, vertical, diagonal):

```gdscript
# Before creating fold record, collect data
var modified_cells_for_record = []  # Cells that were split
var seams_for_record = []  # Seam objects created

# ... existing fold logic ...

# Create enhanced record
var fold_record = create_fold_record_enhanced(
    anchor1, anchor2,
    removed_cells_array,
    modified_cells_for_record,
    shifted_cells_array,
    shift_vector,
    seams_for_record,
    orientation
)
fold_history.append(fold_record)
```

**Test File:** `scripts/tests/test_fold_history.gd`

**Required Tests (8-10 tests):**
```gdscript
extends GutTest

var fold_system: FoldSystem
var grid_manager: GridManager


func before_each():
    grid_manager = GridManager.new()
    grid_manager.grid_size = Vector2i(5, 5)
    grid_manager.cell_size = 64.0
    add_child_autoqfree(grid_manager)
    grid_manager.generate_grid()

    fold_system = FoldSystem.new()
    fold_system.grid_manager = grid_manager
    add_child_autoqfree(fold_system)


func test_serialize_cell():
    var cell = grid_manager.get_cell(Vector2i(2, 2))
    cell.cell_type = 1  # Wall
    cell.is_partial = true

    var serialized = fold_system.serialize_cell(cell)

    assert_has(serialized, "grid_position", "Should have grid_position")
    assert_has(serialized, "geometry", "Should have geometry")
    assert_has(serialized, "cell_type", "Should have cell_type")
    assert_eq(serialized.cell_type, 1, "Cell type should be preserved")
    assert_true(serialized.is_partial, "Partial flag should be preserved")


func test_deserialize_cell():
    var original = grid_manager.get_cell(Vector2i(3, 3))
    original.cell_type = 2  # Water

    var serialized = fold_system.serialize_cell(original)
    var restored = fold_system.deserialize_cell(serialized)

    assert_not_null(restored, "Cell should be restored")
    assert_eq(restored.grid_position, original.grid_position, "Position should match")
    assert_eq(restored.cell_type, original.cell_type, "Type should match")
    assert_eq(restored.geometry.size(), original.geometry.size(), "Geometry size should match")


func test_serialize_cells_array():
    var cells = [
        grid_manager.get_cell(Vector2i(0, 0)),
        grid_manager.get_cell(Vector2i(1, 1)),
        grid_manager.get_cell(Vector2i(2, 2))
    ]

    var serialized = fold_system.serialize_cells(cells)

    assert_eq(serialized.size(), 3, "Should serialize all cells")
    assert_has(serialized[0], "grid_position", "First cell should have position")


func test_enhanced_fold_record_structure():
    var cells = [grid_manager.get_cell(Vector2i(1, 1))]
    var seams = []

    var record = fold_system.create_fold_record_enhanced(
        Vector2i(0, 0),
        Vector2i(4, 0),
        cells,  # removed
        [],     # modified
        [],     # shifted
        Vector2i(0, 0),  # shift_vector
        seams,
        "horizontal"
    )

    assert_has(record, "fold_id", "Should have fold_id")
    assert_has(record, "removed_cells", "Should have removed_cells")
    assert_has(record, "modified_cells", "Should have modified_cells")
    assert_has(record, "shifted_cells", "Should have shifted_cells")
    assert_has(record, "seams_created", "Should have seams_created")
    assert_eq(record.orientation, "horizontal", "Orientation should be set")


func test_seam_serialization_in_record():
    # Create a cell with a seam
    var cell = grid_manager.get_cell(Vector2i(2, 2))
    var seam = Seam.new(
        Vector2(128, 128),
        Vector2(0, 1),
        PackedVector2Array([Vector2(64, 128), Vector2(192, 128)]),
        0,
        1000,
        "test"
    )
    cell.seams.append(seam)

    var serialized = fold_system.serialize_cell(cell)

    assert_has(serialized, "seams", "Should have seams")
    assert_eq(serialized.seams.size(), 1, "Should have 1 seam")
    assert_eq(serialized.seams[0].fold_type, "test", "Seam type should be preserved")


func test_geometry_serialization_preserves_vertices():
    var cell = grid_manager.get_cell(Vector2i(1, 1))
    var original_vertex_count = cell.geometry.size()

    var serialized = fold_system.serialize_cell(cell)
    var restored = fold_system.deserialize_cell(serialized)

    assert_eq(restored.geometry.size(), original_vertex_count, "Vertex count should be preserved")

    # Check first and last vertex match
    assert_almost_eq(restored.geometry[0].x, cell.geometry[0].x, 0.01, "First vertex X matches")
    assert_almost_eq(restored.geometry[0].y, cell.geometry[0].y, 0.01, "First vertex Y matches")


func test_fold_id_increments():
    var record1 = fold_system.create_fold_record_enhanced(
        Vector2i(0, 0), Vector2i(1, 0),
        [], [], [], Vector2i(0, 0), [], "horizontal"
    )

    var record2 = fold_system.create_fold_record_enhanced(
        Vector2i(0, 1), Vector2i(0, 2),
        [], [], [], Vector2i(0, 0), [], "vertical"
    )

    assert_gt(record2.fold_id, record1.fold_id, "Fold ID should increment")


func test_player_position_in_record():
    var player = Player.new()
    player.grid_position = Vector2i(3, 4)
    fold_system.player = player

    var record = fold_system.create_fold_record_enhanced(
        Vector2i(0, 0), Vector2i(1, 0),
        [], [], [], Vector2i(0, 0), [], "horizontal"
    )

    assert_has(record, "player_position_before", "Should have player position")
    assert_eq(record.player_position_before.x, 3, "Player X should be stored")
    assert_eq(record.player_position_before.y, 4, "Player Y should be stored")
```

**Acceptance Criteria:**
- ✅ All serialization/deserialization tests pass
- ✅ Enhanced fold records contain complete state
- ✅ No data loss in serialize → deserialize cycle
- ✅ Existing folds continue to work
- ✅ Fold history size reasonable (no memory bloat)

---

### Task 3: Polygon Union Algorithm (60-90 min)

**File:** `scripts/utils/GeometryCore.gd`

**Implementation:**

```gdscript
## Compute the union of two polygons
##
## Uses Godot's built-in Geometry2D.merge_polygons() which can return
## multiple polygons if the union is non-convex or disjoint.
##
## Strategy:
## 1. Try Geometry2D.merge_polygons()
## 2. If result is single polygon, return it
## 3. If result is multiple polygons, return largest one
## 4. If merge fails, return convex hull as fallback
##
## @param poly1: First polygon (PackedVector2Array)
## @param poly2: Second polygon (PackedVector2Array)
## @return: Union polygon, or largest piece if union is non-convex
static func polygon_union(poly1: PackedVector2Array, poly2: PackedVector2Array) -> PackedVector2Array:
    # Validate inputs
    if poly1.size() < 3 or poly2.size() < 3:
        push_warning("GeometryCore.polygon_union: Invalid polygon (< 3 vertices)")
        return poly1 if poly1.size() >= poly2.size() else poly2

    # Attempt built-in merge
    var merged = Geometry2D.merge_polygons(poly1, poly2)

    if merged.is_empty():
        # Merge failed - fallback to convex hull
        push_warning("GeometryCore.polygon_union: merge_polygons failed, using convex hull")
        return compute_convex_hull_of_polygons([poly1, poly2])

    if merged.size() == 1:
        # Simple case: single merged polygon
        return merged[0]
    else:
        # Complex case: union resulted in multiple polygons
        # This happens when union is non-convex or has holes
        # For now, return the largest polygon
        push_warning("GeometryCore.polygon_union: Union resulted in %d polygons, returning largest" % merged.size())
        return get_largest_polygon(merged)


## Get the largest polygon from an array of polygons
##
## @param polygons: Array of PackedVector2Array
## @return: The polygon with largest area
static func get_largest_polygon(polygons: Array) -> PackedVector2Array:
    if polygons.is_empty():
        return PackedVector2Array()

    var largest = polygons[0]
    var largest_area = polygon_area(largest)

    for i in range(1, polygons.size()):
        var area = polygon_area(polygons[i])
        if area > largest_area:
            largest = polygons[i]
            largest_area = area

    return largest


## Compute convex hull of multiple polygons
##
## Combines all vertices from input polygons and computes their convex hull.
## This is a fallback when polygon_union fails.
##
## @param polygons: Array of PackedVector2Array
## @return: Convex hull as PackedVector2Array
static func compute_convex_hull_of_polygons(polygons: Array) -> PackedVector2Array:
    # Collect all vertices
    var all_vertices = PackedVector2Array()
    for poly in polygons:
        for vertex in poly:
            all_vertices.append(vertex)

    # Compute convex hull using Geometry2D
    var hull = Geometry2D.convex_hull(all_vertices)

    if hull.size() < 3:
        # Hull computation failed - return first polygon as fallback
        push_error("GeometryCore: Convex hull computation failed")
        return polygons[0] if not polygons.is_empty() else PackedVector2Array()

    return hull


## Merge a cell geometry with another geometry (for cell merging)
##
## This is a convenience wrapper around polygon_union specifically
## for merging cell geometries during folds.
##
## @param existing_geometry: Current cell geometry
## @param incoming_geometry: Geometry to merge in
## @return: Merged geometry
static func merge_cell_geometries(
    existing_geometry: PackedVector2Array,
    incoming_geometry: PackedVector2Array
) -> PackedVector2Array:
    return polygon_union(existing_geometry, incoming_geometry)
```

**Test File:** `scripts/tests/test_polygon_union.gd`

**Required Tests (10-15 tests):**
```gdscript
extends GutTest

func test_simple_overlapping_squares():
    # Two overlapping squares should merge into a larger rectangle
    var square1 = PackedVector2Array([
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ])

    var square2 = PackedVector2Array([
        Vector2(50, 0), Vector2(150, 0),
        Vector2(150, 100), Vector2(50, 100)
    ])

    var union = GeometryCore.polygon_union(square1, square2)

    assert_gt(union.size(), 0, "Union should produce vertices")
    var union_area = GeometryCore.polygon_area(union)

    # Union area should be less than sum (due to overlap) but more than either
    var area1 = GeometryCore.polygon_area(square1)
    var area2 = GeometryCore.polygon_area(square2)

    assert_gt(union_area, area1, "Union area should be > square1")
    assert_gt(union_area, area2, "Union area should be > square2")
    assert_lt(union_area, area1 + area2, "Union area should be < sum (overlap)")


func test_adjacent_squares():
    # Two adjacent squares should merge into rectangle
    var square1 = PackedVector2Array([
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ])

    var square2 = PackedVector2Array([
        Vector2(100, 0), Vector2(200, 0),
        Vector2(200, 100), Vector2(100, 100)
    ])

    var union = GeometryCore.polygon_union(square1, square2)

    assert_gt(union.size(), 0, "Union should produce vertices")

    # Should produce rectangle with area = sum of both squares
    var union_area = GeometryCore.polygon_area(union)
    var expected_area = 10000 + 10000  # Two 100x100 squares

    assert_almost_eq(union_area, expected_area, 100, "Union area should equal sum for adjacent")


func test_disjoint_squares():
    # Two separate squares - union should return largest or convex hull
    var square1 = PackedVector2Array([
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ])

    var square2 = PackedVector2Array([
        Vector2(200, 200), Vector2(300, 200),
        Vector2(300, 300), Vector2(200, 300)
    ])

    var union = GeometryCore.polygon_union(square1, square2)

    assert_gt(union.size(), 0, "Union should produce vertices even for disjoint")


func test_triangle_and_square():
    var triangle = PackedVector2Array([
        Vector2(50, 0), Vector2(100, 100), Vector2(0, 100)
    ])

    var square = PackedVector2Array([
        Vector2(25, 50), Vector2(75, 50),
        Vector2(75, 150), Vector2(25, 150)
    ])

    var union = GeometryCore.polygon_union(triangle, square)

    assert_gt(union.size(), 2, "Union should have vertices")

    # Area should be at least as large as either input
    var tri_area = GeometryCore.polygon_area(triangle)
    var sq_area = GeometryCore.polygon_area(square)
    var union_area = GeometryCore.polygon_area(union)

    assert_ge(union_area, tri_area, "Union >= triangle area")
    assert_ge(union_area, sq_area, "Union >= square area")


func test_invalid_polygon_handling():
    var valid = PackedVector2Array([
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ])

    var invalid = PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])  # Only 2 points

    var union = GeometryCore.polygon_union(valid, invalid)

    # Should return the valid polygon
    assert_gt(union.size(), 2, "Should return valid polygon")


func test_identical_polygons():
    var square = PackedVector2Array([
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 100), Vector2(0, 100)
    ])

    var union = GeometryCore.polygon_union(square, square)

    # Union of identical polygons should be the original
    var original_area = GeometryCore.polygon_area(square)
    var union_area = GeometryCore.polygon_area(union)

    assert_almost_eq(union_area, original_area, 1, "Identical polygons union = original")


func test_get_largest_polygon():
    var small = PackedVector2Array([
        Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)
    ])

    var large = PackedVector2Array([
        Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)
    ])

    var largest = GeometryCore.get_largest_polygon([small, large])

    var largest_area = GeometryCore.polygon_area(largest)
    var expected_area = GeometryCore.polygon_area(large)

    assert_almost_eq(largest_area, expected_area, 1, "Should return largest polygon")


func test_convex_hull_fallback():
    var poly1 = PackedVector2Array([
        Vector2(0, 0), Vector2(50, 0), Vector2(50, 50), Vector2(0, 50)
    ])

    var poly2 = PackedVector2Array([
        Vector2(100, 100), Vector2(150, 100), Vector2(150, 150), Vector2(100, 150)
    ])

    var hull = GeometryCore.compute_convex_hull_of_polygons([poly1, poly2])

    assert_gt(hull.size(), 2, "Convex hull should have vertices")


func test_merge_cell_geometries_wrapper():
    var geom1 = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
    ])

    var geom2 = PackedVector2Array([
        Vector2(32, 32), Vector2(96, 32), Vector2(96, 96), Vector2(32, 96)
    ])

    var merged = GeometryCore.merge_cell_geometries(geom1, geom2)

    assert_gt(merged.size(), 0, "Merged geometry should have vertices")


func test_complex_concave_union():
    # L-shaped polygons
    var L1 = PackedVector2Array([
        Vector2(0, 0), Vector2(100, 0),
        Vector2(100, 50), Vector2(50, 50),
        Vector2(50, 100), Vector2(0, 100)
    ])

    var L2 = PackedVector2Array([
        Vector2(50, 50), Vector2(150, 50),
        Vector2(150, 150), Vector2(100, 150),
        Vector2(100, 100), Vector2(50, 100)
    ])

    var union = GeometryCore.polygon_union(L1, L2)

    # Should produce some polygon (might be convex hull)
    assert_gt(union.size(), 2, "Complex union should produce polygon")
```

**Acceptance Criteria:**
- ✅ All 10-15 tests pass
- ✅ Simple overlapping cases work correctly
- ✅ Adjacent polygons merge properly
- ✅ Fallback to convex hull when needed
- ✅ No crashes on invalid input
- ✅ Area calculations are reasonable

---

## Core Implementation (4-6 hours)

After completing the 3 prerequisites, proceed with core Phase 5 work.

### Task 4: Update Cell Merging to Use Polygon Union (30-45 min)

**File:** `scripts/systems/FoldSystem.gd`

**Current implementation (lines 1610-1627):**
```gdscript
func _merge_cells_simple(existing: Cell, incoming: Cell, pos: Vector2i):
    # Mark both as partial
    existing.is_partial = true
    incoming.is_partial = true

    # TODO: Combine geometries (polygon union)
    # For now, keep existing and free incoming

    existing.update_visual()
    incoming.queue_free()
```

**Enhanced implementation:**
```gdscript
## Merge two cells at the same position using polygon union
##
## This is the enhanced version that properly combines geometries.
##
## @param existing: Cell already at the position
## @param incoming: Cell being moved to this position
## @param pos: Grid position where merge occurs
func _merge_cells_with_union(existing: Cell, incoming: Cell, pos: Vector2i):
    # Mark both as partial
    existing.is_partial = true
    incoming.is_partial = true

    # 1. Combine geometries using polygon union
    var merged_geometry = GeometryCore.polygon_union(
        existing.geometry,
        incoming.geometry
    )

    existing.geometry = merged_geometry

    # 2. Merge seam data
    for seam in incoming.seams:
        # Check if seam already exists (by fold_id)
        var seam_exists = false
        for existing_seam in existing.seams:
            if existing_seam.fold_id == seam.fold_id:
                seam_exists = true
                break

        if not seam_exists:
            existing.seams.append(seam.duplicate_seam())

    # 3. Handle cell type conflicts
    if existing.cell_type != incoming.cell_type:
        existing.cell_type = _resolve_cell_type_conflict(
            existing.cell_type,
            incoming.cell_type
        )

    # 4. Update visual with merge indication
    existing.update_visual()

    # 5. Free the incoming cell
    incoming.queue_free()


## Resolve conflict when two cells with different types merge
##
## Priority order: Goal > Wall > Water > Empty
##
## @param type1: First cell type
## @param type2: Second cell type
## @return: Winning cell type
func _resolve_cell_type_conflict(type1: int, type2: int) -> int:
    # Cell type constants (from Cell.gd):
    # 0 = empty, 1 = wall, 2 = water, 3 = goal

    # Goal takes highest priority
    if type1 == 3 or type2 == 3:
        return 3

    # Wall takes second priority
    if type1 == 1 or type2 == 1:
        return 1

    # Water takes third priority
    if type1 == 2 or type2 == 2:
        return 2

    # Both empty
    return 0
```

**Update diagonal fold** to use new merge function:

Change line 1578 from:
```gdscript
_merge_cells_simple(existing, cell, new_pos)
```

To:
```gdscript
_merge_cells_with_union(existing, cell, new_pos)
```

**Test additions to existing test file:**

Add to `scripts/tests/test_fold_system.gd`:

```gdscript
func test_merge_cells_combines_geometry():
    grid_manager.generate_grid()

    # Create two cells with different geometries
    var cell1 = grid_manager.get_cell(Vector2i(2, 2))
    var cell2 = grid_manager.get_cell(Vector2i(2, 3))

    var original_area1 = GeometryCore.polygon_area(cell1.geometry)
    var original_area2 = GeometryCore.polygon_area(cell2.geometry)

    # Merge cell2 into cell1
    fold_system._merge_cells_with_union(cell1, cell2, Vector2i(2, 2))

    # Check that geometry was combined
    var merged_area = GeometryCore.polygon_area(cell1.geometry)

    # Merged area should be greater than either original
    # (might not be exact sum due to overlap)
    assert_gt(merged_area, original_area1, "Merged area > original cell1")


func test_merge_cells_combines_seams():
    grid_manager.generate_grid()

    var cell1 = grid_manager.get_cell(Vector2i(1, 1))
    var cell2 = grid_manager.get_cell(Vector2i(1, 2))

    # Add different seams to each cell
    var seam1 = Seam.new(Vector2(64, 64), Vector2(1, 0), PackedVector2Array(), 0, 1000, "test")
    var seam2 = Seam.new(Vector2(64, 128), Vector2(0, 1), PackedVector2Array(), 1, 2000, "test")

    cell1.seams.append(seam1)
    cell2.seams.append(seam2)

    # Merge
    fold_system._merge_cells_with_union(cell1, cell2, Vector2i(1, 1))

    # Check that both seams are present
    assert_eq(cell1.seams.size(), 2, "Merged cell should have both seams")


func test_cell_type_conflict_resolution():
    # Goal beats wall
    assert_eq(fold_system._resolve_cell_type_conflict(3, 1), 3, "Goal beats wall")

    # Wall beats water
    assert_eq(fold_system._resolve_cell_type_conflict(1, 2), 1, "Wall beats water")

    # Water beats empty
    assert_eq(fold_system._resolve_cell_type_conflict(2, 0), 2, "Water beats empty")

    # Goal beats everything
    assert_eq(fold_system._resolve_cell_type_conflict(3, 0), 3, "Goal beats empty")
    assert_eq(fold_system._resolve_cell_type_conflict(3, 2), 3, "Goal beats water")
```

**Acceptance Criteria:**
- ✅ Cells merge with proper geometry union
- ✅ Seams from both cells are combined
- ✅ Cell type conflicts resolved correctly
- ✅ No memory leaks
- ✅ All new tests pass

---

### Task 5: Implement Seam Tracking in Fold Operations (45-60 min)

Update all fold functions to create and store Seam objects.

**File:** `scripts/systems/FoldSystem.gd`

**For horizontal folds:**

Add after seam line creation (around line 600):

```gdscript
# Create Seam objects for cells affected by this fold
var seams_created = []
var seam = Seam.new(
    Vector2(left_anchor.x * cell_size + cell_size / 2, 0),  # line_point (LOCAL)
    Vector2(0, 1),  # normal (perpendicular to horizontal line)
    PackedVector2Array(),  # intersection_points (will be set per cell)
    fold_history.size(),  # fold_id
    Time.get_ticks_msec(),  # timestamp
    "horizontal"
)

# For each cell that was split by line1 or on the seam line
for cell in cells_on_seam_line:
    # Calculate where seam intersects this cell's boundary
    var cell_bounds = get_cell_boundary_segments(cell)
    var intersections = calculate_seam_intersections(seam, cell_bounds)

    var cell_seam = seam.duplicate_seam()
    cell_seam.intersection_points = intersections

    cell.seams.append(cell_seam)
    seams_created.append(cell_seam)
```

**Helper function to add:**

```gdscript
## Get boundary segments of a cell for intersection testing
##
## @param cell: Cell to get boundaries for
## @return: Array of line segments (each is [start, end])
func get_cell_boundary_segments(cell: Cell) -> Array:
    var segments = []
    var geom = cell.geometry

    for i in range(geom.size()):
        var start = geom[i]
        var end = geom[(i + 1) % geom.size()]
        segments.append([start, end])

    return segments


## Calculate where a seam intersects a cell's boundary
##
## @param seam: Seam to test
## @param boundary_segments: Array of [start, end] segments
## @return: PackedVector2Array of intersection points
func calculate_seam_intersections(seam: Seam, boundary_segments: Array) -> PackedVector2Array:
    var intersections = PackedVector2Array()

    for segment in boundary_segments:
        var start = segment[0]
        var end = segment[1]

        # Check if seam line intersects this segment
        var intersection = GeometryCore.segment_line_intersection(
            start, end,
            seam.line_point, seam.line_point + seam.line_normal.rotated(PI/2) * 1000
        )

        if intersection != Vector2.INF:
            intersections.append(intersection)

    return intersections
```

**Acceptance Criteria:**
- ✅ Seams created for all fold types
- ✅ Intersection points calculated correctly
- ✅ Seams stored in affected cells
- ✅ Seam fold_id matches fold history

---

### Task 6: Implement Multi-Seam Detection (30-45 min)

Add logic to detect when a cell has multiple seams.

**File:** `scripts/core/Cell.gd`

```gdscript
## Check if this cell has multiple seams
##
## @return: true if cell has 2 or more seams
func has_multiple_seams() -> bool:
    return seams.size() >= 2


## Get all seam intersection points within this cell
##
## Returns points where seams intersect each other (not boundary)
##
## @return: Array of Vector2 intersection points
func get_seam_intersections() -> Array[Vector2]:
    var intersections: Array[Vector2] = []

    if seams.size() < 2:
        return intersections

    # Check each pair of seams
    for i in range(seams.size()):
        for j in range(i + 1, seams.size()):
            var intersection = seams[i].intersects_with(seams[j])
            if intersection != Vector2.INF:
                # Verify intersection is inside cell geometry
                if Geometry2D.is_point_in_polygon(intersection, geometry):
                    intersections.append(intersection)

    return intersections


## Check if this cell needs tessellation
##
## A cell needs tessellation if it has multiple seams that intersect
##
## @return: true if tessellation is needed
func needs_tessellation() -> bool:
    if not has_multiple_seams():
        return false

    # Check if any seams intersect
    var intersections = get_seam_intersections()
    return not intersections.is_empty()
```

**Test File:** `scripts/tests/test_multi_seam.gd`

```gdscript
extends GutTest

var cell: Cell


func before_each():
    cell = Cell.new(Vector2i(2, 2), Vector2(128, 128), 64.0)
    cell.geometry = PackedVector2Array([
        Vector2(96, 96), Vector2(160, 96),
        Vector2(160, 160), Vector2(96, 160)
    ])


func test_has_multiple_seams_false():
    assert_false(cell.has_multiple_seams(), "New cell should not have multiple seams")


func test_has_multiple_seams_true():
    cell.seams.append(Seam.new())
    cell.seams.append(Seam.new())

    assert_true(cell.has_multiple_seams(), "Cell with 2 seams should return true")


func test_get_seam_intersections_perpendicular():
    # Horizontal seam
    var seam1 = Seam.new(
        Vector2(128, 128),
        Vector2(0, 1),
        PackedVector2Array([Vector2(96, 128), Vector2(160, 128)]),
        0, 1000, "horizontal"
    )

    # Vertical seam
    var seam2 = Seam.new(
        Vector2(128, 128),
        Vector2(1, 0),
        PackedVector2Array([Vector2(128, 96), Vector2(128, 160)]),
        1, 2000, "vertical"
    )

    cell.seams.append(seam1)
    cell.seams.append(seam2)

    var intersections = cell.get_seam_intersections()

    assert_eq(intersections.size(), 1, "Should find 1 intersection")
    assert_almost_eq(intersections[0].x, 128.0, 0.1, "Intersection X at center")
    assert_almost_eq(intersections[0].y, 128.0, 0.1, "Intersection Y at center")


func test_needs_tessellation():
    # Add intersecting seams
    var seam1 = Seam.new(
        Vector2(128, 128), Vector2(0, 1),
        PackedVector2Array([Vector2(96, 128), Vector2(160, 128)]),
        0, 1000, "horizontal"
    )

    var seam2 = Seam.new(
        Vector2(128, 128), Vector2(1, 0),
        PackedVector2Array([Vector2(128, 96), Vector2(128, 160)]),
        1, 2000, "vertical"
    )

    cell.seams.append(seam1)
    cell.seams.append(seam2)

    assert_true(cell.needs_tessellation(), "Cell with intersecting seams needs tessellation")
```

**Acceptance Criteria:**
- ✅ Can detect multiple seams in cell
- ✅ Can find seam intersection points
- ✅ Correctly identifies need for tessellation
- ✅ All tests pass

---

### Task 7: Implement Tessellation Algorithm (2-3 hours)

This is the core of Phase 5.

**File:** `scripts/core/Cell.gd`

```gdscript
## Tessellate this cell based on its seams
##
## Subdivides the cell geometry into smaller convex polygons,
## each bounded by the seam lines.
##
## Returns an array of new Cell objects, each representing one piece.
## The original cell is NOT modified.
##
## Algorithm:
## 1. Start with current cell geometry
## 2. For each seam, split all current pieces
## 3. Track which seams bound each piece
## 4. Create new Cell objects for each piece
##
## @return: Array of new Cell objects (subdivided pieces)
func tessellate() -> Array[Cell]:
    if not needs_tessellation():
        # No tessellation needed - return self as single piece
        return [self]

    # Start with current geometry as first piece
    var pieces = [geometry]
    var pieces_seams = [[]]  # Track which seams bound each piece

    # Split by each seam sequentially
    for seam in seams:
        var new_pieces = []
        var new_pieces_seams = []

        for i in range(pieces.size()):
            var piece = pieces[i]
            var piece_seam_list = pieces_seams[i]

            # Try to split this piece by current seam
            var split_result = GeometryCore.split_polygon_by_line(
                piece, seam.line_point, seam.line_normal
            )

            if split_result.intersections.size() > 0:
                # Piece was split - add both halves
                if split_result.left.size() >= 3:
                    new_pieces.append(split_result.left)
                    var left_seams = piece_seam_list.duplicate()
                    left_seams.append(seam)
                    new_pieces_seams.append(left_seams)

                if split_result.right.size() >= 3:
                    new_pieces.append(split_result.right)
                    var right_seams = piece_seam_list.duplicate()
                    right_seams.append(seam)
                    new_pieces_seams.append(right_seams)
            else:
                # Piece not split - keep as is
                new_pieces.append(piece)
                new_pieces_seams.append(piece_seam_list)

        pieces = new_pieces
        pieces_seams = new_pieces_seams

    # Create Cell objects for each piece
    var result_cells: Array[Cell] = []

    for i in range(pieces.size()):
        var piece_cell = Cell.new(grid_position, Vector2.ZERO, 0)
        piece_cell.geometry = pieces[i]
        piece_cell.cell_type = cell_type
        piece_cell.is_partial = true

        # Add seams that bound this piece
        for seam in pieces_seams[i]:
            piece_cell.seams.append(seam.duplicate_seam())

        piece_cell.update_visual()
        result_cells.append(piece_cell)

    return result_cells


## Visualize seams within this cell
##
## Creates Line2D nodes for each seam and adds them as children.
## Call this after cell has been tessellated or when seams change.
func visualize_seams():
    # Remove existing seam visuals
    for child in get_children():
        if child is Line2D and child.name.begins_with("Seam_"):
            child.queue_free()

    # Create new seam visuals
    for i in range(seams.size()):
        var seam = seams[i]
        var endpoints = seam.get_seam_endpoints()

        if endpoints.is_empty():
            continue

        var line = Line2D.new()
        line.name = "Seam_%d" % i
        line.add_point(endpoints[0])
        line.add_point(endpoints[1])
        line.width = 2.0
        line.default_color = Color.RED.lerp(Color.BLUE, float(i) / max(seams.size(), 1))
        line.z_index = 10  # Draw on top

        add_child(line)
```

**Test File:** `scripts/tests/test_tessellation.gd`

```gdscript
extends GutTest

var cell: Cell


func before_each():
    cell = Cell.new(Vector2i(2, 2), Vector2(128, 128), 64.0)
    cell.geometry = PackedVector2Array([
        Vector2(96, 96), Vector2(160, 96),
        Vector2(160, 160), Vector2(96, 160)
    ])


func test_tessellate_no_seams():
    var pieces = cell.tessellate()

    assert_eq(pieces.size(), 1, "Cell with no seams should return 1 piece")
    assert_eq(pieces[0], cell, "Should return self")


func test_tessellate_one_seam():
    # Add one horizontal seam
    var seam = Seam.new(
        Vector2(128, 128), Vector2(0, 1),
        PackedVector2Array([Vector2(96, 128), Vector2(160, 128)]),
        0, 1000, "horizontal"
    )
    cell.seams.append(seam)

    var pieces = cell.tessellate()

    # One seam should not trigger tessellation (needs_tessellation returns false for 1 seam)
    # But if we force tessellation, it should split
    assert_gt(pieces.size(), 0, "Should produce pieces")


func test_tessellate_two_perpendicular_seams():
    # Add horizontal seam
    var seam1 = Seam.new(
        Vector2(128, 128), Vector2(0, 1),
        PackedVector2Array([Vector2(96, 128), Vector2(160, 128)]),
        0, 1000, "horizontal"
    )

    # Add vertical seam
    var seam2 = Seam.new(
        Vector2(128, 128), Vector2(1, 0),
        PackedVector2Array([Vector2(128, 96), Vector2(128, 160)]),
        1, 2000, "vertical"
    )

    cell.seams.append(seam1)
    cell.seams.append(seam2)

    var pieces = cell.tessellate()

    # Two perpendicular seams should create 4 pieces
    assert_eq(pieces.size(), 4, "Two perpendicular seams should create 4 quadrants")

    # Each piece should have both seams
    for piece in pieces:
        assert_true(piece.is_partial, "Each piece should be marked partial")
        assert_eq(piece.cell_type, cell.cell_type, "Cell type should be preserved")


func test_tessellate_preserves_total_area():
    var seam1 = Seam.new(
        Vector2(128, 128), Vector2(0, 1),
        PackedVector2Array([Vector2(96, 128), Vector2(160, 128)]),
        0, 1000, "horizontal"
    )

    var seam2 = Seam.new(
        Vector2(128, 128), Vector2(1, 0),
        PackedVector2Array([Vector2(128, 96), Vector2(128, 160)]),
        1, 2000, "vertical"
    )

    cell.seams.append(seam1)
    cell.seams.append(seam2)

    var original_area = GeometryCore.polygon_area(cell.geometry)
    var pieces = cell.tessellate()

    var total_pieces_area = 0.0
    for piece in pieces:
        total_pieces_area += GeometryCore.polygon_area(piece.geometry)

    assert_almost_eq(total_pieces_area, original_area, 1.0, "Total area should be preserved")


func test_tessellate_three_seams():
    # Create 3 seams that subdivide cell
    var seams_to_add = [
        Seam.new(Vector2(128, 128), Vector2(0, 1),
            PackedVector2Array([Vector2(96, 128), Vector2(160, 128)]),
            0, 1000, "horizontal"),
        Seam.new(Vector2(128, 128), Vector2(1, 0),
            PackedVector2Array([Vector2(128, 96), Vector2(128, 160)]),
            1, 2000, "vertical"),
        Seam.new(Vector2(128, 110), Vector2(0, 1),
            PackedVector2Array([Vector2(96, 110), Vector2(160, 110)]),
            2, 3000, "horizontal")
    ]

    for seam in seams_to_add:
        cell.seams.append(seam)

    var pieces = cell.tessellate()

    # Should create multiple pieces (exact count depends on seam positions)
    assert_gt(pieces.size(), 4, "Three seams should create multiple pieces")


func test_visualize_seams():
    var seam = Seam.new(
        Vector2(128, 128), Vector2(0, 1),
        PackedVector2Array([Vector2(96, 128), Vector2(160, 128)]),
        0, 1000, "horizontal"
    )
    cell.seams.append(seam)

    cell.visualize_seams()

    # Check that Line2D was created
    var found_line = false
    for child in cell.get_children():
        if child is Line2D and child.name.begins_with("Seam_"):
            found_line = true
            break

    assert_true(found_line, "Seam visualization should create Line2D")
```

**Acceptance Criteria:**
- ✅ Tessellation correctly subdivides cells
- ✅ All pieces are valid convex polygons
- ✅ Total area is conserved
- ✅ Seam data preserved in pieces
- ✅ Cell type preserved
- ✅ All tests pass (20-25 tests total)

---

### Task 8: Integration and Visual Polish (1-2 hours)

**Update GridManager** to handle tessellated cells:

```gdscript
## Replace a cell with its tessellated pieces
##
## @param cell: Cell to tessellate and replace
func tessellate_cell(cell: Cell):
    if not cell.needs_tessellation():
        return

    var pieces = cell.tessellate()

    if pieces.size() <= 1:
        return  # No actual tessellation occurred

    # Remove original cell
    cells.erase(cell.grid_position)

    # Add all pieces at the same grid position
    # (They'll have the same grid_position but different geometries)
    # Note: This changes our cell storage model - need sub-cell indexing

    # For Phase 5, store pieces in a separate dictionary
    if not has_meta("tessellated_cells"):
        set_meta("tessellated_cells", {})

    var tess_cells = get_meta("tessellated_cells")
    if not tess_cells.has(cell.grid_position):
        tess_cells[cell.grid_position] = []

    for piece in pieces:
        tess_cells[cell.grid_position].append(piece)
        add_child(piece)

    # Free original
    cell.queue_free()
```

**Visual updates:**

Add to `scripts/core/Cell.gd`:

```gdscript
## Update visual to show multi-seam status
func update_visual_with_seams():
    update_visual()

    if has_multiple_seams():
        # Add visual indicator for multi-seam cells
        modulate = Color(1.0, 0.9, 0.9)  # Slight red tint

    # Visualize seams
    visualize_seams()
```

**Acceptance Criteria:**
- ✅ Tessellated cells render correctly
- ✅ Seam lines visible
- ✅ Multi-seam cells have visual indicator
- ✅ Performance acceptable (<100ms per fold)
- ✅ No visual glitches

---

## Testing Summary

### Total New Tests: 45-65

| Component | Tests | Priority |
|-----------|-------|----------|
| Seam class | 5-8 | P0 |
| Enhanced fold history | 8-10 | P0 |
| Polygon union | 10-15 | P0 |
| Multi-seam detection | 5-8 | P1 |
| Tessellation | 20-25 | P1 |
| Integration | 5-10 | P2 |

### Test Execution

Run tests incrementally after each task:

```bash
# After Task 1 (Seam class)
./run_tests.sh seam

# After Task 2 (Fold history)
./run_tests.sh fold_history

# After Task 3 (Polygon union)
./run_tests.sh polygon_union

# After Task 7 (Tessellation)
./run_tests.sh tessellation

# Final check
./run_tests.sh
```

**Target:** All 406-428 tests passing (361 current + 45-65 new)

---

## Risk Assessment

### High Risk Areas
1. **Tessellation complexity** - Many edge cases
   - Mitigation: Extensive testing, start with simple cases
2. **Performance** - Recursive subdivision could be slow
   - Mitigation: Limit max seam count per cell, optimize algorithms
3. **Memory usage** - Many small cells could increase memory
   - Mitigation: Monitor with tests, implement cell pooling if needed

### Medium Risk Areas
1. **Polygon union edge cases** - Godot API might fail on some inputs
   - Mitigation: Fallback to convex hull
2. **Seam intersection precision** - Floating point errors
   - Mitigation: Use EPSILON consistently

### Low Risk Areas
1. **Seam class** - Straightforward data structure
2. **Enhanced history** - Just serialization
3. **Visual updates** - Polish, not critical

---

## Performance Targets

| Operation | Target | Critical |
|-----------|--------|----------|
| Tessellate cell (2 seams) | < 5ms | < 20ms |
| Tessellate cell (3 seams) | < 10ms | < 50ms |
| Polygon union | < 2ms | < 10ms |
| Full fold with tessellation | < 150ms | < 500ms |
| Memory per tessellated cell | < 5KB | < 20KB |

---

## Completion Checklist

### Prerequisites
- [ ] Seam class implemented and tested (5-8 tests passing)
- [ ] Enhanced fold history implemented and tested (8-10 tests passing)
- [ ] Polygon union implemented and tested (10-15 tests passing)
- [ ] All existing 361 tests still pass

### Core Implementation
- [ ] Cell merging uses polygon union
- [ ] Seam tracking in fold operations
- [ ] Multi-seam detection working
- [ ] Tessellation algorithm implemented and tested (20-25 tests)
- [ ] Integration with GridManager complete
- [ ] Visual representation of seams working

### Quality Gates
- [ ] All 406-428 tests passing (100%)
- [ ] No memory leaks detected
- [ ] Performance targets met
- [ ] Code reviewed for clarity and maintainability
- [ ] Documentation updated

### Final Steps
- [ ] Update STATUS.md with new test counts
- [ ] Move phase_5.md to docs/phases/completed/
- [ ] Commit all changes with clear messages
- [ ] Create PR if applicable

---

## Next Steps After Phase 5

With Phase 5 complete, you can proceed to:

1. **Phase 6: Undo System** - Enhanced fold history is ready
2. **Phase 8: Cell Types & Visuals** - Tessellation enables complex visuals
3. **Phase 11: Testing & Validation** - Comprehensive edge case testing

---

## References

- [CELL_MERGE_ANALYSIS.md](../../CELL_MERGE_ANALYSIS.md) - Current merge implementation analysis
- [PHASE_5_6_ANALYSIS.md](../../PHASE_5_6_ANALYSIS.md) - Readiness analysis for both phases
- [docs/ARCHITECTURE.md](../ARCHITECTURE.md) - Design decisions
- [docs/REFERENCE.md](../REFERENCE.md) - API reference
- [STATUS.md](../../STATUS.md) - Current project status

---

**Phase 5 Total Estimated Time:** 6-9 hours
- Prerequisites: 2-3 hours
- Core implementation: 4-6 hours
- Buffer for debugging: +20%

**Recommended Approach:** Complete prerequisites first (1 session), then tackle core work in 2-3 focused sessions.

---

**End of Phase 5 Implementation Specification**
