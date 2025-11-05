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

#### Running Tests in Godot Editor
1. Open the project in Godot 4
2. Go to Project → Project Settings → Plugins
3. Enable the "Gut" plugin
4. Access the GUT panel from the bottom panel tabs
5. Click "Run All" to execute all tests

#### Running Tests from Command Line

To run tests from the command line (useful for CI/CD):

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
