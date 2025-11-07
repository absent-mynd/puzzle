# API Reference

**Purpose:** Quick lookup for classes, methods, and key constants.

**Last Updated:** 2025-11-07

---

## Core Classes

### GeometryCore

**File:** `scripts/utils/GeometryCore.gd`
**Type:** Static utility class

Provides all geometric calculations for the fold system.

#### Constants

```gdscript
const EPSILON = 0.0001  # Floating point comparison threshold
```

#### Methods

##### `point_side_of_line(point: Vector2, line_point: Vector2, line_normal: Vector2) -> float`

Determines which side of a line a point is on.

**Parameters:**
- `point`: Point to test
- `line_point`: Any point on the line
- `line_normal`: Normal vector of the line (perpendicular to line direction)

**Returns:**
- Negative: Point on left/negative side
- Zero (within EPSILON): Point on line
- Positive: Point on right/positive side

**Example:**
```gdscript
var side = GeometryCore.point_side_of_line(
    Vector2(0, 5),    # Point to test
    Vector2(5, 5),    # Line point
    Vector2(1, 0)     # Line normal (pointing right)
)
# side < 0 (point is on left side)
```

---

##### `segment_line_intersection(seg_start: Vector2, seg_end: Vector2, line_point: Vector2, line_normal: Vector2) -> Variant`

Finds intersection point between a line segment and an infinite line.

**Parameters:**
- `seg_start`: Segment start point
- `seg_end`: Segment end point
- `line_point`: Any point on the line
- `line_normal`: Normal vector of the line

**Returns:**
- `Vector2`: Intersection point if segment crosses line
- `null`: No intersection (segment parallel to line or doesn't cross)

**Example:**
```gdscript
var intersection = GeometryCore.segment_line_intersection(
    Vector2(0, 0), Vector2(10, 10),  # Diagonal segment
    Vector2(5, 0), Vector2(0, 1)      # Horizontal line at y=0
)
# intersection == Vector2(0, 0)
```

---

##### `split_polygon_by_line(vertices: PackedVector2Array, line_point: Vector2, line_normal: Vector2) -> Dictionary`

Splits a polygon by an infinite line using Sutherland-Hodgman algorithm.

**Parameters:**
- `vertices`: Polygon vertices in order (clockwise or counter-clockwise)
- `line_point`: Any point on the splitting line
- `line_normal`: Normal vector of the line

**Returns:**
```gdscript
{
    "left": PackedVector2Array,      # Vertices on left/negative side
    "right": PackedVector2Array,     # Vertices on right/positive side
    "intersections": Array[Vector2]  # Intersection points (0 or 2)
}
```

**Example:**
```gdscript
var square = PackedVector2Array([
    Vector2(0, 0), Vector2(10, 0),
    Vector2(10, 10), Vector2(0, 10)
])

var result = GeometryCore.split_polygon_by_line(
    square,
    Vector2(5, 0),   # Line through middle
    Vector2(1, 0)    # Normal pointing right
)

# result.left = left half of square
# result.right = right half of square
# result.intersections = [Vector2(5, 0), Vector2(5, 10)]
```

---

##### `polygon_area(vertices: PackedVector2Array) -> float`

Calculates the area of a polygon.

**Parameters:**
- `vertices`: Polygon vertices in order

**Returns:**
- Area in square units (always positive)

**Example:**
```gdscript
var area = GeometryCore.polygon_area(square_vertices)
# area == 6400.0 for 64x64 square
```

---

##### `polygon_centroid(vertices: PackedVector2Array) -> Vector2`

Calculates the centroid (center of mass) of a polygon.

**Parameters:**
- `vertices`: Polygon vertices in order

**Returns:**
- Centroid position

**Example:**
```gdscript
var center = GeometryCore.polygon_centroid(square_vertices)
# center == Vector2(32, 32) for 64x64 square at origin
```

---

##### `validate_polygon(vertices: PackedVector2Array) -> bool`

Checks if a polygon is valid (no self-intersections).

**Parameters:**
- `vertices`: Polygon vertices to validate

**Returns:**
- `true`: Valid polygon
- `false`: Self-intersecting or degenerate

---

### Cell

**File:** `scripts/core/Cell.gd`
**Extends:** `Node2D`

Represents a single grid cell. Can be a regular square cell or a partial polygon cell after being split by a fold.

#### Properties

```gdscript
var grid_position: Vector2i              # Grid coordinates (e.g., Vector2i(5, 3))
var geometry: PackedVector2Array         # Polygon vertices in LOCAL coordinates
var cell_type: int = 0                   # 0=empty, 1=wall, 2=water, 3=goal
var is_partial: bool = false             # True if cell has been split
var seams: Array[Seam] = []              # Seam metadata (Phase 5)
var polygon_visual: Polygon2D            # Visual representation
```

#### Methods

##### `_init(pos: Vector2i, local_pos: Vector2, size: float)`

Initialize cell as a square.

**Parameters:**
- `pos`: Grid position (e.g., Vector2i(5, 3))
- `local_pos`: Position in LOCAL coordinates relative to GridManager
- `size`: Cell size in pixels (typically 64.0)

**Example:**
```gdscript
var cell = Cell.new(Vector2i(5, 3), Vector2(320, 192), 64.0)
```

---

##### `apply_split(split_result: Dictionary) -> Cell`

Split this cell into two cells using polygon split result.

**Parameters:**
- `split_result`: Result from `GeometryCore.split_polygon_by_line()`

**Returns:**
- New Cell containing the other half of the split

**Notes:**
- This cell keeps one half
- Returns new cell with other half
- Both cells have `is_partial = true`

---

##### `get_center() -> Vector2`

Calculate centroid of cell geometry.

**Returns:**
- Center point in LOCAL coordinates

**Example:**
```gdscript
var center = cell.get_center()
player.position = grid_manager.to_global(center)  # Convert to world coords
```

---

##### `add_seam(seam_data: Dictionary)`

Add seam metadata to cell (Phase 5).

**Parameters:**
- `seam_data`: Dictionary with fold_id, angle, intersection points

---

### GridManager

**File:** `scripts/core/GridManager.gd`
**Extends:** `Node2D`

Manages the entire grid of cells.

#### Properties

```gdscript
var grid_size: Vector2i = Vector2i(10, 10)  # Grid dimensions
var cell_size: float = 64.0                  # Cell size in pixels
var cells: Dictionary = {}                   # Vector2i -> Cell mapping
var selected_anchors: Array[Vector2i] = []   # Currently selected anchors (max 2)
var grid_origin: Vector2                     # Centering offset
```

#### Methods

##### `initialize(size: Vector2i, cell_size_val: float)`

Initialize grid with specified size.

**Parameters:**
- `size`: Grid dimensions (e.g., Vector2i(10, 10))
- `cell_size_val`: Cell size in pixels (typically 64.0)

**Example:**
```gdscript
grid_manager.initialize(Vector2i(10, 10), 64.0)
# Creates 100 cells in a 10x10 grid
```

---

##### `get_cell(grid_pos: Vector2i) -> Cell`

Get cell at grid position.

**Parameters:**
- `grid_pos`: Grid coordinates

**Returns:**
- Cell at that position, or `null` if none exists

**Example:**
```gdscript
var cell = grid_manager.get_cell(Vector2i(5, 3))
if cell:
    print("Cell type: ", cell.cell_type)
```

---

##### `get_cell_at_world_pos(world_pos: Vector2) -> Cell`

Get cell at world position (e.g., mouse click position).

**Parameters:**
- `world_pos`: Position in world coordinates

**Returns:**
- Cell at that position, or `null`

**Example:**
```gdscript
func _input(event):
    if event is InputEventMouseButton:
        var cell = grid_manager.get_cell_at_world_pos(event.position)
```

---

##### `select_cell(grid_pos: Vector2i)`

Select a cell as an anchor point.

**Parameters:**
- `grid_pos`: Grid position to select

**Behavior:**
- First click: Add as first anchor (red outline)
- Second click: Add as second anchor (blue outline)
- Third click: Clear anchors and start over

---

##### `grid_to_world(grid_pos: Vector2i) -> Vector2`

Convert grid position to world coordinates.

**Parameters:**
- `grid_pos`: Grid coordinates

**Returns:**
- World position (center of cell)

**Example:**
```gdscript
var world_pos = grid_manager.grid_to_world(Vector2i(5, 3))
```

---

##### `to_global(local_pos: Vector2) -> Vector2`

Convert local position to world coordinates.

**Parameters:**
- `local_pos`: Position in LOCAL coordinates (relative to GridManager)

**Returns:**
- World position

**Example:**
```gdscript
var local_center = cell.get_center()
var world_center = grid_manager.to_global(local_center)
player.position = world_center
```

---

##### `to_local(world_pos: Vector2) -> Vector2`

Convert world position to local coordinates.

**Parameters:**
- `world_pos`: Position in world coordinates

**Returns:**
- Local position

---

### FoldSystem

**File:** `scripts/systems/FoldSystem.gd`
**Extends:** `Node`

Manages all folding operations.

#### Constants

```gdscript
const MIN_FOLD_DISTANCE = 0  # Minimum distance between anchors (0 = adjacent allowed)
```

#### Properties

```gdscript
var grid_manager: GridManager     # Reference to grid
var player: Player                # Optional player reference
var seam_lines: Array[Line2D]     # Visual seam indicators
var fold_history: Array[Dictionary]  # Fold operation history
```

#### Methods

##### `execute_horizontal_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool`

Execute a horizontal fold (same row).

**Parameters:**
- `anchor1`: First anchor (left)
- `anchor2`: Second anchor (right)

**Returns:**
- `true` if fold succeeded
- `false` if fold failed validation

**Behavior:**
- Removes cells between anchors
- Shifts cells right of anchor2 to left by (anchor2.x - anchor1.x)
- Merges cells at anchor positions
- Creates seam line at merge position

---

##### `execute_vertical_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool`

Execute a vertical fold (same column).

**Parameters:**
- `anchor1`: First anchor (top)
- `anchor2`: Second anchor (bottom)

**Returns:**
- `true` if fold succeeded
- `false` if fold failed validation

**Behavior:**
- Removes cells between anchors
- Shifts cells below anchor2 up by (anchor2.y - anchor1.y)
- Merges cells at anchor positions
- Creates seam line at merge position

---

##### `execute_horizontal_fold_animated(anchor1: Vector2i, anchor2: Vector2i, duration: float = 0.5) -> bool`

Execute horizontal fold with animation.

**Parameters:**
- `anchor1`: First anchor
- `anchor2`: Second anchor
- `duration`: Animation duration in seconds

**Returns:**
- `true` if fold succeeded

---

##### `execute_vertical_fold_animated(anchor1: Vector2i, anchor2: Vector2i, duration: float = 0.5) -> bool`

Execute vertical fold with animation.

**Parameters:**
- `anchor1`: First anchor
- `anchor2`: Second anchor
- `duration`: Animation duration in seconds

**Returns:**
- `true` if fold succeeded

---

##### `validate_fold(anchor1: Vector2i, anchor2: Vector2i) -> bool`

Validate that a fold can be executed.

**Parameters:**
- `anchor1`: First anchor
- `anchor2`: Second anchor

**Returns:**
- `true` if fold is valid
- `false` if fold violates constraints

**Checks:**
- Anchors are different positions
- Anchors are aligned (same row or column for Phases 1-3)
- Distance >= MIN_FOLD_DISTANCE

---

##### `validate_fold_with_player(anchor1: Vector2i, anchor2: Vector2i, player_ref: Player) -> bool`

Validate fold considering player position.

**Parameters:**
- `anchor1`: First anchor
- `anchor2`: Second anchor
- `player_ref`: Player to check

**Returns:**
- `true` if fold doesn't affect player
- `false` if player blocks fold

**Blocks fold if:**
- Player is in removed region (between anchors)
- Player is on cell that would be split

---

### Player

**File:** `scripts/core/Player.gd`
**Extends:** `CharacterBody2D`

Player character with grid-based movement.

#### Properties

```gdscript
var grid_position: Vector2i       # Current grid position
var is_moving: bool = false       # True during movement animation
```

#### Methods

##### `set_grid_position(new_pos: Vector2i)`

Set player's grid position and update world position.

**Parameters:**
- `new_pos`: New grid position

**Example:**
```gdscript
player.set_grid_position(Vector2i(5, 3))
```

---

##### `move_to_grid_position(target: Vector2i) -> bool`

Move player to target grid position (with validation).

**Parameters:**
- `target`: Target grid position

**Returns:**
- `true` if move succeeded
- `false` if move blocked (wall, out of bounds)

**Behavior:**
- Checks if target is valid (not a wall, within bounds)
- Animates movement
- Updates grid_position

---

## Constants Reference

### Cell Types

```gdscript
enum CellType {
    EMPTY = 0,    # Walkable
    WALL = 1,     # Blocks movement
    WATER = 2,    # Special rules (future)
    GOAL = 3      # Level completion
}
```

### Geometric Constants

```gdscript
const EPSILON = 0.0001              # GeometryCore floating point threshold
const MIN_FOLD_DISTANCE = 0         # FoldSystem minimum anchor distance
```

### Grid Defaults

```gdscript
const DEFAULT_GRID_SIZE = Vector2i(10, 10)   # Default 10x10 grid
const DEFAULT_CELL_SIZE = 64.0               # Default 64 pixels per cell
```

---

## Data Structures

### Split Result (from GeometryCore)

```gdscript
{
    "left": PackedVector2Array,      # Vertices on negative side
    "right": PackedVector2Array,     # Vertices on positive side
    "intersections": Array[Vector2]  # Intersection points (0 or 2)
}
```

### Fold Operation (Phase 6)

```gdscript
{
    "id": int,                          # Unique fold ID
    "anchor1": Vector2i,                # First anchor
    "anchor2": Vector2i,                # Second anchor
    "affected_cells": Array[Vector2i],  # Cells modified by fold
    "removed_cells": Array[Cell],       # Cells removed (stored for undo)
    "split_data": Array[Dictionary],    # Original geometry before splits
    "created_seams": Array[int],        # Seam IDs created
    "timestamp": int                    # When fold was executed
}
```

### Seam Data (Phase 5)

```gdscript
{
    "fold_id": int,                        # Which fold created this seam
    "angle": float,                        # Seam angle in radians
    "intersection_points": PackedVector2Array,  # Where seam crosses cell
    "cell_type_a": int,                    # Cell type on one side
    "cell_type_b": int,                    # Cell type on other side
    "timestamp": int                       # When seam was created
}
```

---

## Coordinate Systems

### Grid Coordinates (Vector2i)

Discrete grid positions.

```gdscript
var grid_pos = Vector2i(5, 3)  # Column 5, Row 3
```

**Range:** `0` to `grid_size - 1`

---

### Local Coordinates (Vector2)

Positions relative to GridManager.

```gdscript
var local_pos = Vector2(grid_pos) * cell_size
# Vector2i(5, 3) * 64.0 = Vector2(320, 192)
```

**Used for:**
- Cell geometry
- Seam lines (Line2D children of GridManager)

---

### World Coordinates (Vector2)

Absolute pixel positions in game world.

```gdscript
var world_pos = grid_manager.to_global(local_pos)
```

**Used for:**
- Player position
- Mouse input
- Camera positioning

---

## Common Patterns

### Creating a Cell

```gdscript
# Calculate local position
var local_pos = Vector2(grid_pos) * cell_size

# Create cell
var cell = Cell.new(grid_pos, local_pos, cell_size)
cell.cell_type = CellType.EMPTY

# Add to grid
grid_manager.add_child(cell)
grid_manager.cells[grid_pos] = cell
```

---

### Splitting a Cell

```gdscript
# Define split line
var line_point = Vector2(320, 0)
var line_normal = Vector2(1, 0)  # Vertical line

# Split polygon
var split_result = GeometryCore.split_polygon_by_line(
    cell.geometry,
    line_point,
    line_normal
)

# Create new cell from split
if split_result.left.size() > 0 and split_result.right.size() > 0:
    var new_cell = cell.apply_split(split_result)
    grid_manager.add_child(new_cell)
```

---

### Converting Coordinates

```gdscript
# Grid → Local
var local_pos = Vector2(grid_pos) * grid_manager.cell_size

# Local → World
var world_pos = grid_manager.to_global(local_pos)

# World → Local
var local_pos = grid_manager.to_local(world_pos)

# World → Grid
var grid_pos = Vector2i(local_pos / grid_manager.cell_size)
```

---

### Iterating Over Cells

```gdscript
# All cells
for grid_pos in grid_manager.cells.keys():
    var cell = grid_manager.cells[grid_pos]
    print("Cell at ", grid_pos, " type: ", cell.cell_type)

# Cells in a range
for x in range(start_x, end_x):
    for y in range(start_y, end_y):
        var cell = grid_manager.get_cell(Vector2i(x, y))
        if cell:
            # Process cell
            pass
```

---

## Testing Utilities

### Test Setup Pattern

```gdscript
extends GutTest

var grid_manager: GridManager
var fold_system: FoldSystem

func before_each():
    grid_manager = GridManager.new()
    add_child_autofree(grid_manager)
    grid_manager.initialize(Vector2i(10, 10), 64.0)

    fold_system = FoldSystem.new()
    add_child_autofree(fold_system)
    fold_system.grid_manager = grid_manager

func after_each():
    # Cleanup happens automatically with add_child_autofree
    pass
```

---

**For implementation details, see:**
- [ARCHITECTURE.md](ARCHITECTURE.md) - Why things are designed this way
- [DEVELOPMENT.md](DEVELOPMENT.md) - How to use these APIs correctly
- Source code in `scripts/core/` and `scripts/systems/`

---

**Note:** This reference is manually maintained. When adding new classes or methods, update this file.
