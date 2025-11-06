# Space-Folding Puzzle Game - Agent Task Delegation List

**Generated:** 2025-11-06
**Current Status:** 225 tests passing, Phases 1-3 and 7 complete

---

## How to Use This Document

This document provides a comprehensive task breakdown for AI agents working on the Space-Folding Puzzle Game project. It is designed to be used in conjunction with `CLAUDE.md`, which provides essential project context.

### For AI Agents Starting a Task:

1. **First, read `CLAUDE.md`** - Get essential project context, architectural decisions, and development guidelines
2. **Then, consult this document** - Find your assigned task and understand its requirements
3. **Review dependencies** - Ensure prerequisite phases/tasks are complete
4. **Check the relevant phase issue file** - See detailed specifications (e.g., `PHASE_4_ISSUES.md`)
5. **Write tests first** - Follow TDD approach (see CLAUDE.md for testing framework details)
6. **Implement the feature** - Follow code quality standards from CLAUDE.md
7. **Verify and commit** - Run `./run_tests.sh`, ensure all tests pass, commit with clear messages

### Quick Task Selection Guide:

- **New to the project?** Start with P2-P3 tasks (Level System, GUI, Audio)
- **Experienced with geometry?** Tackle P0 Task 1 (Geometric Folding - CRITICAL)
- **UI/UX specialist?** Focus on Task 6 (Level Editor), Task 7 (Visual Polish), Task 8 (GUI System)
- **Good at testing?** Pick Task 10 (Testing Suite), Task 11 (Performance)
- **Creative/Design focused?** Task 2 (Campaign Levels), Task 12 (Advanced Features)

### Integration with CLAUDE.md:

- **CLAUDE.md** = Project context, architecture, common pitfalls, critical decisions
- **This document** = Task breakdown, priorities, time estimates, acceptance criteria
- **Always reference both documents** when starting new work

---

## Current Project State Summary

### ✅ Completed
- **Phase 1:** Project Setup & Foundation (GeometryCore utilities)
- **Phase 2:** Basic Grid System (Cell, GridManager)
- **Phase 3:** Simple Axis-Aligned Folding (horizontal/vertical folds)
- **Phase 7:** Player Character (movement, validation, goal detection)

### 🎯 Ready to Start
- **Phase 4:** Geometric Folding (diagonal folds - MOST COMPLEX)
- **Phase 5:** Multi-Seam Handling
- **Phase 6:** Undo System
- **Phase 8:** Cell Types & Core Visual Elements
- **Phase 9:** Level Management System
- **Phase 10:** Graphics, GUI & Audio Polish
- **Phase 11:** Testing & Validation

---

## Priority Task Groups

Tasks are organized by priority (P0 = highest) and complexity (⭐ = simple, ⭐⭐⭐ = complex).

---

## 🔴 P0 - Critical Path: Core Gameplay Loop

### Task 1: Implement Geometric Folding System (Phase 4)
**Priority:** P0 | **Complexity:** ⭐⭐⭐⭐⭐ (Most Complex) | **Est. Time:** 8-12 hours

**Objective:** Enable diagonal folds at arbitrary angles with cell polygon splitting.

**Sub-tasks:**
1. **Refactor Cell for Polygon Geometry** (3-4 hours)
   - Update Cell class to use arbitrary polygons (not just squares)
   - Replace ColorRect with Polygon2D for rendering
   - Add geometry transformation tracking
   - Track original geometry for undo
   - Test: Cell can store and render arbitrary polygon shapes

2. **Implement Fold Line Calculation** (2 hours)
   - Calculate perpendicular cut lines from anchor points
   - Compute fold axis vector and normal
   - Handle arbitrary angles (not just 0°, 90°)
   - Test: Fold lines calculated correctly for various angles

3. **Implement Cell Processing Algorithm** (3-4 hours)
   - Determine which region each cell is in (kept-left, removed, kept-right)
   - Use `GeometryCore.split_polygon_by_line()` for split cells
   - Calculate cell centroids for region determination
   - Handle cells that straddle fold lines
   - Test: Cells correctly classified into regions

4. **Implement Cell Merging** (2 hours)
   - Merge corresponding half-cells across fold seam
   - Store seam metadata (angle, points, timestamp)
   - Visual representation of merged cells
   - Test: Merged cells preserve total area

5. **Handle Critical Edge Cases** (2-3 hours)
   - Fold lines through cell vertices (epsilon handling)
   - Near-parallel cuts (reject or special handling)
   - Minimum fold distance validation
   - Boundary clipping (bounded grid model)
   - Player cell split validation
   - Test: All edge cases handled gracefully

**Acceptance Criteria:**
- Diagonal folds at arbitrary angles work correctly
- Cells split into polygons when intersected by fold line
- Cell merging preserves geometry and gameplay properties
- All edge cases handled (vertices, boundaries, player)
- Player validation blocks folds that would split player cell
- 50+ new tests passing for geometric folding
- No geometry validation errors

**Dependencies:** None (Phase 1-3 complete)

**Risk:** HIGH - Most complex feature, many edge cases

---

### Task 2: Create First Campaign Levels (Phase 9 Subset)
**Priority:** P0 | **Complexity:** ⭐⭐ | **Est. Time:** 3-4 hours

**Objective:** Create playable campaign levels to validate game mechanics.

**Sub-tasks:**
1. **Design Tutorial Levels** (1-2 hours)
   - Level 1: Introduction (simple horizontal fold)
   - Level 2: Basic vertical fold
   - Level 3: Combine horizontal + vertical
   - Level 4: First diagonal fold (after Phase 4)
   - Document level solutions and par fold counts

2. **Design Intermediate Levels** (1-2 hours)
   - Levels 5-10: Gradually increasing complexity
   - Introduce walls as obstacles
   - Require multi-step planning
   - Test different grid sizes (8x8, 10x10, 12x12)

3. **Create Level Data Format** (1 hour)
   - Define JSON structure for level storage
   - Include: grid size, cell types, player start, goal, par folds
   - Save levels to `levels/campaign/` directory
   - Document level format in README

**Acceptance Criteria:**
- 10 campaign levels created and playable
- Levels progress in difficulty
- Each level is solvable
- Par fold counts are reasonable
- Levels showcase different mechanics

**Dependencies:** Phase 3, 7 complete (Phase 4 for diagonal levels)

**Risk:** LOW - Design work, low technical complexity

---

## 🟠 P1 - Enhanced Gameplay Features

### Task 3: Implement Multi-Seam Handling (Phase 5)
**Priority:** P1 | **Complexity:** ⭐⭐⭐⭐ | **Est. Time:** 4-6 hours

**Objective:** Handle multiple overlapping seams in the same cell.

**Sub-tasks:**
1. **Implement Seam Data Structure** (1 hour)
   - Create Seam class with fold_id, angle, intersection points, timestamp
   - Track cell types on both sides of seam
   - Store in Cell.seams array

2. **Implement Tessellation Algorithm** (2-3 hours)
   - When new seam intersects cell, subdivide into convex regions
   - Track which sub-polygon came from which side of each seam
   - Maintain seam metadata for each sub-polygon
   - Use recursive splitting approach

3. **Implement Seam Rendering** (1-2 hours)
   - Combine shaders for cell type blending
   - Use Line2D for seam visualization
   - Layer seams by timestamp (newest on top)
   - Different colors for different cell type combinations

**Acceptance Criteria:**
- Cells can contain multiple intersecting seams
- Tessellation correctly subdivides cells
- Visual representation shows all seams clearly
- Cell type properties preserved across splits
- 30+ tests for multi-seam scenarios

**Dependencies:** Phase 4 complete (geometric folding)

**Risk:** MEDIUM - Complex geometry handling

---

### Task 4: Implement Undo System (Phase 6)
**Priority:** P1 | **Complexity:** ⭐⭐⭐ | **Est. Time:** 4-5 hours

**Objective:** Allow players to undo fold operations with dependency checking.

**Sub-tasks:**
1. **Implement UndoManager** (1-2 hours)
   - Create UndoManager class
   - Track fold history with full state snapshots
   - Maintain cell-to-fold mapping
   - Implement fold ID system

2. **Implement FoldOperation Data Structure** (1 hour)
   - Store: fold_id, anchors, affected cells, removed cells
   - Store original geometry for all modified cells
   - Store created seams
   - Include timestamp

3. **Implement Dependency Checking** (1-2 hours)
   - Algorithm: Can only undo if fold is newest affecting ALL its cells
   - Check all seams in affected cells
   - Block undo if newer fold exists
   - Provide clear error messages

4. **Implement Undo Execution** (1 hour)
   - Restore split cells to original polygons
   - Re-add removed cells
   - Reverse position shifts
   - Remove seam visuals
   - Update fold history

**Acceptance Criteria:**
- Can undo last fold successfully
- Dependency blocking works correctly
- State fully restored after undo
- Visual feedback for undo availability
- 25+ tests for undo scenarios

**Dependencies:** Phase 3, 4 complete

**Risk:** MEDIUM - Complex state management

---

## 🟡 P2 - Level System & Content Tools

### Task 5: Implement Level Management System (Phase 9)
**Priority:** P2 | **Complexity:** ⭐⭐⭐ | **Est. Time:** 5-6 hours

**Objective:** Complete level loading, saving, and progression system.

**Sub-tasks:**
1. **Implement LevelData Resource** (1 hour)
   - Create LevelData class with all level properties
   - Support JSON serialization/deserialization
   - Validation for required fields
   - Metadata support (author, tags, etc.)

2. **Implement LevelManager** (2 hours)
   - Load/save level files
   - Level listing and filtering
   - Level validation before loading
   - Error handling for corrupted files

3. **Implement Level Transition System** (1-2 hours)
   - Scene transitions between levels
   - Progress tracking (which levels completed)
   - Star rating system (based on par folds)
   - Next level unlocking

4. **Implement Campaign Progress** (1-2 hours)
   - Save/load progress to user directory
   - Track: completed levels, stars earned, best times
   - Persist across game sessions
   - Handle save file corruption gracefully

**Acceptance Criteria:**
- Levels load and save correctly
- Campaign progression tracked
- Level transitions smooth
- Progress persists across sessions
- 20+ tests for level system

**Dependencies:** Phase 3, 7 complete

**Risk:** LOW - Well-defined functionality

---

### Task 6: Implement Level Editor (Phase 9)
**Priority:** P2 | **Complexity:** ⭐⭐⭐⭐ | **Est. Time:** 6-8 hours

**Objective:** In-game level editor for creating and testing levels.

**Sub-tasks:**
1. **Create Level Editor UI** (2-3 hours)
   - Scene: `scenes/ui/LevelEditor.tscn`
   - Toolbar with cell type selection
   - Grid view with click-to-paint
   - Properties panel (grid size, name, par folds)
   - File operations (new, open, save, save as)

2. **Implement Paint Tools** (2 hours)
   - Paint mode: click to place cell types
   - Erase mode: click to clear
   - Fill mode: flood fill regions
   - Player start placement
   - Goal cell placement

3. **Implement Preview/Playtest Mode** (2-3 hours)
   - Switch between edit and play mode
   - Full gameplay in preview
   - Return to editor after testing
   - Show debug info (fold count, etc.)

4. **Implement Level Validation** (1 hour)
   - Check for player start position
   - Check for goal cell
   - Check for accessibility (goal reachable?)
   - Warn about potential issues

**Acceptance Criteria:**
- Editor can create valid levels
- Paint tools work intuitively
- Preview mode fully functional
- Levels save in correct format
- Validation catches common errors

**Dependencies:** Phase 9 (LevelManager)

**Risk:** MEDIUM - UI complexity

---

## 🟢 P3 - Polish & User Experience

### Task 7: Implement Visual Polish (Phase 8, 10)
**Priority:** P3 | **Complexity:** ⭐⭐⭐ | **Est. Time:** 6-8 hours

**Objective:** Improve graphics, animations, and overall visual appeal.

**Sub-tasks:**
1. **Enhanced Cell Visuals** (2 hours)
   - Distinct textures for each cell type
   - Animated water shader
   - Glowing goal cell effect
   - Border outlines for clarity

2. **Improved Fold Animations** (2-3 hours)
   - Particle effects along fold line
   - Camera shake on fold execution
   - Smooth easing functions
   - Staggered cell animations

3. **Player Character Polish** (1-2 hours)
   - Animated sprite (idle, walk)
   - Directional facing
   - Footstep particles
   - Shadow underneath

4. **Seam Visual Effects** (1-2 hours)
   - Glowing animated seam lines
   - Age-based coloring (newest = bright)
   - "Stitching" effect
   - Particle trails on seam creation

**Acceptance Criteria:**
- Game looks polished and professional
- Animations enhance gameplay understanding
- Visual feedback is clear and helpful
- 60 FPS maintained throughout
- No visual glitches

**Dependencies:** Phase 4, 5 complete

**Risk:** LOW - Mostly aesthetic improvements

---

### Task 8: Implement GUI System (Phase 10)
**Priority:** P3 | **Complexity:** ⭐⭐⭐ | **Est. Time:** 6-8 hours

**Objective:** Complete UI/UX with menus, HUD, and settings.

**Sub-tasks:**
1. **Main Menu** (1-2 hours)
   - Title screen with logo
   - Buttons: Play, Level Select, Editor, Settings, Quit
   - Background animation
   - Menu transitions

2. **HUD (Heads-Up Display)** (1-2 hours)
   - Fold counter with par display
   - Undo button
   - Pause button
   - Level name
   - Optional timer

3. **Pause Menu** (1 hour)
   - Resume, Restart, Settings, Main Menu
   - Dim background
   - Smooth transitions

4. **Level Complete Screen** (1-2 hours)
   - Victory message
   - Stars earned (1-3 based on performance)
   - Statistics (folds used, time, par)
   - Buttons: Next, Retry, Level Select

5. **Settings Menu** (1-2 hours)
   - Audio controls (master, music, SFX)
   - Graphics options (fullscreen, vsync)
   - Accessibility options
   - Key remapping (future)

**Acceptance Criteria:**
- All UI screens implemented
- Navigation between screens works
- Settings persist across sessions
- UI is intuitive and responsive
- Theme is consistent

**Dependencies:** None (can be done in parallel)

**Risk:** LOW - Standard UI implementation

---

### Task 9: Implement Audio System (Phase 10)
**Priority:** P3 | **Complexity:** ⭐⭐ | **Est. Time:** 4-5 hours

**Objective:** Add music and sound effects.

**Sub-tasks:**
1. **Implement AudioManager** (1-2 hours)
   - Singleton for audio management
   - Music playback with fade in/out
   - SFX playback with pitch variation
   - Volume controls (separate buses)

2. **Source or Create Audio Assets** (2-3 hours)
   - Background music tracks (menu, gameplay)
   - SFX: footsteps, fold, selection, error, victory
   - UI sounds: button hover, button click
   - Format: .ogg for compatibility

3. **Integrate Audio Triggers** (1 hour)
   - Play SFX on appropriate events
   - Music transitions between scenes
   - Respect volume settings
   - Test audio mixing levels

**Acceptance Criteria:**
- Music plays on menu and during gameplay
- SFX trigger on all appropriate events
- Volume controls work correctly
- No audio pops or clicks
- Audio enhances experience

**Dependencies:** None (can be done in parallel)

**Risk:** LOW - If using pre-made assets; MEDIUM if creating custom

---

## 🔵 P4 - Testing & Optimization

### Task 10: Comprehensive Testing Suite (Phase 11)
**Priority:** P4 | **Complexity:** ⭐⭐ | **Est. Time:** 4-5 hours

**Objective:** Ensure quality through extensive testing.

**Sub-tasks:**
1. **Integration Tests** (2 hours)
   - Full fold-undo cycles
   - Multiple sequential folds
   - Player-fold interactions
   - Level save/load cycles
   - Campaign progression flow

2. **Edge Case Validation** (1-2 hours)
   - All scenarios from `test_scenarios_and_validation.md`
   - Boundary conditions
   - Corrupted save files
   - Empty grids
   - Maximum grid sizes

3. **Performance Testing** (1 hour)
   - Measure fold operation time
   - Verify 60 FPS in animations
   - Memory usage monitoring
   - Load testing with large grids

4. **Playtesting** (1 hour)
   - Complete all campaign levels
   - Test level editor thoroughly
   - UI/UX validation
   - Collect feedback

**Acceptance Criteria:**
- 300+ total tests passing
- All edge cases covered
- Performance targets met
- No critical bugs
- Game is release-ready

**Dependencies:** All other phases complete

**Risk:** LOW - Testing and validation

---

### Task 11: Performance Optimization (Phase 11)
**Priority:** P4 | **Complexity:** ⭐⭐⭐ | **Est. Time:** 3-4 hours

**Objective:** Optimize for performance and memory efficiency.

**Sub-tasks:**
1. **Profile Performance** (1 hour)
   - Identify bottlenecks
   - Measure fold operations
   - Monitor memory usage
   - Check animation frame rates

2. **Implement Optimizations** (2-3 hours)
   - Pre-calculate cell centroids
   - Spatial partitioning (quadtree) if needed
   - Object pooling for split cells
   - Batch visual updates
   - Optimize polygon rendering

3. **Memory Management** (1 hour)
   - Ensure proper cleanup
   - Fix memory leaks
   - Optimize texture loading
   - Reduce unnecessary allocations

**Acceptance Criteria:**
- Fold operation < 100ms on 20x20 grid
- Consistent 60 FPS
- Memory usage < 50MB
- No memory leaks
- Smooth gameplay on target hardware

**Dependencies:** Most features complete

**Risk:** LOW - Optimization based on profiling

---

## 🟣 P5 - Future Enhancements & Exploration

### Task 12: Advanced Level Features
**Priority:** P5 | **Complexity:** ⭐⭐⭐ | **Est. Time:** 4-6 hours

**Objective:** Add advanced gameplay mechanics (optional).

**Ideas to explore:**
- Water cells with special rules (can only cross via fold?)
- Collectible items on grid
- Multiple players (co-op or puzzle switching)
- Movable blocks/obstacles
- Timed challenges
- Achievement system
- Daily puzzles
- Community level sharing (export/import)
- Leaderboards (time/fold count)

**Approach:**
- Pick 2-3 mechanics to prototype
- Test with players for fun factor
- Implement if adding value
- Document for future expansion

**Dependencies:** Core game complete

**Risk:** LOW - Optional features

---

### Task 13: Mobile/Web Port
**Priority:** P5 | **Complexity:** ⭐⭐⭐ | **Est. Time:** 6-8 hours

**Objective:** Port game to mobile and/or web platforms.

**Sub-tasks:**
1. **Touch Input Implementation** (2-3 hours)
   - Tap to select anchors
   - Swipe for player movement
   - Pinch to zoom (optional)
   - Touch-friendly UI scaling

2. **Responsive UI** (2-3 hours)
   - Adapt to different screen sizes
   - Portrait and landscape support
   - Safe area handling (notches, etc.)
   - Virtual button overlays if needed

3. **Platform-Specific Optimization** (2 hours)
   - Performance tuning for mobile
   - Web export configuration
   - Test on various devices
   - Handle platform permissions

**Acceptance Criteria:**
- Game runs smoothly on mobile/web
- Touch controls feel natural
- UI scales appropriately
- Performance is acceptable
- No platform-specific bugs

**Dependencies:** Core game complete

**Risk:** MEDIUM - Platform-specific issues

---

## 📋 Task Assignment Recommendations

### For General-Purpose Agent
- Task 5: Level Management System (well-defined, medium complexity)
- Task 8: GUI System (independent, clear requirements)
- Task 9: Audio System (independent, clear requirements)

### For Specialized/Careful Agent
- Task 1: Geometric Folding System (MOST CRITICAL, highest complexity)
- Task 3: Multi-Seam Handling (complex geometry)
- Task 4: Undo System (complex state management)

### For Creative/Design Agent
- Task 2: Create Campaign Levels (design-focused)
- Task 12: Advanced Level Features (exploration)

### For UI/UX Specialist Agent
- Task 6: Level Editor (UI-heavy)
- Task 7: Visual Polish (aesthetic focus)

### For QA/Testing Agent
- Task 10: Comprehensive Testing Suite
- Task 11: Performance Optimization

---

## ⚠️ Critical Dependencies & Blockers

### Dependency Chain
```
Phase 1-3, 7 (COMPLETE)
    ↓
Phase 4: Geometric Folding (CRITICAL - blocks Phase 5)
    ↓
Phase 5: Multi-Seam Handling
    ↓
Phase 6: Undo System
    ↓
Phase 11: Final Testing

Parallel tracks:
- Phase 8: Cell Types (can do anytime)
- Phase 9: Level System (can do after Phase 3)
- Phase 10: GUI & Audio (can do anytime)
```

### Critical Path
**The geometric folding system (Task 1) is on the critical path.** Everything else can be developed in parallel or after.

---

## 🎯 Recommended Next Steps

### Immediate Priority (Next 2 weeks)
1. **Task 1: Geometric Folding** (1-2 developers, 8-12 hours)
   - CRITICAL - Enables arbitrary angle folds
   - Most complex feature
   - High risk, needs careful implementation

2. **Task 2: Campaign Levels** (1 developer, 3-4 hours)
   - Validates gameplay
   - Provides content for testing
   - Low risk, high value

3. **Task 5: Level Management** (1 developer, 5-6 hours)
   - Independent of Phase 4
   - Enables level progression
   - Medium complexity

### Near-Term Priority (Weeks 3-4)
4. **Task 3: Multi-Seam Handling** (after Phase 4)
5. **Task 4: Undo System** (after Phase 4)
6. **Task 6: Level Editor** (after Level Management)

### Polish Phase (Weeks 5-6)
7. **Task 7: Visual Polish**
8. **Task 8: GUI System**
9. **Task 9: Audio System**

### Final Phase (Week 7)
10. **Task 10: Testing Suite**
11. **Task 11: Performance Optimization**

---

## 📊 Estimated Timeline

**Total Estimated Time:** 65-85 hours

**With 2-3 developers working in parallel:** 4-6 weeks to completion

**Breakdown:**
- Critical path (Phase 4-6): 16-23 hours
- Level system (Phase 9): 11-14 hours
- Polish (Phase 8, 10): 16-21 hours
- Testing (Phase 11): 7-9 hours

---

## 🔧 Development Guidelines for Agents

### Before Starting Any Task
1. Read `CLAUDE.md` for project context
2. Read `IMPLEMENTATION_PLAN.md` for phase details
3. Read relevant phase issue files (`PHASE_X_ISSUES.md`)
4. Check current test status: `./run_tests.sh`
5. Review existing code in the area you'll modify

### During Development
1. **Write tests FIRST** (TDD approach)
2. Keep commits small and focused
3. Run tests frequently: `./run_tests.sh`
4. Never use `==` for float comparisons (use epsilon)
5. Always use `queue_free()` for node cleanup
6. Comment "why" not "what"

### After Completing Task
1. Ensure all tests pass (aim for 100% coverage)
2. Update documentation if needed
3. Commit with descriptive message
4. Push to feature branch
5. Create PR with clear description

### Code Quality Standards
- ✅ All tests must pass
- ✅ No geometry validation errors
- ✅ Proper memory management
- ✅ Clear variable naming
- ✅ Appropriate comments
- ✅ No floating-point equality checks
- ✅ Handle edge cases gracefully

---

## 📝 Notes for Project Manager

### Risk Assessment
**HIGH RISK:**
- Geometric Folding (Phase 4) - Most complex feature
  - *Mitigation:* Allocate experienced developer, allow extra time, extensive testing

**MEDIUM RISK:**
- Multi-Seam Tessellation (Phase 5) - Complex geometry
  - *Mitigation:* Build on Phase 4 foundation, use visualization tools
- Undo System (Phase 6) - Complex state management
  - *Mitigation:* Clear data structures, comprehensive tests

**LOW RISK:**
- Level System, GUI, Audio, Testing - Well-defined scope

### Quality Gates
1. **After Phase 4:** Comprehensive geometric folding tests must pass
2. **After Phase 9:** Campaign levels must be playable end-to-end
3. **Before Release:** 300+ tests passing, performance targets met

### Success Metrics
- All phases implemented
- 300+ tests passing
- 10+ campaign levels
- Level editor functional
- Polished UI/UX
- Stable 60 FPS
- Positive playtester feedback

---

## Quick Reference: Task Summary Table

| Task # | Name | Priority | Complexity | Est. Time | Dependencies | Risk | Best For |
|--------|------|----------|------------|-----------|--------------|------|----------|
| 1 | Geometric Folding | P0 | ⭐⭐⭐⭐⭐ | 8-12h | None | HIGH | Geometry specialist |
| 2 | Campaign Levels | P0 | ⭐⭐ | 3-4h | Phase 3, 7 | LOW | Creative/Designer |
| 3 | Multi-Seam Handling | P1 | ⭐⭐⭐⭐ | 4-6h | Phase 4 | MEDIUM | Geometry specialist |
| 4 | Undo System | P1 | ⭐⭐⭐ | 4-5h | Phase 3, 4 | MEDIUM | Systems programmer |
| 5 | Level Management | P2 | ⭐⭐⭐ | 5-6h | Phase 3, 7 | LOW | General developer |
| 6 | Level Editor | P2 | ⭐⭐⭐⭐ | 6-8h | Task 5 | MEDIUM | UI/UX specialist |
| 7 | Visual Polish | P3 | ⭐⭐⭐ | 6-8h | Phase 4, 5 | LOW | Visual/Graphics |
| 8 | GUI System | P3 | ⭐⭐⭐ | 6-8h | None | LOW | UI/UX specialist |
| 9 | Audio System | P3 | ⭐⭐ | 4-5h | None | LOW | Audio specialist |
| 10 | Testing Suite | P4 | ⭐⭐ | 4-5h | All phases | LOW | QA/Testing |
| 11 | Performance Opt | P4 | ⭐⭐⭐ | 3-4h | Most features | LOW | Optimization specialist |
| 12 | Advanced Features | P5 | ⭐⭐⭐ | 4-6h | Core complete | LOW | Creative/Designer |
| 13 | Mobile/Web Port | P5 | ⭐⭐⭐ | 6-8h | Core complete | MEDIUM | Platform specialist |

**Legend:**
- **Priority:** P0 (Critical) → P5 (Future)
- **Complexity:** ⭐ (Simple) → ⭐⭐⭐⭐⭐ (Very Complex)
- **Est. Time:** Estimated hours for one developer
- **Risk:** Likelihood of complications or delays

---

## Communication Guidelines for AI Agents

When working on tasks from this document:

### Asking for Clarification
If requirements are unclear:
1. Check CLAUDE.md first
2. Check the phase issue file (e.g., PHASE_4_ISSUES.md)
3. Review existing tests to understand expected behavior
4. If still unclear, ask specific questions referencing the documentation

### Reporting Progress
When updating on task progress:
1. Reference task number and name
2. Report test status (X/Y tests passing)
3. List any blockers or risks encountered
4. Mention any deviations from the plan

### Requesting Code Review
When completing a task:
1. Ensure all acceptance criteria are met
2. Run full test suite and report results
3. Document any architectural decisions made
4. Highlight any areas needing special attention

### Handling Blockers
If blocked on a task:
1. Document the specific blocker
2. List what you've tried
3. Suggest alternative approaches
4. Request specific help or resources needed

---

**Document Maintainer:** Update this document as tasks are completed or priorities change.

**Last Updated:** 2025-11-06
