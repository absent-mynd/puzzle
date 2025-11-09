# Phase 6: Undo System - Implementation Specification

**Status:** 📋 Ready to Start
**Priority:** P1 (Critical Path)
**Estimated Time:** 6-8 hours
**Complexity:** ⭐⭐⭐⭐⭐ (Very High)
**Dependencies:** Phase 4 (Geometric Folding) ✅ Complete, Phase 5 (Multi-Seam Handling) ✅ Complete

---

## Overview

Phase 6 implements a dual undo system for the puzzle game:
1. **Seam-Based Undo** (Primary Puzzle Mechanic): Players can click on seams to unfold specific folds
2. **Sequential Undo Button** (QOL Feature): Traditional undo button that reverses all actions in sequence

**Core Innovation:**
Seams can only be clicked at locations where they pass through the center of a grid cell. This creates a spatial constraint that will eventually tie into the player's reach mechanic (future feature).

---

## Existing Infrastructure

The following systems are already in place and can be leveraged:

### 1. Fold History System (FoldSystem.gd)
- `fold_history: Array[Dictionary]` stores complete fold records
- Each record contains:
  - `fold_id`: Unique incrementing ID for the fold
  - `anchor1, anchor2`: Anchor positions used for the fold
  - `removed_cells`: Array of cells removed by this fold
  - `orientation`: "horizontal", "vertical", or "diagonal"
  - `timestamp`: Time when fold was executed
  - `cells_state`: Complete grid state snapshot BEFORE fold
  - `player_position`: Player position before fold
  - `fold_count`: Global fold counter value
- Grid state serialization via `serialize_grid_state()` and `deserialize_grid_state()`
- Cell snapshots via `to_dict()` and `create_state_snapshot()`
- Tests in `test_fold_history.gd`

### 2. Seam Tracking System
- **CellPiece.gd**: Each piece has `seams: Array[Seam]`
- **Seam.gd**: Contains:
  - `fold_id`: ID of fold that created this seam
  - `timestamp`: When seam was created
  - `line_point`: Point on seam line (LOCAL coordinates)
  - `line_normal`: Normal vector of seam
  - `intersection_points`: 2 points where seam intersects cell boundary
  - `fold_type`: "horizontal", "vertical", or "diagonal"
- **FoldSystem.gd**: `seam_lines: Array[Line2D]` stores visual seam lines
- **Cell.gd**: `get_all_seams()` returns all unique seams across all pieces
- **Seam.gd**: `intersects_with(other: Seam)` checks if two seams intersect

### 3. UI Infrastructure
- **HUD.gd**: Already has:
  - `signal undo_requested`
  - `set_can_undo(enabled: bool)` for button state
  - Undo button and keyboard shortcut 'U'
- **MainScene.gd**: Has placeholder `_on_undo_requested()` (TODO)

### 4. Input System
- **GridManager.gd**: Handles mouse input via `_input(event: InputEvent)`
- Mouse clicks and motion already processed for cell selection/hover

---

## Architecture & Design Decisions

### Decision 1: Dual Undo System

**Two Independent Undo Mechanisms:**

1. **Seam-Based UNFOLD (Puzzle Mechanic)**
   - Click directly on a seam to unfold that specific fold
   - Spatial constraint: seam must pass through grid cell center
   - Dependency validation: can't unfold if newer seams intersect it
   - **Player validation: can't unfold if player is standing on the seam**
   - **Behavior: Full geometric reversal WITHOUT player position restoration**
   - Visual feedback on hover/click
   - Mouse-only interaction

2. **Sequential UNDO Button (QOL Feature)**
   - Traditional undo button that reverses most recent action
   - Actions include: folds AND player moves
   - Separate action history from fold history
   - Always undoes in LIFO order (Last In, First Out)
   - **Behavior: Full state restoration INCLUDING player position**
   - Keyboard shortcut 'U'

**CRITICAL DISTINCTION:**
- **UNFOLD (seam click):**
  - Fully reverses the geometric fold (shifts, merges, splits, removals)
  - Does NOT restore player position from fold record
  - Player blocked if standing on seam (new validation)
  - Behaves like unfolding paper - geometric reversal only

- **UNDO (button/keyboard):**
  - Fully restores game state including player position
  - Restores grid AND player to exact state before action
  - Reverses the most recent action in history

**Rationale:**
- Seam-based unfold is the core puzzle mechanic - spatial and geometric
- Sequential undo prevents frustration from misclicks
- Two systems don't conflict - operate on different histories and behaviors
- Unfold's player-on-seam validation adds tactical depth to puzzle solving

### Decision 2: Seam Click Target Constraint

**The Constraint:**
A seam can only be clicked at positions where the seam line passes through the exact center of an original grid cell.

**Grid Cell Center Definition:**
- Original grid square center = `grid_pos * cell_size + Vector2(cell_size/2, cell_size/2)`
- Uses LOCAL coordinates (relative to GridManager)
- NOT the geometric centroid of current cell polygon (which may be split)

**Implementation Approach:**
1. For each seam, calculate which grid cells have their center on/near the seam line
2. Store these positions as "clickable zones" for the seam
3. On mouse click, check if click is near any clickable zone
4. Multiple cells may be valid for a single seam
5. Some seams may have zero clickable zones (if seam was cut by newer fold)

**Why This Matters:**
- Future feature: player character movement constraints
- Player will only be able to interact with cells they can reach
- This creates spatial puzzle constraints
- For now, it's just a debug/development feature

### Decision 3: Undo Validation Rule (Modified Strict Ordering)

**Original Rule (Decision 8 in ARCHITECTURE.md):**
> A fold can only be undone if it's the newest fold affecting ALL its cells

**New Rule for Seam-Based Undo:**
> A seam can be unfolded iff no newer seams intersect it on any of the cells it affects

**Key Differences:**
- Original: requires fold to be newest on ALL cells (very strict)
- New: allows undo if no INTERSECTING seams are newer (more flexible)
- Seams can intersect spatially even if they don't affect same cells
- Must check seam-to-seam intersection, not just cell overlap

**Implementation Logic:**
1. Get all cells affected by the target fold (from fold record)
2. For each cell, get all seams present in that cell
3. For each seam in those cells:
   - Skip if it's the seam we're trying to undo
   - Check if it spatially intersects with target seam (use `Seam.intersects_with()`)
   - If it intersects AND has newer timestamp, BLOCK undo
4. If no blocking seams found, allow undo

**Why More Flexible:**
- Non-intersecting seams don't affect each other geometrically
- Can undo diagonal fold even if newer horizontal fold exists (if they don't intersect)
- Better gameplay: more strategic undo options
- Still maintains geometric consistency

### Decision 4: Seam Visual States

**Three Visual States for Seams:**

1. **Undoable Seam** (Green):
   - No newer intersecting seams
   - Has at least one clickable zone (passes through cell center)
   - Hover effect: brighter green + glow

2. **Non-Undoable Seam** (Red):
   - Blocked by newer intersecting seams OR
   - No clickable zones (seam was cut)
   - Hover effect: brighter red + warning icon

3. **Neutral Seam** (Cyan - default):
   - Mouse not hovering
   - Color indicates undoable state (green/red) with lower alpha

**Visual Feedback on Click:**
- **Success**: Seam disappears, fold reverses, play unfold sound
- **Failure**: Shake animation, play error sound, show tooltip explaining why blocked

**Implementation:**
- Update seam colors in `_process()` or when undo state changes
- Seam Line2D nodes already exist in `FoldSystem.seam_lines`
- Add metadata to each Line2D to track fold_id and undoable state
- Check mouse proximity to seam lines in input handler

### Decision 5: Action History (Sequential Undo)

**Separate from Fold History:**

Traditional undo button needs to track ALL player actions, not just folds:
- Player movement (grid_position changes)
- Fold operations
- Any future interactive elements

**Action Record Structure:**
```
{
  "action_type": "move" | "fold" | ...,
  "timestamp": int,
  "state_before": Dictionary,  # What to restore
  "state_after": Dictionary,   # What was applied (for redo)
}
```

**Move Action:**
```
{
  "action_type": "move",
  "player_position_before": Vector2i,
  "player_position_after": Vector2i,
}
```

**Fold Action:**
```
{
  "action_type": "fold",
  "fold_id": int,  # Reference to fold_history
}
```

**Implementation Location:**
- New class: `ActionHistory` (scripts/systems/ActionHistory.gd)
- Managed by MainScene or GameManager
- Independent from FoldSystem.fold_history

---

## Implementation Tasks

### Task 1: Seam-to-Fold Mapping System (1.5 hours)

**Goal:** Create a centralized mapping from seam Line2D visuals to their fold records.

**Requirements:**
- Maintain `seam_to_fold_map: Dictionary` in FoldSystem
  - Key: Line2D node (or unique ID)
  - Value: fold_id
- When creating seams in `create_diagonal_seam_visual()`, add to map
- When removing seams (during undo), remove from map
- Helper method: `get_fold_for_seam(seam_line: Line2D) -> Dictionary`

**Why Needed:**
- Currently, seam Line2D visuals exist but aren't linked to fold records
- Need to know which fold to undo when a seam is clicked
- Allows quick lookup from visual element to fold data

**Test Coverage:**
- Create fold → verify seam added to map
- Get fold for seam → correct fold returned
- Undo fold → verify seam removed from map
- Multiple folds → all seams mapped correctly

---

### Task 2: Clickable Zone Calculation (2 hours)

**Goal:** Determine which grid cell centers each seam passes through.

**Algorithm:**
1. For each seam (stored as Line2D in FoldSystem.seam_lines):
   - Get seam line equation (point + normal from Seam object in CellPiece)
   - Iterate through all grid positions (0 to grid_size)
   - Calculate grid cell center: `center = Vector2(grid_pos) * cell_size + Vector2(cell_size/2, cell_size/2)`
   - Check if center is on/near the seam line (within tolerance)
   - If yes, add grid_pos to clickable zones for this seam

2. Distance check:
   - Use point-to-line distance formula
   - Tolerance: `click_tolerance = cell_size * 0.15` (generous for debug use)
   - Formula: `distance = abs((center - line_point).dot(line_normal))`

3. Store results:
   - Add `clickable_zones: Array[Vector2i]` metadata to each Line2D
   - OR maintain separate `seam_clickable_zones: Dictionary` mapping Line2D → Array[Vector2i]

**Edge Cases:**
- Seam parallel to grid lines: may pass through many centers
- Seam at angle: may pass through few or zero centers
- Seam cut by newer fold: some zones may no longer have seam visible

**Test Coverage:**
- Horizontal seam → correct cells identified
- Vertical seam → correct cells identified
- Diagonal seam → correct cells identified
- Seam with no zones → empty array
- Seam cut by fold → only visible portion has zones

---

### Task 3: Seam Intersection Validation (1.5 hours)

**Goal:** Check if a seam can be undone based on intersecting newer seams.

**Algorithm:**
1. Input: `fold_id` of fold to undo
2. Get fold record from fold_history
3. Get all cells affected by this fold (from fold record's affected_cells or removed_cells)
4. For each affected cell:
   - Get all seams in cell via `cell.get_all_seams()`
   - For each seam:
     - Skip if seam.fold_id == target fold_id (it's the one we're undoing)
     - Check if seam intersects target seam (use `Seam.intersects_with()`)
     - If intersects AND seam.timestamp > target_timestamp: BLOCK undo
5. If no blocking seams found: ALLOW undo

**Implementation Details:**
- New method: `FoldSystem.can_undo_fold_seam_based(fold_id: int) -> Dictionary`
  - Returns: `{valid: bool, reason: String, blocking_seams: Array[Seam]}`
- Cache results for performance (invalidate on new fold)
- Consider grid cells that may have been removed (check fold record)

**Edge Cases:**
- Target fold removed cells → can't check those cells, use fold record
- Multiple intersecting seams → return all blocking ones
- Parallel seams (no intersection) → allow undo even if newer
- No remaining seam visuals → can't undo (no clickable zones)

**Test Coverage:**
- No intersecting seams → can undo
- Newer intersecting seam → cannot undo
- Older intersecting seam → can undo
- Multiple newer seams → all reported as blocking
- Removed cells → correctly handled

---

### Task 4: Mouse Input for Seam Clicking (1.5 hours)

**Goal:** Detect when player clicks on a seam at a valid clickable zone.

**Implementation:**
- Add input handler to FoldSystem or GridManager
- On mouse click:
  1. Get mouse position (convert to LOCAL coordinates)
  2. For each seam in seam_lines:
     - Get seam's clickable_zones
     - For each zone:
       - Calculate zone center position
       - Check if mouse within tolerance of zone center
       - If yes → seam click detected!
  3. If seam detected:
     - Check if seam can be undone (`can_undo_fold_seam_based()`)
     - If yes → execute undo
     - If no → show error feedback

**Coordinate Conversion:**
- Mouse gives GLOBAL coordinates
- Seams and cell centers use LOCAL coordinates (relative to GridManager)
- Conversion: `local_pos = grid_manager.to_local(mouse_global_pos)`

**Click Tolerance:**
- Zone center has a radius: `zone_radius = cell_size * 0.25`
- Click valid if: `mouse_local_pos.distance_to(zone_center) <= zone_radius`

**Priority:**
- If multiple seams clickable at same position, use newest first (highest fold_id)
- Or show selection menu (future enhancement)

**Test Coverage:**
- Click on seam at valid zone → detected
- Click on seam outside zones → not detected
- Click on undoable seam → undo executes
- Click on blocked seam → error shown
- Multiple seams at position → correct one selected

---

### Task 5: Undo Execution (2 hours)

**Goal:** Restore grid state from fold record and update all related systems.

**Algorithm:**
1. Get fold record from fold_history by fold_id
2. Restore grid state:
   - Clear ALL current cells from GridManager.cells
   - Deserialize cells_state from fold record
   - Create new Cell nodes for each restored cell
   - Add cells as children of GridManager
   - Update GridManager.cells dictionary
3. Restore player position:
   - Set player.grid_position from fold record
   - Update player.global_position
4. Remove seam visuals:
   - Find all Line2D seams with matching fold_id
   - Remove from scene tree
   - Remove from seam_lines array
   - Remove from seam_to_fold_map
5. Remove fold from history:
   - Remove fold record from fold_history
   - OR mark as undone (keep for redo)
6. Update UI:
   - Decrement fold counter
   - Update undo button state
7. Play undo sound effect

**Memory Management:**
- CRITICAL: Free old cell nodes before creating new ones
- Use `queue_free()` on all cells in GridManager before restoration
- Clear GridManager.cells dictionary
- Ensure no memory leaks from Cell visual nodes (Polygon2D, Line2D, etc.)

**Edge Cases:**
- Undo fold affects player → player moved back
- Undo fold removes seams from multiple cells → all seams updated
- Undo creates cells at negative positions (shouldn't happen with normalized anchors)
- Multiple folds undone in sequence → state correctly restored each time

**Test Coverage:**
- Undo fold → grid state restored correctly
- Undo fold → player position restored
- Undo fold → seam visuals removed
- Undo fold → fold counter decremented
- Multiple undos → all work correctly
- No memory leaks → verify with repeated undo/redo

---

### Task 6: Seam Visual State Updates (1.5 hours)

**Goal:** Color seams based on undoable state and show hover effects.

**Visual States:**
1. **Undoable + Not Hovered:** Green (alpha 0.6)
2. **Undoable + Hovered:** Bright Green (alpha 1.0), width +2
3. **Blocked + Not Hovered:** Red (alpha 0.6)
4. **Blocked + Hovered:** Bright Red (alpha 1.0), show tooltip

**Implementation:**
- Update seam colors in `_process()` or on-demand when state changes
- Track hovered seam (similar to GridManager's hovered_cell)
- On mouse motion:
  - Check proximity to each seam line
  - Set hovered_seam if within tolerance
  - Update visual state
- Cache undoable state to avoid recalculating every frame:
  - Calculate on fold execution
  - Recalculate on undo/redo
  - Mark as dirty when needed

**Hover Detection:**
- Check distance from mouse to seam line segment (use point-to-segment distance)
- Tolerance: `hover_distance = 10.0` pixels
- Only check seams with visible clickable zones

**Tooltip System:**
- Simple Label node positioned at mouse
- Shows reason why seam can't be undone
- E.g., "Blocked by fold #3" or "No reachable activation points"

**Test Coverage:**
- Undoable seam → green color
- Blocked seam → red color
- Hover over seam → color brightens
- Mouse away → color dims
- Tooltip appears on blocked seam hover
- Colors update after new fold

---

### Task 7: Action History for Sequential Undo (1.5 hours)

**Goal:** Track all player actions (moves + folds) for traditional undo button.

**New Class: ActionHistory.gd**
```
class_name ActionHistory

var actions: Array[Dictionary] = []
var max_actions: int = 100  # Limit to prevent memory issues

func push_action(action: Dictionary)
func pop_action() -> Dictionary
func can_undo() -> bool
func clear()
```

**Action Types:**

1. **Move Action:**
   - Created when player moves
   - Stores: old position, new position
   - Undo: move player back to old position

2. **Fold Action:**
   - Created when fold executes
   - Stores: fold_id reference
   - Undo: call undo_fold(fold_id) on FoldSystem

**Integration Points:**
- Player.gd: On successful move, push move action
- FoldSystem.gd: After execute_fold(), push fold action
- MainScene.gd: On undo button, pop action and execute undo

**UI Updates:**
- HUD.set_can_undo(ActionHistory.can_undo())
- Update after every action
- Update after every undo

**Test Coverage:**
- Push move action → stored correctly
- Push fold action → stored correctly
- Pop action → correct action returned
- Undo move → player position restored
- Undo fold → fold system undo called
- Mixed actions → undo in correct order (LIFO)
- Max actions → oldest removed

---

### Task 8: Integration & Testing (1.5 hours)

**Goal:** Wire everything together and ensure all systems work harmoniously.

**Integration Checklist:**
- [ ] FoldSystem creates seam visuals with metadata
- [ ] Seam-to-fold mapping maintained
- [ ] Clickable zones calculated on fold
- [ ] Mouse input detects seam clicks
- [ ] Undo validation works
- [ ] Undo execution restores state
- [ ] Seam visuals update
- [ ] Action history tracks everything
- [ ] Sequential undo works
- [ ] UI updates correctly
- [ ] No memory leaks
- [ ] All existing tests still pass

**Test Scenarios:**
1. Simple fold + seam click undo
2. Multiple folds + selective undo
3. Blocked undo attempt → error shown
4. Sequential undo button → all actions reversed
5. Mixed seam undo + button undo
6. Undo after player move
7. Undo diagonal fold with split cells
8. Undo with null pieces (should restore)
9. Undo with multi-seam cells

**Performance Testing:**
- 10+ folds → undo still fast
- Hover over many seams → no FPS drop
- Large grid (20x20) → undo still works

---

## Data Structures

### Seam Metadata (Attached to Line2D)
```
Line2D.set_meta("fold_id", int)
Line2D.set_meta("seam_object", Seam)
Line2D.set_meta("clickable_zones", Array[Vector2i])
Line2D.set_meta("is_undoable", bool)
Line2D.set_meta("blocking_reason", String)
```

### Seam-to-Fold Map (in FoldSystem)
```
seam_to_fold_map: Dictionary
  Key: Line2D instance ID (get_instance_id())
  Value: int (fold_id)
```

### Action Record (in ActionHistory)
```
{
  "action_id": int,
  "action_type": "move" | "fold",
  "timestamp": int,

  # For move actions:
  "old_position": Vector2i,
  "new_position": Vector2i,

  # For fold actions:
  "fold_id": int
}
```

---

## Visual Design Specs

### Seam Colors
- **Undoable (not hovered):** Color(0.2, 1.0, 0.2, 0.6) - Semi-transparent green
- **Undoable (hovered):** Color(0.4, 1.0, 0.4, 1.0) - Bright green
- **Blocked (not hovered):** Color(1.0, 0.2, 0.2, 0.6) - Semi-transparent red
- **Blocked (hovered):** Color(1.0, 0.4, 0.4, 1.0) - Bright red

### Seam Widths
- **Not hovered:** 2.0 pixels
- **Hovered:** 4.0 pixels

### Clickable Zone Indicator (Debug Mode)
- Small circle at each clickable zone center
- Color: Yellow with low alpha
- Radius: cell_size * 0.1
- Only visible when debug flag enabled

### Tooltip
- Background: Semi-transparent black
- Text: White, size 14
- Padding: 8px
- Position: Mouse position + offset (10, 10)
- Auto-hide after 2 seconds

---

## Sound Effects

### New SFX Needed:
- **unfold.wav**: Reverse-fold sound (pitch-shifted fold sound)
- **undo_blocked.wav**: Error tone when undo blocked
- **seam_hover.wav**: Subtle click when hovering undoable seam (optional)

### Existing SFX to Reuse:
- **error.wav**: For undo validation failures
- **button_click.wav**: For undo button

---

## Testing Strategy

### Test Files to Create:
1. **test_seam_undo.gd** (15-20 tests)
   - Seam-to-fold mapping
   - Clickable zone calculation
   - Intersection validation
   - Mouse input detection
   - Undo execution

2. **test_action_history.gd** (10-15 tests)
   - Action push/pop
   - Move action undo
   - Fold action undo
   - Mixed action sequences
   - Max capacity

3. **test_undo_integration.gd** (10-15 tests)
   - End-to-end undo scenarios
   - UI updates
   - Memory leak checks
   - Performance tests

### Test Coverage Target:
- All new methods: 100%
- Integration scenarios: 90%+
- Edge cases: Comprehensive

---

## Performance Considerations

### Optimizations:
1. **Cache undoable state:**
   - Don't recalculate every frame
   - Only update on fold/undo
   - Mark dirty when needed

2. **Spatial indexing for seam clicks:**
   - Pre-filter seams by bounding box
   - Only check nearby seams on click
   - Use quadtree for large grids (future)

3. **Limit action history:**
   - Max 100 actions (configurable)
   - Remove oldest when limit reached
   - Option to disable for performance

4. **Batch seam visual updates:**
   - Update all seams in single pass
   - Use shader for hover effects (future)
   - Minimize Line2D property changes

### Memory Management:
- Always `queue_free()` old cells on undo
- Clear dictionaries before repopulating
- Don't keep references to freed nodes
- Test with repeated undo/redo cycles

---

## Future Enhancements (Not in Phase 6)

### Player Reach Constraint
- Only show clickable zones within player reach distance
- Pathfinding to determine reachable cells
- Visual indicator of reachable vs unreachable zones

### Redo System
- Store undone actions in redo stack
- Ctrl+Y or Shift+U for redo
- Clear redo stack on new action

### Undo Animation
- Reverse animation of fold
- Cells fly back to original positions
- Seam fades out

### Multiple Seam Selection
- When multiple seams at click point
- Show radial menu to choose which to undo
- Or cycle through with scroll wheel

### Undo Preview
- Hover over seam → ghost preview of undo result
- Show which cells would be restored
- Show where player would move

---

## Completion Checklist

### Core Systems:
- [ ] Seam-to-fold mapping implemented
- [ ] Clickable zone calculation working
- [ ] Seam intersection validation correct
- [ ] Mouse input detects seam clicks
- [ ] Undo execution restores grid state
- [ ] Seam visuals update based on state
- [ ] Action history tracks all actions
- [ ] Sequential undo button functional

### Visual & Audio:
- [ ] Seam colors update (green/red)
- [ ] Hover effects work
- [ ] Tooltips show on blocked seams
- [ ] Undo sound effects play
- [ ] UI updates correctly

### Testing:
- [ ] All new tests pass (40-50 tests)
- [ ] All existing tests still pass
- [ ] No memory leaks detected
- [ ] Performance acceptable

### Documentation:
- [ ] Code comments complete
- [ ] Test coverage documented
- [ ] Known issues logged
- [ ] Phase 6 marked complete in STATUS.md

---

## Known Challenges

### Challenge 1: Seam-to-Cell Mapping After Folds
**Problem:** After a fold, cells shift positions. Seams may no longer be at their original grid positions.

**Solution:**
- Store seam metadata in CellPiece objects (already done)
- Seam visuals (Line2D) in LOCAL coordinates (already done)
- Clickable zones recalculated after each fold
- Use fold_id to track which fold created which seam

### Challenge 2: Null Pieces in Undo
**Problem:** Cells with null pieces created during folds must be restored correctly.

**Solution:**
- Cell serialization already includes all geometry_pieces
- Null pieces have cell_type = -1
- Undo restores all pieces including nulls
- Test null piece restoration explicitly

### Challenge 3: Player Position After Undo
**Problem:** Player may be on a cell that gets restored to different state.

**Solution:**
- Fold records already store player_position
- Restore player to exact position from record
- Validate player position is still walkable (shouldn't fail)
- If position invalid (shouldn't happen), move to nearest valid cell

### Challenge 4: Seam Clicks on Overlapping Seams
**Problem:** Multiple seams may pass through same grid cell center.

**Solution:**
- Prioritize newest seam (highest fold_id)
- OR show selection menu (future enhancement)
- For Phase 6: always select newest
- Document this behavior

---

## Implementation Order

**Recommended sequence for minimal risk:**

1. **Day 1 (3-4 hours):**
   - Task 1: Seam-to-fold mapping
   - Task 2: Clickable zone calculation
   - Task 3: Intersection validation
   - Write tests for above

2. **Day 2 (3-4 hours):**
   - Task 4: Mouse input handling
   - Task 5: Undo execution
   - Write tests for above
   - Integration testing

3. **Day 3 (2-3 hours):**
   - Task 6: Visual state updates
   - Task 7: Action history
   - Task 8: Final integration
   - Polish and bug fixes

---

## Success Criteria

Phase 6 is complete when:

1. ✅ Players can click on seams at valid zones to undo folds
2. ✅ Seams show correct visual state (undoable vs blocked)
3. ✅ Undo correctly restores grid state including null pieces
4. ✅ Traditional undo button works for all actions
5. ✅ UI updates correctly (fold counter, undo button state)
6. ✅ No memory leaks in repeated undo/redo
7. ✅ All tests pass (new + existing)
8. ✅ Performance acceptable on 10x10 grid with 10+ folds

---

**End of Phase 6 Specification**
