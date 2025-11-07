# Phase 3 GitHub Issues - Simple Axis-Aligned Folding

This document contains all issues for Phase 3 of the Space-Folding Puzzle Game implementation. Each issue is structured to be copy-pasted directly into GitHub.

---

## Issue 7: Implement Basic FoldSystem for Axis-Aligned Folds

**Title:** Implement Basic FoldSystem for Horizontal and Vertical Folds

**Labels:** `core`, `phase-3`, `folding-mechanics`

**Priority:** High

**Estimated Time:** 2-3 hours

**Description:**

Implement the `FoldSystem` class that handles axis-aligned (horizontal and vertical) folding operations. This is the first step toward the full geometric folding system and provides the foundation for fold mechanics.

### Tasks

#### Core Implementation

- [ ] Create `scripts/systems/FoldSystem.gd` file
- [ ] Define `FoldSystem` class extending Node
- [ ] Implement properties:
  ```gdscript
  var grid_manager: GridManager
  var fold_history: Array[Dictionary] = []
  var next_fold_id: int = 0
  ```

#### Fold Detection Methods

- [ ] Implement `is_horizontal_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - Return true if anchors have same Y coordinate
  - Allow for small epsilon difference if needed
- [ ] Implement `is_vertical_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - Return true if anchors have same X coordinate
  - Allow for small epsilon difference if needed
- [ ] Implement `get_fold_orientation(anchor1: Vector2i, anchor2: Vector2i) -> String`
  - Return "horizontal", "vertical", or "diagonal"
  - Useful for routing to correct fold handler

#### Horizontal Fold Implementation

- [ ] Implement `execute_horizontal_fold(anchor1: Vector2i, anchor2: Vector2i)`
  - Validate fold is horizontal
  - Ensure anchor1.x < anchor2.x (normalize order)
  - Calculate removed region (cells between anchors)
  - Remove cells in the region
  - Shift cells to the right of anchor2 to be adjacent to anchor1
  - Update world positions of shifted cells
  - Create merged anchor point
  - Store fold operation in history

#### Vertical Fold Implementation

- [ ] Implement `execute_vertical_fold(anchor1: Vector2i, anchor2: Vector2i)`
  - Validate fold is vertical
  - Ensure anchor1.y < anchor2.y (normalize order)
  - Calculate removed region (cells between anchors)
  - Remove cells in the region
  - Shift cells below anchor2 to be adjacent to anchor1
  - Update world positions of shifted cells
  - Create merged anchor point
  - Store fold operation in history

#### Main Fold Execution Method

- [ ] Implement `execute_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - Determine fold orientation
  - Route to appropriate fold handler
  - Return true on success, false on failure
  - Emit signal on fold completion (optional)

#### Helper Methods

- [ ] Implement `calculate_removed_cells(anchor1: Vector2i, anchor2: Vector2i) -> Array[Vector2i]`
  - Return list of grid positions that will be removed
  - Handle both horizontal and vertical cases
  - Include boundary cells correctly
- [ ] Implement `get_fold_distance(anchor1: Vector2i, anchor2: Vector2i) -> int`
  - Return number of cells between anchors
  - Useful for validation
- [ ] Implement `create_fold_record(anchor1: Vector2i, anchor2: Vector2i, removed_cells: Array) -> Dictionary`
  - Store fold metadata for undo system later
  - Include fold_id, anchors, removed cells, timestamp

### Testing Requirements

Create test scenarios in `scripts/tests/test_fold_system.gd`:

- [ ] Test horizontal fold detection
- [ ] Test vertical fold detection
- [ ] Test diagonal fold detection (should fail for now)
- [ ] Test horizontal fold removes correct cells
- [ ] Test vertical fold removes correct cells
- [ ] Test cells are shifted correctly after horizontal fold
- [ ] Test cells are shifted correctly after vertical fold
- [ ] Test world positions updated correctly
- [ ] Test fold history is recorded
- [ ] Test fold with adjacent anchors (distance = 1)
- [ ] Test fold with anchors far apart
- [ ] Test multiple sequential folds
- [ ] Test grid remains consistent after fold

### Manual Testing Checklist

- [ ] Select two cells in the same row
- [ ] Execute fold - verify cells between them disappear
- [ ] Verify cells to the right shift left
- [ ] Select two cells in the same column
- [ ] Execute fold - verify cells between them disappear
- [ ] Verify cells below shift up
- [ ] Verify grid remains playable after multiple folds

### Acceptance Criteria

- FoldSystem class created and properly integrated
- Horizontal folds work correctly
- Vertical folds work correctly
- Cells are removed from correct regions
- Grid geometry updates correctly after fold
- World positions recalculated accurately
- Fold history tracked for future undo system
- All test cases pass
- No crashes or memory leaks
- Grid remains in valid state after folds

### Implementation Notes

**Horizontal Fold Algorithm:**
```gdscript
func execute_horizontal_fold(anchor1: Vector2i, anchor2: Vector2i):
    # 1. Normalize anchor order (ensure anchor1 is leftmost)
    if anchor1.x > anchor2.x:
        var temp = anchor1
        anchor1 = anchor2
        anchor2 = temp

    # 2. Calculate removed region
    var removed_cells = []
    for x in range(anchor1.x + 1, anchor2.x):
        var cell_pos = Vector2i(x, anchor1.y)
        removed_cells.append(cell_pos)

    # 3. Remove cells
    for pos in removed_cells:
        grid_manager.remove_cell(pos)

    # 4. Shift cells to the right of anchor2
    var shift_distance = anchor2.x - anchor1.x
    for x in range(anchor2.x + 1, grid_manager.grid_size.x):
        var old_pos = Vector2i(x, anchor1.y)
        var new_pos = Vector2i(x - shift_distance, anchor1.y)
        grid_manager.move_cell(old_pos, new_pos)

    # 5. Create merged anchor
    # Mark anchor1 as merged point for visual feedback

    # 6. Record fold operation
    var fold_record = create_fold_record(anchor1, anchor2, removed_cells)
    fold_history.append(fold_record)
```

**Important Considerations:**
- Grid size changes after fold (grid becomes smaller)
- May need to update `grid_manager.grid_size` or maintain logical vs physical grid
- Consider whether cells beyond the fold line should maintain grid coordinates or get new ones
- World positions must be recalculated to keep grid visually coherent

**Alternative Approach - Grid Mapping:**
Instead of modifying grid coordinates, maintain a mapping of "logical" to "physical" positions:
```gdscript
# In GridManager
var logical_to_physical: Dictionary = {}  # Vector2i -> Vector2i
var physical_cells: Dictionary = {}  # Vector2i -> Cell
```

This approach is more complex but allows for easier undo implementation.

### References

- Implementation Plan: Phase 3.1
- Related: GridManager (Issue #5), Cell (Issue #4)
- Target: Week 2

### Dependencies

- Depends on: Issue #4 (Cell class)
- Depends on: Issue #5 (GridManager class)
- Depends on: Issue #6 (Anchor selection system)

---

## Issue 8: Implement Fold Validation (No Player for Now)

**Title:** Implement Fold Validation System

**Labels:** `core`, `phase-3`, `validation`

**Priority:** High

**Estimated Time:** 1-2 hours

**Description:**

Implement basic fold validation to ensure folds are valid before execution. This will be extended later to include player position validation, but for now we'll focus on geometric validation.

### Tasks

#### Core Validation Methods

- [ ] Implement `validate_fold(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary`
  - Return `{valid: bool, reason: String}`
  - Check all validation rules
  - Return descriptive error message if invalid

#### Validation Rules

- [ ] Implement `validate_anchors_exist(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - Check both anchors are within grid bounds
  - Check both anchor cells exist
- [ ] Implement `validate_minimum_distance(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - Define `MIN_FOLD_DISTANCE = 1` (at least 1 cell between anchors)
  - Reject adjacent anchors (no cells to remove)
- [ ] Implement `validate_same_row_or_column(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - For Phase 3, only allow horizontal or vertical folds
  - Reject diagonal selections
- [ ] Implement `validate_not_same_cell(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - Reject if both anchors are the same cell

#### Integration with FoldSystem

- [ ] Update `execute_fold()` to call validation first
  - Return early if validation fails
  - Show error message to user
  - Provide visual feedback (red preview line)
- [ ] Add validation result to fold preview
  - Green line: valid fold
  - Red line: invalid fold

#### Visual Feedback

- [ ] Add `preview_fold_line_color` property to GridManager
  - Green (#00FF00) for valid folds
  - Red (#FF0000) for invalid folds
- [ ] Update preview line rendering to use validation result
- [ ] Show validation error message (optional UI label)

### Testing Requirements

Create test scenarios in `scripts/tests/test_fold_validation.gd`:

- [ ] Test validation passes for valid horizontal fold
- [ ] Test validation passes for valid vertical fold
- [ ] Test validation fails for diagonal fold (Phase 3 limitation)
- [ ] Test validation fails for same cell
- [ ] Test validation fails for adjacent cells (no gap)
- [ ] Test validation fails for out-of-bounds anchors
- [ ] Test validation fails for non-existent cells
- [ ] Test validation provides correct error messages
- [ ] Test execute_fold() respects validation

### Acceptance Criteria

- Validation system implemented and working
- Invalid folds are rejected with clear error messages
- Only horizontal and vertical folds allowed in Phase 3
- Minimum distance enforced
- Visual feedback shows valid/invalid status
- All test cases pass
- Integration with FoldSystem complete

### Implementation Notes

**Validation Structure:**
```gdscript
func validate_fold(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
    # Check anchors exist
    if not validate_anchors_exist(anchor1, anchor2):
        return {valid: false, reason: "One or both anchors are invalid"}

    # Check not same cell
    if not validate_not_same_cell(anchor1, anchor2):
        return {valid: false, reason: "Cannot fold a cell onto itself"}

    # Check minimum distance
    if not validate_minimum_distance(anchor1, anchor2):
        return {valid: false, reason: "Anchors must have at least one cell between them"}

    # Check axis-aligned (Phase 3 only)
    if not validate_same_row_or_column(anchor1, anchor2):
        return {valid: false, reason: "Only horizontal and vertical folds supported (for now)"}

    return {valid: true, reason: ""}
```

**Integration with Execute:**
```gdscript
func execute_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool:
    var validation = validate_fold(anchor1, anchor2)

    if not validation.valid:
        print("Fold validation failed: ", validation.reason)
        show_error_feedback(validation.reason)
        return false

    # Proceed with fold execution
    if is_horizontal_fold(anchor1, anchor2):
        execute_horizontal_fold(anchor1, anchor2)
    elif is_vertical_fold(anchor1, anchor2):
        execute_vertical_fold(anchor1, anchor2)

    return true
```

### Future Extensions

This validation system will be extended in Phase 7 to include:
- Player position validation (fold blocked if player in removed region)
- Player cell split validation (fold blocked if player cell would be split)

For now, we're establishing the validation framework that will accommodate these additions.

### References

- Implementation Plan: Phase 3.2 (subset - no player yet)
- Related: FoldSystem (Issue #7)
- Target: Week 2

### Dependencies

- Depends on: Issue #7 (FoldSystem must be implemented first)

---

## Issue 9: Implement Visual Feedback for Fold Operations

**Title:** Add Visual Feedback and Animations for Fold Operations

**Labels:** `ui`, `phase-3`, `polish`, `animation`

**Priority:** Medium

**Estimated Time:** 2-3 hours

**Description:**

Implement visual feedback and animations to make fold operations clear and satisfying. This includes preview lines, fold animations, and seam visualization.

### Tasks

#### Preview Line Enhancement

- [ ] Update preview line to show fold validity
  - Green (#00FF00) for valid folds
  - Red (#FF0000) for invalid folds
  - Update color in real-time as user selects anchors
- [ ] Add fold direction indicator
  - Arrow or chevron showing which way cells will shift
  - Show region that will be removed (semi-transparent highlight)
- [ ] Make preview line more prominent
  - Increase width to 4-5 pixels
  - Add subtle glow effect (optional)

#### Fold Animation System

- [ ] Create animation for cell removal
  - Fade out cells in removed region
  - Duration: 0.3-0.5 seconds
  - Use easing for smooth effect
- [ ] Create animation for cell shifting
  - Tween cells to new positions
  - Duration: 0.5 seconds
  - Use smooth easing (ease_in_out)
  - Stagger slightly for visual appeal (optional)
- [ ] Prevent user input during animation
  - Set `is_animating` flag
  - Block new fold attempts while animating
  - Queue input for after animation (optional)

#### Seam Visualization

- [ ] Create seam line after fold completes
  - Draw line at merged anchor point
  - Use Line2D node
  - Color: Cyan (#00FFFF) or white
  - Width: 2-3 pixels
- [ ] Store seam metadata
  - Fold ID
  - Anchor positions
  - Timestamp
  - Fold direction
- [ ] Make seams persistent
  - Remain visible after fold
  - Show fold history visually

#### Visual Effects (Optional)

- [ ] Add particle effect at fold line
  - Burst of particles when fold executes
  - Particles follow seam line
- [ ] Add sound effects
  - Selection sound
  - Fold execution sound
  - Invalid fold sound (error beep)
- [ ] Add screen shake on fold (subtle)
  - Small camera shake for impact
  - Very subtle - don't overdo it

#### UI Polish

- [ ] Add fold counter
  - Show number of folds performed
  - Display in corner of screen
- [ ] Add status message label
  - Show validation errors
  - Show fold success messages
  - Auto-hide after 2-3 seconds
- [ ] Improve anchor selection visuals
  - Make outlines more visible
  - Add pulsing animation (optional)

### Testing Requirements

Manual testing only (visual feedback is hard to unit test):

- [ ] Preview line updates color based on validation
- [ ] Fold animation plays smoothly
- [ ] Cells move to correct positions during animation
- [ ] Seam lines appear at fold locations
- [ ] No visual glitches during animation
- [ ] Animations don't block unnecessarily
- [ ] Visual feedback is clear and helpful
- [ ] Performance remains good (60 FPS)

### Acceptance Criteria

- Preview line shows fold validity (green/red)
- Fold animations are smooth and polished
- Seam lines appear after folds
- User cannot perform fold during animation
- Visual feedback helps user understand what will happen
- Animations don't cause performance issues
- System feels responsive and satisfying to use

### Implementation Notes

**Animation System:**
```gdscript
var is_animating: bool = false

func execute_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool:
    if is_animating:
        return false  # Block during animation

    var validation = validate_fold(anchor1, anchor2)
    if not validation.valid:
        return false

    is_animating = true

    # Start animation sequence
    await animate_fold_sequence(anchor1, anchor2)

    is_animating = false
    return true

func animate_fold_sequence(anchor1: Vector2i, anchor2: Vector2i):
    # 1. Fade out removed cells
    var removed_cells = calculate_removed_cells(anchor1, anchor2)
    await fade_out_cells(removed_cells, 0.3)

    # 2. Remove cells from grid
    for pos in removed_cells:
        grid_manager.remove_cell(pos)

    # 3. Animate cell shifting
    await shift_cells_animated(anchor1, anchor2, 0.5)

    # 4. Create seam line
    create_seam_visual(anchor1, anchor2)
```

**Tween Example:**
```gdscript
func fade_out_cells(cell_positions: Array[Vector2i], duration: float):
    var tweens = []

    for pos in cell_positions:
        var cell = grid_manager.get_cell(pos)
        if cell:
            var tween = create_tween()
            tween.tween_property(cell, "modulate:a", 0.0, duration)
            tweens.append(tween)

    # Wait for all tweens to complete
    for tween in tweens:
        await tween.finished

func shift_cells_animated(anchor1: Vector2i, anchor2: Vector2i, duration: float):
    var cells_to_shift = get_cells_to_shift(anchor1, anchor2)
    var tweens = []

    for data in cells_to_shift:
        var cell = data.cell
        var new_world_pos = data.new_position

        var tween = create_tween()
        tween.set_ease(Tween.EASE_IN_OUT)
        tween.set_trans(Tween.TRANS_CUBIC)
        tween.tween_property(cell, "position", new_world_pos, duration)
        tweens.append(tween)

    # Wait for all tweens to complete
    for tween in tweens:
        await tween.finished

    # Update grid positions after animation
    update_grid_positions(cells_to_shift)
```

**Seam Visualization:**
```gdscript
func create_seam_visual(anchor1: Vector2i, anchor2: Vector2i):
    var seam_line = Line2D.new()
    seam_line.width = 2.0
    seam_line.default_color = Color.CYAN

    var pos1 = grid_manager.grid_to_world(anchor1)
    var pos2 = grid_manager.grid_to_world(anchor2)

    seam_line.points = PackedVector2Array([pos1, pos2])

    # Add to seams layer
    add_child(seam_line)

    # Store seam metadata
    var seam_data = {
        fold_id: next_fold_id,
        anchor1: anchor1,
        anchor2: anchor2,
        timestamp: Time.get_ticks_msec(),
        visual: seam_line
    }
    seams.append(seam_data)
```

### References

- Implementation Plan: Phase 3.3
- Related: FoldSystem (Issue #7), Validation (Issue #8)
- Target: Week 2

### Dependencies

- Depends on: Issue #7 (FoldSystem)
- Depends on: Issue #8 (Validation)

---

## Additional Notes

### Phase 3 Overview

**Total Estimated Time:** 5-8 hours

**Goals:**
- Implement basic folding mechanics for axis-aligned folds
- Add validation to ensure folds are legal
- Create polished visual feedback for user actions
- Establish foundation for more complex geometric folding (Phase 4)

### Success Criteria for Phase 3

- ✅ Horizontal folds work correctly
- ✅ Vertical folds work correctly
- ✅ Validation prevents invalid folds
- ✅ Visual feedback is clear and helpful
- ✅ Animations are smooth and polished
- ✅ Seam lines show fold history
- ✅ All test cases pass
- ✅ System feels responsive and satisfying
- ✅ Ready for Phase 4 (Geometric Folding) or Phase 7 (Player Character)

### Recommended Development Order

Since the implementation plan suggests adding the Player Character (Phase 7) before tackling the complex Geometric Folding (Phase 4), consider this order:

1. **Complete Phase 3** (this phase)
2. **Implement Phase 7** (Player Character)
   - Simpler than Phase 4
   - Allows testing of fold/player interaction
   - Tests game feel early
3. **Tackle Phase 4** (Geometric Folding)
   - Most complex phase
   - Benefits from having player already implemented

### Next Phase Preview

After Phase 3, you have two options:

**Option A: Phase 7 - Player Character (Recommended)**
- Implement basic player movement
- Test fold mechanics with player
- Add player-fold validation (fold blocked if player in the way)
- Simpler than Phase 4, tests core gameplay

**Option B: Phase 4 - Geometric Folding**
- Most complex phase
- Diagonal folds at arbitrary angles
- Cell splitting with polygon geometry
- Extensive testing required

The implementation plan recommends Option A (Phase 7 next) to test gameplay feel early and defer the complex geometric folding until the game mechanics are solid.

### Integration Points for Future Phases

Phase 3 provides these interfaces:

- `FoldSystem.execute_fold()` - Main entry point for fold execution
- `validate_fold()` - Can be extended with player validation
- `fold_history` - Foundation for undo system (Phase 6)
- Seam visualization - Will be extended for multi-seam handling (Phase 5)
- Animation system - Can be reused for geometric folds

### Testing Strategy

1. **Unit Tests:** Test fold logic in isolation
2. **Integration Tests:** Test FoldSystem with GridManager
3. **Manual Testing:** Verify visual feedback and animations
4. **Performance Tests:** Ensure animations run at 60 FPS
5. **Edge Case Testing:** Test boundary conditions, empty grids, etc.
