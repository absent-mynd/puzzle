# Test fixture worlds

Worlds in here belong to the **test suite**, not to the game. Nothing loads them
except `scripts/tests/`, and nothing here is playable content.

## Why they exist

The scene-driven tests (`test_fold_world.gd`, `test_nested_folds.gd`,
`test_world_audio.gd`) instantiate the real `World.tscn` and assert against real
geometry — a pit at a known place, a wall you can ride, a door with a known
partner. That is the right way to catch integration regressions.

What was wrong was *which* world they got. They inherited `FoldWorld.WORLD_PATH`,
the shipped level. So the kernel's behavioural spec was pinned to content a
designer is expected to edit, and editing it broke the spec:

> Commit `113c0f0` re-pointed `WORLD_PATH` at a different world and 60 kernel
> tests failed. Not one of them was about the change. The fold model was fine;
> the coordinates in the tests had simply stopped meaning anything.

`kernel.json` is a **frozen snapshot** of `worlds/overworld.json` as it stood
when the suite was written, so those coordinates keep meaning what the tests
think they mean. It changes only when someone deliberately changes what the
tests expect — never because a level was edited.

## How a test uses one

`FoldWorld.world_override` wins over both `WORLD_PATH` and the `--world=` flag.
Set it after `instantiate()` and before the node enters the tree:

```gdscript
world = load("res://scenes/world/World.tscn").instantiate()
world.world_override = "res://worlds/fixtures/kernel.json"
add_child_autofree(world)
```

## What does NOT belong here

Tests that validate the **shipped** worlds — every authored hand stands on
ground, every door has a partner, the spawn is solid. Those must read
`worlds/overworld.json` and `worlds/testbed.json` directly, because checking the
real content is the entire point. They live in `test_world_data.gd`,
`test_testbed_world.gd` and friends, and they are how a broken level gets
caught.

The split is the point: **fixtures prove the engine works, the shipped worlds
prove the game is playable.** Neither test should be able to fail for the other's
reason.
