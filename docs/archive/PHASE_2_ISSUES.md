# Phase 2 GitHub Issues - Basic Grid System

This document contains all issues for Phase 2 of the Space-Folding Puzzle Game implementation. Each issue is structured to be copy-pasted directly into GitHub.

---

## Issue 4: Implement Cell Class

**Title:** Implement Cell Class with Geometry Support

**Labels:** `core`, `phase-2`, `grid-system`

**Priority:** High

**Estimated Time:** 1-2 hours

**Description:**

Implement the `Cell` class that represents individual grid cells with support for polygon geometry, cell types, and seam tracking. This is foundational for the grid system and folding mechanics.

### Tasks

#### Core Implementation

- [ ] Create `scripts/core/Cell.gd` file
- [ ] Define `Cell` class extending Node2D
- [ ] Implement properties:
  ```gdscript
  var grid_position: Vector2i        # Position in grid
  var geometry: PackedVector2Array   # Polygon vertices (initially square)
  var cell_type: int = 0             # 0=empty, 1=wall, 2=water, 3=goal
  var is_partial: bool = false       # True if cell has been split
  var seams: Array[Dictionary] = []  # Track seam information
  var polygon_visual: Polygon2D      # Visual representation
  ```

#### Key Methods

- [ ] Implement `_init(pos: Vector2i, world_pos: Vector2, size: float)`
  - Initialize grid_position
  - Create square geometry (4 corners)
  - Set up Polygon2D visual node
  - Set initial cell_type
- [ ] Implement `get_center() -> Vector2`
  - Use `GeometryCore.polygon_centroid()`
  - Return center point of cell geometry
- [ ] Implement `add_seam(seam_data: Dictionary)`
  - Store seam metadata (angle, intersection points, fold_id)
  - Track for multi-seam handling later
- [ ] Implement `set_cell_type(type: int)`
  - Update cell_type property
  - Update visual color/appearance
- [ ] Implement `update_visual()`
  - Refresh Polygon2D node with current geometry
  - Apply color based on cell_type
  - Update collision shape if needed

#### Visual Setup

- [ ] Create Polygon2D node for rendering
- [ ] Define color scheme for cell types:
  - Empty: Light gray (#CCCCCC)
  - Wall: Dark gray (#333333)
  - Water: Blue (#3366FF)
  - Goal: Green (#33FF33)
- [ ] Add subtle border/outline to cells
- [ ] Set up proper z-ordering

#### Helper Functions

- [ ] Implement `contains_point(point: Vector2) -> bool`
  - Check if point is inside cell geometry
  - Use polygon containment test
- [ ] Implement `is_square() -> bool`
  - Return true if geometry is still a perfect square
  - Check vertex count and angles

### Testing Requirements

Create test scenarios in `scripts/tests/test_cell.gd`:

- [ ] Test cell initialization with correct grid position
- [ ] Test square geometry creation (4 vertices in correct positions)
- [ ] Test `get_center()` returns correct centroid
- [ ] Test `contains_point()` for points inside/outside
- [ ] Test cell type changes update correctly
- [ ] Test seam data storage
- [ ] Test visual node creation and updates

### Acceptance Criteria

- Cell class created and properly structured
- All properties initialized correctly
- Methods work as expected
- Visual rendering displays correctly
- Cell types have distinct appearances
- Geometry manipulation supported (ready for splitting in Phase 4)
- All test cases pass
- No memory leaks (proper node cleanup)

### Implementation Notes

**Initial Geometry:**
```gdscript
func _init(pos: Vector2i, world_pos: Vector2, size: float):
    grid_position = pos

    # Create square geometry
    geometry = PackedVector2Array([
        world_pos,                          # Top-left
        world_pos + Vector2(size, 0),       # Top-right
        world_pos + Vector2(size, size),    # Bottom-right
        world_pos + Vector2(0, size)        # Bottom-left
    ])

    # Set up visual
    polygon_visual = Polygon2D.new()
    add_child(polygon_visual)
    update_visual()
```

**Cell Type Colors:**
```gdscript
func get_cell_color() -> Color:
    match cell_type:
        0: return Color(0.8, 0.8, 0.8)  # Empty - light gray
        1: return Color(0.2, 0.2, 0.2)  # Wall - dark gray
        2: return Color(0.2, 0.4, 1.0)  # Water - blue
        3: return Color(0.2, 1.0, 0.2)  # Goal - green
        _: return Color(1.0, 1.0, 1.0)  # Default - white
```

### References

- Implementation Plan: Phase 2.1
- Target: Week 1
- Related: GeometryCore utilities (Issue #2)

### Dependencies

- Depends on: Issue #1 (Project structure)
- Depends on: Issue #2 (GeometryCore utilities)

---

## Issue 5: Implement GridManager Class

**Title:** Implement GridManager Class for 10x10 Grid

**Labels:** `core`, `phase-2`, `grid-system`

**Priority:** High

**Estimated Time:** 1.5-2 hours

**Description:**

Implement the `GridManager` class that manages the 10x10 grid of cells, handles cell creation, provides grid queries, and manages the anchor selection system.

### Tasks

#### Core Implementation

- [ ] Create `scripts/core/GridManager.gd` file
- [ ] Define `GridManager` class extending Node2D
- [ ] Implement properties:
  ```gdscript
  var grid_size := Vector2i(10, 10)
  var cell_size := 64.0
  var cells: Dictionary = {}              # Vector2i -> Cell
  var selected_anchors: Array[Vector2i] = []
  var grid_origin: Vector2 = Vector2.ZERO
  ```

#### Initialization Methods

- [ ] Implement `_ready()`
  - Initialize 10x10 grid
  - Create all Cell instances
  - Store cells in dictionary with grid position as key
  - Center grid on screen
- [ ] Implement `create_grid()`
  - Loop through grid_size (10x10)
  - Create Cell for each position
  - Calculate world position for each cell
  - Add cells as children

#### Query Methods

- [ ] Implement `get_cell(grid_pos: Vector2i) -> Cell`
  - Return cell at grid position
  - Return null if position out of bounds
- [ ] Implement `get_cell_at_world_pos(world_pos: Vector2) -> Cell`
  - Convert world position to grid position
  - Return corresponding cell
  - Handle partial cells by checking polygon containment
- [ ] Implement `is_valid_position(grid_pos: Vector2i) -> bool`
  - Check if position is within grid bounds
  - Return false for out-of-bounds positions
- [ ] Implement `get_neighbors(grid_pos: Vector2i) -> Array[Cell]`
  - Return array of adjacent cells (up, down, left, right)
  - Filter out null/invalid positions
  - Useful for pathfinding later

#### Grid Utility Methods

- [ ] Implement `world_to_grid(world_pos: Vector2) -> Vector2i`
  - Convert world coordinates to grid coordinates
  - Account for grid_origin
- [ ] Implement `grid_to_world(grid_pos: Vector2i) -> Vector2`
  - Convert grid coordinates to world coordinates
  - Return top-left corner of cell
- [ ] Implement `get_grid_bounds() -> Rect2`
  - Return bounding rectangle of entire grid
  - Useful for camera setup

#### Debug and Visualization

- [ ] Implement `draw_grid_lines()` (optional)
  - Draw debug lines showing grid structure
  - Toggle with debug flag
- [ ] Implement `_draw()` override (optional)
  - Show grid coordinates in debug mode
  - Display cell counts

### Testing Requirements

Create test scenarios in `scripts/tests/test_grid_manager.gd`:

- [ ] Test grid initialization creates 100 cells (10x10)
- [ ] Test all cells have correct grid positions
- [ ] Test `get_cell()` returns correct cell
- [ ] Test `get_cell()` returns null for invalid position
- [ ] Test `get_cell_at_world_pos()` hit detection
- [ ] Test `world_to_grid()` conversion accuracy
- [ ] Test `grid_to_world()` conversion accuracy
- [ ] Test `is_valid_position()` bounds checking
- [ ] Test `get_neighbors()` returns 4 neighbors for center cell
- [ ] Test `get_neighbors()` returns 2-3 neighbors for edge cells
- [ ] Test cells are properly positioned in world space

### Acceptance Criteria

- GridManager creates 10x10 grid successfully
- All 100 cells are properly initialized
- Cells are correctly positioned in world space
- Query methods work correctly
- Coordinate conversion is accurate
- Grid is centered on screen
- All test cases pass
- No performance issues with cell lookups
- Memory usage is reasonable

### Implementation Notes

**Grid Initialization:**
```gdscript
func _ready():
    create_grid()
    center_grid_on_screen()

func create_grid():
    for y in range(grid_size.y):
        for x in range(grid_size.x):
            var grid_pos = Vector2i(x, y)
            var world_pos = grid_to_world(grid_pos)

            var cell = Cell.new(grid_pos, world_pos, cell_size)
            cells[grid_pos] = cell
            add_child(cell)

func center_grid_on_screen():
    var viewport_size = get_viewport_rect().size
    var grid_pixel_size = Vector2(grid_size) * cell_size
    grid_origin = (viewport_size - grid_pixel_size) / 2
    position = grid_origin
```

**Coordinate Conversion:**
```gdscript
func world_to_grid(world_pos: Vector2) -> Vector2i:
    var local_pos = world_pos - grid_origin
    return Vector2i(
        int(local_pos.x / cell_size),
        int(local_pos.y / cell_size)
    )

func grid_to_world(grid_pos: Vector2i) -> Vector2:
    return grid_origin + Vector2(grid_pos) * cell_size
```

**Cell Type Setup (Optional):**
For testing, you may want to set some cells as walls:
```gdscript
func setup_test_walls():
    # Example: Create border walls
    for x in range(grid_size.x):
        get_cell(Vector2i(x, 0)).set_cell_type(1)  # Top wall
        get_cell(Vector2i(x, grid_size.y - 1)).set_cell_type(1)  # Bottom wall
```

### References

- Implementation Plan: Phase 2.2
- Target: Week 1
- Related: Cell class (Issue #4)

### Dependencies

- Depends on: Issue #4 (Cell class must be implemented first)

---

## Issue 6: Implement Anchor Selection System

**Title:** Implement Anchor Selection System with Visual Feedback

**Labels:** `ui`, `phase-2`, `interaction`

**Priority:** High

**Estimated Time:** 1-2 hours

**Description:**

Implement the anchor selection system that allows players to select two cells as anchor points for folding. Includes visual feedback with colored outlines and hover effects.

### Tasks

#### Input Handling

- [ ] Add input handling to GridManager
- [ ] Implement `_unhandled_input(event)` method
- [ ] Handle mouse click events
- [ ] Handle mouse motion for hover effects
- [ ] Convert mouse position to grid coordinates

#### Selection Logic

- [ ] Implement `select_cell(grid_pos: Vector2i)`
  - Add cell to selected_anchors array
  - First click: add as anchor 1
  - Second click: add as anchor 2
  - Third click: clear selection and start over
  - Ignore clicks on invalid positions
- [ ] Implement `clear_selection()`
  - Clear selected_anchors array
  - Remove visual feedback from all cells
- [ ] Implement `get_selected_anchors() -> Array[Vector2i]`
  - Return array of selected anchor positions
  - Used by fold system later

#### Visual Feedback System

- [ ] Implement outline/highlight for selected cells
- [ ] First anchor: Red outline (#FF0000)
- [ ] Second anchor: Blue outline (#0000FF)
- [ ] Hover effect: Yellow highlight (#FFFF00, semi-transparent)
- [ ] Preview line between anchors when 2 selected
- [ ] Add visual feedback methods to Cell class:
  - `set_outline_color(color: Color)`
  - `set_hover_highlight(enabled: bool)`
  - `clear_visual_feedback()`

#### Preview Line Rendering

- [ ] Create Line2D node for preview line
- [ ] Implement `update_preview_line()`
  - Draw line between two selected anchors
  - Only show when exactly 2 anchors selected
  - Use dashed line pattern
  - Color: White or cyan
  - Width: 3-4 pixels
- [ ] Hide preview line when selection cleared

#### UI Polish

- [ ] Add selection counter display (optional)
  - Show "Select anchor 1" / "Select anchor 2"
  - Show selected coordinates
- [ ] Add sound effects for selection (optional)
- [ ] Add particle effect at selection point (optional)
- [ ] Smooth transition for visual feedback

### Testing Requirements

Create test scenarios in `scripts/tests/test_anchor_selection.gd`:

- [ ] Test selecting first anchor updates visual
- [ ] Test selecting second anchor updates visual
- [ ] Test third click clears selection
- [ ] Test clicking same cell twice
- [ ] Test clicking invalid position (out of bounds)
- [ ] Test `get_selected_anchors()` returns correct positions
- [ ] Test hover effects show/hide correctly
- [ ] Test preview line appears with 2 anchors
- [ ] Test preview line disappears when selection cleared
- [ ] Test multiple selection/clear cycles

### Manual Testing Checklist

- [ ] Run game and verify grid appears
- [ ] Click cell - should show red outline
- [ ] Click another cell - should show blue outline
- [ ] Preview line should appear between anchors
- [ ] Click third cell - should clear all and start over
- [ ] Hover over cells shows yellow highlight
- [ ] Visual feedback is clear and responsive

### Acceptance Criteria

- Can select exactly 2 anchor cells
- Visual feedback is clear and intuitive
- First anchor shows red outline
- Second anchor shows blue outline
- Third click resets selection
- Hover effects work smoothly
- Preview line displays correctly
- Invalid clicks are ignored gracefully
- All test cases pass
- System is responsive (no lag)
- Ready for fold system integration (Phase 3)

### Implementation Notes

**Input Handling:**
```gdscript
func _unhandled_input(event):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            var world_pos = get_global_mouse_position()
            var cell = get_cell_at_world_pos(world_pos)
            if cell:
                select_cell(cell.grid_position)

    elif event is InputEventMouseMotion:
        var world_pos = get_global_mouse_position()
        update_hover_feedback(world_pos)
```

**Selection Logic:**
```gdscript
func select_cell(grid_pos: Vector2i):
    # Clear previous hover
    clear_all_hover_effects()

    # Handle selection based on count
    if selected_anchors.size() == 0:
        # First anchor
        selected_anchors.append(grid_pos)
        get_cell(grid_pos).set_outline_color(Color.RED)

    elif selected_anchors.size() == 1:
        # Second anchor
        selected_anchors.append(grid_pos)
        get_cell(grid_pos).set_outline_color(Color.BLUE)
        update_preview_line()

    else:
        # Third click - reset
        clear_selection()
        selected_anchors.append(grid_pos)
        get_cell(grid_pos).set_outline_color(Color.RED)
```

**Visual Feedback in Cell:**
```gdscript
# Add to Cell class
var outline_color: Color = Color.TRANSPARENT
var is_hovered: bool = false

func set_outline_color(color: Color):
    outline_color = color
    queue_redraw()

func set_hover_highlight(enabled: bool):
    is_hovered = enabled
    queue_redraw()

func _draw():
    # Draw outline if selected
    if outline_color.a > 0:
        draw_polyline(geometry, outline_color, 4.0, true)

    # Draw hover effect
    if is_hovered:
        draw_colored_polygon(geometry, Color(1, 1, 0, 0.3))
```

**Preview Line:**
```gdscript
var preview_line: Line2D

func _ready():
    preview_line = Line2D.new()
    preview_line.width = 3.0
    preview_line.default_color = Color.CYAN
    preview_line.visible = false
    add_child(preview_line)

func update_preview_line():
    if selected_anchors.size() == 2:
        var pos1 = get_cell(selected_anchors[0]).get_center()
        var pos2 = get_cell(selected_anchors[1]).get_center()

        preview_line.points = PackedVector2Array([pos1, pos2])
        preview_line.visible = true
    else:
        preview_line.visible = false
```

### References

- Implementation Plan: Phase 2.3
- Target: Week 1
- Related: Cell class (Issue #4), GridManager (Issue #5)

### Dependencies

- Depends on: Issue #4 (Cell class)
- Depends on: Issue #5 (GridManager class)

---

## Additional Notes

### Phase 2 Overview

**Total Estimated Time:** 4-6 hours

**Goals:**
- Create functional grid system with 10x10 cells
- Implement cell geometry and visual rendering
- Enable anchor selection for fold preparation
- Establish foundation for fold mechanics (Phase 3)

### Success Criteria for Phase 2

- ✅ Cell class fully implemented with polygon geometry
- ✅ GridManager creates and manages 10x10 grid
- ✅ All cells render correctly with proper colors
- ✅ Anchor selection system works intuitively
- ✅ Visual feedback is clear (red/blue outlines, hover effects)
- ✅ Preview line displays between selected anchors
- ✅ All coordinate conversions work accurately
- ✅ All test cases pass
- ✅ Ready for Phase 3 (Simple Axis-Aligned Folding)

### Next Phase Preview

Phase 3 will implement:
- FoldSystem for executing folds
- Fold validation with player position
- Basic axis-aligned folding (horizontal/vertical)
- Visual animations for fold operations
- Fold preview and execution

These components will use the anchor selection system from Phase 2 to perform actual grid transformations.

### Integration Points

The Phase 2 implementation provides these interfaces for Phase 3:
- `GridManager.get_selected_anchors()` - Get the two anchor points
- `Cell.geometry` - Polygon vertices for splitting operations
- `GridManager.get_cell()` - Access cells for fold operations
- Visual feedback system - Extend for fold validation feedback

### Testing Strategy

1. **Unit Tests:** Test each class and method in isolation
2. **Integration Tests:** Test GridManager with Cells
3. **Manual Testing:** Verify visual feedback and interactions
4. **Performance Tests:** Ensure smooth rendering of 100 cells

Run all tests with GUT framework:
```bash
godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/
```
