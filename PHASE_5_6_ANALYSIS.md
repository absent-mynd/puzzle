# Phase 5 & 6 Readiness Analysis

**Date:** 2025-11-07  
**Current Status:** Phase 4 Complete (361/363 tests passing)  
**Question:** What's needed before Phase 5? Can Phase 6 run in parallel?

---

## Executive Summary

**Phase 5 (Multi-Seam Handling):**
- ✅ **Can start immediately** - Phase 4 dependency met
- ⚠️ **Requires 3 new implementations** before core work
- **Estimated prep time:** 2-3 hours
- **Total phase time:** 6-9 hours (including prep)

**Phase 6 (Undo System):**
- ⚠️ **Cannot fully start yet** - needs shared infrastructure from Phase 5
- ✅ **Can do partial parallel work** - UI and basic structure
- **Blocker:** Requires enhanced fold history (shared with Phase 5)
- **Recommendation:** Start after Phase 5 foundation (first 2-3 hours)

---

## Phase 5 Prerequisites

### ✅ Dependencies Met
- Phase 4 (Geometric Folding) complete
- Cell splitting algorithm working
- Coordinate system stable
- Test framework in place

### ⚠️ Infrastructure Needed (2-3 hours prep work)

#### 1. Seam Class Implementation (30-45 min)
**Status:** Currently `seams: Array[Seam] = []` in Cell, but Seam class doesn't exist

**Required implementation:**
```gdscript
class_name Seam extends Resource

@export var line_point: Vector2        # Point on seam line (LOCAL coords)
@export var line_normal: Vector2       # Normal vector (perpendicular to fold)
@export var intersection_points: PackedVector2Array  # Where seam crosses cell boundary
@export var fold_id: int               # Which fold created this seam
@export var timestamp: int             # When fold occurred (for ordering)
@export var fold_type: String          # "horizontal", "vertical", "diagonal"

func get_seam_endpoints() -> Array[Vector2]:
    # Returns the two points where seam intersects cell boundary
    return [intersection_points[0], intersection_points[1]]
```

**Why needed:**
- Phase 5 tessellation requires tracking multiple seams per cell
- Each seam needs metadata to subdivide polygons correctly
- Undo system (Phase 6) needs seam history

**File location:** `scripts/core/Seam.gd`

**Tests needed:** 5-8 tests for seam creation, serialization, comparison

---

#### 2. Enhanced Fold History (45-60 min)
**Status:** Current `fold_history` only stores positions, not cell data

**Current fold record (lines 300-311 in FoldSystem.gd):**
```gdscript
func create_fold_record(...) -> Dictionary:
    return {
        "fold_id": next_fold_id,
        "anchor1": anchor1,
        "anchor2": anchor2,
        "removed_cells": removed_cells.duplicate(),  # Only positions!
        "orientation": orientation,
        "timestamp": Time.get_ticks_msec()
    }
```

**Required enhancement:**
```gdscript
func create_fold_record_enhanced(...) -> Dictionary:
    return {
        "fold_id": next_fold_id,
        "anchor1": anchor1,
        "anchor2": anchor2,
        
        # For undo: Store complete cell data
        "removed_cells": serialize_cells(cells_to_remove),
        "modified_cells": serialize_cells_state(cells_that_were_split),
        "shifted_cells": {
            "cells": serialize_cells(cells_that_shifted),
            "shift_vector": shift_vector,
            "original_positions": original_positions
        },
        
        # Seam data
        "seams_created": seam_data_array,
        
        # Metadata
        "orientation": orientation,
        "timestamp": Time.get_ticks_msec(),
        "player_position_before": player.grid_position
    }

func serialize_cells(cells: Array) -> Array:
    # Convert cells to dictionaries with all data
    var result = []
    for cell in cells:
        result.append({
            "grid_position": cell.grid_position,
            "geometry": cell.geometry.duplicate(),
            "cell_type": cell.cell_type,
            "is_partial": cell.is_partial,
            "seams": cell.seams.duplicate()
        })
    return result
```

**Why needed:**
- Phase 6 (Undo) requires complete state to restore
- Phase 5 (Multi-Seam) needs to track seam creation per fold
- Debugging complex fold scenarios

**Tests needed:** 8-10 tests for serialization, state capture, restoration

---

#### 3. Polygon Union Algorithm (60-90 min)
**Status:** Currently `_merge_cells_simple()` just keeps one cell, frees other

**From CELL_MERGE_ANALYSIS.md:**
> Current implementation keeps existing cell, frees incoming cell.
> Missing: geometric union of polygons.

**Required implementation:**
```gdscript
## Compute union of two polygons
## Returns a single polygon containing both input polygons
##
## @param poly1: First polygon (PackedVector2Array)
## @param poly2: Second polygon (PackedVector2Array)
## @return: Union polygon, or null if union fails
static func polygon_union(poly1: PackedVector2Array, poly2: PackedVector2Array) -> PackedVector2Array:
    # Implementation options (choose one):
    # 1. Godot's Geometry2D.merge_polygons() - PREFERRED if available
    # 2. Simplified convex hull (fast but loses detail)
    # 3. Weiler-Atherton algorithm (robust but complex)
```

**Godot 4.3 Option:**
Godot has `Geometry2D.merge_polygons()` which returns array of polygons (union may not be convex).

**Implementation approach:**
```gdscript
static func polygon_union(poly1: PackedVector2Array, poly2: PackedVector2Array) -> PackedVector2Array:
    # Use Godot's built-in merge
    var merged = Geometry2D.merge_polygons(poly1, poly2)
    
    if merged.is_empty():
        # Fallback: return convex hull
        return compute_convex_hull([poly1, poly2])
    
    if merged.size() == 1:
        # Simple case: single merged polygon
        return merged[0]
    else:
        # Complex case: multiple polygons (concave union)
        # For Phase 5: keep largest polygon
        # For Phase 6+: may need to handle multiple pieces
        return get_largest_polygon(merged)
```

**Why needed:**
- Phase 5 tessellation requires proper geometric unions
- When cells with multiple seams merge, geometries must combine correctly
- Visual accuracy for complex fold scenarios

**Tests needed:** 10-15 tests for various polygon union scenarios

---

### Phase 5 Core Implementation (After Prep)

Once the 3 prerequisites are done, Phase 5 can proceed with:

1. **Tessellation algorithm** (2-3 hours)
   - Subdivide cells with multiple seams
   - Create convex sub-polygons
   - Track which seams bound each piece

2. **Seam intersection handling** (1-2 hours)
   - Detect when new fold intersects existing seams
   - Compute intersection points
   - Update tessellation

3. **Visual representation** (1 hour)
   - Draw seam lines within cells
   - Color-code by fold order
   - Visual feedback for multi-seam cells

4. **Testing** (1-2 hours)
   - 20-30 tests for tessellation
   - Edge cases (3+ seams, parallel seams)
   - Performance tests

**Total Phase 5 Time:** 6-9 hours (including 2-3 hour prep)

---

## Phase 6 Readiness

### ✅ Dependencies Met (Partially)
- Phase 3, 4 complete ✅
- Basic fold execution working ✅

### ⚠️ Critical Blockers

#### 1. Enhanced Fold History Required
**Problem:** Current fold history doesn't store enough data to undo

**What's missing:**
- Original cell geometries before splits
- Cell data for removed cells (to restore them)
- Original positions before shifts
- Seam data per fold

**Impact:** Cannot implement undo without this

**Solution:** Same enhancement needed for Phase 5 (see above)

---

#### 2. Seam Class Required
**Problem:** To undo splits, need to know which seams to remove

**Impact:** Cannot cleanly undo cell splits without seam tracking

**Solution:** Same Seam class needed for Phase 5

---

#### 3. State Restoration Logic
**Problem:** Need to reverse all fold operations

**What's needed:**
```gdscript
func undo_fold(fold_record: Dictionary) -> bool:
    # 1. Restore removed cells
    for cell_data in fold_record.removed_cells:
        recreate_cell_from_data(cell_data)
    
    # 2. Unshift shifted cells
    var shift_vector = fold_record.shifted_cells.shift_vector
    for cell in fold_record.shifted_cells.cells:
        shift_cell_back(cell, -shift_vector)
    
    # 3. Restore split cells to original geometry
    for cell_data in fold_record.modified_cells:
        restore_cell_geometry(cell_data)
    
    # 4. Remove seams created by this fold
    for seam in fold_record.seams_created:
        remove_seam_from_cells(seam)
    
    # 5. Restore player position
    player.grid_position = fold_record.player_position_before
    
    # 6. Remove fold from history
    fold_history.erase(fold_record)
    
    return true
```

**Complexity:** 3-4 hours of implementation + testing

---

### What Can Be Done in Parallel?

#### ✅ Can Start Now (1-2 hours):
1. **Undo UI components**
   - Undo button in HUD
   - Keyboard shortcut (Ctrl+Z)
   - Visual feedback
   - Disable when history empty

2. **Basic undo framework**
   - Undo command pattern structure
   - History management (max size, clearing)
   - Unit tests for history operations

3. **Dependency checking logic**
   - Determine if fold can be undone (is it most recent affecting all cells?)
   - Validation without actual undo

#### ⚠️ Cannot Start Until Phase 5 Prep Done (2-3 hours):
- Enhanced fold history implementation
- Seam class implementation
- State restoration logic
- Actual undo execution

---

## Recommended Sequence

### Option A: Sequential (Safest)
```
1. Phase 5 Prep (2-3h)
   - Seam class
   - Enhanced fold history
   - Polygon union
   
2. Phase 5 Core (4-6h)
   - Tessellation
   - Multi-seam handling
   
3. Phase 6 (4-5h)
   - Undo logic
   - UI
   - Testing
```
**Total time:** 10-14 hours
**Advantage:** Clean dependencies, less context switching
**Risk:** Low

---

### Option B: Partial Parallel (Faster)
```
Week 1:
  Day 1-2: Phase 5 Prep (2-3h)
           - Seam class ✓
           - Enhanced fold history ✓
           - Polygon union ✓
           
           Phase 6 UI Work (1-2h) PARALLEL
           - Undo button ✓
           - Keyboard shortcuts ✓
           - Basic framework ✓
  
  Day 3-4: Phase 5 Core (4-6h)
           - Tessellation
           - Multi-seam handling
           
           Phase 6 Dependency Logic (1-2h) PARALLEL
           - Validation
           - History management
  
  Day 5: Phase 6 Completion (2-3h)
         - Undo execution
         - Integration
         - Testing
```
**Total time:** 9-13 hours (20% faster)
**Advantage:** Faster delivery, parallelizable
**Risk:** Medium (context switching, potential rework)

---

### Option C: Wait for Phase 5 (Most Conservative)
```
1. Complete Phase 5 entirely (6-9h)
2. Then start Phase 6 (4-5h)
```
**Total time:** 10-14 hours
**Advantage:** Maximum code reuse, cleanest architecture
**Risk:** Very low

---

## Detailed Blockers Summary

| Component | Phase 5 Needs | Phase 6 Needs | Status | Priority |
|-----------|--------------|--------------|--------|----------|
| **Seam class** | ✅ Required | ✅ Required | ❌ Missing | P0 |
| **Enhanced fold history** | ✅ Required | ✅ Required | ❌ Missing | P0 |
| **Polygon union** | ✅ Required | ⚠️ Helpful | ❌ Missing | P0 |
| **Tessellation** | ✅ Required | ⬜ Not needed | ❌ Missing | P1 |
| **Undo UI** | ⬜ Not needed | ✅ Required | ❌ Missing | P2 |
| **State restoration** | ⬜ Not needed | ✅ Required | ❌ Missing | P1 |

**Shared infrastructure (P0):** Seam class + Enhanced fold history = 2-3 hours

---

## Recommendation

### 🎯 **Best Approach: Option B (Partial Parallel)**

**Phase 5 Prep (Start Immediately):**
1. Implement Seam class (30-45 min)
2. Enhance fold history (45-60 min)
3. Add polygon union to GeometryCore (60-90 min)

**Then split work:**
- **Track A (Phase 5):** Tessellation + multi-seam handling (4-6h)
- **Track B (Phase 6):** Undo UI + framework (2-3h in parallel)

**After Phase 5 core done:**
- Complete Phase 6 undo execution (2-3h)

**Total estimated time:** 9-13 hours across both phases

---

## Critical Path

```
START
  │
  ├─→ Seam class (30-45 min) ─────────────┐
  │                                        │
  ├─→ Enhanced fold history (45-60 min) ──┤→ PHASE 5 & 6 UNBLOCKED
  │                                        │
  └─→ Polygon union (60-90 min) ──────────┘
        │
        ├─→ PHASE 5: Tessellation (4-6h)
        │
        └─→ PHASE 6: Undo logic (4-5h)
              (can start UI work in parallel after 2-3h)

TOTAL: 9-14 hours
```

---

## Testing Strategy

### Phase 5 Tests (25-35 total)
- Seam class: 5-8 tests
- Enhanced history: 8-10 tests  
- Polygon union: 10-15 tests
- Tessellation: 20-25 tests
- Multi-seam handling: 15-20 tests

### Phase 6 Tests (20-30 total)
- History management: 5-8 tests
- Undo validation: 8-10 tests
- State restoration: 10-15 tests
- UI integration: 5-8 tests

**Combined new tests:** 45-65 tests
**Target success rate:** 100% (all must pass)

---

## Conclusion

### Direct Answers to Your Questions:

**Q: What still needs implemented before Phase 5 can proceed?**

**A:** Three things (2-3 hours total):
1. ✅ **Seam class** - Track fold lines in cells
2. ✅ **Enhanced fold history** - Store complete cell state
3. ✅ **Polygon union** - Merge geometries correctly

These are not technically "blockers" but Phase 5 quality will suffer without them.

---

**Q: Can Phase 6 proceed in parallel?**

**A:** **Partially yes, with caveats:**

✅ **Can do now (in parallel with Phase 5 prep):**
- Undo UI components (button, shortcuts)
- Basic framework structure
- Dependency checking logic

⚠️ **Must wait 2-3 hours for:**
- Seam class (shared with Phase 5)
- Enhanced fold history (shared with Phase 5)

⚠️ **Should wait 6-9 hours for:**
- Full Phase 5 completion gives cleanest architecture
- But not required - can implement undo after 2-3h of Phase 5 prep

**Recommendation:** Start Phase 5 prep now (2-3h), then decide:
- If you want speed: parallelize Phase 6 UI work
- If you want clean code: finish Phase 5 core first

---

## Next Steps

1. ✅ **Create Seam class** (`scripts/core/Seam.gd`)
2. ✅ **Enhance fold history** (update `FoldSystem.gd`)
3. ✅ **Add polygon union** (update `GeometryCore.gd`)
4. ✅ **Write tests** for all three (15-25 tests)
5. 🎯 **Then proceed** with Phase 5 OR split into parallel tracks

**Estimated start-to-Phase-5-ready time:** 2-3 hours

---

**End of Analysis**
