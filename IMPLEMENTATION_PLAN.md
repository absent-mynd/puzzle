# Space-Folding Puzzle Game - Implementation Plan

## Project Overview
A Godot 4 puzzle game featuring a unique space-folding mechanic where players can fold a grid by selecting two anchor points, removing the space between them, and merging the grid along arbitrary angles.

## Document Sources
This plan synthesizes information from:
- `claude_code_implementation_guide.md` - Stage-by-stage implementation guide
- `math_utilities_reference.md` - Mathematical utilities and algorithms
- `space_folding_design_exploration.md` - Design decisions and architecture
- `test_scenarios_and_validation.md` - Comprehensive test cases

---

## Phase 1: Project Setup & Foundation (Week 1)
**Estimated Time: 2-3 hours**

### 1.1 Create Project Structure
```
SpaceFoldingPuzzle/
├── scenes/
│   ├── main.tscn
│   ├── grid/
│   ├── player/
│   └── ui/
├── scripts/
│   ├── core/           # Cell, Grid, Fold classes
│   ├── systems/        # FoldSystem, UndoManager
│   ├── utils/          # GeometryCore, math utilities
│   └── tests/          # Unit and integration tests
└── assets/
    ├── sprites/
    └── shaders/
```

### 1.2 Implement GeometryCore Utility Class
**Priority: CRITICAL - All folding logic depends on this**

Create `scripts/utils/GeometryCore.gd` with:
- Point-line relationship calculations
- Line-segment intersection detection
- Polygon splitting algorithm (Sutherland-Hodgman)
- Polygon area/centroid calculations
- Polygon validation (self-intersection checks)

**Key Functions:**
- `point_side_of_line(point, line_point, line_normal) -> int`
- `segment_line_intersection(seg_start, seg_end, line_point, line_normal) -> Variant`
- `split_polygon_by_line(vertices, line_point, line_normal) -> Dictionary`
- `polygon_area(vertices) -> float`
- `polygon_centroid(vertices) -> Vector2`
- `validate_polygon(vertices) -> bool`

**Test Coverage:**
- Test polygon splitting with various angles
- Test edge cases (cuts through vertices)
- Verify area conservation

---

## Phase 2: Basic Grid System (Week 1)
**Estimated Time: 2-3 hours**

### 2.1 Implement Cell Class
**File:** `scripts/core/Cell.gd`

```gdscript
class_name Cell
extends Node2D

var grid_position: Vector2i
var geometry: PackedVector2Array  # Initially square
var cell_type: int = 0  # 0=empty, 1=wall, 2=water, 3=goal
var is_partial: bool = false
var seams: Array[Seam] = []
var polygon_visual: Polygon2D
```

**Key Methods:**
- `_init(pos, world_pos, size)` - Initialize as square
- `apply_split(split_result) -> Cell` - Split into two cells
- `get_center() -> Vector2` - Calculate centroid
- `add_seam(seam_data)` - Track seam information

### 2.2 Implement GridManager Class
**File:** `scripts/core/GridManager.gd`

```gdscript
class_name GridManager
extends Node2D

var grid_size := Vector2i(10, 10)
var cell_size := 64.0
var cells: Dictionary = {}  # Vector2i -> Cell
var selected_anchors: Array[Vector2i] = []
```

**Key Methods:**
- `_ready()` - Initialize 10x10 grid
- `select_cell(grid_pos)` - Handle anchor selection (max 2)
- `get_cell_at_world_pos(pos) -> Cell`
- `validate_selection() -> bool`

### 2.3 Implement Anchor Selection System
**Features:**
- Left-click to select cells as anchors
- First click: red outline
- Second click: blue outline
- Third click: reset and start new selection
- Hover effects for visual feedback

**Tests:**
- Grid generates 100 cells (10x10)
- Cell selection toggles correctly
- Exactly 2 anchors can be selected
- Visual feedback appears correctly

---

## Phase 3: Simple Axis-Aligned Folding (Week 2)
**Estimated Time: 3-4 hours**

### 3.1 Implement Basic FoldSystem
**File:** `scripts/systems/FoldSystem.gd`

```gdscript
class_name FoldSystem
extends Node

func execute_fold(anchor1: Vector2, anchor2: Vector2, grid: GridManager):
    # Only handle same-row or same-column folds initially
    if is_horizontal_fold(anchor1, anchor2):
        execute_horizontal_fold(anchor1, anchor2, grid)
    elif is_vertical_fold(anchor1, anchor2):
        execute_vertical_fold(anchor1, anchor2, grid)
```

**Algorithm for Horizontal Fold:**
1. Identify all cells between anchors
2. Remove those cells from grid
3. Shift cells to the right of anchor2 to be adjacent to anchor1
4. Update world positions
5. Create merged anchor point

### 3.2 Visual Feedback System
- Preview line between anchors before fold
- 0.5 second animation for grid sections moving
- Seam line visualization after fold
- Smooth tweening for cell movement

**Tests:**
- Horizontal fold removes correct cells
- Vertical fold removes correct cells
- Cells maintain relative positions
- Fold operations are stored correctly

---

## Phase 4: Geometric Folding (Weeks 3-4)
**Estimated Time: 6-8 hours**
**⚠️ MOST COMPLEX PHASE - Proceed carefully**

### 4.1 Refactor Cell to Support Polygon Geometry
**Changes to Cell class:**
- `geometry: PackedVector2Array` - Now arbitrary polygon
- Replace ColorRect with Polygon2D for rendering
- Track original geometry for undo

**Decision:** Use Hybrid Grid-Polygon System
- Start with regular grid cells (position + type only)
- Convert to polygon only when split
- Benefits: memory efficient, easier level creation

### 4.2 Implement Fold Line Calculation
```gdscript
func calculate_cut_lines(anchor1: Vector2, anchor2: Vector2) -> Dictionary:
    var fold_vector = anchor2 - anchor1
    var perpendicular = Vector2(-fold_vector.y, fold_vector.x).normalized()

    return {
        "line1": {"point": anchor1, "normal": perpendicular},
        "line2": {"point": anchor2, "normal": perpendicular},
        "fold_axis": {"start": anchor1, "end": anchor2}
    }
```

### 4.3 Implement Cell Processing Algorithm
For each cell during fold:
1. Calculate cell centroid
2. Determine which region it's in:
   - **Kept (left of line1)**: Side1 < 0
   - **Removed (between lines)**: Side1 >= 0 AND Side2 <= 0
   - **Kept (right of line2)**: Side2 > 0
   - **Split by line1**: Cell straddles line1
   - **Split by line2**: Cell straddles line2

3. For split cells:
   - Use `GeometryCore.split_polygon_by_line()`
   - Keep appropriate half
   - Store intersection points as seam data

### 4.4 Cell Merging After Fold
- Find corresponding half-cells on each side
- Merge geometries along seam
- Store seam metadata (angle, points, timestamp)

### 4.5 Critical Edge Cases to Handle

#### Edge Case 1: Cut Through Vertex
When fold line passes exactly through a cell corner:
- Use epsilon comparison (EPSILON = 0.0001)
- Treat vertex on line as part of both sides
- Ensure no degenerate triangles are created

#### Edge Case 2: Near-Parallel Cuts
When anchors are nearly aligned:
- Define `MAX_FOLD_ANGLE = 89.0` degrees
- Reject folds that would create near-parallel cuts
- Fall back to axis-aligned logic if possible

#### Edge Case 3: Minimum Distance
- Define `MIN_FOLD_DISTANCE = 1.0` grid units
- Reject folds with anchors too close
- Prevent same-cell anchor selection

#### Edge Case 4: Boundary Conditions
**Decision:** Bounded Grid Model
- Folds clip at grid boundaries
- Don't create cells outside grid
- More intuitive for players

**Tests:**
- Polygon splitting at 45 degrees
- Corner intersection cases
- Cell merging preserves total area
- Seam data stored correctly
- Near-horizontal folds (89 degrees)
- Very short fold distances

---

## Phase 5: Multi-Seam Handling (Week 5)
**Estimated Time: 4-5 hours**

### 5.1 Implement Seam Data Structure
```gdscript
class Seam:
    var fold_id: int
    var angle: float
    var intersection_points: PackedVector2Array
    var timestamp: int
    var cell_type_a: int  # Type on one side
    var cell_type_b: int  # Type on other side
```

### 5.2 Multi-Seam Cell Handling
**Decision:** Tessellation Approach
- When seams intersect, subdivide cell into convex regions
- Each region tracks its origin cell type
- Seams become edges in the tessellation
- Most robust for complex scenarios

**Algorithm:**
1. Start with cell polygon
2. For each new seam:
   - Split existing polygons
   - Track which sub-polygon came from which side
   - Maintain seam metadata

### 5.3 Seam Rendering System
**Decision:** Combine Shader and Mesh Approaches
- Shaders for cell type blending
- Line2D nodes for seam lines
- Layer seams by timestamp (newest on top)

**Visual Styles:**
- Different colors for different cell type combinations
- Glowing effect on newest seam
- Darker lines on older seams

**Tests:**
- Two perpendicular folds through same cell
- Three folds creating triangle in one cell
- Seam visual ordering is correct
- Cell type preservation across multiple splits

---

## Phase 6: Undo System (Week 6)
**Estimated Time: 4-5 hours**

### 6.1 Implement UndoManager
**File:** `scripts/systems/UndoManager.gd`

```gdscript
class UndoManager:
    var fold_history: Array[FoldOperation] = []
    var cell_fold_map: Dictionary = {}  # cell_id -> Array[fold_id]
    var seam_to_fold_map: Dictionary = {}  # seam_id -> fold_id
```

### 6.2 FoldOperation Data Structure
```gdscript
class FoldOperation:
    var id: int
    var anchor1: Vector2
    var anchor2: Vector2
    var affected_cells: Array[CellID]
    var removed_cells: Array[Cell]  # Store full state
    var split_data: Array[Dictionary]  # Original geometry
    var created_seams: Array[SeamID]
    var timestamp: int
```

### 6.3 Dependency Checking Algorithm
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

### 6.4 Undo Execution
When undoing a fold:
1. Restore split cells to original polygons
2. Re-add removed cells
3. Update world positions (reverse the shift)
4. Remove seam visuals
5. Remove fold from history

### 6.5 Visual Feedback
- Click merged anchor point to attempt undo
- Green outline: can undo
- Red outline: blocked by dependencies
- Show dependency chain on hover (optional)

**Tests:**
- Simple undo of last fold
- Blocked undo due to dependencies
- State fully restored after undo
- Undo oldest fold after non-overlapping newer fold
- Visual feedback for undo availability

---

## Phase 7: Player Character (Week 7)
**Estimated Time: 3-4 hours**

### 7.1 Implement Player Class
**File:** `scripts/core/Player.gd`

```gdscript
class_name Player
extends CharacterBody2D

var grid_position: Vector2i
var target_position: Vector2
var is_moving: bool = false
```

### 7.2 Grid-Based Movement
- Arrow keys or WASD for movement
- Move one cell at a time
- Snap to grid after movement
- Cannot move through walls
- Simple tween animation for smooth movement

### 7.3 Player-Fold Interaction
**Decision:** Proportional Positioning
If player is X% along the distance between anchors, place at X% along the resulting seam.

**Algorithm:**
```gdscript
func handle_player_during_fold(player, anchor1, anchor2, removed_region):
    if player.position in removed_region:
        var t = calculate_position_ratio(player.position, anchor1, anchor2)
        player.position = lerp(anchor1, anchor2, t)
    elif player.cell is split:
        # Keep in remaining portion
        if not point_in_polygon(player.position, player.cell.geometry):
            player.position = player.cell.get_center()
```

### 7.4 Fold Validation with Player
Optional: Prevent folds that would:
- Trap player with no valid moves
- Remove goal cell
- Create unreachable regions

**Tests:**
- Player movement validation
- Player position after fold in removed area
- Player position after fold on split cell
- Fold prevention when it would trap player (if implemented)

---

## Phase 8: Cell Types & Visual Polish (Week 8)
**Estimated Time: 3-4 hours**

### 8.1 Implement Cell Type System
```gdscript
enum CellType {
    EMPTY = 0,    # Walkable
    WALL = 1,     # Blocks movement
    WATER = 2,    # Special rules (optional)
    GOAL = 3      # Level completion
}
```

### 8.2 Cell Type Merging Visuals
When different types merge:
- Define blend rules:
  ```gdscript
  var blend_rules = {
      [CellType.EMPTY, CellType.WALL]: "checkered_pattern",
      [CellType.WATER, CellType.WALL]: "shore_effect",
      # etc...
  }
  ```
- Use shaders for smooth blending
- Maintain gameplay properties (merged wall still blocks)

### 8.3 Polish Elements
- Smooth fold animations with easing
- Particle effects at seam creation
- Sound effects (fold, cell selection, player movement)
- Better visual style for cells (textures, colors)
- UI elements (fold counter, undo button, level info)

---

## Phase 9: Testing & Validation (Week 9)
**Estimated Time: 3-4 hours**

### 9.1 Unit Test Suite
Create tests for:
- Geometric utilities (point-line, intersections, splits)
- Cell operations (splitting, merging)
- Grid operations (fold, undo)
- Player movement logic

**Test Framework:** GUT (Godot Unit Test) or built-in testing

### 9.2 Integration Tests
- Full fold-undo cycles
- Multiple sequential folds
- Player interaction with folds
- Save/load state

### 9.3 Edge Case Validation
Run all scenarios from `test_scenarios_and_validation.md`:
- Cut through vertex
- Near-parallel cuts
- Minimum distance validation
- Triple seam intersection
- Dependent undo blocking

### 9.4 Performance Tests
**Targets:**
- Fold operation: < 100ms for 20x20 grid
- Animation: 60 FPS
- Memory: < 50MB for complex states
- Undo operation: < 50ms

**Optimization Strategy:**
- Pre-calculate cell centroids
- Use spatial partitioning (quadtree) for large grids
- Batch visual updates
- Object pooling for split cells
- Consider MultiMesh for rendering

### 9.5 Debug Visualization Tools
Create debug overlays:
- Show cell vertices and indices
- Visualize cut lines before folding
- Display fold operation data
- Show seam hierarchy
- Cell type color coding

---

## Critical Implementation Notes

### Floating Point Precision
```gdscript
const EPSILON = 0.0001
# NEVER use == with floats
# ALWAYS use: abs(a - b) < EPSILON
```

### Coordinate Systems
Be consistent with:
- Grid coordinates (Vector2i)
- World coordinates (Vector2)
- Local cell coordinates (Vector2)

### Array Modifications
```gdscript
# BAD: Modifying array during iteration
for cell in cells:
    if condition:
        cells.erase(cell)

# GOOD: Copy first
var cells_to_remove = []
for cell in cells:
    if condition:
        cells_to_remove.append(cell)
for cell in cells_to_remove:
    cells.erase(cell)
```

### Memory Management
- Properly free visual nodes when cells removed
- Use `queue_free()` for Node cleanup
- Clear references in dictionaries

### Z-Ordering
- Newest seams must render on top
- Use z_index property
- Maintain seam layer hierarchy

---

## Recommended Development Order

1. **Weeks 1-2:** Phase 1-3 (Foundation + Simple Folding)
   - Get basic grid and axis-aligned folding working

2. **Week 3:** Phase 7 (Player Character)
   - Add player movement with simple folding
   - Test gameplay feel early

3. **Weeks 4-5:** Phase 4 (Geometric Folding)
   - This is the hardest - allocate extra time
   - Test extensively with each sub-task

4. **Week 6:** Phase 5 (Multi-Seam)
   - Only after Phase 4 is solid

5. **Week 7:** Phase 6 (Undo System)
   - Build on stable fold implementation

6. **Week 8:** Phase 8 (Polish)
   - Make it look good

7. **Week 9:** Phase 9 (Testing & Optimization)
   - Validate everything

---

## Risk Mitigation

### High Risk Areas

1. **Geometric Folding (Phase 4)**
   - Most complex algorithms
   - Many edge cases
   - **Mitigation:** Extensive unit testing, incremental implementation

2. **Multi-Seam Tessellation (Phase 5)**
   - Complex polygon subdivision
   - **Mitigation:** Start with simple cases, use visualization tools

3. **Undo Dependencies (Phase 6)**
   - Complex state management
   - **Mitigation:** Clear data structures, thorough testing

### Medium Risk Areas

4. **Performance (Large grids)**
   - May need optimization
   - **Mitigation:** Profile early, implement spatial partitioning if needed

5. **Visual Polish (Phase 8)**
   - Can be time-consuming
   - **Mitigation:** Start simple, iterate based on feedback

---

## Success Criteria

✅ Grid system generates correctly
✅ Anchor selection works intuitively
✅ Axis-aligned folds work correctly
✅ Arbitrary-angle folds work correctly
✅ Cells split and merge properly
✅ Multiple seams handled correctly
✅ Undo system respects dependencies
✅ Player interacts correctly with folds
✅ All edge cases handled
✅ Performance targets met
✅ Visual representation is clear
✅ No geometry validation errors

---

## Design Questions to Resolve During Implementation

1. Should fold animations be interruptible?
2. What happens if player tries to move during fold?
3. Should cells remember original position for undo?
4. How should diagonal movement work for player?
5. Should there be a maximum number of folds per level?
6. Should we show fold count/undo count in UI?
7. Level win condition: just reach goal, or collect items too?
8. Should water cells have special mechanics?

---

## Next Steps

1. Set up Godot 4 project with folder structure
2. Implement GeometryCore.gd (critical foundation)
3. Create basic Cell and GridManager classes
4. Implement simple grid rendering
5. Add anchor selection
6. Start with Phase 3 (simple folding)

**Ready to begin implementation!**
