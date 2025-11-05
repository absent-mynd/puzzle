#!/bin/bash
# Test runner script for Space Folding Puzzle Game
# This script runs all GUT tests using the Godot engine

# Check if godot is available
if ! command -v godot &> /dev/null; then
    echo "Error: Godot 4 is not installed or not in PATH"
    echo "Please install Godot 4.3 or higher from https://godotengine.org/"
    exit 1
fi

# Check Godot version
GODOT_VERSION=$(godot --version | head -n 1)
echo "Using Godot: $GODOT_VERSION"
echo ""

# Run tests
echo "Running GUT tests..."
echo "===================="
godot --path . --headless -s addons/gut/gut_cmdln.gd "$@"

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
