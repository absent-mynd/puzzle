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

Directly, without the wrapper:

```bash
godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/ -gexit
```

**After adding or renaming a `class_name`**, run `godot --headless --import` once so
the global class registry updates — otherwise you will see spurious
"Identifier not declared in the current scope" parse errors that have nothing to do
with your change.

## Layout

One `test_<subject>.gd` per subject, matching the source file it covers.

| File | Covers |
|---|---|
| `test_geometry_core.gd` | Sutherland-Hodgman, epsilon, area/centroid |
| `test_collision_core.gd` | Polygon clipping under folds |
| `test_base_grid.gd` | The immutable base model |
| `test_fold_replay.gd` | The derivation engine |
| `test_folded_state.gd` | Per-position stacks, dominant type |
| `test_fold_unfold_inverse.gd` | Unfold as drop-and-re-derive |
| `test_base_frame.gd` | Base ↔ derived point transport |
| `test_tile_types.gd` | The tile registry |
| `test_occupants.gd` | Entities riding tiles; split-on-unfold |
| `test_trigger_cascade.gd` | Fold-on-enter cascade |
| `test_world_data.gd` | World format + the shipped world |
| `test_world_core.gd` | Map parsing, seams, anchor/fold eligibility, camera zoom + lookahead |
| `test_player_body.gd` | Look/point keys, velocity-as-fraction-of-limits, motion scalar |
| `test_audio_manager.gd` | Buses, playback, volume, the `Sounds` registry |
| `test_world_audio.gd` | **Scene-driven**: that the world is actually heard |
| **`test_fold_world.gd`** | **Scene-driven integration** |

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
