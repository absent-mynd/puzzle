# Space Folding

A side-view gravity **metroidvania** where the traversal verb is folding space,
built with Godot 4.3.

> **Contributors & AI agents:** start with **[AGENTS.md](AGENTS.md)** (architecture,
> layering, critical decisions) and **[STATUS.md](STATUS.md)** (current progress).

## What it is

Pin two anchors within arm's reach and the space between them is excised — the two
halves slide together and meet. A pit closes. A wall you could not climb becomes
ground under your feet. A sealed chamber loses a corner to a diagonal crease.

What makes it a metroidvania rather than a puzzle game:

- **Folds persist.** They are world state, not a move you undo. Regions keep their
  fold state when you leave them.
- **Folds are places.** The strip a fold excises is a real interior you can be
  pinched into, walk around in, fold *within*, and surface from somewhere else.
- **Doors are warp points that ride folds.** Fold a door away and its partner
  delivers you *inside* that fold. Fold something over a door and you have jammed it
  shut until you unfold.
- **Lamps are occupants too.** Fold one away and it leaves the overworld entirely —
  and lights the folded-away place instead, for whoever ends up in there.

Run it: open the project in Godot and press play (`scenes/world/World.tscn`), or

```bash
godot --path . scenes/world/World.tscn
```

Controls and the design beats are in
[scripts/world/README.md](scripts/world/README.md).

## Development Setup

**Prerequisites:** Godot 4.3+ and Git.

```
scripts/
├── model/     # kernel: base grid, folds, derivation, transport, tile registry
├── utils/     # kernel: geometry and collision math
├── world/     # the game: FoldWorld, WorldCore, PlayerBody, WorldOverlay,
│           #   and the render pass: PixelArt, TileAtlas, LightRig
├── systems/   # AudioManager
├── ui/        # PauseMenu, Settings
└── tests/     # GUT suite — the behavioral spec
worlds/        # authored worlds (regions, doors, pre-placed folds, lights)
scenes/world/  # World.tscn — the main scene
assets/        # the lighting shader; the tileset layout (assets/sprites/README.md)
```

The art is **pixel art with dynamic lighting**: the world renders into a 320x180
target scaled up 4x, tiles come from a 16px tileset, and lights are evaluated per
art pixel. It is style only — world coordinates, physics and reachability are
unchanged, and unlit ground is exactly as navigable as lit ground. See
[scripts/world/README.md](scripts/world/README.md) §"Art & light".

The kernel is pure and headless; it must never reference `scripts/world/`.

## Testing

This project uses **GUT (Godot Unit Test)** v9.4.0. The suite is the behavioral
spec — to learn how a subsystem behaves, read its `test_*.gd`.

```bash
./run_tests.sh                 # all tests
./run_tests.sh world           # partial filename match

# or directly
godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/ -gexit
```

If Godot's config dir is sandboxed, redirect `HOME`:

```bash
HOME=/tmp/godot-home ./run_tests.sh
```

After adding or renaming a `class_name`, run `godot --headless --import` once so the
global class registry updates — otherwise you get spurious "Identifier not declared"
parse errors.

`run_tests.sh` prefers the bundled `tools/godot/godot.gz` (Linux x86-64, gzipped)
and falls back to a system `godot` on PATH.

### Continuous Integration

[![GUT Tests](https://github.com/absent-mynd/puzzle/actions/workflows/gut-tests.yml/badge.svg)](https://github.com/absent-mynd/puzzle/actions/workflows/gut-tests.yml)

All pull requests run the full suite via GitHub Actions (Ubuntu 22.04, Godot 4.3.0).
Tests must pass before merging. To reproduce the CI environment locally:

```bash
docker run --rm -v $(pwd):/workspace -w /workspace \
  barichello/godot-ci:4.3 \
  bash -c "godot --headless --import --quit && \
           godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/ -gexit"
```

### Pre-Push Hook (optional)

Runs the suite locally before pushing, so failures surface before CI:

```bash
./setup-hooks.sh
```

Skips gracefully if Godot is not on PATH. Bypass with `git push --no-verify`.

## Contributing

1. Write the test first — the suite is the spec.
2. Ensure all tests pass before committing.
3. Respect the layering: the kernel never depends on the world.

## History

The project previously carried a second, top-down grid-based build alongside this
one. It was removed on 2026-08-04; see `AGENTS.md` for what that means in practice.
The pre-consolidation tree is commit `8bf8193` (tagged `topdown-archive` locally).

## Resources

- [GUT Documentation](https://gut.readthedocs.io/)
- [Godot 4 Documentation](https://docs.godotengine.org/)
