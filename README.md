# Space Folding Puzzle Game

A puzzle game with space-folding mechanics built with Godot 4.

## Project Overview

This is a geometric puzzle game where players fold space to solve challenges. The game features:
- Grid-based puzzle solving
- Space-folding mechanics
- Test-driven development approach

## Development Setup

### Prerequisites
- Godot 4.3 or higher
- Git

### Testing Framework

This project uses **GUT (Godot Unit Test)** v9.4.0 for automated testing.

### Continuous Integration (CI/CD)

[![GUT Tests](https://github.com/absent-mynd/puzzle/actions/workflows/gut-tests.yml/badge.svg)](https://github.com/absent-mynd/puzzle/actions/workflows/gut-tests.yml)

All pull requests automatically run the full GUT test suite via GitHub Actions. Tests must pass before merging.

**Workflow details:**
- Runs on: Ubuntu 22.04
- Godot version: 4.3.0
- Test directory: `res://scripts/tests/`
- Trigger: All PRs and pushes to `main`

You can also manually trigger the workflow from the Actions tab in GitHub.

### Pre-Push Hook (Optional but Recommended)

A pre-push hook is available to run GUT tests locally before pushing to remote. This provides early feedback and catches issues before CI runs.

**Benefits:**
- ✅ Catches test failures before pushing to remote
- ✅ Runs 3-5 times per day (vs. CI-only approach)
- ✅ Gracefully handles missing Godot installation
- ✅ Takes 1-3 minutes per push (acceptable for most workflows)
- ✅ Can be bypassed with `--no-verify` if needed

**Installation:**

```bash
# Run the setup script
./setup-hooks.sh

# Or manually install
cp .githooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

**Requirements:**
- Godot 4.3+ installed and available in your PATH
- Download from: https://godotengine.org/download

**Usage:**
The hook runs automatically on `git push`. If tests fail:
- Fix the failing tests and push again (recommended)
- Use `git push --no-verify` to bypass (not recommended)

**Note:** If Godot is not installed, the hook will skip gracefully with a warning, and tests will still run in CI.

#### Running Tests in Godot Editor
1. Open the project in Godot 4
2. Go to Project → Project Settings → Plugins
3. Enable the "Gut" plugin
4. Access the GUT panel from the bottom panel tabs
5. Click "Run All" to execute all tests

#### Running Tests from Command Line

To run tests from the command line (useful for local CI/CD):

```bash
# Run all tests
godot --path . --headless -s addons/gut/gut_cmdln.gd

# Run tests in a specific directory
godot --path . --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/

# Run a specific test file
godot --path . --headless -s addons/gut/gut_cmdln.gd -gtest=res://scripts/tests/test_example.gd

# Generate JUnit XML report for CI integration
godot --path . --headless -s addons/gut/gut_cmdln.gd -gxml=test_results.xml
```

#### Running Tests Locally with Docker

To run tests in the same environment as CI:

```bash
# Run tests using the same Docker image as GitHub Actions
docker run --rm -v $(pwd):/workspace -w /workspace \
  barichello/godot-ci:4.3 \
  bash -c "godot --headless --import --quit && \
           godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://scripts/tests/ -gexit"
```

#### Writing Tests

Test files should:
- Be placed in `scripts/tests/` directory
- Extend `GutTest` class
- Have test methods starting with `test_`
- Use descriptive assertion messages

Example test structure:
```gdscript
extends GutTest

func test_something():
    assert_eq(5, 5, "Five should equal five")
```

See `scripts/tests/test_example.gd` for more assertion examples.

#### Available Assertions

Common assertions include:
- `assert_eq(a, b, msg)` - Assert equal
- `assert_ne(a, b, msg)` - Assert not equal
- `assert_gt(a, b, msg)` - Assert greater than
- `assert_lt(a, b, msg)` - Assert less than
- `assert_true(val, msg)` - Assert true
- `assert_false(val, msg)` - Assert false
- `assert_null(val, msg)` - Assert null
- `assert_not_null(val, msg)` - Assert not null
- `assert_almost_eq(a, b, epsilon, msg)` - Assert almost equal (for floats)

## Project Structure

```
SpaceFoldingPuzzle/
├── addons/
│   └── gut/              # GUT testing framework
├── scenes/
│   ├── main.tscn
│   ├── grid/
│   ├── player/
│   └── ui/
├── scripts/
│   ├── core/             # Cell, Grid, Fold classes
│   ├── systems/          # FoldSystem, UndoManager
│   ├── utils/            # GeometryCore, math utilities
│   └── tests/            # Unit and integration tests
└── assets/
    ├── sprites/
    └── shaders/
```

## Contributing

When contributing:
1. Write tests for new features
2. Ensure all tests pass before committing
3. Follow the existing code structure

## Resources

- [GUT Documentation](https://gut.readthedocs.io/)
- [Godot 4 Documentation](https://docs.godotengine.org/)
