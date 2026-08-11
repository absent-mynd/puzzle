# Architecture & Design Decisions

**Purpose:** *why* the code is shaped the way it is. For *where* things live, see
[REFERENCE.md](REFERENCE.md). For onboarding, see [AGENTS.md](../AGENTS.md).

**Last Updated:** 2026-08-04

> **History note.** This document was rewritten during the 2026-08-04 consolidation.
> The decisions it used to record — the hybrid grid-polygon cell system, the
> null-piece system, LOCAL-vs-WORLD cell coordinates, strict undo ordering,
> tessellation for multi-seam cells — described the top-down grid build, which no
> longer exists. They are preserved in git history at `8bf8193`
> (`topdown-archive`).

---

## Core philosophy

**The world is a sheet of paper with rules, not a grid of tiles with special cases.**

Every decision below follows from taking that literally. A fold is a physical
operation on a sheet; if the model can express "this part of the paper is now
somewhere else, and it is still the same part of the paper," then almost everything
else — riding flaps, being pinched inside a fold, doors that travel with the terrain,
entities cut in half — falls out without special-casing.

---

## Decision 1: Derive, never mutate

**State is `(BaseGrid, Array[Fold])`. Everything else is a pure function of it.**

`FoldReplay.derive_pieces(base, folds)` replays the fold list over the immutable base
grid and returns a fresh piece list. There is no in-place mutation in the kernel.

**Why:** the predecessor was ~2000 lines of in-place mutation that had to implement
*unfold* as a hand-written inverse of every forward operation — reversing shifts,
restoring removed cells, re-merging split pieces, reconciling cut lines. Each fix
broke a neighbouring case. Under derive/replay, unfold is:

```gdscript
folds.erase(f)      # drop it
rebuild_world()     # re-derive
```

There is no inverse to get wrong, no snapshot to go stale, and no ordering constraint
— any fold can be removed at any time.

**Cost:** re-deriving is O(pieces × folds) on every change, and it is the most
expensive thing the game does. Measured 2026-08-11 on the shipped region (792
pieces, headless): one replay of one fold is **~15 ms** — the clip is
Sutherland-Hodgman per piece, so the O() is not a formality. A whole `do_fold`
is ~68 ms, about four frames at 60fps, masked by the 0.24 s fold animation.

> An earlier version of this paragraph said "at current world sizes this is
> microseconds and not worth optimizing." That was wrong by four orders of
> magnitude, and it is the sentence that would stop someone profiling here. It is
> corrected rather than deleted because the mistake is instructive: the decision is
> still right, and the number attached to it was never checked.

**This does not change the decision.** The cost buys the property the decision
exists for — no inverse to get wrong, no snapshot to go stale, no ordering
constraint — and that property has already paid for itself several times over.

**Where the remaining cost is, if you come here to optimize.** A fold used to clip
every piece *twice*: `capture_strip` and `apply_one_fold` are the same loop over
`CollisionCore.fold_polygons`, keeping different parts of the same answer.
`FoldReplay.fold_and_capture` now does it once, which took a fold from ~82 ms to
~68 ms with no cached state. What is left is ~16 ms of clip and ~17 ms of view
rebuild (terrain batch + collision shapes).

**What has been tried and does not work.** Pooling the `CollisionPolygon2D` nodes
instead of recreating them is *slower* (5.7 ms vs 4.2 ms — assigning `.polygon` on a
parented node triggers the same physics-shape rebuild). Caching `TileAtlas.uv_for`
by base polygon is *slower* (8.5 ms vs 3.8 ms — hashing the polygon costs more than
the computation it saves), even though 95% of pieces do keep their base polygon
through a fold. Rediscovering *what changed* by comparing geometry costs more than
recomputing it.

**The one real option left**, and the reason it has not been taken: `do_fold`
already holds the derived list that `rebuild()` then recomputes, so handing it over
would save another ~15 ms. It is safe *today* — every mutator guards on
`animating()`, and `_reset` cancels a pending finalize — but it would make those
~16 scattered guards load-bearing for the correctness of the rendered world rather
than merely for input sanity, and no test would catch a future path that missed
one. That is the snapshot this decision exists to avoid. Take it only with a test
that pins the invariant.

---

## Decision 2: `src_offset` — the invariant that makes transport exact

**Every derived piece satisfies `polygon == base_polygon + src_offset`.**

That one invariant is the load-bearing element of the whole design:

```
current point ──(subtract its piece's src_offset)──► base point
base point ──(find the piece with the same base_id containing it)──► any other configuration
```

`BaseFrame` is that round trip. It is how the player rides a flap through a fold, how
a pinned anchor survives being carried into a subspace and back out, how a door
resolves its partner's *current* location, and how a trigger's authored anchors
follow whatever earlier folds did.

**The alternative we rejected:** crease arithmetic — classify a point by which side of
the fold it is on, then apply that side's shift. Simpler, and it works for one fold.
It does *not* compose: after two folds a point's displacement depends on which
pieces it passed through, not on its position relative to either crease. Crease
math survives in `WorldCore.fold_shift_for_side` as a fallback for points over
**void**, where there is no piece to ask.

---

## Decision 3: Meet-in-the-middle folds

A fold orders its anchors (`anchor_a` = lexicographic min by `(y, x)`), excises the
strip strictly between their creases, and slides **both** flaps inward by integer
half-shifts so they meet at a common line. The seam sits at
`anchor_a + shift_a_grid`.

**Why both flaps rather than one:** it makes the fold symmetric, so the operation does
not privilege whichever anchor you happened to place first, and the seam lands
predictably between them. Integer half-shifts keep everything grid-aligned, which
keeps `plane_pos` meaningful and lets the door and anchor machinery work in cell
coordinates.

**Consequence — infinite creases.** A crease is a full line, not a segment, so a fold
excises a strip across the entire world. Close a pit here and a structure on the far
side of the map loses the same strip. **This is deliberately unresolved.** It is the
strongest argument for barrier-scoped fold regions, and the design position is that it
should be *felt* in play before it is engineered away. Do not quietly fix it.

---

## Decision 4: Subspaces are real places, derived the same way

A fold's excised strip is not deleted — it is captured (`WorldCore.capture_strip`) as
a real piece list retaining `base_id` and `src_offset`. Being pinched into a fold
enters that list as a *level* with the same rules as the outside: you can fold within
it, and interior folds persist into the world when you exit.

**Why this needed no new machinery:** a subspace's base pieces are just the parent's
strip content, and its fold list is just another `Array[Fold]`. So
`FoldWorld._compute_level(path)` derives any level — world, strip, or interior of an
interior — by the same replay. Recursion came free because the strip kept its base
identity.

---

## Decision 5: The tile registry owns per-type behavior

`TileTypes` is the single authority for what a tile type *is* and *does*: walkable,
merge rank, `blocks_fold`, `blocks_anchor`, `on_enter`.

**Why:** before it existed, the type int was switched on in ~6 places (merge priority,
walkability, collision, colour, anchor validation), so adding a tile type meant
editing every site — and forgetting one meant a subtle bug. Now a new tile is one row
in one table.

The discipline this asks for: **do not write `if piece.type == TileTypes.WALL`.**
Write `TileTypes.is_walkable(piece.type)`. The collider-building loop in
`FoldWorld.rebuild_world` follows this, which is why `PIN` and `UNANCHORABLE_WALL`
collide correctly without that loop ever having heard of them.

---

## Decision 6: Uniform unfold blocking

A fold cannot be unfolded while a **newer** fold's excision strip crosses its seam
segment. The same test against a fold's two glue lines gates exiting a subspace.

**Why one rule:** the naive alternative is a stack discipline (only unfold the newest
fold). Simpler, but far less interesting — it forbids legal, comprehensible
configurations, and it cannot express the situation that makes subspaces tense: an
interior fold whose creases are not parallel to the glue *locks you inside* until you
undo it. One geometric predicate, applied at every level, produces that for free.

---

## Decision 7: No undo — respawn instead

The predecessor had Baba-style global undo: a step log replayed from a prefix. It was
good, and it does not survive the pivot.

**Why it cannot be kept:** an undo log needs discrete, enumerable steps to reverse. A
continuous physics world has no such step — the player's position changes every frame,
mid-jump, mid-collision. Recording a transform per frame is not an undo model, it is a
replay buffer.

**What replaces it:** unfold is already the in-world inverse of fold, and it is a
*mechanic* rather than a correction — walking to a seam and undoing your own fold is
part of the traversal vocabulary. For actual mistakes, respawn. Save points are the
open work item.

**What this cost:** triggered folds used to be undoable for free (dropping the
authored step re-derived the prefix without the cascade). They are now applied
directly and stay applied. `TriggerResolver` keeps the properties that made the
cascade safe — fire-once guard, per-channel idempotence, bounded fixpoint — because
those were never about undo.

---

## Decision 8: Sutherland-Hodgman for polygon splitting

Industry-standard convex clipping, used by `CollisionCore.fold_polygons` to split each
piece by the two crease lines into up to three parts (A-side, between, B-side).

**Why:** simple, robust for convex clip regions (a crease half-plane always is), and
predictable in the degenerate cases (vertex exactly on the line, edge collinear with
it) given an epsilon. Pieces stay convex under repeated folding, so it composes.

**The epsilon discipline:** `GeometryCore.EPSILON = 0.0001`. Never compare floats with
`==`. Grazing a crease must not count as crossing it — which is why
`WorldCore.segment_intersects_strip` uses a half-pixel margin. Without it, a fold whose
seam merely *touches* another's strip would spuriously block unfolding.

---

## Decision 9: Layering — the kernel never sees the world

```
scripts/model/ + scripts/utils/   ← pure, headless
        ▲
scripts/world/                    ← view, physics, input
```

**Why it is worth enforcing:** the kernel holds the real invariants and the real test
coverage, and it is testable precisely because it has no scene tree. The moment a
model file imports `WorldCore`, that property is gone.

This is why `BaseFrame` lives in `scripts/model/` rather than inside `WorldCore` where
it started: `TriggerResolver` needs exact point transport during a pure derivation.
Extracting the pure part was the fix; importing upward would have been a cycle.

---

## Decision 10: Anything in the world is an occupant; rendering asks base space

Doors and lights do not store a world position. They store a **base identity plus a
point inside that tile**, and where they are is a question asked of the current
piece list through `BaseFrame`. `LightSource` is the second instance of the
pattern, and it is what makes the design work read as inevitable rather than
implemented: a lamp folded away is not in the overworld, and the same lamp is what
lights that fold's interior. Nobody wrote either behaviour — both are the answer to
"where are you?" in two different configurations.

The one place the two differ is strictness. A door resolves with
`resolve_base_point` and goes **dormant** when its point sits exactly on a cut:
there is no unambiguous side to arrive on. A light resolves with
`world_point_from_base` and keeps burning on whichever half its point landed in,
because a light has no such ambiguity to resolve.

**Rendering follows the same rule.** A piece's tile art, its variant and its
edge kind all come from base space (`TileAtlas.uv_for` sends each vertex back
through `src_offset`), so a tile looks identical however it has been folded,
ridden or cut — and a crease cuts the *art* exactly as it cuts the geometry. That
is what keeps the seam a hard line for free, rather than as a special case.

**Why the render pass lives in `scripts/world/`:** it is view. `LightSource` is
kernel because it is data plus a `BaseFrame` question; `LightRig`, `TileAtlas` and
`PixelArt` are the view that draws the answer. The layering rule (Decision 9) is
unchanged.

---

## Implementation patterns

**Validate before folding.** `WorldCore.fold_blocked_by_tile` (pins) and
`can_anchor_at` (unanchorable tiles) gate a fold before it is applied. Both consult
the registry rather than checking types.

**Depenetrate after riding.** The physics server only sees rebuilt colliders on the
next frame, so ride placement must be pure geometry. `WorldCore.depenetrate` searches
upward first (a flap that lands a floor under you should read as "standing on the new
ground"), then sideways, then slightly down. If nothing fits, the fold is refused
rather than leaving the player inside a wall.

**Test-driven.** Write the test first; the suite is the behavioral spec. The
scene-driven `test_fold_world.gd` is what catches integration regressions.

---

## What is deliberately still open

- **Fold extent** (infinite creases) — see Decision 3.
- **No nested pinch:** you cannot fold yourself deeper while already inside a fold.
- **Triggers are world-level only:** firing inside a subspace would require splicing
  folds into an interior list mid-cascade.
- **Unfold animation** plays only for newest-fold unfolds at world level; the reverse
  transform is exact only there.
- **Lights do not cast shadows,** and the seam is not lit or blended specially.
  Occluders would have to be re-derived per fold and would want to soften the seam,
  which is the one thing the art is currently committed to keeping hard.
