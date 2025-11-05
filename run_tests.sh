#!/bin/bash
# Test runner script for Space Folding Puzzle Game
# This script runs all GUT tests using the Godot engine

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_GODOT="${SCRIPT_DIR}/tools/godot/godot"
LOCAL_GODOT_GZ="${SCRIPT_DIR}/tools/godot/godot.gz"

# Decompress Godot if needed
if [ ! -f "$LOCAL_GODOT" ] && [ -f "$LOCAL_GODOT_GZ" ]; then
    echo "Decompressing Godot binary (first time only)..."
    gunzip -k "$LOCAL_GODOT_GZ"
    chmod +x "$LOCAL_GODOT"
    echo "Godot decompressed successfully."
fi

# Check for local Godot first, then system Godot
if [ -f "$LOCAL_GODOT" ]; then
    GODOT_BIN="$LOCAL_GODOT"
    echo "Using local Godot binary from tools/godot/"
elif command -v godot &> /dev/null; then
    GODOT_BIN="godot"
    echo "Using system Godot"
else
    echo "Error: Godot 4 is not found"
    echo "  - Local binary not found at: $LOCAL_GODOT"
    echo "  - System godot not found in PATH"
    echo ""
    echo "Please either:"
    echo "  1. Place Godot 4.3 binary at tools/godot/godot"
    echo "  2. Install Godot 4.3 or higher from https://godotengine.org/"
    exit 1
fi

# Check Godot version
GODOT_VERSION=$("$GODOT_BIN" --version | head -n 1)
echo "Using Godot: $GODOT_VERSION"
echo ""

# Import project first (required for GUT classes to be recognized)
echo "Importing project..."
"$GODOT_BIN" --path . --headless --import --quit
echo ""

# Run tests
echo "Running GUT tests..."
echo "===================="
"$GODOT_BIN" --path . --headless -s addons/gut/gut_cmdln.gd "$@"

# Capture exit code
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "All tests passed!"
else
    echo ""
    echo "Tests failed with exit code: $EXIT_CODE"
fi

exit $EXIT_CODE
