# Project Status - Space-Folding Puzzle Game

**Last Updated:** 2026-07-07
**Current Phase:** Core mechanics complete (Phases 1-7). Remaining work is content & polish (Phases 8-11).
**Total Tests:** **568 passing** / 568 (0 failing, 0 risky)

---

## Quick Summary

| Metric | Value |
|--------|-------|
| Core mechanic phases | ✅ Complete (1, 2, 3, 4, 5, 6, 7) |
| Support phases | ⚙️ Substantial (9 Levels, 10 GUI/Audio) |
| Tests passing | 568 / 568 (0 failing, 0 risky) |
| Test run time | ~6s |

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
Dual system with a deliberate behavioral split (see CLAUDE.md §2a):
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

---

## Substantially Complete ⚙️

### Phase 9: Level Management System
GUI (MainMenu, HUD, PauseMenu, LevelComplete, Settings), JSON level
data/serialization, load/save, campaign progression with stars/unlocking, level
validation, custom-level support. **Remaining:** campaign content creation, final
integration polish.

### Phase 10: Graphics, GUI & Audio Polish
Complete GUI, HUD fold counter, AudioManager with SFX/music integration.
**Remaining:** particle effects, seam visual polish, UI/UX refinements.

---

## Pending Phases 📋

| Phase | Name | Priority | Est. Time | Notes |
|-------|------|----------|-----------|-------|
| 8 | Cell Types & Visual Elements | P2 | 3-4h | No spec doc yet |
| 9 | Level Management (polish) | P2 | 1-2h | Content + integration |
| 10 | Graphics/Audio (polish) | P3 | 2-3h | Particles, animations |
| 11 | Testing & Validation | P4 | 4-5h | Edge cases, perf |

---

## Recent Changes

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
  phase_6 spec to `completed/`, refreshed phase README and CLAUDE.md. Replaced the
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

None. All 568 tests pass with no failing or risky tests.

Several `test_*_bug.gd` / `test_*_debug.gd` / `test_*_trace.gd` files remain from
past bug hunts; they still assert (not risky) but are print-heavy and could be
consolidated in a future cleanup pass.

---

## For Detailed Information

- [CLAUDE.md](CLAUDE.md) — AI agent quick start
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design decisions
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — development workflow
- [docs/REFERENCE.md](docs/REFERENCE.md) — API reference
- [docs/phases/](docs/phases/) — phase-specific documentation
