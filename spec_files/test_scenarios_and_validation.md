# Space-Folding Puzzle: Test Scenarios & Edge Cases

## Test Scenario Categories

### 1. Basic Grid Operations

#### Test 1.1: Grid Initialization
```gdscript
func test_grid_initialization():
    var grid = GridManager.new(Vector2i(10, 10))
    assert_eq(grid.cells.size(), 100, "Should create 100 cells")
    assert_eq(grid.cells[Vector2i(0, 0)].grid_position, Vector2i(0, 0))
    assert_eq(grid.cells[Vector2i(9, 9)].grid_position, Vector2i(9, 9))
```

#### Test 1.2: Cell Selection
```gdscript
func test_cell_selection():
    var grid = GridManager.new(Vector2i(5, 5))
    
    # Select first anchor
    grid.select_cell(Vector2i(1, 1))
    assert_eq(grid.selected_anchors.size(), 1)
    assert_eq(grid.selected_anchors[0], Vector2i(1, 1))
    
    # Select second anchor
    grid.select_cell(Vector2i(3, 1))
    assert_eq(grid.selected_anchors.size(), 2)
    
    # Select third should reset
    grid.select_cell(Vector2i(2, 2))
    assert_eq(grid.selected_anchors.size(), 1)
    assert_eq(grid.selected_anchors[0], Vector2i(2, 2))
```

### 2. Simple Axis-Aligned Folds

#### Test 2.1: Horizontal Fold
```
Initial Grid (5x5):        After Fold (anchors at (1,2) and (3,2)):
  0 1 2 3 4                  0 1 3 4
0 . . . . .                0 . . . .
1 . . . . .                1 . . . .
2 . A . B .   ------>      2 . X . .
3 . . . . .                3 . . . .
4 . . . . .                4 . . . .

Where X is the merged anchor point
```

```gdscript
func test_horizontal_fold():
    var grid = GridManager.new(Vector2i(5, 5))
    grid.select_cell(Vector2i(1, 2))
    grid.select_cell(Vector2i(3, 2))
    grid.execute_fold()
    
    # Column 2 should be removed
    assert_eq(grid.cells.has(Vector2i(2, 0)), false)
    assert_eq(grid.cells.has(Vector2i(2, 1)), false)
    assert_eq(grid.cells.has(Vector2i(2, 2)), false)
    
    # Columns should be adjacent now
    var cell_3_2 = grid.cells[Vector2i(3, 2)]
    var cell_1_2 = grid.cells[Vector2i(1, 2)]
    assert_lt(cell_3_2.position.distance_to(cell_1_2.position), CELL_SIZE * 1.1)
```

#### Test 2.2: Vertical Fold
```gdscript
func test_vertical_fold():
    var grid = GridManager.new(Vector2i(5, 5))
    grid.select_cell(Vector2i(2, 1))
    grid.select_cell(Vector2i(2, 3))
    grid.execute_fold()
    
    # Row 2 should be removed
    assert_eq(grid.cells.has(Vector2i(0, 2)), false)
    assert_eq(grid.cells.has(Vector2i(1, 2)), false)
    assert_eq(grid.cells.has(Vector2i(2, 2)), false)
```

### 3. Diagonal Fold Geometry

#### Test 3.1: 45-Degree Diagonal Fold
```
Before:                    After:
  0   1   2   3              0   1   2 3
0 [A] [ ] [ ] [ ]          0 [▲] [▄] [■]
1 [ ] [ ] [ ] [ ]          1 [▄] [■] [ ]
2 [ ] [ ] [ ] [ ]          2 [■] [ ] [ ]
3 [ ] [ ] [ ] [B]          3 [ ] [ ] [ ]

Where:
- ▲ = Merged anchor point
- ▄ = Partially cut cells (bottom half)
- ■ = Fully kept cells
```

```gdscript
func test_45_degree_fold():
    var grid = GridManager.new(Vector2i(4, 4))
    grid.select_cell(Vector2i(0, 0))
    grid.select_cell(Vector2i(3, 3))
    grid.execute_fold()
    
    # Check that cells along the diagonal are split
    var cell_1_0 = grid.cells[Vector2i(1, 0)]
    assert_eq(cell_1_0.is_partial, true)
    assert_eq(cell_1_0.geometry.size(), 3)  # Triangle
    
    # Check cells in removed region don't exist
    assert_eq(grid.cells.has(Vector2i(0, 2)), false)
    assert_eq(grid.cells.has(Vector2i(1, 3)), false)
```

#### Test 3.2: Arbitrary Angle Fold
```gdscript
func test_arbitrary_angle():
    var grid = GridManager.new(Vector2i(10, 10))
    grid.select_cell(Vector2i(2, 3))  # Not aligned
    grid.select_cell(Vector2i(7, 5))  # Arbitrary angle
    grid.execute_fold()
    
    # Verify geometry is preserved
    var total_area_before = grid.calculate_total_area()
    var total_area_after = 0.0
    for cell in grid.cells.values():
        total_area_after += GeometryCore.polygon_area(cell.geometry)
    
    # Area should be less (removed cells) but consistent
    assert_lt(total_area_after, total_area_before)
    
    # Check for seam creation
    var seam_count = 0
    for cell in grid.cells.values():
        if cell.seams.size() > 0:
            seam_count += 1
    assert_gt(seam_count, 0, "Should have created seams")
```

### 4. Critical Edge Cases

#### Test 4.1: Cut Through Vertex
```
Cut line passes exactly through grid intersection:
  
  0   1   2
0 [A]---+---[ ]
  |  ╱  |   |
1 +-╱---+---+
  |╱    |   |
2 +-----+-[B]
```

```gdscript
func test_cut_through_vertex():
    var grid = GridManager.new(Vector2i(3, 3))
    
    # Position anchors so cut line passes through vertex
    grid.cells[Vector2i(0, 0)].world_position = Vector2(0, 0)
    grid.cells[Vector2i(2, 2)].world_position = Vector2(128, 128)  # Exactly diagonal
    
    grid.select_cell(Vector2i(0, 0))
    grid.select_cell(Vector2i(2, 2))
    grid.execute_fold()
    
    # Cell at (1,1) should handle vertex intersection correctly
    var cell_1_1 = grid.cells.get(Vector2i(1, 1))
    if cell_1_1 != null:
        assert_eq(GeometryCore.validate_polygon(cell_1_1.geometry), true)
```

#### Test 4.2: Near-Parallel Cut Lines
```gdscript
func test_near_parallel_cuts():
    var grid = GridManager.new(Vector2i(10, 10))
    
    # Anchors very close in Y, far in X (nearly horizontal fold)
    grid.select_cell(Vector2i(1, 5))
    grid.select_cell(Vector2i(9, 5))  # Same row
    
    # This should either be rejected or handled as horizontal
    var can_fold = grid.validate_fold()
    if can_fold:
        grid.execute_fold()
        # Verify it was treated as horizontal fold
        for y in range(10):
            assert_eq(grid.cells.has(Vector2i(5, y)), false)
    else:
        assert_eq(can_fold, false, "Should reject near-parallel fold")
```

#### Test 4.3: Minimum Distance Validation
```gdscript
func test_minimum_fold_distance():
    var grid = GridManager.new(Vector2i(10, 10))
    
    # Anchors too close
    grid.select_cell(Vector2i(5, 5))
    grid.select_cell(Vector2i(5, 5))  # Same cell!
    
    assert_eq(grid.validate_fold(), false)
    
    # Adjacent cells - might be too close depending on threshold
    grid.select_cell(Vector2i(5, 5))
    grid.select_cell(Vector2i(5, 6))
    
    if MINIMUM_FOLD_DISTANCE > CELL_SIZE:
        assert_eq(grid.validate_fold(), false)
```

### 5. Multiple Seams Interaction

#### Test 5.1: Perpendicular Seams
```
First fold: horizontal       Second fold: vertical
    A---B                         C
    -----                         |
                                  |
                                  D
                                  
Result: One cell with crossing seams
```

```gdscript
func test_perpendicular_seams():
    var grid = GridManager.new(Vector2i(5, 5))
    
    # First fold - horizontal
    grid.select_cell(Vector2i(1, 2))
    grid.select_cell(Vector2i(3, 2))
    grid.execute_fold()
    
    # Second fold - vertical through the seam
    grid.select_cell(Vector2i(2, 1))
    grid.select_cell(Vector2i(2, 3))
    grid.execute_fold()
    
    # Find cell with both seams
    var multi_seam_cell = null
    for cell in grid.cells.values():
        if cell.seams.size() >= 2:
            multi_seam_cell = cell
            break
    
    assert_not_null(multi_seam_cell)
    assert_eq(multi_seam_cell.seams.size(), 2)
    
    # Verify seams are perpendicular
    var seam1_angle = multi_seam_cell.seams[0].angle
    var seam2_angle = multi_seam_cell.seams[1].angle
    var angle_diff = abs(seam1_angle - seam2_angle)
    assert_almost_eq(angle_diff, PI/2, 0.01)
```

#### Test 5.2: Triple Seam Intersection
```gdscript
func test_triple_seam():
    var grid = GridManager.new(Vector2i(7, 7))
    
    # Create three folds that intersect in one cell
    # Fold 1: Horizontal
    grid.execute_fold_between(Vector2i(2, 3), Vector2i(4, 3))
    
    # Fold 2: Vertical
    grid.execute_fold_between(Vector2i(3, 2), Vector2i(3, 4))
    
    # Fold 3: Diagonal
    grid.execute_fold_between(Vector2i(2, 2), Vector2i(4, 4))
    
    # Find the cell with three seams
    var max_seams = 0
    for cell in grid.cells.values():
        max_seams = max(max_seams, cell.seams.size())
    
    assert_gte(max_seams, 3, "At least one cell should have 3 seams")
```

### 6. Undo System Tests

#### Test 6.1: Simple Undo
```gdscript
func test_simple_undo():
    var grid = GridManager.new(Vector2i(5, 5))
    
    var initial_state = grid.save_state()
    
    grid.execute_fold_between(Vector2i(1, 2), Vector2i(3, 2))
    assert_ne(grid.cells.size(), 25)  # Some cells removed
    
    grid.undo_last_fold()
    assert_eq(grid.cells.size(), 25)  # All cells restored
    
    # Verify state matches initial
    assert_eq(grid.save_state(), initial_state)
```

#### Test 6.2: Blocked Undo Due to Dependencies
```gdscript
func test_undo_dependencies():
    var grid = GridManager.new(Vector2i(5, 5))
    
    # First fold
    grid.execute_fold_between(Vector2i(1, 2), Vector2i(3, 2))
    var fold1_id = grid.get_last_fold_id()
    
    # Second fold that intersects first
    grid.execute_fold_between(Vector2i(2, 1), Vector2i(2, 3))
    
    # Try to undo first fold
    assert_eq(grid.can_undo_fold(fold1_id), false)
    
    # Should be able to undo second fold
    assert_eq(grid.can_undo_last_fold(), true)
    
    # After undoing second, should be able to undo first
    grid.undo_last_fold()
    assert_eq(grid.can_undo_fold(fold1_id), true)
```

### 7. Player Interaction Tests

#### Test 7.1: Player in Removed Region
```gdscript
func test_player_in_removed_region():
    var grid = GridManager.new(Vector2i(5, 5))
    var player = Player.new()
    
    # Place player in region that will be removed
    player.grid_position = Vector2i(2, 2)
    grid.add_child(player)
    
    # Fold that removes player's position
    grid.execute_fold_between(Vector2i(1, 2), Vector2i(3, 2))
    
    # Player should be at anchor
    assert_true(
        player.grid_position == Vector2i(1, 2) or 
        player.grid_position == Vector2i(3, 2)
    )
```

#### Test 7.2: Player on Split Cell
```gdscript
func test_player_on_split_cell():
    var grid = GridManager.new(Vector2i(5, 5))
    var player = Player.new()
    
    # Place player on edge cell
    player.grid_position = Vector2i(1, 1)
    player.local_position = Vector2(32, 32)  # Center of cell
    
    # Diagonal fold that splits player's cell
    grid.execute_fold_between(Vector2i(0, 0), Vector2i(2, 2))
    
    # Player should still be in a valid position
    var player_cell = grid.get_cell_at(player.grid_position)
    assert_not_null(player_cell)
    assert_true(GeometryCore.point_in_polygon(
        player.local_position,
        player_cell.geometry
    ))
```

### 8. Visual Consistency Tests

#### Test 8.1: Seam Visual Accuracy
```gdscript
func test_seam_visual_accuracy():
    var grid = GridManager.new(Vector2i(5, 5))
    
    grid.execute_fold_between(Vector2i(1, 1), Vector2i(3, 3))
    
    for cell in grid.cells.values():
        if cell.seams.size() > 0:
            var seam = cell.seams[0]
            var visual_seam = cell.get_seam_visual()
            
            # Visual should match geometry
            assert_eq(visual_seam.points.size(), seam.intersection_points.size())
            
            for i in range(seam.intersection_points.size()):
                assert_almost_eq_v2(
                    visual_seam.points[i],
                    seam.intersection_points[i],
                    1.0  # Within 1 pixel
                )
```

#### Test 8.2: Cell Type Blending
```gdscript
func test_cell_type_blending():
    var grid = GridManager.new(Vector2i(5, 5))
    
    # Set different cell types
    grid.cells[Vector2i(1, 2)].cell_type = CellType.GRASS
    grid.cells[Vector2i(2, 2)].cell_type = CellType.WATER
    grid.cells[Vector2i(3, 2)].cell_type = CellType.STONE
    
    # Fold merges different types
    grid.execute_fold_between(Vector2i(1, 2), Vector2i(3, 2))
    
    # Find merged cell
    var merged_cell = grid.cells[Vector2i(1, 2)]
    
    # Should have blend information
    assert_true(merged_cell.has_multiple_types())
    assert_eq(merged_cell.get_blend_texture(), "grass_stone_blend")
```

### 9. Performance Tests

#### Test 9.1: Large Grid Fold Performance
```gdscript
func test_large_grid_performance():
    var grid = GridManager.new(Vector2i(50, 50))  # 2500 cells
    
    var start_time = Time.get_ticks_msec()
    grid.execute_fold_between(Vector2i(10, 10), Vector2i(40, 40))
    var elapsed = Time.get_ticks_msec() - start_time
    
    assert_lt(elapsed, 100, "Fold should complete in < 100ms")
```

#### Test 9.2: Multiple Fold Stress Test
```gdscript
func test_multiple_folds_stress():
    var grid = GridManager.new(Vector2i(20, 20))
    
    # Execute 10 random folds
    for i in range(10):
        var anchor1 = Vector2i(randi() % 20, randi() % 20)
        var anchor2 = Vector2i(randi() % 20, randi() % 20)
        
        if anchor1 != anchor2:
            grid.execute_fold_between(anchor1, anchor2)
    
    # Verify grid is still valid
    for cell in grid.cells.values():
        assert_true(GeometryCore.validate_polygon(cell.geometry))
        assert_gte(cell.geometry.size(), 3)  # At least triangle
```

### 10. Save/Load Tests

#### Test 10.1: State Serialization
```gdscript
func test_save_load_state():
    var grid = GridManager.new(Vector2i(5, 5))
    
    # Perform some operations
    grid.execute_fold_between(Vector2i(1, 1), Vector2i(3, 3))
    grid.execute_fold_between(Vector2i(0, 2), Vector2i(4, 2))
    
    # Save state
    var state = grid.serialize_state()
    
    # Create new grid and load state
    var grid2 = GridManager.new(Vector2i(5, 5))
    grid2.load_state(state)
    
    # Verify states match
    assert_eq(grid2.cells.size(), grid.cells.size())
    assert_eq(grid2.fold_history.size(), grid.fold_history.size())
    
    for pos in grid.cells:
        assert_true(grid2.cells.has(pos))
        assert_eq(
            grid2.cells[pos].geometry,
            grid.cells[pos].geometry
        )
```

## Test Execution Order

1. **Unit Tests First**: Run geometric utilities tests
2. **Component Tests**: Test individual systems (Grid, Fold, Undo)
3. **Integration Tests**: Test system interactions
4. **Edge Case Tests**: Run all edge case scenarios
5. **Performance Tests**: Run last (may be slow)
6. **Visual Tests**: Manual verification or screenshot comparison

## Success Criteria

- All geometric operations maintain polygon validity
- No cells have self-intersecting geometry
- Total grid area is conserved (minus removed cells)
- Undo operations fully restore previous state
- Player is never in an invalid position
- Performance targets are met
- Visual representations match underlying geometry
