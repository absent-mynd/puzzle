# Space Folding — AI Agent Guide

**START HERE.** The context you need before touching anything.

**Engine:** Godot 4.7 · **Language:** GDScript · **Approach:** TDD

---

## What this game is

A **side-view gravity metroidvania** where the traversal verb is *folding space*.
You pin two anchors within arm's reach, and the space between them is excised — the
two halves slide together and meet. A pit closes. A wall you could not climb becomes
ground under your feet.

Three things make it a metroidvania rather than a puzzle game:

- **Folds persist.** They are world state, not a move you undo. Regions keep their
  fold state when you leave them.
- **Folds are places.** The strip a fold excises is a real place you can be pinched
  into, walk around in, fold *within*, and surface from somewhere else.
- **Progression is knowledge and configuration**, not keys. A door folded shut is a
  door you jammed; unfolding is the key you already had.

**You fold with HANDS, and you have two.** A hand is an object you carry, not an
ability you have; a fold standing in the world is holding the hands that were spent on
it, and unfolding gives those same ones back. Two slots, never more — so the budget is
how many folds may stand *at once*. See §"The hand economy".

**Two anchors fold together when they can REACH each other.** A hand pinned alone
stands there indefinitely; how far it reaches for a partner is its kind's `span`. So
hands placed around the world are a plan you lay out, and a fold happens where the
plan closes.

---

## ⚠️ Read this first: the 2026-08-04 consolidation

The project used to be two games sharing one fold kernel — a top-down grid puzzler
and this. **The top-down build is gone.** If you find a doc, comment, or memory
referring to `GridManager`, `Cell`, `CellPiece`, `FoldController`, `FoldSystem`,
`FoldEngine`, `StepReplay`, `HistoryManager`, `LevelData`, `ProgressManager`,
`LevelEditor`, or a level campaign — that is pre-consolidation and no longer exists.
The pre-consolidation tree is `git checkout 8bf8193`.

**Consequences worth knowing:**

- **There is no undo.** A continuous physics world has no discrete move to reverse.
  Unfold is the in-world inverse of fold; respawn handles mistakes. Do not
  reintroduce a step log without a design conversation. (The world EDITOR has undo,
  and that is not a contradiction: it edits a file, not play state.)
- **There is no level campaign.** One world, many regions — `worlds/overworld.json`,
  plus `worlds/testbed.json`, a DEBUG world of one-of-everything you boot with
  `--world=testbed`. Never balance or design against the testbed.
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
                          Array[FoldedPiece]  ← the piece list
                          (base_id, type, polygon, plane_pos, src_offset)
                            │                          │
                   Polygon2D + colliders          BaseFrame
                     (FoldWorld view)        (exact point transport)
```

**The invariant everything rests on:** every piece satisfies
`polygon == base_polygon + src_offset`. So a point in current space maps to base
space by subtracting its piece's offset, and back into *any* other configuration
by finding the piece with the same `base_id` containing it. That round trip is
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

**The kernel must never reference the world**, and `scripts/tests/test_layering.gd`
fails the build if it does. When you find yourself wanting to reach upward, check
whether the thing you are reaching for is actually pure. Usually it is, and it is
simply in the wrong directory — that was the whole of the one violation this rule
ever had. **Move it down; do not relax the rule.**

---

## Where things are written down

| What you want | Where |
|---|---|
| What a file is responsible for | [docs/REFERENCE.md](docs/REFERENCE.md) |
| Why it is shaped this way, and what was rejected | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| What a thing is called | [docs/GLOSSARY.md](docs/GLOSSARY.md) |
| How to run, test and debug | [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) |
| What is done, broken, and next | [STATUS.md](STATUS.md) |
| Controls and the design beats | [scripts/world/README.md](scripts/world/README.md) |
| How something behaves | its `scripts/tests/test_*.gd` |
| What changed and why | `git log` |

### The rules that keep it that way

Docs rot; code, tests and `git log` do not. So **every fact has exactly one home,
and it is the one that cannot go stale.**

1. **Write a fact once.** To state it in a second place, link instead. Every
   duplicate this project has had went stale on one side — a changelog in
   `STATUS.md`, a key-files list in this file, a per-script test-count table, a
   limits list that reached three copies before anyone noticed they disagreed. (A
   one-line command like `./run_tests.sh` is not a fact worth linking for; an
   explanation of it is.)
2. **Put the reason next to the thing.** A trap in `_land_ball` belongs in
   `_land_ball`'s docstring, where someone editing it will see it — not in a
   narrative page they would have to already know to open.
3. **No hand-maintained numbers.** Test counts, file counts, timings: whatever
   produces them is the authority. If a number must hold, assert it in a test.
4. **Delete a point-in-time document when its moment passes.** Reviews, audits,
   migration plans. Act on it, then delete it; `git log` keeps it.
5. **Prefer deleting to updating.** If a paragraph is wrong, ask what is lost by
   removing it. Usually nothing: a shorter true document beats a longer one with a
   stale paragraph in it.

**Adding a doc is a decision, not a courtesy.** A new `.md` needs a fact no existing
home can hold. Otherwise it is a page nobody finds and nobody updates.

---

## Critical decisions — do not deviate without thought

Argued in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), with the alternatives that
were rejected and why:

| Rule | Argued in |
|---|---|
| Derive, never mutate — change the fold list and re-derive | Decision 1 |
| Transport by `BaseFrame`, not crease arithmetic | Decision 2 |
| `TileTypes` is the only authority on what a tile does | Decision 5 |
| Which anchors are a pair is DERIVED; only the fuse is stored | Decision 11 |
| Unfold blocking is one rule at every depth | Decision 6 |
| Never compare floats with `==`; use `GeometryCore.EPSILON` | Decision 8 |
| The kernel never sees the world — enforced by `test_layering.gd` | Decision 9 |
| Anything in the world is an occupant, resolved through `BaseFrame` | Decision 10 |

What follows is the part that is only here.

### 1. A tile's per-instance params are registry rows too

`params` extends the registry rule to a tile's PER-INSTANCE data (`tile_data`): the
registry declares each parameter's key, type, default and label, and `TileParams`
says what those declarations mean. The editor's tile inspector is generated from
them and names no tile type, so declaring a parameter is the whole job. Do not add a
bespoke editor panel for a new parameter; add a row to the schema.

### 2. The hand ledger is derived, never stored — and so is the pairing

`HandStock` computes; it does not remember. Every number is summed from where the
hands actually are, which is why unfolding gives them back with no bookkeeping — the
fold leaves the list and stops being counted. **Never add a "hands spent" counter**;
it would be a second source of truth that can drift from the fold list.

A fold stores the KINDS it took, not just how many, because unfolding has to return
the same hands that went in. It may hold two, one or none: what it holds is what was
actually spent on it, and the world's own anchors cost nothing.

`_hands_for_fold` is the one place hands leave your slots, and it must be called
**late**, at the point of no return: a fold refused for a pin in its span must not
have cost you the hands it never took.

**`AnchorField` is the same rule one level up.** There is one list of anchors, and
which two of them are a pair is recomputed from where they are — never stored. The
only thing kept is each pair's countdown, because time cannot be derived. If you find
yourself adding a field that remembers a relationship between two anchors, that is the
`unpaired`/`armed` pair of lists coming back; see ARCHITECTURE Decision 11.

### 3. A fold in flight owns the frame

`_play_transition` freezes the body where it started and does not rebuild the
geometry until it finalizes, so for the length of a fold animation BOTH the player's
position and the piece list are halfway between two states. Anything that reads
either one during that window is reading a world that does not exist.

`_physics_process` therefore returns the moment `_tick_fuse` starts a transition. It
is not enough to check `animating()` at the top: the fuse fires from inside the
frame, and the checks below it used to run anyway — which let a door fire while the
player still stood where the fold had not yet moved them from. **If you add anything
to that tail, ask whether it can start a transition; if it can, the same guard has
to follow it.**

### 4. One space is on screen, and `FoldLattice` says how it repeats

There is no world path and subspace path. There is the **current space** (`Space`) —
the region is simply the space whose `context` is empty — and one set of everything
derived from it. `FoldLattice` is the whole of what "this space repeats" means: no
periods in a region, one inside a fold, **two inside a fold whose creases run across
the fold outside it**, which is a torus. Copies, colliders, the body's wrap-around,
the camera's framing and the lights all come off that one object.

This is why folding yourself deeper needed no new rendering.

### 5. The wrap is not each object's problem

> **Anything that MOVES repeats through `WrapCanvas`. Anything STATIC bakes its
> copies at rebuild (`TileBatch`).**

`WrapCanvas` subclasses override `paint()` and draw in ordinary world coordinates;
the base class repeats those commands at every lattice offset. **If you add a drawer
and find yourself writing a loop over copies, you have written the bug this
replaced.** Register new canvases in `FoldWorld._wrap_canvases()` — one list, so
forgetting is visible.

The corollary, which cost a bug: **a canvas that remembers a position between frames
has to be carried through a wrap.** `WrapCanvas.carry_through_wrap` offers the
displacement to every canvas; keep no state and you inherit the no-op.

### 6. Audio is a leaf, and `Sounds` is its registry

`AudioManager.play_sfx(...)` is a statement, never a question: nothing reads back
from audio and no gameplay decision may depend on it. The game is fully playable
silent.

`Sounds` owns the vocabulary AND the mix — a sound's id is its asset's basename, and
its dB trim, pitch jitter and retrigger floor all live in that one registry, so
**balancing the game is a diff**. Do not scatter volume constants at call sites, and
do not add a throttle at one.

### 7. Placing a hand stops the clock, and stopping it is a NON-EVENT

Placing is two taps: the first raises the hand into a cursor over the nine cells of
arm's reach, the second pins it. Between them `_physics_process` returns early and
the body is `frozen` — see `FoldWorld.placing()`.

**The freeze is implemented by not running, and it must stay that way.** Nothing is
saved, snapshotted or restored: the fuses are not paused-and-resumed, the balls are
not parked, the velocity is not stashed. They are simply not stepped, which is why
resuming is exact rather than approximately exact, and why no future addition to the
frame has to remember to opt in. **If you find yourself writing "save X on freeze,
restore X on resume", the guard is in the wrong place** — move it up so X is never
stepped at all. This is the same argument as §2 and Decision 1: a second copy of a
value is a second thing that can be wrong.

`_process` deliberately keeps running. The camera has to go on easing onto the cell
being chosen, and the hold that cancels the placement has to keep counting; neither
moves the world. If you add something to `_process` that DOES move the world, it
needs the guard that `_physics_process` has.

Two consequences worth keeping:

- **Raising a hand spends nothing.** It leaves its slot at the pin, not at the
  raise, so a cancelled placement costs exactly nothing and conservation never sees
  a hand in a fourth state. Do not make `begin_aim` take it out of the slot early.
- **Reach is a square, and its radius is level design.** `WorldCore.within_arm_reach`
  is a box of `ARM_REACH` cells around your own, diagonals and your own feet
  included. A one-tile shell keeps you out of what it encloses only because that
  radius is 1 (the sealed chamber is exactly that shell), so raising it is a design
  conversation, not tuning.
- **The stop reaches the DECORATIONS, through one clock.** `WorldClock` is world
  time: `FoldWorld._process` advances it only while the world runs, and everything
  that drifts, throbs or flickers without being pushed reads it — the hands' idle
  float, the fuse throb, the lamp flicker, the burst ring. It exists because there
  were three clocks (two direct `Time.get_ticks_msec()` reads and `LightRig`'s own
  accumulator) and all three kept running through a pause that had stopped everything
  else, which reads as a paused game rather than as held time. **Anything new that
  animates in the world reads `WorldClock`**, and `test_world_clock` fails the build
  if it reads the wall clock instead. Wall time stays right for what is NOT in the
  world: the input charge, the HUD's flash, and the held-look ease — all three are
  about the pause rather than in it.
- **`PlayerBody.frozen` means "do not step me" and nothing else.** It is set for two
  unrelated reasons now, and they want opposite framings: a fold ride leaves the
  velocity stale and the lens should read it as still, while a raised hand leaves it
  exactly intact and the lens must go on reading it — or the frame eases shut over the
  second you spend aiming and blooms open again when you pin. So *which* is happening
  is `WorldCamera`'s call, off the `frozen` fact the world passes it, and
  `motion_intensity` is a plain statement about velocity. Do not put a mode check back
  into the body.
- **The LENS stops too, and it is a separate flag.** `PlayerBody.camera_held` freezes
  the follow, the lead and the zoom where they are — mid-lag, wherever the moment
  caught them. It cannot be `frozen`: that is also set by a fold ride, and there the
  camera keeping up IS its job. The two flags mean "the body is not stepped" and "the
  view is not stepped", and only one of them is about time having stopped. A
  consequence worth knowing before adding a focus point: while the lens is held it
  cannot act on one, so a point that only exists during a placement does nothing —
  which is why the cursor's cell is not in `_camera_focus`.

---

## The hand economy

| Where a hand can be | How it gets there | How it comes back |
|---|---|---|
| One of your two slots | the world's `starting_hands`; walking over a loose hand | — |
| Pinned as an anchor | tap F to raise it, walk the cursor, tap F to pin (leaves the slot at the pin, not the raise) | a burst in reach |
| Held by a standing fold | the fuse of a pair going off | a burst at its seam |
| Lying on the ground | authored; overflow from a burst; a fold that failed at the fuse | walk over it |

There is no fifth place. "In an armed pair" is not one: a pair is two anchors that can
reach each other, asked afresh every frame, so being in one is something an anchor
*is*, not somewhere it has gone.

**One key, two directions.** Tap puts a hand down; F held and then *released* fires
a **burst**. There is no committing press — a pair that can reach lights a **fuse**
and folds itself.

**Putting one down is two taps, and the world is stopped between them** (§7). A
charged release while a hand is raised is still a burst: it cancels the placement,
fires, and starts the clock again.

Those places always sum to the same number. **Nothing in the game creates or destroys
a hand** — placing, committing, unfolding, bursting and picking up all just move one
— which is what `HandStock.total` states and `test_hand_stock` pins.

The mechanism is documented where it lives: `HandField` and `FoldWorld`'s
`_land_ball`, `_take_back`, `_wake_unsupported_hands`, `_scatter_pair` and
`_recover_lost_hand` each carry the trap that shaped them. What is **only** here is
what you must not quietly change:

- **Two slots, and that never grows.** A hand you pick up is not a capacity upgrade;
  it refills a slot you emptied. Traversal is nearly free — fold, cross, unfold
  behind you — and what costs you is a fold you must *leave standing*.
- **Nothing is ever refused for want of room.** A hand with nowhere to go lands on
  the ground, which is what lets a burst be fired blind and why no code path asks "is
  there a slot" first.
- **The burst is not aimed.** `hold_action` takes no direction. Do not give it a
  target without a design conversation — the untargeted reading is what makes it a
  thing you *do*, not a thing you *point*.
- **Both gestures fire on the RELEASE.** A hold does not act, it *loads*. So the
  irreversible half of the verb is never on a timer you cannot stop, and a charge is
  a state you can carry — load it on safe ground, walk to the seam, release there.
  Reach is measured where you let go, not where you pressed. Do not move either
  gesture back onto the press.
- **The charge is worn on the body**, shading the player toward the teal that means
  "openable" everywhere else on screen (`PlayerBody.charge_color`). Not a ring on the
  aimed cell — a burst does not go off there. If you need to say something new about
  the charge, say it on the body.
- **The burst reaches exactly what is inside it.** It takes the anchors in the sphere
  and nothing else; the far half of a pair stays pinned where you chose, and the pair
  stops existing because there is nothing left to pair with. Reaching in costs you the
  fuse, not the hand at the other end — which is what makes a badly aimed pair
  correctable one end at a time. **A BOLTED anchor does not answer**: it is authored
  world state with no way back, and popping one would let a burst quietly delete a
  puzzle for a hand that was never yours.
- **Fold validity is asked at the FUSE, not at placement.** That is what makes the
  fuse a *window*: you can put both hands down from a spot the fold could not put you
  and run clear before it fires. Moving a check back to placement closes it.
- **A failed fold scatters rather than refunds** — returning hands to your slots
  would make a mistimed fold free.
- **A loose hand is a BALL in flight and an occupant at rest.** That boundary is what
  lets a hand behave physically without giving anything persistent a live position.
- **There is no fixed number of placed anchors, and no fixed number of unpaired ones.**
  Two fixed registers is what wedged the game once. The bound is how many hands you are
  carrying, and a hand nothing reaches simply stands where you put it.
- **A hand pairs with whatever it can REACH** — `gap <= span(a) + span(b)`, measured
  the way the space is walked (`FoldLattice.shortest_delta`), asked every frame. Not
  with whichever anchor was placed last. Anchors carry their region, because base ids
  are per-region and DO overlap.
- **A site holds one anchor.** Two on one spot are a pair at zero gap: guaranteed to
  arm, guaranteed to be refused. This is the only thing besides "is there sheet here"
  that placement asks, and it is a question about the SPOT, not about the fold.
- **A kind changes its fuse and its span, and nothing else.** A third behaviour is a
  design change; do it in `HandTypes` and nowhere else.
- **`ARM_REACH` and `span` are different distances.** Your arm is how far you can PIN
  (a square of nine cells). A span is how far the anchor then reaches for a PARTNER.
  Both were called reach once; that is why one of them is not now.
- **There is no remote unfold**, so **you can strand yourself**. Do not paper over
  that with a recall key without a design conversation. A **burst plate**
  (`TileTypes.TRIGGER_BURST`) is not that key: it fires the same burst at a reach the
  WORLD authored, from a tile you have to walk onto. What is player-aimed is still
  exactly your own arm.
- **The floating hands are style.** Nothing reads their drawn positions back; do not
  make them load-bearing without saying so.

---

## Rendering, in one page

The world is **pixel art**, and that is a rendering decision only — no physics
constant, cell size or coordinate changed.

```
world (unchanged: CELL = 64 world units)
        │
        ▼
  SubViewport, RESIZED per zoom  ← 1 art pixel = 4 world units = WORLD_PER_PIXEL
        │  320x180 at 1:1          the LENS never moves; the target grows instead
        │
        ├── TileBatch   the sheet: ALL pieces of ALL copies in two Polygon2Ds
        ├── StaticBody2D  colliders, domain + the copies one step out
        └── WrapCanvas×n  everything that moves, painted once per lattice offset
        │
        ▼
  TextureRect, nearest             HUD renders OUTSIDE this, at window resolution
    + held.gdshader                the whole world speaking for itself when it stops
```

- **The camera's zoom is fixed; the render target resizes.** Moving the lens would
  resample the tileset and soften everything. The camera IS dynamic
  (`WorldCore.camera_zoom_for`) — a *logical* zoom, which sizes the target via
  `PixelArt.target_size`. Never set `_cam.zoom` from gameplay code.
- **Appearance is a base-space fact.** Variant, edge kind and UVs come from the base
  grid, so a tile looks the same however it has been folded. Do not key art off the
  folded neighbourhood.
- **The seam is a hard line**, cut exactly as the geometry is. Deliberate — do not
  soften it without a design conversation.
- **Lighting is style, not a mechanic.** The player and the overlay markers are drawn
  unlit so they never disappear into a dark corner.
- **The held look composites the whole world at once**, which is why it lives on the
  rect rather than on anything in the scene. Once arrived it **must not animate**:
  with `held` steady the output is a fixed function of the input, so a held world is
  one unchanging image — and a render check hashes two frames half a second apart to
  hold that. The overlay is inside the same target, which is what bounds how far the
  colour drain may go; `scripts/world/README.md` §"What a held world looks like" has
  the reasoning.

---

## Open design questions

Live, not settled — listed in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
§"What is deliberately still open". **Do not close one silently in a refactor.**
The biggest is fold extent: a fold here guts a structure over there, and that is kept
so it can be *felt* before it is designed away.

---

## Testing

```bash
HOME=/tmp/godot-home ./run_tests.sh            # all
HOME=/tmp/godot-home ./run_tests.sh world      # partial filename match
```

`run_tests.sh` prefers the bundled `tools/godot/godot` (gzipped, Linux x86-64) and
falls back to a system `godot` on PATH. After adding or renaming a `class_name`, run
`godot --headless --editor --quit` once so the global class registry picks it up, or
you will get spurious "Identifier not declared" errors.

**Write the test first.** The suite is the behavioral spec — to know how something
behaves, read its `test_*.gd` before reading the implementation. See
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for what each gate catches.

---

## Git workflow

Work on `claude/*` feature branches; PRs merge into `main`.

---

## The five things that matter most

1. **Read `STATUS.md`** — what is done and what is next.
2. **State is `(base, folds)`; everything else is derived** — including the hand
   ledger. Re-derive, don't mutate.
3. **`BaseFrame` is how anything survives a fold.** Not crease math.
4. **Ask `TileTypes`, don't switch on type ints.**
5. **Write the test first** — the suite is the spec.
