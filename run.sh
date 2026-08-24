#!/bin/bash
# Launch Space Folding.
#
# Usage:
#   ./run.sh                            # the launcher: pick a world to play or edit
#   ./run.sh testbed                    # play worlds/testbed.json
#   ./run.sh worlds/other.json          # play another world
#   ./run.sh --edit                     # edit worlds/overworld.json
#   ./run.sh --edit testbed             # edit worlds/testbed.json
#   ./run.sh -h, --help
#
# Everything runs inside one scene — `scenes/Shell.tscn`, the project's main scene —
# which is what lets the editor drop you into a run of the world you are editing (F5,
# or F6 from the cursor) and Escape bring you back to it untouched. See
# docs/features/SHELL.md.
#
# `./run_editor.sh` is this with --edit, kept because it is what the docs have always
# said. Naming a world here is the SAME flag the game and the editor both read
# (`WorldData.selected_path`), so neither can disagree about which world a run means.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_GODOT="${SCRIPT_DIR}/tools/godot/godot"
LOCAL_GODOT_GZ="${SCRIPT_DIR}/tools/godot/godot.gz"

EDIT=""
WORLD=""
for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --edit)    EDIT="--edit" ;;
        *)         WORLD="$arg" ;;
    esac
done

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
USER_ARGS=()
if [ -n "$WORLD" ]; then
    case "$WORLD" in
        res://*)   ;;
        /*)        WORLD="res://$(realpath --relative-to="$SCRIPT_DIR" "$WORLD")" ;;
        */*|*.*)   WORLD="res://$WORLD" ;;
        *)         WORLD="res://worlds/$WORLD.json" ;;
    esac
    USER_ARGS+=("--world=$WORLD")
fi
[ -n "$EDIT" ] && USER_ARGS+=("$EDIT")

if [ ${#USER_ARGS[@]} -gt 0 ]; then
    VERB="Playing"
    [ -n "$EDIT" ] && VERB="Editing"
    echo "$VERB ${WORLD:-the shipped world}"
    exec "$GODOT_BIN" --path "$SCRIPT_DIR" -- "${USER_ARGS[@]}"
fi
exec "$GODOT_BIN" --path "$SCRIPT_DIR"
