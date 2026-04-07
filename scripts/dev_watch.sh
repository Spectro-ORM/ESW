#!/bin/bash
# Development watch script for ESW
# Watches .esw files and rebuilds when they change
#
# Usage:
#   ./scripts/dev_watch.sh
#
# Requirements:
#   - fswatch (install via: brew install fswatch)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔍 Watching .esw files in $PROJECT_ROOT"
echo "🔄 Will rebuild on changes..."
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Watch for .esw file changes and rebuild
fswatch -o "$PROJECT_ROOT" --event=Updated --event=Created --event=Removed \
  --exclude=".build" \
  --exclude=".git" \
  --extended \
  '\.esw$' | while read -r num; do
  echo ""
  echo "📝 Changes detected ($num file(s) affected)"
  echo "🔨 Rebuilding..."
  if swift build 2>&1; then
    echo "✅ Build successful"
  else
    echo "❌ Build failed"
  fi
  echo ""
  echo "Waiting for changes..."
done
