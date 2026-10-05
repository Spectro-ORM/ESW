#!/bin/bash
# Keep signed SwiftPM products outside file-provider-managed source folders.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
package_path="$project_root/Integrations/PeregrineLive"
checkout_id="$(printf '%s' "$package_path" | shasum -a 256 | cut -c 1-16)"

if [[ "$(uname -s)" == Darwin ]]; then
    cache_root="$HOME/Library/Caches"
else
    cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
fi
scratch_path="${ESW_LIVE_SCRATCH_PATH:-$cache_root/esw-live/$checkout_id}"
swift_options=(--package-path "$package_path" --scratch-path "$scratch_path")

action="${1:-run}"
if [[ $# -gt 0 ]]; then shift; fi
case "$action" in
    run) exec swift run "${swift_options[@]}" "$@" LiveDemo ;;
    build) exec swift build "${swift_options[@]}" --product LiveDemo "$@" ;;
    test) exec swift test "${swift_options[@]}" "$@" ;;
    bin-path) exec swift build "${swift_options[@]}" --show-bin-path "$@" ;;
    -h|--help) printf 'Usage: %s [run|build|test|bin-path] [SwiftPM options]\n' "$0" ;;
    *) printf 'Unknown action: %s\n' "$action" >&2; exit 2 ;;
esac
