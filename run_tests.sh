#!/bin/bash
# Test runner script for Space Folding Puzzle Game
# This script runs all GUT tests using the Godot engine
#
# Usage:
#   ./run_tests.sh                           # Run all tests
#   ./run_tests.sh test_file_name            # Run specific test file (e.g., test_fold_system)
#   ./run_tests.sh path/to/test_file.gd      # Run specific test file by path
#   ./run_tests.sh -h, --help                # Show help message
#
# You can also pass GUT command line options directly:
#   ./run_tests.sh -gtest=res://scripts/tests/test_fold_system.gd

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_GODOT="${SCRIPT_DIR}/tools/godot/godot"
LOCAL_GODOT_GZ="${SCRIPT_DIR}/tools/godot/godot.gz"

# Function to show help message
show_help() {
    echo "Space Folding Puzzle Game - Test Runner"
    echo ""
    echo "Usage:"
    echo "  ./run_tests.sh                           # Run all tests"
    echo "  ./run_tests.sh test_file_name            # Run specific test file"
    echo "  ./run_tests.sh path/to/test_file.gd      # Run specific test file by path"
    echo "  ./run_tests.sh -h, --help                # Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./run_tests.sh                           # Run all tests"
    echo "  ./run_tests.sh test_fold_system          # Run test_fold_system.gd"
    echo "  ./run_tests.sh test_geometry_core        # Run test_geometry_core.gd"
    echo "  ./run_tests.sh scripts/tests/test_fold_system.gd"
    echo ""
    echo "Advanced (GUT command line options):"
    echo "  ./run_tests.sh -gtest=res://scripts/tests/test_fold_system.gd"
    echo "  ./run_tests.sh -gdir=res://scripts/tests/"
    echo ""
    exit 0
}

# Parse command line arguments
TEST_ARGS=""
if [ $# -eq 0 ]; then
    # No arguments - run all tests (default behavior)
    TEST_ARGS=""
elif [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_help
elif [ "${1:0:1}" == "-" ]; then
    # Argument starts with '-' - pass through to GUT directly
    TEST_ARGS="$@"
else
    # Argument doesn't start with '-' - treat as test file name or selection string
    TEST_SELECTOR="$1"

    # Remove .gd extension if present
    TEST_SELECTOR="${TEST_SELECTOR%.gd}"
    # Remove test_ prefix if present
    TEST_SELECTOR="${TEST_SELECTOR#test_}"
    # Remove path components if present
    TEST_SELECTOR="${TEST_SELECTOR##*/}"

    # Use -gselect to run tests matching the selector
    # -gselect will filter scripts that contain the selector string in their filename
    TEST_ARGS="-gselect=$TEST_SELECTOR"
    echo "Running tests matching: $TEST_SELECTOR"
    echo ""
fi

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
if [ -z "$TEST_ARGS" ]; then
    "$GODOT_BIN" --path . --headless -s addons/gut/gut_cmdln.gd
else
    "$GODOT_BIN" --path . --headless -s addons/gut/gut_cmdln.gd $TEST_ARGS
fi

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
