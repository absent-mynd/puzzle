#!/bin/bash
# Git Hooks Setup Script
# This script installs the pre-push hook that runs GUT tests before pushing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SOURCE="${SCRIPT_DIR}/.githooks/pre-push"
HOOK_DEST="${SCRIPT_DIR}/.git/hooks/pre-push"

echo "========================================"
echo "Git Hooks Setup"
echo "========================================"
echo ""

# Check if source hook exists
if [ ! -f "$HOOK_SOURCE" ]; then
    echo "❌ Error: Hook source not found at $HOOK_SOURCE"
    exit 1
fi

# Check if destination already exists
if [ -f "$HOOK_DEST" ]; then
    echo "⚠️  Warning: Pre-push hook already exists"
    read -p "Do you want to overwrite it? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted. No changes made."
        exit 0
    fi
    echo ""
fi

# Copy the hook
echo "📋 Installing pre-push hook..."
cp "$HOOK_SOURCE" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo "✅ Pre-push hook installed successfully!"
echo ""
echo "========================================"
echo "What happens now?"
echo "========================================"
echo ""
echo "The pre-push hook will:"
echo "  1. Run automatically before every 'git push'"
echo "  2. Execute the GUT test suite (takes 1-3 minutes)"
echo "  3. Block the push if tests fail"
echo "  4. Gracefully skip if Godot is not installed"
echo ""
echo "Requirements:"
echo "  • Godot 4.3+ installed and in your PATH"
echo "  • Download from: https://godotengine.org/download"
echo ""
echo "To bypass the hook (not recommended):"
echo "  git push --no-verify"
echo ""
echo "To uninstall:"
echo "  rm .git/hooks/pre-push"
echo ""
echo "========================================"
echo ""
