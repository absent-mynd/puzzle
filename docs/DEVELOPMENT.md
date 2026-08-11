# Development Workflow

**Purpose:** how to work on this project — the loop, the gates, and the mistakes
this codebase specifically invites.

**Last Updated:** 2026-08-11

> Rewritten from a 823-line version last touched 2025-11-07. That version opened by
> telling you to `cat docs/phases/pending/phase_X.md` — a directory that does not
> exist — and to expect `"All tests passed" (225/225)` from a suite that now has
> 791 tests. Most of the rest was generic Godot tutorial material that the
> [Godot docs](https://docs.godotengine.org/) do better and keep current. What
> survives here is the part that is true and specific to this repository.

For *where things live*, see [REFERENCE.md](REFERENCE.md). For *why the code is
shaped this way*, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## The loop

```bash
./run_tests.sh                 # everything
./run_tests.sh world           # partial filename match
```

1. **Write the test first.** The suite is the behavioural spec; it is how you find
   out what a subsystem does.
2. **Make it pass.**
3. **Run the whole suite before pushing.** The pre-push hook does this for you if
   you have run `./setup-hooks.sh`.

After adding or renaming a `class_name`, run `godot --headless --import` once so
the global class registry updates — otherwise you get spurious
"Identifier not declared" parse errors that have nothing to do with your change.

---

## The gates, and what they catch

There is **one** invocation of the test suite: `run_tests.sh`. CI
(`.github/workflows/gut-tests.yml`) and the pre-push hook both call it rather than
spelling out their own `godot` command. That is deliberate and worth preserving —
when those copies drift, it is always the automated one that stops telling the
truth. This project spent a stretch with a green CI badge over a red `main`
because CI's copy of the command carried `-d`, which makes Godot break into the
debugger on the first runtime error and exit **0** before GUT reports anything.

**Never run the suite with `-d`.**

A run fails if any of these is true:

| Condition | Caught by |
|---|---|
| An assertion failed | GUT |
| A test crashed before asserting | `tools/gut_strict_exit.gd` |
| A test asserted nothing at all | `tools/gut_strict_exit.gd` |
| A test script never loaded (parse error) | `tools/gut_strict_exit.gd` |
| The kernel referenced the view | `scripts/tests/test_layering.gd` |
| A shipped world is unplayable | `scripts/tests/test_shipped_worlds.gd` |

The middle three exist because GUT derives its exit code from the assertion-failure
count alone, so a test that never reaches an assertion scores zero of everything and
passes. A test file could be deleted by breaking it and nothing said so.

If you legitimately want a test that does not assert yet, mark it `pending()` —
that is tracked separately and does not fail the build.

---

## Which world a test runs against

This matters more than it sounds, and getting it wrong once cost 60 test failures
that had nothing to do with the change that caused them.

- **Kernel and integration tests** (`test_fold_world`, `test_nested_folds`,
  `test_world_audio`) pin themselves to `worlds/fixtures/kernel.json` via
  `FoldWorld.world_override`. They assert against concrete geometry — a pit here, a
  wall there — so they must not inherit whichever level happens to be shipping.
- **Content tests** (`test_shipped_worlds`, `test_world_data`,
  `test_testbed_world`) read the real worlds, because checking the real content is
  the entire point.

See [`worlds/fixtures/README.md`](../worlds/fixtures/README.md). The rule:
**fixtures prove the engine works, shipped worlds prove the game is playable.**
Neither test should be able to fail for the other's reason.

Express invariants as **deltas**, not constants. `assert_eq(_total(), 5)` is a
statement about one level's contents; `assert_eq(_total(), _start_total)` is the
conservation law you actually meant.

---

## Layering

```
scripts/model/ + scripts/utils/   ← pure, headless kernel
        ▲
scripts/world/ + editor/ + ui/ + systems/   ← view, physics, input
```

The kernel never references the view. It is testable precisely because it has no
scene tree, and that property is worth exactly as much as it is enforced —
`test_layering.gd` enforces it.

If you find yourself wanting to reach upward, the code you are reaching for is
usually pure and in the wrong directory. That is what happened to `WorldCore`:
`RefCounted`, every function static, no scene-tree contact, and living in
`scripts/world/` where the kernel had to reach up for it. Moving the file was the
entire fix. **Move it down; don't relax the rule.**

---

## Pitfalls this codebase invites

### 1. Mutating derived state — the most common

Editing a `FoldedPiece` (or the piece list) and expecting it to stick.

**Symptom:** your change works for one frame and vanishes on the next fold, unfold,
region load, or subspace transition.

**Why:** derived state is rebuilt from scratch by
`FoldReplay.derive_pieces(base, folds)` on every change. Pieces are outputs, not
storage. See ARCHITECTURE.md Decision 1.

```gdscript
# WRONG — the next rebuild throws this away
piece.type = TileTypes.WALL

# RIGHT — change the inputs, then re-derive
folds.append(fold)
rebuild_world()

# RIGHT — persistent facts belong on the BASE grid
base.tile_at(pos).type = TileTypes.WALL
rebuild_world()
```

**Rule of thumb:** if you want it to survive, it belongs in `BaseGrid`, the fold
list, or `WorldData` — never in a derived piece.

### 2. Comparing floats with `==`

`GeometryCore.EPSILON` is `0.0001`. Grazing a crease must not count as crossing it,
which is why `WorldCore.segment_intersects_strip` carries a half-pixel margin.
Without it, a fold whose seam merely *touches* another's strip spuriously blocks
unfolding.

```gdscript
if absf(point.x - 5.0) < GeometryCore.EPSILON:
if point.distance_to(target) < GeometryCore.EPSILON:
```

### 3. Switching on a tile type

`TileTypes` is the single authority for what a tile *does*.

```gdscript
if piece.type == TileTypes.WALL:      # WRONG — the next tile type breaks it
if TileTypes.is_walkable(piece.type): # RIGHT
```

This is why `PIN` and `UNANCHORABLE_WALL` collide correctly without the
collider-building loop in `FoldWorld.rebuild_world` having ever heard of them. A new
tile type should be one row in one table.

### 4. Giving a view a reference to the world

`WorldOverlay` used to hold `var world  # untyped to avoid a load-order cycle` and
reach into two dozen members of `FoldWorld`. The missing type annotation was the
receipt: a real dependency cycle suppressed by giving up static typing.

That was not a tidiness problem. Because the overlay could ask the world anything at
any point, two allocating queries drifted into the per-copy draw path, where
`WrapCanvas` runs them once per copy of the space — 77 copies two folds deep. They
cost most of a frame. Nothing about the drawing was wrong; only where the question
was asked, and with no boundary between the two objects there was no wrong side to
be on.

Do what `WorldHud`, `WorldCamera` and `OverlayView` do: **take the facts you need as
arguments.** A view that receives what it needs cannot form the cycle, and cannot
quietly acquire a cost inside a draw call. If a view needs a new fact, add a field to
its view-model — a decision made once, in a file whose purpose is to list what a
frame contains.

---

## Working on FoldWorld

`scripts/world/FoldWorld.gd` is ~2390 lines and still the object most features get
added to. Two seams have been lifted out (`WorldHud`, `WorldCamera`); the hand-ball
physics has **not**, because it depends on ten separate pieces of current-level
state and extracting it today would only convert that into a ten-field context
object or another back-reference.

The prerequisite is a **`Level` value object**. `_compute_level` already returns
`{base_pieces, level_folds, pieces}`, but the rest of the level's state —
`pieces_by_pos`, `wall_polys`, `lattice`, `free_extent`, `mode`, `region_id`,
`_spawn` — is scattered across members that `_apply_context` assigns. Gather those
into one value and the hand field becomes `step(level, delta)` with a narrow
interface. Until then, leave it where it is.

---

## Conventions

- **Typed GDScript.** `var x: int`, `func f() -> void`. The type system is the
  cheapest test you have.
- **Comment the *why*.** This codebase is unusually well commented and it is one of
  its real assets — the comments explain decisions, tradeoffs, and what was tried
  and rejected. Match that. Do not write comments that restate the code.
- **`_leading_underscore`** for private members and methods.
- **Small commits, descriptive messages.** Say what changed and why it changed.

---

## Debugging

```bash
godot --path . scenes/world/World.tscn                      # run the game
godot --path . scenes/world/World.tscn -- --world=testbed   # the debug world
./run_editor.sh                                             # the world editor
```

`worlds/testbed.json` holds one of everything the model can express, wired so
nothing is more than two doors away. It is the fastest way to reproduce a mechanic
in isolation. See [features/TESTBED_WORLD.md](features/TESTBED_WORLD.md).

`print_debug()` includes a stack trace. `breakpoint` stops in the editor debugger —
but never leave one in code that the suite runs.
