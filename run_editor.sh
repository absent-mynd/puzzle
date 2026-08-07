#!/bin/bash
# Launch the world editor for Space Folding.
#
# Usage:
#   ./run_editor.sh                          # edit worlds/overworld.json
#   ./run_editor.sh testbed                  # edit worlds/testbed.json
#   ./run_editor.sh worlds/other.json        # edit another world
#   ./run_editor.sh -h, --help
#
# The editor is a scene in this project, not a Godot editor plugin, so it runs
# the same way the game does — and it draws terrain with the game's own tileset.
# It WRITES to the world file, so run it from a working tree you can revert.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_GODOT="${SCRIPT_DIR}/tools/godot/godot"
LOCAL_GODOT_GZ="${SCRIPT_DIR}/tools/godot/godot.gz"
EDITOR_SCENE="res://scenes/editor/WorldEditor.tscn"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

# Decompress the bundled Godot if needed (same as run_tests.sh).
if [ ! -f "$LOCAL_GODOT" ] && [ -f "$LOCAL_GODOT_GZ" ]; then
    echo "Decompressing Godot binary (first time only)..."
    gunzip -k "$LOCAL_GODOT_GZ"
    chmod +x "$LOCAL_GODOT"
fi

# The bundled binary is Linux x86-64; probe it rather than assuming it runs here.
godot_runnable() {
    "$1" --version >/dev/null 2>&1
}

GODOT_BIN=""
if [ -f "$LOCAL_GODOT" ] && godot_runnable "$LOCAL_GODOT"; then
    GODOT_BIN="$LOCAL_GODOT"
elif command -v godot &> /dev/null && godot_runnable godot; then
    GODOT_BIN="godot"
else
    echo "Error: no runnable Godot 4 found."
    echo "  - Bundled binary at $LOCAL_GODOT is missing or not for this platform"
    echo "  - System 'godot' not found on PATH"
    echo ""
    echo "Install Godot 4.x (https://godotengine.org/) or place a binary for THIS"
    echo "platform at tools/godot/godot. The bundled one is Linux x86-64."
    exit 1
fi

# A world may be given as a bare name (worlds/<name>.json), as res://..., or as a
# path relative to the project. The bare form matches what `--world=` accepts.
WORLD_ARGS=()
if [ -n "$1" ]; then
    WORLD="$1"
    case "$WORLD" in
        res://*)   ;;
        /*)        WORLD="res://$(realpath --relative-to="$SCRIPT_DIR" "$WORLD")" ;;
        */*|*.*)   WORLD="res://$WORLD" ;;
        *)         WORLD="res://worlds/$WORLD.json" ;;
    esac
    WORLD_ARGS=(-- "--world=$WORLD")
    echo "Editing $WORLD"
fi

exec "$GODOT_BIN" --path "$SCRIPT_DIR" "$EDITOR_SCENE" "${WORLD_ARGS[@]}"
