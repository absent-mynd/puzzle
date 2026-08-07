# Space Folding — AI Agent Guide

**START HERE.** Essential context for anyone (human or agent) working on this project.

**Last Updated:** 2026-08-06
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

**You fold with HANDS, and you have two.** A hand is an object you carry, not an
ability you have; a fold standing in the world is holding the two hands you pinned it
with, and unfolding gives those same two back. Two slots, never more — so the budget
is how many folds may stand *at once*, and that is one until you find another hand.
This is what makes "configuration" a real currency: you cannot take your bridge with
you. See §"The hand economy".

---

## ⚠️ Read this first: the 2026-08-04 consolidation

The project used to be two games sharing one fold kernel — a top-down grid puzzler
and this. **The top-down build is gone.** If you find a doc, comment, or memory
referring to `GridManager`, `Cell`, `CellPiece`, `FoldController`, `FoldSystem`,
`FoldEngine`, `StepReplay`, `HistoryManager`, `LevelData`, `ProgressManager`,
`LevelEditor`, or a level campaign — that is pre-consolidation and no longer exists.

(The editor that exists NOW is `WorldEditor` — `scripts/editor/`, added
2026-08-06. Different thing, different name on purpose: there are no levels to
edit. See `docs/features/WORLD_EDITOR.md`.)

The pre-consolidation tree is tagged **`topdown-archive`** (commit `8bf8193`).
The tag is local-only — the remote refuses tag pushes from this session — so
`git checkout 8bf8193` is the reliable way back.

**Consequences worth knowing:**

- **There is no undo.** A continuous physics world has no discrete move to reverse.
  Unfold is the in-world inverse of fold; respawn handles mistakes. Do not
  reintroduce a step log without a design conversation. (The world EDITOR has undo,
  and that is not a contradiction: it edits a file, not play state. `EditorDoc`
  snapshots `WorldData`; the two stacks never meet.)
- **There are no levels.** One world, many regions. `worlds/overworld.json` — plus
  `worlds/testbed.json`, a DEBUG world of one-of-everything that you boot with
  `--world=testbed` (see `docs/features/TESTBED_WORLD.md`). Never balance or design
  against the testbed; it exists to make a mechanic reachable in thirty seconds.
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
| **How a space repeats** (cylinder / torus) | `scripts/model/FoldLattice.gd` |
| What a tile IS and DOES (the registry) | `scripts/model/TileTypes.gd` |
| What a tile's per-instance params MEAN | `scripts/model/TileParams.gd` |
| **The hand registry** (one file per kind) | `scripts/model/HandTypes.gd` |
| A hand lying in the world (an occupant) | `scripts/model/HandPickup.gd` |
| **The slot ledger** (conservation arithmetic) | `scripts/model/AnchorStock.gd` |
| Entities that ride tiles through folds | `scripts/model/Occupants.gd` |
| Fold-on-enter cascade | `scripts/model/TriggerResolver.gd` |
| Authored world (regions, doors, folds) | `scripts/model/WorldData.gd` |
| Polygon clipping under folds | `scripts/utils/CollisionCore.gd` |
| Sutherland-Hodgman, epsilon, area | `scripts/utils/GeometryCore.gd` |
| Lights as occupants of the sheet | `scripts/model/LightSource.gd` |
| **The game**: regions, subspaces, doors, input | `scripts/world/FoldWorld.gd` |
| Pure world logic (maps, seams, depenetration) | `scripts/world/WorldCore.gd` |
| Player physics body | `scripts/world/PlayerBody.gd` |
| Anchors, previews, seam markers, the fuse pulse | `scripts/world/WorldOverlay.gd` |
| The hands that float beside you (style only) | `scripts/world/HandOrbit.gd` |
| **A canvas that repeats with the space** | `scripts/world/WrapCanvas.gd` |
| The sheet, batched into two canvas items | `scripts/world/TileBatch.gd` |
| The blob, drawn wherever the space says it is | `scripts/world/PlayerVisual.gd` |
| How big an art pixel is | `scripts/world/PixelArt.gd` |
| The tileset: kinds, variants, base-space UVs | `scripts/world/TileAtlas.gd` |
| Lit materials, light uniforms, lamp glyphs | `scripts/world/LightRig.gd` |
| The lighting shader | `assets/shaders/pixel_lit.gdshader` |
| **The sound registry** (vocabulary + the whole mix) | `scripts/systems/Sounds.gd` |
| Buses, voices, fades, volume persistence | `scripts/systems/AudioManager.gd` (autoload) |
| **The world editor**: every mutation + undo | `scripts/editor/EditorDoc.gd` |
| Editor: palette, raster ops, fold guides (pure) | `scripts/editor/EditorTools.gd` |
| Editor: the board, the cards, the overlays | `scripts/editor/EditorBoard.gd` |
| Editor: mouse, camera, tools | `scripts/editor/WorldEditor.gd` |

See `scripts/world/README.md` for controls and the design beats, and
`docs/features/WORLD_EDITOR.md` for the editor (`./run_editor.sh`).

---

## Critical decisions — do not deviate without thought

### 1. Derive, never mutate
Fold state is `(BaseGrid, Array[Fold])`. To change the world, change the fold list
and re-derive. Never edit a `FoldedPiece` in place and expect it to persist.

### 2. The registry owns per-type behavior
`TileTypes` is the single authority for walkable / merge rank / `blocks_fold` /
`blocks_anchor` / `on_enter` / `name` / `params`. Adding a tile type should mean
editing **one** file. If you are about to write `if piece.type == TileTypes.WALL`,
ask whether you want `TileTypes.is_walkable(piece.type)` instead — almost always yes.

`params` extends that rule to a tile's PER-INSTANCE data (`tile_data`): the
registry declares each parameter's key, value type, default and label, and
`TileParams` says what those declarations mean. The editor's tile inspector is
generated from them and names no tile type, so declaring a parameter is the whole
job — it becomes editable, validated, drawn on the board and saved with nothing
else touched. Do not add a bespoke editor panel for a new parameter; add a row to
the schema. See `docs/features/WORLD_EDITOR.md` §"Per-tile parameters".

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

### 6. The hand ledger is derived, never stored
`AnchorStock` computes; it does not remember. A hand is only ever in one of three
places — your slots (`FoldWorld.hands`), pinned but uncommitted (the two pending
anchors), or held by a standing fold (`Fold.held_hands`) — and every number is summed
from where the hands actually are. That is why unfolding gives them back with no
bookkeeping: the fold leaves the list and stops being counted. **Never add a "hands
spent" counter** — it would be a second source of truth that can drift from the fold
list, which is the same mistake as caching derived fold state.

A fold stores the KINDS it took, not just how many, because unfolding has to return
the same two hands that went in. Player folds hold two; folds the *world* makes —
authored pre-folds and trigger folds — hold none.

`_hands_for_fold` is the one place hands leave your slots, and it must be called
**late**, at the point of no return: a fold refused for a pin in its span must not
have cost you the hands it never took.

### 7. A fold in flight owns the frame
`_play_transition` freezes the body at where it started and does not rebuild the
geometry until it finalizes, so for the length of a fold animation BOTH the player's
position and the fragment list are halfway between two states. Anything that reads
either one during that window is reading a world that does not exist.

`_physics_process` therefore returns the moment `_tick_fuse` starts a transition. It
is not enough to check `animating()` at the top: the fuse fires from inside the frame,
and the checks below it used to run anyway. That let a door fire while the player was
still standing where the fold had not yet moved them from — warping them to another
region, whereupon the fold's finalize applied a landing position computed in the
region they had just left. Stuck in a wall, or off the map.

If you add anything to that tail, ask whether it can start a transition; if it can,
the same guard has to follow it.

### 8. One space is on screen, and `FoldLattice` says how it repeats
There is no world path and subspace path. There is the **current level** — the
region is simply the level whose `context` is empty — and one set of everything
derived from it. `FoldLattice` is the whole of what "this space repeats" means:
no periods in a region, one inside a fold, **two inside a fold whose creases run
across the fold outside it**, which is a torus. Copies, colliders, the body's
wrap-around, the camera's framing and the lights all come off that one object.

This is why folding yourself deeper needed no new rendering, and why `do_fold`
handles a pinch at depth three the same way it handles one at the surface.

### 9. The wrap is not each object's problem
Two mechanisms, and the rule between them is short:

> **Anything that MOVES repeats through `WrapCanvas`. Anything STATIC bakes its
> copies at rebuild (`TileBatch`).**

`WrapCanvas` subclasses override `paint()` and draw in ordinary world
coordinates; the base class repeats those commands at every lattice offset. Put
a new thing in the world and it appears in every band without being asked.
Before this there were four separate repeat loops — terrain copies, a player
ghost list, light offsets, the overlay's `_copy_offsets` — and `HandOrbit`, the
newest object, had none, so the hands you carry vanished from every copy but
one. **If you add a drawer and find yourself writing a loop over copies, you
have written the bug this replaced.**

Register new canvases in `FoldWorld._wrap_canvases()` — one list, so forgetting
is visible.

### 10. Anything in the world is an occupant, resolved through `BaseFrame`
Doors and lights have no world position. They store a base identity plus a point
inside that tile, and where they *are* is a question asked of the current
fragment list. That is why a light folded away leaves the overworld and lights
the fold's interior instead — nobody wrote that; it falls out of asking. When you
add a new thing that lives in the world, store it that way. Do not cache a
world position and try to keep it up to date through folds.

### 9. Audio is a leaf, and `Sounds` is its registry
`AudioManager.play_sfx(...)` is a statement, never a question: nothing reads back
from audio and no gameplay decision may depend on it, which is what lets a call
site be one line in the middle of world logic. The game is fully playable silent.

`Sounds` owns the vocabulary AND the mix — a sound's id is its asset's basename,
and its dB trim, pitch jitter and retrigger floor all live in that one registry.
So adding a sound means editing `Sounds.gd` and dropping a file, and **balancing
the game is a diff** rather than a re-render. `test_audio_manager` asserts the
registry and the shipped assets are the same set in both directions.

Do not scatter volume constants at call sites, and do not add a throttle at one:
the floor that keeps per-frame events from emptying the voice pool is a registry
field precisely so it is solved once. See `docs/features/AUDIO.md`.

---

## The hand economy

| Where a hand can be | How it gets there | How it comes back |
|---|---|---|
| One of your two slots | the world's `starting_hands`; walking over a loose hand | — |
| Pinned as an anchor | tap F pointing at a cell (leaves the slot at once) | a burst in reach |
| Pinned in an ARMED pair | pairing with a reachable unpaired anchor | a burst reaching either half |
| Held by a standing fold | the fuse going off | a burst at its seam |
| Lying on the ground | authored by the world; overflow from a burst; a fold that failed at the fuse | walk over it |

**One key, two directions.** Tap puts a hand down; hold fires a **release burst**.
There is no committing press — the second hand lights a **fuse** and the pair folds
itself. The input mirrors the economy on purpose.

Those four places always sum to the same number. **Nothing in the game creates or
destroys a hand** — placing, committing, unfolding, bursting and picking up all just
move one — which is what `AnchorStock.total` states and `test_anchor_stock` pins.

Consequences worth keeping in mind when designing:

- **Two slots, and that never grows.** A cache does not raise a capacity; it hands
  you *another hand* for a slot you emptied by placing one. So a cache is the second
  half of a fold already in progress, and the natural way to use one is to finish a
  fold with a kind you did not set out with.
- **Traversal is nearly free; configuration is not.** Fold a pit shut, walk across
  the seam, unfold behind you — you keep the hands and you are across. What costs you
  is a fold you must *leave standing*.
- **Nothing is ever refused for want of room.** A fold returns both hands at once,
  and a hand with nowhere to go lands on the ground as a `HandPickup` — the same
  object an authored cache is. That one clause is what lets the burst be fired blind
  and is why no code path has to ask "is there a slot" first.
- **The burst is not aimed.** `hold_action` takes no direction: where you stand is
  the whole input, and it releases what was releasable when it fired rather than
  cascading. Do not give it a target without a design conversation — the untargeted
  reading is what makes it read as a thing you *do*, not a thing you *point*.
- **Fold validity is asked at the FUSE, not at placement.** `place_hand` checks
  only that there is sheet to pin to (which is storage, not a rule — an anchor is a
  base identity, and void has none). Everything else — the degenerate pair, the
  surface rules, the span, somewhere to land — is `fire_pair`'s question. That
  is what makes the fuse a *window*: you can put both hands down from a spot the fold
  could not put you and run clear before it fires. Moving a check back to placement
  would close that window, so do not.
- **A failed fold scatters rather than refunds.** `_scatter_pair` drops both hands
  from where they were pinned, converting each anchor straight into a `HandPickup` —
  they are already stored as the same thing. Returning them to your slots would make a
  mistimed fold free.
- **A loose hand is a BALL while it is in flight, and an occupant once it stops.** That
  boundary is the whole design, and it is what lets a hand behave physically without
  breaking §8.

  A hand let go of anywhere becomes an entry in `FoldWorld.hand_balls` — light, high-drag,
  simulated by `WorldCore.hand_ball_step`: it floats down rather than dropping, rolls off
  slopes, ejects out of walls, and comes to rest. `_land_ball` then converts it back into
  a `HandPickup`, and from that moment it has no position of its own again. Every path
  that lets a hand go goes through `_drop_hand`/`_toss_hand`, so there is one answer to
  "what happens when you drop a hand" everywhere.

  **A ball is the one thing in the world that holds a live position, and it is
  deliberately transient.** §8 forbids caching one on anything that persists, because the
  fragment list is the only authority on where things are. A ball holds one for a second
  or two and nothing outlives that. While flying it is still transported like everything
  else: `_carry_balls_through` maps it through `BaseFrame` exactly as the player is, so a
  fold carries a hand in flight — and a hand the fold sweeps into a strip goes on flying
  *inside* the strip, velocity intact, because a fold is a translation and the step is
  position-independent.

  **Conservation holds mid-flight.** `hands_loose()` counts balls, so a falling hand is
  never momentarily destroyed and re-created on landing. A ball is also catchable in the
  air (`_check_pickups`).

  **A strip is a cylinder, so a falling thing wraps** (`WorldCore.wrap_into_strip`, the
  same rule the player crosses the glue by, as a modulo because a falling object can cross
  more than one band in a frame). When the wrap axis has a vertical component a hand
  **orbits indefinitely** — that is a real object in a closed space, not a leak: still
  counted, still catchable, and it lands the moment a fold puts ground in its way. Only
  the tangential ends are open, and a ball leaving one is returned to the player's feet.

  **A resting hand wakes if a fold takes its ground away** (`_wake_unsupported_hands`,
  called from every fold/unfold finalize). A fold that merely *moves* its tile carries it
  and it stays put, like a door. The cost, chosen deliberately: a cache can move without
  you touching it.

  **`_take_back` must run AFTER the rebuild and the teleport.** A hand a fold cannot give
  you is a hand it DROPS, and a hand is dropped at the player's position in the current
  geometry — so returning hands before the unfold has moved the player launches the
  overflow one from a stale position into the old fragment list. It was the reported
  "one hand vanishes on unfold" bug, and `hands_total` was correct throughout, which is
  why no conservation test caught it: the hand existed, it was just cells away from where
  you ended up. Same trap on the subspace-exit path, worse — the ball was tagged
  `in_sub` in a world that no longer had a subspace, so it could never be stepped, drawn
  or reached. Pinned by the regression block in `test_fold_world`.

  **`_land_ball` may never give up on a hand.** It used to warn and return when no sheet
  was within two cells, which was the one code path in the game that could actually
  destroy one — silent, because a `push_warning` is not a failing test. It now falls back
  to the spawn tile, and failing that keeps the hand airborne. Relatedly, a hand that
  falls out of the world is recovered by `_recover_lost_hand`, which lands it as a pickup
  rather than re-dropping a ball at the player: a player standing over a pit would
  otherwise have the recovered hand fall off again and loop forever, counted but never
  findable.

  Two consequences worth knowing before you change any of it: a refused fold no longer
  leaves its hands on the cells you chose (the shape of the attempt is no longer legible —
  traded for "a hand is always somewhere you can see and walk to"), and authored hands are
  **settled at load** (`_settle_authored`) because authoring names a cell, which puts a
  hand at that tile's centre — half a cell in the air. Without settling, the first fold
  near a cache would drop it, since it was never really on the ground.
- **There is no fixed number of placed anchors.** `unpaired` holds hands waiting for
  a partner and `primed` holds pairs, each with its OWN fuse. Two fixed registers is
  what wedged the game: a hand left in another region sat in one forever, so every
  pair formed afterwards contained an unreachable partner and never fired. Do not
  reintroduce a bound here — the bound is how many hands you are carrying.
- **A hand pairs with the last unpaired anchor you can SEE.** Not merely the last one
  placed: an anchor in another region or sealed in a fold is not a partner a fold
  could be finished with, so pairing with it would spend a hand on a fold that can
  never fire.
- **Anchors carry their region, and resolution checks it.** Base ids are per-region
  and DO overlap, so without that check a west anchor can quietly resolve onto
  whatever east tile shares its id.
- **There is no minimum anchor distance.** A one-cell fold is a fold. The only
  impossible pair is two anchors on one cell, which has no crease direction at all.
- **A kind only changes the fuse.** Colour is identity, `HandTypes.fuse` is the whole
  of the behaviour, and a mixed pair fuses at the MEAN of its two. If you give kinds a
  second behaviour, that is a design change; do it in `HandTypes` and nowhere else.
- **There is no remote unfold** — `hold` requires you to be at the seam. It means
  **you can strand yourself**: both hands in a fold, seam unreachable, and short of a
  cache, `R` the only way out. `R` drops every fold and restores your starting pair,
  which is exactly why caches respawn with it: hands are what a reset gives back, so
  leaving the caches spent would strand you *shorter* than you began. Save points are
  the real answer and do not exist yet. Do not paper over any of this with a recall
  key without a design conversation.
- **The floating hands are style.** `HandOrbit` springs them beside the body, adds a
  passive drift so no hand is ever perfectly still (carried or loose — both draw
  through `draw_hand`), and nothing reads their positions back. In particular
  `_check_pickups` measures from where a hand *is*, not where it is drawn, which is
  why `WorldCore.DRIFT_RADIUS` is a fraction of the pickup range. Do not make these
  positions load-bearing without saying so.

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
        │
        ├── TileBatch   the sheet: ALL fragments of ALL copies in two Polygon2Ds
        │                 (one per lit material), base-space UVs from TileAtlas,
        │                 the wrap baked into the vertices
        ├── StaticBody2D  colliders, domain + the copies one step out
        └── WrapCanvas×n  everything that moves — the blob, the hands you carry,
                          the hands in flight, the markers — each painted once
                          per lattice offset
        │
        ▼
  TextureRect, nearest             HUD renders OUTSIDE this, at window resolution
```

**Cost.** The sheet is two canvas items whatever the region size and however many
copies a wrap draws; a fold transition is three batches, and two of the three move
by setting a position. What this replaced built one `Polygon2D` per fragment per
copy — ~800 for a region, ×49 inside a fold — and tore the whole lot down on every
single fold.

Four rules worth keeping:

- **The wrap belongs to the space, not to the objects in it.** See §9 above.

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
- **How deep nesting should go before it stops being legible** is untested by play.
  It works to arbitrary depth and the tint deepens with each layer, but three folds
  in is a claim about the game, not just about the code.
- **A torus has no turn-back.** Fold yourself in across the grain and the space has
  no ends at all — every direction wraps. Whether that reads as elegant or as being
  lost is a playtesting question.
- **A fold does not reach around the cylinder.** Fold across the glue you came in
  through and the band finds the end of the stored sheet rather than the next copy
  of it. That is a design choice, not a geometric necessity — the alternative (cut
  the strip out of the parent's full orbit) was implemented and reverted. What it
  costs is that a band past the glue is emptier than the space it sits in; what it
  buys is that the glue line means something.
- **Triggers are world-level only.** A trigger inside a subspace would have to
  splice folds into an interior list mid-cascade; the resolver does not model that.
- **Unfold animation** plays only for newest-fold unfolds at world level; mid-stack
  unfolds are instant.
- **Jump feel is a first guess, but jump HEIGHT is level design.** How long you hold
  Space sets the height, from a ~1.25-cell tap to a ~2.6-cell full hold. The curve
  itself wants playtesting; the two bounds around it do not — the pinned pillar is
  two tiles because it is meant to be jumped and the plate's wall is three because
  it is meant to need a fold. `PlayerBody.jump_height_for_hold` integrates the real
  step and `test_player_body` asserts both bounds, so tune the gravity constants by
  all means and let that test tell you when you have moved the world.
- **Hand scarcity and the fuse lengths are not yet tuned.** Two slots, and fuses of
  0.65 / 1.6 / 3.2 seconds, are first guesses; the west beats were authored when
  folding was free and instant. Whether the fuse reads as deliberate pacing or as the
  game taking the decision away from you is a playtesting question.
- **A kind changes only the fuse.** Whether that is enough to make picking up a
  colour feel like a choice, or whether kinds want a second axis, is open.
- **Loose hands are state outside `(base, folds)`** — `FoldWorld.hand_pickups`,
  region id -> Array[HandPickup]. It lives outside `regions` so a region rebuild
  cannot silently clear it, and `_setup_all` rebuilds it from the authored world. It
  is the first thing that will need the save system to outlive a session.
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
