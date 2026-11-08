# Project Status — Space Folding

**Last Updated:** 2026-11-08
**Current Phase:** Consolidated onto the gravity metroidvania direction. Playable
vertical slice: two regions, doors, real subspaces, fold/unfold with animation,
folding as a **finite carried resource** — rendered as pixel art with fold-aware
dynamic lighting, framed by a camera that zooms and leads with the moment. The
world is **authored in an editor** rather than by hand-editing JSON, and the editor
and the game are now **one app**: `F5` plays what you are editing.
**Tests:** 962 passing / 962, 38 scripts, ~25s. (`./run_tests.sh` prints the real
numbers; this line is a snapshot and the runner is the authority.)

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
| Tile registry (pins, unanchorable, water, triggers) | ✅ Wired, tested, **in the world** |
| Fold-on-enter triggers — a plate pins a bolted pair, the fuse folds it | ✅ **At any depth**, in the world |
| **Burst plates** (`B`) — a tile that fires your burst at a radius it chooses | ✅ Wired at every depth, tested; placed in the testbed, not in the shipped world |
| Hands: two slots, typed, conserved (`HandStock`/`HandTypes`) | ✅ Playable, **in the world** |
| **Anchors as one system** (`Anchor`/`AnchorField`) — yours, the world's, a plate's | ✅ In the world |
| **Proximity pairing** — a pair is two anchors within their spans, derived per frame | ✅ Playable, ⚙️ untuned |
| Spans per hand kind (plain 4 / swift 3 / patient 6 cells) | ✅ Wired, ⚙️ **first guess** |
| Authored anchors (`regions[].anchors`) — bolted, channel- or proximity-armed | ✅ Format, loader, editor tool (`W`), testbed |
| Loose hands (`HandPickup`) — authored + dropped, one object | ✅ Three placed, ⚙️ untuned |
| One-key verb (tap = raise a hand, tap = pin it, hold-and-release = burst) | ✅ Playable |
| **Placement cursor** — time stops between the two taps; nine cells of reach; dithered held-world look | ✅ Playable, ⚙️ untuned |
| Auto-commit fuse, pulsing on the placed hands | ✅ Playable, ⚙️ untuned |
| Hands floating beside the body (style only) | ✅ Playable |
| Occupant model (entities riding tiles) | ⚙️ Ported and tested, **not yet used in-world** |
| World authoring (`worlds/overworld.json`) | ⚙️ Format done; one hand-authored world |
| **Testbed world** (`worlds/testbed.json`, `--world=testbed`) | ✅ 14 regions of one-of-everything, for poking at mechanics |
| **World editor** — paint, canvases, doors, folds, per-tile params | ✅ Usable (`./run_editor.sh`) |
| **One app** (`Shell`) — launcher, editor and a run of the game as three screens | ✅ Usable (`./run.sh`) |
| **Playtest from the editor** — `F5`, `F6` from the cursor, on the UNSAVED document; `Esc` back to the editor untouched | ✅ Usable |
| **Launcher** — the worlds in `worlds/`, played or edited, and a run started in any region | ✅ Usable, ⚙️ developer-facing |
| Unanchorable tiles (`_`, `X`) | ⚙️ Wired and tested; placed in the testbed, not in the shipped world |
| Pixel-art render pass (low-res target, 16px tileset, UVs) | ✅ In the world |
| **One wrap for the whole view** (`FoldLattice` / `WrapCanvas`) | ✅ In the world |
| **Batched sheet** — two canvas items, not one per piece | ✅ In the world |
| Dynamic lights as fold-aware occupants | ✅ In the world, 5 placed |
| Hand-drawn tilesheet | ⚙️ Layout + drop-in path done; sheet is generated in code |
| Audio | ✅ Whole fold vocabulary wired; 21 SFX + 2 music beds ship (generated placeholders) |
| Save / progression | ❌ Not started |
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

**The queue is the authority on what is next:** every planned piece of work is a
ticket in [queue/](queue/README.md), and what waits on a decision is the owner's
inbox.

```bash
./tools/queue.py board     # everything open, by state
./tools/queue.py inbox     # what waits on the owner
```

A priority list used to live here; it moved into tickets so that each item has one
home and a state.

---

## Known issues

Standing caveats only. Anything with work attached is a ticket in
[queue/](queue/README.md).

- **Nothing displayed may use a glyph the theme font lacks.** It falls back to a
  system font on a desktop and has none in the **web export**, so arrows, `★` and `⏸`
  rendered locally and were empty boxes on the hosted build.
  `scripts/tests/test_font_coverage.gd` is the gate; see
  [docs/features/SHELL.md](docs/features/SHELL.md) §"Two things that only bite
  somewhere else".
- The `topdown-archive` tag is **local only** — the remote refused the tag push
  (session credentials are scoped to the working branch). Use `git checkout 8bf8193`.
- The pin/trigger wing lives in **east**, not west, and is reached through a door.
  West's four authored beats depend on its exact geometry and infinite creases make
  a pin a global veto on every fold whose strip spans it, so nothing was placed there
  without playtesting. See the note in `scripts/world/README.md`.

---

## For detailed information

- [AGENTS.md](AGENTS.md) — start here: architecture, layering, critical decisions
- [docs/GLOSSARY.md](docs/GLOSSARY.md) — the vocabulary: one name per thing
- [scripts/world/README.md](scripts/world/README.md) — controls and design beats
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design decisions & rationale
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — workflow, gates, pitfalls
- [docs/REFERENCE.md](docs/REFERENCE.md) — code map
