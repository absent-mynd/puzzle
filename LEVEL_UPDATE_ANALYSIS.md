# Level Updates for Overlapping/Merging Fold Behavior

## Overview of Behavior Change

### Old Behavior (Adjacent)
- Folding from anchor A to anchor B would place B adjacent to A
- Cells between A and B removed
- B becomes neighbor of A

### New Behavior (Overlapping/Merging)
- Folding from anchor A to anchor B merges them at A's position
- Cells between A and B removed
- B overlaps with A completely (same grid position)
- MIN_FOLD_DISTANCE = 0 (adjacent cells can be folded together)

## Impact Analysis by Level

### Level 01: First Steps (8x8)
- **Current**: Player (0,0), Goal (7,7), Par 3
- **Impact**: HIGH - Can now solve in 2 folds or possibly 1!
  - Fold (0,y) to (7,y) horizontally
  - Then fold (x,0) to (x,7) vertically
  - Player would overlap with goal immediately!
- **Action**: Needs redesign or accept it's now easier
- **Recommendation**: Change par to 2, or add obstacles

### Level 02: Vertical Challenge (10x10)
- **Current**: Player (0,0), Goal (9,9), Wall at x=3, Par 4
- **Impact**: MEDIUM - Wall prevents direct path
- **Action**: Test - might still be solvable, possibly easier
- **Recommendation**: Possibly reduce par to 3

### Level 03: Diagonal Thinking (12x12)
- **Current**: Phase 4 feature (diagonal folds)
- **Impact**: N/A - not yet implemented
- **Action**: No changes needed yet

### Level 04: Corner Pocket (6x6)
- **Current**: Player (0,0), Goal (5,5), Par 2
- **Impact**: CRITICAL - Now trivially easy!
  - Can fold (0,0) to (5,5) in one move
- **Action**: MUST redesign
- **Recommendation**: Add obstacles or change goal position

### Level 05: Edge of Space (10x10)
- **Current**: Perimeter walls, Player (5,5), Goal (2,2), Par 2
- **Impact**: LOW - Walls limit options
- **Action**: Test - should still work
- **Recommendation**: Keep as-is

### Level 06: Breaking Barriers (8x8)
- **Current**: Two vertical walls at x=2 and x=5, Par 2
- **Impact**: LOW - Wall splitting test
- **Action**: Keep as-is
- **Recommendation**: No changes

### Level 07: All Goals (9x9)
- **Current**: 8 goals in pattern, Player (4,4), Par 1
- **Impact**: NONE - Already optimized for 1 fold
- **Action**: Keep as-is
- **Recommendation**: Perfect for new behavior

### Level 08: Narrow Passage (11x7)
- **Current**: Zigzag walls, Par 5
- **Impact**: MEDIUM - Easier with overlapping
- **Action**: Reduce par to 3 or 4
- **Recommendation**: Test first

### Level 09: Blocked Path (7x7)
- **Current**: Player (3,3), Goals at corners, Par 3
- **Impact**: MEDIUM - Can reach goals more directly
- **Action**: Test and adjust par
- **Recommendation**: Possibly par 2

### Level 10: Labyrinth (12x12)
- **Current**: Complex maze, Par 8
- **Impact**: HIGH - Much easier with overlapping
- **Action**: Reduce par to 4-5
- **Recommendation**: Test thoroughly

### Level 11: Limited Moves (10x6)
- **Current**: Max 2 folds, Par 2
- **Impact**: CRITICAL - Might be impossible!
  - If it requires more than 2 overlapping folds
- **Action**: MUST test - might need max_folds = 3
- **Recommendation**: Test first

### Level 12: Big World (16x16)
- **Current**: Large grid, Par 3
- **Impact**: LOW - Already optimal for stress test
- **Action**: Keep as-is
- **Recommendation**: No changes

### Level 13: Tiny World (3x3)
- **Current**: Minimal grid, Par 2
- **Impact**: HIGH - Now solvable in 1 fold!
  - Fold (0,0) to (2,2)
- **Action**: Reduce par to 1, or add obstacle
- **Recommendation**: Par 1 is fine

### Level 14: Crossing Waters (9x9)
- **Current**: Water hazards, Par 4
- **Impact**: MEDIUM - Can skip water more easily
- **Action**: Reduce par to 3
- **Recommendation**: Test with water mechanics

### Level 15: Complex Pattern (8x8)
- **Current**: Checkerboard walls, Par 2
- **Impact**: LOW - Still needs strategic folding
- **Action**: Keep as-is
- **Recommendation**: No changes

### Level 16: One Dimension (15x1)
- **Current**: Single row, Par 2
- **Impact**: MEDIUM - Can reach goal in 1-2 folds
- **Action**: Keep par 2
- **Recommendation**: Already optimal

### Level 17: Vertical Line (1x15)
- **Current**: Single column, Par 2
- **Impact**: MEDIUM - Can reach goal in 1-2 folds
- **Action**: Keep par 2
- **Recommendation**: Already optimal

### Level 18: Empty Space (10x10)
- **Current**: No obstacles, Par 2
- **Impact**: HIGH - Now 2 folds is exactly right
  - One horizontal, one vertical to overlap with goal
- **Action**: Keep par 2
- **Recommendation**: Perfect!

### Level 19: Impossible Path (9x9)
- **Current**: Walled-off goal, Par 2
- **Impact**: LOW - Still requires folding strategy
- **Action**: Keep as-is
- **Recommendation**: No changes

## Summary of Required Changes

### Critical (Must Change)
1. **Level 04**: Add obstacles or redesign completely
2. **Level 11**: Test max_folds constraint

### High Priority (Likely Need Changes)
3. **Level 01**: Reduce par to 2 or add obstacles
4. **Level 10**: Reduce par to 4-5
5. **Level 13**: Reduce par to 1

### Medium Priority (Test and Adjust)
6. **Level 02**: Possibly reduce par to 3
7. **Level 08**: Reduce par to 3-4
8. **Level 09**: Possibly reduce par to 2
9. **Level 14**: Reduce par to 3

### Low Priority (Keep As-Is)
10. Levels 03, 05, 06, 07, 12, 15, 16, 17, 18, 19

## Implementation Plan

1. Update par values for easy fixes (01, 02, 08, 09, 10, 13, 14)
2. Redesign Level 04 with obstacles
3. Test Level 11 to verify max_folds works
4. Validate all changes
5. Update TEST_CAMPAIGN_README.md with new analysis
