# Cell Data Structure Design for Merging, Multi-Seam, and Undo Support

## Executive Summary

**Recommendation**: Implement a **CompoundCell system** with **CellFragment** components to support:
- Multiple geometric fragments at the same grid position (Phase 4, 5)
- Merge tracking and history (Phase 6 undo)
- Fold dependency validation (Phase 6 undo)
- Cell type merging when different types overlap

## Current Implementation Analysis

### Existing Structure
```gdscript
class_name Cell extends Node2D:
    var grid_position: Vector2i
    var geometry: PackedVector2Array
    var cell_type: int = 0
    var is_partial: bool = false
    var seams: Array[Dictionary] = []
    var polygon_visual: Polygon2D

# GridManager storage
var cells: Dictionary = {}  # Vector2i -> Cell
```

### Critical Problems Identified

#### Problem 1: Single Cell Per Position Limitation
- **Issue**: After diagonal folds, multiple cell fragments can occupy the same grid position
- **Current behavior**: Dictionary with `Vector2i` keys can only store ONE cell per position
- **Impact**: Overwrites prevent proper merging, causes data loss

#### Problem 2: No Merge Tracking
- **Issue**: When cells overlap during folds, we simply overwrite the old cell
- **Impact**: Cannot track which original cells contributed to merged state
- **Undo requirement**: Need to know source cells to reverse merge operations

#### Problem 3: No Identity or Lineage Tracking
- **Issue**: When a cell splits, new cells have no link to their parent
- **Impact**: Cannot determine if two fragments came from the same original cell
- **Undo requirement**: Must track cell lineage for dependency checking

#### Problem 4: No Fold History Per Cell
- **Issue**: No record of which folds affected each cell
- **Impact**: Cannot implement "strict undo ordering" rule from Phase 6
- **Requirement**: "Can only undo a fold if it's the newest fold affecting ALL its cells"

#### Problem 5: Memory Management Complexity
- **Issue**: Need to free Node2D objects when cells are removed/merged, but preserve data for undo
- **Current risk**: Memory leaks if nodes aren't freed, data loss if freed too early

## Requirements Analysis

### Phase 4: Geometric Folding
- Cells split by diagonal fold lines into multiple fragments
- Fragments shift to new positions
- **Multiple fragments can end up at the same grid position** (THE KEY REQUIREMENT)
- Must handle fragment geometry in LOCAL coordinates

### Phase 5: Multi-Seam Handling
- Multiple folds create intersecting seams through same cell
- Tessellation approach: subdivide cells into convex regions
- Each region is essentially a fragment with its own geometry
- **Need to track multiple fragments per cell** (confirms Phase 4 requirement)

### Phase 6: Undo System
From implementation plan:
```gdscript
func can_undo_fold(fold_id: int) -> bool:
    var fold = get_fold(fold_id)
    # A fold can only be undone if it's the newest fold
    # affecting ALL its cells
    for cell_id in fold.affected_cells:
        var cell = get_cell(cell_id)
        for seam in cell.seams:
            var seam_fold = seam_to_fold_map[seam.id]
            if seam_fold.timestamp > fold.timestamp:
                return false  # Blocked by newer fold
    return true
```

**Requirements**:
1. Track fold_id for each fold operation
2. Track which cells each fold affected
3. Track fold history per cell (chronologically ordered)
4. Ability to query "newest fold" for each cell
5. Store enough data to reverse fold operations

### Additional Requirements
- **Coordinate system consistency**: All geometry in LOCAL coordinates (relative to GridManager)
- **Cell type merging**: When different types overlap, need merge rules (e.g., goal > wall > water > empty)
- **Visual rendering**: Each fragment needs its own Polygon2D visual
- **Player queries**: Must efficiently determine if player is on a cell
- **Memory efficiency**: Don't keep infinite history, but enough for reasonable undo depth

## Design Options Evaluated

### Option 1: Array of Cells per Position ❌
```gdscript
var cells: Dictionary = {}  # Vector2i -> Array[Cell]
```

**Pros**:
- Minimal change to existing code
- Allows multiple cells at same position

**Cons**:
- No clear parent-child relationships between fragments
- Hard to track which fragments came from same original cell
- Merge tracking still unclear
- Doesn't solve fold history problem
- Complex to determine "the cell" at a position for player queries

**Verdict**: Insufficient for our needs

### Option 2: Cell with Fragment Array ❌
```gdscript
class_name Cell extends Node2D:
    var grid_position: Vector2i
    var cell_type: int
    var fragments: Array[PackedVector2Array]  # Multiple geometries
```

**Pros**:
- Keeps existing grid structure
- Allows multiple geometries per cell

**Cons**:
- Loses fragment-level seam tracking (needed for Phase 5)
- No fragment-level fold history
- When do we merge Cell objects vs fragments?
- Doesn't provide clear merge semantics

**Verdict**: Better, but still insufficient

### Option 3: CompoundCell with CellFragment Components ✅ RECOMMENDED
```gdscript
class_name CellFragment:
    var geometry: PackedVector2Array      # Polygon vertices (LOCAL coords)
    var seam_data: Array[Dictionary]      # Seams bordering this fragment
    var fold_created: int                 # Fold ID that created this fragment
    var area: float                       # Cached for performance

class_name CompoundCell extends Node2D:
    var grid_position: Vector2i              # Current logical position
    var cell_type: int                       # Merged/dominant type
    var fragments: Array[CellFragment] = []  # All geometric pieces here
    var source_positions: Array[Vector2i] = [] # Original grid positions
    var fold_history: Array[int] = []        # Fold IDs chronologically
    var polygon_visuals: Array[Polygon2D] = [] # Visual per fragment
```

**Pros**:
- ✅ Natural representation of multiple fragments at same position
- ✅ Clear merge semantics via `source_positions`
- ✅ Fold history tracked per compound cell
- ✅ Fragment-level seam tracking for Phase 5
- ✅ Maintains grid-based indexing `Dictionary[Vector2i, CompoundCell]`
- ✅ Easy to query "newest fold" via `fold_history[-1]`
- ✅ Each fragment has its own visual representation
- ✅ Weighted centroid calculation for player positioning
- ✅ Clear cell type merging logic

**Cons**:
- Requires significant refactoring
- More complex than current simple Cell
- Need to manage multiple Polygon2D children

**Verdict**: Best fit for all requirements

### Option 4: Immutable Fold History with Computed State ❌
```gdscript
var initial_grid: Dictionary
var fold_transforms: Array[FoldTransform] = []
var cached_state: Dictionary  # Recompute when dirty
```

**Pros**:
- Undo is trivial (pop transform, recompute)
- Perfect history tracking
- Functional programming style

**Cons**:
- ❌ Performance: must recompute entire grid state after each change
- ❌ Complex caching strategy needed
- ❌ Difficult to optimize for 60 FPS rendering
- ❌ Overkill for this project's scope

**Verdict**: Theoretically elegant but impractical

## Recommended Design: CompoundCell System

### Core Data Structures

```gdscript
# ============================================================================
# CellFragment - Represents a single geometric piece
# ============================================================================
class_name CellFragment extends RefCounted

var geometry: PackedVector2Array      # Polygon vertices in LOCAL coordinates
var seam_data: Array[Dictionary] = [] # Seams that border this fragment
var fold_created: int = -1            # Fold ID that created this fragment (-1 = original)
var area: float = 0.0                 # Cached area for performance

func _init(geom: PackedVector2Array, fold_id: int = -1):
    geometry = geom
    fold_created = fold_id
    area = GeometryCore.polygon_area(geometry)

func get_centroid() -> Vector2:
    return GeometryCore.polygon_centroid(geometry)

func add_seam(seam: Dictionary):
    seam_data.append(seam)


# ============================================================================
# CompoundCell - Represents all fragments at a grid position
# ============================================================================
class_name CompoundCell extends Node2D

# Logical grid position (where this cell currently is)
var grid_position: Vector2i

# Cell type (determines color, player interaction, etc.)
var cell_type: int = 0  # 0=empty, 1=wall, 2=water, 3=goal

# All geometric fragments at this position
var fragments: Array[CellFragment] = []

# Track which original grid positions merged to create this cell
# Initially just [grid_position], grows when cells merge
var source_positions: Array[Vector2i] = []

# Chronological list of fold IDs that affected this cell
# Last element is the newest fold
var fold_history: Array[int] = []

# Visual representation (one Polygon2D per fragment)
var polygon_visuals: Array[Polygon2D] = []

# Visual feedback for selection/hover
var outline_color: Color = Color.TRANSPARENT
var is_hovered: bool = false


# ============================================================================
# Constructor
# ============================================================================

func _init(pos: Vector2i, initial_type: int = 0):
    grid_position = pos
    cell_type = initial_type
    source_positions = [pos]  # Initially, just itself


# ============================================================================
# Fragment Management
# ============================================================================

## Add a new fragment to this compound cell
func add_fragment(frag: CellFragment):
    fragments.append(frag)

    # Create visual for this fragment
    var polygon = Polygon2D.new()
    polygon.polygon = frag.geometry
    polygon.color = get_cell_color()
    add_child(polygon)
    polygon_visuals.append(polygon)

## Remove all fragments (when cell is deleted)
func clear_fragments():
    fragments.clear()
    for poly in polygon_visuals:
        poly.queue_free()
    polygon_visuals.clear()


# ============================================================================
# Merge Operations
# ============================================================================

## Merge another CompoundCell into this one
## Used when cells shift to overlap during folds
func merge_with(other: CompoundCell, fold_id: int):
    # Merge all fragments
    for frag in other.fragments:
        add_fragment(frag)

    # Merge source positions (union, no duplicates)
    for pos in other.source_positions:
        if pos not in source_positions:
            source_positions.append(pos)

    # Merge fold histories (union, maintaining chronological order)
    # This is important for undo dependency checking
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

    # Update visuals
    update_all_visuals()

## Determine cell type when merging
## Priority: goal > wall > water > empty
func _merge_cell_types(type_a: int, type_b: int) -> int:
    const PRIORITY = {3: 4, 1: 3, 2: 2, 0: 1}  # goal, wall, water, empty
    if PRIORITY.get(type_a, 0) >= PRIORITY.get(type_b, 0):
        return type_a
    return type_b


# ============================================================================
# Geometry Queries
# ============================================================================

## Get total area of all fragments
func get_total_area() -> float:
    var total = 0.0
    for frag in fragments:
        total += frag.area
    return total

## Get weighted centroid of all fragments
## Used for player positioning
func get_center() -> Vector2:
    if fragments.is_empty():
        # Fallback: use grid position
        var cell_size = get_parent().cell_size if get_parent() else 64.0
        return Vector2(grid_position) * cell_size

    var weighted_pos = Vector2.ZERO
    var total_area = 0.0

    for frag in fragments:
        var frag_area = frag.area
        var frag_centroid = frag.get_centroid()
        weighted_pos += frag_centroid * frag_area
        total_area += frag_area

    if total_area > GeometryCore.EPSILON:
        return weighted_pos / total_area

    # Fallback for degenerate case
    return fragments[0].get_centroid()

## Check if a point (in LOCAL coordinates) is inside any fragment
func contains_point(point: Vector2) -> bool:
    for frag in fragments:
        if GeometryCore.point_in_polygon(point, frag.geometry):
            return true
    return false


# ============================================================================
# Fold History Queries (for Undo System)
# ============================================================================

## Check if this cell was affected by a specific fold
func is_affected_by_fold(fold_id: int) -> bool:
    return fold_id in fold_history

## Get the newest (most recent) fold that affected this cell
## Returns -1 if no folds have affected this cell
func get_newest_fold() -> int:
    if fold_history.is_empty():
        return -1
    return fold_history[-1]

## Record that this cell was affected by a fold
func add_fold_to_history(fold_id: int):
    if fold_id not in fold_history:
        fold_history.append(fold_id)


# ============================================================================
# Visual Update Methods
# ============================================================================

func update_all_visuals():
    for i in range(polygon_visuals.size()):
        if i < fragments.size():
            polygon_visuals[i].polygon = fragments[i].geometry
            polygon_visuals[i].color = get_cell_color()

func get_cell_color() -> Color:
    match cell_type:
        0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
        1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
        2: return Color(0.2, 0.4, 1.0)  # Water - blue
        3: return Color(0.2, 1.0, 0.2)  # Goal - green
        _: return Color(1.0, 1.0, 1.0)  # Default

func set_cell_type(new_type: int):
    cell_type = new_type
    update_all_visuals()

func set_outline_color(color: Color):
    outline_color = color
    queue_redraw()

func set_hover_highlight(enabled: bool):
    is_hovered = enabled
    queue_redraw()

func clear_visual_feedback():
    outline_color = Color.TRANSPARENT
    is_hovered = false
    queue_redraw()

func _draw():
    # Draw hover effect
    if is_hovered:
        for frag in fragments:
            draw_colored_polygon(frag.geometry, Color(1, 1, 0, 0.3))

    # Draw outline if selected
    if outline_color.a > 0:
        for frag in fragments:
            var outline_points = frag.geometry.duplicate()
            outline_points.append(frag.geometry[0])  # Close the loop
            draw_polyline(outline_points, outline_color, 4.0)


# ============================================================================
# Splitting Support (for Phase 4)
# ============================================================================

## Split a specific fragment by a fold line
## Returns new fragments for both sides
func split_fragment(frag_index: int, line_point: Vector2, line_normal: Vector2, fold_id: int) -> Dictionary:
    if frag_index < 0 or frag_index >= fragments.size():
        push_error("Invalid fragment index")
        return {}

    var frag = fragments[frag_index]
    var split_result = GeometryCore.split_polygon_by_line(frag.geometry, line_point, line_normal)

    if split_result.intersections.size() == 0:
        push_error("Fragment does not intersect fold line")
        return {}

    # Create new fragments for each side
    var left_frag = CellFragment.new(split_result.left, fold_id)
    var right_frag = CellFragment.new(split_result.right, fold_id)

    # Copy seam data to both fragments
    for seam in frag.seam_data:
        left_frag.add_seam(seam.duplicate())
        right_frag.add_seam(seam.duplicate())

    # Add new seam data for this split
    var new_seam = {
        "fold_id": fold_id,
        "line_point": line_point,
        "line_normal": line_normal,
        "intersection_points": split_result.intersections
    }
    left_frag.add_seam(new_seam)
    right_frag.add_seam(new_seam)

    return {
        "left": left_frag,
        "right": right_frag,
        "intersections": split_result.intersections
    }
```

### GridManager Changes

```gdscript
class_name GridManager extends Node2D

var grid_size := Vector2i(10, 10)
var cell_size := 64.0

# CHANGED: Still Dictionary[Vector2i, Cell] but Cell is now CompoundCell
var cells: Dictionary = {}  # Vector2i -> CompoundCell

var selected_anchors: Array[Vector2i] = []
var grid_origin: Vector2 = Vector2.ZERO


# ============================================================================
# Grid Initialization
# ============================================================================

func create_grid() -> void:
    for y in range(grid_size.y):
        for x in range(grid_size.x):
            var grid_pos = Vector2i(x, y)

            # Create CompoundCell
            var cell = CompoundCell.new(grid_pos, 0)  # Type 0 = empty

            # Create initial square fragment
            var local_pos = Vector2(grid_pos) * cell_size
            var square_geometry = PackedVector2Array([
                local_pos,
                local_pos + Vector2(cell_size, 0),
                local_pos + Vector2(cell_size, cell_size),
                local_pos + Vector2(0, cell_size)
            ])

            var initial_fragment = CellFragment.new(square_geometry, -1)  # -1 = original
            cell.add_fragment(initial_fragment)

            cells[grid_pos] = cell
            add_child(cell)


# ============================================================================
# Cell Queries (mostly unchanged interface)
# ============================================================================

func get_cell(grid_pos: Vector2i) -> CompoundCell:
    return cells.get(grid_pos, null)

func get_cell_at_world_pos(world_pos: Vector2) -> CompoundCell:
    var local_pos = to_local(world_pos)

    # First try simple grid lookup
    var grid_pos = world_to_grid(world_pos)
    var cell = get_cell(grid_pos)
    if cell and cell.contains_point(local_pos):
        return cell

    # For complex cases, check all cells
    for c in cells.values():
        if c.contains_point(local_pos):
            return c

    return null
```

### FoldSystem Changes

```gdscript
class_name FoldSystem extends Node

var grid_manager: GridManager
var player: Player
var next_fold_id: int = 0
var fold_history: Array[Dictionary] = []


# ============================================================================
# Fold Execution (example for diagonal fold)
# ============================================================================

func execute_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i, fold_angle: float):
    var fold_id = next_fold_id
    next_fold_id += 1

    # Calculate fold line
    var fold_line = _calculate_fold_line(anchor1, anchor2, fold_angle)

    # Classify all cells
    var cells_to_split = []
    var cells_to_remove = []
    var cells_to_shift = []

    for pos in grid_manager.cells.keys():
        var cell = grid_manager.cells[pos]
        var classification = _classify_cell(cell, fold_line)

        match classification:
            "split": cells_to_split.append(pos)
            "removed": cells_to_remove.append(pos)
            "shifted": cells_to_shift.append(pos)

    # Step 1: Split cells
    for pos in cells_to_split:
        var cell = grid_manager.cells[pos]

        # Split each fragment in the cell
        var left_fragments = []
        var right_fragments = []

        for i in range(cell.fragments.size()):
            var split_result = cell.split_fragment(i, fold_line.point, fold_line.normal, fold_id)
            if not split_result.is_empty():
                left_fragments.append(split_result.left)
                right_fragments.append(split_result.right)

        # Keep left side at current position
        cell.clear_fragments()
        cell.add_fold_to_history(fold_id)
        for frag in left_fragments:
            cell.add_fragment(frag)

        # Create new cell for right side at shifted position
        var shifted_pos = _calculate_shifted_position(pos, anchor1, anchor2)
        var new_cell = CompoundCell.new(shifted_pos, cell.cell_type)
        new_cell.source_positions = cell.source_positions.duplicate()
        new_cell.add_fold_to_history(fold_id)

        for frag in right_fragments:
            # Update geometry to new position
            frag.geometry = _shift_geometry(frag.geometry, shift_vector)
            new_cell.add_fragment(frag)

        # Handle merging at new position
        if grid_manager.cells.has(shifted_pos):
            var existing = grid_manager.cells[shifted_pos]
            existing.merge_with(new_cell, fold_id)
            new_cell.queue_free()
        else:
            grid_manager.cells[shifted_pos] = new_cell
            grid_manager.add_child(new_cell)

    # Step 2: Remove cells in removed region
    for pos in cells_to_remove:
        var cell = grid_manager.cells[pos]
        grid_manager.cells.erase(pos)
        cell.queue_free()

    # Step 3: Shift unsplit cells
    for pos in cells_to_shift:
        var cell = grid_manager.cells[pos]
        var new_pos = _calculate_shifted_position(pos, anchor1, anchor2)

        # Update geometry and metadata
        cell.grid_position = new_pos
        cell.add_fold_to_history(fold_id)

        for frag in cell.fragments:
            frag.geometry = _shift_geometry(frag.geometry, shift_vector)

        cell.update_all_visuals()

        # Handle merging
        grid_manager.cells.erase(pos)
        if grid_manager.cells.has(new_pos):
            var existing = grid_manager.cells[new_pos]
            existing.merge_with(cell, fold_id)
            cell.queue_free()
        else:
            grid_manager.cells[new_pos] = cell

    # Record fold
    fold_history.append({
        "fold_id": fold_id,
        "anchor1": anchor1,
        "anchor2": anchor2,
        "affected_cells": cells_to_split + cells_to_shift,
        # ... additional data for undo
    })


# ============================================================================
# Undo System Support
# ============================================================================

func can_undo_fold(fold_id: int) -> bool:
    # Find the fold in history
    var fold_data = null
    for f in fold_history:
        if f.fold_id == fold_id:
            fold_data = f
            break

    if not fold_data:
        return false

    # Check if this fold is the newest fold for ALL affected cells
    for cell_pos in fold_data.affected_cells:
        if not grid_manager.cells.has(cell_pos):
            continue  # Cell might have been removed by later fold

        var cell = grid_manager.cells[cell_pos]
        if cell.get_newest_fold() != fold_id:
            return false  # This cell has been affected by a newer fold

    return true
```

## Migration Strategy

### Phase 1: Create New Classes (No Breaking Changes)
1. Create `CellFragment` class
2. Create `CompoundCell` class (initially with single fragment)
3. Add to project, ensure they compile

### Phase 2: Migrate GridManager
1. Change cell creation to use CompoundCell
2. Update grid initialization to create single-fragment cells
3. Run existing tests - should still pass

### Phase 3: Update FoldSystem for Phase 3 Folds
1. Modify horizontal/vertical fold to work with CompoundCell
2. Add fold_history tracking
3. Implement merge_with() logic
4. Run Phase 3 tests - should still pass

### Phase 4: Implement Diagonal Folds
1. Implement fragment splitting logic
2. Handle multi-fragment cells
3. Test with Phase 4 requirements

### Phase 5: Implement Undo System
1. Use fold_history for dependency checking
2. Implement can_undo_fold()
3. Implement undo execution

## Benefits of This Approach

1. **✅ Supports Multiple Fragments**: Natural representation of overlapping cells
2. **✅ Clear Merge Semantics**: `source_positions` and `merge_with()` handle all cases
3. **✅ Fold History Tracking**: Built-in support for undo dependency checking
4. **✅ Phase 5 Ready**: Fragments map directly to tessellated regions
5. **✅ Incremental Migration**: Can migrate gradually without breaking existing code
6. **✅ Maintains Grid Structure**: Still `Dictionary[Vector2i, CompoundCell]` for queries
7. **✅ Memory Safe**: Clear lifecycle with `queue_free()` when merging
8. **✅ Coordinate Consistency**: All geometry in LOCAL coordinates

## Potential Concerns and Mitigations

### Concern: Complexity
- **Mitigation**: Start with single fragment per cell, add complexity gradually
- **Mitigation**: Good documentation and clear method names
- **Mitigation**: Comprehensive unit tests for each method

### Concern: Performance
- **Mitigation**: Cache area calculations in fragments
- **Mitigation**: Use weighted centroids instead of recomputing
- **Mitigation**: Profile and optimize hot paths if needed
- **Expected**: Should be fine for 10x10 grid, even with 100+ fragments total

### Concern: Memory Usage
- **Mitigation**: Fragments are lightweight (just geometry + metadata)
- **Mitigation**: Don't keep infinite fold history (can cap at N recent folds)
- **Expected**: Much lower than keeping full cell copies for undo

### Concern: Visual Rendering
- **Mitigation**: One Polygon2D per fragment is standard Godot pattern
- **Mitigation**: Can batch if performance becomes issue
- **Expected**: Should easily hit 60 FPS for reasonable fragment counts

## Alternative Considered: Simpler Fragment Tracking

Keep current Cell structure, add:
```gdscript
var source_positions: Array[Vector2i] = []
var fold_history: Array[int] = []
```

**Why rejected**:
- Doesn't solve multiple-geometries-per-position problem
- Phase 5 tessellation would require fragments anyway
- Would need another refactor later

## Conclusion

The **CompoundCell with CellFragment** system provides:
- ✅ Clear, maintainable design
- ✅ Supports all Phase 4, 5, 6 requirements
- ✅ Incremental migration path
- ✅ Good performance characteristics
- ✅ Natural representation of game state

**Recommendation**: Proceed with this design for Phase 4 implementation.
