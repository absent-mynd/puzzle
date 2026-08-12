# Project Status — Space Folding

**Last Updated:** 2026-08-12
**Current Phase:** Consolidated onto the gravity metroidvania direction. Playable
vertical slice: two regions, doors, real subspaces, fold/unfold with animation,
folding as a **finite carried resource** — rendered as pixel art with fold-aware
dynamic lighting, framed by a camera that zooms and leads with the moment. The
world is now **authored in an editor** rather than by hand-editing JSON.
**Tests:** 797 passing / 797, 32 scripts, ~18s. (`./run_tests.sh` prints the real
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
| Fold-on-enter triggers | ✅ Wired in a region, **in the world** |
| Hands: two slots, typed, conserved (`HandStock`/`HandTypes`) | ✅ Playable, **in the world** |
| Loose hands (`HandPickup`) — authored + dropped, one object | ✅ Three placed, ⚙️ untuned |
| One-key verb (tap = place a hand, hold = burst) | ✅ Playable |
| Auto-commit fuse, pulsing on the placed hands | ✅ Playable, ⚙️ untuned |
| Hands floating beside the body (style only) | ✅ Playable |
| Occupant model (entities riding tiles) | ⚙️ Ported and tested, **not yet used in-world** |
| World authoring (`worlds/overworld.json`) | ⚙️ Format done; one hand-authored world |
| **Testbed world** (`worlds/testbed.json`, `--world=testbed`) | ✅ 14 regions of one-of-everything, for poking at mechanics |
| **World editor** — paint, canvases, doors, folds, per-tile params | ✅ Usable (`./run_editor.sh`) |
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

Roughly in priority order — nothing here is committed to yet:

1. **Playtest the hand economy.** Two slots, and fuses of 0.65 / 1.6 / 3.2 seconds,
   are first guesses, and west's beats were authored when folding was free. The
   question to answer by feel: does scarcity make the world read as *considered*, or
   merely fussy? Tuning is a playtesting job, not an editing one.
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
   the loose hands you have moved need to outlive a session, and the answer to
   stranding yourself with no hands and no reachable seam.
6. **Entities.** `Occupants` is the model; nothing renders or moves one yet.
7. **Finish the `Space` migration.** `FoldWorld` still carries twelve
   getter/setter properties forwarding to `space.x`, so the current space can be
   read two ways. Moving the call sites over and deleting them is mechanical.
8. **Two gaps in the editor** (`./run_editor.sh` — see
   `docs/features/WORLD_EDITOR.md`): a light's colour/radius/flicker are not yet on
   the `TileParams` pattern, and nested pre-placed folds are designed but deferred —
   the format reserves `folds[].in` and the loader ignores it.

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
- **You can strand yourself.** Spend your last hands on a fold, walk somewhere its
  seam cannot be reached from, and `R` is the only way back. `R` is survivable by
  design — it drops every fold and respawns the authored loose hands — but it still
  costs your position, your fold configuration, and any hand you had dropped
  somewhere deliberately. Save points are the real fix.
- Loose hands are runtime-only state (`FoldWorld.hand_pickups`) — the first thing that
  is not `(base, folds)`. `R` rebuilds them from the authored world and nothing carries
  them across a session; a save system is what they need next.
- The tilesheet is generated in code, so the world looks systematic rather than
  authored. The layout is fixed and a drawn sheet drops in without code changes.
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
