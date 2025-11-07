# Space-Folding Puzzle Game - Implementation Plan

## Current Project Status (Updated: 2025-11-06)

### Completed Phases ✅
- **Phase 1: Project Setup & Foundation** - All core geometry utilities implemented and tested
- **Phase 2: Basic Grid System** - Cell and GridManager classes fully functional with anchor selection
- **Phase 3: Simple Axis-Aligned Folding** - Horizontal and vertical folds with validation and animations
- **Phase 7: Player Character** - Grid-based movement, fold validation, goal detection

### Current Status Summary
- **225 tests passing** (GeometryCore: 41, Cell: 14, GridManager: 27, FoldSystem: 63, Player: 36, FoldValidation: 32, WinCondition: 12)
- **Test Coverage:** 100% for completed phases
- **CI/CD:** GitHub Actions configured with GUT test automation
- **Pre-push hooks:** Available for local test execution
- **Core Gameplay:** Playable with axis-aligned folds and player movement

### Next Steps (Updated Phase Structure - Now 11 Phases)
- **Phase 4:** Geometric Folding (most complex - diagonal folds at arbitrary angles) ← NEXT CRITICAL
- **Phase 5:** Multi-Seam Handling (cells with multiple intersecting seams)
- **Phase 6:** Undo System (with dependency checking)
- **Phase 8:** Cell Types & Core Visual Elements (water cells, enhanced visuals)
- **Phase 9:** Level Management System (storing, creating, editing, transitioning)
- **Phase 10:** Graphics, GUI & Audio Polish (comprehensive UI and audio)
- **Phase 11:** Testing & Validation (final polish and optimization)

---

## Project Overview
A Godot 4 puzzle game featuring a unique space-folding mechanic where players can fold a grid by selecting two anchor points, removing the space between them, and merging the grid along arbitrary angles.

## Document Sources
This plan synthesizes information from:
- `claude_code_implementation_guide.md` - Stage-by-stage implementation guide
- `math_utilities_reference.md` - Mathematical utilities and algorithms
- `space_folding_design_exploration.md` - Design decisions and architecture
- `test_scenarios_and_validation.md` - Comprehensive test cases

---

## Key Design Decisions

These architectural decisions shape the entire implementation:

✅ **Hybrid Grid-Polygon System** - Start with simple grid cells, convert to polygons only when split (memory efficient, easier level creation)

✅ **Tessellation for Multi-Seams** - When seams intersect, subdivide cells into convex regions (most robust for complex cases)

✅ **Bounded Grid Model** - Folds clip at grid boundaries, don't create cells outside grid (most intuitive for players)

✅ **Player Fold Validation** - **CRITICAL:** Folds are blocked if player is in the removed region OR on a cell that would be split (simplifies player logic, prevents edge cases)

✅ **Shader + Mesh Visuals** - Combine shaders for cell blending with Line2D nodes for seam lines

✅ **Strict Undo Ordering** - Can only undo a fold if it's the newest fold affecting all its cells (simpler than partial resolution)

✅ **Sutherland-Hodgman Polygon Splitting** - Industry-standard algorithm for reliable polygon clipping

---

## Phase 1: Project Setup & Foundation (Week 1) ✅ COMPLETE
**Estimated Time: 2-3 hours**

### 1.1 Create Project Structure ✅
```
SpaceFoldingPuzzle/
├── scenes/
│   ├── main.tscn
│   ├── grid/
│   ├── player/
│   └── ui/                      # UI scenes (menus, HUD, etc.)
│       ├── MainMenu.tscn
│       ├── LevelSelect.tscn
│       ├── LevelEditor.tscn
│       ├── HUD.tscn
│       ├── PauseMenu.tscn
│       ├── LevelComplete.tscn
│       └── Settings.tscn
├── scripts/
│   ├── core/                    # Cell, Grid, Fold, Player, LevelData classes
│   ├── systems/                 # FoldSystem, UndoManager, LevelManager, AudioManager
│   ├── ui/                      # UI controller scripts
│   ├── utils/                   # GeometryCore, math utilities
│   └── tests/                   # Unit and integration tests
├── assets/
│   ├── sprites/                 # Player, cell textures, icons
│   ├── shaders/                 # Visual effects for folding
│   ├── audio/
│   │   ├── music/              # Background music tracks
│   │   └── sfx/                # Sound effects
│   ├── fonts/                  # UI fonts
│   └── themes/                 # UI theme resources
└── levels/                      # Level data files
    ├── campaign/               # Main campaign levels
    ├── custom/                 # User-created levels
    └── level_packs/            # Community level packs
```

### 1.2 Implement GeometryCore Utility Class ✅
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

## Phase 2: Basic Grid System (Week 1) ✅ COMPLETE
**Estimated Time: 2-3 hours**

### 2.1 Implement Cell Class ✅
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

### 2.2 Implement GridManager Class ✅
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

### 2.3 Implement Anchor Selection System ✅
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

## Phase 3: Simple Axis-Aligned Folding ✅ COMPLETE
**Status:** Fully implemented with 63 FoldSystem tests + 32 validation tests passing

**CRITICAL IMPLEMENTATION NOTES FOR NEXT PHASES:**

**Coordinate System (MOST IMPORTANT):**
- Cells use LOCAL coordinates (relative to GridManager.position)
- Formula: `local_pos = Vector2(grid_pos) * cell_size` (NOT grid_to_world!)
- Player uses WORLD coordinates: `grid_manager.to_global(local_pos)`
- Seam lines (Line2D) are children of GridManager: use LOCAL coordinates
- WHY: Cells and Line2D nodes inherit GridManager's position transform

**Folding Behavior:**
- Cells OVERLAP at anchor (merge behavior, not adjacent)
- Shift distance: `anchor2 - anchor1` (full overlap)
- MIN_FOLD_DISTANCE = 0 (adjacent anchors allowed)
- Must FREE overlapped cells to prevent memory leaks

**Player Integration:**
- Player shifts with grid during folds
- Update both grid_position AND world position
- Always use `to_global()` when setting player.position

**See CLAUDE.md for complete implementation details and FoldSystem algorithm**

### 3.1 Implement Basic FoldSystem ✅
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
1. **Validate fold with player position** (see 3.2)
2. Identify all cells between anchors
3. Remove those cells from grid
4. Shift cells to the right of anchor2 to be adjacent to anchor1
5. Update world positions
6. Create merged anchor point

### 3.2 Fold Validation with Player Position
**CRITICAL CONSTRAINT:** Folds are not permitted if:
1. Player is in the region that would be removed (between anchors)
2. Player is on a cell that would be split by the fold seam

```gdscript
func validate_fold_with_player(anchor1: Vector2, anchor2: Vector2, player: Player) -> bool:
    # Check if player is in removed region
    var removed_cells = calculate_removed_cells(anchor1, anchor2)
    if player.grid_position in removed_cells:
        return false  # Fold blocked - player in removed region

    # Check if player's cell would be split
    var player_cell = grid.get_cell(player.grid_position)
    if would_cell_be_split(player_cell, anchor1, anchor2):
        return false  # Fold blocked - player on split cell

    return true  # Fold allowed
```

**Visual Feedback:**
- Show red preview line if fold is blocked by player
- Show green preview line if fold is valid
- Display message: "Cannot fold - player in the way"

### 3.3 Visual Feedback System
- Preview line between anchors before fold
- 0.5 second animation for grid sections moving
- Seam line visualization after fold
- Smooth tweening for cell movement

**Tests:**
- Horizontal fold removes correct cells
- Vertical fold removes correct cells
- Cells maintain relative positions
- Fold operations are stored correctly
- **Fold blocked when player in removed region**
- **Fold blocked when player on cell that would be split**
- **Visual feedback shows red for blocked folds**

---

## Phase 4: Geometric Folding (Weeks 3-4) ← NEXT PRIORITY
**Estimated Time: 6-8 hours**
**⚠️ MOST COMPLEX PHASE - Proceed carefully**

**CRITICAL: Apply Phase 3 Lessons**
- ALL cell geometry operations MUST use LOCAL coordinates
- When splitting cells: new polygons are still in LOCAL coordinates
- Player position updates MUST use `to_global()` conversion
- Seam lines at arbitrary angles: still use LOCAL coordinates for Line2D points
- Cell merging/overlapping: same pattern as Phase 3 (free overlapped cells)
- Coordinate formula: `local_pos = Vector2(grid_pos) * cell_size`

**Key Challenge:**
- Sutherland-Hodgman algorithm already implemented in GeometryCore
- But must ensure all inputs/outputs are in LOCAL coordinate space
- Test coordinate conversions extensively!

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

#### Edge Case 5: Player Position Validation
**CRITICAL:** Must validate before any fold:
- Check if player is in removed region (between cut lines)
- Check if player's cell would be split by either cut line
- Use `GeometryCore.split_polygon_by_line()` to test if player cell intersects
- Block fold and show visual feedback if invalid

```gdscript
func would_cell_be_split(cell: Cell, anchor1: Vector2, anchor2: Vector2) -> bool:
    var cut_lines = calculate_cut_lines(anchor1, anchor2)

    # Check both perpendicular cut lines
    var split1 = GeometryCore.split_polygon_by_line(
        cell.geometry, cut_lines.line1.point, cut_lines.line1.normal
    )
    var split2 = GeometryCore.split_polygon_by_line(
        cell.geometry, cut_lines.line2.point, cut_lines.line2.normal
    )

    # Cell is split if either line divides it
    return split1.intersections.size() > 0 or split2.intersections.size() > 0
```

**Tests:**
- Polygon splitting at 45 degrees
- Corner intersection cases
- Cell merging preserves total area
- Seam data stored correctly
- Near-horizontal folds (89 degrees)
- Very short fold distances
- **Player position validation blocks folds correctly**
- **Diagonal fold blocked when player cell would be split**

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
**SIMPLIFIED DESIGN:** Folds that affect the player are prevented entirely.

Since fold validation (Phase 3.2 and Phase 4.5) blocks any fold where:
- Player is in the removed region
- Player's cell would be split

**No special player relocation logic is needed!**

The fold system simply calls the validation function before executing:
```gdscript
func attempt_fold(anchor1: Vector2, anchor2: Vector2):
    if not validate_fold_with_player(anchor1, anchor2, player):
        show_error_message("Cannot fold - player in the way")
        show_red_preview_line(anchor1, anchor2)
        return false

    execute_fold(anchor1, anchor2)
    return true
```

### 7.4 Optional: Advanced Validation
For additional puzzle design constraints, you may also want to prevent folds that:
- Remove the goal cell
- Create unreachable regions (trap player)
- Leave player with no valid moves

These are **optional** enhancements for level validation.

**Tests:**
- Player movement in four directions
- Movement blocked by walls
- **Fold attempt blocked when player in removed region**
- **Fold attempt blocked when player on cell that would split**
- **Error message displays correctly**
- **Preview line shows red for invalid folds**

---

## Phase 8: Cell Types & Core Visual Elements (Week 8)
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

### 8.3 Goal Detection and Win Condition
- Detect when player reaches goal cell
- Handle win condition (level complete)
- Prepare for level transition system

### 8.4 Basic Animation System
- Smooth fold animations with easing
- Cell movement tweening
- Basic particle effects at seam creation

**Tests:**
- Cell type behaviors work correctly
- Goal detection triggers properly
- Cell type merging preserves gameplay rules
- Animations complete without errors

---

## Phase 9: Level Management System (Week 9)
**Estimated Time: 5-6 hours**

### 9.1 Level Data Structure
**File:** `scripts/core/LevelData.gd`

```gdscript
class_name LevelData
extends Resource

@export var level_id: String
@export var level_name: String
@export var grid_size: Vector2i = Vector2i(10, 10)
@export var cell_size: float = 64.0
@export var player_start_position: Vector2i
@export var cell_data: Dictionary = {}  # Vector2i -> CellType
@export var difficulty: int = 1  # 1-5 rating
@export var max_folds: int = -1  # -1 = unlimited
@export var par_folds: int = -1  # Target fold count for "perfect"
@export var description: String = ""
@export var metadata: Dictionary = {}  # Author, tags, etc.
```

### 9.2 Level Serialization System
**File:** `scripts/systems/LevelManager.gd`

```gdscript
class_name LevelManager
extends Node

func save_level(level_data: LevelData, file_path: String) -> bool:
    # Serialize level to JSON or .tres (Godot resource)
    # Include: grid layout, cell types, player start, metadata

func load_level(file_path: String) -> LevelData:
    # Deserialize level from file
    # Validate structure and data integrity

func get_level_list() -> Array[String]:
    # Return list of available level files in levels/ directory
```

**Level File Formats:**
- **Option A:** `.tres` files (Godot's native resource format)
  - Pros: Easy integration, built-in editor support
  - Cons: Binary format, harder to version control
- **Option B:** `.json` files (custom JSON format)
  - Pros: Human-readable, easy to version control, web-friendly
  - Cons: Need custom serialization/deserialization
- **Recommended:** Use JSON for portability and version control

**Level Directory Structure:**
```
levels/
├── campaign/
│   ├── 01_introduction.json
│   ├── 02_basic_folding.json
│   ├── 03_diagonal_challenge.json
│   └── ...
├── custom/
│   └── user_created_levels/
└── level_packs/
    └── community_pack_01/
```

### 9.3 Level Loading and Initialization
```gdscript
func initialize_level(level_data: LevelData):
    # Clear current grid
    grid_manager.clear()

    # Set grid dimensions
    grid_manager.grid_size = level_data.grid_size
    grid_manager.cell_size = level_data.cell_size

    # Populate cells with types
    for grid_pos in level_data.cell_data:
        var cell = grid_manager.get_cell(grid_pos)
        cell.cell_type = level_data.cell_data[grid_pos]

    # Position player at start
    player.set_grid_position(level_data.player_start_position)

    # Reset game state
    undo_manager.clear_history()
    fold_count = 0
```

### 9.4 Level Editor System
**File:** `scenes/ui/LevelEditor.tscn` and `scripts/ui/LevelEditor.gd`

**Features:**
- Grid size configuration (5x5 to 20x20)
- Paint tool for cell types (empty, wall, water, goal)
- Player start position placement
- Level metadata editor (name, description, par folds)
- Save/Load level files
- Play-test current level in editor

**UI Components:**
- Toolbar with cell type selection
- Grid view with click-to-paint
- Properties panel for level settings
- File operations (new, open, save, save as)
- Preview mode to test level

**Implementation:**
```gdscript
class_name LevelEditor
extends Control

var current_level: LevelData
var selected_cell_type: int = CellType.EMPTY
var paint_mode: bool = false

func _on_grid_cell_clicked(grid_pos: Vector2i):
    if paint_mode:
        paint_cell(grid_pos, selected_cell_type)

func save_current_level():
    var file_path = level_save_dialog.current_path
    level_manager.save_level(current_level, file_path)

func load_level_for_editing(file_path: String):
    current_level = level_manager.load_level(file_path)
    refresh_editor_grid()
```

### 9.5 Level Transition System
**File:** `scripts/systems/LevelTransitionManager.gd`

```gdscript
class_name LevelTransitionManager
extends Node

signal level_started(level_id: String)
signal level_completed(level_id: String, stats: Dictionary)
signal level_failed(level_id: String)

var current_level_id: String
var campaign_progress: Dictionary = {}  # level_id -> completed/stars/etc

func start_level(level_id: String):
    var level_data = level_manager.load_level_by_id(level_id)
    initialize_level(level_data)
    current_level_id = level_id
    level_started.emit(level_id)

func complete_level(stats: Dictionary):
    # Stats: fold_count, time_elapsed, par_achieved, etc.
    level_completed.emit(current_level_id, stats)
    update_campaign_progress(current_level_id, stats)
    show_level_complete_screen(stats)

func go_to_next_level():
    var next_level = get_next_campaign_level(current_level_id)
    if next_level:
        start_level(next_level)
    else:
        show_campaign_complete_screen()

func restart_level():
    start_level(current_level_id)

func return_to_menu():
    get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
```

### 9.6 Campaign Progress System
**File:** `scripts/systems/ProgressManager.gd`

```gdscript
class_name ProgressManager
extends Node

const SAVE_FILE = "user://campaign_progress.json"

var campaign_data: Dictionary = {
    "levels_completed": [],
    "levels_unlocked": ["01_introduction"],
    "total_folds": 0,
    "best_times": {},  # level_id -> best_time
    "stars_earned": {}  # level_id -> stars (0-3)
}

func save_progress():
    var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
    file.store_string(JSON.stringify(campaign_data))

func load_progress():
    if FileAccess.file_exists(SAVE_FILE):
        var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
        var json_string = file.get_as_text()
        campaign_data = JSON.parse_string(json_string)

func mark_level_complete(level_id: String, stats: Dictionary):
    if level_id not in campaign_data.levels_completed:
        campaign_data.levels_completed.append(level_id)

    # Calculate stars (3 = par or better, 2 = under 1.5x par, 1 = completed)
    var stars = calculate_stars(stats)
    campaign_data.stars_earned[level_id] = max(
        stars,
        campaign_data.stars_earned.get(level_id, 0)
    )

    # Unlock next level
    unlock_next_level(level_id)
    save_progress()

func unlock_next_level(completed_level_id: String):
    var next_level = get_sequential_next_level(completed_level_id)
    if next_level and next_level not in campaign_data.levels_unlocked:
        campaign_data.levels_unlocked.append(next_level)
```

### 9.7 Level Validation System
**File:** `scripts/systems/LevelValidator.gd`

```gdscript
class_name LevelValidator
extends Node

func validate_level(level_data: LevelData) -> Dictionary:
    var errors = []
    var warnings = []

    # Check for required elements
    if not has_player_start(level_data):
        errors.append("No player start position defined")

    if not has_goal(level_data):
        errors.append("No goal cell defined")

    # Check for accessibility
    if not is_goal_reachable(level_data):
        warnings.append("Goal may not be reachable from start")

    # Check for reasonable difficulty
    if level_data.max_folds > 0 and level_data.max_folds < 2:
        warnings.append("Max folds seems very restrictive")

    return {
        "valid": errors.size() == 0,
        "errors": errors,
        "warnings": warnings
    }

func is_goal_reachable(level_data: LevelData) -> bool:
    # Simple pathfinding check (BFS/DFS)
    # Returns true if goal is reachable from start
    # without considering folds
```

### 9.8 Level Selection UI
**Scene:** `scenes/ui/LevelSelect.tscn`

**Features:**
- Grid or list view of campaign levels
- Show level status: locked, unlocked, completed
- Display stars earned per level
- Show level name, difficulty, par folds
- Filter by difficulty or completion status
- "Play" and "Edit" buttons for each level

**Tests:**
- Level saves correctly to JSON
- Level loads with all properties intact
- Level editor can create valid levels
- Campaign progress saves and loads
- Level transitions work smoothly
- Invalid levels are caught by validator
- Progress unlocks next levels correctly

---

## Phase 10: Graphics, GUI & Audio Polish (Week 10)
**Estimated Time: 6-8 hours**

### 10.1 Visual Style and Graphics

#### Cell Visuals
- Design distinct textures/colors for each cell type:
  - Empty: Light gray with subtle grid pattern
  - Wall: Dark stone texture with highlights
  - Water: Animated flowing water shader
  - Goal: Glowing/pulsing effect
- Add border outlines for cell clarity
- Implement proper lighting and shadows

#### Fold Animation Polish
```gdscript
func animate_fold(cells_to_move: Array, target_positions: Array):
    var tween = create_tween()
    tween.set_parallel(true)

    for i in cells_to_move.size():
        tween.tween_property(
            cells_to_move[i],
            "position",
            target_positions[i],
            0.6
        ).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

    # Particle effects
    spawn_fold_particles(fold_line)

    # Camera shake
    camera.apply_shake(0.3, 5.0)
```

#### Seam Visuals
- Glowing animated lines for seams
- Color-code seams by age (newest = bright, older = faded)
- Add "stitching" effect along seam lines
- Particle trails when seams form

#### Player Character Design
- Animated sprite with idle, walk animations
- Directional sprites for 4-way movement
- Footstep particles
- Shadow underneath character

### 10.2 User Interface System

#### Main Menu
**Scene:** `scenes/ui/MainMenu.tscn`

**Components:**
- Title screen with game logo
- Buttons:
  - Play Campaign
  - Level Select
  - Level Editor
  - Settings
  - Credits
  - Quit
- Background animation (subtle fold effect)
- Menu transition animations

#### HUD (Heads-Up Display)
**Scene:** `scenes/ui/HUD.tscn`

**Elements:**
- Fold counter: "Folds: 5 / 8" (current / par)
- Undo button with count
- Pause menu button
- Level name display
- Timer (optional, for speedruns)
- Hint button (optional)

#### Pause Menu
**Scene:** `scenes/ui/PauseMenu.tscn`

**Options:**
- Resume
- Restart Level
- Level Select
- Settings
- Main Menu

#### Level Complete Screen
**Scene:** `scenes/ui/LevelComplete.tscn`

**Display:**
- "Level Complete!" message
- Stars earned (based on fold efficiency)
- Statistics:
  - Folds used
  - Par folds
  - Time elapsed
- Buttons:
  - Next Level
  - Retry (for better score)
  - Level Select

#### Settings Menu
**Scene:** `scenes/ui/Settings.tscn`

**Options:**
- Audio:
  - Master volume
  - Music volume
  - SFX volume
- Graphics:
  - Fullscreen toggle
  - VSync toggle
  - Particle effects on/off
- Controls:
  - Key remapping (future)
- Accessibility:
  - Colorblind mode
  - Animation speed
  - Grid lines on/off

### 10.3 Audio System
**File:** `scripts/systems/AudioManager.gd`

```gdscript
class_name AudioManager
extends Node

var music_bus_index: int
var sfx_bus_index: int

var current_music: AudioStreamPlayer
var music_tracks: Dictionary = {}

func _ready():
    music_bus_index = AudioServer.get_bus_index("Music")
    sfx_bus_index = AudioServer.get_bus_index("SFX")

    # Load audio resources
    load_audio_resources()

func play_music(track_name: String, fade_in: bool = true):
    if current_music and current_music.playing:
        fade_out_music()

    current_music = music_tracks[track_name]

    if fade_in:
        var tween = create_tween()
        current_music.volume_db = -80
        current_music.play()
        tween.tween_property(current_music, "volume_db", 0, 2.0)
    else:
        current_music.play()

func play_sfx(sound_name: String, pitch_variation: float = 0.1):
    var player = AudioStreamPlayer.new()
    add_child(player)
    player.stream = load("res://assets/audio/sfx/" + sound_name + ".ogg")
    player.bus = "SFX"

    # Add slight pitch variation for variety
    player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)

    player.play()
    player.finished.connect(func(): player.queue_free())

func set_music_volume(volume: float):
    AudioServer.set_bus_volume_db(music_bus_index, linear_to_db(volume))

func set_sfx_volume(volume: float):
    AudioServer.set_bus_volume_db(sfx_bus_index, linear_to_db(volume))
```

#### Sound Effects Needed
- **Player Actions:**
  - Footstep (4 variations)
  - Bump into wall
  - Reach goal (victory jingle)
- **Fold System:**
  - Cell selection (click)
  - Anchor placed (confirmation beep)
  - Fold execute (whoosh + spatial warp sound)
  - Fold invalid (error beep)
  - Undo fold (reverse whoosh)
- **UI:**
  - Button hover
  - Button click
  - Menu open/close
  - Level complete fanfare
  - Star earned (3 variations)

#### Music Tracks
- Main menu theme (ambient, mysterious)
- Gameplay background music (calm, thinking music)
- Level complete jingle
- Final level / boss puzzle music (optional)

**Audio Format:** `.ogg` (Vorbis) for compatibility and size

### 10.4 Particle Effects System

#### Fold Particles
```gdscript
var fold_particles = CPUParticles2D.new()
fold_particles.amount = 50
fold_particles.lifetime = 1.0
fold_particles.explosiveness = 0.8
fold_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_LINE
# Spawn along fold line
fold_particles.position = fold_line_center
fold_particles.rotation = fold_angle
```

**Effects to Implement:**
- Sparkles along seam creation
- Grid "tear" effect when removing cells
- Dust particles when cells move
- Glow effect on merged anchor points
- Victory particles when reaching goal

### 10.5 Camera System
**File:** `scripts/core/GameCamera.gd`

```gdscript
class_name GameCamera
extends Camera2D

func follow_player(player: Player):
    # Smooth camera follow
    var tween = create_tween()
    tween.tween_property(self, "position", player.position, 0.3)

func zoom_to_fit_grid(grid_size: Vector2i, cell_size: float):
    # Automatically adjust zoom to fit grid on screen
    var viewport_size = get_viewport_rect().size
    var grid_pixel_size = Vector2(grid_size) * cell_size
    var zoom_factor = min(
        viewport_size.x / grid_pixel_size.x,
        viewport_size.y / grid_pixel_size.y
    ) * 0.9  # 90% to add padding

    zoom = Vector2(zoom_factor, zoom_factor)

func apply_shake(duration: float, intensity: float):
    # Camera shake effect for impactful moments
    var original_offset = offset
    var shake_tween = create_tween()

    for i in range(int(duration * 60)):  # 60 FPS
        var shake_offset = Vector2(
            randf_range(-intensity, intensity),
            randf_range(-intensity, intensity)
        )
        shake_tween.tween_property(
            self, "offset",
            original_offset + shake_offset,
            1.0/60.0
        )

    shake_tween.tween_property(self, "offset", original_offset, 0.1)
```

### 10.6 Theme and Styling

#### UI Theme Resource
Create `assets/themes/main_theme.tres`:
- Button styles (normal, hover, pressed, disabled)
- Label fonts and sizes
- Panel backgrounds
- Color palette:
  - Primary: #4A90E2 (blue)
  - Secondary: #7B68EE (purple)
  - Success: #50C878 (green)
  - Warning: #FFB347 (orange)
  - Error: #E74C3C (red)
  - Background: #2C3E50 (dark blue-gray)
  - Text: #ECF0F1 (light gray)

#### Fonts
- Heading: Bold, large font (e.g., Montserrat Bold)
- Body: Regular, readable font (e.g., Roboto Regular)
- Monospace: For counters and numbers (e.g., Courier New)

### 10.7 Visual Feedback Systems

#### Hover Effects
- Cell hover: Subtle highlight
- Button hover: Color change + scale up slightly
- Anchor preview: Show fold line before committing

#### Selection Indicators
- Selected anchors: Colored outlines (red for first, blue for second)
- Player cell: Subtle glow
- Goal cell: Pulsing animation
- Seam lines: Animated dashed lines

#### Transition Animations
- Scene transitions: Fade to black
- Level start: Grid builds from center
- Level complete: Zoom and particle burst

**Tests:**
- Audio plays correctly without clicks/pops
- Volume controls work for music and SFX
- UI elements are responsive and accessible
- Animations run at 60 FPS
- Camera follows player smoothly
- Particle effects don't cause performance issues
- UI theme is consistent across all screens

---

## Phase 11: Testing & Validation (Week 11)
**Estimated Time: 4-5 hours**

### 11.1 Unit Test Suite
Create tests for:
- Geometric utilities (point-line, intersections, splits)
- Cell operations (splitting, merging)
- Grid operations (fold, undo)
- Player movement logic
- Level loading and saving
- Audio system

**Test Framework:** GUT (Godot Unit Test) or built-in testing

### 11.2 Integration Tests
- Full fold-undo cycles
- Multiple sequential folds
- Player interaction with folds
- Level save/load cycles
- Campaign progression flow
- UI navigation and transitions

### 11.3 Edge Case Validation
Run all scenarios from `test_scenarios_and_validation.md`:
- Cut through vertex
- Near-parallel cuts
- Minimum distance validation
- Triple seam intersection
- Dependent undo blocking
- Level loading edge cases (corrupted files, missing data)
- Audio edge cases (multiple sounds, quick succession)

### 11.4 Performance Tests
**Targets:**
- Fold operation: < 100ms for 20x20 grid
- Animation: 60 FPS
- Memory: < 50MB for complex states
- Undo operation: < 50ms
- Level load time: < 500ms
- UI responsiveness: < 16ms input latency

**Optimization Strategy:**
- Pre-calculate cell centroids
- Use spatial partitioning (quadtree) for large grids
- Batch visual updates
- Object pooling for split cells
- Consider MultiMesh for rendering
- Optimize audio loading (stream vs. preload)

### 11.5 Debug Visualization Tools
Create debug overlays:
- Show cell vertices and indices
- Visualize cut lines before folding
- Display fold operation data
- Show seam hierarchy
- Cell type color coding
- FPS counter and performance stats
- Memory usage display

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

6. **Week 8:** Phase 8 (Cell Types & Core Visuals)
   - Implement gameplay elements

7. **Week 9:** Phase 9 (Level Management)
   - Add level loading, saving, editor
   - Critical for creating content

8. **Week 10:** Phase 10 (Graphics, GUI & Audio)
   - Polish the look and feel
   - Implement full UI system

9. **Week 11:** Phase 11 (Testing & Optimization)
   - Validate everything
   - Final performance optimization

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

5. **Level Editor (Phase 9)**
   - UI complexity and feature creep
   - **Mitigation:** Start with minimal viable editor, add features iteratively

6. **Audio System (Phase 10)**
   - Timing, synchronization, resource loading
   - **Mitigation:** Use proven patterns, test early and often

7. **Visual Polish (Phase 10)**
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
✅ **Fold validation prevents player conflicts (removed region or split cell)**
✅ Level system loads and saves correctly
✅ Level editor creates valid levels
✅ Campaign progression tracks properly
✅ UI is intuitive and responsive
✅ Audio plays without glitches
✅ Graphics are polished and consistent
✅ All edge cases handled
✅ Performance targets met
✅ Visual representation is clear
✅ No geometry validation errors

---

## Design Questions to Resolve During Implementation

1. Should fold animations be interruptible?
2. ~~What happens if player tries to move during fold?~~ **RESOLVED:** Player movement during animation can be blocked.
3. Should cells remember original position for undo?
4. How should diagonal movement work for player?
5. Should there be a maximum number of folds per level?
6. Should we show fold count/undo count in UI?
7. Level win condition: just reach goal, or collect items too?
8. Should water cells have special mechanics?
9. Should folds that remove the goal cell be prevented?
10. Should level files be JSON or .tres format? **RECOMMENDED:** JSON for portability
11. Should the level editor be in-game or separate tool?
12. How should campaign unlocking work? Linear or branching paths?
13. Should there be a tutorial system?
14. What audio style: ambient/mysterious vs. upbeat/puzzle?
15. Should there be a hint system for stuck players?
16. Should levels have a time limit or timer?
17. Should there be achievements/trophies?
18. Should custom levels be shareable (export/import)?

---

## Next Steps

1. ✅ Set up Godot 4 project with folder structure
2. ✅ Implement GeometryCore.gd (critical foundation)
3. ✅ Create basic Cell and GridManager classes
4. ✅ Implement simple grid rendering
5. ✅ Add anchor selection
6. Start with Phase 3 (simple folding)
7. Continue through phases 4-11 as outlined
8. Create initial level content as systems become available
9. Iterate on UI/UX based on playtesting
10. Polish and optimize before release

**Ready to continue implementation!**
