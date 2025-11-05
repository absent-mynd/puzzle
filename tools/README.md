# Tools Directory

This directory contains development tools and utilities for the Space-Folding Puzzle Game project.

## Godot Engine

The `godot/` directory contains a local copy of the Godot Engine executable used for running tests and development.

### Current Version

- **Version**: Godot 4.3 Stable
- **Build**: 77dcf97d8 (Official)
- **Platform**: Linux x86_64
- **Compressed Size**: ~48 MB (godot.gz)
- **Uncompressed Size**: ~107 MB (auto-extracted on first use)

### Why is Godot Included?

The Godot executable is included in the repository to:
1. Ensure consistent test execution across different environments
2. Avoid repeated downloads in ephemeral CI/CD environments
3. Provide a ready-to-use development environment without external dependencies
4. Guarantee version compatibility for all contributors

### Automatic Decompression

The Godot binary is stored compressed (godot.gz) to stay under GitHub's 100 MB file size limit. The `run_tests.sh` script automatically decompresses it on first use:

```bash
# First run will decompress godot.gz to godot
./run_tests.sh
# Output: "Decompressing Godot binary (first time only)..."

# Subsequent runs use the decompressed binary directly
./run_tests.sh
# Output: "Using local Godot binary from tools/godot/"
```

The decompressed `godot` binary is gitignored and generated locally.

### Usage

The `run_tests.sh` script automatically detects and uses the local Godot binary:

```bash
# The script will use tools/godot/godot if available
./run_tests.sh

# Run specific tests
./run_tests.sh -gtest=test_cell.gd

# Run tests in a specific directory
./run_tests.sh -gdir=res://scripts/tests/
```

### Manual Usage

You can also run Godot directly:

```bash
# Check version
./tools/godot/godot --version

# Run tests manually
./tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd

# Import project assets
./tools/godot/godot --headless --path . --import --quit
```

### Updating Godot

To update to a newer version:

1. Download the new Godot Linux binary from https://godotengine.org/download
2. Replace `tools/godot/godot` with the new binary
3. Ensure it's executable: `chmod +x tools/godot/godot`
4. Test that it works: `./tools/godot/godot --version`
5. Run tests to verify compatibility: `./run_tests.sh`
6. Commit the updated binary

### Platform-Specific Notes

**Linux**: The included binary works on x86_64 Linux systems.

**macOS/Windows**: If you're on macOS or Windows, download the appropriate Godot binary for your platform and either:
- Replace the Linux binary with your platform's binary (not recommended for commits)
- Install Godot system-wide, and `run_tests.sh` will use it automatically

### Download Links

- Official Godot Downloads: https://godotengine.org/download
- Godot 4.3 Stable: https://github.com/godotengine/godot/releases/tag/4.3-stable

## Future Tools

This directory may contain additional development tools as the project grows:
- Custom build scripts
- Asset processing tools
- Validation utilities
