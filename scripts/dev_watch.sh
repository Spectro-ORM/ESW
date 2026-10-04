#!/bin/bash
# Development watch script for ESW
# Watches .esw and .heex files and rebuilds when they change
#
# Usage:
#   ./scripts/dev_watch.sh
#
# Requirements:
#   - fswatch 1.22+ (install via: brew install fswatch)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🔍 Watching .esw and .heex files in $PROJECT_ROOT"
echo "🔄 Will rebuild on changes..."
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Include templates, then exclude generated files even if they are templates.
fswatch -o -r "$PROJECT_ROOT" --event=Updated --event=Created --event=Removed --event=Renamed \
  --extended \
  --filter-mode=conjunctive \
  --include='\.(esw|heex)$' \
  --exclude='/\.(build|git)(/|$)' | while read -r num; do
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
