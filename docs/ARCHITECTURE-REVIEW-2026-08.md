# Architecture Review — August 2026

**Reviewer:** external architecture review
**Commit reviewed:** `113c0f0` ("wip"), tip of `main`
**Date:** 2026-08-11
**Status:** point-in-time diagnosis. Not a document to maintain.

> **Vocabulary note.** This review was written before `docs/GLOSSARY.md` settled the
> project's terms, and its wording is left exactly as reviewed rather than
> retranslated — a dated record that gets edited is no longer a record. Read
> *fragment* as **piece**, *band* as **strip** or **copy**, *primed* as **armed**,
> *anchor* (where it means the resource) as **hand**, and `Level` as `Space`.

> **Remediation status — every finding in this review is closed.** The suite is
> **795/795 green**, the gates now actually gate, and a full run emits **0 errors**
> where it emitted 1,964.
>
> Three things are worth reading before the findings themselves, because each one
> changed what got built:
>
> **Closing finding 01 turned up two further holes this document did not predict.**
> Removing `-d` stops the run being truncated but does not make a crashed test fail,
> and a test script that fails to parse is skipped with a warning while the run still
> exits 0. Every gate here was believed to work until something was made to fail on
> purpose — and the third hole was found by luck rather than by looking.
>
> **Finding 05's log storm was not a logging problem.** Instrumenting it rather than
> reasoning about it found an infinite recovery loop. Fixing the logging as this
> document prescribed would have left the loop running and removed its only outward
> sign.
>
> **Finding 08 was underrated, and one claim about it here was wrong.** Extracting
> `Level` does *not* collapse most of its reach-throughs — it covers 3 of 24, and the
> other 21 are gameplay queries no amount of level state answers. More importantly,
> the finding was filed P2 on structural grounds while quietly being the most
> expensive thing in the frame: two allocating queries on the per-copy draw path cost
> most of a 60fps budget two folds deep. Both symptom and cause are now fixed.
> **Price a coupling finding before you schedule it** — I would have got to this one
> last.

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

> **Follow-up (2026-08-11).** Removing `-d` closes only the loud half of this.
> GUT derives its exit code from the assertion-failure count alone
> (`GutRunner._handle_quit` → `gut.get_fail_count()`), so a test that dies of a
> runtime error before reaching an assert is filed as **risky**, not failing, and
> the run still exits 0. The run is no longer truncated, but the crash is still
> invisible — and a crash is exactly what broke this repository.
>
> This was found by canarying the fix rather than assuming it: appending a
> deliberate `empty[0]` access to a real test file still produced exit 0.
> `tools/gut_strict_exit.gd` now fails the run on a non-zero risky count, via
> GUT's supported `post_run_script` hook. Pending tests are excluded — `pending()`
> is a legitimate authoring tool with its own total.
>
> Then a **third** hole, found the same way — by accident, while adding a test file
> that happened to have a parse error in it. GUT reacts to a script it cannot load
> by logging "Ignoring script ... because it does not extend GutTest" and carrying
> on: the file's tests do not fail, they cease to exist. One bad character in
> `test_base_grid.gd` took the suite from 788 tests to 779 and still exited 0. A
> test file could be deleted by breaking it. The hook now also compares the test
> files on disk against the scripts GUT actually collected.
>
> Verify a gate by making it fail on purpose. A gate nobody has watched fail is
> only believed to work — that was true three times here, and the third was found
> by luck rather than by looking.

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
solid ground"* ×8).

Separately, a full suite run emits
`ERROR: FoldWorld: nowhere at all to land a hand near (864, 1568)` **2,246
times**.

> **Correction (2026-08-11).** The first draft of this review presented the second
> fact as a consequence of the first. It is not. Removing the eight floating hands
> dropped the count only from 2,246 to 1,964; they accounted for 282. All 1,964
> remaining come from `test_fold_world`, via the `push_error` at
> `FoldWorld.gd:1593` — a hand that can reach neither a sheet nor the spawn tile
> is kept in the air and re-reports on every landing attempt, and the tests step
> the flight simulation up to 900 times per test. The two problems are unrelated;
> the attribution was wrong.

The logging issue is the more durable of the two: this is a *recoverable* state
the code handles deliberately (it keeps the hand catchable rather than deleting
it), reported at ERROR severity from inside a loop. An error-severity message
emitted 1,964 times is not an error message — it is noise that will hide the next
real one. It wants to be a once-per-hand warning, or a counter.

> **Second correction (2026-08-11).** It wanted neither. Instrumenting the path
> rather than reasoning about it showed `_recover_lost_hand` entering **1,965
> times**, always at the same point, always from a freshly built ball — an
> infinite recovery loop, not a chatty log. A hand that ran off the free axis
> inside a fold took the *world-level* answer (settle at the player's feet), which
> inside a fold is routinely outside the strip, so it bound to nothing, was put
> back in the air, drifted out and was recovered again.
>
> This is precisely the loop `_recover_lost_hand`'s own docstring says it exists
> to prevent; it had moved from the world level into subspaces. Nothing caught it
> — the ledger stayed correct, the hand really was still in the band, and the two
> tests watching an orbiting hand watched the *wrap* axis while the escape was
> along the *free* one.
>
> The fix was three lines above the bug, in a comment: *"Turn it back the way the
> fold turns the player back."* `_wrap_body` already did exactly that for the
> body. The body and the ball now share that code.
>
> The lesson is the same one finding 01 kept teaching: **a symptom that looks like
> noise is worth instrumenting rather than tidying.** Had I fixed the logging as
> written here, the loop would still be running and would have been harder to find
> afterwards, because its only outward sign would be gone.

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

> **Outcome (2026-08-11).** Two of the three seams are out. `WorldHud` took the
> overlay — background, controls line, status readout, flash and its lifetime — and
> `WorldCamera` took the lead, the lens and the render-target sizing. Both take the
> facts they need as arguments and hold no reference back, which is the property
> finding 08 is about. `FoldWorld` is 2,391 lines, down from 2,441.
>
> **The hand-ball physics was deliberately not extracted, and that is the more
> useful result.** It depends on ten separate pieces of current-level state —
> `wall_polys`, `current_pieces`, `pieces_by_pos`, `lattice`, `free_extent`,
> `base.grid_size`, `mode`, `region_id`, `_spawn`, the player's position — and
> mutates two more (`loose_hands`, the pickup lists). Pulling it out today converts
> that into either a ten-field context object or another back-reference, which is
> the thing finding 08 says not to do. It would move lines without reducing coupling.
>
> The prerequisite is a **`Level` value object**. `_compute_level` already returns
> `{base_pieces, level_folds, pieces}`; the rest of the level's state is scattered
> across members that `_apply_context` assigns. Gather them into one value and the
> hand field becomes `step(level, delta)` with a genuinely narrow interface — and
> `WorldOverlay`'s two dozen reach-throughs mostly collapse into it too, which is
> why this is the same fix as finding 08 rather than a different one.
>
> Doing a bad extraction to close a finding is worse than leaving the finding open
> with its blocker written down.

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

> **This was filed as a coupling problem. It was hiding a performance bug, and the
> coupling is why nobody could see it. (2026-08-11)**
>
> `WrapCanvas` splits drawing into `prepare()` — once, before any copy — and
> `paint()` — once per copy. Its own docstring says why: *"so a question that costs
> something is asked once rather than once per band."* `WorldOverlay` overrides both,
> gathers eighteen answers correctly in `prepare()`, and then asks **fifteen more
> from inside `paint()`**. Two of those are not cheap: `glue_lines()` scans every
> base piece for every period of the lattice, and `loose_hand_points()` resolves
> every loose hand against every fragment.
>
> A region does not repeat, so at world level this costs one extra call and is
> invisible. Inside a fold the space repeats **7** times. Two folds deep it repeats
> **77**. The ceiling is `MAX_WRAP_COPIES` = 121.
>
> Measured on the fixture world, two folds deep:
>
> | Query | Cost | Calls/frame | Total |
> |---|---:|---:|---:|
> | `glue_lines()` | 187.90 µs | ×77 | 14.5 ms |
> | `loose_hand_points()` | 23.94 µs | ×77 | 1.8 ms |
> | | | | **16.3 ms** |
>
> A 60fps frame is 16.6 ms. **The torus — the headline mechanic of the whole game —
> was spending 97.9% of its frame budget re-deriving two answers that had not
> changed between copies.** Gathered in `prepare()` the same two cost 212 µs: a 45×
> reduction, and flat in the copy count rather than linear in it.
>
> Nothing about the drawing differs. Nothing about the code is wrong except *where
> the question is asked* — and the reason it could be asked there is finding 08
> itself. When a view holds the whole world and may ask it anything at any point,
> there is no boundary for a gather to be on the wrong side of.
>
> **Closed (2026-08-11).** `OverlayView` is the view-model this section asked for: a
> plain value listing what one frame contains — markers, doors, placed hands, preview
> pairs, glue, the aim ring, the burst. `FoldWorld` fills one in per frame and hands
> it over; the overlay draws it and can do nothing else.
>
> | | Before | After |
> |---|---:|---:|
> | Reach-throughs into `FoldWorld` | 24 | **0** |
> | …of those, once per copy | 15 | **0** |
> | Per-frame cost, 77 copies | 11.0 ms (65.8%) | **199 µs (1.2%)** |
>
> The 199 µs builds the *entire* view and re-clips the preview polygons —
> `Geometry2D.intersect_polygons` was also running per copy. The drawing is identical.
>
> `test_wrap_canvas_contract.gd` holds both halves: the general rule that no
> allocating query may be reached from any canvas's per-copy path, because the next
> `WrapCanvas` subclass will not have a view-model; and the specific one that the
> overlay declares no `world` member and reaches into none. The second is checked by
> source rather than behaviour, because **"cannot" is the property that matters** — a
> test that merely draws correctly would pass with the reference restored.

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

**Everything in this review is now done**, plus three follow-ups it generated and
two corrections to its own claims. The suite is 795/795, the gates fail on four
distinct kinds of broken test rather than one, the kernel's layering rule is enforced
by a test rather than a paragraph, and a full run emits nothing.

`FoldWorld` is 2,460 lines with 603 more living in five classes that read on their
own — `WorldHud`, `WorldCamera`, `HandField`, `OverlayView` and the kernel's `Level`.
It is not smaller than it was, and that is the honest outcome: what changed is that
five concerns now have names and boundaries instead of being interleaved.

**What I would do next**, in order:

1. **Migrate `FoldWorld`'s internal call sites onto `level.x`** and delete the
   compatibility properties. Mechanical, and it removes the last place where the
   level's state can be read two ways.
2. **Playtest the anchor economy.** Every remaining item in `STATUS.md` §"Next up" is
   a design question, not an engineering one — which is a better place for this
   project to be than where it started.

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
