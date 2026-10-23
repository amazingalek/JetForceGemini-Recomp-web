// Jet Force Gemini port on a page (N64Recomp-browser): what the page's JavaScript calls. Nothing here on the desktop.
#ifdef __EMSCRIPTEN__
#include <cstdio>
#include <emscripten/emscripten.h>
#include "jfg_game.h"
#include "jfg_options.h"

using namespace jfg;

// The level warp the F9 window and the F10 toolbar offer, reachable from the page's JavaScript for the script that
// records the page's shader list by visiting every level (tools/shader_survey.js): Module._jfg_web_warp(level,
// character, entrance) warps at the next tick, as "Go to level" does, and Module._jfg_web_level_names() prints each
// level's number and name to the console.
extern "C" EMSCRIPTEN_KEEPALIVE void jfg_web_warp(int level, int character, int entrance) {
    g.warp_level = level;
    g.warp_character = character;
    g.warp_entrance = entrance;
    g.pending_warp = true;
}
extern "C" EMSCRIPTEN_KEEPALIVE void jfg_web_level_names() {
    load_level_names();
    for (size_t i = 0; i < g_level_names.size(); i++) {
        std::printf("[jfg] level %zu: %s\n", i, g_level_names[i].c_str());
    }
}
#endif
