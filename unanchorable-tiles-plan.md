# Plan: Unanchorable Tile Types

## Overview

Add two new tile types — `UNANCHORABLE_FLOOR` and `UNANCHORABLE_WALL` — to the
`TileTypes` registry. Both disallow anchor placement. `UNANCHORABLE_FLOOR` is
walkable (player can stand on it); `UNANCHORABLE_WALL` is not walkable (behaves
like a wall for movement). Neither blocks fold excision (unlike PIN).

The single coordination point for anchor eligibility is
`GridManager.is_anchor_eligible`, which must be extended to reject cells whose
dominant tile type has `blocks_anchor = true`.

Level editor support is in scope: both types are added to the editor palette
(visual swatches + keyboard shortcuts), `Cell.get_cell_color_for_type` returns a
distinct color for each, and `LevelData` serializes/deserializes them as plain
integer type ids (no new dict format needed, since neither type carries
per-instance parameters).

---

## Sub-Tasks

---

### Sub-task 1 — Add `blocks_anchor` field + two new types to TileTypes

**Intent**
`TileTypes` is the single authority for per-type facts. Adding `blocks_anchor`
here means no other engine file needs to know the specific type IDs — they just
call `TileTypes.blocks_anchor(type)`.

**Expected Outcomes**
- `TileTypes` exports two new constants: `UNANCHORABLE_FLOOR` (type id `6`) and
  `UNANCHORABLE_WALL` (type id `7`).
- Every registry entry gains a `blocks_anchor` key (`false` for all existing
  types).
- `UNANCHORABLE_FLOOR`: `walkable=true`, `merge_rank=1`, `blocks_anchor=true`,
  `blocks_fold=false`, `on_enter=""`.
- `UNANCHORABLE_WALL`: `walkable=false`, `merge_rank=3`, `blocks_anchor=true`,
  `blocks_fold=false`, `on_enter=""`.
- A new static method `TileTypes.blocks_anchor(type: int) -> bool` is callable.
- `_DEFAULT` also includes `"blocks_anchor": false` (safe default for unknown
  types).

**Todo List**
1. In `scripts/model/TileTypes.gd`:
   - Add constants `UNANCHORABLE_FLOOR := 6` and `UNANCHORABLE_WALL := 7` with
     doc comments explaining their behavior.
   - Add `"blocks_anchor": false` to every existing `_REGISTRY` entry and to
     `_DEFAULT`.
   - Add entries for `UNANCHORABLE_FLOOR` and `UNANCHORABLE_WALL` using the
     correct property values listed above.
   - Add `static func blocks_anchor(type: int) -> bool` accessor (same pattern
     as `is_walkable` and `blocks_fold`).

**Relevant Context**
- [`scripts/model/TileTypes.gd`](scripts/model/TileTypes.gd) — follow the exact
  pattern used for `PIN` (id `5`). PIN's id is `5`; use `6` and `7`.
- `merge_rank` for `UNANCHORABLE_WALL` = 3 (same as WALL); for
  `UNANCHORABLE_FLOOR` = 1 (same as EMPTY / TRIGGER_FOLD).

**Status** `[ ] pending`

---

### Sub-task 2 — Enforce `blocks_anchor` in `GridManager.is_anchor_eligible`

**Intent**
`GridManager.is_anchor_eligible` is the single gate for anchor placement in the
UI path (both mouse-click and facing-interact flows). Adding the check here
means both flows are covered without touching `InteractionController` or
`FoldController`.

**Expected Outcomes**
- `is_anchor_eligible` returns `false` for any grid position whose dominant tile
  type has `blocks_anchor = true`, regardless of the null-anchor mode setting.
- The rejection visual + error sound (`_reject_anchor`) are already triggered by
  the existing `false` return — no additional UI wiring needed.
- The check uses `TileTypes.blocks_anchor(dominant_type)` via the derived state.

**Todo List**
1. In `scripts/core/GridManager.gd`, inside `is_anchor_eligible` (after the
   `get_cell` null-check and before the `NullAnchor` mode switch), add:
   - Get the dominant type: use `fold_system.state.dominant_type_at(grid_pos)`
     when `fold_system` is available; fall back to `cell.get_dominant_type()`
     otherwise.
   - If `TileTypes.blocks_anchor(dominant_type)` is `true`, return `false`.

**Relevant Context**
- [`scripts/core/GridManager.gd:316-333`](scripts/core/GridManager.gd:316) —
  `is_anchor_eligible` body.
- `GridManager` already holds a `fold_system` reference (the `FoldController`);
  `fold_system.state` exposes the current `FoldedState`;
  `FoldedState.dominant_type_at(pos)` is the correct query.
- Fall back to `cell.get_dominant_type()` when `fold_system` is null (editor /
  test contexts with no FoldController).

**Status** `[ ] pending`

---

### Sub-task 3 — Visual color + level editor palette entries

**Intent**
The two new types need a distinct on-screen color in the grid view and must
appear as selectable swatches in the level editor so level designers can paint
them. Serialization to/from level JSON files works automatically for plain
integer types — no extra `LevelData` changes are needed.

**Expected Outcomes**
- `Cell.get_cell_color_for_type` returns a distinct color for each new type:
  - `UNANCHORABLE_FLOOR`: EMPTY's light gray shifted slightly purple
    (e.g. `Color(0.75, 0.7, 0.85)`).
  - `UNANCHORABLE_WALL`: WALL's dark gray shifted slightly purple
    (e.g. `Color(0.25, 0.15, 0.3)`).
- `LevelEditor.PAINT_TYPES` includes entries for both new types with their names
  and matching colors.
- The editor's `create_palette()` iterates over the new type ids and renders
  swatches for them (the existing loop `for cell_type in [0, 1, 2, 3]` must be
  extended).
- Keyboard shortcuts `6` and `7` select and paint the new types (`KEY_6` /
  `KEY_7` added to the input handler).
- Saving/loading a level that contains these types round-trips correctly through
  `LevelData.to_dict()` / `from_dict()` — no changes needed since `cell_data`
  stores plain ints and `LevelData` already handles arbitrary int types.

**Todo List**
1. In `scripts/core/Cell.gd`, add two new cases to `get_cell_color_for_type`:
   - `TileTypes.UNANCHORABLE_FLOOR`: return EMPTY's gray shifted slightly purple
     (e.g. `Color(0.75, 0.7, 0.85)`).
   - `TileTypes.UNANCHORABLE_WALL`: return WALL's dark gray shifted slightly purple
     (e.g. `Color(0.25, 0.15, 0.3)`).
2. In `scripts/core/LevelEditor.gd`:
   - Add entries `6` and `7` to `PAINT_TYPES` with names and the same purple-tinted
     colors used in `Cell.get_cell_color_for_type`.
   - Extend the `create_palette()` loop from `[0, 1, 2, 3]` to
     `[0, 1, 2, 3, 6, 7]`.
   - Add `KEY_6` and `KEY_7` cases in the keyboard input handler, calling
     `select_and_paint(6)` and `select_and_paint(7)`.

**Relevant Context**
- [`scripts/core/Cell.gd:292-301`](scripts/core/Cell.gd:292) —
  `get_cell_color_for_type` match block; add new cases before the `_:` fallback.
- [`scripts/core/LevelEditor.gd:158-213`](scripts/core/LevelEditor.gd:158) —
  `PAINT_TYPES` constant and `create_palette` / `update_palette` methods.
- [`scripts/core/LevelEditor.gd:242-276`](scripts/core/LevelEditor.gd:242) —
  keyboard input handler; `KEY_4` and `KEY_5` are absent (TRIGGER_FOLD and PIN
  are not editable from the basic palette); add `KEY_6` and `KEY_7`.
- `LevelData.to_dict()` / `from_dict()` in
  [`scripts/core/LevelData.gd`](scripts/core/LevelData.gd) — no changes needed;
  plain int cell values serialise correctly already.

**Status** `[ ] pending`

---

### Sub-task 4 — Tests for the new tile types

**Intent**
Following TDD conventions, add tests that pin the new types' registry properties
and the anchor-eligibility gate. Two test files cover the two concerns:
`test_tile_types.gd` (registry facts) and a new `test_unanchorable_tiles.gd`
(integration: anchor placement rejected at the GridManager level).

**Expected Outcomes**
- `test_tile_types.gd` has new cases asserting:
  - Both new types are registered.
  - `UNANCHORABLE_FLOOR` is walkable; `UNANCHORABLE_WALL` is not.
  - Both have `blocks_anchor = true`.
  - Neither has `blocks_fold = true`.
  - Merge rank for `UNANCHORABLE_WALL` equals WALL's rank; for
    `UNANCHORABLE_FLOOR` equals EMPTY's rank.
- `test_unanchorable_tiles.gd` asserts that `is_anchor_eligible` returns `false`
  for cells of both new types and `true` for a neighboring `EMPTY` cell.
- All tests pass when run with `HOME=/tmp/godot-home ./run_tests.sh`.

**Todo List**
1. In `scripts/tests/test_tile_types.gd`, add a new test group with cases for
   `UNANCHORABLE_FLOOR` and `UNANCHORABLE_WALL` covering the outcomes above.
2. Create `scripts/tests/test_unanchorable_tiles.gd`:
   - Use the same `_engine` helper pattern from
     `test_fold_blocked_by_tile.gd` to build a minimal `FoldEngine` from a
     `LevelData`.
   - Since `is_anchor_eligible` lives on `GridManager` (which requires a scene
     node), test the property contract directly through `TileTypes.blocks_anchor`
     (which is what `is_anchor_eligible` delegates to) rather than instantiating
     a full `GridManager`. Include a note explaining why.
   - Additionally verify that `FoldEngine.apply_fold` is NOT blocked by the new
     types (they don't have `blocks_fold=true`), confirming they are freely
     foldable.
3. Run `HOME=/tmp/godot-home ./run_tests.sh tile_types` and
   `./run_tests.sh unanchorable` to confirm all new tests pass with no
   regressions.

**Relevant Context**
- [`scripts/tests/test_tile_types.gd`](scripts/tests/test_tile_types.gd)
- [`scripts/tests/test_fold_blocked_by_tile.gd`](scripts/tests/test_fold_blocked_by_tile.gd)
  — reference for the `_engine` helper pattern.

**Status** `[ ] pending`

---

## Notes

- `merge_rank` for the two new types follows the nearest analog:
  `UNANCHORABLE_WALL` ranks with WALL (3); `UNANCHORABLE_FLOOR` ranks with EMPTY
  (1). This means if `UNANCHORABLE_WALL` and EMPTY share a cell after a fold, the
  wall-rank wins (correct); if `UNANCHORABLE_FLOOR` and WALL share a cell, the
  wall wins (correct — the unanchorable floor "disappears" under a wall).
- `on_enter` is `""` for both types (no trigger behavior at this time).
- PIN (id 5) already holds `merge_rank: 6`; ids 6 and 7 do not conflict with any
  existing rank values.
- `LevelData` serialization requires no changes: plain int type ids in
  `cell_data` already round-trip correctly through `to_dict()` / `from_dict()`.
- Colors chosen in Sub-task 3 are suggestions; the implementer may adjust for
  visual clarity in the actual game context.
