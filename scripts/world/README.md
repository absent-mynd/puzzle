# The World — controls & design beats

The side-view gravity world: `FoldWorld` drives the fold kernel (`BaseGrid` /
`Fold` / `FoldReplay` / `CollisionCore` / `BaseFrame`) with a physics player over
colliders generated from derived fragments.

## Run it

`scenes/world/World.tscn` is the project's main scene, so just press play. Or from
a terminal:

```bash
godot --path . res://scenes/world/World.tscn
```

The world is authored in `worlds/overworld.json` — regions of ASCII terrain, doors
between them, and pre-placed folds. See `scripts/model/WorldData.gd` for the format
and `WorldCore.CHARS` for the terrain characters.

## Controls

| Input | Action |
|---|---|
| A/D or ←/→ | move (also sets your facing) |
| Space | jump |
| hold W/↑ or S/↓ | point up / down (otherwise you point where you face) |
| **tap F** | pin **anchor 1** (orange), then **anchor 2** (blue), then **commit** the pair as a fold |
| **hold F** | **pull back**: your own anchor if you point at it, the fold under a seam diamond, the subspace's white glue diamond (exit) — or, pointing at nothing, your last anchor |
| R | reset |

One key, two directions. **Tap pushes an anchor in; hold pulls one back out.**
That is the whole verb, and it is the whole economy too — see below. A filling
amber ring around the cell you point at shows a hold building, so the two
gestures are never ambiguous while the key is still down.

Anchor placement is **embodied**: both anchors must be pinned from somewhere
you can stand (or jump — mid-air placement works), so folding is gated by
reachability. Placement and commitment are separate acts: pin both anchors,
then choose where to be standing before the committing tap — inside the red
band to be folded in, outside it to ride a flap. Anchors must be 2+ tiles
apart in any direction (off-axis pairs make diagonal creases); a second anchor
placed too close to the first is refused *when you place it*, because the next
tap would otherwise be a commit that cannot fire.

There is **no remote unfold**. The anchors in a fold are exactly where you left
them, so getting them back means walking to its seam diamond and holding.

## Anchors are a resource

An anchor is an **object you carry**, not an ability you have. A fold standing
in the world is holding two of yours — the seam diamond is where they went.

- Your allowance is `anchor_capacity` in `worlds/overworld.json` (4 = two folds).
- Pinning charges one **immediately**; the HUD count drops as you place.
- Committing charges nothing more — the fold takes the same two anchors you
  already pinned.
- **Unfolding refunds in full.** Nothing is ever destroyed, only committed.
- Out of anchors? The aim ring turns red and taps stop pinning.

So the budget is not *how many folds may you ever make* but **how many folds
may stand at once**. Crossing a pit costs nothing permanent: fold it, walk
across the seam, unfold behind you, keep your anchors. What costs you is a fold
you must **leave standing** — a wall folded away, a chamber you are inside, a
door jammed shut. You cannot take your bridge with you.

**Anchor caches** (`A`, orange tiles) raise the ceiling permanently by 2 —
one more fold left standing, for good. Because anchors are conserved rather
than spent, granting anchors and raising capacity are the same act. A cache
that got folded away is not lost: it is inside the fold, and collecting it in
there counts. Collected caches stay in the world as dimmed husks.

`AnchorStock` owns the arithmetic and stores nothing: held anchors are summed
from the live fold lists, so unfolding refunds simply by removing the fold.

**Inside a fold, the same rules apply.** The subspace is a real place: the
pinch fold is applied to the world, and the outer fold's two anchors coincide
at one point on the glue line — the white diamond. Holding F there unfolds the
subspace (exit). You can pin anchors and fold *within* the subspace; interior
folds persist into the world when you exit, and pending anchors ride along
and land where the strip content lands. **Unfold blocking** applies
everywhere: a fold cannot be unfolded while a newer fold's band crosses its
seam — so an interior fold that crosses the glue (its creases are not
parallel to the outer fold's) locks the exit until you unfold it; the white
diamond turns red to show it. Player and anchors move by **exact base-tile
riding** (each fragment knows its base identity and offset), not approximate
crease math. Folds and unfolds animate: flaps slide, the strip collapses
onto — or springs from — the seam.

## Regions & doors

The world is now **two regions** (west and east), each its own sheet with its
own persistent fold state. **Doors are warp points** (green rings) at
base-tile centers — they ride folds with their tile, and walking into one
warps you to its partner, wherever that partner currently *is*:

- Partner in normal space → you arrive there (camera snaps, region loads).
- Partner **folded away** → you arrive INSIDE that fold's subspace. The east
  region ships pre-folded: the door near the west spawn leads straight into
  a fold you've never seen open (there's a goal in there too). The far-right
  west door leads to east's normal space, where the shipped fold's seam
  diamond is visible — unfolding it from outside is the other way in.
- Partner's tile **split exactly through its center** → the door is dormant
  (no glyph, traversal refused) until the halves rejoin.
- Landing blocked (something folded over the door) → traversal refused: you
  can *jam doors shut by folding* and clear them by unfolding.

Doors exit subspaces **without unfolding them** — interior folds and all
persist for the next visit. The glue anchor (white diamond) remains the
unfolding exit. Pending anchors are inert outside their region but stay
pinned and resolve again when you return.

## What to try (the beats)

1. **Ride a fold.** Cross the wide pit by folding it away: tap F on one rim, then
   on the other, then once more to commit. You ride your flap; the seam diamond
   marks the meeting line. Walk over it, hold F, and you ride the unfold back —
   and get both anchors back, because you no longer need the pit closed. Also try a
   *vertical* fold (same column): fold the sky down / the floor up to climb —
   this is the gravity-specific verb.
2. **Get folded in.** Stand *inside* the red preview band and commit the fold:
   instead of blocking, the fold swallows you. You're inside the excised strip,
   rendered repeating across the glue lines (cyan) — **and so are you.** Every
   visible copy of the strip shows you at the same place in its own band,
   because they are all the same band: the strip is a cylinder and you are one
   point on it. Walking "through" a glue line slides body and camera together
   by exactly one band width, so the frame does not change and the crossing is
   invisible — there is no seam to cross, only a lap to finish.
3. **Dive-traverse.** While inside, walk somewhere else along the strip, then
   hold F on the white glue diamond. The fold springs open and you emerge
   **where you walked to** — fold, dive, surface: movement through the inside
   of a fold.
4. **Break the sealed chamber.** With arm's-length anchors, sealed means
   sealed — no straight fold can excise its shell, because one anchor would
   have to be pinned from inside. Diagonal folds are the crack in that logic:
   a fold pinned from two *outside* positions at different heights can lay a
   slanted band across the chamber's corner and bite it off. One of the two
   anchors has to be pinned mid-jump. (Note the fold stays active: unfold it
   from inside and you've sealed yourself in.) This is the beat where the
   economy bites: being in there means **leaving that fold standing**, so two
   of your anchors stay in its seam the whole time you are inside. The cache
   next to the goal pays them back.
5. **Pay for the climb.** The vertical fold onto the pillar top (beat 1) has a
   cache waiting at the summit. Folds that open new ground are how you afford
   the next fold.
6. **Meet a fold you cannot make, and one you don't have to.** Through door W2,
   in the east region — see the next section.
7. **Find a cache inside a fold.** Through door W1: you arrive inside east's
   shipped pre-fold, and there is a cache in there with the goal. Folded-away
   space is real space, and it holds real things.

## The pin & plate wing (east)

Past door **W2** you arrive in the east region near door E2. Walking right from
there is a short teaching run for the two behavioural tile types:

- **The pinned pillar** (red, base x21). A `PIN` cannot be stood on **and no fold may
  excise or cut it** — try to fold across it and the commit is refused
  ("Something in that span refuses to fold."). It is two tiles tall, so the way past
  is to *jump it*: the thing that blocks your fold is also your stepping stone. This
  is the tile that says **route around, do not erase**.
- **The pressure plate** (pink, base x25) and the wall it opens (base x27). The wall
  is three tiles tall — above jump height — so folding is the only way through, and
  you do not do the folding: stepping on the plate fires a `TRIGGER_FOLD` that
  excises the wall's band. The reward sits behind it.

Two details worth noticing, because both fall out of the model rather than being
special-cased:

- The plate's fold **rides you and door E2 with it** — the whole A-side flap moves,
  so when you walk back the door is one cell right of where you left it.
- The plate's fold **refuses to cut the pillar**. A trigger is not a back door around
  a pin; `TriggerResolver` runs the same fold-block predicate a player commit does.

The triggered fold is persistent world state like any other: leave the region and
come back and the wall is still open.

## Why the west region has no pins

Fold extent is infinite-crease (see below), which makes a pin a **global veto on a
band of folds** — a pin anywhere in a column forbids every horizontal fold spanning
it, at any height. West carries the four authored beats and its geometry is load
bearing for all of them, so pins went in east, where there is room to be wrong.
Placing them in west is a playtesting job, not an editing one.

## Current limits (deliberate)

- No nested pinch: you cannot fold yourself deeper while already inside a
  fold (the fold is blocked with a message).
- Fold extent is the whole world (infinite-crease semantics) — deliberately
  kept so the "a fold over here guts a structure over there" problem is
  *feelable*; it's the live design argument for barrier-scoped fold regions.
- Unfold animation plays only when the unfolded fold is the newest (the
  reverse transform is exact only there); mid-stack unfolds are instant.
- Movable seams are design-agreed but not implemented.
- Triggers only fire at world level — a trigger inside a subspace would have to
  splice folds into an interior list mid-cascade, which the resolver does not model.
- Unanchorable tiles (`_`, `X`) and occupants are supported by the format and covered
  by tests, but the shipped world does not place any yet.
- **You can strand yourself.** Spend your last anchors on a fold, walk somewhere
  its seam cannot be reached from, and there is no way back to them but `R`.
  This is the accepted cost of having no remote unfold; save points are the real
  answer and do not exist yet.
- Anchor caches are collected per region into runtime state (`regions[id].collected`)
  — the one piece of world state that is not `(base, folds)`. It resets with `R`
  and will need the save system to outlive a session.

## Files

- `AnchorStock.gd` (kernel) — the anchor ledger: conservation arithmetic, nothing
  stored. Covered by `scripts/tests/test_anchor_stock.gd`.
- `WorldCore.gd` — pure logic (map parse, side classification, strip capture, seam
  and glue segments, depenetration, anchor/fold eligibility). Covered by
  `scripts/tests/test_world_core.gd`.
- `FoldWorld.gd` — scene driver: derived geometry → Polygon2D + colliders,
  fold/unfold with player riding, subspace enter/wrap/exit, regions, doors,
  triggers, the tap/hold verb and the anchor ledger.
- `PlayerBody.gd` — CharacterBody2D blob (coyote time, jump buffer, squash) and
  the camera, whose smoothing is driven here so the wrap can displace it by a
  whole band width without losing its lag.
- `WorldOverlay.gd` — anchors, strip preview band, seam markers, glue lines.
  Everything point-like repeats across the wrap copies (`_copy_offsets`).
- Scene flows in `scripts/tests/test_fold_world.gd`.
