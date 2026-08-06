# Project Status — Space Folding

**Last Updated:** 2026-08-06
**Current Phase:** Consolidated onto the gravity metroidvania direction. Playable
vertical slice: two regions, doors, real subspaces, fold/unfold with animation,
folding as a **finite carried resource** — rendered as pixel art with fold-aware
dynamic lighting, framed by a camera that zooms and leads with the moment.
**Tests:** **556 passing** / 556 (0 failing, 0 risky), 24 scripts, ~22.5s.

---

## Where the project is

The long-running split between a top-down grid puzzler and a side-view gravity
metroidvania is **resolved in favour of gravity**. See `AGENTS.md` §"the
2026-08-04 consolidation" for what that removed and what it kept.

What exists and works today:

| Area | State |
|---|---|
| Fold kernel (derive/replay, arbitrary crease angles) | ✅ Solid, well covered |
| Base-frame transport (`BaseFrame`) | ✅ Solid, well covered |
| Side-view world: gravity, riding flaps, depenetration | ✅ Playable |
| Variable-height jump (tap vs hold), air control | ✅ Playable |
| Subspaces (fold interiors as real places) | ✅ Playable |
| **Nesting: folding yourself in, and in again** | ✅ Playable, any depth, ⚙️ untuned |
| Regions + doors (recursive partner resolution) | ✅ Playable |
| Tile registry (pins, unanchorable, water, triggers) | ✅ Wired, tested, **in the world** |
| Fold-on-enter triggers | ✅ Wired at world level, **in the world** |
| Hands: two slots, typed, conserved (`AnchorStock`/`HandTypes`) | ✅ Playable, **in the world** |
| Loose hands (`HandPickup`) — authored + dropped, one object | ✅ Three placed, ⚙️ untuned |
| One-key verb (tap = place a hand, hold = release burst) | ✅ Playable |
| Auto-commit fuse, pulsing on the placed hands | ✅ Playable, ⚙️ untuned |
| Hands floating beside the body (style only) | ✅ Playable |
| Occupant model (entities riding tiles) | ⚙️ Ported and tested, **not yet used in-world** |
| World authoring (`worlds/overworld.json`) | ⚙️ Format done; one hand-authored world |
| Unanchorable tiles (`_`, `X`) | ⚙️ Wired and tested, not yet placed in the world |
| Pixel-art render pass (low-res target, 16px tileset, UVs) | ✅ In the world |
| **One wrap for the whole view** (`FoldLattice` / `WrapCanvas`) | ✅ In the world |
| **Batched sheet** — two canvas items, not one per fragment | ✅ In the world |
| Dynamic lights as fold-aware occupants | ✅ In the world, 5 placed |
| Hand-drawn tilesheet | ⚙️ Layout + drop-in path done; sheet is generated in code |
| Audio | ✅ Whole fold vocabulary wired; 21 SFX + 2 music beds ship (generated placeholders) |
| Save / progression | ❌ Not started |
| Entities (items, enemies, save points) | ❌ Not started |

---

## Test suite

556 passing across 24 scripts. Composition:

| Script | Tests | Covers |
|---|---:|---|
| `test_fold_world` | 106 | **Scene-driven**: riding, pinch, subspaces, doors, pins, plates, lights, camera, the hand economy, the fuse and the burst |
| `test_nested_folds` | 25 | **Scene-driven**: folding yourself deeper, the torus, surfacing a layer at a time, the ledger and the renderer at depth |
| `test_fold_lattice` | 18 | How a space repeats: descent, orthogonality, wrapping, copies, framing |
| `test_tile_batch` | 11 | The batched sheet: grouping, UVs, baked copies, per-copy deformation |
| `test_geometry_core` | 41 | Sutherland-Hodgman, epsilon, area/centroid |
| `test_world_core` | 70 | Map parsing, seams, anchor eligibility, camera framing + lookahead, the hand spring, its idle drift, and the falling-hand ball physics |
| `test_world_data` | 31 | World format + the shipped world's content, incl. lights and loose hands |
| `test_audio_manager` | 47 | Buses, the volume-applied-once rule, loading + looping, the mix/jitter/throttle registry, fades, persistence |
| `test_player_body` | 22 | Look/point keys, the jump press edge, the tap-to-hold height curve, velocity-as-fraction, motion scalar |
| `test_world_audio` | 20 | **Scene-driven**: that the fold vocabulary is actually heard |
| `test_tile_atlas` | 17 | Tileset kinds/variants, base-space UVs, the generated sheet |
| `test_tile_types` | 16 | The registry |
| `test_light_source` | 15 | Lights as occupants: fold-away, ride, split, serialization |
| `test_pixel_art` | 14 | The art-pixel quantum; the target that resizes so zoom stays crisp |
| `test_collision_core` | 13 | Polygon clipping under folds |
| `test_trigger_cascade` | 12 | Firing, idempotence, pin veto, cascade cap |
| `test_occupants` | 11 | Split-on-unfold, footprints, carried geometry |
| `test_folded_state` | 11 | Per-position stacks, dominant type |
| `test_fold_replay` | 11 | The derivation engine |
| `test_anchor_stock` | 11 | Hand conservation: slots ↔ pinned ↔ fold ↔ ground |
| `test_hand_types` | 10 | The kind registry: colours, fuses, mixed pairs |
| `test_base_grid` | 9 | Immutable base model |
| `test_base_frame` | 9 | Base ↔ derived transport |
| `test_fold_unfold_inverse` | 4 | Unfold-as-drop-and-re-derive |

> The consolidation dropped the count from 525 to 226 because ~340 tests covered
> code it deleted. Kernel coverage is intact; every ported subsystem — and every
> subsystem added since — shipped with tests.

`test_fold_world` is the one that matters most for confidence: it drives the real
scene and exercises the beats end to end.

---

## Recent Changes

### 2026-08-06 — A fold reaches into every copy, and takes from every copy

Three reports, one root cause: a level stores ONE copy of a repeating space, but
a fold's band — and the preview of it — live in the space as it *repeats*.
Anything reaching past a glue line found nothing there.

- **Folding across the glue pulls in sheet, not void.** What a fold takes is now
  cut from the space as it repeats (`FoldWorld._tiled_for`): a band running past
  its own glue line is reaching into the next copy of this space, which is this
  space. Only the periods the fold does NOT keep are materialised — the ones it
  keeps become the child's own wrap and would be drawn twice otherwise — so the
  ordinary perpendicular case tiles nothing and is byte-identical to before.
  A tiled fragment is an ordinary `FoldedPiece`: shifting `src_offset` by the same
  vector as the polygon keeps `polygon == base_polygon + src_offset`, so
  base-frame transport carries the player through it like anything else.
- **The outer tiling survives a fold at an angle.** `FoldLattice.push` used to
  ask `P · n == 0`. The honest rule is that sliding by the whole gap is the
  IDENTITY inside a fold, so a period whose across-the-band component is a whole
  number of gaps still descends — **sheared** to its along-the-band part. At any
  other angle the band spirals and the outer repetition stops being copies and
  becomes **content**: the strip is cut out of the outer world's tiling, so it
  carries a row of sheared copies of the room you came from.
- **The preview band is drawn in every copy**, clipped to one
  (`FoldLattice.domain_polygon`) so the copies tile rather than stacking their
  alpha into a wash. What you see before the fuse burns is now what the fold will
  actually take. Outside a fold there is no domain, nothing is clipped, and it is
  the single band it always was.

11 new tests (498 → 509).

### 2026-08-06 — Folds inside folds inside folds; one wrap for the whole view

Two things that turned out to be the same thing. Nesting was blocked by there
being *two* of everything — a world path and a subspace path — and the wrap was
kludgy for exactly the same reason: four places re-implemented "repeat across the
copies", and the newest object in the game had forgotten to.

**One space, at any depth.**

- **New `FoldLattice`** (kernel): the periodic structure of a space, stated once.
  No periods in a region, one inside a fold, **two inside a fold whose creases run
  across the fold outside it** — a torus. Descent is a one-line rule: a period
  survives into a fold's interior exactly when it runs ALONG the new band
  (`P · n == 0`). A consequence worth knowing: the axes are then always
  orthogonal, so wrapping is a per-axis `floor` rather than a lattice reduction,
  and every period is a whole number of cells even for a diagonal crease.
- **`do_sub_fold` is `do_fold`.** The world path and the subspace path collapsed
  into one, and with them `current_pieces`/`sub_pieces`, `rebuild_world`/
  `rebuild_sub`, `wall_polys`/`sub_wall_polys`, and the rest of the pairs. The
  region is simply the level whose context is empty. **Folding yourself deeper is
  not a feature that was added; it is the refusal that was deleted** — there was
  no longer a second code path for it to be missing from.
- Surfacing comes up **one layer at a time**, animating at any depth (drawn
  against the parent space's copies), and the sheet's tint deepens with each
  layer so how far in you are is legible without a readout.
- The exit rules, the unfold-blocking rules and the hand ledger needed no changes
  at all: all three were already written against "the current level".

**One wrap, and it is not the objects' problem.**

> Anything that MOVES repeats through `WrapCanvas`. Anything STATIC bakes its
> copies at rebuild (`TileBatch`).

- **New `WrapCanvas`**: a canvas item that paints itself once per lattice offset.
  Subclasses override `paint()` and draw in ordinary world coordinates.
  `WorldOverlay`, `HandOrbit` and the new `PlayerVisual` are the three; the ghost
  list, `_copy_offsets`, the per-copy terrain nodes and the hand-rolled light
  offsets are all gone.
- **The hands floating beside you now appear in every band**, which they never
  did. That took one word — `extends WrapCanvas` — and is the point of the whole
  exercise.
- `prepare()` gathers the expensive queries once per frame rather than once per
  copy; `paint_once()` is for what belongs to the frame rather than the space
  (the preview band, the full-extent guides).

**And it got a great deal cheaper.**

- **New `TileBatch`**: the entire sheet is **two** `Polygon2D`s — one per lit
  material — using `Polygon2D.polygons` to carry every fragment of every copy over
  one vertex array. It was one node per fragment per copy: ~800 for a region,
  ×49 inside a fold, torn down and rebuilt on **every single fold**.
- The fold transition is **three batches** (A flap, B flap, strip) instead of a
  node per sub-fragment. Two of the three move by setting a position; only the
  strip touches vertices, and its deformation is applied per copy so each band
  collapses onto its own seam.
- `LightRig` went from four materials to two, with depth as a tint uniform — which
  is what lets an arbitrary nesting depth read differently with no new state.
- Colliders are one body whose shapes cover the domain and the copies one step
  out, and they are detached before being freed rather than lingering a frame.
- Full suite: **16.0s → ~14.5s**, with 45 more tests in it.

**New tests:** `test_fold_lattice` (14), `test_nested_folds` (18),
`test_tile_batch` (11).

### 2026-08-06 — Hands are objects: they float, they fall, they orbit

Hands used to be markers that appeared where the code put them. Now they behave like
things.

- **They drift when nothing is happening** (`WorldCore.hand_drift`) — carried and lying
  on the ground alike, since both draw through `HandOrbit.draw_hand`. Two beating sines
  per axis on frequencies sharing no period, so there is no loop the eye can learn. It is
  a function of wall time rather than an integration, so a hand dropped and picked back up
  keeps its phase, and the wrap copies of one hand inside a strip bob identically. Each
  hand's phase is seeded from *what it is*, never its list index — seeding by index made
  every remaining hand twitch when a different one was picked up.
- **The burst reaches 1.3 cells** (was 1.2). At a tile it kept missing seams that looked
  well inside it, which reads as the key not working.
- **A loose hand is a light, draggy BALL while in flight** (`WorldCore.hand_ball_step`),
  and an occupant again once it stops (`_land_ball`). It floats down rather than dropping,
  rolls off slopes, ejects out of walls, and rests hovering on its floating radius. It can
  be **caught in mid-air**, and `hands_loose()` counts balls so conservation never wobbles
  mid-fall.
- **Folds carry a hand in flight** (`_carry_balls_through`, through `BaseFrame` exactly as
  the player) — and one swept into a strip **keeps flying inside the strip**, velocity
  intact, because a fold is a translation and the step is position-independent.
- **A strip is a cylinder, so a falling thing wraps** (`WorldCore.wrap_into_strip` — a
  modulo, not the player's one-band if/elif, because a falling object can cross several
  bands in a frame). With a vertical wrap axis a hand **orbits indefinitely**: a real
  object in a closed space, still counted, still catchable, landing the moment a fold puts
  ground in its way.
- **A resting hand wakes if a fold takes its ground away** (`_wake_unsupported_hands`). A
  fold that merely slides its tile carries it, as before.

Three bugs found by writing the tests first, all of which a player would have met:

1. A ball rolling into the corner at the foot of a slope **pinned itself there forever** —
   holding a velocity every direction of which was blocked, so a speed-based rest test
   never fired and the position never changed. Rest is now judged on *progress*
   (`HAND_STALL_DISTANCE`), which is the honest test of motion.
2. A hand unpinned from a wall face **fell down the inside of the wall**, because contact
   resolution assumed it was arriving at a surface rather than already buried. Balls now
   eject before anything else.
3. Two tests were **teleporting the player fully inside a merged wall pillar** —
   `depenetrate` returns `INF` there, a state not even the player can occupy — and passing
   because the old instant-drop landed the hand on top of them.

Also: **authored hands are settled at load** (`_settle_authored`). Authoring names a cell,
which puts a hand at that tile's *centre*, half a cell up; without settling, the first
fold near a cache dropped it, since it was never really on the ground.

The trade, chosen explicitly: a refused fold no longer leaves its hands on the exact cells
you picked, so the shape of a failed attempt is no longer legible in the world. Bought for
"a hand is always somewhere you can see and walk to", with no exceptions to learn. And a
cache can now move without you touching it.

79 new tests (416 → 495).

**Follow-up fix (same day): the hand that vanished on unfold.** Reported as holding one
anchor, releasing a folded one, and never finding the second hand. Two independent bugs,
neither caught by the conservation tests because `hands_total` was right the whole time:

1. `_take_back` ran **before** the unfold rebuilt the geometry and teleported the player,
   so the overflow hand was let go at the pre-unfold position and into the old fragment
   list — cells away from where you ended up, on ground that had since slid out from under
   it. Same ordering bug on the subspace-exit path, where it was worse: the ball was tagged
   as flying inside a strip that no longer existed, so it could never be stepped, drawn or
   collected.
2. `_land_ball` **warned and gave up** when no sheet was within two cells — the one code
   path that could really destroy a hand, silent because a warning is not a failing test.
   It now falls back to the spawn tile, then to keeping the hand airborne.

Also `_recover_lost_hand`: a hand falling out of the world used to be re-dropped as a
*ball* at the player, so a player standing over a pit had it fall off again and loop
forever — counted, never findable. It lands as a pickup now. 5 new tests (495 → 500).

### 2026-08-06 — The jump has a hold, and the hold has a height

The jump was one height: press the key and you got the whole arc, whatever you
meant. Now **how long you hold Space is an input**, and the height is a continuum
from a ~1.25-cell tap to a ~2.6-cell full hold.

- **Cut the rise with weight, not by clipping the velocity.** Releasing mid-rise
  doubles gravity (`JUMP_CUT_GRAVITY`) rather than truncating `velocity.y`. Same
  launch speed every time, so `motion_fraction` still measures a fresh jump as a
  full -1 up — and, more importantly, releasing at any point in the rise gives the
  height you paid for instead of one of two jumps.
- **The press is now an EDGE** (`take_jump_press`). The buffer used to be refilled
  from the *held* key, which left it permanently full while you held: the player
  holding for height bounced off the floor on the frame they touched it and spent
  the hold on the wrong jump. Sustain is armed only by a jump we launched, so a
  held key cannot re-arm it without a fresh press, and a body thrown upward by the
  world is not quietly made floatier by a key that happened to be down.
- **The apex is lighter** (`APEX_GRAVITY`, 0.7 within 200 units/s of the peak) and
  **the fall is heavier** (1.12). More of the frames where you are choosing a
  landing or pinning the sealed chamber's mid-air anchor; a landing that arrives
  sooner than the rise that earned it.
- **Air deceleration is gentler than ground** (`AIR_DECEL` 1400 vs 3200), so
  letting go of the stick mid-jump keeps the run that launched it. Steering the
  other way still gets the full `RUN_ACCEL` — nothing that was reachable got harder
  to reach, only stopping dead in mid-air did.

**The level-design bounds are now pinned by tests, not by hope.**
`PlayerBody.jump_height_for_hold` integrates the very step the body takes, and
`test_player_body` asserts a tap clears one cell, a full hold clears the two-tile
pinned pillar, and nothing clears the three-tile wall the pressure plate opens. A
gravity constant nudged for feel can move the world; that test is what says so.

12 new tests (404 → 416). What is *not* pinned is feel — the curve is a first
guess and wants a controller in a human's hands.

### 2026-08-05 — A fold in flight owns the frame

**Bug:** prime a fold, cross between regions, and when it went off the player was
teleported somewhere impossible — reported as ending up stuck in a wall.

Reproduced by arming a fold and standing on a door while its fuse ran out. The trace
made the mechanism plain: the player warped to east *while the fold animation was
still playing*, and then the fold's finalize teleported them to `(2592, 864)` — the
landing it had computed in west, applied in an east region only 1920px wide. Off the
map entirely; in other geometry, inside a wall.

`_physics_process` checked `animating()` at the top, but `_tick_fuse` STARTS a
transition from inside the frame, and the goal / pickup / trigger / door checks below
it then ran anyway — against a body frozen at its pre-fold position and a fragment
list that does not rebuild until the animation finalizes.

- **`_physics_process` now returns as soon as `_tick_fuse` starts a transition.** The
  rest of the frame belongs to the fold.
- **`_traverse` refuses to fire while animating**, stating the invariant where it
  would be harmed rather than only where it happens to be enforced.
- The two regression tests are the only ones in the suite that run with animation ON,
  because the bug exists only while a transition is in flight. Both were checked to
  fail without the fix.

This was latent from the moment committing moved into `_physics_process` with the
fuse; before that, folds committed from `_unhandled_input`, where the next frame's
top-of-function guard caught them.

### 2026-08-05 — Any number of hands down; several folds armed at once

**Bug:** place a hand in one region, cross to another, place a second — and the game
wedged. Reported as "I can no longer place any more hands"; reproduced exactly. The
two fixed anchor registers were the cause: the hand left behind occupied one forever,
so every pair formed afterwards contained a partner that could not be reached, the
fuse paused permanently, and the burst could not recover it from where you now were.

Fixed by removing the limit rather than special-casing the symptom.

- **`pending_a`/`pending_b` became `unpaired` + `primed`.** `unpaired` holds hands
  waiting for a partner; `primed` holds PAIRS, each counting its own fuse. There is no
  bound but the hands you are carrying.
- **A hand pairs with the last unpaired anchor you can SEE.** An anchor in another
  region — or sealed inside a fold — is not a partner a fold could be finished with,
  so a new hand starts a fresh pair rather than being spent on one that can never
  fire. The stranded hand waits where it is.
- **Several folds can be armed at once, and they fire in FUSE order.** A swift pair
  laid second goes off before a patient pair laid first. That falls out of per-pair
  fuses rather than being arranged.
- **An armed pair outside your region pauses**, and resumes when you come back —
  leaving one ticking behind you is now a thing you can choose to do.
- **A burst reaching either half of an armed pair breaks the whole pair.** You cannot
  half-defuse a fold: what you can reach comes back, the far hand drops where it was
  pinned, so reaching into an armed pair always costs you one.
- **Anchors now carry their region and resolution checks it.** Base ids are per-region
  and overlap, so a west anchor could otherwise resolve onto whatever east tile shared
  its id — latent, and only not biting because the two regions differ in size.
- The overlay draws every placed hand and every armed pair's band, each pulsing on its
  own fuse, so two armed folds beat at different rates and you can see which is next.

### 2026-08-05 — Validity moves to the fuse; the distance rule goes

The fuse was a delay. It is now a *window*.

- **Placement asks nothing of the fold.** `place_pending` checks one thing: that
  there is sheet under the cell to pin to. That is storage rather than a rule — an
  anchor is a base identity plus a point in a tile, and void has no tile to be a
  point in. The degenerate pair, the surface rules (`can_anchor_at`), the span and
  somewhere-to-land are all `commit_pending`'s question now.
- **Which makes the fuse a window to make a doubtful fold work.** Put both hands down
  while standing where the fold cannot put you, then run clear before it fires and
  ride the flap instead of being swallowed. Refusing at placement would have closed
  that window before it opened.
- **A fold that fails at the fuse scatters.** Both hands drop WHERE THEY WERE PINNED
  — not into your slots, not at your feet. A pending anchor already stores exactly
  what a loose hand does, so `_scatter_pending` is a conversion, not a placement, and
  the hands land on the spots you chose. Returning them would make a mistimed fold
  free.
- **The two-tile minimum is gone.** A one-cell fold excises a one-cell band and the
  halves meet; the rule was protecting taste, not geometry. `anchors_valid` now
  rejects only two anchors on one cell, which genuinely has no crease direction.

### 2026-08-05 — Hands pop into the world; recall becomes a burst

Two changes that turn out to be the same change: a hand that has nowhere to go is a
hand on the ground, and once that is true nothing has to be refused.

- **New `HandPickup`** (kernel): a hand lying in the world, stored as a base identity
  plus a point in the tile — the same shape as `LightSource` and a door. So it rides
  flaps, folds away with its tile, and is found again inside the fold. Authored caches
  and hands a burst popped out are the SAME object in the SAME list, drawn by the SAME
  function (`HandOrbit.draw_hand`), because to the player they are the same thing.
- **The `ANCHOR_CACHE` tile type is gone**, with its `A` character and its atlas row.
  A loose hand is an occupant of the sheet, not terrain; it is authored per region in
  a `hands` array beside `lights`, and it draws as a hand rather than as a tile.
- **Recall is a BURST, not an aimed act.** Holding F fires a small sphere around the
  body (`BURST_RADIUS`, ~1.3 tiles) that takes back placed hands in reach, opens folds
  whose seam is in reach, exits a subspace from its glue — and **drops any hand with
  nowhere to go at your feet**. `hold_action` no longer takes a direction: where you
  stand is the whole input. A ring confirms the reach after the fact.
- **Nothing is refused for want of room any more.** The `_has_room_for` gate added
  yesterday is deleted; overflow lands on the ground instead. That one clause is what
  lets the burst be fired blind.
- **A burst releases what was releasable when it fired**, not a cascade: a stack of
  two folds under one diamond clears one layer per press, and the behaviour no longer
  depends on which unfolds happen to animate.
- **Conservation is now total.** `AnchorStock.total` counts the ground as a fourth
  place a hand can be, so *nothing* in the game changes the number of hands — placing,
  committing, unfolding, bursting and picking up all just move one.

Two bugs the tests caught rather than review: dropping two hands with a positional fan
picked their fragments from the fanned points, which at a seam put one either side of
the crease — the unfold then carried them to opposite ends of the world (the fan now
applies after the fragment is chosen); and a burst that cascaded cleared a whole stack
in one press.

### 2026-08-05 — Anchors become HANDS: two of them, typed, and they fold themselves

The counting model became typed objects. An anchor was an anonymous unit drawn from a
growing capacity; a hand is a thing with a kind, you have exactly two, and a fold
holds the two you pinned it with.

- **Two slots, and that never grows.** `AnchorStock` went from capacity arithmetic to
  slot arithmetic (`SLOTS = 2`); `WorldData.anchor_capacity` became `starting_hands`,
  a list of kinds. `Fold.held_anchors: int` became `Fold.held_hands: Array[int]`, so
  unfolding returns the same two hands — kinds and all — that went in.
- **New `HandTypes`** (kernel): one file per kind, carrying its colour and its fuse.
  Three ship — `plain` (1.6s), `swift` (0.65s), `patient` (3.2s) — and the fuse is the
  ONLY behavioural difference, which is the restraint the registry exists to prove.
- **A cache gives ONE hand, into one free slot.** Since a slot is free because you put
  a hand down, a cache is the second half of a fold already in progress: place a hand,
  walk to a cache, take a different kind, finish the fold with a pair you did not set
  out with. Full hands walk straight over one and it waits. Which kind is authored per
  tile (`data.hand`); the tile is painted neutral and tinted by that kind, so one
  atlas row covers every colour.
- **The commit press is gone.** Placing the second hand lights a fuse — the mean of
  the two kinds' fuses, so a mixed pair lands genuinely between its parents — and the
  pair folds itself. Both hands pulse while it burns, slower at first, quickening as
  it comes due. Pulling a hand back defuses it, and the fuse PAUSES while an anchor is
  out of frame, so walking through a door mid-count makes the fold wait rather than
  fire somewhere you cannot see.
- **Unfolding can now be refused for want of room.** A fold gives back both hands at
  once, so a spare you picked up has to go down first.
- **Hands float beside you** (`HandOrbit`): small circles on a spring, trailing your
  motion, and drifting on their own even at rest — carried or lying on the ground
  alike, since both go through `draw_hand`. Style only — nothing reads their
  positions. `WorldCore.spring_step` and `WorldCore.hand_drift` are pure and tested;
  the node is just the drawing.
- **Reset restores hands and respawns caches**, reversing yesterday's call *because
  the model changed under it*: capacity no longer grows, so there is no progression
  left for a reset to confiscate — and hands are exactly what a reset gives back, so
  leaving caches spent would strand you shorter than you started.

### 2026-08-05 — Reset stops confiscating your caches; the HUD stops lecturing

- **`R` keeps what you found.** Collected caches were per-region state inside
  `regions`, so `_setup_all` wiped them on every reset — and reset is the only way
  out of stranding yourself with no anchors and no reachable seam. Using the escape
  hatch cost you your progression. Caches now live in `FoldWorld.collected_caches`
  (region id -> {base_id: grant}), **outside** `regions` precisely so the rebuild
  cannot reach them. Folds still reset, which is what makes `R` a real remedy: with
  no fold standing, every anchor is back in hand.
- **The on-screen help is one line of controls.** It was nine lines that explained
  the fold verb, the economy, the caches and the doors — teaching, in text, over the
  top of a game whose aim ring, preview band, seam diamonds and anchor readout
  already say those things in place. Flash messages lost their instructional tails
  too ("Folded IN. F at the seam anchor (white diamond) unfolds it." → "Folded in.").

### 2026-08-05 — Anchors are a thing you carry, and one key spends them

Folding was free and unlimited. It is now paid for out of a countable, **conserved**
stock, and the whole verb collapsed onto one key.

- **New `AnchorStock`** (kernel): `free = capacity - held-by-live-folds - pinned`.
  Nothing is stored — `held` is summed from `Fold.held_anchors` across every live
  fold list, so **unfolding refunds by simply removing the fold**. Adding a "spent"
  counter would be a second source of truth; don't.
- **A standing fold holds two of your anchors.** The budget is how many folds may
  stand *at once*, not how many you may ever make. Crossing a pit still costs
  nothing permanent (fold, walk the seam, unfold behind you); what costs is a fold
  you must leave standing. Folds the *world* makes — authored pre-folds, trigger
  folds — hold zero and charge you nothing.
- **Charged at pin time**, so the count drops as you place and the commit moves the
  same two anchors into the fold without moving the total. An un-affordable or
  too-close anchor is refused *when placed*, because the next tap is the commit.
- **One key (F): tap pushes in, hold pulls back.** Tap pins anchor 1, then anchor 2,
  then commits. Hold retrieves your own anchor, unfolds the fold under a seam
  diamond, or exits a subspace by its glue diamond. `Q`/`E`/`Esc`/`U` are gone —
  and with `U` went the remote unfold, which had been a free escape valve.
- **New `ANCHOR_CACHE` tile (`A`)**, registry-driven (`grant: 2`). Three placed, each
  behind a beat rather than in front of one: the pillar top pays for the climb fold,
  the sealed chamber pays its way back out, and one sits **inside east's shipped
  pre-fold** — reachable only through door W1, because a cache folded away is not
  lost. Collected caches dim in place; collection is per-region runtime state.
- `WorldData.anchor_capacity` (4) authors the starting allowance. The old level-era
  "fold budget" this resembles was a per-level par; this one is carried and refunded.
- Integrated with the pixel pass: `ANCHOR_CACHE` is a tileset row (`TileAtlas.K_CACHE`,
  a pair of upright pegs — two is what it grants and what a fold costs), and a spent
  cache is the same tile modulated dark rather than a different one.

### 2026-08-05 — Pixel art meets the dynamic camera

The pixel pass and the dynamic camera were built in parallel and are, on their
face, incompatible: the pass wanted the lens pinned at 1/4 so a 64-unit cell
covers exactly 16 art pixels, and the camera wanted to open from 0.80 to 0.55.

- **Resolved by resizing the render target instead of moving the lens.** Inside a
  render target the size of an art pixel is purely a function of camera zoom — so
  the lens now *never* moves (`PixelArt.CAMERA_ZOOM`), and "show more world" is
  answered with more pixels: `PixelArt.target_size` gives the resolution a given
  logical zoom needs and `FoldWorld._size_pixel_view` applies it as the zoom eases.
  World-per-art-pixel holds at 4.0 across the whole zoom range, so the tileset is
  never resampled.
- `PlayerBody.zoom_target` / `camera_zoom()` are therefore **logical** zoom: they
  size the buffer. The pixel snap moved into `_cam.offset`, leaving
  `global_position` the unsnapped truth — quantizing the smoothing state itself
  would let a slow pan stall inside a pixel.
- Verified in the real scene: opening the frame from 0.80 to 0.55 grows the target
  400x225 → 582x327 with the lens fixed at 0.250 and a cell steady at ~16 art px.

### 2026-08-05 — Pixel art + dynamic lighting

- **Pixel render pass.** The world draws into a low-resolution `SubViewport` scaled
  up with nearest filtering; one art pixel is 4 world units and a cell is 16 art
  pixels. No physics constant, cell size or coordinate changed. `PixelArt` is the
  one place that says how big an art pixel is. The HUD stays outside the pixel
  viewport at window resolution. (The target is sized from the camera's logical
  zoom — see the entry above.)
- **A real tileset** (`TileAtlas`): 16px tiles, one row per kind, one column per
  variant, generated procedurally so it ships as readable code and headless tests
  never touch the import pipeline. Drop a sheet at `assets/sprites/tiles.png` and it
  is used instead — see `assets/sprites/README.md`.
- **Base-space UVs.** Fold fragments are arbitrary polygons, so tiles cannot be
  blitted on a grid. `TileAtlas.uv_for` sends each vertex back through `src_offset`
  to its base tile, so a fragment carries the patch of art it was cut from and the
  crease cuts the art exactly as it cuts the geometry. **The seam stays a hard
  line** — deliberately, for now.
- **Lights are occupants** (`LightSource`, kernel): a base identity plus a point in
  the tile, resolved through `BaseFrame` against whatever configuration is on
  screen. Fold a lamp away and it leaves the overworld and lights that fold's
  *interior*; fold something else and it rides the flap. Nothing special-cases
  this — it is the door machinery applied to light. Five lamps placed in the
  shipped world, including one sealed inside east's pre-placed fold.
- **Pixel-level lighting** (`assets/shaders/pixel_lit.gdshader`, `LightRig`):
  shaded point and light position are snapped to the art-pixel grid, intensity is
  quantized into bands, and band edges are ordered-dithered with a 4x4 Bayer
  threshold — light arrives in chunky rings, not a smooth glow. Ambient is
  deliberately generous: **lighting is style, not fog of war**, and the player and
  overlay markers are drawn unlit so they never vanish into a dark corner.
- Foreground and background answer light differently (the registry's walkability
  picks which), which is the only depth cue the flat world has.

### 2026-08-05 — The frame leads where you are going

- **Camera lookahead.** Zoom decides how *much* to show; lookahead decides *where
  to centre it*. The body sat dead centre, which spent half the frame on ground
  already crossed. The view now leads:
  - **speed** — the lead is a fraction of the body's own limits, so it saturates
    at a full run rather than tracking velocity forever;
  - **falling much harder than rising** — a fall is committed and its landing is
    what you need to see; the top of a jump is about to reverse, and leading hard
    there would swing the frame back a moment later;
  - **held look keys** — the same W/S that aim an anchor lean the frame, so
    pressing up to point up shows you what you are pointing at;
  - **flat along a folded band** — inside a fold the strip repeats along the
    crease normal, so a lead that way slides the view across identical copies.
- **`WorldCore.camera_lookahead_for` is the pure decision**; `PlayerBody` supplies
  `motion_fraction` (velocity as a signed fraction of *its own* run / fall / jump
  limits) and `look_dir`, and eases the lead even more lazily than the zoom —
  the lead flips sign when you turn around, and eased that reads as the view
  swinging round rather than whipping across the body. Capped at 6 cells; hard
  relocations cut it along with the lens.
- **Ordering matters and is now load-bearing**: the lead is computed *before* the
  zoom, because the lead moves the camera and the zoom's focus distances are
  measured from where the camera ends up. Reversed, a hard lead would quietly
  crop the very things the focus set exists to keep on screen.
- **Fixed: stacked seam diamonds offered you the fold you could not unfold.**
  Two folds can meet in the same cell; `aimed_fold` took the first in fold order,
  which is exactly the one the newer fold blocks — so F on the diamond only ever
  reported the refusal. It now searches newest-first and prefers a fold that can
  actually come out. The overlay draws one diamond per meeting *cell*
  (`FoldWorld.seam_markers`) so the colour cannot promise what the act refuses.

### 2026-08-05 — The camera frames the moment, not a fixed lens

- **Zoom is dynamic.** The frame rested at 1:1 — about twenty cells across — which
  read tight for a game whose subject is the shape of the space. It now rests at
  `WorldCore.ZOOM_RESTING` (0.80) and *opens* from there, never closes:
  - **speed** — running widens a little, falling hard widens a lot;
  - **the fold you are composing** — pin an anchor, walk away, and the view opens
    to keep it on screen; the span you can see IS the decision you are making;
  - **the band you are inside** — a subspace is framed glue to glue, so a wide
    strip reads as a cylinder rather than a corridor with no visible walls;
  - **a fold rearranging the world** — the transition steps the camera back.
- **`WorldCore.camera_zoom_for` is the pure decision** (a motion scalar, a widen
  scalar, and a focus set of points that must stay on screen); `FoldWorld` supplies
  the context, `PlayerBody` supplies motion from its own limits and eases the lens
  (much lazier than the follow — a frame that resizes as fast as it pans breathes).
  Hard relocations cut the zoom with the position.
- **Subspace wrap copies now derive from the widest frame** rather than a hardcoded
  1400px, so the repeating strip has no visible end when the lens opens.

### 2026-08-05 — The inside of a fold reads as one cylinder

- **The player is drawn in every visible copy of the strip.** `rebuild_sub` gives
  each wrap band a twin of the blob (`sub_player_ghosts`), updated with the body
  each frame. One lone body made the repeated strip read as separate worlds.
- **Crossing a glue line is seamless.** The wrap now displaces body *and* camera
  by the same band width (`PlayerBody.shift_camera`) instead of snapping the
  camera to the body — the snap threw away the smoothing lag (~40px at a full
  run) and jolted the view every crossing.
- `PlayerBody` owns its camera smoothing (Camera2D exposes no way to move its
  smoothed centre, only `reset_smoothing()`), and `FoldWorld` now runs its
  per-frame world logic *after* the body has moved (`process_physics_priority`).
- `WorldOverlay` grew `_copy_offsets()`; the aim ring and pending-anchor rings
  repeat with the copies like doors and seam diamonds already did.

### 2026-08-04 — Consolidation onto the gravity direction

- **Deleted** the top-down view/entity layer (`GridManager`, `Cell`, `CellPiece`,
  grid `Player`, `FoldController`, `InteractionController`, `MainScene`), the
  level-based meta layer (`GameManager`, `LevelManager`, `LevelValidator`,
  `ProgressManager`, `LevelEditor`, `LevelData`, level-select/complete/HUD UI,
  `MainMenu`), the step-log undo (`HistoryManager`, `FoldStep`, `StepReplay`), and
  the 10-level campaign + 10 custom levels.
- **Promoted** `scripts/prototype/` → `scripts/world/`; `Proto*` →
  `FoldWorld` / `WorldCore` / `PlayerBody` / `WorldOverlay`.
  `scenes/world/World.tscn` is the main scene.
- **New `BaseFrame`** (kernel): exact base ↔ derived point transport, lifted out of
  the view layer so pure derivation can use it without a model→view cycle.
- **New `Occupants`** (from `StepReplay`): tile-riding entities with split-on-unfold
  latents. The player no longer uses it — a continuous body has no ridden tile.
- **`TileTypes` wired into the world**: solidity, anchor eligibility
  (`UNANCHORABLE_*`) and fold-proof tiles (`PIN`) are registry-driven; the fold and
  collision paths no longer switch on type ints.
- **`TriggerResolver` reworked** to run against a fragment list and a continuous
  player position. Determinism, channel idempotence, the fire-once guard and the
  cascade cap all carry over.
- **New `WorldData`** (from `LevelData`): regions of ASCII terrain, doors, and
  pre-placed folds per region. The world boots from `worlds/overworld.json`; region
  shapes are byte-identical to the previously hardcoded maps.
- **`PauseMenu`** rebuilt as an in-world overlay (resume / respawn / settings / quit).

### Earlier

The fold kernel (derive/replay engine, diagonal folds, multi-piece fragments) and the
gravity prototype it drives were built between 2025-11 and 2026-07. See
`git log` and the `topdown-archive` tag (`8bf8193`) for that history.

---

## Next up

Roughly in priority order — nothing here is committed to yet:

1. **Playtest the anchor economy.** The allowance (4) and cache grant (2) are first
   guesses, and west's beats were authored when folding was free. The question to
   answer by feel: does scarcity make the world read as *considered*, or merely
   fussy? Tuning is a playtesting job, not an editing one.
2. **Draw the tileset by hand.** The generated sheet is real but plain; the layout
   and drop-in path are done, so this is now an art job, not an engineering one.
3. **Finish putting the ported systems in the world.** `PIN` and `TRIGGER_FOLD` are
   now placed (east's right wing); `Occupants` and `UNANCHORABLE_*` still are not.
   Placing them is also how their design gets pressure-tested.
4. **Settle fold extent.** Infinite-crease is the biggest open question in the
   direction (see `AGENTS.md` §"Open design questions"). Barrier-scoped folds are
   the leading candidate.
5. **Save / checkpoints.** Undo is gone by design; respawn currently sends you to the
   region spawn. Real save points are the replacement — and they are now also what
   collected caches need to outlive a session, and the answer to stranding yourself
   with no anchors and no reachable seam.
6. **Entities.** `Occupants` is the model; nothing renders or moves one yet.
7. **Authoring tooling.** ASCII rows in JSON are workable but hand-editing region
   geometry will not scale. Revisit an editor once the tile vocabulary settles.

---

## Known issues

- The `topdown-archive` tag is **local only** — the remote refused the tag push
  (session credentials are scoped to the working branch). Use `git checkout 8bf8193`.
- The pause menu and settings screen are complete and wired but **unreachable** —
  nothing opens them, so the volume sliders cannot be used in-game. Volumes are
  read from `user://settings.json` at startup, so they are settable by hand.
- Audio is not positional: a fold across the room sounds like one at your feet.
- The shipped sounds are generated placeholders (`tools/gen_audio.py`), not art.
- Unanchorable tiles (`_`, `X`) and occupants are covered by tests but not placed in
  the world yet. Pins and triggers now are — see east's right wing.
- **You can strand yourself.** Spend your last anchors on a fold, walk somewhere its
  seam cannot be reached from, and `R` is the only way back. `R` is survivable by
  design — it refunds every anchor and keeps your caches — but it still costs your
  position and fold configuration. Save points are the real fix.
- Collected anchor caches are runtime-only state (`FoldWorld.collected_caches`) — the
  first thing that is not `(base, folds)`. They survive `R` but not the session; a save
  system is what they need next.
- Lights do not cast shadows: they pass through walls. Occluders would have to be
  re-derived per fold and would want to soften the seam, which the art is currently
  committed to keeping hard.
- The tilesheet is generated in code, so the world looks systematic rather than
  authored. The layout is fixed and a drawn sheet drops in without code changes.
- The pin/trigger wing lives in **east**, not west, and is reached through a door.
  West's four authored beats depend on its exact geometry and infinite creases make
  a pin a global veto on a band of folds, so nothing was placed there without
  playtesting. See the note in `scripts/world/README.md`.

---

## For detailed information

- [AGENTS.md](AGENTS.md) — start here: architecture, layering, critical decisions
- [scripts/world/README.md](scripts/world/README.md) — controls and design beats
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design decisions & rationale
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — workflow, testing, pitfalls
- [docs/REFERENCE.md](docs/REFERENCE.md) — code map
