#!/usr/bin/env bash
#
# Watches .esw files and rebuilds on change.
# Requires: fswatch (brew install fswatch)
#
# Usage: ./scripts/dev_watch.sh [source_dir]
#   source_dir defaults to Sources/

set -euo pipefail

SOURCE_DIR="${1:-Sources}"

if ! command -v fswatch &>/dev/null; then
    echo "Error: fswatch is required. Install with: brew install fswatch" >&2
    exit 1
fi

echo "Watching .esw files in ${SOURCE_DIR}/ for changes..."
echo "Press Ctrl+C to stop."

fswatch -o --include='\.esw$' --exclude='.*' "$SOURCE_DIR" | while read -r _; do
    echo ""
    echo "--- Change detected, rebuilding... ---"
    swift build 2>&1
    echo "--- Done ---"
done
