# Building the web page

This fork's `main` branch builds the game with [Emscripten](https://emscripten.org) into a page,
`JetForceGeminiRecompiled.html`, that draws through WebGPU. The desktop build is upstream's and unchanged: README.md's
Build and run.

The desktop build is [cyscott/dkr-recomp](https://github.com/cyscott/dkr-recomp), which `build_linux.sh` downloads,
with this repo's `patches/` and `src/jfg/` on top. The page is the same, built in `web-build/` by `tools/build_web.sh`
(its header says each step), with one difference: its `lib/rt64`, `lib/N64ModernRuntime` and `lib/N64Recomp` are
upstream's at the commits [N64Recomp-browser](https://github.com/amazingalek/N64Recomp-browser) (`lib/N64Recomp-browser`)
makes its patches on, with the web support patched in (its `patches/apply.cmake`), and the base project's and this
repo's changes to them made again for those commits on top:

- `patches/web/rt64.patch`: the base project's rt64 changes and `patches/rt64-jfg.patch`.
- `patches/web/N64ModernRuntime.patch`: the base project's runtime changes.
- `patches/web/dkr.patch`: the base project's own code for the page. RT64 draws on the page's canvas, the menus'
  shaders are WGSL, the sound plays on the browser's audio thread (N64Recomp-browser's `frontend/audio_output.h`), the
  ROM comes from the page's file picker, and saves and settings are kept in the browser.

The page needs recompiled code of its own: the web-patched N64Recomp writes a tail call as a `return_call` and keeps
the FPU's rounding mode for float-to-int conversions (WebAssembly's own instructions only round to nearest). That
N64Recomp has no call tracking for the crash log, so `jfg.us.toml`'s hooks lose their `recomp_exit_function()` calls in
the copy it reads.

What the page leaves out, since a browser can't do it: mods a player adds (the live recompiler writes machine code,
which a page can't load), texture packs (there is no folder to put one in), the debug window, the F10 toolbar and the
overlay (they draw through ImGui's Vulkan and Direct3D 12 backends), and Exit and Quit (a program that ends leaves the
page dead: a reload or closing the tab is the way out). The launcher lists only the keys the page has.

## What it needs

- The US ROM of Jet Force Gemini, once (`.z64`, SHA-1 `493ced9008dbe932d6e91179b68e8630cf23a023`): its copy is kept in
  `web-build/`.
- The [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html), installed and activated
  (`source emsdk_env.sh`).
- [naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga) on `PATH` (`cargo install naga-cli`), which turns the shaders
  into WGSL, and `spirv-opt` ([SPIRV-Tools](https://github.com/KhronosGroup/SPIRV-Tools)), without which the shaders
  come out about twice the size.
- A host clang and clang++ for the recompiler (`HOST_CC` and `HOST_CXX` pick others), CMake 3.20+, Ninja, git and
  Python 3.
- [ccache](https://ccache.dev) on `PATH`, optional: a second build dir then compiles nothing that was compiled before.

It was built on Linux, in the Docker image N64Recomp-browser's README describes.

## Building

```bash
git clone --recursive https://github.com/amazingalek/JetForceGemini-Recomp-web
cd JetForceGemini-Recomp-web
tools/build_web.sh path/to/baserom.us.z64
```

Run again after a pull, without the ROM: each step skips what is done or redoes only what changed. `WEB_CMAKE_ARGS`
goes to the configure (`-DN64RECOMP_BROWSER_FAST_LINK=ON` for a quick link while trying something, never for a page
people play). `tools/build_web.sh --patches` stops once everything is patched and needs no ROM: N64Recomp-browser's CI
runs it over its own checkout, so a change there that stops this repo's patches applying is caught where it is made.

`web-build/build-web` then holds `JetForceGeminiRecompiled.html`, `.js`, `.wasm`, `.data` and `coi_serviceworker.js`.
The page must be cross-origin isolated: serve the folder with `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`, or on a host that can't set headers (GitHub Pages), as is, and
`coi_serviceworker.js` sets them after one reload. The player picks their ROM in the launcher; it, the settings and the
saves are kept in the browser's IndexedDB for that origin.

## The shaders

The page builds the game's shaders from `src/rt64_shaders.txt` (`RT64_PREBUILT_SHADER_LIST`, which `dkr.patch` sets
in `CMakeLists.txt`), in sections, one a planet. In Chrome they are built in the background, and the game
waits only when a frame wants 4 or more that aren't built yet, under a small "Preparing graphics" indicator in a
corner; Chrome keeps them for the visits after. Firefox builds a pipeline in line with the rest of its GPU work, so
there the game waits instead: on its first frame for the list's boot, and for a planet's section when a frame first
wants 4 of its shaders. Without them RT64 would draw with its ubershader meanwhile, which integrated graphics can't
keep up with. A shader the list missed is built behind the game, and the page remembers it and builds it with the
rest on the next visit.

The list is recorded by code, not by hand: `tools/shader_plan.json` (written by `tools/make_plans.py`, whose docstring
says how it plays) is a plan for N64Recomp-browser's `tools/record_shaders.mjs`, which boots the page, starts a new
game and, for each section, warps to every room of one planet with `tools/shader_survey.js`, looking around in each,
and in a load of its own to the planet's bosses, cutscene or race that draw shaders its rooms don't, fighting there.
The warp is the one the desktop build's F10 toolbar has (`src/jfg/jfg_debug_menu.cpp`), which the page's build
exports to the survey as `jfg_web_warp`. To record again, after `tools/build_web.sh`:

```bash
python3 tools/make_plans.py
bash tools/record_shaders.sh web-build/build-web <rom>
tools/build_web.sh
```

then put back the list's header, which says what was played.

## How it plays

How the page plays in Chrome and Firefox, run by run, is recorded in N64Recomp-browser's
[plays.jsonl](https://github.com/amazingalek/N64Recomp-browser/blob/main/plays.jsonl) and its
[games table](https://github.com/amazingalek/N64Recomp-browser#games).

On the page the Graphics menu's Framerate is Display by default, where the desktop build's is Original:
`patches/web/dkr.patch` sets `rr_default` with Emscripten and moves a page's settings saved before graphics config
version 6 to Display once, so RT64 interpolates between the game's frames to the display's rate. Before
N64Recomp-browser v0.54.0 it interpolates only now and then in play: the game's shadows' display
list before each frame's reads as a frame of its own, and the game's frames take 2 and 3 VIs, which rt64 179adb8
handles. The game's own Frame Rate setting (Visuals) stays Original, 30 frames a second dropping to 20 when a
frame runs long, as on the N64. On the page every frame does:
the game sends two display lists a frame, and each takes RT64 10-12 ms with the exact copy, about 6 ms
of it waiting for the readback (4-5 ms with the late copy, with which a test build held 30). The game can't take the
late copy (below), so it plays at 20 in every browser, the GPU about a third busy.

## Render to RAM

RT64's render to RAM stays on, with its exact copy (RT64's default): each display list's frame is copied into RDRAM
before the list ends. The game works on its frames with the CPU: its shadows are drawn into render targets on the heap
that the CPU then reworks, the screen effects (`mainCPUeffects`, the refraction) read and write the framebuffers at
0x8010FF00 and 0x80135700, and the lens flares read the Z buffer (`mainUpdateZBCheck`, at 0x8015AF40). The other
pages' copy a list late (N64Recomp-browser's `set_render_to_ram_late`) can't serve that: the CPU writes to those render
targets before the copy lands in every room with a character in it (in Goldwood's first room over a hundred times in
5 s), and RT64 then keeps what the CPU wrote, so the shadows came out blurred or as dots, where the exact copy draws
them as the desktop build does.

The exact copy cost the game half its frame rate, until the page let the game run while a frame is drawn. The base
runtime holds the game thread that submits a display list until the graphics thread has drawn it, and no other game
thread runs meanwhile, so the game stood still through RT64's wait for the GPU and the readback: from a local build in
headless Chrome 155 (RTX 2070, a quiet host), the play plan drew 19.4-19.8 frames a second with 250,000-300,000 sound
frames short in 165 s. On the page RT64 calls the runtime back at the list's last full sync (the one its end follows:
every list the game sends has one), when the whole list has been read from RDRAM, and the runtime lets the game go
there (`patches/web/rt64.patch`, `patches/web/N64ModernRuntime.patch`, `dkr.patch`'s renderer). The RSP's and the
RDP's completion still come once the frame is drawn, so the game never rebuilds a list RT64 is still reading. Running
on, the game counts the retraces an RSP or RDP task has been current, and at 11 its scheduler takes the RCP for hung,
shows its debug screen and stops; a frame that waits for its prebuilt shaders takes a second and more, so a hook
(`patches/web/jfg.us.web.toml`) starts both counts again at every retrace.
