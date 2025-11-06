# Test Campaign - Level Documentation

This document describes all levels in the test campaign, their purpose, and what edge cases they test.

## Overview

**Total Levels**: 19 (3 original + 16 new test levels)
**Purpose**: Comprehensive testing of game mechanics and edge case discovery

## Level Catalog

### Tutorial/Original Levels

#### 01 - First Steps
- **ID**: `01_introduction`
- **Grid**: 8x8
- **Difficulty**: 1 ⭐
- **Par**: 3 folds
- **Description**: Learn the basics of space folding. Reach the goal using a simple horizontal fold.
- **Test Purpose**: Basic tutorial level, tests simple horizontal folding
- **Key Features**:
  - Empty grid with single goal
  - Corner-to-corner traversal

#### 02 - Vertical Challenge
- **ID**: `02_basic_folding`
- **Grid**: 10x10
- **Difficulty**: 1 ⭐
- **Par**: 4 folds
- **Description**: Practice vertical folds to navigate around obstacles and reach the goal.
- **Test Purpose**: Vertical folding with wall obstacles
- **Key Features**:
  - Vertical wall with gap
  - Tests wall avoidance
  - Tests finding the gap in obstacles

#### 03 - Diagonal Thinking
- **ID**: `03_diagonal_challenge`
- **Grid**: 12x12
- **Difficulty**: 2 ⭐⭐
- **Par**: 5 folds
- **Max Folds**: 10
- **Description**: Master diagonal folds to solve more complex puzzles. This level requires geometric folding (Phase 4).
- **Test Purpose**: Diagonal/geometric folding (Phase 4 feature)
- **Key Features**:
  - 2x2 wall obstacle in center
  - Requires Phase 4 implementation

---

### Edge Case Test Levels

#### 04 - Corner Pocket
- **ID**: `04_corner_fold`
- **Grid**: 6x6
- **Difficulty**: 1 ⭐
- **Par**: 2 folds
- **Description**: Test folding from corners. Player starts in corner, goal in opposite corner.
- **Test Purpose**: Corner-to-corner folding behavior
- **Edge Cases Tested**:
  - ✓ Folding from grid corners
  - ✓ Minimal distance corner-to-corner
  - ✓ Empty grid traversal

#### 05 - Edge of Space
- **ID**: `05_boundary_test`
- **Grid**: 10x10
- **Difficulty**: 2 ⭐⭐
- **Par**: 2 folds
- **Description**: Tests boundary clipping - walls along all edges with a path through the middle.
- **Test Purpose**: Fold clipping at grid boundaries
- **Edge Cases Tested**:
  - ✓ Full perimeter walls
  - ✓ Fold lines clipping at boundaries
  - ✓ Center start position

#### 06 - Breaking Barriers
- **ID**: `06_wall_split`
- **Grid**: 8x8
- **Difficulty**: 2 ⭐⭐
- **Par**: 2 folds
- **Description**: Test wall splitting mechanics. Fold lines should properly split wall cells.
- **Test Purpose**: Cell splitting when fold lines intersect walls
- **Edge Cases Tested**:
  - ✓ Vertical wall splitting
  - ✓ Multiple parallel walls
  - ✓ Proper polygon subdivision

#### 07 - All Goals
- **ID**: `07_multi_goal`
- **Grid**: 9x9
- **Difficulty**: 1 ⭐
- **Par**: 1 fold
- **Description**: Multiple goals scattered around. Tests goal detection and win condition logic.
- **Test Purpose**: Win condition with multiple goals
- **Edge Cases Tested**:
  - ✓ Multiple goal cells
  - ✓ Win on ANY goal reached (not all)
  - ✓ 8 goals in symmetric pattern
  - ✓ Center starting position

#### 08 - Narrow Passage
- **ID**: `08_tight_spaces`
- **Grid**: 11x7
- **Difficulty**: 2 ⭐⭐
- **Par**: 5 folds
- **Description**: Navigate through tight corridors. Tests single-cell width pathways.
- **Test Purpose**: Single-cell-wide corridors
- **Edge Cases Tested**:
  - ✓ 1-cell-wide pathways
  - ✓ Zigzag wall pattern
  - ✓ Alternating gaps
  - ✓ Collision detection in tight spaces

#### 09 - Blocked Path
- **ID**: `09_player_blocking`
- **Grid**: 7x7
- **Difficulty**: 2 ⭐⭐
- **Par**: 3 folds
- **Description**: Tests player fold blocking rules. Player position should prevent certain folds.
- **Test Purpose**: Player position blocking fold validation
- **Edge Cases Tested**:
  - ✓ Folds blocked by player position
  - ✓ Player in removed region
  - ✓ Player on split cell
  - ✓ Multiple goals to test different paths

#### 10 - Labyrinth
- **ID**: `10_maze`
- **Grid**: 12x12
- **Difficulty**: 3 ⭐⭐⭐
- **Par**: 8 folds
- **Description**: Complex maze requiring careful navigation and strategic folding.
- **Test Purpose**: Complex pathfinding and multiple fold sequences
- **Edge Cases Tested**:
  - ✓ Complex wall patterns
  - ✓ Multiple turns required
  - ✓ Long path navigation
  - ✓ Strategic fold planning

#### 11 - Limited Moves
- **ID**: `11_fold_limit`
- **Grid**: 10x6
- **Difficulty**: 3 ⭐⭐⭐
- **Par**: 2 folds
- **Max Folds**: 2
- **Description**: Strict fold limit - you can only make 2 folds. Plan carefully!
- **Test Purpose**: Max_folds constraint enforcement
- **Edge Cases Tested**:
  - ✓ Fold counter tracking
  - ✓ Blocking folds when limit reached
  - ✓ UI display of remaining folds
  - ✓ Puzzle solvable within limit

#### 12 - Big World
- **ID**: `12_stress_test`
- **Grid**: 16x16
- **Difficulty**: 2 ⭐⭐
- **Par**: 3 folds
- **Description**: Large 16x16 grid to test performance with bigger levels.
- **Test Purpose**: Performance on larger grid sizes
- **Edge Cases Tested**:
  - ✓ 256 total cells
  - ✓ Rendering performance
  - ✓ Fold calculation time
  - ✓ Memory usage
  - ✓ Large distance traversal

#### 13 - Tiny World
- **ID**: `13_minimal`
- **Grid**: 3x3
- **Difficulty**: 1 ⭐
- **Par**: 2 folds
- **Description**: Minimal 3x3 grid. Tests edge cases with very small grids.
- **Test Purpose**: Behavior on minimal grid size
- **Edge Cases Tested**:
  - ✓ Smallest practical grid
  - ✓ Limited fold options
  - ✓ UI scaling on small grids
  - ✓ Center obstacle

#### 14 - Crossing Waters
- **ID**: `14_water_hazard`
- **Grid**: 9x9
- **Difficulty**: 2 ⭐⭐
- **Par**: 4 folds
- **Description**: Navigate around water hazards. Tests water cell type mechanics.
- **Test Purpose**: Water cell type and navigation around hazards
- **Edge Cases Tested**:
  - ✓ Water cell type (type 2)
  - ✓ Multiple 2x5 water patches
  - ✓ Navigation around hazards
  - ✓ Death/reset on water entry (if implemented)

#### 15 - Complex Pattern
- **ID**: `15_checkerboard`
- **Grid**: 8x8
- **Difficulty**: 3 ⭐⭐⭐
- **Par**: 2 folds
- **Description**: Checkerboard pattern of walls. Tests complex cell arrangements and splitting.
- **Test Purpose**: Complex patterns and multiple cell splitting
- **Edge Cases Tested**:
  - ✓ Checkerboard wall pattern
  - ✓ Many walls to potentially split
  - ✓ Complex visual patterns
  - ✓ Alternating walkable spaces

#### 16 - One Dimension
- **ID**: `16_single_row`
- **Grid**: 15x1
- **Difficulty**: 2 ⭐⭐
- **Par**: 2 folds
- **Description**: Extreme aspect ratio - 1 row, 15 columns. Tests horizontal-only folding.
- **Test Purpose**: Extreme aspect ratio (single row)
- **Edge Cases Tested**:
  - ✓ 15:1 aspect ratio
  - ✓ Horizontal-only folding
  - ✓ UI rendering on extreme dimensions
  - ✓ Camera/viewport handling

#### 17 - Vertical Line
- **ID**: `17_single_column`
- **Grid**: 1x15
- **Difficulty**: 2 ⭐⭐
- **Par**: 2 folds
- **Description**: Extreme aspect ratio - 1 column, 15 rows. Tests vertical-only folding.
- **Test Purpose**: Extreme aspect ratio (single column)
- **Edge Cases Tested**:
  - ✓ 1:15 aspect ratio
  - ✓ Vertical-only folding
  - ✓ UI rendering on extreme dimensions
  - ✓ Very tall grid handling

#### 18 - Empty Space
- **ID**: `18_no_obstacles`
- **Grid**: 10x10
- **Difficulty**: 1 ⭐
- **Par**: 2 folds
- **Description**: No walls or hazards - just empty space. Tests pure folding mechanics.
- **Test Purpose**: Pure folding without obstacles
- **Edge Cases Tested**:
  - ✓ No obstacles at all
  - ✓ Pure space folding
  - ✓ Optimal fold path
  - ✓ Minimal visual clutter

#### 19 - Impossible Path
- **ID**: `19_unreachable_without_fold`
- **Grid**: 9x9
- **Difficulty**: 2 ⭐⭐
- **Par**: 2 folds
- **Description**: Goal is completely walled off - MUST use folding to reach it.
- **Test Purpose**: Levels where folding is mandatory
- **Edge Cases Tested**:
  - ✓ Goal unreachable by walking
  - ✓ Enclosed goal area
  - ✓ Folding is mandatory (validation warning expected)
  - ✓ Testing space-folding as core mechanic

---

## Testing Matrix

### Core Mechanics Tested

| Mechanic | Levels |
|----------|--------|
| Horizontal Folding | 01, 04, 16, 18 |
| Vertical Folding | 02, 08, 17 |
| Diagonal Folding | 03 (Phase 4) |
| Wall Interaction | 02, 05, 06, 08, 10, 15 |
| Water Hazards | 14 |
| Multiple Goals | 07 |
| Fold Limits | 11 |
| Player Blocking | 09 |

### Edge Cases Tested

| Edge Case | Levels | Priority |
|-----------|--------|----------|
| Corner positions | 04 | High |
| Boundary clipping | 05 | High |
| Cell splitting | 06, 15 | High |
| Multi-goal win | 07 | Medium |
| Tight corridors | 08 | Medium |
| Player validation | 09 | High |
| Complex paths | 10 | Low |
| Fold constraints | 11 | High |
| Performance (large) | 12 | Medium |
| Performance (small) | 13 | Medium |
| Cell types | 14 | Low |
| Extreme aspect ratios | 16, 17 | Low |
| Empty grids | 18 | Medium |
| Mandatory folding | 19 | Low |

### Grid Size Coverage

| Size | Levels | Purpose |
|------|--------|---------|
| 3x3 | 13 | Minimal size |
| 6x6 | 04 | Small |
| 7x7 | 09 | Small |
| 8x8 | 01, 06, 15 | Standard small |
| 9x9 | 07, 14, 19 | Standard medium |
| 10x6 | 11 | Rectangular |
| 10x10 | 02, 05, 18 | Standard |
| 11x7 | 08 | Rectangular |
| 12x12 | 03, 10 | Large |
| 16x16 | 12 | Stress test |
| 15x1 | 16 | Extreme horizontal |
| 1x15 | 17 | Extreme vertical |

---

## How to Use This Campaign

### For Manual Testing

1. Play levels in order (01-19) for progressive difficulty
2. Try to beat par fold counts
3. Note any visual glitches or unexpected behavior
4. Test edge cases intentionally (try to break things!)

### For Automated Testing

Run the validation script:
```bash
python3 tools/validate_json.py
```

### Focus Areas by Phase

**Phase 3 (Axis-Aligned Folding)**:
- Levels: 01, 02, 04, 05, 07, 08, 09, 11, 13, 16, 17, 18, 19
- Skip: 03, 06, 10, 14, 15 (require Phase 4 or later)

**Phase 4 (Geometric Folding)**:
- All levels should work
- Focus on: 03, 06, 10, 15 (complex splitting)

**Phase 5 (Multi-Seam)**:
- Test: 06, 10, 15 (levels with many intersecting folds)

---

## Known Issues & Expected Warnings

### Level 19 - Impossible Path
- **Expected Warning**: "Goal may not be reachable from start position (without using folds)"
- **This is intentional** - the level requires folding to reach the goal

### Level 03 - Diagonal Thinking
- **Requires Phase 4** (geometric folding)
- May not work with Phase 3 implementation

### Level 14 - Crossing Waters
- Water mechanics may not be fully implemented yet
- Should work as walkable cells if water behavior not added

---

## Adding New Test Levels

To add new test levels to this campaign:

1. Create a JSON file in `levels/campaign/`
2. Follow the naming pattern: `##_descriptive_name.json`
3. Use the LevelData format (see existing files)
4. Run validation: `python3 tools/validate_json.py`
5. Document the level in this README
6. Add to appropriate testing matrix category

### Test Level Template

```json
{
	"level_id": "##_test_name",
	"level_name": "Display Name",
	"description": "What this level tests and how to play it.",
	"grid_size": {"x": 10, "y": 10},
	"cell_size": 64.0,
	"player_start_position": {"x": 0, "y": 0},
	"cell_data": {
		"(9, 9)": 3
	},
	"difficulty": 1,
	"max_folds": -1,
	"par_folds": 2,
	"metadata": {
		"author": "Test Campaign",
		"version": "1.0",
		"tags": ["test", "category"],
		"test_purpose": "Describe what edge case this tests"
	}
}
```

---

## Cell Type Reference

- **0**: Empty (walkable)
- **1**: Wall (blocked)
- **2**: Water (hazard - implementation TBD)
- **3**: Goal (win condition)

---

## Validation Results

**Last Validated**: 2025-11-06
**Total Levels**: 19
**Valid**: 19 ✓
**Invalid**: 0
**Warnings**: 0

All levels pass JSON validation and basic structure checks.

---

## Future Test Scenarios

Ideas for additional test levels:

1. **Undo System Tests** (Phase 6)
   - Level with dependency chains
   - Test undo blocking rules

2. **Save/Load Tests**
   - Mid-level save state
   - Multiple fold history

3. **Animation Tests**
   - Very fast fold sequences
   - Multiple simultaneous animations

4. **UI Tests**
   - Very long level names
   - Special characters in descriptions

5. **Performance Tests**
   - 20x20 grid with many walls
   - Rapid fold execution
   - Memory leak tests (100+ folds)

---

*This test campaign is designed to comprehensively test the Space Folding Puzzle Game and discover edge cases before release.*
