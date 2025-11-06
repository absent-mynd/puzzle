# Phase 4: Diagonal Fold Cell Merging & Shifting Strategy

## Problem Statement

For diagonal folds, we need to:
1. **Merge split cell halves** from the two cut lines
2. **Shift the play region** to bring split halves together
3. **Support future features**: undo (Phase 6), multi-type cells (Phase 8), multi-seam (Phase 5)

## Design Principles

### 1. Tessellation Approach (from specification)
- When seams intersect, subdivide cells into convex regions
- Each region tracks its origin and type
- Seams become edges in the tessellation
- **Most robust for complex scenarios**

### 2. Metadata-First Design for Undo Support
Every cell transformation must track:
- Original state before fold
- Transformation applied
- Fold ID that created the change
- Seam information

### 3. Cell Type Merging Strategy
When different cell types merge:
- **Priority**: Non-empty types take precedence (wall > water > empty)
- **Future**: Support multi-type cells with visual blending
- **Metadata**: Track all merged types for undo

## Geometric Strategy for Diagonal Folds

### The Transform Problem

For diagonal folds, we need to:
1. Remove region between line1 and line2
2. Bring line2 to coincide with line1
3. Merge the split halves

**Key Insight**: The transformation is a **translation** along the fold normal (perpendicular to fold axis).

### Transformation Calculation

```
fold_vector = anchor2 - anchor1
fold_normal = fold_vector.normalized()
shift_vector = fold_vector  // Full overlap - bring anchor2 to anchor1
```

All cells in `kept_right` region shift by `-shift_vector` to collapse the removed region.

### Cell Merging Process

1. **Split cells at line1 and line2**
   - Cells split by line1: keep left half
   - Cells split by line2: keep right half

2. **Apply transformation** to kept_right region
   - Translate by `-shift_vector`
   - Update geometry coordinates
   - Update grid_position (approximate to nearest grid cell)

3. **Merge overlapping cells**
   - Find pairs of cells at same grid position
   - Combine their geometries if they share a seam
   - Track merge in metadata

## Implementation Details

### Data Structures

#### MergeMetadata (stored in Cell.seams)
```gdscript
{
    "type": "merge",           # Distinguish from simple seams
    "fold_id": int,            # For undo tracking
    "merged_from": [Cell],     # Original cells (for undo)
    "merge_line": {            # Where cells merged
        "point": Vector2,
        "normal": Vector2
    },
    "timestamp": int
}
```

#### FoldRecord (enhanced for diagonal)
```gdscript
{
    "fold_id": int,
    "orientation": "diagonal",
    "anchor1": Vector2i,
    "anchor2": Vector2i,
    "cut_lines": Dictionary,
    "removed_cells": Array[Vector2i],
    "split_cells": {           # NEW: Track splits for undo
        "line1_splits": Array[{
            "original": Cell,
            "kept": Cell,
            "removed": Cell
        }],
        "line2_splits": Array[{...}]
    },
    "merged_cells": Array[{     # NEW: Track merges for undo
        "grid_position": Vector2i,
        "left_half": Cell,
        "right_half": Cell,
        "merged_result": Cell
    }],
    "shift_transform": Vector2,  # NEW: For undo
    "timestamp": int
}
```

### Algorithm: execute_diagonal_fold (Enhanced)

```gdscript
func execute_diagonal_fold(anchor1: Vector2i, anchor2: Vector2i):
    # 1. Setup
    var cut_lines = calculate_cut_lines(anchor1_local, anchor2_local)
    var fold_vector = anchor2_local - anchor1_local
    var shift_vector = fold_vector

    # 2. Classify cells
    var cells_by_region = classify_all_cells(cut_lines)

    # 3. Process splits (store halves for merging)
    var line1_split_halves = []  # Will merge with line2 halves
    var line2_split_halves = []  # Will merge with line1 halves

    for cell in cells_by_region.split_line1:
        var split_result = split_cell(cell, line1, keep="left")
        var kept_half = cell  // Modified in place
        var removed_half = split_result.new_cell
        line1_split_halves.append(kept_half)
        removed_half.queue_free()

    for cell in cells_by_region.split_line2:
        var split_result = split_cell(cell, line2, keep="right")
        var kept_half = cell  // Modified in place
        line2_split_halves.append(kept_half)
        removed_half.queue_free()

    # 4. Remove cells in removed region
    remove_cells(cells_by_region.removed)

    # 5. Apply shift transform to kept_right region
    var shifted_cells = []
    for cell in cells_by_region.kept_right:
        shift_cell(cell, -shift_vector)
        shifted_cells.append(cell)

    # Shift line2 split halves (they're part of kept_right)
    for cell in line2_split_halves:
        shift_cell(cell, -shift_vector)

    # 6. Merge split halves
    var merged_cells = []
    for left_half in line1_split_halves:
        for right_half in line2_split_halves:
            if should_merge(left_half, right_half):
                var merged = merge_cells(left_half, right_half, cut_lines)
                merged_cells.append(merged)

    # 7. Update player position if affected
    if player in shifted_region:
        shift_player(player, -shift_vector)

    # 8. Create seam visualization at merge line
    create_merged_seam_visual(cut_lines.line1)  // Line2 moved to line1

    # 9. Record fold with full metadata
    record_fold_with_metadata(...)
```

### Helper: should_merge(cell1, cell2)

Two cells should merge if:
1. They're at the same grid position (after shifting)
2. They share a boundary along the merge line
3. Their geometries touch or overlap

```gdscript
func should_merge(cell1: Cell, cell2: Cell, merge_line: Dictionary) -> bool:
    # Must be at same grid position
    if cell1.grid_position != cell2.grid_position:
        return false

    # Check if their boundaries touch along merge line
    var cell1_boundary = get_boundary_on_line(cell1.geometry, merge_line)
    var cell2_boundary = get_boundary_on_line(cell2.geometry, merge_line)

    # If boundaries overlap, they should merge
    return boundaries_overlap(cell1_boundary, cell2_boundary)
```

### Helper: merge_cells(left_cell, right_cell, cut_lines)

```gdscript
func merge_cells(left_cell: Cell, right_cell: Cell, cut_lines: Dictionary) -> Cell:
    # Combine geometries along seam
    var merged_geometry = combine_geometries_at_seam(
        left_cell.geometry,
        right_cell.geometry,
        cut_lines.line1
    )

    # Determine merged cell type (prioritize non-empty)
    var merged_type = max(left_cell.cell_type, right_cell.cell_type)

    # Create merge metadata
    var merge_metadata = {
        "type": "merge",
        "fold_id": current_fold_id,
        "merged_from": [left_cell.grid_position, right_cell.grid_position],
        "left_type": left_cell.cell_type,
        "right_type": right_cell.cell_type,
        "merge_line": cut_lines.line1,
        "timestamp": Time.get_ticks_msec()
    }

    # Update left_cell to be the merged result
    left_cell.geometry = merged_geometry
    left_cell.cell_type = merged_type
    left_cell.add_seam(merge_metadata)
    left_cell.update_visual()

    # Remove right_cell
    grid_manager.cells.erase(right_cell.grid_position)
    right_cell.queue_free()

    return left_cell
```

## Grid Position Strategy

After shifting, cells may not align perfectly with grid positions. Strategy:

1. **Approximate to nearest grid cell**:
   ```gdscript
   var center = cell.get_center()
   var new_grid_pos = Vector2i(
       round(center.x / cell_size),
       round(center.y / cell_size)
   )
   ```

2. **Handle collisions**:
   - If grid position is occupied, merge with existing cell
   - If geometries don't touch, store as partial cell at that position

3. **Track partial cells**:
   - `is_partial = true` for split or merged cells
   - Grid position is approximate for partial cells

## Future Feature Support

### Undo (Phase 6)
- FoldRecord stores complete before/after state
- Split cell metadata includes original geometry
- Merge metadata tracks both source cells
- Can reconstruct by reversing transformations

### Multi-Type Cells (Phase 8)
- Merge metadata already tracks both cell types
- Visual system can blend based on metadata
- Priority system allows fallback behavior

### Multi-Seam (Phase 5)
- Each seam adds to cell.seams array
- Tessellation can subdivide cells further
- Seam intersections handled by geometry operations
- No limit on number of seams per cell

## Testing Strategy

### Unit Tests
1. Test shift transformation calculation
2. Test cell merging logic
3. Test grid position approximation
4. Test merge metadata creation

### Integration Tests
1. Test complete diagonal fold with merging
2. Test player position updates
3. Test seam visualization at merge line
4. Test overlapping diagonal folds (multi-seam)

### Edge Cases
1. Very small fold angles (near-parallel)
2. Cells that don't merge cleanly
3. Player on merged cell
4. Multiple folds through same region

## Implementation Priority

1. **Phase 4.1**: Basic shifting and merging (this implementation)
2. **Phase 4.2**: Enhanced metadata for undo preparation
3. **Phase 5**: Multi-seam tessellation
4. **Phase 6**: Undo using stored metadata
5. **Phase 8**: Multi-type visualization

## Success Criteria

- [x] Diagonal folds remove region between cut lines
- [ ] Grid shifts to collapse removed region
- [ ] Split halves merge along fold axis
- [ ] Player position updates correctly
- [ ] Seam visualization shows merge line
- [ ] Metadata supports future undo
- [ ] Tests pass for merging and shifting
