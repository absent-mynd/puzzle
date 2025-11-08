# Phase 5: Multi-Seam Handling - UPDATED Implementation Specification

**Status:** ✅ Complete
**Completed:** 2025-11-08
**Priority:** P1 (Critical Path)
**Actual Time:** ~5-7 hours (2h prep + 3-5h core)
**Complexity:** ⭐⭐⭐⭐ (High)
**Dependencies:** Phase 4 (Geometric Folding) ✅ Complete

**UPDATED DESIGN:** Multi-polygon rendering instead of geometric union

---

## Overview

Phase 5 implements the ability for cells to handle multiple intersecting fold seams. The **updated approach** keeps multiple separate polygons within a single cell, rendering each independently to maintain visual distinction of cell types.

**Core Concept:** 
- A cell can contain multiple polygons (from different merged cells)
- Each polygon retains its original cell type for visual rendering
- The cell acts as a single logical unit for game/player interaction
- Game logic can query cell composition (which types are present)

**Benefits over polygon union:**
- ✅ Simpler implementation (no complex geometric merging)
- ✅ Maintains visual fidelity (can see original cell types)
- ✅ Easier debugging and testing
- ✅ More flexible for future features
- ✅ Better performance (no expensive union operations)

---

## Updated Architecture

### Cell Structure Changes

**From:** Single geometry polygon
```gdscript
class Cell:
    var geometry: PackedVector2Array  # Single polygon
    var cell_type: int  # Single type
```

**To:** Multiple geometry polygons
```gdscript
class Cell:
    var geometry_pieces: Array[CellPiece]  # Multiple polygons
    var cell_type: int  # Primary/dominant type (for simple queries)
    
class CellPiece:
    var geometry: PackedVector2Array
    var cell_type: int
    var source_fold_id: int  # Which fold created this piece
    var seams: Array[Seam]  # Seams bounding this piece
```

---

## Prerequisites (2 hours - SIMPLIFIED)

### Task 1: Implement Seam Class (30-45 min)

**Same as original spec** - No changes needed.

---

### Task 2: Enhanced Fold History (45-60 min)

**Same as original spec** - No changes needed.

---

### Task 3: Implement CellPiece Class (30-45 min) **[NEW - REPLACES POLYGON UNION]**

**File:** `scripts/core/CellPiece.gd`

**Implementation:**
```gdscript
class_name CellPiece extends Node2D

## CellPiece
##
## Represents one geometric piece within a Cell that may contain multiple pieces.
## Each piece has its own geometry and cell type, allowing cells to be composed
## of multiple types while acting as a single logical unit.

## The geometry of this piece (LOCAL coordinates)
var geometry: PackedVector2Array = PackedVector2Array()

## Cell type of this piece (0=empty, 1=wall, 2=water, 3=goal)
var cell_type: int = 0

## ID of the fold that created this piece
var source_fold_id: int = -1

## Seams that bound this piece
var seams: Array[Seam] = []

## Visual representation of this piece
var polygon_visual: Polygon2D = null


## Constructor
func _init(
    p_geometry: PackedVector2Array = PackedVector2Array(),
    p_cell_type: int = 0,
    p_source_fold_id: int = -1
):
    geometry = p_geometry
    cell_type = p_cell_type
    source_fold_id = p_source_fold_id


func _ready():
    create_visual()


## Create visual representation of this piece
func create_visual():
    if polygon_visual:
        polygon_visual.queue_free()

    polygon_visual = Polygon2D.new()
    polygon_visual.polygon = geometry
    polygon_visual.color = get_color_for_type(cell_type)
    add_child(polygon_visual)


## Get color based on cell type
func get_color_for_type(type: int) -> Color:
    match type:
        0:  # Empty
            return Color(0.95, 0.95, 0.95, 0.8)  # Light gray (slightly transparent)
        1:  # Wall
            return Color(0.3, 0.3, 0.3, 1.0)  # Dark gray
        2:  # Water
            return Color(0.2, 0.5, 0.8, 0.7)  # Blue (transparent)
        3:  # Goal
            return Color(1.0, 0.8, 0.0, 0.9)  # Gold
        _:
            return Color.WHITE


## Update visual to reflect current state
func update_visual():
    if polygon_visual:
        polygon_visual.polygon = geometry
        polygon_visual.color = get_color_for_type(cell_type)


## Get area of this piece
func get_area() -> float:
    return GeometryCore.polygon_area(geometry)


## Get centroid of this piece
func get_center() -> Vector2:
    return GeometryCore.polygon_centroid(geometry)


## Serialize to dictionary
func to_dict() -> Dictionary:
    return {
        "geometry": _serialize_geometry(geometry),
        "cell_type": cell_type,
        "source_fold_id": source_fold_id,
        "seams": _serialize_seams(seams)
    }


## Deserialize from dictionary
static func from_dict(dict: Dictionary) -> CellPiece:
    var piece = CellPiece.new()
    piece.geometry = _deserialize_geometry(dict.get("geometry", []))
    piece.cell_type = dict.get("cell_type", 0)
    piece.source_fold_id = dict.get("source_fold_id", -1)

    if dict.has("seams"):
        for seam_dict in dict["seams"]:
            piece.seams.append(Seam.from_dict(seam_dict))

    return piece


## Helper: Serialize geometry
static func _serialize_geometry(geom: PackedVector2Array) -> Array:
    var result = []
    for v in geom:
        result.append({"x": v.x, "y": v.y})
    return result


## Helper: Deserialize geometry
static func _deserialize_geometry(arr: Array) -> PackedVector2Array:
    var result = PackedVector2Array()
    for item in arr:
        result.append(Vector2(item.x, item.y))
    return result


## Helper: Serialize seams
static func _serialize_seams(seams_array: Array) -> Array:
    var result = []
    for seam in seams_array:
        if seam is Seam:
            result.append(seam.to_dict())
    return result


## Duplicate this piece
func duplicate_piece() -> CellPiece:
    var dup = CellPiece.new(geometry.duplicate(), cell_type, source_fold_id)
    for seam in seams:
        dup.seams.append(seam.duplicate_seam())
    return dup
```

**Test File:** `scripts/tests/test_cell_piece.gd`

```gdscript
extends GutTest

func test_cell_piece_creation():
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0),
        Vector2(64, 64), Vector2(0, 64)
    ])

    var piece = CellPiece.new(geometry, 1, 0)

    assert_not_null(piece, "CellPiece should be created")
    assert_eq(piece.cell_type, 1, "Cell type should be set")
    assert_eq(piece.geometry.size(), 4, "Geometry should have 4 vertices")


func test_get_color_for_type():
    var piece = CellPiece.new()

    var wall_color = piece.get_color_for_type(1)
    assert_eq(wall_color, Color(0.3, 0.3, 0.3, 1.0), "Wall should be dark gray")

    var goal_color = piece.get_color_for_type(3)
    assert_eq(goal_color, Color(1.0, 0.8, 0.0, 0.9), "Goal should be gold")


func test_get_area():
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(10, 0),
        Vector2(10, 10), Vector2(0, 10)
    ])

    var piece = CellPiece.new(geometry, 0, -1)
    var area = piece.get_area()

    assert_almost_eq(area, 100.0, 0.1, "10x10 square should have area 100")


func test_serialize_and_deserialize():
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0),
        Vector2(64, 64), Vector2(0, 64)
    ])

    var piece = CellPiece.new(geometry, 2, 5)
    var dict = piece.to_dict()

    assert_has(dict, "cell_type", "Should have cell_type")
    assert_has(dict, "geometry", "Should have geometry")

    var restored = CellPiece.from_dict(dict)

    assert_eq(restored.cell_type, 2, "Cell type should be restored")
    assert_eq(restored.source_fold_id, 5, "Source fold ID should be restored")
    assert_eq(restored.geometry.size(), 4, "Geometry should be restored")


func test_duplicate_piece():
    var geometry = PackedVector2Array([
        Vector2(0, 0), Vector2(64, 0),
        Vector2(64, 64), Vector2(0, 64)
    ])

    var piece = CellPiece.new(geometry, 1, 0)
    var dup = piece.duplicate_piece()

    assert_not_null(dup, "Duplicate should be created")
    assert_eq(dup.cell_type, piece.cell_type, "Cell type should match")
    assert_ne(dup, piece, "Should be different objects")
```

**Acceptance Criteria:**
- ✅ CellPiece class compiles without errors
- ✅ All 5-8 tests pass
- ✅ Visual rendering works
- ✅ Serialization/deserialization correct

---

## Core Implementation (3-5 hours)

### Task 4: Update Cell Class for Multi-Polygon Support (45-60 min)

**File:** `scripts/core/Cell.gd`

**Add to Cell class:**

```gdscript
## Array of geometric pieces that compose this cell
var geometry_pieces: Array[CellPiece] = []

## Legacy geometry accessor (returns combined bounds or first piece)
## DEPRECATED: Use geometry_pieces instead
var geometry: PackedVector2Array:
    get:
        if geometry_pieces.is_empty():
            return PackedVector2Array()
        return geometry_pieces[0].geometry


## Initialize cell with single piece (backward compatible)
func _init_with_geometry(grid_pos: Vector2i, local_pos: Vector2, size: float):
    grid_position = grid_pos

    # Create default square geometry as a single piece
    var square_geom = PackedVector2Array([
        local_pos,
        local_pos + Vector2(size, 0),
        local_pos + Vector2(size, size),
        local_pos + Vector2(0, size)
    ])

    var piece = CellPiece.new(square_geom, cell_type, -1)
    geometry_pieces.append(piece)


## Get all cell types present in this cell
##
## @return: Array of unique cell types
func get_cell_types() -> Array[int]:
    var types: Array[int] = []

    for piece in geometry_pieces:
        if piece.cell_type not in types:
            types.append(piece.cell_type)

    return types


## Check if cell contains a specific type
##
## @param type: Cell type to check for
## @return: true if any piece has this type
func has_cell_type(type: int) -> bool:
    for piece in geometry_pieces:
        if piece.cell_type == type:
            return true
    return false


## Get dominant cell type (most common or by priority)
##
## Priority: Goal > Wall > Water > Empty
##
## @return: Dominant cell type
func get_dominant_type() -> int:
    # Check for goal (highest priority)
    if has_cell_type(3):
        return 3

    # Check for wall
    if has_cell_type(1):
        return 1

    # Check for water
    if has_cell_type(2):
        return 2

    # Default to empty
    return 0


## Get total area of all pieces
func get_total_area() -> float:
    var total = 0.0
    for piece in geometry_pieces:
        total += piece.get_area()
    return total


## Get center of mass of all pieces
func get_center() -> Vector2:
    if geometry_pieces.is_empty():
        return Vector2.ZERO

    var total_area = 0.0
    var weighted_center = Vector2.ZERO

    for piece in geometry_pieces:
        var area = piece.get_area()
        var center = piece.get_center()
        weighted_center += center * area
        total_area += area

    if total_area > 0:
        return weighted_center / total_area
    else:
        return geometry_pieces[0].get_center()


## Update visual representation of all pieces
func update_visual():
    # Clear existing piece visuals
    for child in get_children():
        if child is CellPiece:
            child.queue_free()

    # Create visuals for each piece
    for piece in geometry_pieces:
        add_child(piece)
        piece.create_visual()


## Add a piece to this cell
##
## @param piece: CellPiece to add
func add_piece(piece: CellPiece):
    geometry_pieces.append(piece)
    add_child(piece)


## Remove a piece from this cell
##
## @param piece: CellPiece to remove
func remove_piece(piece: CellPiece):
    geometry_pieces.erase(piece)
    if piece.get_parent() == self:
        remove_child(piece)
```

**Update existing Cell methods:**

```gdscript
## Check if cell has multiple seams
func has_multiple_seams() -> bool:
    var total_seams = 0
    for piece in geometry_pieces:
        total_seams += piece.seams.size()
    return total_seams >= 2


## Get all unique seams across all pieces
func get_all_seams() -> Array[Seam]:
    var all_seams: Array[Seam] = []
    var seam_ids = []

    for piece in geometry_pieces:
        for seam in piece.seams:
            if seam.fold_id not in seam_ids:
                all_seams.append(seam)
                seam_ids.append(seam.fold_id)

    return all_seams
```

**Test File:** Add to `scripts/tests/test_cell.gd`:

```gdscript
func test_multi_piece_cell_creation():
    var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), 64.0)

    # Should have 1 piece by default
    assert_eq(cell.geometry_pieces.size(), 1, "New cell should have 1 piece")


func test_add_piece_to_cell():
    var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), 64.0)

    var new_piece = CellPiece.new(
        PackedVector2Array([Vector2(64, 64), Vector2(128, 64), Vector2(128, 128), Vector2(64, 128)]),
        1,  # Wall
        0
    )

    cell.add_piece(new_piece)

    assert_eq(cell.geometry_pieces.size(), 2, "Cell should have 2 pieces after adding")


func test_get_cell_types():
    var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), 64.0)

    # Add pieces of different types
    var piece1 = CellPiece.new(PackedVector2Array(), 1, 0)  # Wall
    var piece2 = CellPiece.new(PackedVector2Array(), 2, 1)  # Water

    cell.add_piece(piece1)
    cell.add_piece(piece2)

    var types = cell.get_cell_types()

    assert_true(1 in types, "Should contain wall type")
    assert_true(2 in types, "Should contain water type")


func test_get_dominant_type_goal():
    var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), 64.0)

    cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 0))  # Wall
    cell.add_piece(CellPiece.new(PackedVector2Array(), 3, 1))  # Goal

    assert_eq(cell.get_dominant_type(), 3, "Goal should dominate")


func test_get_dominant_type_wall():
    var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), 64.0)

    cell.add_piece(CellPiece.new(PackedVector2Array(), 2, 0))  # Water
    cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 1))  # Wall

    assert_eq(cell.get_dominant_type(), 1, "Wall should dominate over water")


func test_has_cell_type():
    var cell = Cell.new(Vector2i(1, 1), Vector2(64, 64), 64.0)

    cell.add_piece(CellPiece.new(PackedVector2Array(), 2, 0))  # Water

    assert_true(cell.has_cell_type(2), "Should have water type")
    assert_false(cell.has_cell_type(1), "Should not have wall type")
```

**Acceptance Criteria:**
- ✅ Cell can store multiple pieces
- ✅ Each piece renders with correct color
- ✅ Cell type queries work correctly
- ✅ Backward compatibility maintained
- ✅ All tests pass

---

### Task 5: Update Cell Merging to Use Multi-Polygon Approach (30-45 min)

**File:** `scripts/systems/FoldSystem.gd`

**Replace `_merge_cells_simple()` with:**

```gdscript
## Merge two cells by combining their pieces
##
## Instead of geometric union, we keep all pieces separate and transfer
## them from incoming cell to existing cell. This maintains visual distinction
## and allows rendering each piece with its original cell type.
##
## @param existing: Cell already at the position
## @param incoming: Cell being moved to this position  
## @param pos: Grid position where merge occurs
func _merge_cells_multi_polygon(existing: Cell, incoming: Cell, pos: Vector2i):
    # Mark both as affected by merge
    existing.is_partial = true
    incoming.is_partial = true

    # Transfer all pieces from incoming to existing
    for piece in incoming.geometry_pieces:
        var piece_copy = piece.duplicate_piece()
        existing.add_piece(piece_copy)

    # Update dominant cell type based on new composition
    existing.cell_type = existing.get_dominant_type()

    # Update visual to show all pieces
    existing.update_visual()

    # Free the incoming cell (its pieces are now in existing)
    incoming.queue_free()

    # Log merge for debugging
    if DEBUG_FOLD_EXECUTION:
        print("Merged cells at %s: now has %d pieces with types %s" % [
            pos,
            existing.geometry_pieces.size(),
            existing.get_cell_types()
        ])
```

**Update diagonal fold to use new merge:**

Change line 1578 from:
```gdscript
_merge_cells_simple(existing, cell, new_pos)
```

To:
```gdscript
_merge_cells_multi_polygon(existing, cell, new_pos)
```

**Test File:** Add to `scripts/tests/test_fold_system.gd`:

```gdscript
func test_merge_combines_pieces():
    grid_manager.generate_grid()

    var cell1 = grid_manager.get_cell(Vector2i(2, 2))
    var cell2 = grid_manager.get_cell(Vector2i(2, 3))

    # Set different types
    cell1.geometry_pieces[0].cell_type = 1  # Wall
    cell2.geometry_pieces[0].cell_type = 2  # Water

    var original_pieces1 = cell1.geometry_pieces.size()
    var original_pieces2 = cell2.geometry_pieces.size()

    # Merge
    fold_system._merge_cells_multi_polygon(cell1, cell2, Vector2i(2, 2))

    # Check pieces combined
    assert_eq(
        cell1.geometry_pieces.size(),
        original_pieces1 + original_pieces2,
        "Pieces should be combined"
    )

    # Check types present
    assert_true(cell1.has_cell_type(1), "Should have wall type")
    assert_true(cell1.has_cell_type(2), "Should have water type")


func test_merge_maintains_visual_distinction():
    grid_manager.generate_grid()

    var cell1 = grid_manager.get_cell(Vector2i(1, 1))
    var cell2 = grid_manager.get_cell(Vector2i(1, 2))

    cell1.geometry_pieces[0].cell_type = 1  # Wall
    cell2.geometry_pieces[0].cell_type = 3  # Goal

    fold_system._merge_cells_multi_polygon(cell1, cell2, Vector2i(1, 1))

    # Dominant type should be goal
    assert_eq(cell1.get_dominant_type(), 3, "Goal should dominate")

    # But wall should still be present
    assert_true(cell1.has_cell_type(1), "Wall should still be present")
```

**Acceptance Criteria:**
- ✅ Cells merge by combining pieces
- ✅ Visual distinction maintained
- ✅ No memory leaks
- ✅ All tests pass

---

### Task 6: Update Player Collision Logic (30 min)

**File:** `scripts/core/Player.gd`

**Update collision detection to check dominant type:**

```gdscript
## Check if player can move to target position
func can_move_to(target_pos: Vector2i) -> bool:
    var cell = grid_manager.get_cell(target_pos)

    if not cell:
        return false  # Out of bounds

    # Check dominant type for collision
    var dominant_type = cell.get_dominant_type()

    # Can't move into walls
    if dominant_type == 1:
        return false

    # Can move into empty, water, or goal
    return true


## Check if player reached goal
func check_goal_reached() -> bool:
    var cell = grid_manager.get_cell(grid_position)

    if not cell:
        return false

    # Check if cell contains goal type
    return cell.has_cell_type(3)
```

**Test File:** Add to `scripts/tests/test_player.gd`:

```gdscript
func test_player_collision_with_multi_type_cell():
    var cell = grid_manager.get_cell(Vector2i(1, 0))

    # Add wall piece
    cell.add_piece(CellPiece.new(PackedVector2Array(), 1, 0))

    # Player should not be able to move into cell with wall
    assert_false(player.can_move_to(Vector2i(1, 0)), "Can't move into wall")


func test_player_goal_detection_multi_type():
    var cell = grid_manager.get_cell(Vector2i(1, 0))

    # Add goal piece along with empty
    cell.add_piece(CellPiece.new(PackedVector2Array(), 3, 0))

    player.grid_position = Vector2i(1, 0)

    # Should detect goal even if cell has multiple types
    assert_true(player.check_goal_reached(), "Should detect goal in multi-type cell")
```

**Acceptance Criteria:**
- ✅ Player collision uses dominant type
- ✅ Goal detection works with multi-type cells
- ✅ All player tests pass

---

### Task 7: Visual Polish and Seam Rendering (1-2 hours)

**File:** `scripts/core/Cell.gd`

**Add seam visualization for multi-piece cells:**

```gdscript
## Visualize all seams across all pieces
func visualize_seams():
    # Remove existing seam visuals
    for child in get_children():
        if child is Line2D and child.name.begins_with("Seam_"):
            child.queue_free()

    # Get all unique seams
    var all_seams = get_all_seams()

    # Create visuals for each seam
    for i in range(all_seams.size()):
        var seam = all_seams[i]
        var endpoints = seam.get_seam_endpoints()

        if endpoints.is_empty():
            continue

        var line = Line2D.new()
        line.name = "Seam_%d" % i
        line.add_point(endpoints[0])
        line.add_point(endpoints[1])
        line.width = 2.0

        # Color code by fold order
        var color_t = float(i) / max(all_seams.size(), 1)
        line.default_color = Color.RED.lerp(Color.BLUE, color_t)
        line.z_index = 10  # Draw on top of pieces

        add_child(line)


## Update visual with multi-piece rendering
func update_visual_multi_piece():
    # Update each piece
    for piece in geometry_pieces:
        piece.update_visual()

    # Show seams if cell has multiple pieces
    if geometry_pieces.size() > 1:
        visualize_seams()
```

**File:** `scripts/core/CellPiece.gd`

**Add border rendering:**

```gdscript
## Add border outline to piece
func add_border():
    if polygon_visual:
        # Add thin outline
        var outline = Line2D.new()
        outline.z_index = 1

        # Trace polygon border
        for i in range(geometry.size()):
            outline.add_point(geometry[i])
        outline.add_point(geometry[0])  # Close the loop

        outline.width = 1.0
        outline.default_color = Color.BLACK.lerp(Color.WHITE, 0.3)

        add_child(outline)
```

**Acceptance Criteria:**
- ✅ Each piece renders with correct color
- ✅ Piece borders visible
- ✅ Seam lines drawn between pieces
- ✅ Multi-piece cells visually distinct

---

## Testing Summary

### Total New Tests: 35-50

| Component | Tests | Priority |
|-----------|-------|----------|
| Seam class | 5-8 | P0 |
| CellPiece class | 5-8 | P0 |
| Enhanced fold history | 8-10 | P0 |
| Multi-piece Cell | 10-15 | P1 |
| Merging | 5-8 | P1 |
| Player collision | 3-5 | P1 |
| Visual | 2-4 | P2 |

**Note:** Removed polygon union tests (10-15) since we're not using geometric union.

**Target:** All 396-411 tests passing (361 current + 35-50 new)

---

## Benefits of Multi-Polygon Approach

### Simpler Implementation
- ✅ No complex geometric union algorithm
- ✅ Fewer edge cases to handle
- ✅ Easier to debug and test
- ✅ ~1-2 hours faster than union approach

### Better Visual Fidelity
- ✅ Can see original cell types
- ✅ Distinguish wall vs. water vs. goal in merged cells
- ✅ Educational for players (see fold history)
- ✅ More intuitive visualization

### More Flexible
- ✅ Easy to query cell composition
- ✅ Game rules can check "contains wall?" vs. "is entirely wall?"
- ✅ Supports future features (e.g., partial water flooding)
- ✅ Better undo support (know which pieces came from which fold)

### Performance
- ✅ No expensive polygon union operations
- ✅ Rendering multiple simple polygons is fast
- ✅ Easier garbage collection (just remove pieces)
- ✅ Better memory locality

---

## Game Logic Examples

### Example 1: Player Movement
```gdscript
# Can move if dominant type is not wall
if cell.get_dominant_type() != WALL:
    player.move_to(target)
```

### Example 2: Water Hazard
```gdscript
# Player drowns if cell contains any water
if cell.has_cell_type(WATER):
    player.trigger_water_hazard()
```

### Example 3: Goal Detection
```gdscript
# Goal reached if cell contains goal type (even if mixed)
if cell.has_cell_type(GOAL):
    level_complete()
```

### Example 4: Complex Rule
```gdscript
# Special rule: safe if cell has both wall and goal
if cell.has_cell_type(WALL) and cell.has_cell_type(GOAL):
    player.safe_zone = true
```

---

## Updated Completion Checklist

### Prerequisites
- [ ] Seam class implemented and tested (5-8 tests)
- [ ] CellPiece class implemented and tested (5-8 tests)
- [ ] Enhanced fold history implemented and tested (8-10 tests)
- [ ] All existing 361 tests still pass

### Core Implementation
- [ ] Cell updated for multi-piece support (10-15 tests)
- [ ] Cell merging uses multi-polygon approach (5-8 tests)
- [ ] Player collision updated (3-5 tests)
- [ ] Seam tracking in fold operations
- [ ] Visual rendering working (2-4 tests)

### Quality Gates
- [ ] All 396-411 tests passing (100%)
- [ ] No memory leaks detected
- [ ] Performance acceptable (<100ms per fold)
- [ ] Visual quality good
- [ ] Code reviewed

---

## Time Estimate Comparison

| Approach | Prep | Core | Total |
|----------|------|------|-------|
| **Polygon Union** (original) | 2-3h | 4-6h | 6-9h |
| **Multi-Polygon** (updated) | 2h | 3-5h | 5-7h |
| **Savings** | 0.5-1h | 1h | 1.5-2h |

**Recommended:** Multi-polygon approach (this spec)

---

**End of Updated Phase 5 Implementation Specification**
