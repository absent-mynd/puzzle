#!/bin/bash
# Launch the world editor for Space Folding.
#
# Usage:
#   ./run_editor.sh                          # edit worlds/overworld.json
#   ./run_editor.sh testbed                  # edit worlds/testbed.json
#   ./run_editor.sh worlds/other.json        # edit another world
#   ./run_editor.sh -h, --help
#
# The editor is a scene in this project, not a Godot editor plugin, so it runs the
# same way the game does — and it draws terrain with the game's own tileset. It
# WRITES to the world file, so run it from a working tree you can revert.
#
# From inside it, F5 plays the world you are editing and F6 plays from the cell under
# the cursor, unsaved edits and all; Escape brings you back to the editor exactly as
# you left it. See docs/features/SHELL.md.
#
# This is `./run.sh --edit`, which is the whole of what it does now — the editor and
# the game are two screens of one app (`scenes/Shell.tscn`). Kept because it is the
# command the docs have said for months, and because "edit the world" deserves a name.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

exec "${SCRIPT_DIR}/run.sh" --edit "$@"
