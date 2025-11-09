# Independent Unfold System - Refactor Plan

**Date:** 2025-11-09
**Goal:** Allow folds to be unfolded in any order with proper geometric recalculation

## Current Understanding

### Data Structures

**Fold Record:**
```gdscript
{
  "fold_id": int,
  "anchor1": Vector2i,
  "anchor2": Vector2i,
  "removed_cells": Array[Vector2i],        # Cells removed by this fold
  "shifted_positions": Array[Vector2i],    # Positions BEFORE shift
  "orientation": String,                    # "horizontal", "vertical", "diagonal"
  "timestamp": int,
  "cells_state": Dictionary,                # Complete grid state BEFORE fold
  "player_position": Vector2i,              # Player position BEFORE fold
  "fold_count": int
}
```

**Cell Structure:**
- `geometry_pieces`: Array[CellPiece]
  - Each CellPiece has:
    - `geometry`: PackedVector2Array (polygon vertices, LOCAL coords)
    - `cell_type`: int (-1=null, 0=empty, 1=wall, 2=water, 3=goal)
    - `source_fold_id`: int (which fold created this piece)
    - `seams`: Array[Seam] (fold lines within this piece)

**Seam Structure:**
- `line_point`, `line_normal`: Line definition (LOCAL coords)
- `intersection_points`: Where seam crosses cell boundary
- `fold_id`: Which fold created this seam
- `timestamp`: When created
- `fold_type`: "horizontal", "vertical", "diagonal"

### Current Behavior

**UNDO (`undo_fold_by_id`):**
- Full grid state restoration from snapshot
- Restores player position from fold record
- Removes fold from history
- Uses `can_undo_fold_seam_based()` validation (checks seam intersections)

**UNFOLD (`unfold_seam`):**
- Currently: Same as UNDO but doesn't restore player position
- Still does full grid state restoration (deletes all cells, recreates from snapshot)
- Player validation: Blocks if player on seam
- Uses `can_undo_fold_seam_based()` validation

## Naming Confusion Issues

### Functions that need renaming:

1. **`can_undo_fold_seam_based(fold_id)` → Needs better name**
   - Currently used by BOTH undo and unfold
   - Checks if newer seams intersect with target fold's seams
   - For independent unfold, we DON'T want this validation
   - **Suggested rename:** `has_newer_seam_intersections(fold_id)`
   - **New behavior:** Only used for visual feedback, NOT blocking unfold

2. **UNDO doesn't need seam intersection validation**
   - UNDO is full state restore - can always succeed (unless fold not found)
   - Remove validation call from `undo_fold_by_id()`

3. **UNFOLD needs different validation**
   - Keep player-on-seam validation
   - Remove seam intersection validation (allow unfold even with newer seams)

## Independent Unfold Algorithm

### High-Level Steps:

```
1. VALIDATION
   - Check player isn't on seam
   - Find fold record

2. IDENTIFY AFFECTED CELLS
   - Get removed_cells from fold record
   - Get shifted_positions from fold record
   - Find all cells with seams matching fold_id

3. REMOVE TARGET FOLD'S SEAMS
   - For each current cell:
     - For each piece in cell:
       - Filter out seams where seam.fold_id == target fold_id

4. RECALCULATE CELL GEOMETRIES
   - For cells that had seams removed:
     - If cell now has 0 seams:
       - Restore to original square geometry
     - Else if cell has remaining seams:
       - Re-tessellate using remaining seams

5. RESTORE REMOVED CELLS
   - For each position in removed_cells:
     - Get cell data from fold_record.cells_state
     - Create cell at that position
     - Remove target fold's seams
     - Re-apply later folds' seams (if any)

6. REVERSE SHIFTS
   - Calculate inverse shift vector
   - For each shifted position:
     - Move cell back to original position
     - Handle merge if needed

7. HANDLE PLAYER
   - If player on shifted cell, move with cell
   - Otherwise keep position unchanged

8. UPDATE STATE
   - Remove fold from history
   - Remove seam visuals
   - Update fold count
```

### Detailed Implementation Plan

#### Step 1: Remove Seams Function
```gdscript
func remove_seams_from_cells(fold_id: int) -> void:
    for pos in grid_manager.cells.keys():
        var cell = grid_manager.cells[pos]
        for piece in cell.geometry_pieces:
            # Filter out seams matching fold_id
            var remaining_seams = []
            for seam in piece.seams:
                if seam.fold_id != fold_id:
                    remaining_seams.append(seam)
            piece.seams = remaining_seams
```

#### Step 2: Recalculate Cell Geometry Function
```gdscript
func recalculate_cell_geometry_after_seam_removal(cell: Cell, grid_pos: Vector2i) -> void:
    # Collect all remaining unique seams across all pieces
    var all_seams = cell.get_all_seams()

    if all_seams.is_empty():
        # No seams left - restore to original square
        restore_cell_to_square(cell, grid_pos)
    else:
        # Re-tessellate cell using remaining seams
        retessellate_cell_with_seams(cell, grid_pos, all_seams)
```

**HARD PART:** Retessellation algorithm
- Start with full square geometry for grid position
- Apply each seam's cut sequentially
- Each cut may subdivide existing pieces
- Need to track which pieces came from which sides of each seam

#### Step 3: Restore Removed Cells Function
```gdscript
func restore_removed_cells(fold_record: Dictionary) -> void:
    var removed_cells = fold_record["removed_cells"]
    var cells_state = fold_record["cells_state"]
    var target_timestamp = fold_record["timestamp"]

    for removed_pos in removed_cells:
        # Get original cell data from snapshot
        var pos_str = var_to_str(removed_pos)
        var cell_data = cells_state[pos_str]

        # Create cell at removed position
        var cell = create_cell_from_data(removed_pos, cell_data)

        # Remove target fold's seams from restored cell
        remove_seams_from_cell(cell, fold_record["fold_id"])

        # Re-apply later folds' seams (timestamp > target_timestamp)
        reapply_later_seams_to_cell(cell, removed_pos, target_timestamp)

        grid_manager.cells[removed_pos] = cell
        grid_manager.add_child(cell)
```

**CHALLENGE:** `reapply_later_seams_to_cell()` needs to:
- Find all folds with timestamp > target fold
- For each later fold, check if its seams affect this cell
- Re-cut the cell with those seams

#### Step 4: Reverse Shifts Function
```gdscript
func reverse_shifts_for_fold(fold_record: Dictionary) -> void:
    var anchor1 = fold_record["anchor1"]
    var anchor2 = fold_record["anchor2"]
    var shifted_positions = fold_record["shifted_positions"]

    # Calculate inverse shift vector
    var original_shift = anchor2 - anchor1  # What was applied during fold
    var inverse_shift = -original_shift     # Reverse it

    # Process in reverse order to avoid conflicts
    for old_pos in shifted_positions:
        var current_pos = old_pos + original_shift  # Where cell is now
        var cell = grid_manager.cells.get(current_pos)

        if cell:
            # Move cell back to old position
            shift_cell_back(cell, old_pos, inverse_shift)
```

**CHALLENGE:** Handling merges when shifting back
- If cell already exists at target position, need to merge
- Use existing multi-polygon merge logic

## Implementation Order

### Phase 1: Refactoring & Foundation
1. ✅ Create this planning document
2. Rename `can_undo_fold_seam_based()` → `has_newer_seam_intersections()`
3. Remove seam intersection validation from UNDO
4. Keep it for visual feedback only

### Phase 2: Helper Functions
5. Implement `remove_seams_from_cells(fold_id)`
6. Implement `restore_cell_to_square(cell, grid_pos)`
7. Implement `get_all_folds_after_timestamp(timestamp)`

### Phase 3: Geometry Recalculation (HARD)
8. Implement `retessellate_cell_with_seams(cell, grid_pos, seams)`
   - Start with square geometry
   - Apply each seam's cut sequentially
   - Track piece origins

### Phase 4: Cell Restoration (HARD)
9. Implement `restore_removed_cells(fold_record)`
10. Implement `reapply_later_seams_to_cell(cell, pos, target_timestamp)`
   - Find relevant later folds
   - Re-cut cell with their seams

### Phase 5: Shift Reversal
11. Implement `reverse_shifts_for_fold(fold_record)`
12. Handle merge conflicts when shifting back

### Phase 6: Integration
13. Rewrite `unfold_seam()` to use new independent unfold logic
14. Update player position handling
15. Test with simple cases

### Phase 7: Testing & Polish
16. Write comprehensive tests
17. Test edge cases (multiple folds, intersecting seams, etc.)
18. Update documentation

## Key Challenges

### 1. Retessellation Algorithm
**Problem:** Given a cell with multiple seams, reconstruct geometry pieces

**Solution Approach:**
```
Start with: Full square geometry
For each seam in cell.get_all_seams():
    For each existing piece:
        Split piece by seam line
        Create new pieces for each side
    Replace pieces with split versions
```

### 2. Re-applying Later Seams
**Problem:** When restoring removed cell, need to apply seams from folds that came after

**Solution Approach:**
```
Get all folds where timestamp > target fold timestamp
For each later fold:
    Get fold's seams (from fold record or current cells)
    Check if seam passes through restored cell
    If yes, cut cell with that seam
```

### 3. Tracking Fold Effects
**Problem:** Need to know which cells were affected by which folds

**Solution:** Fold records already track:
- `removed_cells`: Cells deleted
- `shifted_positions`: Cells that moved
- Seams in cells track `fold_id`

## Testing Strategy

### Test Cases:

1. **Single Fold Unfold**
   - Fold A → Unfold A
   - Should restore to initial state

2. **Two Independent Folds**
   - Fold A (horizontal) → Fold B (vertical, non-overlapping) → Unfold A
   - Fold B should remain
   - Fold A's effects should be reversed

3. **Two Overlapping Folds**
   - Fold A (horizontal y=5) → Fold B (vertical x=5, crosses A's seam) → Unfold A
   - Fold B's seam should remain
   - Cells with both seams should only have B's seam after unfold

4. **Fold with Removed Cells**
   - Fold A removes cells → Fold B affects nearby area → Unfold A
   - Removed cells should be restored
   - Fold B should remain intact

5. **Shift Reversal**
   - Fold A shifts cells → Fold B modifies shifted cells → Unfold A
   - Cells should shift back
   - Fold B's modifications should move with cells

## Questions to Resolve

1. ✅ **Seam intersection validation:** User confirmed - remove for unfold, only use for visual feedback
2. **Merge conflicts:** When shifting back, if cell exists at target, merge or replace? → Use existing multi-polygon merge logic
3. **Player on shifted cell:** User confirmed - player moves with cell (paper folding behavior)
4. **Null pieces:** How to handle when unfolding? → Remove if they were created by target fold

## Success Criteria

- ✅ Folds can be unfolded in any order
- ✅ Geometry is correctly recalculated
- ✅ Later folds' seams are preserved
- ✅ Removed cells are properly restored
- ✅ Shifts are correctly reversed
- ✅ Player moves with cells (paper folding behavior)
- ✅ All tests pass
- ✅ No memory leaks
