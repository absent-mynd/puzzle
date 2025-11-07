# Architecture & Design Decisions

**Purpose:** This document explains **WHY** things are designed the way they are.

**Last Updated:** 2025-11-07

---

## Core Design Philosophy

**1. Test-Driven Development (TDD)**
- Write tests before implementation
- Tests define expected behavior
- Target: 100% test coverage
- Tests serve as living documentation

**2. Simplicity First**
- Start with simplest solution that works
- Add complexity only when needed
- Clear, readable code over clever code
- Explicit over implicit

**3. Performance Through Design**
- Memory efficient data structures
- Avoid premature optimization
- Profile before optimizing
- Target: < 100ms fold operations, 60 FPS

---

## Critical Architectural Decisions

These decisions shape the entire implementation. **Do not deviate** without careful consideration and team discussion.

---

### Decision 1: Hybrid Grid-Polygon System

**The Decision:**
- Start with simple grid cells (position + type only)
- Convert to polygon geometry ONLY when cell is split by a fold
- Track split state with `is_partial` flag

**Rationale:**
- **Memory efficiency:** 100 grid cells = 100 Vector2i positions vs 100 × 4+ vertices
- **Easier level creation:** Just specify grid position and type
- **Cleaner code:** Most operations work on grid coordinates
- **Performance:** No polygon operations until absolutely needed

**Implementation:**
```gdscript
class_name Cell
extends Node2D

var grid_position: Vector2i          # Always present
var geometry: PackedVector2Array     # Initially square, becomes polygon when split
var is_partial: bool = false         # True if split by fold
```

**Alternatives Considered:**
- ❌ **All polygons from start:** Wasteful memory, complex level creation
- ❌ **Always grid-based:** Can't support diagonal folds
- ✅ **Hybrid approach:** Best of both worlds

**Impact on Future Development:**
- Phase 4: Cells become polygons when split
- Phase 5: Polygon cells can be subdivided further
- Level creation: Simple grid-based level files

---

### Decision 2: Player Fold Validation Rule

**The Decision:**
Folds are blocked if:
1. Player is in the removed region (between fold lines), OR
2. Player is on a cell that would be split by the fold

**Rationale:**
- **Simplifies player logic:** No need to relocate player during fold
- **Prevents edge cases:** What if player on split cell? What if split creates unreachable region?
- **Intuitive gameplay:** Players understand "can't fold through myself"
- **Cleaner code:** Validation is simple check before fold

**Implementation:**
```gdscript
func validate_fold_with_player(anchor1, anchor2, player) -> bool:
    # Check if player in removed region
    var removed_cells = calculate_removed_cells(anchor1, anchor2)
    if player.grid_position in removed_cells:
        return false

    # Check if player cell would be split
    var player_cell = grid.get_cell(player.grid_position)
    if would_cell_be_split(player_cell, anchor1, anchor2):
        return false

    return true
```

**Alternatives Considered:**
- ❌ **Move player automatically:** Complex, unpredictable, can trap player
- ❌ **Allow splits, track player in half-cell:** Very complex geometry
- ❌ **Kill player if in removed region:** Frustrating gameplay
- ✅ **Block folds that affect player:** Simple, intuitive, reliable

**Impact on Future Development:**
- Phase 4: Same validation applies to diagonal folds
- Phase 6: Undo system doesn't need to restore player state
- Level design: Levels can be designed knowing this constraint

---

### Decision 3: Coordinate System Architecture

**The Decision:**
- **Cells store geometry in LOCAL coordinates** (relative to GridManager.position)
- **Player uses WORLD coordinates** (absolute pixel positions)
- **Seam lines (Line2D) use LOCAL coordinates** (children of GridManager)
- **GridManager is positioned at `grid_origin`** (centered on screen)

**Rationale:**
- **Godot's scene tree:** Children inherit parent's transform
- **Cells are children of GridManager:** Inherit GridManager.position transform
- **Player is NOT a child:** Needs absolute positioning for camera follow
- **Consistency:** All cell geometry calculations in same coordinate space
- **Performance:** No repeated conversions during rendering

**Formula:**
```gdscript
# Creating cell geometry (LOCAL coordinates)
var local_pos = Vector2(grid_pos) * cell_size
cell.geometry = create_square(local_pos, cell_size)

# Converting for player (WORLD coordinates)
player.position = grid_manager.to_global(local_pos + offset)
```

**Common Bug:**
```gdscript
# ❌ WRONG - Double offset!
var world_pos = grid_manager.grid_to_world(grid_pos)
cell.geometry = create_square(world_pos, size)
# Cell appears at grid_origin + grid_origin position!

# ✅ CORRECT
var local_pos = Vector2(grid_pos) * cell_size
cell.geometry = create_square(local_pos, size)
```

**Alternatives Considered:**
- ❌ **All world coordinates:** Requires offset adjustments everywhere
- ❌ **All local coordinates:** Player positioning becomes complex
- ❌ **Player as child of GridManager:** Camera follow breaks
- ✅ **Hybrid (local for cells, world for player):** Clear separation of concerns

**Impact on Future Development:**
- Phase 4: Diagonal fold geometry still in LOCAL coordinates
- Phase 5: Tessellation operates in LOCAL coordinate space
- Visual effects: Particle positions need conversion

---

### Decision 4: Folding Behavior - Overlapping at Anchors

**The Decision:**
- Cells at right/bottom anchor **shift to** left/top anchor position
- Cells **overlap/merge** at anchor (not adjacent)
- Shift distance = full distance between anchors
- MIN_FOLD_DISTANCE = 0 (adjacent anchors allowed)

**Rationale:**
- **Intuitive metaphor:** Folding paper brings anchors together
- **Simpler algorithm:** No gap calculations, direct position assignment
- **Cleaner visuals:** Seam at anchor point, not between anchors
- **Flexible gameplay:** Allows maximum grid compression

**Implementation:**
```gdscript
# Horizontal fold example
var shift_distance = right_anchor.x - left_anchor.x

for cell in cells_to_shift:
    var new_pos = Vector2i(cell.grid_position.x - shift_distance, cell.grid_position.y)

    # Free any existing cell at target position (merge)
    var existing_cell = grid.cells.get(new_pos)
    if existing_cell:
        grid.cells.erase(new_pos)
        existing_cell.queue_free()

    # Move cell to new position
    cell.grid_position = new_pos
    grid.cells[new_pos] = cell
```

**Alternatives Considered:**
- ❌ **Adjacent positioning:** More complex, less intuitive
- ❌ **Minimum distance > 0:** Arbitrary restriction
- ❌ **Keep both cells at merge:** Ambiguous, complex visuals
- ✅ **Overlap and merge:** Simple, clear, intuitive

**Impact on Future Development:**
- Phase 4: Same merge behavior for diagonal folds
- Phase 5: Merged cells can have multiple seams
- Memory management: Critical to free overlapped cells

---

### Decision 5: Sutherland-Hodgman Polygon Splitting

**The Decision:**
Use the Sutherland-Hodgman clipping algorithm for polygon splitting by a line.

**Rationale:**
- **Industry standard:** Well-tested, reliable algorithm
- **Handles all cases:** Convex and concave polygons
- **Efficient:** O(n) where n = number of vertices
- **Robust:** Handles edge cases (vertex on line, all vertices on one side)
- **Simple implementation:** Straightforward to code and test

**Implementation:**
```gdscript
# GeometryCore.split_polygon_by_line()
static func split_polygon_by_line(
    vertices: PackedVector2Array,
    line_point: Vector2,
    line_normal: Vector2
) -> Dictionary:
    # Returns: {
    #   "left": PackedVector2Array,    # Vertices on left/negative side
    #   "right": PackedVector2Array,   # Vertices on right/positive side
    #   "intersections": Array[Vector2] # Intersection points
    # }
```

**Alternatives Considered:**
- ❌ **Custom polygon splitting:** Reinventing the wheel, bug-prone
- ❌ **Godot's Geometry2D (limited):** Doesn't provide split functionality
- ❌ **SAT-based approaches:** Overkill for this use case
- ✅ **Sutherland-Hodgman:** Proven, simple, efficient

**Impact on Future Development:**
- Phase 4: Core algorithm for diagonal folds
- Phase 5: Used recursively for tessellation
- Testing: Well-known algorithm makes test cases clear

---

### Decision 6: Bounded Grid Model

**The Decision:**
- Folds clip at grid boundaries
- Don't create cells outside the grid
- Grid size is fixed for each level

**Rationale:**
- **Most intuitive for players:** Understand grid boundaries
- **Simpler implementation:** No infinite grid management
- **Better performance:** Fixed maximum cell count
- **Easier level design:** Clear playfield boundaries

**Implementation:**
```gdscript
# After fold, ensure all cells are within bounds
func clip_to_bounds(grid_pos: Vector2i, grid_size: Vector2i) -> bool:
    return (grid_pos.x >= 0 and grid_pos.x < grid_size.x and
            grid_pos.y >= 0 and grid_pos.y < grid_size.y)
```

**Alternatives Considered:**
- ❌ **Unbounded grid:** Complex scrolling, memory management
- ❌ **Wrap-around (toroidal):** Confusing for players
- ❌ **Dynamic expansion:** When to shrink? Complex edge cases
- ✅ **Bounded with clipping:** Clear, simple, predictable

**Impact on Future Development:**
- Level design: Fixed grid sizes (can vary per level)
- Camera system: Can auto-zoom to fit grid
- Performance: Maximum cells = grid_size.x × grid_size.y

---

### Decision 7: Tessellation for Multi-Seam Handling

**The Decision:**
When seams intersect in a cell, subdivide the cell into convex regions using tessellation.

**Rationale:**
- **Most robust approach:** Handles arbitrary seam intersections
- **Maintains polygon structure:** Each region is still a valid polygon
- **Visual clarity:** Each region can be rendered distinctly
- **Tracks origins:** Know which side of each seam each region came from

**Implementation (Phase 5):**
```gdscript
# When adding new seam to cell with existing seams:
# 1. Split cell polygon by new seam
# 2. For each resulting sub-polygon, check against existing seams
# 3. Recursively subdivide until all seams processed
# 4. Store seam metadata for each sub-polygon
```

**Alternatives Considered:**
- ❌ **Overlapping polygons:** Visual rendering nightmare
- ❌ **Single polygon with holes:** Complex, doesn't track seam relationships
- ❌ **Ignore intersecting seams:** Limits gameplay possibilities
- ✅ **Tessellation:** Complex but handles all cases correctly

**Impact on Future Development:**
- Phase 5: Core algorithm for multi-seam cells
- Rendering: Each sub-polygon can have different shader
- Undo system: Must restore entire tessellation state

---

### Decision 8: Strict Undo Ordering

**The Decision:**
A fold can only be undone if it's the newest fold affecting ALL its cells.

**Rationale:**
- **Simpler implementation:** No partial undo resolution
- **Predictable behavior:** Players understand "undo most recent affecting this area"
- **Avoid complex dependencies:** Don't need to track dependency graphs
- **Sufficient for gameplay:** Most puzzles designed with sequential undo

**Implementation (Phase 6):**
```gdscript
func can_undo_fold(fold_id: int) -> bool:
    var fold = get_fold(fold_id)
    # Check all cells affected by this fold
    for cell_id in fold.affected_cells:
        var cell = get_cell(cell_id)
        # Check all seams in this cell
        for seam in cell.seams:
            var seam_fold = seam_to_fold_map[seam.id]
            # If any seam is from a newer fold, block undo
            if seam_fold.timestamp > fold.timestamp:
                return false
    return true
```

**Alternatives Considered:**
- ❌ **Allow partial undo:** Very complex, unpredictable
- ❌ **Always allow undo (revert newer folds):** Confusing cascade
- ❌ **Unlimited undo history:** Memory concerns
- ✅ **Strict ordering:** Simple, predictable, sufficient

**Impact on Future Development:**
- Gameplay: Encourages thoughtful planning
- Level design: Can design around undo limitations
- UI: Clear visual feedback for undo availability

---

## Implementation Patterns

### Pattern 1: Always Validate Before Fold

```gdscript
func attempt_fold(anchor1, anchor2):
    # ALWAYS validate first
    if not validate_fold(anchor1, anchor2):
        return false

    if player and not validate_fold_with_player(anchor1, anchor2, player):
        show_error_message("Cannot fold - player in the way")
        return false

    # THEN execute
    execute_fold(anchor1, anchor2)
    return true
```

**Why:** Prevents invalid states, provides user feedback

---

### Pattern 2: Test-Driven Development Flow

```gdscript
# 1. Write test FIRST
func test_diagonal_fold_45_degrees():
    var result = fold_system.execute_diagonal_fold(...)
    assert_eq(result.cells_removed, 12)
    assert_not_null(grid.get_cell(Vector2i(7, 2)))

# 2. Run test (fails)
# 3. Implement feature
# 4. Run test (passes)
# 5. Refactor if needed
# 6. Run test again (still passes)
```

**Why:** Defines expected behavior, catches regressions, builds confidence

---

### Pattern 3: Cell Merging with Memory Safety

```gdscript
func merge_cells(source_cell, target_pos):
    # 1. Check if target position already has a cell
    var existing_cell = grid.cells.get(target_pos)

    # 2. If exists, FREE it first
    if existing_cell:
        grid.cells.erase(target_pos)
        if existing_cell.get_parent():
            existing_cell.get_parent().remove_child(existing_cell)
        existing_cell.queue_free()

    # 3. THEN assign new cell
    source_cell.grid_position = target_pos
    grid.cells[target_pos] = source_cell
```

**Why:** Prevents memory leaks, ensures clean scene tree

---

### Pattern 4: Floating Point Comparisons

```gdscript
const EPSILON = 0.0001

# NEVER use ==
if point.x == 5.0:  # ❌ WRONG

# ALWAYS use epsilon
if abs(point.x - 5.0) < EPSILON:  # ✅ CORRECT

# For Vector2
func vectors_equal(a: Vector2, b: Vector2) -> bool:
    return a.distance_to(b) < EPSILON
```

**Why:** Floating point arithmetic is imprecise, epsilon handles rounding errors

---

## Performance Considerations

### Target Metrics

| Operation | Target | Current | Status |
|-----------|--------|---------|--------|
| Fold (10x10 grid) | < 100ms | ~20ms | ✅ Exceeds |
| Animation FPS | 60 | 60 | ✅ Met |
| Memory usage | < 50MB | ~30MB | ✅ Good |
| Test execution | < 30s | ~8s | ✅ Excellent |

### Optimization Strategy

1. **Measure first:** Use Godot profiler, don't guess
2. **Optimize hot paths:** Focus on operations that happen frequently
3. **Trade memory for speed judiciously:** Pre-compute if access is frequent
4. **Avoid premature optimization:** Simple code first, optimize if needed

### Future Optimizations (if needed)

- **Spatial partitioning (quadtree):** For large grids (20x20+)
- **Object pooling:** Reuse split cell objects instead of creating new ones
- **Pre-calculated centroids:** Store in cell, update on geometry change
- **Batch visual updates:** Update all cell visuals in single pass
- **MultiMesh rendering:** For many cells with same visual

---

## Design Questions Resolved

### ✅ Should fold animations be interruptible?
**Decision:** No, animations play to completion
**Rationale:** Simpler state management, short animations (0.5s)

### ✅ What happens if player tries to move during fold?
**Decision:** Block player input during fold animation
**Rationale:** Prevents invalid states, animations are short

### ✅ Should cells remember original position for undo?
**Decision:** Yes, store in FoldOperation
**Rationale:** Required for accurate undo

### ✅ How should diagonal movement work for player?
**Decision:** Grid-based only (4 directions: up, down, left, right)
**Rationale:** Simpler, matches puzzle grid structure

### ✅ Should we show fold count/undo count in UI?
**Decision:** Yes, in HUD with par comparison
**Rationale:** Gives players feedback on performance

### ✅ Level win condition?
**Decision:** Just reach goal cell
**Rationale:** Simple, can add collectibles later if desired

### ✅ Should folds that remove goal cell be prevented?
**Decision:** Not enforced (level design should avoid this)
**Rationale:** Allows creative level designs, designer responsibility

### ✅ Should level files be JSON or .tres format?
**Decision:** JSON for portability
**Rationale:** Human-readable, version control friendly, web-compatible

---

## Future Architecture Considerations

### Phase 9: Level System
- JSON level format for portability
- Level validation before loading
- Campaign progression in user:// directory

### Phase 10: Audio System
- Separate audio buses (Music, SFX)
- Pooled audio players for SFX
- Fade in/out for music transitions

### Mobile/Web Port (Future)
- Touch input layer
- Responsive UI scaling
- Platform-specific optimizations

---

## References

**Algorithms:**
- Sutherland-Hodgman: [Wikipedia](https://en.wikipedia.org/wiki/Sutherland%E2%80%93Hodgman_algorithm)

**Godot Documentation:**
- [Scene Tree](https://docs.godotengine.org/en/stable/getting_started/step_by_step/scene_tree.html)
- [Coordinate Systems](https://docs.godotengine.org/en/stable/tutorials/2d/2d_transforms.html)

**Testing:**
- [GUT Documentation](https://gut.readthedocs.io/)

---

**This document is stable** - only update when major architectural decisions are made or revised.
