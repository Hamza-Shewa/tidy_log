#!/usr/bin/env bash
# Compiles the tidy_flutter wrapper to build/tidy_flutter (a native binary, so
# F5 does not wait for Dart to compile it on every launch).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/packages/tidy_log_core"
dart pub get >/dev/null
mkdir -p "$root/build"
dart compile exe bin/tidy_flutter.dart -o "$root/build/tidy_flutter"
echo
echo "Wrapper ready: $root/build/tidy_flutter"
echo "Use it as \"customTool\" in .vscode/launch.json (see README)."
