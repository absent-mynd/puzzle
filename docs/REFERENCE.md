# Code Map (Source Pointer Reference)

**Purpose:** Point you to the *right source file* for any subsystem. The source is
the authoritative API — this doc deliberately does **not** restate function
signatures, because a hand-maintained API list drifts out of sync with the code
(this file used to do that, and it went stale). Read the file; every class carries
`##` doc-comments on its public methods.

> **Finding things fast**
> - Every public type has a `class_name`, so grep for it: `grep -rn "class_name Cell" scripts/`
> - Jump to a symbol's definition or callers with your editor's LSP, or:
>   `grep -rn "func <name>" scripts/`
> - List a file's public API: `grep -nE "^(func|var|const|signal|class_name) " scripts/<file>.gd`

---

## Subsystem → File

### Geometry (pure math, no scene tree)
| Concern | File |
|---|---|
| Polygon splitting (Sutherland-Hodgman), point/line tests, intersections, area/centroid, complement geometry for null pieces. `const EPSILON = 0.0001` lives here. | `scripts/utils/GeometryCore.gd` |
| File I/O helpers (JSON read/write) | `scripts/utils/FileUtils.gd` |

### Grid & cells
| Concern | File |
|---|---|
| A single grid cell: `grid_position`, `geometry_pieces: Array[CellPiece]`, dominant `cell_type`, `is_partial`. Cell coords are **LOCAL**. | `scripts/core/Cell.gd` |
| One polygon piece within a cell (geometry, type, `source_fold_id`, seams). Created when cells are split/merged. | `scripts/core/CellPiece.gd` |
| A fold line stored on a piece (`line_point`, `line_normal`, intersection points, `fold_id`, `fold_type`). | `scripts/core/Seam.gd` |
| The grid itself: `cells: Dictionary` (Vector2i→Cell), anchor selection, `grid_origin`, coordinate conversion. `GridManager.position` sits at `grid_origin`. | `scripts/core/GridManager.gd` |

### Folding (the core mechanic — largest file, ~2.5k loc)
| Concern | Entry points in `scripts/systems/FoldSystem.gd` |
|---|---|
| Execute a fold (all orientations route through the diagonal path) | `execute_fold()` → `execute_diagonal_fold()` |
| Validation before folding | `validate_fold()`, `validate_fold_with_player()` |
| **UNFOLD** (seam-click mechanic; independent, order-free) | `unfold_seam()`, `restore_removed_cells_for_fold()`, `reverse_shifts_for_fold()`, `merge_pieces_after_seam_removal()` |
| **UNDO** (full snapshot restore) | `undo_fold_by_id()` |
| Seam intersection check (blocks unfold / drives visuals; **not** used by undo) | `has_newer_seam_intersections()` |
| Geometry helpers | `calculate_cut_lines()`, `calculate_removed_cells()`, `serialize_grid_state()` |

> The UNFOLD vs UNDO distinction is a deliberate design decision — see
> [AGENTS.md](../AGENTS.md) §2a and [ARCHITECTURE.md](ARCHITECTURE.md) before
> changing either path.

### Player
| Concern | File |
|---|---|
| Grid-based movement, wall collision, goal/win detection, position updates during folds. Player uses **WORLD** coords. | `scripts/core/Player.gd` |

### Game state, history, audio
| Concern | File |
|---|---|
| Global game state / fold count (autoload singleton) | `scripts/core/GameManager.gd` |
| Sequential undo action stack | `scripts/systems/ActionHistory.gd` |
| SFX/music playback (autoload singleton) | `scripts/systems/AudioManager.gd` |

### Levels
| Concern | File |
|---|---|
| Level data resource + (de)serialization | `scripts/core/LevelData.gd` |
| Load/save levels, campaign flow | `scripts/systems/LevelManager.gd` |
| Level validation | `scripts/systems/LevelValidator.gd` |
| Campaign progression, stars, unlocking (save/load) | `scripts/systems/ProgressManager.gd` |
| In-game level editor | `scripts/core/LevelEditor.gd` |

### UI (`scripts/ui/`)
`MainMenu`, `HUD`, `PauseMenu`, `LevelComplete`, `LevelSelect`, `CustomLevelSelect`,
`Settings` — one script per screen; scenes live in `scenes/ui/`.

---

## Conventions that bite (read before editing)

These are enforced by the code, not optional style. Full rationale in
[ARCHITECTURE.md](ARCHITECTURE.md) and the pitfalls section of
[AGENTS.md](../AGENTS.md):

- **Cells/seams use LOCAL coordinates; the player uses WORLD.** Use
  `Vector2(grid_pos) * cell_size`, never `grid_to_world()`, for cell geometry.
- **Never compare floats with `==`** — use `GeometryCore.EPSILON`.
- **Free cells before overwriting them** in the `cells` dictionary (memory leak).
- **Don't mutate a collection while iterating it** — collect, then apply.

---

## Tests as living documentation

The test suite (`scripts/tests/`) is the most reliable behavioral spec. To see
how any subsystem is *meant* to behave, read its `test_*.gd`. See
[DEVELOPMENT.md](DEVELOPMENT.md) for how to run tests (including the macOS /
sandbox invocation).
