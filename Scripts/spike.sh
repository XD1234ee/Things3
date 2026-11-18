#!/usr/bin/env bash
# Phase 0 test: checks that Daybreak can read from and write to Things on this Mac.
#
#   Scripts/spike.sh            read-only: connection check and read timings
#   Scripts/spike.sh --write    also creates one test to-do, moves it around,
#                               completes it and deletes it (it ends up in Things' Trash)
#
# The first run triggers macOS's "Terminal wants to control Things3" prompt; allow it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/DaybreakCore/Sources/DaybreakCore/Resources/things.js"

run() { osascript -l JavaScript "$JS" "$@"; }

echo "== Connection"
run ping
echo

echo "== Read timings (per list: number of open to-dos, milliseconds)"
run bench
echo

echo "== First 3 to-dos in Today"
run lists today | osascript -l JavaScript -e '
function run(argv) {
  const data = JSON.parse(argv[0]);
  return JSON.stringify(data.today.slice(0, 3), null, 2);
}' "$(cat)"
echo

if [[ "${1:-}" == "--write" ]]; then
  echo "== Write self-test"
  run selftest
  echo
  echo "Write self-test passed."
fi
