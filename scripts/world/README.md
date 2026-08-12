# The World — controls & design beats

The side-view gravity world: `FoldWorld` drives the fold kernel (`BaseGrid` /
`Fold` / `FoldReplay` / `CollisionCore` / `BaseFrame`) with a physics player over
colliders generated from derived pieces.

## Run it

`scenes/world/World.tscn` is the project's main scene, so just press play. Or from
a terminal:

```bash
godot --path . res://scenes/world/World.tscn
```

The world is authored in `worlds/overworld.json` — regions of ASCII terrain, doors
between them, and pre-placed folds. See `scripts/model/WorldData.gd` for the format
and `WorldCore.CHARS` for the terrain characters.

**To boot a different world, pass `--world=`:**

```bash
godot --path . res://scenes/world/World.tscn -- --world=testbed
```

A bare name means `res://worlds/<name>.json`; a path is taken as written. The editor
takes the same flag (`./run_editor.sh testbed`), because both read it through
`WorldData.selected_path` — so the game and the editor cannot disagree about which
world a run means.

`worlds/testbed.json` is the **debug world**: fourteen regions holding one of
everything the model can express — every tile character, every hand kind, every
trigger outcome, pre-folds in every orientation, and door cases the shipped world has
no room for (two doors in one cell, a pair inside one region, one split by a crease,
one sealed inside a fold). See [docs/features/TESTBED_WORLD.md](../../docs/features/TESTBED_WORLD.md).

## Controls

| Input | Action |
|---|---|
| A/D or ←/→ | move (also sets your facing) |
| Space | jump — **tap for a hop, hold for full height** |
| hold W/↑ or S/↓ | point up / down (otherwise you point where you face) |
| **tap F** | put a **hand** down on the cell you point at — the second one lights the fuse |
| **hold F** | **release burst**: everything of yours within about a tile and a third comes loose at once |
| R | reset |

One key, two directions. **Tap puts a hand down; hold bursts them loose.** There
is no committing press: put both hands down and the fold goes off by itself.

## Moving

**The jump is variable-height, and how long you hold Space is the input.** Every
jump leaves the floor at the same speed; what you decide on the way up is when to
stop paying for it. Let go and gravity doubles, so the rise is cut short by weight
rather than by having your velocity clipped — which means the height is a
*continuum*, not two jumps:

| Hold | Rise |
|---|---|
| a bare tap | ~1.25 cells — clears a one-tile step |
| ~0.15s | ~2 cells |
| through the whole rise (~0.45s) | ~2.6 cells — clears the two-tile pillar, never the three-tile wall |

Holding past the apex buys nothing: the hold window *is* the rise. And holding
through a landing does not bounce you — a jump needs a fresh press, so the hold
you are spending always belongs to the jump you are in.

Those bounds are **level design, not feel**. The pinned pillar is two tiles because
it is meant to be jumped; the pressure plate's wall is three because it is meant to
need a fold. `PlayerBody.jump_height_for_hold` integrates the real step so the test
suite can pin them — if you tune a gravity constant, that test is what tells you
whether you moved the world.

Two smaller things, both about the frames you actually make decisions in:

- **The apex is lighter.** Near the top of a jump gravity drops to 0.7, which buys
  more of the frames where you are barely moving vertically and entirely occupied
  with where to land — and where the sealed chamber wants a mid-air anchor pinned.
  It costs about 6 units of height, which is why the three-cell wall is still a wall.
- **Letting go in mid-air does not stop you dead.** Air deceleration is much gentler
  than ground deceleration, so a jump keeps the run that launched it. Steering the
  *other* way is unchanged, so nothing you could reach before is harder to reach —
  only stopping in place mid-flight is.

Anchor placement is **embodied**: both hands must be placed from somewhere you
can stand (or jump — mid-air placement works), so folding is gated by
reachability. Any distance apart works, down to neighbouring cells, and off-axis
pairs make diagonal creases.

**Placement asks nothing of the fold.** Put hands wherever there is sheet to pin
to — the only question at placement is whether *something is there*. Whether the
pair makes a fold at all, whether the surface will hold it, whether you have
anywhere to land: all of that is asked **when the fuse fires**.

That is what the fuse is *for*. It is a window in which to make a doubtful fold
work: put both hands down while standing somewhere the fold cannot put you, then
run clear before it goes off and ride the flap instead of being swallowed.

If the fold still cannot go when the fuse runs out, **both hands drop from where
they were pinned** — not back into your slots, not at your feet. They fall from
the spots you chose and land on the floor beneath them. Go and pick them up, or
leave them and pin somewhere better.

There is **no remote unfold**. The hands in a fold are exactly where you left
them, so getting them back means walking to its seam and bursting.

A hand you leave in another region (or sealed inside a fold) is **not a partner
you could finish a fold with**, so the next hand you place starts a fresh pair
instead of being wasted on one that could never fire. The stranded hand waits
where it is until you go back for it — with a burst, or by pairing it with a new
one when you return.

An armed pair **outside the region you are in pauses**. Leave a fold ticking in
west, walk to east, and it waits; come back and it resumes. Leaving one armed
behind you is a thing you can choose to do.

### The burst

Holding F fires a small sphere of influence around your body (`BURST_RADIUS`,
about a tile and a third — tune it in `FoldWorld`). It is **not aimed**: where you stand is
the whole input. Everything of yours inside it comes loose at once —

- unpaired hands you placed come back;
- armed pairs you can reach either half of come apart — what you can reach comes
  back, the far hand falls where it was pinned;
- folds whose seam is in reach come apart, if nothing newer is blocking them;
- inside a fold, the glue anchor in reach is the way out;
- and **any hand with nowhere to go pops into the world at your feet.**

That last clause is what makes the burst safe to fire blind. Nothing is refused
for want of a slot and nothing is destroyed: a hand you cannot catch is a hand
on the ground, the same object an authored one is. A ring shows how far the
burst reached, after the fact — it confirms, it does not aim.

A burst releases the folds that were unfoldable **when it fired**. A stack of
two folds under one diamond clears one layer per press, because releasing the
newer one is what unblocks the older, and one press undoing work you never
asked it to reach would be a surprise.

## Hands

A hand is an **object you carry**, not an ability you have. You have **two
slots**, and that never grows. A fold standing in the world is holding the two
hands you pinned it with — the seam diamond is where they went.

They float beside you as small circles, springing and trailing as you move —
and **drifting slightly even when nothing is happening**, whether they are riding
beside you or lying on the ground waiting to be picked up. A hand is never
perfectly still, because a hand is an object in the world rather than a marker
drawn on it. That is style, not a mechanic: nothing reads their positions, and
the drift is a fraction of the distance you have to be within to pick one up.
What they tell you is how many you have and what **kind** they are.

- Placing a hand takes it out of its slot **immediately**.
- A hand pairs with the last unpaired one **you can currently see**, and the pair
  lights its **fuse**. Both hands pulse, slowly at first and faster as the fold
  comes due, then it folds. No press commits it.
- **Several pairs can be armed at once** — as many as you have hands for. Each
  counts its own fuse, so they go off in the order their fuses run out rather
  than the order you laid them: a swift pair laid second fires before a patient
  pair laid first.
- **Bursting takes back** whatever is in reach. Reaching either half of an armed
  pair breaks the whole pair — the far hand drops where it was pinned, so
  reaching into one always costs you a hand.
- A pair that **fails at the fuse** drops both hands from where they were pinned.
- **Unfolding gives back the same two hands that went in** — kinds and all.
- Hands with nowhere to go **land on the ground** rather than being refused.
- **A loose hand is a physical object.** Let go of one and it *falls* — as a light ball
  with a lot of air drag, so it floats down rather than dropping like a stone. It rolls
  off slopes, pops out of walls it was let go inside, and comes to rest hovering just
  above the ground. That holds however it came loose: a burst, an unfold, a refused fold.
  **You can catch one out of the air**, and a hand still falling is still yours to lose —
  nothing is destroyed mid-flight.

  A fold carries a hand in flight the same way it carries you. **A hand a fold sweeps
  into a strip keeps falling inside the strip**, and because a strip is a cylinder, a
  hand that finds no floor in there *wraps* and goes round again. When the wrap runs
  vertically that is a hand in **orbit**, indefinitely — you can still reach into the
  fold and pluck it out of the air, and it lands the moment a fold puts ground in its way.

  And a hand at rest is not done forever: **fold the ground out from under a hand and it
  falls again.** A fold that only slides its tile carries it, as it always did. So a
  loose hand you remember the position of may not be where you left it after you fold nearby.

So the budget is not how many folds you may ever make but **how many folds may
stand at once** — and with two slots, that is one, until you find more hands.
Crossing a pit still costs nothing permanent: fold it, walk across the seam,
burst behind you, keep your hands.

### Kinds

Hands come in kinds, told apart by **colour**, and a kind changes the **fuse**
of the fold it makes:

| Kind | Colour | Fuse |
|---|---|---|
| `plain` | orange | 1.6s |
| `swift` | cyan | 0.65s |
| `patient` | violet | 3.2s |

A fold may be pinned with **two different kinds**, and its fuse is the mean of
the two — so a mixed pair lands genuinely between its parents rather than being
decided by one of them. That is what makes mixing a decision.

### Hands on the ground

A hand lying in the world is one object, whether the world put it there or a
burst did. Same storage, same rules, **same drawing** — a loose hand looks
exactly like the ones orbiting you, in its kind's colour, because to you it is
the same thing.

Walking over one takes it **into a free slot**, one at a time. A slot is free
because you *put a hand down* — so one is not a stockpile you raid on
the way past, it is the second half of a fold you have already started:

> place a hand → walk to a loose one → take a different kind → place that → the
> fold you finish is not the fold you would have made with the pair you set out
> with.

Walk over one with both hands full and it stays where it is, waiting. Like a
door or a lamp, a loose hand is an **occupant of the sheet**: it stores a base
identity rather than a position, so it rides flaps, folds away with its tile,
and is found again inside the fold.

`HandStock` owns the arithmetic and stores nothing: committed hands are read
off the folds themselves, so unfolding gives them back by removing the fold, and
the four places a hand can be — slot, pinned, in a fold, on the ground — always
sum to the same total. Nothing in the game changes that number.

Two folds can **meet in the same cell**, and then one diamond stands for both.
A burst there takes the newest that can actually come out — not the first in
fold order, which is precisely the one the newer fold is blocking. The diamond
is drawn once per cell and reads unblocked whenever a burst would do something,
so the marker never promises what the act refuses.

**Inside a fold, the same rules apply.** The subspace is a real place: the
pinch fold is applied to the world, and the outer fold's two anchors coincide
at one point on the glue line — the white diamond. A burst in reach of it opens
the subspace (exit), and the diamond lights when you are close enough. You can
pin anchors and fold *within* the subspace; inner folds persist into the world
when you exit, and pending anchors ride along
and land where the strip content lands. **Unfold blocking** applies
everywhere: a fold cannot be unfolded while a newer fold's strip crosses its
seam — so an inner fold that crosses the glue (its creases are not
parallel to the outer fold's) locks the exit until you unfold it; the white
diamond turns red to show it. Player and anchors move by **exact base-tile
riding** (each piece knows its base identity and offset), not approximate
crease math. Folds and unfolds animate: flaps slide, the strip collapses
onto — or springs from — the seam.

## Folding yourself deeper

Being inside a fold does not stop you folding. Stand in the strip of a fold you
make *in there* and it swallows you again, and you are **two folds deep** — and
there is no limit but the hands to do it with. The status line says how deep,
the sheet tints further with every layer, and surfacing by the glue diamond
brings you up **one layer at a time**, unfolding as it goes.

What is worth going in for is what the space becomes. It depends entirely on
which way the second fold runs:

- **With the grain** — the inner creases parallel to the glue you came in
  through — and the inner strip never reaches that glue. You are in a narrower
  strip inside the strip: still a **cylinder**, wrapping one way, with two ends
  you can run off (the fold turns you back).
- **Across the grain** — the inner creases perpendicular — and the inner strip
  spans the outer one glue to glue. Walking along the outer normal still wraps,
  and now walking across it wraps too. You are on a **torus**: every direction
  comes back to where you started, there are no ends at all, and the frame is
  four glue lines rather than two. The status line names it.

- **At any other angle** the outer repetition does not come down at all, and the
  space is a plain cylinder with the inner fold's period alone.

None of that is authored. Which periods survive is one line of geometry — a
translation descends exactly when it runs *along* the new strip — and everything
else (how many copies to draw, where the colliders go, which way the camera
refuses to lead, how you wrap) is read off it. See `FoldLattice`, which sets out
why "a whole number of gaps across" is *not* a weaker condition that also works.

**A fold takes what is in front of it in the sheet it is cut from; it does not
reach around the cylinder.** A strip that runs past its own glue line finds the
end of the stored sheet rather than the next copy of it. What you get is always
really there — the strip is a genuine piece of the space — but for a fold that
is not perpendicular to the one outside it, it is not *everything* that is there.
The preview strip is drawn in every copy (clipped to one), so what you see before
the fuse burns is what the fold will actually take.

A hand committed to a fold three layers down is counted by the same ledger as one
at the surface, and the four places a hand can be still sum to the same number.

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
- **The strip you are inside.** In a subspace the fundamental domain is framed
  glue to glue, so a wide strip reads as the cylinder it is rather than a corridor
  with no visible walls — and on a torus that is all four walls, out of the same
  call.
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
- **The lead is flat along every axis the space repeats on.** A repeating space
  already shows every copy there is that way, so leading along it slides the view
  across identical copies for nothing. One axis inside a fold — and on a torus,
  both, so the lead is the body's own motion and nothing else.

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

Doors exit subspaces **without unfolding them** — inner folds and all
persist for the next visit. The glue anchor (white diamond) remains the
unfolding exit. Pending anchors are inert outside their region but stay
pinned and resolve again when you return.

## What to try (the beats)

1. **Ride a fold.** Cross the wide pit by folding it away: tap F on one rim, then
   on the other. The pair starts pulsing and folds itself — so where you are
   standing when it goes off is a decision, not a keypress. You ride your flap;
   the seam diamond marks the meeting line. Walk over it, hold F, and you ride the
   unfold back — and get both hands back, because you no longer need the pit
   closed. Also try a
   *vertical* fold (same column): fold the sky down / the floor up to climb —
   this is the gravity-specific verb.
2. **Get folded in.** Stand *inside* the red preview strip and commit the fold:
   instead of blocking, the fold swallows you. You're inside the excised strip,
   rendered repeating across the glue lines (cyan) — **and so are you.** Every
   visible copy of the strip shows you at the same place in it,
   because they are all the same strip: the strip is a cylinder and you are one
   point on it. Walking "through" a glue line slides body and camera together
   by exactly one period, so the frame does not change and the crossing is
   invisible — there is no seam to cross, only a lap to finish.
3. **Dive-traverse.** While inside, walk somewhere else along the strip, then
   hold F on the white glue diamond. The fold springs open and you emerge
   **where you walked to** — fold, dive, surface: movement through the inside
   of a fold.
4. **Break the sealed chamber.** With arm's-length anchors, sealed means
   sealed — no straight fold can excise its shell, because one anchor would
   have to be pinned from inside. Diagonal folds are the crack in that logic:
   a fold pinned from two *outside* positions at different heights can lay a
   slanted strip across the chamber's corner and bite it off. One of the two
   anchors has to be pinned mid-jump. (Note the fold stays active: unfold it
   from inside and you've sealed yourself in.) This is the beat where the
   economy bites: being in there means **leaving that fold standing**, so both
   your hands are in its seam the whole time you are inside — and the patient
   hand by the goal is the only one you will have in there.
5. **Finish a fold with a hand you did not set out with.** Put one hand down, then
   walk to a loose hand with the slot it freed: the pillar top has a **swift** hand, the
   sealed chamber a **patient** one. The pair you finish with fuses at the mean of
   the two, so the same two cells fold at a different pace depending on what you
   went and fetched. This is what the colours are for.
6. **Meet a fold you cannot make, and one you don't have to.** Through door W2,
   in the east region — see the next section.
7. **Find a hand inside a fold.** Through door W1: you arrive inside east's
   shipped pre-fold, and there is a loose hand in there with the goal. Folded-away
   space is real space, and it holds real things.
8. **Fold yourself in twice, across the grain.** Get pinched into the pit fold
   (beat 2), then — standing in the strip — fold *across* it: a vertical anchor
   pair, so the new creases run the other way. It swallows you again. You are two
   folds deep, and the space you are in has no ends: walk any direction far enough
   and you come back to yourself. The status line calls it a **torus**, because
   that is what the two folds together made, and nothing authored it. Then walk
   somewhere and surface twice — you come out where you walked to, as always.

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
  excises the wall's strip. The reward sits behind it.

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
strip of folds** — a pin anywhere in a column forbids every horizontal fold spanning
it, at any height. West carries the four authored beats and its geometry is load
bearing for all of them, so pins went in east, where there is room to be wrong.
Placing them in west is a playtesting job, not an editing one.

## Sound

Everything the verb does is audible. Placing a hand, arming a pair, the fold
going off, being swallowed by it, surfacing again, a fold that would not go and
scattered your hands instead — each has its own sound, and the ones that mean
opposite things are built as mirrors: `fold` and `unfold` are the same waveform
reversed, and `pinch` / `surface` are going in and coming out.

Refusals share one sound and one message. If a thing did not happen you get a
short low blip and a line of text, whatever the reason — the text says which
reason.

**A subspace has its own music.** Crossing into one crossfades the
region bed out and a darker, detuned version of it in: the same room, folded.
It is the only thing that tells you where you are without a word of UI.

Audio is style, like the lighting: the game is fully playable with the sound
off, and nothing you can hear is information you cannot also see. Volume is
read from `user://settings.json` at startup — the settings screen that would
edit it exists but nothing opens it yet.

Everything shipped is a generated placeholder (`tools/gen_audio.py`). See
`docs/features/AUDIO.md`.

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
  for the layout). Pieces are textured through **base-space UVs**: a piece
  is sent back to its base tile by subtracting `src_offset`, so it carries the
  patch of art it was cut from. A tile's variant is hashed from its `base_id`,
  and the "open sky above" edge tile is read from the base grid — so a tile's
  look never changes because it was folded, ridden or cut.
- **The whole sheet is two canvas items** (`TileBatch`). A region is ~800 tiles,
  folds cut those into more pieces, and inside a fold the strip is drawn again
  in every copy it repeats into. `Polygon2D` holds many sub-polygons over one
  vertex array and the tileset is one texture, so the only thing forcing a second
  node is the lit material: foreground and background. A fold rebuild touches two
  nodes instead of thousands.
- **The wrap is a property of the space, not of the things in it.** Static content
  bakes its copies into vertices; anything that moves is a `WrapCanvas` and is
  painted once per copy by its base class, in ordinary world coordinates. That is
  the whole contract — add a floating object and it turns up in every copy without
  knowing folds exist. (The hands orbiting your body are the object that proved
  the point: they used to appear in one copy and nowhere else.)

  The one thing a canvas does have to answer for is state it keeps between frames.
  Crossing a glue line slides body and camera by a period, and a canvas that
  remembers a world position is left a copy behind — so `carry_through_wrap` offers
  every canvas that same displacement, and one holding positions of its own adds it.
  `HandOrbit` is the only one that does; leaving it out was the hands appearing to
  snap back to the copy you entered from and swim after you.
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
it burns is a question asked of the current piece list. Everything follows
from that:

- Fold a lamp's tile away and it is **gone from the region** — no glyph, no
  light — and the same lamp is what **lights the fold's subspace** when you get
  in there.
- Fold something else and the lamp **rides its flap**, like any other occupant.
- Split its tile with a crease and it keeps burning on whichever half it landed
  on. (A door in that position goes dormant; a light has no ambiguity to resolve.)

Lighting is evaluated **per art pixel**: the shaded point and the light position
are both snapped to the pixel grid, the accumulated intensity is quantized into
steps, and the step edges are ordered-dithered — so light arrives in chunky
rings rather than as a smooth glow. Ambient is generous on purpose.

Where the shipped lights are, and what each is for:

| Light | Region | Shows you |
|---|---|---|
| `w_spawn` | west | the ordinary case — and it rides the flap when you fold the pit |
| `w_pit` | west | fold the pit shut and it leaves the world with the pit; get pinched in and it is in there with you |
| `w_chamber` | west | the sealed chamber glows through its own shell — there is something in there |
| `e_vault` | east | inside east's pre-placed fold: invisible from the region, and the only thing lighting the vault when you arrive through door W1 |
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

- Fold extent is the whole world (infinite-crease semantics) — deliberately
  kept so the "a fold over here guts a structure over there" problem is
  *feelable*; it's the live design argument for barrier-scoped fold regions.
- Unfold animation plays only when the unfolded fold is the newest of its space
  (the reverse transform is exact only there); mid-stack unfolds are instant.
- **A fold's own space is not re-derived when a fold cuts across its glue.** What
  the fold TAKES is cut from the repeating space (so you land in sheet, not void),
  but the flaps left behind are still drawn at the period the space came in with.
  That configuration is already the one the game singles out — it blocks the exit
  and reddens the glue diamond.
- Movable seams are design-agreed but not implemented.
- Triggers only fire in a region — a trigger inside a subspace would have to
  splice folds into an inner-fold list mid-cascade, which the resolver does not model.
- Unanchorable tiles (`_`, `X`) are supported by the format and covered by tests, but
  the SHIPPED world does not place any yet. `worlds/testbed.json` does — its
  `unanchor` region is nothing else — so the way to see one is `--world=testbed`
  rather than a code change.
- **You can strand yourself.** Put both hands into a fold, walk somewhere its seam
  cannot be reached from, and short of finding a loose hand there is no way back to
  them but `R` — which drops every fold and puts your starting pair back in your
  hands. The accepted cost of having no remote unfold; save points are the real
  answer and do not exist yet.
- Loose hands are runtime state (`FoldWorld.hand_pickups`) — the one thing tracked
  that is not `(base, folds)`. `R` rebuilds the list from the authored world, so
  authored loose hands respawn and hands dropped in play are forgotten.
- Lights do not cast shadows, and the seam is not lit specially — see *Art & light*.
- The player and the overlay markers are drawn unlit, so they never disappear
  into an unlit corner.

## Files

- `HandTypes.gd` (kernel) — the hand registry: one file per kind (colour, fuse).
  Covered by `scripts/tests/test_hand_types.gd`.
- `HandStock.gd` (kernel) — the slot ledger: conservation arithmetic, nothing
  stored. Covered by `scripts/tests/test_hand_stock.gd`.
- `HandPickup.gd` (kernel) — a hand lying in the world: base identity + point in
  tile, exactly like a door or a lamp. One object for authored loose hands and dropped
  hands alike.
- `FoldLattice.gd` (kernel) — how the space you are in repeats: no periods in a
  region, one inside a fold, two on the torus you get by folding yourself in
  across the grain. Copies, colliders, wrap-around and framing all read off it.
  Covered by `scripts/tests/test_fold_lattice.gd`.
- `WrapCanvas.gd` — a canvas item that paints itself once per copy of the space.
  Subclasses override `paint()` and never mention folds. `paint_once()` is for
  what belongs to the frame instead (the preview strip, the full-extent guides), and
  `carry_through_wrap()` for whatever a canvas remembers across frames.
- `TileBatch.gd` — the sheet, batched into two canvas items, with the wrap baked
  into the vertices. Also what the fold transition draws through: three batches,
  two of which move by setting a position. Covered by
  `scripts/tests/test_tile_batch.gd`.
- `PlayerVisual.gd` — the blob, drawn wherever the space says the body is.
- `HandOrbit.gd` — the circles that float beside you, and `draw_hand`, the ONE place
  a hand is drawn (the overlay draws loose ones through it, so they cannot drift
  apart — which is also why the idle drift lives in `draw_hand` and no caller can
  forget it). The spring is `WorldCore.spring_step`; the passive float is
  `WorldCore.hand_drift`, a function of wall time rather than an integration, so it
  needs no state and a hand dropped or picked up never restarts its phase. A
  `WrapCanvas`, which is the whole of what it knows about folds.
- **The falling hand**: `WorldCore.hand_ball_step` is the whole simulation (light, draggy,
  swept collision, rolls, rests) and it is pure, so it is pinned by `test_world_core`
  without a scene. `FoldWorld.hand_balls` is the transient in-flight list;
  `_land_ball` converts one back into a `HandPickup`, `_carry_balls_through` takes them
  through folds, `_wake_unsupported_hands` re-drops a resting hand whose ground has gone,
  and `WorldCore.wrap_into_strip` is why a hand can orbit inside a fold. See `AGENTS.md`
  for why a ball may hold a live position when nothing else in the world may.
- `WorldCore.gd` — pure logic (map parse, side classification, strip capture, seam
  and glue segments, depenetration, anchor/fold eligibility, camera zoom and
  lookahead). Covered by `scripts/tests/test_world_core.gd`.
- `FoldWorld.gd` — scene driver. ONE space at a time (the region is the space
  whose context is empty): derived geometry → batched tiles + colliders,
  fold/unfold with player riding, folding yourself in to any depth, wrap and exit,
  regions, doors, triggers, the tap/hold verb, the hand ledger, and the pixel
  render target (which it resizes as the zoom changes).
- `PlayerBody.gd` — CharacterBody2D blob (coyote time, jump buffer, the
  variable-height jump, squash) and the pixel-snapped camera, whose smoothing is
  driven here so the wrap can displace it by a whole period without losing its
  lag. It does not draw itself — `PlayerVisual` does, once per copy of the space.
  Its readings (`look_dir`, `take_jump_press`, `motion_fraction`,
  `motion_intensity`) and its jump arithmetic (`gravity_scale`, `step_fall`,
  `jump_height_for_hold`) are covered by `scripts/tests/test_player_body.gd`.
- `WorldOverlay.gd` — anchors, strip preview strip, seam markers, glue lines,
  doors, loose hands. A `WrapCanvas`: it draws one copy's worth and they appear
  in every copy. Seam diamonds are one per meeting CELL, since folds can share one
  (`FoldWorld.seam_markers`). Stroke widths are multiples of one art pixel.
- `PixelArt.gd` — how big an art pixel is; the one place that says so, including
  the target size a given zoom needs (`target_size`).
- `TileAtlas.gd` — the tileset: kinds, variants, and base-space UVs for pieces.
- `LightRig.gd` — lit materials, per-frame light uniforms, lamp glyphs.
- Audio lives outside this directory: `scripts/systems/Sounds.gd` is the
  vocabulary and the mix, `AudioManager` is the autoload that plays it. `FoldWorld`
  and `PlayerBody` only ever call into it — see `_deny` and `_update_music`.
- Scene flows in `scripts/tests/test_fold_world.gd`; what the world sounds like in
  `scripts/tests/test_world_audio.gd`.
