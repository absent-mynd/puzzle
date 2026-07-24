# Gravity / Metroidvania Fold Prototype

A playable proof-of-concept for pivoting the game from discrete sokoban
puzzles to a physics-enabled explorable world. It reuses the real fold model
(`BaseGrid` / `Fold` / `FoldReplay` / `CollisionCore`) **unchanged** — only the
view/entity layer is new, which is the architectural claim being tested.

## Run it

Open the project in the Godot editor, open
`scenes/prototype/FoldPrototype.tscn`, and press **Play Scene** (F6). Or from
a terminal:

```bash
godot --path . res://scenes/prototype/FoldPrototype.tscn
```

## Controls

| Input | Action |
|---|---|
| A/D or ←/→ | move (also sets your facing) |
| Space | jump |
| hold W/↑ or S/↓ | point up / down (otherwise you point where you face) |
| Q | pin **anchor 1** (orange) on the cell you point at — re-pin moves it, same spot clears |
| E | pin **anchor 2** (blue), same rules; anchors must be 2+ tiles apart, any direction (off-axis pairs make diagonal creases) |
| F | **interact**: commit the pinned pair as a fold — or, aimed at (or standing on) a seam diamond, unfold that fold |
| Esc | clear both pending anchors |
| U | unfold newest fold (or exit the subspace) |
| R | reset |

Anchor placement is **embodied**: both anchors must be pinned from somewhere
you can stand (or jump — mid-air placement works), so folding is gated by
reachability. Placement and commitment are separate acts: pin both anchors,
then choose where to be standing before pressing F — inside the red band to
be folded in, outside it to ride a flap. Any active fold can be unfolded by
walking up to its seam diamond (where its two anchors met) and interacting.

## What to try (the three beats)

1. **Ride a fold.** Cross the wide pit by folding it away: click one rim, then
   the other. You ride your flap; the seam diamond marks the meeting line.
   Press U while standing near it and you ride the unfold back. Also try a
   *vertical* fold (same column): fold the sky down / the floor up to climb —
   this is the gravity-specific verb.
2. **Get folded in.** Stand *inside* the red preview band and commit the fold:
   instead of blocking, the fold swallows you. You're inside the excised strip,
   rendered repeating across the glue lines (cyan) — walk "through" one and
   you wrap around the cylinder seamlessly.
3. **Dive-traverse.** While inside, walk somewhere else along the strip, then
   press U. The fold springs open and you emerge **where you walked to** —
   fold, dive, surface: movement through the inside of a fold.
4. **Break the sealed chamber.** With arm's-length anchors, sealed means
   sealed — no straight fold can excise its shell, because one anchor would
   have to be pinned from inside. Diagonal folds are the crack in that logic:
   a fold pinned from two *outside* positions at different heights can lay a
   slanted band across the chamber's corner and bite it off. One of the two
   anchors has to be pinned mid-jump. (Note the fold stays active: unfold it
   from inside and you've sealed yourself in.)

## v1 shortcuts (deliberate)

- A pinch fold is never applied to the outside world: you can't see outside
  and exiting would undo it, so the outcome is identical with fewer states.
- Only the newest fold can be unfolded (stack discipline); no folding while
  inside a subspace; axis-aligned anchors only.
- Fold extent is the whole world (infinite-crease semantics) — deliberately
  kept so the "a fold over here guts a structure over there" problem is
  *feelable*; it's the live design argument for barrier-scoped fold regions.
- Exit-at-tile-center seam points, movable seams, and doors are design-agreed
  but not in this PoC.

## Files

- `ProtoCore.gd` — pure logic (map parse, side classification, strip capture,
  depenetration). Covered by `scripts/tests/test_proto_core.gd`.
- `ProtoWorld.gd` — scene driver: derived geometry → Polygon2D + colliders,
  fold/unfold with player riding, subspace enter/wrap/exit.
- `ProtoPlayer.gd` — CharacterBody2D blob (coyote time, jump buffer, squash).
- `ProtoOverlay.gd` — anchors, strip preview band, seam markers, glue lines.
- Scene flows in `scripts/tests/test_proto_world.gd`.
