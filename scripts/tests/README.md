# Test Suite

The suite is the project's behavioral spec. When you want to know how a subsystem is
*meant* to work, read its test before reading its implementation.

## Running

```bash
./run_tests.sh                 # everything
./run_tests.sh world           # partial filename match
./run_tests.sh fold            # every file matching "fold"
```

If Godot's config directory is sandboxed, redirect `HOME`:

```bash
HOME=/tmp/godot-home ./run_tests.sh
```

## Layout

One `test_<subject>.gd` per subject, matching the source file it covers — so `ls`
answers "what is covered" and there is no hand-maintained index here to fall behind
the directory. (There was one. It listed half the scripts.)

Two are different, and both deliberately:

`test_fold_world.gd` is the important one. It instantiates the real world scene and
drives the actual beats — riding a flap, being pinched into a fold, folding inside a
subspace, exiting through the glue anchor, door traversal between regions, doors into
a pre-folded subspace. Everything else is pure and headless; this is what catches
integration regressions.

`test_world_audio.gd` drives the same scene and listens to `AudioManager.sfx_played`,
so it asserts what the player would **hear** rather than what the code asked for. It
exists because the previous audio system rotted in exactly the gap it fills:
`AudioManager` was tested, complete and correct, and nothing in the game called it.
A test of the engine alone cannot tell you that.

## Conventions

- Extend `GutTest`; test methods start with `test_`.
- **Always** pass a descriptive message to assertions — the message is what a failure
  report is made of.
- Prefer `assert_almost_eq` for anything float-valued; never `==`.
- Kernel tests need no scene tree and no `after_each` teardown. If a test you are
  writing needs nodes, ask whether the thing you are testing belongs in the kernel.

```gdscript
extends GutTest

const CELL := 64.0
var base: BaseGrid

func before_each():
    base = BaseGrid.from_types(Vector2i(10, 10), CELL)

func test_fold_excises_the_strip_between_the_creases():
    var f := Fold.create(0, Vector2i(2, 5), Vector2i(6, 5), CELL)
    var state := FoldReplay.derive(base, [f])
    assert_lt(state.occupied_count(), 100,
        "the excised strip should reduce the occupied position count")
```

See [docs/DEVELOPMENT.md](../../docs/DEVELOPMENT.md) for the fuller testing guide and
the invariants worth asserting.
