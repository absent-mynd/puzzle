# Architecture Review — August 2026

**Reviewer:** external architecture review
**Commit reviewed:** `113c0f0` ("wip"), tip of `main`
**Date:** 2026-08-11
**Status:** point-in-time diagnosis. Not a document to maintain.

---

## Summary

The fold kernel is the best thing in this repository and it is not the problem.
`docs/ARCHITECTURE.md` is a genuinely excellent design document — the
derive-never-mutate decision, the `src_offset` invariant, and the "occupants ask
base space where they are" pattern are load-bearing ideas that earn their
complexity, and they are written down honestly, including the parts that are
still open.

The problem is everything wrapped around that kernel. Specifically:

**The project's quality gates do not work, and have not worked for some time.**
`main` is currently red — 73 of 778 tests fail — and CI reported success on it.
Both automated gates (GitHub Actions and the pre-push hook) are structurally
incapable of reporting a failure. This is not a "some tests are flaky" problem.
It is a "the green checkmark carries no information" problem, and every green
run in the recent history is suspect.

Everything else in this review is secondary to that.

---

## P0 — The build is lying

### 1. CI cannot fail

`.github/workflows/gut-tests.yml` and `.githooks/pre-push` both run Godot with
the `-d` (debug) flag. On the first *runtime* error in any test, Godot breaks
into the interactive debugger, finds no stdin, and terminates the process —
**with exit code 0**, before GUT ever prints its totals or sets its own exit
code.

Measured on this commit, same binary, same environment, only `-d` differing:

| Command | Test scripts run | Result printed | Exit code |
|---|---|---|---|
| CI's exact command (with `-d`) | 11 of 29 | none — aborted mid-run | **0** |
| Identical, minus `-d` | 29 of 29 | 778 tests, 73 failing | **1** |

With `-d`, the run dies at `test_fold_world.gd:60` on
`Invalid access of index '0' on a base object of type: 'Array[Fold]'` and the
remaining 18 test scripts never execute. CI calls that a pass.

**Fix:** delete `-d` from the workflow and from the pre-push hook. One word, two
files. Do this before anything else in this document, because until it is done
no other fix can be verified.

### 2. `main` is red, and was merged red

The tip of `main` is a commit named `wip`. It fails 73 of 778 tests. The GitHub
Actions run for it is green.

A commit called "wip" is the head of the default branch. That is a process
signal, not just a code signal.

### 3. Three test runners, three different behaviours

| Runner | Flags | Honest? |
|---|---|---|
| `./run_tests.sh` | no `-d`, reads `.gutconfig.json` | **yes** — exits 1 |
| `.githooks/pre-push` | `-d`, explicit `-gdir` | no — exits 0 |
| CI `gut-tests.yml` | `-d`, explicit `-gdir` | no — exits 0 |

The only runner that tells the truth is the one a human has to remember to type.
Both gates that run automatically are the broken ones. Consolidate all three onto
one script — have CI and the hook call `run_tests.sh` — so a fix to the invocation
cannot drift out of sync again.

---

## P1 — The "behavioral spec" is coupled to level content

`docs/ARCHITECTURE.md` and `README.md` both state that the test suite is the
behavioral spec. It is not, quite: a large part of it is a regression test
against one specific authored level, and it breaks when a designer edits that
level.

`scripts/tests/test_fold_world.gd` is 1,943 lines that instantiate the real
shipped `World.tscn` and assert against hardcoded world coordinates
(`do_fold(Vector2i(20, 12), Vector2i(28, 12))`) and **absolute** entity counts.

The `wip` commit did two ordinary content things and detonated the suite:

- flipped `WORLD_PATH` from `overworld.json` to a new `intro.json`
- raised overworld's loose-hand count from 3 to 11

Measured contribution of each, by reverting only `WORLD_PATH`:

| `WORLD_PATH` | Failing tests |
|---|---|
| `intro.json` (as shipped on `main`) | 73 |
| `overworld.json` | 13 |

So **60 failures are the world-file switch alone** — the tests' hardcoded
coordinates simply do not mean anything in the new world. The remaining 13 are
the hand-count change: assertions like `"Conserved, as ever"` and
`"and nothing was created or destroyed"` fail with `[13] expected to equal [5]`.

That last one is the instructive case. Those tests are checking a genuine kernel
invariant — *conservation* — but they express it as an absolute number baked from
the shipped level. A conservation test should assert `after == before`, never
`after == 5`. As written, the invariant is correct, the level is correct, and the
test fails anyway.

**Fix:** split the file. Kernel behaviour gets a small fixture world owned by the
test suite and versioned as a test asset, so it changes only when behaviour
changes. Content assertions ("the shipped world is playable") become a separate,
clearly-labelled level-validation suite. Rewrite the conservation assertions as
deltas.

### Content bug, surfaced by the above

Eight of the nine loose hands in the `east` region of `overworld.json` are
authored floating in mid-air (`test_world_data`: *"hand at (5, 4) in east lies on
solid ground"* ×8). At runtime this produces
`ERROR: FoldWorld: nowhere at all to land a hand near (864, 1568)` — logged
**2,246 times in a 16-second test run**. An error-severity message emitted 2,246
times is not an error message, it is noise that will hide the next real one.

---

## P2 — Structure

### 4. `WorldCore` is misfiled, and it is the *only* reason the layering rule is broken

Decision 9 says the kernel never imports the world. There is exactly one
violation: `scripts/model/WorldData.gd:239` calls `WorldCore.parse_map()`, and
`WorldCore` lives in `scripts/world/`.

The interesting part is that this is not a discipline failure. `WorldCore` is:

- `class_name WorldCore extends RefCounted`
- 32 static functions, **0** instance functions
- zero references to `Node`, `get_tree`, `add_child`, or any scene type
- self-described in its own docstring as *"Pure, testable logic… Everything here
  is static and side-effect free."*

It is kernel code. It is sitting in the view directory, and the kernel below it
reaches up to get at it. The layering rule isn't being violated by a careless
call — it is being violated by a filesystem location.

**Fix:** move `WorldCore.gd` to `scripts/model/`. The violation disappears, no
call sites change (GDScript resolves `class_name` globally), and the rule becomes
mechanically enforceable — a grep for `scripts/world/` identifiers inside
`scripts/model/` can then run in CI as a real gate.

### 5. `FoldWorld` is a god object

2,441 lines, 103 functions, one `Node2D`. Its own header comment needs 64 lines
to introduce it, and its internal section banners enumerate thirteen distinct
responsibilities: region loading, level derivation, input, the anchor ledger, the
fuse, folding, unfolding, hand physics, doors, animation, camera framing,
per-frame world logic, and the HUD.

The header is well written and the code is well commented — this is not sloppy
work, it is *accreted* work. But it is now the file that every feature has to be
added to, which is why the git history reads as a sequence of merges into it.

The seams are already visible in the banners and mostly clean. In rough order of
how easily they lift out: the HUD (`_build_hud`, `_update_status`, `_show_flash`,
`_deny`, `_update_music`), the camera (`_update_camera`, `_size_pixel_view`,
`_cut_camera`, `_camera_focus`), the hand-ball simulation (`_step_hand_balls`,
`_land_ball`, `_wake_unsupported_hands`, `_recover_lost_hand`), and the anchor
ledger. None of these need to know about fold derivation; all of them currently
sit inside the object that does it.

I would not attempt this until P0 is fixed. Refactoring a god object against a
test suite that cannot report failure is how you lose a weekend.

### 6. A dependency cycle papered over by deleting the type

`scripts/world/WorldOverlay.gd:36`:

```gdscript
var world  # FoldWorld; untyped to avoid a load-order cycle
```

The comment is honest about what it is doing: there is a genuine cycle between
`FoldWorld` and `WorldOverlay`, and it is being suppressed by giving up static
typing on the reference. The overlay then reaches into **24 distinct members** of
`FoldWorld` — `base`, `player`, `doors`, `lattice`, `primed`, `unpaired`,
`sub_fold`, `BURST_RADIUS`, and 16 more.

That is not a view reading a model, it is a view sharing a brain with one. The
cycle is the real finding; the missing type annotation is just the receipt.

**Fix:** the overlay wants a view-model — one struct produced by `FoldWorld` per
rebuild describing what should be drawn — rather than 24 reach-throughs. That
also breaks the cycle for real, at which point the type annotation comes back.

---

## P3 — Hygiene

- **`docs/DEVELOPMENT.md` is 823 lines of stale instructions.** Last updated
  2025-11-07, nine months ago. It tells a new contributor to run
  `cat docs/phases/pending/phase_X.md` — `docs/phases/` does not exist — and to
  expect `"All tests passed" (225/225)` from a suite that now has 778 tests.
  A contributor following it hits a missing directory in step 2. Delete it or
  rewrite it; do not leave it.
- **Documentation outweighs its own maintenance budget.** 4,364 lines of markdown
  against 12,797 lines of non-test GDScript — roughly one line of prose for every
  three lines of code, across `AGENTS.md` (566), `STATUS.md` (821),
  `DEVELOPMENT.md` (823) and six more files. `ARCHITECTURE.md` is worth every
  line. Most of the rest is duplicated or drifting, and `DEVELOPMENT.md` is
  already provably wrong. Prose that isn't executable rots silently; the fix is
  fewer, shorter documents with clearer ownership.
- **Dead code the engine already flags:** `FoldWorld.gd:235`,
  `var _on_screen_lights: Array = []` — declared, never used. Godot reports this
  on every single test run.
- **`scenes/world/World.tscn` has a stale resource UID**, producing 150
  `invalid UID` warnings per test run. Re-save the scene.

---

## What I would do, in order

1. **Remove `-d`** from `gut-tests.yml` and `.githooks/pre-push`. Nothing else can
   be verified until this is true.
2. **Get `main` green.** Decide whether `intro.json` or `overworld.json` is the
   shipped world — the `wip` commit changed it without saying — and either fix
   the world data or re-point the tests. Fix the eight floating hands.
3. **Collapse the three runners into one.** CI and the hook call `run_tests.sh`.
4. **Split `test_fold_world.gd`** into kernel-behaviour tests on a fixture world
   and level-validation tests on the shipped worlds. Convert absolute-count
   assertions to deltas.
5. **Move `WorldCore.gd` into `scripts/model/`**, then add a CI grep that fails
   the build if `scripts/model/` or `scripts/utils/` names anything from
   `scripts/world/`. The rule in `ARCHITECTURE.md` becomes enforced rather than
   aspirational.
6. **Then, and only then, start carving up `FoldWorld`** — HUD first, camera
   second, hand physics third.
7. **Delete or rewrite `docs/DEVELOPMENT.md`.**

Items 1–3 are a day's work and buy back the ability to trust the repository.
Item 6 is the large one, and it is safe to attempt only after 1–4.

---

## What not to change

- **The derive-never-mutate kernel.** It is correct, it is well tested, and the
  cost analysis in Decision 1 is sound.
- **Infinite creases (Decision 3).** `ARCHITECTURE.md` explicitly asks that this
  be felt in play before it is engineered away. That is a legitimate design
  position and a reviewer should not quietly overrule it.
- **`TileTypes` as the behaviour registry.** The discipline is holding: only six
  direct `== TileTypes.X` comparisons survive outside the registry, and all six
  are in rendering and editor code doing genuinely presentational things.
- **`docs/ARCHITECTURE.md` itself.** Keep it, keep it current, and make it the
  document the others defer to.
