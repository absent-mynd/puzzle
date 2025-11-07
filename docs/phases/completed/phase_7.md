# Phase 7 GitHub Issues - Player Character

This document contains all issues for Phase 7 of the Space-Folding Puzzle Game implementation. Each issue is structured to be copy-pasted directly into GitHub.

**Note:** Phase 7 is recommended to be implemented before Phase 4 (Geometric Folding) to test gameplay feel early and establish player-fold interaction patterns.

---

## Issue 10: Implement Player Class and Grid-Based Movement

**Title:** Implement Player Character with Grid-Based Movement

**Labels:** `gameplay`, `phase-7`, `player`

**Priority:** High

**Estimated Time:** 2-3 hours

**Description:**

Implement the player character with grid-based movement. The player moves one cell at a time, respects wall collisions, and snaps to the grid. This establishes the core gameplay before adding complex player-fold interactions.

### Tasks

#### Core Player Class

- [ ] Create `scripts/core/Player.gd` file
- [ ] Define `Player` class extending CharacterBody2D
- [ ] Implement properties:
  ```gdscript
  var grid_position: Vector2i        # Current grid cell
  var target_position: Vector2         # Target world position for movement
  var is_moving: bool = false          # Currently animating movement
  var move_speed: float = 300.0        # Movement animation speed
  var grid_manager: GridManager        # Reference to grid
  ```

#### Initialization

- [ ] Implement `_init(start_pos: Vector2i, grid: GridManager)`
  - Set initial grid position
  - Store grid manager reference
  - Calculate initial world position
- [ ] Implement `_ready()`
  - Set up visual representation (sprite or simple shape)
  - Position at starting cell center
  - Set up collision shape
  - Configure z-index to render above grid

#### Input Handling

- [ ] Implement `_unhandled_input(event)` or `_process(delta)` for input
  - Handle arrow keys (UP, DOWN, LEFT, RIGHT)
  - Handle WASD keys as alternative
  - Ignore input during movement animation
  - Ignore input during fold animation
- [ ] Create input action mappings
  - Define in Project Settings → Input Map
  - Actions: move_up, move_down, move_left, move_right

#### Movement Logic

- [ ] Implement `attempt_move(direction: Vector2i) -> bool`
  - Calculate target grid position
  - Validate target position (within bounds)
  - Check for wall collision
  - Check if target cell exists
  - Return true if movement allowed
- [ ] Implement `execute_move(new_grid_pos: Vector2i)`
  - Update grid_position
  - Calculate new world position
  - Start movement animation
  - Set is_moving flag
- [ ] Implement movement animation
  - Use Tween to move to target position
  - Duration: ~0.2 seconds for snappy feel
  - Use ease_out for smooth stop
  - Clear is_moving flag when complete

#### Collision Detection

- [ ] Implement `can_move_to(grid_pos: Vector2i) -> bool`
  - Check grid bounds
  - Check cell exists (hasn't been removed by fold)
  - Check cell type (walls block movement)
  - Return true if position is walkable
- [ ] Implement wall detection
  - Empty cells (type 0): walkable
  - Wall cells (type 1): blocked
  - Water cells (type 2): walkable (for now)
  - Goal cells (type 3): walkable

#### Visual Representation

- [ ] Create player sprite or placeholder
  - Simple colored circle or square for prototype
  - Size: slightly smaller than cell size
  - Color: distinct from grid (e.g., yellow or orange)
  - Add subtle outline for visibility
- [ ] Implement direction facing (optional)
  - Rotate sprite based on movement direction
  - Or use different sprite frames

### Testing Requirements

Create test scenarios in `scripts/tests/test_player.gd`:

- [ ] Test player initialization at correct position
- [ ] Test movement in all four directions
- [ ] Test movement blocked by walls
- [ ] Test movement blocked by grid boundaries
- [ ] Test movement blocked during animation
- [ ] Test can_move_to() validation
- [ ] Test grid position updates correctly after move
- [ ] Test world position matches grid position
- [ ] Test movement to non-existent cell (removed by fold)
- [ ] Test WASD and arrow keys both work

### Manual Testing Checklist

- [ ] Run game with player visible on grid
- [ ] Press arrow keys - player should move one cell at a time
- [ ] Movement should be smooth and animated
- [ ] Player should stop at grid boundaries
- [ ] Player should not move through walls
- [ ] Player should not move during animation
- [ ] Movement feels responsive and snappy

### Acceptance Criteria

- Player class implemented and working
- Grid-based movement in 4 directions
- Smooth movement animations
- Wall collision detection works
- Boundary checking works correctly
- Cannot move during animation
- Cannot move to removed/invalid cells
- Visual representation is clear
- All test cases pass
- Movement feels good to play

### Implementation Notes

**Player Class Structure:**
```gdscript
class_name Player
extends CharacterBody2D

var grid_position: Vector2i
var target_position: Vector2
var is_moving: bool = false
var move_speed: float = 300.0
var grid_manager: GridManager

func _init(start_pos: Vector2i, grid: GridManager):
    grid_position = start_pos
    grid_manager = grid

func _ready():
    # Set up visual
    var sprite = ColorRect.new()
    sprite.size = Vector2(48, 48)  # Slightly smaller than cell
    sprite.color = Color.ORANGE
    sprite.position = -sprite.size / 2  # Center on player
    add_child(sprite)

    # Position at starting cell
    position = grid_manager.grid_to_world(grid_position)
    position += Vector2(32, 32)  # Center in cell (assuming 64px cells)

func _process(delta):
    if is_moving:
        return  # Don't accept input during movement

    var direction = Vector2i.ZERO

    if Input.is_action_just_pressed("move_up"):
        direction = Vector2i(0, -1)
    elif Input.is_action_just_pressed("move_down"):
        direction = Vector2i(0, 1)
    elif Input.is_action_just_pressed("move_left"):
        direction = Vector2i(-1, 0)
    elif Input.is_action_just_pressed("move_right"):
        direction = Vector2i(1, 0)

    if direction != Vector2i.ZERO:
        attempt_move(direction)

func attempt_move(direction: Vector2i) -> bool:
    var new_pos = grid_position + direction

    if not can_move_to(new_pos):
        return false

    execute_move(new_pos)
    return true

func can_move_to(grid_pos: Vector2i) -> bool:
    # Check bounds
    if not grid_manager.is_valid_position(grid_pos):
        return false

    # Check cell exists
    var cell = grid_manager.get_cell(grid_pos)
    if not cell:
        return false

    # Check not a wall
    if cell.cell_type == 1:  # Wall
        return false

    return true

func execute_move(new_grid_pos: Vector2i):
    is_moving = true
    grid_position = new_grid_pos

    # Calculate target world position (cell center)
    var cell_world_pos = grid_manager.grid_to_world(new_grid_pos)
    target_position = cell_world_pos + Vector2(32, 32)  # Center of 64px cell

    # Animate movement
    var tween = create_tween()
    tween.set_ease(Tween.EASE_OUT)
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.tween_property(self, "position", target_position, 0.2)
    await tween.finished

    is_moving = false
```

**Input Action Setup:**
Add these to Project Settings → Input Map:
- `move_up`: Arrow Up, W
- `move_down`: Arrow Down, S
- `move_left`: Arrow Left, A
- `move_right`: Arrow Right, D

### References

- Implementation Plan: Phase 7.1, 7.2
- Related: GridManager (Issue #5), Cell (Issue #4)
- Target: Week 7 (or earlier, after Phase 3)

### Dependencies

- Depends on: Issue #5 (GridManager)
- Depends on: Issue #4 (Cell with cell types)

---

## Issue 11: Implement Player-Fold Validation

**Title:** Add Player Position Validation to Fold System

**Labels:** `gameplay`, `phase-7`, `validation`

**Priority:** High

**Estimated Time:** 1-2 hours

**Description:**

Extend the fold validation system to prevent folds that would affect the player. Specifically, block folds if:
1. Player is in the region that would be removed (between anchors)
2. Player's cell would be split by the fold seam (Phase 4+ only)

For Phase 3 (axis-aligned folds), we only need to implement rule #1 since cells aren't split yet.

### Tasks

#### Validation Methods

- [ ] Update `FoldSystem` to have reference to player
  - Add `var player: Player` property
  - Set during initialization
- [ ] Implement `validate_fold_with_player(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary`
  - Check if player is in removed region
  - Return validation result with reason
  - Integrate with existing `validate_fold()` method
- [ ] Implement `is_player_in_removed_region(anchor1: Vector2i, anchor2: Vector2i) -> bool`
  - Calculate which cells will be removed
  - Check if player.grid_position is in that set
  - Return true if player would be removed

#### Integration with FoldSystem

- [ ] Update `execute_fold()` to include player validation
  - Call `validate_fold_with_player()` before executing
  - Block fold if player in the way
  - Show error message
- [ ] Ensure validation happens before animation starts
  - Prevent wasted animation if fold will fail

#### Visual Feedback

- [ ] Update preview line color based on player validation
  - Red if player blocks the fold
  - Green if fold is valid (including player check)
- [ ] Show error message when player blocks fold
  - "Cannot fold - player in the way"
  - "Move the player first"
  - Display for 2-3 seconds
- [ ] Optional: Highlight player in red when blocking fold
  - Visual indicator that player is the problem
  - Pulsing red outline or similar

#### Player Relocation Prevention

- [ ] Ensure player is NEVER relocated by fold
  - Validation prevents this scenario entirely
  - No special relocation logic needed
  - Simpler than trying to move player
- [ ] Document this design decision
  - Folds that affect player are blocked
  - Player must move out of the way first
  - Creates interesting puzzle constraints

### Testing Requirements

Create test scenarios in `scripts/tests/test_player_fold_validation.gd`:

- [ ] Test fold allowed when player not in removed region
- [ ] Test fold blocked when player in removed region (horizontal fold)
- [ ] Test fold blocked when player in removed region (vertical fold)
- [ ] Test fold blocked when player at anchor point
- [ ] Test fold allowed when player adjacent to removed region
- [ ] Test validation error message is correct
- [ ] Test preview line turns red when player blocks
- [ ] Test multiple folds with player moving between

### Manual Testing Checklist

- [ ] Place player in grid
- [ ] Attempt fold that would remove player's cell
- [ ] Verify fold is blocked with error message
- [ ] Verify preview line is red
- [ ] Move player out of removed region
- [ ] Verify fold now works (preview line green)
- [ ] Test with player at different positions
- [ ] Verify player never gets relocated

### Acceptance Criteria

- Player validation integrated into FoldSystem
- Folds blocked when player in removed region
- Clear error messages when fold blocked
- Visual feedback (red preview line)
- Player never gets relocated
- All test cases pass
- Puzzle gameplay feels logical and fair

### Implementation Notes

**Validation Method:**
```gdscript
func validate_fold_with_player(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
    if not player:
        return {valid: true, reason: ""}  # No player, no restriction

    # Check if player is in removed region
    if is_player_in_removed_region(anchor1, anchor2):
        return {valid: false, reason: "Cannot fold - player in the way"}

    # Future: Check if player's cell would be split (Phase 4+)
    # if would_split_player_cell(anchor1, anchor2):
    #     return {valid: false, reason: "Cannot fold - player's cell would be split"}

    return {valid: true, reason: ""}

func is_player_in_removed_region(anchor1: Vector2i, anchor2: Vector2i) -> bool:
    var removed_cells = calculate_removed_cells(anchor1, anchor2)
    return player.grid_position in removed_cells
```

**Integration with execute_fold:**
```gdscript
func execute_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool:
    if is_animating:
        return false

    # Standard validation (bounds, distance, etc.)
    var validation = validate_fold(anchor1, anchor2)
    if not validation.valid:
        show_error_message(validation.reason)
        return false

    # Player validation
    var player_validation = validate_fold_with_player(anchor1, anchor2)
    if not player_validation.valid:
        show_error_message(player_validation.reason)
        update_preview_line_color(Color.RED)
        return false

    # Fold is valid - proceed
    update_preview_line_color(Color.GREEN)
    await animate_fold_sequence(anchor1, anchor2)
    return true
```

**Error Message Display:**
```gdscript
var error_label: Label
var error_timer: Timer

func show_error_message(message: String):
    if not error_label:
        setup_error_ui()

    error_label.text = message
    error_label.visible = true

    # Auto-hide after 2 seconds
    error_timer.start(2.0)

func setup_error_ui():
    error_label = Label.new()
    error_label.add_theme_color_override("font_color", Color.RED)
    # Position at top of screen
    error_label.position = Vector2(20, 20)
    add_child(error_label)

    error_timer = Timer.new()
    error_timer.one_shot = true
    error_timer.timeout.connect(func(): error_label.visible = false)
    add_child(error_timer)
```

### Design Philosophy

**Why block folds instead of relocating player?**

1. **Simpler implementation** - No complex relocation logic needed
2. **Clearer gameplay** - Player always knows where they are
3. **Better puzzle design** - Creates interesting constraints
4. **Predictable behavior** - No surprises for the player
5. **Easier to reason about** - Fold validation is straightforward

This design decision simplifies both the code and the gameplay, while creating interesting puzzle opportunities where the player must plan their position before folding.

### Future Extensions (Phase 4)

When geometric folding is implemented, add this additional validation:

```gdscript
func would_split_player_cell(anchor1: Vector2i, anchor2: Vector2i) -> bool:
    var player_cell = grid_manager.get_cell(player.grid_position)
    if not player_cell:
        return false

    # Check if fold seam would split player's cell
    var cut_lines = calculate_cut_lines(anchor1, anchor2)

    var split1 = GeometryCore.split_polygon_by_line(
        player_cell.geometry,
        cut_lines.line1.point,
        cut_lines.line1.normal
    )
    var split2 = GeometryCore.split_polygon_by_line(
        player_cell.geometry,
        cut_lines.line2.point,
        cut_lines.line2.normal
    )

    # Cell is split if either line divides it
    return split1.intersections.size() > 0 or split2.intersections.size() > 0
```

For now (Phase 3), we only validate removed region since axis-aligned folds don't split cells.

### References

- Implementation Plan: Phase 7.3
- Related: Player (Issue #10), FoldSystem (Issue #7)
- Target: Week 7 (or earlier)

### Dependencies

- Depends on: Issue #10 (Player class)
- Depends on: Issue #7 (FoldSystem)
- Depends on: Issue #8 (Basic validation)

---

## Issue 12: Implement Goal Detection and Level Win Condition

**Title:** Add Goal Cell and Win Condition

**Labels:** `gameplay`, `phase-7`, `level-design`

**Priority:** Medium

**Estimated Time:** 1 hour

**Description:**

Implement goal cell functionality and win condition detection. When the player reaches a goal cell, the level is completed. This establishes the core win condition for puzzle levels.

### Tasks

#### Goal Cell Type

- [ ] Ensure goal cell type (type 3) is properly supported
  - Already defined in Cell class
  - Color: Green (#33FF33)
  - Should be walkable
- [ ] Add visual distinction for goal cells
  - Different color or pattern
  - Pulsing animation (optional)
  - Particle effect (optional)

#### Win Condition Detection

- [ ] Implement `check_win_condition()` in main game script
  - Check if player is on goal cell
  - Called after each player move
  - Return true if win condition met
- [ ] Implement `on_level_complete()` callback
  - Triggered when player reaches goal
  - Show win message
  - Stop accepting input
  - Show "Next Level" or "Restart" options

#### Win Condition Visuals

- [ ] Create win message UI
  - "Level Complete!" text
  - Fold count display
  - Time display (optional)
  - Buttons: "Next Level", "Restart", "Main Menu"
- [ ] Add win celebration effect
  - Particle burst at player position
  - Screen flash or color shift
  - Sound effect (optional)
  - Victory music (optional)

#### Level Setup

- [ ] Add method to designate goal cell
  - `GridManager.set_goal_cell(grid_pos: Vector2i)`
  - Updates cell type to goal (type 3)
  - Visually distinct
- [ ] Create simple test level
  - 10x10 grid
  - Player starts at one corner
  - Goal at opposite corner
  - Some walls in between
  - Requires a few folds to solve

### Testing Requirements

Create test scenarios in `scripts/tests/test_win_condition.gd`:

- [ ] Test player on goal cell triggers win
- [ ] Test player on non-goal cell doesn't trigger win
- [ ] Test win condition only checked after player moves
- [ ] Test win callback is called exactly once
- [ ] Test input blocked after win
- [ ] Test goal cell is walkable

### Manual Testing Checklist

- [ ] Run game with goal cell visible
- [ ] Move player around - no win yet
- [ ] Move player to goal cell
- [ ] Verify win message appears
- [ ] Verify input is blocked after win
- [ ] Verify restart works correctly

### Acceptance Criteria

- Goal cell type properly implemented
- Goal cells visually distinct from other cells
- Win condition detected when player reaches goal
- Win message displayed clearly
- Input blocked after win
- Level can be restarted
- All test cases pass
- Win condition feels satisfying

### Implementation Notes

**Win Condition Check:**
```gdscript
# In Player class or main game controller
func check_win_condition() -> bool:
    var current_cell = grid_manager.get_cell(grid_position)
    if not current_cell:
        return false

    return current_cell.cell_type == 3  # Goal cell

# After each move
func execute_move(new_grid_pos: Vector2i):
    is_moving = true
    grid_position = new_grid_pos

    # ... movement animation ...

    is_moving = false

    # Check win condition
    if check_win_condition():
        on_level_complete()
```

**Win UI:**
```gdscript
var win_ui: Control
var is_level_complete: bool = false

func on_level_complete():
    if is_level_complete:
        return  # Already won, don't trigger again

    is_level_complete = true
    show_win_ui()
    celebrate()

func show_win_ui():
    win_ui = Control.new()
    # ... create win message, buttons, etc ...
    add_child(win_ui)

func celebrate():
    # Particle effect
    var particles = CPUParticles2D.new()
    particles.position = player.position
    particles.emitting = true
    particles.one_shot = true
    add_child(particles)

    # Color flash
    var flash = ColorRect.new()
    flash.color = Color(1, 1, 1, 0.5)
    flash.size = get_viewport_rect().size
    add_child(flash)

    var tween = create_tween()
    tween.tween_property(flash, "modulate:a", 0.0, 0.5)
    await tween.finished
    flash.queue_free()
```

**Level Setup Example:**
```gdscript
func setup_simple_level():
    # Set up some walls
    grid_manager.get_cell(Vector2i(5, 5)).set_cell_type(1)  # Wall
    grid_manager.get_cell(Vector2i(5, 6)).set_cell_type(1)  # Wall
    grid_manager.get_cell(Vector2i(5, 4)).set_cell_type(1)  # Wall

    # Set goal
    grid_manager.set_goal_cell(Vector2i(9, 9))

    # Spawn player
    player = Player.new(Vector2i(0, 0), grid_manager)
    add_child(player)
```

### References

- Implementation Plan: Phase 8 (Cell Types), Phase 7 overview
- Related: Player (Issue #10), Cell types (Issue #4)
- Target: Week 7-8

### Dependencies

- Depends on: Issue #10 (Player class)
- Depends on: Issue #4 (Cell with types)

---

## Additional Notes

### Phase 7 Overview

**Total Estimated Time:** 4-5 hours

**Goals:**
- Implement player character with satisfying movement
- Integrate player with fold validation system
- Establish win condition and level structure
- Test gameplay feel before tackling complex geometric folding
- Validate that the fold mechanics work well with player interaction

### Success Criteria for Phase 7

- ✅ Player moves smoothly on grid
- ✅ Movement respects walls and boundaries
- ✅ Folds blocked when player in the way
- ✅ Clear error messages when fold blocked by player
- ✅ Win condition triggers on goal cell
- ✅ Game feel is good and responsive
- ✅ All test cases pass
- ✅ Ready for Phase 4 (Geometric Folding) with player validation in place

### Why Implement Phase 7 Before Phase 4?

The implementation plan recommends doing Phase 7 (Player) before Phase 4 (Geometric Folding) for several good reasons:

1. **Test Gameplay Early** - Get a feel for how the game plays before investing time in complex folding
2. **Simpler Implementation** - Player movement is much simpler than geometric folding
3. **Establish Validation Patterns** - Learn how player-fold interaction should work with simple folds first
4. **Motivation** - Having a playable game is more motivating than just geometric algorithms
5. **Find Issues Early** - May discover game design issues that affect fold system design

**Recommended Order:**
1. Phase 1 ✅ (Complete)
2. Phase 2 ✅ (Complete)
3. Phase 3 → (Next - Simple folding)
4. **Phase 7** → (After Phase 3 - Player)
5. Phase 4 → (After Phase 7 - Complex geometric folding)
6. Phase 5 → (Multi-seam handling)
7. Phase 6 → (Undo system)
8. Phase 8 → (Polish)
9. Phase 9 → (Testing & optimization)

### Integration with Phase 3

Phase 7 builds directly on Phase 3:
- Uses the FoldSystem from Issue #7
- Extends validation from Issue #8
- Interacts with animations from Issue #9
- Adds player as a new constraint on folds

### Integration with Future Phase 4

When implementing Phase 4 (Geometric Folding), the player validation will need to be extended:

```gdscript
# Additional validation for Phase 4
func validate_fold_with_player(anchor1: Vector2i, anchor2: Vector2i) -> Dictionary:
    # Existing: Check if player in removed region
    if is_player_in_removed_region(anchor1, anchor2):
        return {valid: false, reason: "Cannot fold - player in the way"}

    # NEW for Phase 4: Check if player's cell would be split
    if would_split_player_cell(anchor1, anchor2):
        return {valid: false, reason: "Cannot fold - player on split cell"}

    return {valid: true, reason: ""}
```

This validation framework is established in Phase 7 and extended in Phase 4.

### Testing Strategy

1. **Unit Tests:** Test player movement logic in isolation
2. **Integration Tests:** Test player with GridManager and FoldSystem
3. **Manual Testing:** Essential for game feel - movement must feel good
4. **Playtest:** Create simple puzzle and solve it
5. **Edge Cases:** Test player at boundaries, on removed cells, etc.

### Level Design Considerations

With player implemented, start thinking about:
- What makes a good puzzle?
- How many folds should a level require?
- How to introduce mechanics gradually?
- Tutorial levels?
- Difficulty progression?

These questions will inform later phases, especially Phase 8 (Polish) and beyond.
