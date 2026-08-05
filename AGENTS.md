# Space Folding — AI Agent Guide

**START HERE.** Essential context for anyone (human or agent) working on this project.

**Last Updated:** 2026-08-05
**Engine:** Godot 4.3 · **Language:** GDScript · **Approach:** TDD

---

## What this game is

A **side-view gravity metroidvania** where the traversal verb is *folding space*.
You pin two anchors within arm's reach, and the space between them is excised — the
two halves slide together and meet. A pit closes. A wall you could not climb becomes
ground under your feet. A sealed chamber loses a corner to a diagonal crease.

Three things make it a metroidvania rather than a puzzle game:

- **Folds persist.** They are world state, not a move you undo. Regions keep their
  fold state when you leave them.
- **Folds are places.** The strip a fold excises is a real interior you can be
  pinched into, walk around in, fold *within*, and surface from somewhere else.
- **Progression is knowledge and configuration**, not keys. A door folded shut is a
  door you jammed; unfolding is the key you already had.

**Anchors are finite and conserved.** You carry a countable number of them, and a
fold standing in the world is holding two — so the budget is how many folds may
stand *at once*, not how many you may ever make. Unfolding refunds in full. This is
what makes "configuration" a real currency: you cannot take your bridge with you.
See §"The anchor economy".

---

## ⚠️ Read this first: the 2026-08-04 consolidation

The project used to be two games sharing one fold kernel — a top-down grid puzzler
and this. **The top-down build is gone.** If you find a doc, comment, or memory
referring to `GridManager`, `Cell`, `CellPiece`, `FoldController`, `FoldSystem`,
`FoldEngine`, `StepReplay`, `HistoryManager`, `LevelData`, `ProgressManager`,
`LevelEditor`, or a level campaign — that is pre-consolidation and no longer exists.

The pre-consolidation tree is tagged **`topdown-archive`** (commit `8bf8193`).
The tag is local-only — the remote refuses tag pushes from this session — so
`git checkout 8bf8193` is the reliable way back.

**Consequences worth knowing:**

- **There is no undo.** A continuous physics world has no discrete move to reverse.
  Unfold is the in-world inverse of fold; respawn handles mistakes. Do not
  reintroduce a step log without a design conversation.
- **There are no levels.** One world, many regions. `worlds/overworld.json`.
- **The player does not ride a tile.** It is a `CharacterBody2D` at a continuous
  position, transported through folds by exact base-frame mapping (`BaseFrame`).
  `Occupants` — the tile-riding model — is for world entities, not the player.

---

## Architecture in one page

**State = an immutable base grid + an ordered list of folds. Everything else is
DERIVED by replaying the folds from scratch.** There is no mutating fold system and
no snapshot; unfold is "drop the fold and re-derive."

```
worlds/overworld.json
        │
        ▼
   WorldData ──── build_base ────► BaseGrid (immutable, BaseTile per position)
                                        │
                        FoldReplay.derive_pieces(base, folds)
                                        │
                                        ▼
                          Array[FoldedPiece]  ← the fragment list
                          (base_id, type, polygon, plane_pos, src_offset)
                            │                          │
                   Polygon2D + colliders          BaseFrame
                     (FoldWorld view)        (exact point transport)
```

**The invariant everything rests on:** every fragment satisfies
`polygon == base_polygon + src_offset`. So a point in current space maps to base
space by subtracting its fragment's offset, and back into *any* other configuration
by finding the fragment with the same `base_id` containing it. That round trip is
what carries the player, entities, pinned anchors and door points through arbitrary
fold/unfold sequences — exactly, with no crease arithmetic.

**Fold semantics — MEET-IN-THE-MIDDLE:** a fold orders its two anchors
(`anchor_a` = lexicographic min by `(y,x)`), excises the strip strictly between
their creases, and slides BOTH outer flaps inward by integer half-shifts so the
halves meet at a common line. The seam sits at `anchor_a + shift_a_grid`.

---

## Layers — and the rule that keeps them apart

| Layer | Files | May depend on |
|---|---|---|
| **Kernel** (pure, headless) | `scripts/model/` + `scripts/utils/` | nothing above it |
| **World** (view, physics, input, rendering) | `scripts/world/` | kernel |
| **UI / systems** | `scripts/ui/`, `scripts/systems/` | kernel |

**The kernel must never reference the world.** This is why `BaseFrame` exists as
kernel rather than living in `WorldCore`: `TriggerResolver` needs point transport
during a pure derivation, and a model→view dependency would be a cycle. If you find
yourself wanting to import `WorldCore` from `scripts/model/`, extract the pure part
instead.

---

## Key files

| Concern | File |
|---|---|
| Immutable base grid / tiles | `scripts/model/BaseGrid.gd`, `BaseTile.gd` |
| One fold (anchors, creases, shifts) | `scripts/model/Fold.gd` |
| The derivation engine | `scripts/model/FoldReplay.gd` |
| Derived fragments / queryable state | `scripts/model/FoldedPiece.gd`, `FoldedState.gd` |
| **Base ↔ derived point transport** | `scripts/model/BaseFrame.gd` |
| What a tile IS and DOES (the registry) | `scripts/model/TileTypes.gd` |
| **The anchor ledger** (conservation arithmetic) | `scripts/model/AnchorStock.gd` |
| Entities that ride tiles through folds | `scripts/model/Occupants.gd` |
| Fold-on-enter cascade | `scripts/model/TriggerResolver.gd` |
| Authored world (regions, doors, folds) | `scripts/model/WorldData.gd` |
| Polygon clipping under folds | `scripts/utils/CollisionCore.gd` |
| Sutherland-Hodgman, epsilon, area | `scripts/utils/GeometryCore.gd` |
| Lights as occupants of the sheet | `scripts/model/LightSource.gd` |
| **The game**: regions, subspaces, doors, input | `scripts/world/FoldWorld.gd` |
| Pure world logic (maps, seams, depenetration) | `scripts/world/WorldCore.gd` |
| Player physics body | `scripts/world/PlayerBody.gd` |
| Anchors, previews, seam markers | `scripts/world/WorldOverlay.gd` |
| How big an art pixel is | `scripts/world/PixelArt.gd` |
| The tileset: kinds, variants, base-space UVs | `scripts/world/TileAtlas.gd` |
| Lit materials, light uniforms, lamp glyphs | `scripts/world/LightRig.gd` |
| The lighting shader | `assets/shaders/pixel_lit.gdshader` |

See `scripts/world/README.md` for controls and the design beats.

---

## Critical decisions — do not deviate without thought

### 1. Derive, never mutate
Fold state is `(BaseGrid, Array[Fold])`. To change the world, change the fold list
and re-derive. Never edit a `FoldedPiece` in place and expect it to persist.

### 2. The registry owns per-type behavior
`TileTypes` is the single authority for walkable / merge rank / `blocks_fold` /
`blocks_anchor` / `on_enter`. Adding a tile type should mean editing **one** file.
If you are about to write `if piece.type == TileTypes.WALL`, ask whether you want
`TileTypes.is_walkable(piece.type)` instead — almost always yes.

### 3. Transport by base frame, not by crease math
When something must survive a fold, map it through `BaseFrame`. Crease arithmetic
(`fold_shift_for_side`) is a fallback for points over void only — it is approximate
and does not compose across multiple folds.

### 4. Unfold blocking is uniform
A fold cannot be unfolded while a **newer** fold's excision band crosses its seam
segment. The same test against a fold's glue lines gates exiting a subspace. One
rule, applied at every level — world, strip, interior.

### 5. Never compare floats with `==`
Use `GeometryCore.EPSILON`.

### 6. The anchor ledger is derived, never stored
`AnchorStock` computes; it does not remember. Free anchors are
`capacity - held-by-live-folds - pinned-but-uncommitted`, with `held` summed from
`Fold.held_anchors` across every live fold list. That is why unfolding refunds with
no bookkeeping: the fold leaves the list and stops being counted. **Never add a
"spent anchors" counter** — it would be a second source of truth that can drift
from the fold list, which is the same mistake as caching derived fold state.

Capacity is the one accumulating part: authored start (`WorldData.anchor_capacity`)
plus every collected cache's grant. Player folds hold `COST_PER_FOLD`; folds the
*world* makes — authored pre-folds and trigger folds — hold zero.


### 7. Anything in the world is an occupant, resolved through `BaseFrame`
Doors and lights have no world position. They store a base identity plus a point
inside that tile, and where they *are* is a question asked of the current
fragment list. That is why a light folded away leaves the overworld and lights
the fold's interior instead — nobody wrote that; it falls out of asking. When you
add a new thing that lives in the world, store it that way. Do not cache a
world position and try to keep it up to date through folds.

---

## The anchor economy

| Where an anchor can be | How it gets there | How it comes back |
|---|---|---|
| Your pocket | start of the world; an anchor cache | — |
| A pending slot | tap F pointing at a cell (charged immediately) | hold F |
| A standing fold | committing tap (takes the two pending ones) | hold F at its seam |

**One key, two directions.** Tap = push an anchor in (pin, pin, commit). Hold =
pull one back out (your own anchor, the fold under a seam diamond, or a subspace's
glue diamond). The input mirrors the economy on purpose.

Consequences worth keeping in mind when designing:

- **Traversal is nearly free; configuration is not.** Fold a pit shut, walk across
  the seam, unfold behind you — you keep the anchors and you are across. What costs
  you is a fold you must *leave standing*: a wall folded away, a chamber you are
  inside, a door jammed shut.
- **There is no remote unfold** — `hold` requires you to be at the seam. This was a
  deliberate choice over a recall key, and it means **you can strand yourself**:
  last anchors spent, seam unreachable, `R` the only way out. `R` is built to be
  usable for that — it drops every fold (so every anchor comes back) and **keeps
  your collected caches**, because an escape hatch that confiscates what you found
  is a punishment for using it. It still costs you your position and your fold
  configuration; save points are the real answer and do not exist yet. Do not paper
  over any of this with a recall key without a design conversation.
- **A cache folded away is not lost.** It is inside the fold, and collecting it in
  there counts — `_check_caches` runs at world level and in subspaces alike.


---

## Rendering, in one page

The world is **pixel art**, and that is a rendering decision only — no physics
constant, cell size or coordinate changed. See `scripts/world/README.md`
§"Art & light" for the player-facing version.

```
world (unchanged: CELL = 64 world units)
        │
        ▼
  SubViewport, RESIZED per zoom  ← 1 art pixel = 4 world units = WORLD_PER_PIXEL
        │  320x180 at 1:1          the LENS never moves; the target grows instead
        ├── tiles: Polygon2D + tileset texture + base-space UVs (TileAtlas)
		│            uv = (polygon - src_offset) mapped into the tile's atlas cell
		└── lit by pixel_lit.gdshader (ambient + snapped, quantized, dithered lights)
		│
		▼
  TextureRect, nearest             HUD renders OUTSIDE this, at window resolution
```

Three rules worth keeping:

- **The camera's zoom is fixed; the render target resizes.** Inside a render
  target the size of an art pixel is purely a function of zoom, so moving the lens
  would resample the tileset and soften everything. The camera IS dynamic
  (`WorldCore.camera_zoom_for`) — that is a *logical* zoom, which sizes the target
  via `PixelArt.target_size`. Never set `_cam.zoom` from gameplay code.
- **Appearance is a base-space fact.** Variant, edge kind and UVs all come from
  the base grid, so a tile looks the same however it has been folded, ridden or
  cut. Do not key art off the folded neighbourhood.
- **The seam is a hard line.** The art is cut by the crease exactly as the
  geometry is, and nothing blends across it. Deliberate — do not soften it
  without a design conversation.
- **Lighting is style, not a mechanic.** Ambient stays high enough that unlit
  ground is navigable; the player and the overlay markers are drawn unlit so
  they never disappear into a dark corner.

---

## Open design questions

These are live, not settled. Do not close them silently in a refactor.

- **Fold extent is infinite-crease.** A fold here guts a structure over there. This
  is deliberately unresolved — it is the argument for barrier-scoped fold regions,
  and it needs to be *felt* before it is designed away.
- **No nested pinch.** You cannot fold yourself deeper while already inside a fold.
- **Triggers are world-level only.** A trigger inside a subspace would have to
  splice folds into an interior list mid-cascade; the resolver does not model that.
- **Unfold animation** plays only for newest-fold unfolds at world level; mid-stack
  unfolds are instant.
- **Anchor scarcity is not yet tuned.** The shipped allowance (4 = two standing
  folds) and the cache grant (2) are first guesses; the west beats were authored
  before anchors were finite. Whether scarcity makes the world feel considered or
  merely fussy is a playtesting question, not an editing one.
- **Cache collection is state outside `(base, folds)`** — `FoldWorld.collected_caches`,
  region id -> {base_id: grant}. It is PLAYER progression, not world state, which is
  why it lives outside `regions` and survives `_setup_all` (and therefore `R`). It is
  the first thing that will need the save system to outlive a session.
- **Lights do not cast shadows.** Occluders would have to be re-derived per fold,
  and they would want to soften the seam — which is the one thing the art is
  currently committed to keeping hard.

---

## Testing

```bash
HOME=/tmp/godot-home ./run_tests.sh            # all
HOME=/tmp/godot-home ./run_tests.sh world      # partial filename match
```

`run_tests.sh` prefers the bundled `tools/godot/godot`, which is **gzipped and
Linux x86-64** (`tools/godot/godot.gz`); the script falls back to a system `godot`
on PATH. If Godot's config dir is sandboxed, redirect `HOME` as above. After adding
or renaming a `class_name`, run `godot --headless --import` once so the global class
registry picks it up, or you will get spurious "Identifier not declared" errors.

**Write the test first.** The suite is the behavioral spec — when you want to know
how something behaves, read its `test_*.gd` before reading the implementation.

See `STATUS.md` for the current suite size.

---

## Git workflow

Work on `claude/*` feature branches; PRs merge into `main`.

---

## The five things that matter most

1. **Read `STATUS.md`** — what is done and what is next.
2. **State is `(base, folds)`; everything else is derived** — including the anchor
   ledger. Re-derive, don't mutate.
3. **`BaseFrame` is how anything survives a fold.** Not crease math.
4. **Ask `TileTypes`, don't switch on type ints.**
5. **Write the test first** — the suite is the spec.
