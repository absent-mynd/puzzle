# Project Status — Space Folding

**Last Updated:** 2026-11-10
**Current Phase:** Consolidated onto the gravity metroidvania direction. A designed
world of **six rooms, each one idea, played door to door by the test suite**: real
subspaces, fold/unfold with animation, folding as a **finite carried resource** that
now has a second use (a hand on a weight plate keeps one of the world's folds
standing) — rendered as pixel art with fold-aware dynamic lighting, framed by a
camera that zooms and leads with the moment. The world is **authored in an editor**,
and the editor and the game are **one app**: `F5` plays what you are editing.
**Tests:** `./run_tests.sh` prints the count and the time, and is the authority on both.

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
| Subspaces (the inside of a fold as a real place) | ✅ Playable |
| **Nesting: folding yourself in, and in again** | ✅ Playable, any depth, ⚙️ untuned |
| Regions + doors (recursive partner resolution) | ✅ Playable |
| Tile registry (pins, unanchorable air, water, plates) | ✅ Wired, tested, **in the world** |
| **Weight plates** (`H`) — a channel live while you or a hand rest there; the world's fold stands while it is down | ✅ Playable, **in the world**, ⚙️ untuned (it lets go at once) |
| **Sockets** — a bolted anchor on proximity; one hand completes it, and it comes back when the fold does | ✅ Playable, **in the world** |
| **Water** — swim in it, cannot pin in it | ✅ Playable, **in the world**, ⚙️ swim feel is a first guess |
| **Sigils** — goal tiles found once and counted | ✅ In the world; ❌ not saved across sessions |
| **Room reset** (`R`) — rebuild the room, refund the hands; `Shift+R` for the world | ✅ Playable |
| **Hand swap** (`Q`) — choose which hand goes down next | ✅ Playable, ⚙️ untested by feel |
| Fold-on-enter triggers — a plate pins a bolted pair, the fuse folds it | ✅ **At any depth**, in the world |
| **Burst plates** (`B`) — a tile that fires your burst at a radius it chooses | ✅ Wired at every depth, tested, **in the world** (the end of `press`) |
| Hands: two slots, typed, conserved (`HandStock`/`HandTypes`) | ✅ Playable, **in the world** |
| **Anchors as one system** (`Anchor`/`AnchorField`) — yours, the world's, a plate's | ✅ In the world |
| **Proximity pairing** — a pair is two anchors within their spans, derived per frame | ✅ Playable, ⚙️ untuned |
| Spans per hand kind (plain 4 / swift 3 / patient 6 cells) | ✅ Wired, ⚙️ **first guess** |
| Authored anchors (`regions[].anchors`) — bolted, channel- or proximity-armed | ✅ Format, loader, editor tool (`W`), testbed |
| Loose hands (`HandPickup`) — authored + dropped, one object | ✅ One placed (the patient hand in `press`), ⚙️ untuned |
| One-key verb (tap = raise a hand, tap = pin it, hold-and-release = burst) | ✅ Playable |
| **Placement cursor** — time stops between the two taps; nine cells of reach; dithered held-world look | ✅ Playable, ⚙️ untuned |
| Auto-commit fuse, pulsing on the placed hands | ✅ Playable, ⚙️ untuned |
| Hands floating beside the body (style only) | ✅ Playable |
| Occupant model (entities riding tiles) | ⚙️ Ported and tested, **not yet used in-world** |
| **The shipped world** (`worlds/overworld.json`) | ✅ Six rooms, one sigil each; every room solved and every wrong turn refused by `test_overworld_solutions`; ⚙️ **never played by a person** |
| **Testbed world** (`worlds/testbed.json`, `--world=testbed`) | ✅ 14 regions of one-of-everything, for poking at mechanics |
| **World editor** — paint, canvases, doors, folds, per-tile params | ✅ Usable (`./run_editor.sh`) |
| **One app** (`Shell`) — launcher, editor and a run of the game as three screens | ✅ Usable (`./run.sh`) |
| **Playtest from the editor** — `F5`, `F6` from the cursor, on the UNSAVED document; `Esc` back to the editor untouched | ✅ Usable |
| **Launcher** — the worlds in `worlds/`, played or edited, and a run started in any region | ✅ Usable, ⚙️ developer-facing |
| Unanchorable tiles (`_`, `X`) | ✅ `_` is in the world, as the air over two pits and the spray in `cistern`; `X` is in the testbed only |
| Pixel-art render pass (low-res target, 16px tileset, UVs) | ✅ In the world |
| **One wrap for the whole view** (`FoldLattice` / `WrapCanvas`) | ✅ In the world |
| **Batched sheet** — two canvas items, not one per piece | ✅ In the world |
| Dynamic lights as fold-aware occupants | ✅ In the world, every room lit |
| Hand-drawn tilesheet | ⚙️ Layout + drop-in path done; sheet is generated in code |
| Audio | ✅ Whole fold vocabulary wired; 21 SFX + 2 music beds ship (generated placeholders) |
| Save / progression | ❌ Not started — sigils and fold state live for one session |
| Entities (items, enemies, save points) | ❌ Not started |

---

## Test suite

`./run_tests.sh` reports the current composition — script count, test count and
timing — every time it runs, so it is not restated here. A hand-maintained table of
per-script counts used to live in this section; it claimed 747 tests across 28
scripts while the suite had moved to 792 across 31, which is the failure mode of
every number in a document that has to be updated by remembering to.

What the suite is *for* is in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): which
gates exist and what each catches, and the split between tests pinned to a fixture
world and tests that validate the shipped ones.

---

## History

Read `git log`. A hand-written changelog used to live here — roughly 570 lines of
dated entries, one per merged branch — duplicating information git already keeps
correctly and for free.

The entries were well written, and that is not enough: nothing verified them, and
a second copy of the history is a second thing to get wrong. The commit messages in
this repository are long-form and carry the same reasoning, which is the version
that stays attached to the change it describes.

```bash
git log --oneline                 # what happened
git log --stat <commit>           # and what it touched
```

For the reasoning behind the *shape* of the code rather than its history, see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Next up

Roughly in priority order — nothing here is committed to yet:

1. **Play the six rooms.** Every one of them is proved possible and proved
   unwalkable by a model, and none has been played by a person. The model says a
   room CAN be done; it has no opinion on whether the idea lands, whether the wrong
   turns are tempting or merely annoying, or how the `threshold` lift reads to
   someone who has never pinned a hand. Start there: it is the room that teaches
   the verb.
2. **Tune by feel what was set by arithmetic.** Spans (plain 4 / swift 3 / patient
   6), fuses, the swim (`PlayerBody.SWIM_*`), and whether a weight plate should let
   go at once or after a beat. The rooms are cut against the spans, so
   `test_overworld_solutions` moves with them.
3. **A way back.** The annex's chamber is one-way: once you surface inside it, the
   rooms before it are behind a wall no fold of yours opens. A second socket on the
   west side would make it a valve you can work from both ends, and the fuse race
   between a plain and a patient socket is the obvious way to say which one answers.
4. **Rooms for what the world does not ask.** Diagonal creases, folding in twice
   (the torus), trip plates, pre-placed folds and the swift hand all work and are
   only in the testbed. Each wants a room where it is the only way.
5. **The camera, now that a pair is bounded.** The lens holds the player and any
   ARMED pair, which is finite by construction — but a lone anchor is deliberately
   not framed, and how a frame full of span circles reads is untested by play. The
   vault's attic is seven rows above its hall and sits at the top edge of the frame
   until you look up.
6. **Draw the tileset by hand.** The generated sheet is real but plain; the layout
   and drop-in path are done, so this is an art job, not an engineering one.
7. **Settle fold extent.** See ARCHITECTURE §"What is deliberately still open". The
   six rooms are an argument for a crease being a whole line *inside a room*.
8. **Save / checkpoints.** A room reset now answers stranding, so what a save is
   FOR has narrowed to what should outlive a session: sigils, fold state, and where
   your hands are.
9. **Entities.** `Occupants` is the model; nothing renders or moves one yet. A crate
   is the obvious third thing that could rest on a weight plate.
10. **Finish the `Space` migration.** `FoldWorld` still carries twelve
    getter/setter properties forwarding to `space.x`, so the current space can be
    read two ways. Moving the call sites over and deleting them is mechanical.
11. **Gaps in the editor** (`./run_editor.sh` — see
    `docs/features/WORLD_EDITOR.md`): a world anchor's arming rule is tool state
    rather than per-anchor — which matters more now that weight plates lean on
    channels — a light's colour/radius/flicker are not yet on the `TileParams`
    pattern, and nested pre-placed folds are designed but deferred.
12. **Playtest the playtest loop.** See `docs/features/SHELL.md` §"Known gaps".

---

## Known issues

- **Nothing displayed may use a glyph the theme font lacks.** It falls back to a
  system font on a desktop and has none in the **web export**, so arrows, `★` and `⏸`
  rendered locally and were empty boxes on the hosted build.
  `scripts/tests/test_font_coverage.gd` is the gate; see
  [docs/features/SHELL.md](docs/features/SHELL.md) §"Two things that only bite
  somewhere else".
- The `topdown-archive` tag is **local only** — the remote refused the tag push
  (session credentials are scoped to the working branch). Use `git checkout 8bf8193`.
- The pause menu and settings screen are complete and wired but **unreachable** —
  nothing opens them, so the volume sliders cannot be used in-game. Volumes are
  read from `user://settings.json` at startup, so they are settable by hand. `Esc` is
  now taken: it leaves the run for whatever opened it. What `Esc` should mean in a
  FINISHED game is the decision that has not been made — see
  [docs/features/SHELL.md](docs/features/SHELL.md) §"Known gaps".
- Audio is not positional: a fold across the room sounds like one at your feet.
- The shipped sounds are generated placeholders (`tools/gen_audio.py`), not art.
- **The shipped world has been solved by the suite and played by nobody.** See
  "Next up" 1. A room the model calls possible may still be one a person cannot read.
- **The annex is one-way.** Surface inside its chamber and the first four rooms are
  out of reach for the rest of the run; so is the plain hand you left in `press`.
  Nothing after it needs either, which is why it shipped, and it is still a door
  that only opens one way in a genre that is about going back.
- **There are solutions the suite does not know about.** It proves the intended one
  works and that walking does not. It cannot prove no OTHER fold does — a diagonal
  with a socket moves the sheet up as well as along, and nobody has enumerated those.
  Where a cheap one was found it was closed (`_` over the pits, the nails in `span`,
  the spray in `cistern`); the rest are a player's to find.
- **Taking an older fold out from under a newer one slides the newer one** — its
  creases stay where they were while the sheet moves beneath them. A burst can do
  this; a weight plate will not (it lets go newest-first, for this reason). See
  ARCHITECTURE Decision 12.
- Trip plates (`T`), pre-placed folds, `X`, diagonal creases, the torus, the swift
  hand and occupants are covered by tests and the testbed, and are not in the six
  rooms.
- **The editor cannot set a world anchor's arming rule.** The `W` tool places, pairs,
  removes and draws them, and `validate()` reports the ones the game would refuse in
  silence — but every anchor it places takes the tool's current setting, so a channel
  name still has to be typed into the JSON.
- **You can strand yourself**, and `R` is the way back: it puts the room you are in
  back the way it shipped and returns the hands you spent in it. It costs that room's
  configuration and your place in it, and nothing else — other rooms, loose hands and
  sigils are untouched. What it cannot reach is a hand left in a room you can no
  longer get to; `Shift+R` resets the world.
- Loose hands and found sigils are runtime-only state (`FoldWorld.hand_pickups`,
  `sigils_found`) — the things that are not `(base, folds)`. Nothing carries them
  across a session; a save system is what they need next.
- The tilesheet is generated in code, so the world looks systematic rather than
  authored. The layout is fixed and a drawn sheet drops in without code changes.

---

## For detailed information

- [AGENTS.md](AGENTS.md) — start here: architecture, layering, critical decisions
- [docs/GLOSSARY.md](docs/GLOSSARY.md) — the vocabulary: one name per thing
- [scripts/world/README.md](scripts/world/README.md) — controls and design beats
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design decisions & rationale
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — workflow, gates, pitfalls
- [docs/REFERENCE.md](docs/REFERENCE.md) — code map
