#!/usr/bin/env bash
# Builds the web page, web-build/build-web/JetForceGeminiRecompiled.html, from this checkout and your ROM (BUILDING.md says
# what it needs and how to serve it):
#
#   tools/build_web.sh [path/to/rom.z64]
#   tools/build_web.sh --patches          the patch step alone: no ROM, and only git, CMake and Python
#
# The ROM defaults to baserom.us.z64 next to build_linux.sh, and is needed once: its copy stays in web-build/. Safe
# to run again after a pull: every step skips what is done or redoes only what changed. Extra arguments for the page's
# CMake configure go in $WEB_CMAKE_ARGS (it runs once per build dir: delete web-build/build-web/build.ninja to
# configure again). --patches stops once everything is patched, which N64Recomp-browser's CI runs with its own checkout
# as lib/N64Recomp-browser, so a change there that stops this repo's patches applying is red where it is made.
#
# The page is the base project build_linux.sh builds, with the same JFG patches, in web-build/, but its libraries are
# at the upstream commits N64Recomp-browser's patches are made on (lib/N64Recomp-browser/patches/patches.txt), with
# the web support patched in, and then the base project's and JFG's own changes to them, made again for those commits:
#   patches/web/rt64.patch              the base's rt64 changes (Dinosaur Planet's, F3DDKR) and patches/rt64-jfg.patch
#   patches/web/N64ModernRuntime.patch  the base's runtime changes (sound, a display list parsed before its task ends)
#   patches/web/dkr.patch               the base project's own code for the page: the canvas, the menus' WGSL shaders,
#                                       sound on the browser's audio thread, the file picker, no mods or Exit
# The recompiled code is made by N64Recomp patched for the web (N64Recomp-browser): it writes the tail calls as
# return_calls and keeps the FPU's rounding mode for float-to-int conversions, which WebAssembly's own instructions
# can't. That N64Recomp has no call tracking for the crash log (the base's recomp_enter_function and
# recomp_exit_function), so jfg.us.toml's hooks lose their recomp_exit_function() calls in the copy it reads, which
# also takes the page's own hooks (patches/web/jfg.us.web.toml).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES_ONLY=false
if [ "${1:-}" = --patches ]; then PATCHES_ONLY=true; shift; fi
ROM="${1:-$HERE/baserom.us.z64}"
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
WORK="$HERE/web-build"
BROWSER="$HERE/lib/N64Recomp-browser"
BASE_URL=https://github.com/cyscott/dkr-recomp.git
BASE_COMMIT="$(sed -n 's/^BASE_COMMIT=//p' "$HERE/build_linux.sh")"
ROM_SHA1="$(sed -n 's/^ROM_SHA1=//p' "$HERE/build_linux.sh")"
step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nError: %s\n' "$*" >&2; exit 1; }

[ -f "$BROWSER/patches/patches.txt" ] || fail "lib/N64Recomp-browser is missing: git submodule update --init lib/N64Recomp-browser"
TOOLS="git cmake ninja clang clang++ python3 emcmake embuilder"
! $PATCHES_ONLY || TOOLS="git cmake python3"
for t in $TOOLS; do command -v "$t" > /dev/null || fail "$t not found"; done
upstream() { awk -v n="$1" '$1 == n { print $4 }' "$BROWSER/patches/patches.txt"; }

# ---------------------------------------------------------------- the base project
if [ ! -d "$WORK/.git" ]; then
    step "Downloading the base project into web-build/"
    git clone -q "$BASE_URL" "$WORK"
    git -C "$WORK" checkout -q --detach "$BASE_COMMIT"
    git -C "$WORK" submodule update --init --recursive --depth 1
fi
cd "$WORK"

# ---------------------------------------------------------------- the patches
# Everything is patched from scratch whenever the patches, or what they patch, aren't as this left them.
LIBS="lib/rt64 lib/N64ModernRuntime lib/N64Recomp"
patched_state() {
    {
        echo "$BASE_COMMIT"
        cat "$BROWSER"/patches/*.patch "$HERE"/patches/*.patch "$HERE"/patches/web/*.patch submodule-patches/n64recomp-dkr.patch
        git -C "$HERE" ls-files -s src include assets icons tools jfg.us.toml jfg.us.syms.toml rsp-aspMain.jfg.toml version.txt
        git -C "$HERE" diff HEAD -- src include assets icons tools jfg.us.toml jfg.us.syms.toml rsp-aspMain.jfg.toml version.txt
        git diff HEAD
        for lib in $LIBS; do
            git -C "$lib" rev-parse HEAD
            git -C "$lib" diff HEAD
            git -C "$lib" submodule foreach --recursive -q 'git rev-parse HEAD && git diff HEAD'
        done
    } | git hash-object --stdin
}
PATCHED="$(git rev-parse --git-dir)/web-patched"
if [ "$(cat "$PATCHED" 2> /dev/null)" != "$(patched_state 2> /dev/null)" ]; then
    step "Patching the base project and its libraries"
    # The libraries at N64Recomp-browser's upstream commits, clean.
    moveto() { # <lib> <upstream repository> <commit>
        if [ "$(git -C "$1" rev-parse HEAD)" != "$3" ]; then
            git -C "$1" fetch -q --depth 1 "$2" "$3"
            git -C "$1" checkout -q -f --detach "$3"
        fi
        git -C "$1" submodule foreach --recursive -q 'git reset -q --hard && git clean -fdq'
        git -C "$1" reset -q --hard
        git -C "$1" clean -fdq
        git -C "$1" submodule update -q --init --recursive --depth 1
    }
    moveto lib/rt64 https://github.com/rt64/rt64 "$(upstream rt64)"
    moveto lib/N64ModernRuntime https://github.com/N64Recomp/N64ModernRuntime "$(upstream N64ModernRuntime)"
    moveto lib/N64Recomp https://github.com/N64Recomp/N64Recomp "$(upstream N64Recomp)"
    git checkout -q -f -- .
    git clean -fdq -- src include assets icons tools shaders

    # The web support (N64Recomp-browser), then the base's and JFG's changes on top.
    web_patch() { cmake -P "$BROWSER/patches/apply.cmake" "$@"; }
    web_patch rt64 lib/rt64
    web_patch plume lib/rt64/src/contrib/plume
    web_patch hlslpp lib/rt64/src/contrib/hlslpp
    web_patch N64ModernRuntime lib/N64ModernRuntime
    web_patch N64Recomp lib/N64ModernRuntime/N64Recomp
    web_patch N64Recomp lib/N64Recomp
    git -C lib/rt64 apply "$HERE/patches/web/rt64.patch"
    git -C lib/N64ModernRuntime apply "$HERE/patches/web/N64ModernRuntime.patch"
    git -C lib/N64Recomp apply --recount "$WORK/submodule-patches/n64recomp-dkr.patch"

    # JFG on the base project, as build_linux.sh does it, then the page's changes.
    git apply --recount "$HERE/patches/jfg-base.patch"
    python3 "$HERE/tools/set_version.py" "$HERE/version.txt" .
    mkdir -p src/jfg include tools assets/jfg_launcher
    cp "$HERE"/src/jfg/*.cpp "$HERE"/src/jfg/*.h "$HERE"/src/jfg/*.inc src/jfg/
    cp "$HERE"/assets/config_menu/jfg_*.rml assets/config_menu/
    cp "$HERE"/assets/jfg_launcher/* assets/jfg_launcher/
    cp "$HERE"/include/*.h include/
    cp "$HERE"/icons/* icons/
    cp "$HERE"/jfg.us.toml "$HERE"/jfg.us.syms.toml "$HERE"/rsp-aspMain.jfg.toml .
    cp "$HERE"/tools/*.py "$HERE"/tools/jfg.us.dynamic_relocs.json tools/
    git apply "$HERE/patches/web/dkr.patch"
    # The shaders the page builds before the game starts (CMakeLists.txt's RT64_PREBUILT_SHADER_LIST).
    [ ! -f "$HERE/src/rt64_shaders.txt" ] || cp "$HERE/src/rt64_shaders.txt" src/
    patched_state > "$PATCHED"
fi
! $PATCHES_ONLY || { step "Patched"; exit 0; }

# ---------------------------------------------------------------- the recompiled code
step "Building the recompilers"
if [ ! -f build-tools/build.ninja ]; then
    cmake -S lib/N64Recomp -B build-tools -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER="${HOST_CC:-clang}" -DCMAKE_CXX_COMPILER="${HOST_CXX:-clang++}" > /dev/null
fi
cmake --build build-tools --target N64RecompCLI RSPRecomp

if [ ! -f baserom.us.z64 ] || [ -f "$ROM" ]; then
    [ -f "$ROM" ] || fail "ROM not found: $ROM (your Jet Force Gemini US ROM, or pass its path)"
    [ "$(sha1sum "$ROM" | cut -d' ' -f1)" = "$ROM_SHA1" ] || fail "wrong ROM: expected SHA-1 $ROM_SHA1 (US, .z64)"
    cmp -s "$ROM" baserom.us.z64 || cp -f "$ROM" baserom.us.z64
fi

step "Recompiling the game"
# Only the files that changed are replaced, so the page's build recompiles only those.
[ -f baserom.us.recomp.z64 ] && [ baserom.us.recomp.z64 -nt baserom.us.z64 ] ||
    python3 tools/prepare_overlays.py baserom.us.z64 - baserom.us.recomp.z64 - tools/jfg.us.dynamic_relocs.json
cat jfg.us.toml "$HERE/patches/web/jfg.us.web.toml" |
    sed -e 's/ recomp_exit_function();//g' -e 's|^output_func_path = .*|output_func_path = "RecompiledFuncs.new"|' > jfg.us.web.toml
rm -rf RecompiledFuncs.new && mkdir -p RecompiledFuncs.new RecompiledFuncs
./build-tools/N64Recomp jfg.us.web.toml > recomp.log 2>&1 || { tail -20 recomp.log; fail "N64Recomp failed (web-build/recomp.log)"; }
python3 tools/merge_gen_anim_data.py RecompiledFuncs.new
python3 tools/fix_dynamic_relocs.py RecompiledFuncs.new tools/jfg.us.dynamic_relocs.json baserom.us.recomp.z64 jfg.us.syms.toml
for file in RecompiledFuncs.new/*; do
    cmp -s "$file" "RecompiledFuncs/${file##*/}" || cp "$file" RecompiledFuncs/
done
for file in RecompiledFuncs/*; do
    [ -e "RecompiledFuncs.new/${file##*/}" ] || rm "$file"
done
rm -rf RecompiledFuncs.new
mkdir -p rsp
./build-tools/RSPRecomp rsp-aspMain.jfg.toml > /dev/null

# ---------------------------------------------------------------- the page
step "Building the page"
# The Emscripten ports CMake finds and the build depends on.
embuilder build sdl2-mt freetype-legacysjlj > /dev/null
if [ ! -f build-web/build.ninja ]; then
    emcmake cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release ${WEB_CMAKE_ARGS:-}
fi
cmake --build build-web --target JetForceGeminiRecompiled

printf '\nDone: %s/build-web/JetForceGeminiRecompiled.html (BUILDING.md says how to serve it).\n' "$WORK"
