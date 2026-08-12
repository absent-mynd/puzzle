# The testbed world

`worlds/testbed.json` is a **debug world**: fourteen regions holding one of
everything the model can express, wired together so you can get at any of it in
two door-steps. It is not a designed world, nothing in it is balanced, and
several arrangements in it are deliberately impossible. It exists so that
"what happens if a door is on a crease" is a thirty-second question instead of
an afternoon of editing.

```bash
godot --path . scenes/world/World.tscn -- --world=testbed   # play it
./run_editor.sh testbed                                     # edit it
```

`--world=` takes a bare name (`testbed` → `res://worlds/testbed.json`) or a
path (`res://worlds/whatever.json`). Without it you get `overworld.json`, the
shipped world, unchanged. `WorldData.selected_path` is the one place that reads
the flag, so the game and the editor can never disagree about which world a run
means.

`scripts/tests/test_testbed_world.gd` is what stops it rotting: it asserts the
file still loads, that everything in it points at something real, and that it
still covers the ground claimed below.

---

## The shape of it

**`hub` is the router.** Thirteen doors along one concourse, one per region, so
nothing is ever more than two doors away. Every other region opens with a
**landing run** — a clear stretch of walk line at `x = 1..13` carrying its
routing doors — which is what lets the terrain past it be as impassable as it
likes without stranding you.

On top of the star, the twelve themed regions are chained in a **ring**
(`plain → water → pins → … → kitchen → plain`) with four **chords** across it,
so region loading gets entered from more than one direction.

| Region | Focus |
|---|---|
| `hub` | **doors**, in every arrangement the model allows |
| `plain` | bare terrain — the shapes the jump and the fold are measured against |
| `water` | `~` — walkable, so it is air you can see |
| `pins` | `P` — one pin vetoes every fold whose *strip* spans it, at every height |
| `unanchor` | `_` and `X` — space and wall you cannot pin to |
| `triggers` | `T` — every outcome `TriggerResolver` has |
| `prefold` | regions that ship already folded, in every orientation |
| `lamps` | lights: colour, radius, energy, flicker, offset, and the light budget |
| `hands` | loose hands, in every place a hand can be |
| `goals` | `G` — the tile that shows you where a fold *put* things |
| `mash_a` | pins × triggers × water |
| `mash_b` | unanchorable × pre-folds × lamps × hands |
| `mash_c` | an open arena for folding yourself in, and in again across the grain |
| `kitchen` | **everything**, jammed into one 34×16 room |

---

## What each one is for

### `hub` — doors

Every door case at once, which no single shipped region can show you:

- **thirteen ordinary spokes** along the ground, one per region;
- **two doors in one cell** (`HUB_TWIN_A`/`HUB_TWIN_B` at `30,18`) going to two
  different regions — doors are keyed by id, not by cell, so nothing stops it;
- **a pair inside one region** (`HUB_LOOP_A`/`HUB_LOOP_B` on the left
  mezzanine): walking in moves you across the sheet you are already on;
- **a door with no floor under it** (`HUB_SKY` at `30,8`), ten cells up — fold
  the ground to it, or arrive through its partner in `lamps`;
- **a door split by a crease** (`HUB_DORMANT`, on the right mezzanine's
  pre-fold anchor): its tile is cut exactly through its centre, so there is no
  unambiguous side to arrive on and it is **dormant** until you unfold;
- **a door inside a fold** (`HUB_VAULT`): gone from the region entirely, so
  its partner in `kitchen` delivers you into the strip's subspace — where the
  lamp and the patient hand sealed in there are waiting.

There is also a two-tall pin on the concourse: jumpable, and a standing veto on
every horizontal fold whose strip spans its column.

### `plain` — terrain

The four heights the movement doc pins: a one-tall step (a bare tap clears it),
a two-tall pillar (a full hold clears it), a three-tall wall (nothing clears it
— fold it), a corridor two cells high to run under. Then a bottomless pit, a
shaft for the vertical-fold climb, and a sealed chamber with a goal in it that
only a diagonal crease can bite into.

### `water` — `~`

Water is **walkable**, which means it is not solid: it is air you can see.
So the region is mostly about what that does. A pool on the floor, a
full-height column you can stand anywhere in, a ceiling of it held up by
nothing, a pocket of it sealed inside walls — and a stretch of water used **as
the floor**, which you fall straight through and out of the world. There is a
water/wall checkerboard for watching rank 3 beat rank 2 wherever a fold makes
the two share a cell.

### `pins` — `P`

A single pin, a two-tall one (the thing blocking your fold is also your
stepping stone), a four-tall one that is neither jumpable nor foldable — with a
platform routing you over the top, because "route around, do not erase" is the
whole point of the tile. Then two extremes: **a nail in the sky** at `24,3`,
nowhere near anything, which vetoes every fold whose strip spans column 24 at
any height; and a **pin ring around a goal**, which is sealed for good.

### `unanchor` — `_` and `X`

Both refuse anchors; only `X` is solid. So `_` is open space you can walk
through but never pin to, and `X` is a wall you can never pin to. A stretch of
`_` over ground that is `X` underneath; alternating `X`/`#` stripes where every
other column is the only one you may pin to; a chamber whose entire shell
refuses anchors, with a goal and a hand inside it.

### `triggers` — `T`

Eleven plates covering every outcome `TriggerResolver` has. Channel names are
the index:

| Channel | What it shows |
|---|---|
| `gate_a` | the plain case: a plate, and the three-tall wall its fold excises |
| `gate_b` | **two plates, one channel** — whichever fires first makes the fold, the other finds it standing |
| `pinned` | **a pin vetoes it.** The plate is on the floor, the nail is six rows up in the sky, and the fold's strip spans it anyway — a trigger is not a back door around a pin |
| `degenerate` | both anchors on one cell: no fold, and the plate still counts as fired |
| *(blank)* | **no channel at all**, so nothing makes it idempotent and it stacks a new fold every time |
| `swallow` | a fold whose strip contains the plate: it would pinch in whoever fired it, so it is refused |
| `ghost` | **order-dependent** — its anchors sit inside `gate_a`'s strip, so it folds if you reach it first and finds nothing if you do not |

Trigger anchors are authored in **BASE** cells (`TriggerResolver` maps them
through the current fold state itself), unlike pre-placed fold anchors — see
below.

### `prefold` — regions that ship folded

Five pre-folds in one region, none of them nested: horizontal (sealing a vault whole,
and splitting the dormant door's tile), horizontal again (swallowing a door),
one **straight through a pin** — authored folds are applied without the block
check, so it goes, and it will not come apart — vertical (a strip of *rows*
across the whole width), and a **diagonal**, which is the one to look at: a
crease has infinite extent, so a diagonal strip takes a wide swath of the region
rather than the corner you aimed at. Roughly half this region is inside a fold
at boot. That is not a bug in the authoring; it is what infinite-crease means,
and it is much easier to believe once you have stood in it.

There is also a **nested** entry (`"in": [0]`). That field is reserved: the
editor saves it, the loader skips it. Authoring one here is what keeps that
contract from changing quietly.

### `lamps` — lights

One overhead alcove per variant: radius 1 and radius 20, energy 0.15 and energy
3.0, a lamp that flickers at full amplitude, a lamp offset into the corner of
its tile. Then two extremes — **six lamps in one cell**, to lean on the
shader's twelve-light budget, and a lamp buried inside the floor. And one lamp
inside a one-column pre-fold, which is therefore **not in the region at
all**: it lights the strip's subspace, for whoever ends up in there.

### `hands` — loose hands

The three kinds on the ground; **two in one cell**; one let go at the ceiling
so it falls the whole height of the region; one perched on a pin; one sealed in
a pocket with no way in; one resting under water; and one inside a pre-fold, to
be found by getting in there. Fold near any of them and watch what a hand does
when its ground goes away.

### `goals` — `G`

A goal floor, a goal ceiling, a goal column, a goal under water (rank 4 beats
rank 2), a goal a pin stands in front of, and a goal already sealed inside a
pre-fold at boot.

### `mash_a` / `mash_b` / `mash_c`

Crossings, not new elements. `mash_a` stands water on top of pins and puts a
plate in the water; `mash_b` pre-folds ground you cannot pin to and boxes a
goal in walls where only one of the four refuses anchors; `mash_c` is a wide
empty arena with a roof, two ledges to pin a second anchor from mid-jump, and a
pin floating in the middle — it is the room for folding yourself in, then
folding across the grain to get the torus.

### `kitchen` — the everything room

34×16. Every authoring character in one row (`~ P _ X G T`, with walls and air
around them), a trigger and the wall it opens, all three hand kinds, three
lamps, a goal, a pre-folded vault carrying a door and a lamp inside it, and
seven doors — including one half of the hub's two-in-one-cell pair and a
kitchen→kitchen loop. One place to stand and watch everything interact at once.

---

## Two things worth knowing before editing it

**Pre-placed fold anchors are PLANE cells, not base cells.** The loader applies
a region's fold list *in order against the already-folded piece list*
(`FoldWorld._setup_all`), so the second fold's anchors mean "where the sheet is
now", not "where it started". In `prefold`, fold 2 is authored at `(25,18)`
rather than `(28,18)` for exactly this reason. Trigger anchors are the other
way round — base cells, resolved through the fold state at fire time. If you
move a pre-fold in the editor, the ones after it in the list move with it.

**A fold's extent is the whole world.** Every strip spans the region
perpendicular to its anchors: a horizontal pair takes whole columns from sky to
floor, a vertical pair takes whole rows wall to wall, and a diagonal pair takes
a diagonal swath of everything. So a pre-fold placed to seal one vault will
also take whatever else shares its columns — including doors, which is how the
dormant and vault door cases here are authored, and which is why every routing
door sits on the landing run well clear of any strip.
