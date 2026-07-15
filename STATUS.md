# Project Status - Space-Folding Puzzle Game

**Last Updated:** 2026-07-15
**Current Phase:** Fold engine re-architected twice over: derive/replay (fold-list) →
step-log replay (F1-F7). Core mechanics + step-log foundation complete. Content/editor
support for the new tile types is the current gap.
**Total Tests:** **496 passing** / 496 (0 failing, 0 risky)

---

## Quick Summary

| Metric | Value |
|--------|-------|
| Core mechanic phases | ✅ Complete (1, 2, 3, 4, 5, 6, 7) |
| Step-log foundation (F1-F7 + collision) | ✅ Complete — see below |
| Support phases | ⚙️ Substantial (9 Levels, 10 GUI/Audio) |
| Tests passing | 496 / 496 (0 failing, 0 risky) |
| Test run time | ~9s |

> Test count dropped from 617 → 496 overall: the 2026-07-10 derive/replay rewrite
> deleted the legacy `FoldSystem`/`ActionHistory`/`Seam`/null-piece test suites
> (~6,300 lines) along with the code they covered (617 → 357), then both rewrites
> added back new suites — `test_fold_replay`, `test_folded_state`, `test_step_log_replay`,
> `test_trigger_cascade`, `test_tile_types`, `test_collision_core`, occupant tests, etc.
> — bringing the count to 496. Net behavior coverage is not smaller, it's a different
> (leaner, per-mutation) architecture. See AGENTS.md for the full architectural writeup.

> **Running tests locally:** the bundled `tools/godot/godot` is a Linux binary.
> On macOS use a system Godot 4.x. Because the sandbox blocks Godot's default
> config dir, redirect HOME:
> ```
> HOME=/private/tmp/godot-home godot --path . --headless -s addons/gut/gut_cmdln.gd
> ```

---

## Completed Phases ✅

### Phase 1: Project Setup & Foundation (2025-11-05)
GeometryCore utility class — Sutherland-Hodgman polygon splitting, point-line
relationships, intersections, area/centroid. Files: `scripts/utils/GeometryCore.gd`.

### Phase 2: Basic Grid System (2025-11-05)
Cell and GridManager classes, 10×10 grid, anchor selection (max 2), hover/select
feedback, grid↔world↔local coordinate conversion. Files: `scripts/core/Cell.gd`,
`scripts/core/GridManager.gd`.

### Phase 3: Simple Axis-Aligned Folding (2025-11-06)
FoldSystem with horizontal/vertical folds, cell overlap/merge at anchors, seam
line creation/shift/removal, player-position validation, memory-safe cell cleanup.
Files: `scripts/systems/FoldSystem.gd`.

### Phase 4: Geometric Folding (2025-11-07)
Diagonal folds at arbitrary angles. Cut-line calculation with perpendicular
normals, cell classification into regions, polygon splitting, cross-seam merging,
anchor normalization, two-pass shift. All fold orientations now route through
`execute_diagonal_fold()`.

### Phase 5: Multi-Seam Handling (2025-11-08)
Multiple intersecting seams per cell via multi-piece cells (CellPiece), Seam class,
per-piece classification/merging, null-piece system for geometric completeness.
Files: `scripts/core/CellPiece.gd`, `scripts/core/Seam.gd`.

### Phase 6: Undo/Unfold System (2025-11-09)
Dual system with a deliberate behavioral split (see AGENTS.md §2a):
- **UNFOLD** (seam clicks, `unfold_seam()`) — independent geometric reversal. Any
  fold can be unfolded in any order; other folds are preserved. Blocked only if the
  player stands on the seam or a newer seam intersects. Does not restore player pos.
- **UNDO** (button/keyboard, `undo_fold_by_id()`) — full snapshot restore including
  player position. No seam validation (a snapshot restore always applies).

Includes seam-to-fold mapping, clickable-zone calc, action history for sequential
undo, and the independent-unfold refactor.

### Phase 7: Player Character (2025-11-06)
Grid-based movement (arrows/WASD), wall collision, goal detection / win condition,
position updates during folds. Files: `scripts/core/Player.gd`.

### F1-F7 + Collision: Step-Log Foundation (2026-07-15)
Second engine rewrite. Promoted the source of truth from a fold-only list to a full
action log (`FoldStep`) so every mutation (fold, unfold, move, place-anchor) is
replay-reachable and undoable by construction (`StepReplay`, incremental checkpoint
stack, O(1) undo). Files: `scripts/model/`, `scripts/systems/FoldEngine.gd`.
- **F1 TileTypes** (`scripts/model/TileTypes.gd`) — single registry for
  walkable/merge_rank/blocks_fold/blocks_anchor/on_enter per tile type. Two new
  tile types added directly on top of it: `UNANCHORABLE_FLOOR` / `UNANCHORABLE_WALL`
  (block anchor placement, don't block folding).
- **F2 FoldStep + StepReplay** — step-log model, split-on-unfold, latent bodies,
  multi-body player.
- **F3 TriggerResolver** — fold-on-enter cascade (`TRIGGER_FOLD` tiles), cycle-guarded
  via a per-cascade `fired` set, deterministic, hard iteration cap.
- **F4** — player can be split into multiple bodies by a fold instead of collapsing
  to one (`test_player_split.gd`).
- **F5** — general fold-block predicate: `PIN` tiles are fold-proof obstacles (can't
  be stood on, can't be excised/cut by a fold).
- **F6 Occupants** — boxes, split-off player bodies, and anchors generalized as
  occupants; `FoldController` occupant overlays; engine-authoritative movement.
- **F7 Pre-placed folds** — `LevelData.folds` applied before the player spawns;
  nested-reveal on unfold; crease dots rendered for each pre-fold.
- **Collision engine** (`scripts/utils/CollisionCore.gd`) — polygon clips + swept
  collision + navigable predicates; carried rigid geometry (cuts stay cut, relative
  to the base tile's anchor); footprint/occupant blocking.
- 10 new custom demo levels (`levels/custom/t1_pressure_gate.json` … `t10_squeeze_by.json`)
  showcasing PIN/TRIGGER_FOLD/box mechanics. **The official 10-level campaign
  (`levels/campaign/`) still only uses the original wall/water/goal tiles** — none
  of the new mechanics have been woven into it yet.
- `CLAUDE.md` renamed to `AGENTS.md` project-wide as part of this merge.
- Level editor palette gained swatches for `UNANCHORABLE_FLOOR`/`UNANCHORABLE_WALL`
  but **not** for `PIN` or `TRIGGER_FOLD` — those two types can currently only be
  authored by hand-editing level JSON.

---

## Substantially Complete ⚙️

### Phase 9: Level Management System
GUI (MainMenu, HUD, PauseMenu, LevelComplete, Settings), JSON level
data/serialization, load/save, campaign progression with stars/unlocking, level
validation, custom-level support. **10-level campaign authored** (fold-forcing puzzles,
solvability-tested). **Remaining:** final integration polish.

### Phase 10: Graphics, GUI & Audio Polish
Complete GUI, HUD fold counter, AudioManager with SFX/music integration.
**Remaining:** particle effects, seam visual polish, UI/UX refinements.

---

## Pending / Next Steps 📋

The "Phase 8-11" framing below predates the F1-F7 rewrite and is kept for history;
the concrete next steps identified after F1-F7 are:

| Item | Priority | Notes |
|------|----------|-------|
| Level editor support for `PIN` / `TRIGGER_FOLD` | P1 | Paintable today only via hand-edited JSON (`levels/custom/t*.json`). `TRIGGER_FOLD` also needs a UI for its per-instance data (channel, anchors). |
| Weave new mechanics into the official campaign | P2 | The 10-level campaign (`levels/campaign/`) is still wall/water/goal-only; PIN/TRIGGER_FOLD/boxes/unanchorable tiles only appear in the `t1`-`t10` demo levels. |
| Refresh `docs/ARCHITECTURE.md` / `docs/REFERENCE.md` | P2 | Still describe the deleted `FoldSystem`/`ActionHistory`/null-piece system as current; AGENTS.md is now the accurate source. |
| Cell Types & Visual Elements polish | P3 | Distinct rendering/animation for PIN, TRIGGER_FOLD, unanchorable tiles (currently flat-color swatches). |
| Graphics/Audio polish | P3 | Particle effects, seam visual polish, UI/UX refinements (carried over from old Phase 10 backlog). |
| Testing & Validation | P4 | Edge cases, performance, larger grids. |

<details>
<summary>Original Phase 8-11 table (pre-F1-F7, kept for history)</summary>

| Phase | Name | Priority | Est. Time | Notes |
|-------|------|----------|-----------|-------|
| 8 | Cell Types & Visual Elements | P2 | 3-4h | No spec doc yet |
| 9 | Level Management (polish) | P2 | 1-2h | Content + integration |
| 10 | Graphics/Audio (polish) | P3 | 2-3h | Particles, animations |
| 11 | Testing & Validation | P4 | 4-5h | Edge cases, perf |

</details>

---

## Recent Changes

### 2026-07-15
- **F1-F7 + collision engine merged** (see "F1-F7 + Collision" section above for the
  full breakdown). Second engine rewrite in a week: promotes the source of truth from
  a fold-only list to a full step log so every mutation is replay-reachable and
  undoable by construction.
- `CLAUDE.md` → `AGENTS.md` rename applied repo-wide.
- Test suite: 617 (pre-derive/replay) → 357 (2026-07-10 rewrite) → **496 passing**,
  0 failing, 0 risky (2026-07-15).
- Previously open items from the 2026-07-10 rewrite are now resolved: the
  wall-folded-onto-goal ambiguity is settled by `TileTypes.merge_rank` (goal=4 beats
  wall=3, by design, not by accident), and all campaign level solutions pass under
  the full suite (`test_custom_levels_solvable.gd`, campaign BFS-verification tests).

### 2026-07-10
- **Level editor usability pass.** The editor↔play round-trip now works: pressing `T`
  (Test) stashes the live editing session in `GameManager` (`is_testing_from_editor` +
  `editor_session`), and a **Back to Editor** button on the pause and level-complete
  screens (plus a **TEST MODE** banner on the HUD) returns to the editor with all edits,
  cursor, player start, filename, and grid size intact. `LevelEditor._ready()` restores the
  stashed session; `GameManager.return_to_editor()` clears gameplay state but preserves the
  session for the editor to consume.
- Fixed `GameManager.restart_level()` no-op during an editor test (empty level id): it now
  reloads the in-memory `current_level_data`. Dropped the temp-JSON write in `test_level()`
  that silently clobbered `custom_level.json`.
- New editor conveniences: on-screen **tool palette** (active paint type highlighted),
  **mouse click/drag painting** (right-click erases), **grid resize** (`G`, e.g. `12x8`)
  with cell/cursor clamping, and **metadata editing** (`M`: name / par / difficulty).
  `load_level`/`new_level` now route through `resize_grid` so non-10×10 levels load
  correctly.
- Split `GameManager` return/restart methods into pure `_prepare_*` state mutators (for
  testability) + thin scene-change callers. Added `test_game_manager_editor_roundtrip.gd`,
  `test_editor_ui_wiring.gd`, `test_level_editor.gd` (round-trip state, UI node wiring,
  editor boot/palette/resize/paint).

### 2026-07-08
- Phase 8 gameplay interaction (in progress): center-dot highlights (hover any piece
  of a merged cell), second-anchor fold-region preview, crease dots at fold merge
  points, player facing + SPACE interact, and configurable interaction axes
  (`InteractionConfig`/`InteractionController`). Anchor placement now rejects
  ineligible/invalid anchors in both mouse and facing flows.
- Fixed unfold shift direction: it derived the shift from `anchor1-anchor2`, which is
  wrong when anchors were selected in reverse order (normalization picks target/source
  independently). Now uses stored `target_anchor-source_anchor` (`_fold_shift_vector`).
- Fixed unfold geometry position: `reverse_shifts_for_fold` re-keyed reversed cells but
  never translated their geometry back, so cells rendered at the folded location while
  indexed at the original slot (overlap + vacant-slot). Now translates by the inverse
  shift.
- Crease markers ride the cells they sit on through folds/unfolds via
  `remap_grid_markers` (the extension point for future grid-attached entities).
- Fixed unfold cell IDENTITY: cut-line cells were rebuilt with the merge's dominant type
  (a goal merged onto empty left the wrong cell green) and, for diagonal folds, the
  source cut line's cells were left as holes / stale NULL cells. Reverse-shifted cells and
  all cut-line cells (both lines) are now reconciled from the pre-fold snapshot
  (`_populate_cell_from_snapshot`, `reconcile_cut_line_cells`) — rebuilding existing cells
  and recreating vacated ones — when no other fold's seam remains on them.
- Campaign rebuilt: removed all pre-existing campaign/custom levels and authored a fresh
  **10-level campaign** (`levels/campaign/01_first_fold` … `10_the_gauntlet`) of
  fold-forcing wall/water puzzles with a difficulty ramp (single fold → two-axis → diagonal
  → 12×12 finale). `ProgressManager` sequence + default unlock updated. Added
  `test_campaign_levels.gd`, which loads each level, applies its intended fold solution, and
  BFS-verifies the goal is unreachable by walking but reachable after folding (par matches).
- Editor: interaction axes (A–D) are now direct enum dropdowns on the Main node
  (`second_anchor`, `confirm_persistence`, `action_priority`, `null_anchor`) instead of an
  empty sub-resource, so they can be toggled without creating a resource.
- ALLOW_MOVEMENT now defers player-position fold validation to commit time (the player may
  place the 2nd anchor while inside the fold region); the invalid region flashes red at
  commit if still blocked. Preview visuals now draw ON TOP of the map (raised z_index).
- Test suite: 568 → **617 passing**, 0 failing, 0 risky.

### 2026-07-07
- Fixed unfold bug: `restore_removed_cells_for_fold()` now refills the full fold
  footprint (removed cells **and** shift-destination positions), not just
  `removed_cells`. The source-anchor column — vacated when a merge-target cell
  shifts back on unfold — is now correctly restored. (10-cell gap → full restore.)
- Rewrote `test_undo_blocked_fold_returns_false` →
  `test_undo_succeeds_even_with_intersecting_newer_fold` to match the intentional
  Phase 6 design (undo no longer performs seam-intersection validation).
- Fixed a silent coverage regression: `test_seam_undo.gd` still called
  `can_undo_fold_seam_based()`, which the Phase 6 refactor renamed to
  `has_newer_seam_intersections()`. The calls errored before asserting, so 9
  seam-intersection tests were marked "risky" (running nothing). Updated all
  call sites — those tests now assert.
- Pruned 3 print-only diagnostic scratch tests (deleted
  `test_diagonal_45deg_fold.gd`; removed `test_understand_keep_side_for_vertical_fold`).
- Test suite: 556 → **568 passing**, 0 failing, 0 risky.
- Documentation cleanup: removed obsolete root analysis/planning docs
  (CELL_MERGE_ANALYSIS, PHASE_5_6_ANALYSIS, UNFOLD_REFACTOR_PLAN), moved completed
  phase_6 spec to `completed/`, refreshed phase README and AGENTS.md. Replaced the
  hand-written REFERENCE.md with a source pointer/code map; `run_tests.sh` now
  falls back to a system Godot when the bundled Linux binary can't execute.

### 2025-11-09
- Independent unfold system implemented (folds unfold in any order, preserving
  other folds). Unfold vs undo behavior distinction finalized.

### 2025-11-08
- Phase 5 (Multi-Seam Handling) complete.

### 2025-11-05 → 11-07
- Phases 1-4 and 7 complete; level system and audio brought to substantial state.

---

## Known Issues

None functionally. All 496 tests pass with no failing or risky tests.

Documentation gaps (see "Pending / Next Steps" above):
- `docs/ARCHITECTURE.md` and `docs/REFERENCE.md` were not updated for either the
  derive/replay or the F1-F7 step-log rewrite and describe deleted code
  (`FoldSystem.gd`, `ActionHistory.gd`, the null-piece system) as current.
- The `test_*_bug.gd` / `test_*_debug.gd` / `test_*_trace.gd` files noted in earlier
  status reports were deleted along with legacy `FoldSystem` in the 2026-07-10
  rewrite, so that cleanup item is now moot.

---

## For Detailed Information

- [AGENTS.md](AGENTS.md) — AI agent quick start
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design decisions
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — development workflow
- [docs/REFERENCE.md](docs/REFERENCE.md) — API reference
- [docs/phases/](docs/phases/) — phase-specific documentation
