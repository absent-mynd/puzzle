# Phase 6: Undo System - Implementation Specification

**Status:** 📋 Ready to Start
**Priority:** P1 (Critical Path)
**Estimated Time:** 4-6 hours
**Complexity:** ⭐⭐⭐⭐ (High)
**Dependencies:** Phase 4 (Geometric Folding) ✅ Complete, Phase 5 (Multi-Seam Handling) ✅ Complete

---

## Overview

Phase 6 implements a complete undo system for fold operations. Players will be able to undo previous folds and restore the grid to earlier states.

**Core Features:**
- Undo individual fold operations
- Redo support (optional enhancement)
- Maintain game state consistency
- Strict undo ordering (only undo newest fold affecting all its cells)
- Efficient state storage

---

## Architecture

### Undo System Design

**Undo Stack Pattern:**
```gdscript
class UndoStack:
    var operations: Array[FoldOperation]  # Stack of completed folds
    var current_index: int = -1  # Index of last executed operation

    func push_operation(op: FoldOperation)
    func undo() -> bool
    func redo() -> bool
    func can_undo() -> bool
    func can_redo() -> bool
```

**FoldOperation Storage:**
```gdscript
class FoldOperation:
    var fold_id: int
    var fold_type: String  # "horizontal", "vertical", "diagonal"
    var anchor1: Vector2i
    var anchor2: Vector2i
    var affected_cells: Array[Vector2i]  # Cells modified by this fold
    var cell_snapshots: Dictionary  # Position -> Cell state before fold
    var timestamp: int
```

### Key Decisions

1. **Strict Undo Ordering:**
   - Only undo a fold if it's the newest fold affecting ALL its cells
   - Prevents complex dependency resolution
   - See Decision 8 in ARCHITECTURE.md

2. **Cell State Snapshots:**
   - Store complete cell state before each fold
   - Includes geometry_pieces, cell_type, is_partial
   - Allows fast restoration without re-computing

3. **Memory Management:**
   - Limit undo stack to 50 operations (configurable)
   - Free oldest operations when limit reached
   - Snapshots are freed when operation removed

---

## Implementation Tasks

### Task 1: Implement FoldOperation Class (1 hour)

**File:** `scripts/systems/FoldOperation.gd`

**Requirements:**
- Store fold parameters and affected cells
- Serialize/deserialize for save/load
- Calculate which cells were affected by fold

**Test File:** `scripts/tests/test_fold_operation.gd`

**Acceptance Criteria:**
- ✅ FoldOperation class compiles
- ✅ All tests pass (6-8 tests)
- ✅ Serialization correct

---

### Task 2: Implement UndoStack Class (1-1.5 hours)

**File:** `scripts/systems/UndoStack.gd`

**Requirements:**
- Manage stack of operations
- Push/pop operations
- Track current position
- Memory management

**Test File:** `scripts/tests/test_undo_stack.gd`

**Acceptance Criteria:**
- ✅ Stack operations work correctly
- ✅ All tests pass (8-10 tests)
- ✅ Memory properly managed

---

### Task 3: Implement Cell Snapshots (1 hour)

**File:** `scripts/core/Cell.gd` (enhancements)

**Requirements:**
- Create snapshots before fold
- Restore from snapshot
- Handle multi-piece cells

**Test File:** `scripts/tests/test_cell_snapshot.gd`

**Acceptance Criteria:**
- ✅ Snapshots created correctly
- ✅ Restoration accurate
- ✅ All tests pass (5-8 tests)

---

### Task 4: Integrate Undo with FoldSystem (1.5-2 hours)

**File:** `scripts/systems/FoldSystem.gd` (enhancements)

**Requirements:**
- Create operation before fold
- Push to undo stack after successful fold
- Implement undo_last_fold() method
- Validate undo eligibility (strict ordering)

**Test File:** `scripts/tests/test_fold_system_undo.gd`

**Acceptance Criteria:**
- ✅ Folds recorded in undo stack
- ✅ Undo restores grid state
- ✅ All tests pass (10-15 tests)

---

### Task 5: UI Integration (1-1.5 hours)

**File:** `scripts/ui/HUD.gd` (enhancements)

**Requirements:**
- Undo button/hotkey
- Visual feedback (disabled when no undo available)
- Display undo count if desired

**Test File:** `scripts/tests/test_hud_undo.gd`

**Acceptance Criteria:**
- ✅ Undo button functional
- ✅ Proper enable/disable state
- ✅ All tests pass (3-5 tests)

---

## Testing Summary

**Total New Tests:** 35-50

| Component | Tests | Priority |
|-----------|-------|----------|
| FoldOperation | 6-8 | P0 |
| UndoStack | 8-10 | P0 |
| Cell Snapshots | 5-8 | P0 |
| FoldSystem Undo | 10-15 | P1 |
| UI Integration | 3-5 | P1 |

**Target:** All tests passing (474 current + 35-50 new = 509-524 tests)

---

## Completion Checklist

- [ ] FoldOperation class implemented and tested
- [ ] UndoStack class implemented and tested
- [ ] Cell snapshot system working
- [ ] Undo integrated with FoldSystem
- [ ] UI buttons functional
- [ ] All 509-524 tests passing
- [ ] No memory leaks
- [ ] Code reviewed

---

**End of Phase 6 Specification**
