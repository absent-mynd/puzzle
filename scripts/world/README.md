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

Two folds can **meet in the same cell**, and then one diamond stands for both.
F there acts on the newest fold that can actually come out — not the first in
fold order, which is precisely the one the newer fold is blocking (see
`FoldWorld.aimed_fold`). The diamond is drawn once per cell and reads unblocked
whenever F would do something, so the marker never promises what the act
refuses.

**Inside a fold, the same rules apply.** The subspace is a real place: the
pinch fold is applied to the world, and the outer fold's two anchors coincide
at one point on the glue line — the white diamond. F there unfolds the
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

## The camera

The frame is not a fixed lens — it opens and closes with what the moment is
about, and it only ever opens (resting is the tightest it sits, so it never
closes in on you unasked):

- **Speed.** Running widens it a little, falling hard widens it a lot. A long
  drop is the one move where the frame you have is certainly not the frame you
  need.
- **The fold you are composing.** Pin an anchor and walk away, and the view
  opens to keep it on screen. The camera is showing you how big the fold has
  got — that span *is* the decision you are about to make.
- **The band you are inside.** In a subspace the strip is framed glue to glue,
  so a wide band reads as the cylinder it is rather than a corridor with no
  visible walls.
- **A fold rearranging the world.** The transition steps the camera back so you
  watch the space move, then settles.

Zoom eases much more slowly than the follow does — a frame that resizes as
briskly as it pans reads as breathing rather than attention. `PlayerBody` owns
the camera, `WorldCore.camera_zoom_for` decides the target, and
`FoldWorld._camera_focus` is the list of things it would be a mistake to leave
off screen. Hard relocations (respawn, doors) cut the zoom along with the
position — easing it would read as the new room inflating.

**And the frame leads where you are going.** Zoom decides how *much* to show;
lookahead decides *where to centre it*. Sitting the body dead centre spends half
the frame on ground you have already crossed, which is the wrong half. So the
view sits ahead of you, and the asymmetries are the design:

- **A fall leads much further than a rise.** A fall is committed and its landing
  is the thing you need to see; the top of a jump is about to reverse, and
  leading hard there would swing the frame back a moment later.
- **Holding a look key leads on its own.** The same W/S that aim an anchor lean
  the frame, so pressing up to point up shows you what you are pointing at —
  wanting to see up there is a thing you can ask for without moving.
- **Inside a fold the lead is flat along the band.** The strip repeats along the
  crease normal, so the frame already shows every copy there is that way; leading
  along it would slide the view across identical bands for nothing.

The lead eases even more lazily than the zoom, because it *flips sign* the
instant you turn around: eased, a reversal reads as the view swinging round to
your new heading instead of whipping across the body. It is capped, and a hard
relocation cuts it along with the lens. `WorldCore.camera_lookahead_for` is the
pure decision; the body supplies its own velocity-as-a-fraction-of-its-limits
(`motion_fraction`) and the held look keys (`look_dir`).

One ordering matters: the lead is decided *before* the zoom, because the lead
moves the camera and the zoom's focus distances are measured from where the
camera ends up. The other way round, a hard lead would quietly crop the very
things the focus set exists to keep on screen.

**Zoom here is a *logical* zoom, and the Camera2D's own zoom never changes.**
Opening the frame resizes the pixel render target instead of moving the lens —
otherwise the tileset would be resampled and the pixel art would go soft. See
*Art & light → The pixel pass* for why, before changing anything about zoom.

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

1. **Ride a fold.** Cross the wide pit by folding it away: pin one rim (Q), then
   the other (E), then commit (F). You ride your flap; the seam diamond marks
   the meeting line. Press U near it and you ride the unfold back. Also try a
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
   press U. The fold springs open and you emerge **where you walked to** —
   fold, dive, surface: movement through the inside of a fold.
4. **Break the sealed chamber.** With arm's-length anchors, sealed means
   sealed — no straight fold can excise its shell, because one anchor would
   have to be pinned from inside. Diagonal folds are the crack in that logic:
   a fold pinned from two *outside* positions at different heights can lay a
   slanted band across the chamber's corner and bite it off. One of the two
   anchors has to be pinned mid-jump. (Note the fold stays active: unfold it
   from inside and you've sealed yourself in.)
5. **Meet a fold you cannot make, and one you don't have to.** Through door W2,
   in the east region — see the next section.

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

## Art & light

The world is drawn as **pixel art with dynamic lighting**. Both are style, not
mechanics: nothing about folding, collision or reachability changed, and an
unlit corner is exactly as navigable as a lit one.

### The pixel pass

Everything in the world renders into a **low-resolution SubViewport** that is
scaled up with nearest filtering (`PixelArt`). World coordinates did not change —
a cell is still 64 units and every physics constant is untouched — so one art
pixel is 4 world units and a cell is 16 art pixels. At 1:1 the target is 320×180.

**The camera's lens never moves, even though the zoom is dynamic.** These are the
two facts that have to coexist, and the way they do is worth knowing before you
touch either: inside a render target, the size of an art pixel is purely a
function of camera zoom. Move the lens and a 16px tile stops covering 16 target
pixels — the atlas gets resampled and the world goes soft, which is the one thing
this pass exists to prevent.

So "the frame opens" is answered with **more pixels, not a wider lens**:
`PixelArt.target_size` gives the resolution a given logical zoom needs, and
`FoldWorld._size_pixel_view` resizes the target as the zoom eases. World-per-art-
pixel stays 4.0 at every zoom, so a cell always spans a whole tile. The camera's
`zoom_target` is therefore a *logical* zoom — it sizes the buffer; `_cam.zoom`
stays pinned at `PixelArt.CAMERA_ZOOM` forever.

- **Tiles come from a 16px tileset** (`TileAtlas`, and `assets/sprites/README.md`
  for the layout). Fragments are textured through **base-space UVs**: a fragment
  is sent back to its base tile by subtracting `src_offset`, so it carries the
  patch of art it was cut from. A tile's variant is hashed from its `base_id`,
  and the "open sky above" edge tile is read from the base grid — so a tile's
  look never changes because it was folded, ridden or cut.
- **The seam stays a hard line.** Because the art is cut by the crease exactly
  as the geometry is, two flaps meeting at a seam show two tiles cut mid-pattern
  against each other. Nothing blends, blurs or fades across it. That is
  deliberate for now.
- **The HUD is outside the pixel viewport**, at window resolution, so text stays
  legible over chunky tiles. So are the overlay's markers — they are drawn
  unlit, because what you navigate by must never dim.

### Lights

A light is an **occupant of the sheet**, stored the way a door is: a base tile
identity plus a point inside it (`LightSource`). It has no world position; where
it burns is a question asked of the current fragment list. Everything follows
from that:

- Fold a lamp's tile away and it is **gone from the overworld** — no glyph, no
  light — and the same lamp is what **lights the fold's interior** when you get
  in there.
- Fold something else and the lamp **rides its flap**, like any other occupant.
- Split its tile with a crease and it keeps burning on whichever half it landed
  on. (A door in that position goes dormant; a light has no ambiguity to resolve.)

Lighting is evaluated **per art pixel**: the shaded point and the light position
are both snapped to the pixel grid, the accumulated intensity is quantized into
bands, and the band edges are ordered-dithered — so light arrives in chunky
rings rather than as a smooth glow. Ambient is generous on purpose.

Where the shipped lights are, and what each is for:

| Light | Region | Shows you |
|---|---|---|
| `w_spawn` | west | the ordinary case — and it rides the flap when you fold the pit |
| `w_pit` | west | fold the pit shut and it leaves the world with the pit; get pinched in and it is in there with you |
| `w_chamber` | west | the sealed chamber glows through its own shell — there is something in there |
| `e_vault` | east | inside east's pre-placed fold: invisible from the overworld, and the only thing lighting the vault when you arrive through door W1 |
| `e_reward` | east | over the reward the pressure plate opens |

Authoring, per region in `worlds/overworld.json`:

```json
"lights": [
  {"id": "w_spawn", "cell": {"x": 3, "y": 13}, "color": "#ffd08a",
   "radius": 5.0, "energy": 1.0, "flicker": 0.12}
]
```

`radius` is in **cells**; `offset` (cell units, default centre) places the lamp
within its tile; `flicker` is the idle amplitude, 0 for a steady lamp.

**No occlusion.** Lights pass through walls. Shadow casters would have to be
re-derived per fold and would want to soften the seam, which is exactly what we
do not want yet.

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
- Lights do not cast shadows, and the seam is not lit specially — see *Art & light*.
- The player and the overlay markers are drawn unlit, so they never disappear
  into an unlit corner.

## Files

- `WorldCore.gd` — pure logic (map parse, side classification, strip capture, seam
  and glue segments, depenetration, anchor/fold eligibility, camera zoom and
  lookahead). Covered by `scripts/tests/test_world_core.gd`.
- `FoldWorld.gd` — scene driver: derived geometry → textured Polygon2D + colliders,
  fold/unfold with player riding, subspace enter/wrap/exit, regions, doors,
  triggers, and the pixel render target (which it resizes as the zoom changes).
- `PlayerBody.gd` — CharacterBody2D blob (coyote time, jump buffer, squash) and
  the pixel-snapped camera, whose smoothing is driven here so the wrap can
  displace it by a whole band width without losing its lag. Its camera-facing
  readings (`look_dir`, `motion_fraction`, `motion_intensity`) are covered by
  `scripts/tests/test_player_body.gd`.
- `WorldOverlay.gd` — anchors, strip preview band, seam markers, glue lines.
  Everything point-like repeats across the wrap copies (`_copy_offsets`); seam
  diamonds are one per meeting CELL, since folds can share one
  (`FoldWorld.seam_markers`). Stroke widths are multiples of one art pixel.
- `PixelArt.gd` — how big an art pixel is; the one place that says so, including
  the target size a given zoom needs (`target_size`).
- `TileAtlas.gd` — the tileset: kinds, variants, and base-space UVs for fragments.
- `LightRig.gd` — lit materials, per-frame light uniforms, lamp glyphs.
- Scene flows in `scripts/tests/test_fold_world.gd`.
