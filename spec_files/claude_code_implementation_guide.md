# Space-Folding Puzzle Implementation Guide for Claude Code

## Project Setup Instructions

```
Create a new Godot 4 project called "SpaceFoldingPuzzle". 
Set up the following folder structure:
- scenes/
  - main.tscn
  - grid/
  - player/
  - ui/
- scripts/
  - core/
  - systems/
  - utils/
  - tests/
- assets/
  - sprites/
  - shaders/
```

---

## Stage 1: Basic Grid Foundation
**Estimated Time: 2-3 hours**

### Task 1.1: Create Grid System

Create a GridManager class that:
1. Generates a 10x10 grid of cells
2. Each cell should be a ColorRect node (64x64 pixels)
3. Cells should be clickable and highlight on hover
4. Implement a Cell class with properties:
   - `grid_position: Vector2i`
   - `world_position: Vector2`
   - `cell_type: int` (0=empty, 1=wall, 2=goal)
   - `visual_node: ColorRect`

### Task 1.2: Anchor Selection System

Implement anchor selection:
1. Left-click a cell to mark it as an anchor (show with a red outline)
2. Clicking a second cell marks it as the second anchor (blue outline)
3. Clicking a third cell should clear previous anchors and start new selection
4. Store selected anchors in GridManager as `selected_anchors: Array[Vector2i]`

### Test Requirements for Stage 1:
```gdscript
# Create test_grid_basics.gd
- Test grid generates correct number of cells
- Test cell selection toggles properly
- Test that exactly 2 anchors can be selected
- Test anchor visual feedback appears correctly
```

---

## Stage 2: Simple Axis-Aligned Folding
**Estimated Time: 3-4 hours**

### Task 2.1: Implement Horizontal/Vertical Folding

For now, only support folds where anchors share the same row or column:
1. When two anchors are selected in the same row:
   - Remove all cells between them
   - Shift all cells to the right of anchor2 to be adjacent to anchor1
2. Same logic for vertical (column) folding
3. Create a `FoldOperation` class to track each fold

### Task 2.2: Visual Feedback

Add visual feedback for folding:
1. Before fold: Draw a preview line between anchors
2. During fold: Animate the grid sections moving together (0.5 second duration)
3. After fold: Show a "seam" line where the fold occurred

### Test Requirements for Stage 2:
```gdscript
# Create test_simple_folding.gd
- Test horizontal fold removes correct cells
- Test vertical fold removes correct cells
- Test cells maintain relative positions after fold
- Test fold operation can be stored and retrieved
```

---

## Stage 3: Arbitrary Angle Folding
**Estimated Time: 6-8 hours**
**⚠️ This is the most complex stage - proceed carefully**

### Task 3.1: Geometric Cell Representation

Refactor cells to support polygon geometry:
1. Add `geometry: PackedVector2Array` to Cell class
2. Initially, set geometry to square (4 vertices)
3. Add `is_partial: bool` flag for split cells
4. Create visualization using Polygon2D instead of ColorRect

### Task 3.2: Fold Line Calculation

Implement perpendicular cut lines:
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

### Task 3.3: Polygon Splitting Algorithm

Implement Sutherland-Hodgman style polygon clipping:
1. For each cell, determine if it's: fully kept, fully removed, or split
2. If split, calculate the intersection points with the cut line
3. Generate two new polygons from the split
4. **Critical**: Handle edge cases where cut line passes through vertices

### Task 3.4: Cell Merging After Fold

After removing the middle section:
1. Find corresponding half-cells on each side of the fold
2. Merge their geometries (may not be simple rectangles anymore)
3. Store seam information: angle, intersection points

### Test Requirements for Stage 3:
```gdscript
# Create test_geometric_folding.gd
- Test polygon splitting with various angles
- Test corner intersection cases (line through vertex)
- Test cell merging preserves total area
- Test seam data is correctly stored
- Test 45-degree fold
- Test near-horizontal fold (89 degrees)
```

### Critical Edge Cases to Test:
1. Fold line passes exactly through cell corner
2. Fold line is nearly parallel to grid axis
3. Very short fold distance (anchors close together)
4. Fold line extends beyond grid boundaries

---

## Stage 4: Multi-Seam Handling
**Estimated Time: 4-5 hours**

### Task 4.1: Multiple Seams Per Cell

Enhance Cell class to handle multiple seams:
```gdscript
class Cell:
    var seams: Array[Seam] = []
    
class Seam:
    var fold_id: int
    var angle: float
    var intersection_points: PackedVector2Array
    var timestamp: int
    var cell_type_a: int  # Type on one side
    var cell_type_b: int  # Type on other side
```

### Task 4.2: Seam Intersection Logic

When a new fold intersects existing seams:
1. Subdivide the cell into regions
2. Track which region belongs to which original cell type
3. Maintain seam hierarchy (newest on top)

### Task 4.3: Visual Representation

Create a seam rendering system:
1. Draw seam lines with Line2D nodes
2. Different visual styles for different cell type combinations
3. Layer seams correctly (newest on top)

### Test Requirements for Stage 4:
```gdscript
# Create test_multi_seam.gd
- Test two perpendicular folds through same cell
- Test three folds creating a triangle in one cell
- Test seam visual ordering is correct
- Test cell type preservation across multiple splits
```

---

## Stage 5: Undo System
**Estimated Time: 4-5 hours**

### Task 5.1: Fold History Management

Create an UndoManager:
```gdscript
class UndoManager:
    var fold_history: Array[FoldOperation] = []
    var cell_fold_map: Dictionary = {}  # cell_id -> Array[fold_id]
    
    func record_fold(operation: FoldOperation):
        # Store the fold and update affected cells
    
    func can_undo_fold(fold_id: int) -> bool:
        # Check if any dependent folds exist
    
    func undo_fold(fold_id: int):
        # Restore grid state before this fold
```

### Task 5.2: Dependency Checking

Implement undo validation:
1. A fold can only be undone if it's the newest fold affecting ALL its cells
2. Click on a merged anchor point to attempt undo
3. Show visual feedback: green if can undo, red if blocked

### Task 5.3: State Restoration

When undoing:
1. Restore split cells to their original form
2. Restore removed cells
3. Update positions of shifted cells
4. Remove seam visuals

### Test Requirements for Stage 5:
```gdscript
# Create test_undo_system.gd
- Test simple undo of last fold
- Test blocked undo due to dependencies
- Test state fully restored after undo
- Test undo of oldest fold after newer non-overlapping fold
- Test visual feedback for undo availability
```

---

## Stage 6: Player Character
**Estimated Time: 3-4 hours**

### Task 6.1: Basic Player Movement

Add a player character:
1. Create a CharacterBody2D that moves on the grid
2. Grid-based movement (move one cell at a time)
3. Cannot move through walls
4. Simple sprite or colored square

### Task 6.2: Fold Interaction

Handle player during folds:
1. If player is in removed section: move to nearest anchor
2. If player is on a split cell: keep in the remaining portion
3. Prevent folds that would trap the player
4. Animate player movement during fold

### Test Requirements for Stage 6:
```gdscript
# Create test_player_interaction.gd
- Test player movement validation
- Test player position after fold in removed area
- Test player position after fold on split cell
- Test fold prevention when it would trap player
```

---

## Stage 7: Cell Types and Visual Polish
**Estimated Time: 3-4 hours**

### Task 7.1: Multiple Cell Types

Implement different cell types:
1. Empty (walkable)
2. Wall (blocks movement)
3. Water (special rules)
4. Goal (level completion)

### Task 7.2: Cell Type Merging Visuals

When different types merge:
1. Create border effects at seams
2. Use shaders or textures to blend
3. Maintain gameplay properties (e.g., wall still blocks)

### Task 7.3: Polish

Add polish elements:
1. Smooth animations for folding
2. Particle effects at seam creation
3. Sound effects (if desired)
4. Better visual style for cells

---

## Stage 8: Testing and Validation Suite
**Estimated Time: 2-3 hours**

### Task 8.1: Comprehensive Test Suite

Create a full test suite:
```gdscript
# test_suite.gd
- Geometric accuracy tests
- Performance tests (fold operation < 100ms)
- Edge case validation
- Visual regression tests
- Gameplay logic tests
```

### Task 8.2: Debug Visualization

Create debug tools:
1. Show cell vertices and indices
2. Visualize cut lines before folding
3. Display fold operation data
4. Show seam hierarchy

### Task 8.3: Level Validation

Create tools to validate puzzle levels:
1. Check if level is solvable
2. Verify no impossible states
3. Test minimum fold count

---

## Performance Targets

- Fold operation: < 100ms for 20x20 grid
- Animation: Smooth 60 FPS
- Memory: < 50MB for complex states
- Undo operation: < 50ms

---

## Common Pitfalls to Avoid

1. **Floating point precision**: Use epsilon comparisons for geometric operations
2. **Coordinate systems**: Be consistent with grid vs world coordinates
3. **Array modifications during iteration**: Copy arrays before modifying
4. **Seam z-ordering**: Newest seams must render on top
5. **Memory leaks**: Properly free visual nodes when cells are removed

---

## Suggested Development Order

1. Start with Stage 1-2 (basic grid and simple folding)
2. Get Stage 6 (player) working with simple folding
3. Then tackle Stage 3 (geometric folding) - this is the hardest
4. Add Stage 4 (multi-seam) only after Stage 3 is solid
5. Implement Stage 5 (undo) 
6. Polish with Stage 7
7. Validate with Stage 8

---

## Code Architecture Guidelines

```
GridManager (Node2D)
├── CellContainer (Node2D)
│   └── Cell nodes
├── SeamContainer (Node2D)  
│   └── Seam Line2D nodes
├── FoldSystem (Node)
├── UndoManager (Node)
└── Player (CharacterBody2D)
```

Keep systems modular and testable. Use signals for communication between systems.

---

## Questions to Ask During Implementation

1. "Should fold animations be interruptible?"
2. "What happens if player tries to move during a fold?"
3. "Should cells remember their original position for undo?"
4. "How should diagonal movement work for the player?"
5. "Should there be a maximum number of folds per level?"

These design decisions will affect implementation, so gather feedback early.
