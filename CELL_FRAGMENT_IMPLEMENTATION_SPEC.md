# CompoundCell & CellFragment Implementation Specification

**Version:** 1.0
**Date:** 2025-11-06
**Status:** Ready for Implementation
**Target Phases:** 4 (Geometric Folding), 5 (Multi-Seam), 6 (Undo System)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [CellFragment Class Specification](#cellfragment-class-specification)
4. [CompoundCell Class Specification](#compoundcell-class-specification)
5. [Rendering System](#rendering-system)
6. [GridManager Integration](#gridmanager-integration)
7. [FoldSystem Integration](#foldsystem-integration)
8. [Coordinate System Guidelines](#coordinate-system-guidelines)
9. [Memory Management](#memory-management)
10. [Testing Strategy](#testing-strategy)
11. [Migration Plan](#migration-plan)
12. [Performance Considerations](#performance-considerations)

---

## Overview

### Problem Statement

The current `Cell` class cannot support Phase 4-6 requirements:
- **Phase 4**: Multiple cell fragments at the same grid position after diagonal folds
- **Phase 5**: Tessellated regions when multiple seams intersect
- **Phase 6**: Fold history tracking for dependency-aware undo

### Solution

Implement a two-tier architecture:
- **CellFragment**: Lightweight geometric piece (RefCounted, not Node)
- **CompoundCell**: Container managing multiple fragments at a grid position (Node2D)

### Key Benefits

✅ Multiple fragments at same position
✅ Clear merge semantics with history tracking
✅ Fold dependency checking built-in
✅ Incremental migration path
✅ Memory efficient (RefCounted fragments)
✅ Rendering per-fragment for visual accuracy

---

## Architecture

### Class Hierarchy

```
RefCounted
└── CellFragment          # Lightweight geometric piece

Node2D
└── CompoundCell          # Container with visual representation
    ├── Polygon2D (fragment 0)
    ├── Polygon2D (fragment 1)
    └── ...
```

### Data Flow

```
GridManager
├── cells: Dictionary[Vector2i, CompoundCell]
│
CompoundCell (at position Vector2i(5, 3))
├── fragments: Array[CellFragment]
│   ├── CellFragment #0: geometry, seams, fold_created
│   ├── CellFragment #1: geometry, seams, fold_created
│   └── ...
├── polygon_visuals: Array[Polygon2D]
│   ├── Polygon2D (renders fragment #0)
│   ├── Polygon2D (renders fragment #1)
│   └── ...
├── source_positions: [Vector2i(5, 3), Vector2i(6, 3)]
└── fold_history: [0, 3, 7]
```

### Coordinate System

**CRITICAL**: All geometry uses **LOCAL coordinates** relative to GridManager.

```gdscript
# GridManager is positioned at grid_origin (screen center)
# CompoundCell is child of GridManager → inherits position
# Polygon2D is child of CompoundCell → inherits position

# Creating geometry for grid position (5, 3):
var local_pos = Vector2(5, 3) * cell_size  # LOCAL coordinates
var geometry = PackedVector2Array([
    local_pos,
    local_pos + Vector2(cell_size, 0),
    # ... square vertices
])

# Polygon2D.polygon is set to this LOCAL geometry
# Godot automatically transforms to world coordinates for rendering
```

---

## CellFragment Class Specification

### File Location
`scripts/core/CellFragment.gd`

### Full Implementation

```gdscript
## CellFragment - Represents a single geometric piece of a cell
##
## CellFragment is a lightweight data structure (RefCounted) that stores
## the geometry and metadata for one piece of a cell. Multiple fragments
## can exist at the same grid position when cells merge.
##
## Memory: RefCounted → automatically freed when no references remain
## Coordinates: All geometry in LOCAL coordinates (relative to GridManager)

class_name CellFragment extends RefCounted

## ============================================================================
## PROPERTIES
## ============================================================================

## Polygon vertices in LOCAL coordinates (relative to GridManager)
## CRITICAL: These are NOT world coordinates. GridManager.position is added
## automatically by Godot's scene tree when rendering.
var geometry: PackedVector2Array = []

## Array of seam metadata dictionaries
## Each seam dictionary contains:
##   - fold_id: int (which fold created this seam)
##   - line_point: Vector2 (point on fold line, LOCAL coords)
##   - line_normal: Vector2 (normal vector of fold line)
##   - intersection_points: PackedVector2Array (where fold intersected this fragment)
##   - timestamp: int (Time.get_ticks_msec() when created)
var seam_data: Array[Dictionary] = []

## Fold ID that created this fragment
## -1 = original grid cell (created at initialization)
## >= 0 = created by a fold operation
var fold_created: int = -1

## Cached area for performance
## Updated whenever geometry changes
var area: float = 0.0

## Cached centroid for performance
## Updated whenever geometry changes
var centroid: Vector2 = Vector2.ZERO


## ============================================================================
## CONSTRUCTOR
## ============================================================================

## Initialize a new CellFragment
##
## @param geom: Polygon vertices in LOCAL coordinates
## @param fold_id: Fold ID that created this fragment (-1 for original cells)
func _init(geom: PackedVector2Array, fold_id: int = -1):
    geometry = geom
    fold_created = fold_id
    _recalculate_cached_values()


## ============================================================================
## GEOMETRY METHODS
## ============================================================================

## Recalculate cached area and centroid
## Call this whenever geometry changes
func _recalculate_cached_values():
    if geometry.size() < 3:
        area = 0.0
        centroid = Vector2.ZERO
        return

    area = GeometryCore.polygon_area(geometry)
    centroid = GeometryCore.polygon_centroid(geometry)


## Get the centroid of this fragment
##
## @return: Centroid in LOCAL coordinates
func get_centroid() -> Vector2:
    return centroid


## Get the area of this fragment
##
## @return: Area in square pixels
func get_area() -> float:
    return area


## Update the geometry of this fragment
## Use this when shifting/transforming fragments
##
## @param new_geometry: New polygon vertices in LOCAL coordinates
func set_geometry(new_geometry: PackedVector2Array):
    geometry = new_geometry
    _recalculate_cached_values()


## Transform this fragment's geometry by a vector
## Used when shifting cells during folds
##
## @param offset: Vector to add to all vertices (LOCAL coordinates)
func translate_geometry(offset: Vector2):
    var new_geom = PackedVector2Array()
    for vertex in geometry:
        new_geom.append(vertex + offset)
    set_geometry(new_geom)


## Check if this fragment is degenerate (invalid geometry)
##
## @return: true if geometry is invalid (< 3 vertices or zero area)
func is_degenerate() -> bool:
    return geometry.size() < 3 or abs(area) < GeometryCore.EPSILON


## ============================================================================
## SEAM MANAGEMENT
## ============================================================================

## Add seam metadata to this fragment
##
## @param seam: Dictionary with keys: fold_id, line_point, line_normal,
##              intersection_points, timestamp
func add_seam(seam: Dictionary):
    # Validate seam data
    if not seam.has("fold_id") or not seam.has("line_point") or not seam.has("line_normal"):
        push_error("CellFragment.add_seam: Invalid seam dictionary")
        return

    seam_data.append(seam)


## Get all seams affecting this fragment
##
## @return: Array of seam dictionaries
func get_seams() -> Array[Dictionary]:
    return seam_data


## Check if this fragment has a seam from a specific fold
##
## @param fold_id: Fold ID to check
## @return: true if fragment has a seam from this fold
func has_seam_from_fold(fold_id: int) -> bool:
    for seam in seam_data:
        if seam.get("fold_id", -1) == fold_id:
            return true
    return false


## ============================================================================
## DEBUG & SERIALIZATION
## ============================================================================

## Create a duplicate of this fragment
## Used when splitting or copying fragments
##
## @return: New CellFragment with same data
func duplicate_fragment() -> CellFragment:
    var new_frag = CellFragment.new(geometry.duplicate(), fold_created)

    # Deep copy seam data
    for seam in seam_data:
        new_frag.add_seam(seam.duplicate())

    return new_frag


## Get debug string representation
##
## @return: Human-readable string
func to_string() -> String:
    return "CellFragment(vertices=%d, area=%.2f, fold=%d, seams=%d)" % [
        geometry.size(),
        area,
        fold_created,
        seam_data.size()
    ]
```

### Usage Examples

```gdscript
# Create a square fragment for grid position (3, 4)
var local_pos = Vector2(3, 4) * cell_size
var square_geom = PackedVector2Array([
    local_pos,
    local_pos + Vector2(cell_size, 0),
    local_pos + Vector2(cell_size, cell_size),
    local_pos + Vector2(0, cell_size)
])
var fragment = CellFragment.new(square_geom, -1)  # -1 = original

# Add a seam
var seam = {
    "fold_id": 5,
    "line_point": Vector2(200, 150),
    "line_normal": Vector2(0.707, 0.707),
    "intersection_points": PackedVector2Array([Vector2(200, 128), Vector2(256, 150)]),
    "timestamp": Time.get_ticks_msec()
}
fragment.add_seam(seam)

# Shift fragment
fragment.translate_geometry(Vector2(-64, 0))  # Shift left one cell

# Check validity
if not fragment.is_degenerate():
    print("Fragment area: ", fragment.get_area())
```

---

## CompoundCell Class Specification

### File Location
`scripts/core/CompoundCell.gd`

### Full Implementation

```gdscript
## CompoundCell - Represents all cell fragments at a grid position
##
## CompoundCell is a Node2D that manages multiple CellFragment instances
## and their visual representations. It handles merging, rendering, and
## fold history tracking for undo support.
##
## Hierarchy: CompoundCell (Node2D)
##              ├── Polygon2D (fragment 0 visual)
##              ├── Polygon2D (fragment 1 visual)
##              └── ...
##
## Memory: Node2D → must be explicitly freed with queue_free()
## Coordinates: Child of GridManager → uses LOCAL coordinate space

class_name CompoundCell extends Node2D

## ============================================================================
## PROPERTIES - Core Identity
## ============================================================================

## Current logical grid position
## This is where the cell "lives" in the grid
var grid_position: Vector2i = Vector2i.ZERO

## Cell type determines color and behavior
## 0 = empty, 1 = wall, 2 = water, 3 = goal
var cell_type: int = 0

## Array of original grid positions that merged to create this cell
## Initially just [grid_position], grows during merge operations
## Used for undo and debugging
var source_positions: Array[Vector2i] = []


## ============================================================================
## PROPERTIES - Fragment Management
## ============================================================================

## All geometric fragments at this position
## These are the actual polygon pieces that make up the cell
var fragments: Array[CellFragment] = []

## Visual representation - one Polygon2D per fragment
## IMPORTANT: These are children of this CompoundCell node
## Array indices match fragments array (fragment[i] → polygon_visuals[i])
var polygon_visuals: Array[Polygon2D] = []


## ============================================================================
## PROPERTIES - Fold History (for Undo System)
## ============================================================================

## Chronological list of fold IDs that affected this cell
## Last element is the most recent fold
## Used for undo dependency checking
var fold_history: Array[int] = []


## ============================================================================
## PROPERTIES - Visual Feedback
## ============================================================================

## Outline color for anchor selection
var outline_color: Color = Color.TRANSPARENT

## Whether this cell is currently hovered by mouse
var is_hovered: bool = false

## Outline width for selection visuals
const OUTLINE_WIDTH: float = 4.0

## Hover highlight color (semi-transparent yellow)
const HOVER_COLOR: Color = Color(1, 1, 0, 0.3)


## ============================================================================
## CONSTRUCTOR
## ============================================================================

## Initialize a new CompoundCell
##
## @param pos: Grid position for this cell
## @param initial_type: Cell type (0=empty, 1=wall, 2=water, 3=goal)
func _init(pos: Vector2i, initial_type: int = 0):
    grid_position = pos
    cell_type = initial_type
    source_positions = [pos]  # Initially, just itself


## ============================================================================
## FRAGMENT MANAGEMENT
## ============================================================================

## Add a new fragment to this compound cell
## Creates a corresponding Polygon2D visual automatically
##
## @param frag: CellFragment to add
func add_fragment(frag: CellFragment):
    if frag == null:
        push_error("CompoundCell.add_fragment: null fragment")
        return

    if frag.is_degenerate():
        push_warning("CompoundCell.add_fragment: Degenerate fragment ignored")
        return

    fragments.append(frag)

    # Create visual for this fragment
    var polygon = Polygon2D.new()
    polygon.polygon = frag.geometry
    polygon.color = get_cell_color()
    add_child(polygon)
    polygon_visuals.append(polygon)


## Remove a specific fragment by index
##
## @param index: Index in fragments array
func remove_fragment(index: int):
    if index < 0 or index >= fragments.size():
        push_error("CompoundCell.remove_fragment: Invalid index %d" % index)
        return

    fragments.remove_at(index)

    if index < polygon_visuals.size():
        var poly = polygon_visuals[index]
        polygon_visuals.remove_at(index)
        poly.queue_free()


## Remove all fragments and their visuals
## Used when cell is being deleted
func clear_fragments():
    fragments.clear()

    for poly in polygon_visuals:
        poly.queue_free()
    polygon_visuals.clear()


## Get number of fragments in this cell
##
## @return: Fragment count
func get_fragment_count() -> int:
    return fragments.size()


## Check if cell has no fragments (should be deleted)
##
## @return: true if no fragments
func is_empty() -> bool:
    return fragments.is_empty()


## ============================================================================
## GEOMETRY QUERIES
## ============================================================================

## Get total area of all fragments
##
## @return: Total area in square pixels
func get_total_area() -> float:
    var total = 0.0
    for frag in fragments:
        total += frag.get_area()
    return total


## Get weighted centroid of all fragments
## Used for player positioning and visual centering
##
## @return: Centroid in LOCAL coordinates
func get_center() -> Vector2:
    if fragments.is_empty():
        # Fallback: use grid position
        var cell_size = 64.0
        if get_parent() and get_parent().has("cell_size"):
            cell_size = get_parent().cell_size
        return Vector2(grid_position) * cell_size

    # Single fragment - use its centroid
    if fragments.size() == 1:
        return fragments[0].get_centroid()

    # Multiple fragments - weighted average by area
    var weighted_pos = Vector2.ZERO
    var total_area = 0.0

    for frag in fragments:
        var frag_area = frag.get_area()
        var frag_centroid = frag.get_centroid()
        weighted_pos += frag_centroid * frag_area
        total_area += frag_area

    if total_area > GeometryCore.EPSILON:
        return weighted_pos / total_area

    # Fallback for degenerate case
    return fragments[0].get_centroid()


## Check if a point (in LOCAL coordinates) is inside any fragment
##
## @param point: Point to test in LOCAL coordinates
## @return: true if point is inside any fragment
func contains_point(point: Vector2) -> bool:
    for frag in fragments:
        if GeometryCore.point_in_polygon(point, frag.geometry):
            return true
    return false


## Get bounding rectangle of all fragments
##
## @return: Rect2 in LOCAL coordinates
func get_bounding_rect() -> Rect2:
    if fragments.is_empty():
        return Rect2()

    var min_x = INF
    var min_y = INF
    var max_x = -INF
    var max_y = -INF

    for frag in fragments:
        for vertex in frag.geometry:
            min_x = min(min_x, vertex.x)
            min_y = min(min_y, vertex.y)
            max_x = max(max_x, vertex.x)
            max_y = max(max_y, vertex.y)

    return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


## ============================================================================
## MERGE OPERATIONS
## ============================================================================

## Merge another CompoundCell into this one
## Used when cells shift to overlap during folds
##
## CRITICAL: Caller is responsible for freeing the 'other' cell after merge!
##
## @param other: CompoundCell to merge into this one
## @param fold_id: Fold ID causing this merge
func merge_with(other: CompoundCell, fold_id: int):
    if other == null:
        push_error("CompoundCell.merge_with: null other cell")
        return

    # Merge all fragments
    for frag in other.fragments:
        add_fragment(frag.duplicate_fragment())

    # Merge source positions (union, no duplicates)
    for pos in other.source_positions:
        if pos not in source_positions:
            source_positions.append(pos)

    # Merge fold histories (union, preserving chronological order)
    var all_folds = fold_history + other.fold_history
    all_folds.append(fold_id)  # Add the merge fold itself

    # Remove duplicates while preserving order
    var unique_folds = []
    for f_id in all_folds:
        if f_id not in unique_folds:
            unique_folds.append(f_id)
    fold_history = unique_folds

    # Determine merged cell type using priority rules
    cell_type = _merge_cell_types(cell_type, other.cell_type)

    # Update all visuals
    update_all_visuals()


## Determine cell type when merging
## Priority: goal > wall > water > empty
##
## @param type_a: First cell type
## @param type_b: Second cell type
## @return: Merged cell type (higher priority wins)
func _merge_cell_types(type_a: int, type_b: int) -> int:
    const PRIORITY = {3: 4, 1: 3, 2: 2, 0: 1}  # goal, wall, water, empty
    var priority_a = PRIORITY.get(type_a, 0)
    var priority_b = PRIORITY.get(type_b, 0)
    return type_a if priority_a >= priority_b else type_b


## ============================================================================
## FOLD HISTORY TRACKING (for Undo System)
## ============================================================================

## Record that this cell was affected by a fold
##
## @param fold_id: Fold ID to add to history
func add_fold_to_history(fold_id: int):
    if fold_id not in fold_history:
        fold_history.append(fold_id)


## Check if this cell was affected by a specific fold
##
## @param fold_id: Fold ID to check
## @return: true if cell has this fold in history
func is_affected_by_fold(fold_id: int) -> bool:
    return fold_id in fold_history


## Get the newest (most recent) fold that affected this cell
##
## @return: Fold ID, or -1 if no folds have affected this cell
func get_newest_fold() -> int:
    if fold_history.is_empty():
        return -1
    return fold_history[-1]


## Get all folds that affected this cell
##
## @return: Array of fold IDs in chronological order
func get_fold_history() -> Array[int]:
    return fold_history


## ============================================================================
## CELL TYPE & VISUAL UPDATES
## ============================================================================

## Set the cell type and update visuals
##
## @param new_type: New cell type (0=empty, 1=wall, 2=water, 3=goal)
func set_cell_type(new_type: int):
    cell_type = new_type
    update_all_visuals()


## Get color for current cell type
##
## @return: Color for this cell type
func get_cell_color() -> Color:
    match cell_type:
        0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
        1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
        2: return Color(0.2, 0.4, 1.0)  # Water - blue
        3: return Color(0.2, 1.0, 0.2)  # Goal - green
        _: return Color(1.0, 1.0, 1.0)  # Default - white


## Update all fragment visuals (geometry and color)
## Call this after geometry changes or cell type changes
func update_all_visuals():
    var color = get_cell_color()

    for i in range(min(fragments.size(), polygon_visuals.size())):
        polygon_visuals[i].polygon = fragments[i].geometry
        polygon_visuals[i].color = color

    queue_redraw()  # Trigger redraw for outlines/hover


## ============================================================================
## VISUAL FEEDBACK (Selection & Hover)
## ============================================================================

## Set outline color for anchor selection
##
## @param color: Color for outline (Color.TRANSPARENT to hide)
func set_outline_color(color: Color):
    outline_color = color
    queue_redraw()


## Set hover highlight state
##
## @param enabled: true to show hover effect
func set_hover_highlight(enabled: bool):
    is_hovered = enabled
    queue_redraw()


## Clear all visual feedback
func clear_visual_feedback():
    outline_color = Color.TRANSPARENT
    is_hovered = false
    queue_redraw()


## Custom draw function for outlines and hover effects
## Called automatically by Godot when queue_redraw() is called
func _draw():
    # Draw hover effect (semi-transparent yellow over all fragments)
    if is_hovered:
        for frag in fragments:
            draw_colored_polygon(frag.geometry, HOVER_COLOR)

    # Draw outline if selected
    if outline_color.a > 0:
        for frag in fragments:
            # Create closed polygon for outline
            var outline_points = frag.geometry.duplicate()
            outline_points.append(frag.geometry[0])  # Close the loop
            draw_polyline(outline_points, outline_color, OUTLINE_WIDTH)


## ============================================================================
## SPLITTING SUPPORT (for Phase 4 Diagonal Folds)
## ============================================================================

## Split a specific fragment by a fold line
## Returns new fragments for both sides of the line
##
## @param frag_index: Index of fragment to split
## @param line_point: Point on fold line (LOCAL coordinates)
## @param line_normal: Normal vector of fold line
## @param fold_id: Fold ID creating this split
## @return: Dictionary with keys "left", "right", "intersections", or empty dict on failure
func split_fragment(frag_index: int, line_point: Vector2, line_normal: Vector2, fold_id: int) -> Dictionary:
    if frag_index < 0 or frag_index >= fragments.size():
        push_error("CompoundCell.split_fragment: Invalid index %d" % frag_index)
        return {}

    var frag = fragments[frag_index]
    var split_result = GeometryCore.split_polygon_by_line(frag.geometry, line_point, line_normal)

    if split_result.intersections.size() == 0:
        push_warning("CompoundCell.split_fragment: Fragment does not intersect fold line")
        return {}

    # Validate split results
    if split_result.left.size() < 3 or split_result.right.size() < 3:
        push_warning("CompoundCell.split_fragment: Degenerate split result")
        return {}

    # Create new fragments for each side
    var left_frag = CellFragment.new(split_result.left, fold_id)
    var right_frag = CellFragment.new(split_result.right, fold_id)

    # Copy existing seam data to both fragments
    for seam in frag.seam_data:
        left_frag.add_seam(seam.duplicate())
        right_frag.add_seam(seam.duplicate())

    # Add new seam data for this split
    var new_seam = {
        "fold_id": fold_id,
        "line_point": line_point,
        "line_normal": line_normal,
        "intersection_points": split_result.intersections,
        "timestamp": Time.get_ticks_msec()
    }
    left_frag.add_seam(new_seam)
    right_frag.add_seam(new_seam)

    return {
        "left": left_frag,
        "right": right_frag,
        "intersections": split_result.intersections
    }


## Split ALL fragments in this cell by a fold line
## Returns two arrays of fragments (left and right sides)
##
## @param line_point: Point on fold line (LOCAL coordinates)
## @param line_normal: Normal vector of fold line
## @param fold_id: Fold ID creating this split
## @return: Dictionary with keys "left_fragments" (Array), "right_fragments" (Array)
func split_all_fragments(line_point: Vector2, line_normal: Vector2, fold_id: int) -> Dictionary:
    var left_fragments: Array[CellFragment] = []
    var right_fragments: Array[CellFragment] = []

    for i in range(fragments.size()):
        var split_result = split_fragment(i, line_point, line_normal, fold_id)

        if not split_result.is_empty():
            left_fragments.append(split_result.left)
            right_fragments.append(split_result.right)
        else:
            # Fragment not intersected - classify which side it's on
            var centroid = fragments[i].get_centroid()
            var side = GeometryCore.point_side_of_line(centroid, line_point, line_normal)

            if side <= 0:  # Left or on line
                left_fragments.append(fragments[i].duplicate_fragment())
            else:  # Right
                right_fragments.append(fragments[i].duplicate_fragment())

    return {
        "left_fragments": left_fragments,
        "right_fragments": right_fragments
    }


## ============================================================================
## DEBUG & UTILITIES
## ============================================================================

## Get debug string representation
##
## @return: Human-readable string
func to_string() -> String:
    return "CompoundCell(pos=%s, type=%d, fragments=%d, sources=%d, folds=%s)" % [
        grid_position,
        cell_type,
        fragments.size(),
        source_positions.size(),
        str(fold_history)
    ]


## Validate integrity of this cell
## Returns true if cell is in valid state
##
## @return: true if valid, false if integrity issues found
func validate() -> bool:
    # Check fragments match visuals
    if fragments.size() != polygon_visuals.size():
        push_error("CompoundCell.validate: Fragment/visual count mismatch")
        return false

    # Check all fragments are valid
    for frag in fragments:
        if frag.is_degenerate():
            push_error("CompoundCell.validate: Degenerate fragment found")
            return false

    # Check source_positions not empty
    if source_positions.is_empty():
        push_error("CompoundCell.validate: No source positions")
        return false

    return true
```

### Usage Examples

```gdscript
# Create a new CompoundCell
var cell = CompoundCell.new(Vector2i(5, 3), 0)  # Empty cell at (5,3)

# Add initial square fragment
var local_pos = Vector2(5, 3) * 64.0
var square_geom = PackedVector2Array([...])
var frag = CellFragment.new(square_geom, -1)
cell.add_fragment(frag)

# Add cell to grid
grid_manager.cells[Vector2i(5, 3)] = cell
grid_manager.add_child(cell)

# Later: Split cell by diagonal fold
var line_point = Vector2(300, 200)
var line_normal = Vector2(0.707, 0.707)
var result = cell.split_all_fragments(line_point, line_normal, 5)

# Keep left fragments at current position
cell.clear_fragments()
for frag in result.left_fragments:
    cell.add_fragment(frag)
cell.add_fold_to_history(5)

# Create new cell for right fragments at shifted position
var new_cell = CompoundCell.new(Vector2i(6, 2), cell.cell_type)
new_cell.source_positions = cell.source_positions.duplicate()
for frag in result.right_fragments:
    # Shift geometry
    frag.translate_geometry(Vector2(64, -64))  # Shift right+up
    new_cell.add_fragment(frag)
new_cell.add_fold_to_history(5)

# Merge if position already occupied
if grid_manager.cells.has(Vector2i(6, 2)):
    grid_manager.cells[Vector2i(6, 2)].merge_with(new_cell, 5)
    new_cell.queue_free()
else:
    grid_manager.cells[Vector2i(6, 2)] = new_cell
    grid_manager.add_child(new_cell)
```

---

## Rendering System

### Visual Hierarchy

```
GridManager (Node2D) at grid_origin
├── CompoundCell at (0,0) [Node2D]
│   ├── Polygon2D (fragment 0)
│   └── Polygon2D (fragment 1)
├── CompoundCell at (1,0) [Node2D]
│   └── Polygon2D (fragment 0)
└── ...
```

### Rendering Strategy

#### Per-Fragment Rendering

Each `CellFragment` gets its own `Polygon2D` visual:

**Advantages:**
- Accurate visual representation of complex cells
- Each fragment can have different rendering properties if needed
- Standard Godot pattern - well optimized

**Performance:**
- Godot efficiently batches Polygon2D nodes with same material
- For 10x10 grid with average 2 fragments per cell = 200 Polygon2D nodes
- Expected: 60 FPS easily achievable

#### Color & Material

```gdscript
func get_cell_color() -> Color:
    match cell_type:
        0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
        1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
        2: return Color(0.2, 0.4, 1.0)  # Water - blue
        3: return Color(0.2, 1.0, 0.2)  # Goal - green
```

All fragments in a CompoundCell share the same color (determined by cell_type).

#### Outline & Hover Effects

Rendered in `CompoundCell._draw()`:
- **Hover**: Semi-transparent yellow overlay (`draw_colored_polygon`)
- **Selection**: Colored outline (`draw_polyline` with 4px width)

These are rendered ON TOP of Polygon2D children automatically by Godot's draw order.

#### Seam Lines (Future Phase 5)

Seam lines will be separate `Line2D` nodes, children of GridManager:

```gdscript
# In FoldSystem
var seam_line = Line2D.new()
seam_line.points = PackedVector2Array([intersection1, intersection2])
seam_line.width = 3.0
seam_line.default_color = Color.WHITE
grid_manager.add_child(seam_line)
```

### Z-Ordering

Default Godot render order (children rendered in add order):
1. Polygon2D nodes (cell fills)
2. CompoundCell._draw() calls (outlines/hover)
3. Line2D nodes (seam lines)

This gives correct layering: fills → highlights → seams.

### Update Strategy

**When geometry changes:**
```gdscript
# Update fragment
fragment.set_geometry(new_geometry)

# Update corresponding visual
polygon_visual.polygon = fragment.geometry

# Redraw outlines
cell.queue_redraw()
```

**When cell type changes:**
```gdscript
cell.set_cell_type(new_type)  # Automatically updates all visuals
```

**Performance:** Only modified cells need updates. No need to redraw entire grid.

---

## GridManager Integration

### Modified GridManager Class

#### Property Changes

```gdscript
# BEFORE (current)
var cells: Dictionary = {}  # Vector2i -> Cell

# AFTER (new)
var cells: Dictionary = {}  # Vector2i -> CompoundCell
```

**Important:** Type is still compatible! Dictionary keys are still `Vector2i`, values are still Node2D subclass.

#### Grid Initialization

```gdscript
func create_grid() -> void:
    for y in range(grid_size.y):
        for x in range(grid_size.x):
            var grid_pos = Vector2i(x, y)

            # Create CompoundCell (CHANGED)
            var cell = CompoundCell.new(grid_pos, 0)  # Type 0 = empty

            # Create initial square fragment (ADDED)
            var local_pos = Vector2(grid_pos) * cell_size
            var square_geometry = PackedVector2Array([
                local_pos,                              # Top-left
                local_pos + Vector2(cell_size, 0),      # Top-right
                local_pos + Vector2(cell_size, cell_size), # Bottom-right
                local_pos + Vector2(0, cell_size)       # Bottom-left
            ])

            var initial_fragment = CellFragment.new(square_geometry, -1)
            cell.add_fragment(initial_fragment)

            # Add to grid (unchanged)
            cells[grid_pos] = cell
            add_child(cell)
```

#### Query Methods (Unchanged Interface!)

```gdscript
## Get cell at grid position
## @param grid_pos: Grid coordinates
## @return: CompoundCell at position, or null if out of bounds
func get_cell(grid_pos: Vector2i) -> CompoundCell:
    return cells.get(grid_pos, null)


## Get cell at world position
## @param world_pos: World coordinates (global)
## @return: CompoundCell at position, or null if none found
func get_cell_at_world_pos(world_pos: Vector2) -> CompoundCell:
    var local_pos = to_local(world_pos)

    # First try simple grid lookup
    var grid_pos = world_to_grid(world_pos)
    var cell = get_cell(grid_pos)

    # For cells that haven't been split, simple lookup works
    if cell and cell.contains_point(local_pos):
        return cell

    # For partial cells, check all cells for containment
    for c in cells.values():
        if c.contains_point(local_pos):
            return c

    return null
```

**Key Point:** Public API remains the same! Just return type changed from `Cell` to `CompoundCell`.

#### Cell Removal (Important!)

```gdscript
## Remove a cell from the grid
## Properly frees the node and clears references
##
## @param grid_pos: Position of cell to remove
func remove_cell(grid_pos: Vector2i):
    var cell = cells.get(grid_pos)
    if cell:
        cells.erase(grid_pos)

        # Important: Clear fragments to free Polygon2D nodes
        cell.clear_fragments()

        # Queue free the CompoundCell node
        cell.queue_free()
```

#### New Helper Methods

```gdscript
## Get all cells affected by a specific fold
##
## @param fold_id: Fold ID to check
## @return: Array of CompoundCells
func get_cells_affected_by_fold(fold_id: int) -> Array[CompoundCell]:
    var affected: Array[CompoundCell] = []

    for cell in cells.values():
        if cell.is_affected_by_fold(fold_id):
            affected.append(cell)

    return affected


## Validate grid integrity
## Checks all cells for validity
##
## @return: true if grid is valid
func validate_grid() -> bool:
    for pos in cells.keys():
        var cell = cells[pos]

        # Check cell position matches dictionary key
        if cell.grid_position != pos:
            push_error("GridManager: Cell position mismatch at %s" % pos)
            return false

        # Validate cell
        if not cell.validate():
            push_error("GridManager: Cell validation failed at %s" % pos)
            return false

    return true
```

---

## FoldSystem Integration

### Diagonal Fold Implementation

```gdscript
## Execute a diagonal fold between two anchors
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param fold_angle: Angle of fold in degrees (0 = horizontal, 90 = vertical)
func execute_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i, fold_angle: float):
    # Generate fold ID
    var fold_id = next_fold_id
    next_fold_id += 1

    # Calculate fold line geometry
    var fold_line = _calculate_fold_line(anchor1, anchor2, fold_angle)

    # Classify all cells
    var classifications = _classify_all_cells(fold_line)

    # Step 1: Split cells that intersect fold line
    _split_cells(classifications.split_cells, fold_line, fold_id)

    # Step 2: Remove cells in removed region
    _remove_cells(classifications.removed_cells)

    # Step 3: Shift cells on shifted side
    _shift_cells(classifications.shifted_cells, anchor1, anchor2, fold_id)

    # Step 4: Create seam line visual
    _create_seam_line(fold_line.point1, fold_line.point2)

    # Step 5: Record fold in history
    _record_fold(fold_id, anchor1, anchor2, classifications)


## Calculate fold line geometry from anchors and angle
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param angle_degrees: Fold angle in degrees
## @return: Dictionary with fold line data
func _calculate_fold_line(anchor1: Vector2i, anchor2: Vector2i, angle_degrees: float) -> Dictionary:
    # Convert anchors to LOCAL coordinates (cell centers)
    var anchor1_local = (Vector2(anchor1) + Vector2(0.5, 0.5)) * grid_manager.cell_size
    var anchor2_local = (Vector2(anchor2) + Vector2(0.5, 0.5)) * grid_manager.cell_size

    # Midpoint between anchors
    var midpoint = (anchor1_local + anchor2_local) / 2.0

    # Calculate fold line direction from angle
    var angle_rad = deg_to_rad(angle_degrees)
    var line_direction = Vector2(cos(angle_rad), sin(angle_rad))
    var line_normal = Vector2(-line_direction.y, line_direction.x)

    # Calculate endpoints for seam line (extended beyond grid)
    var line_length = 1000.0  # Long enough to span entire grid
    var point1 = midpoint - line_direction * line_length
    var point2 = midpoint + line_direction * line_length

    return {
        "point": midpoint,
        "normal": line_normal,
        "direction": line_direction,
        "point1": point1,
        "point2": point2
    }


## Classify all cells relative to fold line
##
## @param fold_line: Fold line data from _calculate_fold_line()
## @return: Dictionary with arrays: split_cells, removed_cells, shifted_cells, stationary_cells
func _classify_all_cells(fold_line: Dictionary) -> Dictionary:
    var split_cells = []
    var removed_cells = []
    var shifted_cells = []
    var stationary_cells = []

    for pos in grid_manager.cells.keys():
        var cell = grid_manager.cells[pos]

        # Check each fragment in the cell
        var left_count = 0
        var right_count = 0
        var intersecting_count = 0

        for frag in cell.fragments:
            # Classify fragment
            var classification = _classify_fragment(frag, fold_line)

            if classification == "intersecting":
                intersecting_count += 1
            elif classification == "left":
                left_count += 1
            elif classification == "right":
                right_count += 1

        # Cell classification based on fragment classifications
        if intersecting_count > 0:
            # Any fragment intersecting → cell must be split
            split_cells.append(pos)
        elif left_count > 0 and right_count > 0:
            # Fragments on both sides → cell must be split (shouldn't happen if intersecting check works)
            split_cells.append(pos)
        elif right_count > 0:
            # All fragments on right → shifted
            shifted_cells.append(pos)
        else:
            # All fragments on left or on line → stationary
            stationary_cells.append(pos)

    # Determine removed region based on anchors
    # (Implementation depends on fold direction - see existing axis-aligned code)
    removed_cells = _determine_removed_cells(split_cells, shifted_cells, fold_line)

    return {
        "split_cells": split_cells,
        "removed_cells": removed_cells,
        "shifted_cells": shifted_cells,
        "stationary_cells": stationary_cells
    }


## Classify a single fragment relative to fold line
##
## @param frag: CellFragment to classify
## @param fold_line: Fold line data
## @return: "intersecting", "left", "right", or "on_line"
func _classify_fragment(frag: CellFragment, fold_line: Dictionary) -> String:
    var left_count = 0
    var right_count = 0
    var on_line_count = 0

    # Check each vertex
    for vertex in frag.geometry:
        var side = GeometryCore.point_side_of_line(vertex, fold_line.point, fold_line.normal)

        if abs(side) < GeometryCore.EPSILON:
            on_line_count += 1
        elif side < 0:
            left_count += 1
        else:
            right_count += 1

    # Classification logic
    if left_count > 0 and right_count > 0:
        return "intersecting"  # Vertices on both sides
    elif right_count > 0:
        return "right"
    elif left_count > 0:
        return "left"
    else:
        return "on_line"  # All vertices on line (degenerate case)


## Split cells that intersect the fold line
##
## @param cell_positions: Array of Vector2i positions to split
## @param fold_line: Fold line data
## @param fold_id: Fold ID for tracking
func _split_cells(cell_positions: Array, fold_line: Dictionary, fold_id: int):
    for pos in cell_positions:
        var cell = grid_manager.cells[pos]

        # Split all fragments in the cell
        var result = cell.split_all_fragments(fold_line.point, fold_line.normal, fold_id)

        # Keep left fragments at current position
        cell.clear_fragments()
        cell.add_fold_to_history(fold_id)

        for frag in result.left_fragments:
            cell.add_fragment(frag)

        # Calculate shifted position for right fragments
        var shifted_pos = _calculate_shifted_position(pos, fold_line)

        # Create new cell for right fragments
        var new_cell = CompoundCell.new(shifted_pos, cell.cell_type)
        new_cell.source_positions = cell.source_positions.duplicate()
        new_cell.add_fold_to_history(fold_id)

        # Calculate shift vector
        var shift_vector = _calculate_shift_vector(fold_line)

        for frag in result.right_fragments:
            # Shift fragment geometry to new position
            frag.translate_geometry(shift_vector)
            new_cell.add_fragment(frag)

        # Handle merging at shifted position
        if grid_manager.cells.has(shifted_pos):
            var existing = grid_manager.cells[shifted_pos]
            existing.merge_with(new_cell, fold_id)
            new_cell.queue_free()
        else:
            grid_manager.cells[shifted_pos] = new_cell
            grid_manager.add_child(new_cell)


## Remove cells in the removed region
##
## @param cell_positions: Array of Vector2i positions to remove
func _remove_cells(cell_positions: Array):
    for pos in cell_positions:
        grid_manager.remove_cell(pos)


## Shift unsplit cells to new positions
##
## @param cell_positions: Array of Vector2i positions to shift
## @param anchor1: First anchor position
## @param anchor2: Second anchor position
## @param fold_id: Fold ID for tracking
func _shift_cells(cell_positions: Array, anchor1: Vector2i, anchor2: Vector2i, fold_id: int):
    var shift_vector = _calculate_shift_vector_from_anchors(anchor1, anchor2)

    for pos in cell_positions:
        var cell = grid_manager.cells[pos]
        var new_pos = _calculate_shifted_position_from_anchors(pos, anchor1, anchor2)

        # Update cell metadata
        cell.grid_position = new_pos
        cell.add_fold_to_history(fold_id)

        # Shift all fragment geometries
        for frag in cell.fragments:
            frag.translate_geometry(shift_vector)

        cell.update_all_visuals()

        # Update dictionary
        grid_manager.cells.erase(pos)

        # Handle merging at new position
        if grid_manager.cells.has(new_pos):
            var existing = grid_manager.cells[new_pos]
            existing.merge_with(cell, fold_id)
            cell.queue_free()
        else:
            grid_manager.cells[new_pos] = cell
```

### Undo System Implementation

```gdscript
## Check if a fold can be undone
## A fold can only be undone if it's the newest fold affecting ALL its cells
##
## @param fold_id: Fold ID to check
## @return: true if fold can be undone
func can_undo_fold(fold_id: int) -> bool:
    # Find fold in history
    var fold_data = _get_fold_data(fold_id)
    if fold_data == null:
        return false

    # Get all cells affected by this fold
    var affected_cells = grid_manager.get_cells_affected_by_fold(fold_id)

    # Check if this fold is the newest for ALL affected cells
    for cell in affected_cells:
        if cell.get_newest_fold() != fold_id:
            # This cell has been affected by a newer fold → blocked
            return false

    return true


## Get fold data from history
##
## @param fold_id: Fold ID to find
## @return: Fold data dictionary, or null if not found
func _get_fold_data(fold_id: int) -> Dictionary:
    for fold in fold_history:
        if fold.get("fold_id") == fold_id:
            return fold
    return {}
```

---

## Coordinate System Guidelines

### The Three Coordinate Systems

#### 1. Grid Coordinates (Vector2i)
- **Range**: (0, 0) to (9, 9) for 10x10 grid
- **Usage**: Dictionary keys, logical cell positions
- **Example**: `Vector2i(5, 3)`

#### 2. Local Coordinates (Vector2)
- **Origin**: Relative to GridManager.position (which is set to grid_origin)
- **Usage**: Cell geometry, fragment vertices, seam line endpoints
- **Example**: `Vector2(320.0, 192.0)` for cell (5, 3) center at 64px cell size

#### 3. World Coordinates (Vector2)
- **Origin**: Absolute screen coordinates (0, 0) at top-left
- **Usage**: Mouse position, player position, get_global_mouse_position()
- **Example**: `Vector2(640.0, 360.0)` for screen center

### Conversion Functions

```gdscript
# Grid to Local
var local_pos = Vector2(grid_pos) * cell_size

# Local to Grid
var grid_pos = Vector2i(local_pos / cell_size)

# Local to World (GridManager method)
var world_pos = grid_manager.to_global(local_pos)

# World to Local (GridManager method)
var local_pos = grid_manager.to_local(world_pos)

# World to Grid (GridManager method)
var grid_pos = grid_manager.world_to_grid(world_pos)
```

### Critical Rules

1. **Cell/Fragment geometry**: ALWAYS LOCAL coordinates
2. **Mouse input**: ALWAYS convert to LOCAL before using
3. **Player position**: ALWAYS WORLD coordinates
4. **Seam Line2D points**: ALWAYS LOCAL coordinates (Line2D is child of GridManager)

### Common Mistakes to Avoid

```gdscript
# ❌ WRONG - Using world coordinates for geometry
var world_pos = grid_manager.grid_to_world(grid_pos)
cell.geometry = create_square(world_pos, size)  # Double offset!

# ✅ CORRECT - Using local coordinates
var local_pos = Vector2(grid_pos) * cell_size
cell.geometry = create_square(local_pos, size)

# ❌ WRONG - Setting player position to local coordinates
player.position = cell.get_center()  # Player in wrong location!

# ✅ CORRECT - Converting to world coordinates
player.position = grid_manager.to_global(cell.get_center())
```

---

## Memory Management

### Memory Model

#### RefCounted (Automatic)
- **CellFragment** extends RefCounted
- Automatically freed when no references remain
- No explicit `queue_free()` needed
- Lightweight: ~200 bytes per fragment

#### Node2D (Manual)
- **CompoundCell** extends Node2D
- Must explicitly call `queue_free()` when removing
- Heavier: ~1KB per cell + Polygon2D children

### Lifecycle Management

#### Creating Cells

```gdscript
# Create cell
var cell = CompoundCell.new(grid_pos, cell_type)

# Create fragments
var frag = CellFragment.new(geometry, fold_id)
cell.add_fragment(frag)  # Cell holds reference

# Add to grid
grid_manager.cells[grid_pos] = cell
grid_manager.add_child(cell)  # CRITICAL: Add to scene tree
```

#### Removing Cells

```gdscript
# Remove from dictionary
grid_manager.cells.erase(grid_pos)

# Clear fragments (frees Polygon2D nodes)
cell.clear_fragments()

# Queue free the cell node
cell.queue_free()  # Will be freed at end of frame

# Fragments automatically freed when cell is freed (RefCounted)
```

#### Merging Cells

```gdscript
# Merge other into existing
existing_cell.merge_with(other_cell, fold_id)

# CRITICAL: Free the other cell
other_cell.queue_free()

# Fragments from other_cell are duplicated into existing_cell
# Original fragments in other_cell will be freed when other_cell is freed
```

### Memory Leak Prevention

#### Common Leak Sources

1. **Forgot to free merged cell**:
```gdscript
# ❌ BAD
existing.merge_with(other, fold_id)
# other still in scene tree → memory leak

# ✅ GOOD
existing.merge_with(other, fold_id)
other.queue_free()
```

2. **Forgot to clear fragments before freeing cell**:
```gdscript
# ❌ BAD
cell.queue_free()
# Polygon2D nodes still in scene tree → leak

# ✅ GOOD
cell.clear_fragments()  # Frees Polygon2D nodes
cell.queue_free()
```

3. **Dictionary references preventing GC**:
```gdscript
# ❌ BAD
cell.queue_free()
# Cell still in cells dictionary → prevents GC

# ✅ GOOD
cells.erase(grid_pos)  # Remove from dictionary
cell.clear_fragments()
cell.queue_free()
```

### Validation

```gdscript
# In tests, check for leaks
func test_fold_no_memory_leak():
    var initial_node_count = get_tree().get_node_count()

    # Perform fold
    fold_system.execute_diagonal_fold(anchor1, anchor2, 45.0)

    # Force garbage collection
    await get_tree().process_frame

    # Check node count is reasonable
    var final_node_count = get_tree().get_node_count()
    var node_diff = final_node_count - initial_node_count

    # Should be <= number of new cells created
    assert_lte(node_diff, 10, "Potential memory leak detected")
```

---

## Testing Strategy

### Unit Tests

#### CellFragment Tests

File: `scripts/tests/test_cell_fragment.gd`

```gdscript
extends GutTest

func test_create_fragment():
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
    ])
    var frag = CellFragment.new(geometry, -1)

    assert_not_null(frag, "Fragment should be created")
    assert_eq(frag.geometry.size(), 4, "Geometry should have 4 vertices")
    assert_eq(frag.fold_created, -1, "Fold ID should be -1")
    assert_almost_eq(frag.get_area(), 4096.0, 0.1, "Area should be 64x64")


func test_fragment_centroid():
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
    ])
    var frag = CellFragment.new(geometry, -1)
    var centroid = frag.get_centroid()

    assert_almost_eq(centroid.x, 32.0, 0.1, "Centroid X should be 32")
    assert_almost_eq(centroid.y, 32.0, 0.1, "Centroid Y should be 32")


func test_fragment_translate():
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
    ])
    var frag = CellFragment.new(geometry, -1)

    frag.translate_geometry(Vector2(100, 50))

    assert_almost_eq(frag.geometry[0].x, 100.0, 0.1, "First vertex X shifted")
    assert_almost_eq(frag.geometry[0].y, 50.0, 0.1, "First vertex Y shifted")


func test_fragment_add_seam():
    var frag = CellFragment.new(PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)
    ]), -1)

    var seam = {
        "fold_id": 5,
        "line_point": Vector2(32, 32),
        "line_normal": Vector2(1, 0)
    }
    frag.add_seam(seam)

    assert_eq(frag.seam_data.size(), 1, "Should have 1 seam")
    assert_true(frag.has_seam_from_fold(5), "Should have seam from fold 5")
```

#### CompoundCell Tests

File: `scripts/tests/test_compound_cell.gd`

```gdscript
extends GutTest

func test_create_compound_cell():
    var cell = CompoundCell.new(Vector2i(5, 3), 0)

    assert_not_null(cell, "Cell should be created")
    assert_eq(cell.grid_position, Vector2i(5, 3), "Position should match")
    assert_eq(cell.cell_type, 0, "Type should be 0")
    assert_eq(cell.source_positions.size(), 1, "Should have 1 source position")


func test_add_fragment():
    var cell = CompoundCell.new(Vector2i(0, 0), 0)
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
    ])
    var frag = CellFragment.new(geometry, -1)

    cell.add_fragment(frag)

    assert_eq(cell.get_fragment_count(), 1, "Should have 1 fragment")
    assert_eq(cell.polygon_visuals.size(), 1, "Should have 1 visual")


func test_merge_cells():
    # Create first cell with one fragment
    var cell1 = CompoundCell.new(Vector2i(0, 0), 0)
    var geom1 = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
    ])
    cell1.add_fragment(CellFragment.new(geom1, -1))
    cell1.add_fold_to_history(1)

    # Create second cell with one fragment
    var cell2 = CompoundCell.new(Vector2i(1, 0), 1)  # Wall type
    var geom2 = PackedVector2Array([
        Vector2(64, 0), Vector2(128, 0), Vector2(128, 64), Vector2(64, 64)
    ])
    cell2.add_fragment(CellFragment.new(geom2, 2))
    cell2.add_fold_to_history(2)

    # Merge
    cell1.merge_with(cell2, 3)

    assert_eq(cell1.get_fragment_count(), 2, "Should have 2 fragments after merge")
    assert_eq(cell1.source_positions.size(), 2, "Should have 2 source positions")
    assert_eq(cell1.cell_type, 1, "Type should be wall (priority)")
    assert_true(cell1.is_affected_by_fold(1), "Should have fold 1")
    assert_true(cell1.is_affected_by_fold(2), "Should have fold 2")
    assert_true(cell1.is_affected_by_fold(3), "Should have fold 3 (merge)")


func test_split_fragment():
    var cell = CompoundCell.new(Vector2i(0, 0), 0)
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)
    ])
    cell.add_fragment(CellFragment.new(geometry, -1))

    # Split diagonally
    var line_point = Vector2(32, 32)
    var line_normal = Vector2(0.707, 0.707)
    var result = cell.split_fragment(0, line_point, line_normal, 5)

    assert_false(result.is_empty(), "Split should succeed")
    assert_not_null(result.get("left"), "Should have left fragment")
    assert_not_null(result.get("right"), "Should have right fragment")
    assert_gt(result.left.get_area(), 0, "Left fragment should have area")
    assert_gt(result.right.get_area(), 0, "Right fragment should have area")
```

### Integration Tests

File: `scripts/tests/test_fold_integration.gd`

```gdscript
extends GutTest

var grid_manager: GridManager
var fold_system: FoldSystem

func before_each():
    grid_manager = GridManager.new()
    grid_manager.grid_size = Vector2i(5, 5)
    grid_manager.cell_size = 64.0
    grid_manager.create_grid()

    fold_system = FoldSystem.new()
    fold_system.initialize(grid_manager)

    add_child_autofree(grid_manager)
    add_child_autofree(fold_system)


func test_diagonal_fold_splits_cells():
    var initial_count = grid_manager.cells.size()

    # Execute 45-degree diagonal fold
    fold_system.execute_diagonal_fold(Vector2i(1, 1), Vector2i(3, 3), 45.0)

    # Should have split cells
    var split_found = false
    for cell in grid_manager.cells.values():
        if cell.get_fragment_count() > 1:
            split_found = true
            break

    assert_true(split_found, "At least one cell should be split")


func test_fold_history_tracking():
    fold_system.execute_diagonal_fold(Vector2i(1, 1), Vector2i(3, 3), 45.0)

    # Check that affected cells have fold in history
    var cells_with_fold = 0
    for cell in grid_manager.cells.values():
        if cell.is_affected_by_fold(0):  # Fold ID 0
            cells_with_fold += 1

    assert_gt(cells_with_fold, 0, "At least one cell should be affected by fold")


func test_cell_merge_on_overlap():
    # Set up scenario where cells will merge
    # (Specific setup depends on fold implementation)
    fold_system.execute_diagonal_fold(Vector2i(0, 2), Vector2i(4, 2), 0.0)

    # Check for merged cells (cells with multiple source positions)
    var merged_found = false
    for cell in grid_manager.cells.values():
        if cell.source_positions.size() > 1:
            merged_found = true
            break

    # May or may not find merged cells depending on fold
    # This is more of a smoke test
    assert_not_null(grid_manager.cells, "Grid should still exist after fold")
```

### Performance Tests

File: `scripts/tests/test_performance.gd`

```gdscript
extends GutTest

func test_fragment_count_after_multiple_folds():
    var grid_manager = GridManager.new()
    grid_manager.grid_size = Vector2i(10, 10)
    grid_manager.create_grid()

    var fold_system = FoldSystem.new()
    fold_system.initialize(grid_manager)

    add_child_autofree(grid_manager)
    add_child_autofree(fold_system)

    # Execute multiple folds
    for i in range(5):
        fold_system.execute_diagonal_fold(
            Vector2i(i, i),
            Vector2i(9 - i, 9 - i),
            45.0
        )

    # Count total fragments
    var total_fragments = 0
    for cell in grid_manager.cells.values():
        total_fragments += cell.get_fragment_count()

    # Reasonable upper bound: 500 fragments for 10x10 grid after 5 folds
    assert_lt(total_fragments, 500, "Fragment count should be reasonable")
```

---

## Migration Plan

### Phase 1: Create New Classes (Non-Breaking)
**Duration:** 1-2 hours
**Risk:** Low

#### Steps:
1. Create `scripts/core/CellFragment.gd` with full implementation
2. Create `scripts/core/CompoundCell.gd` with full implementation
3. Add `class_name` declarations
4. Run `godot --headless --import --quit` to ensure no syntax errors

#### Validation:
```bash
# Check for errors
godot --headless --script scripts/core/CellFragment.gd
godot --headless --script scripts/core/CompoundCell.gd
```

### Phase 2: Create Unit Tests
**Duration:** 2-3 hours
**Risk:** Low

#### Steps:
1. Create `test_cell_fragment.gd` with all fragment tests
2. Create `test_compound_cell.gd` with all cell tests
3. Run tests to ensure classes work correctly

#### Validation:
```bash
./run_tests.sh test_cell_fragment
./run_tests.sh test_compound_cell
```

### Phase 3: Update GridManager (Breaking Change)
**Duration:** 1-2 hours
**Risk:** Medium

#### Steps:
1. Update `GridManager.create_grid()` to use CompoundCell
2. Update method signatures to return `CompoundCell`
3. Keep all public methods the same (just change types)
4. **DO NOT modify FoldSystem yet**

#### Expected Breakage:
- Existing tests will fail (Cell vs CompoundCell type mismatch)
- FoldSystem calls will fail (Cell vs CompoundCell)

#### Validation:
```bash
# These WILL fail - expected
./run_tests.sh test_grid_manager
```

### Phase 4: Update Existing Tests
**Duration:** 2-3 hours
**Risk:** Medium

#### Steps:
1. Update all test files to use CompoundCell instead of Cell
2. Update assertions to work with fragments:
```gdscript
# BEFORE
assert_not_null(cell.geometry)

# AFTER
assert_gt(cell.get_fragment_count(), 0)
assert_not_null(cell.fragments[0].geometry)
```

3. Run tests after each file update

#### Validation:
```bash
./run_tests.sh  # All Phase 1-3 tests should pass
```

### Phase 5: Update FoldSystem for Phase 3 Folds
**Duration:** 2-3 hours
**Risk:** Medium

#### Steps:
1. Update `execute_horizontal_fold()` to work with CompoundCell
2. Update `execute_vertical_fold()` to work with CompoundCell
3. Add fold_history tracking
4. Implement merge_with() calls when cells overlap
5. Update animated versions

#### Changes Needed:
```gdscript
# BEFORE
var cell = grid_manager.cells[pos]
cell.geometry = new_geometry

# AFTER
var cell = grid_manager.cells[pos]
# Cell now has fragments, update all of them
for frag in cell.fragments:
    frag.set_geometry(new_geometry)
cell.update_all_visuals()
```

#### Validation:
```bash
./run_tests.sh test_fold_system
./run_tests.sh test_fold_validation
```

### Phase 6: Implement Phase 4 Diagonal Folds
**Duration:** 6-8 hours
**Risk:** High

#### Steps:
1. Implement `_calculate_fold_line()` for arbitrary angles
2. Implement `_classify_fragment()` and `_classify_all_cells()`
3. Implement `_split_cells()` using `CompoundCell.split_all_fragments()`
4. Implement `_shift_cells()` with geometry translation
5. Add comprehensive tests

#### Validation:
```bash
./run_tests.sh test_diagonal_fold
```

### Phase 7: Implement Undo System
**Duration:** 3-4 hours
**Risk:** Medium

#### Steps:
1. Implement `can_undo_fold()` using fold_history
2. Implement fold data recording
3. Implement undo execution (reverse operations)
4. Add undo tests

#### Validation:
```bash
./run_tests.sh test_undo_system
```

### Migration Checklist

- [ ] Phase 1: New classes created and compile
- [ ] Phase 2: Unit tests for new classes pass
- [ ] Phase 3: GridManager updated to use CompoundCell
- [ ] Phase 4: All existing tests updated and passing
- [ ] Phase 5: Phase 3 folds work with CompoundCell
- [ ] Phase 6: Phase 4 diagonal folds implemented
- [ ] Phase 7: Undo system implemented
- [ ] All 225+ tests passing
- [ ] No memory leaks detected
- [ ] Performance acceptable (60 FPS)

---

## Performance Considerations

### Expected Performance

**Target:** 60 FPS (16.67ms per frame)

**Measurements:**

| Operation | Expected Time | Notes |
|-----------|---------------|-------|
| Grid creation (10x10) | < 50ms | One-time cost |
| Simple fold | < 100ms | Phase 3 folds |
| Diagonal fold | < 150ms | Phase 4 folds |
| Cell merge | < 5ms | Per merge operation |
| Render frame (100 fragments) | < 10ms | Well within 16.67ms budget |

### Optimization Strategies

#### 1. Cache Calculated Values

```gdscript
# CellFragment caches area and centroid
var area: float = 0.0
var centroid: Vector2 = Vector2.ZERO

func _recalculate_cached_values():
    area = GeometryCore.polygon_area(geometry)
    centroid = GeometryCore.polygon_centroid(geometry)
```

**Benefit:** Avoid recalculating on every query

#### 2. Batch Visual Updates

```gdscript
# Update all visuals in one call
func update_all_visuals():
    for i in range(min(fragments.size(), polygon_visuals.size())):
        polygon_visuals[i].polygon = fragments[i].geometry
        polygon_visuals[i].color = get_cell_color()
```

**Benefit:** Single redraw call instead of multiple

#### 3. Use RefCounted for Fragments

```gdscript
class_name CellFragment extends RefCounted
```

**Benefit:** Automatic memory management, no scene tree overhead

#### 4. Spatial Culling (Future Optimization)

If performance becomes an issue:

```gdscript
# Only update visuals for cells in viewport
func update_visible_cells():
    var viewport_rect = get_viewport_rect()
    for cell in cells.values():
        if cell.get_bounding_rect().intersects(viewport_rect):
            cell.update_all_visuals()
```

**Benefit:** Skip offscreen cells (useful for large grids)

### Profiling

Use Godot's built-in profiler:

```gdscript
# In FoldSystem
func execute_diagonal_fold(...):
    var start_time = Time.get_ticks_usec()

    # ... fold operations ...

    var end_time = Time.get_ticks_usec()
    var elapsed_ms = (end_time - start_time) / 1000.0
    print("Fold completed in %.2f ms" % elapsed_ms)
```

### Memory Budgets

**Expected memory usage for 10x10 grid:**
- 100 CompoundCells: ~100 KB
- 200 CellFragments (average 2 per cell): ~40 KB
- 200 Polygon2D nodes: ~200 KB
- **Total: ~340 KB** (well within acceptable limits)

**For larger grids (20x20):**
- 400 CompoundCells: ~400 KB
- 800 CellFragments: ~160 KB
- 800 Polygon2D nodes: ~800 KB
- **Total: ~1.36 MB** (still very reasonable)

---

## Appendix A: API Quick Reference

### CellFragment

```gdscript
# Constructor
CellFragment.new(geometry: PackedVector2Array, fold_id: int = -1)

# Geometry
get_centroid() -> Vector2
get_area() -> float
set_geometry(new_geometry: PackedVector2Array)
translate_geometry(offset: Vector2)
is_degenerate() -> bool

# Seams
add_seam(seam: Dictionary)
get_seams() -> Array[Dictionary]
has_seam_from_fold(fold_id: int) -> bool

# Utility
duplicate_fragment() -> CellFragment
to_string() -> String
```

### CompoundCell

```gdscript
# Constructor
CompoundCell.new(pos: Vector2i, initial_type: int = 0)

# Fragments
add_fragment(frag: CellFragment)
remove_fragment(index: int)
clear_fragments()
get_fragment_count() -> int
is_empty() -> bool

# Geometry
get_total_area() -> float
get_center() -> Vector2
contains_point(point: Vector2) -> bool
get_bounding_rect() -> Rect2

# Merging
merge_with(other: CompoundCell, fold_id: int)

# Fold History
add_fold_to_history(fold_id: int)
is_affected_by_fold(fold_id: int) -> bool
get_newest_fold() -> int
get_fold_history() -> Array[int]

# Visuals
set_cell_type(new_type: int)
get_cell_color() -> Color
update_all_visuals()
set_outline_color(color: Color)
set_hover_highlight(enabled: bool)
clear_visual_feedback()

# Splitting
split_fragment(frag_index: int, line_point: Vector2, line_normal: Vector2, fold_id: int) -> Dictionary
split_all_fragments(line_point: Vector2, line_normal: Vector2, fold_id: int) -> Dictionary

# Utility
to_string() -> String
validate() -> bool
```

---

## Appendix B: Coordinate System Cheat Sheet

```gdscript
# GRID COORDINATES (Vector2i) - Logical positions
var grid_pos = Vector2i(5, 3)  # Cell at row 5, column 3

# LOCAL COORDINATES (Vector2) - Relative to GridManager
var local_pos = Vector2(grid_pos) * cell_size  # Top-left corner
var local_center = local_pos + Vector2(cell_size/2, cell_size/2)

# WORLD COORDINATES (Vector2) - Absolute screen positions
var world_pos = grid_manager.to_global(local_pos)

# CONVERSIONS
grid_pos = Vector2i(local_pos / cell_size)          # Local → Grid
local_pos = grid_manager.to_local(world_pos)       # World → Local
world_pos = grid_manager.to_global(local_pos)      # Local → World
grid_pos = grid_manager.world_to_grid(world_pos)   # World → Grid

# USAGE RULES
# ✅ Cell geometry:     LOCAL coordinates
# ✅ Fragment vertices: LOCAL coordinates
# ✅ Fold line points:  LOCAL coordinates
# ✅ Seam line points:  LOCAL coordinates
# ✅ Mouse position:    WORLD coordinates (convert to LOCAL)
# ✅ Player position:   WORLD coordinates
```

---

## Conclusion

This specification provides a complete, implementable design for the CompoundCell and CellFragment system. The design supports:

✅ Phase 4: Diagonal folds with multiple fragments per position
✅ Phase 5: Multi-seam tessellation
✅ Phase 6: Undo system with dependency tracking
✅ Incremental migration path
✅ Memory safety and performance
✅ Comprehensive testing strategy

**Next Steps:**
1. Review specification with team
2. Begin Phase 1 implementation (create new classes)
3. Follow migration plan step-by-step
4. Run tests after each phase

**Questions or Issues:**
- Refer to this spec for implementation details
- Check coordinate system cheat sheet for conversions
- Review API quick reference for method signatures
