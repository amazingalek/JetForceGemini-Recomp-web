#!/usr/bin/env bash
# Records src/rt64_shaders.txt, the shaders the web page builds before the game and a planet at a time, by code rather
# than by playing: N64Recomp-browser's tools/record_shaders.mjs serves the page built in <build dir>
# (web-build/build-web), drives it in headless Chrome through tools/shader_plan.json, a page load a section, in which
# tools/shader_survey.js warps to each room of a planet, and writes the list. Needs node 22 or later and Chrome. Then
# build the page again, so that it prebuilds the new list. A description the old list had and the recording didn't
# print is lost: to keep them, save the old list first and add those to the end in a section of their own.
#
#   bash tools/record_shaders.sh <build dir> <ROM> [--profile <dir>] [--port <n>] [--only <section>,...]
set -euo pipefail
[ $# -ge 2 ] || { sed -n '9p' "$0"; exit 1; }
cd "$(dirname "$0")/.."
build="$1" rom="$2"
shift 2
exec node lib/N64Recomp-browser/tools/record_shaders.mjs tools/shader_plan.json "$build" "$rom" src/rt64_shaders.txt "$@"
