// Evaluated in the page by N64Recomp-browser's tools/record_shaders.mjs and play_page.mjs (tools/shader_plan.json,
// tools/play_plan.json), to reach any level by code, without anyone playing. The page's build exports the debug
// menu's level warp (src/jfg/jfg_debug_menu.cpp, jfg_web_warp): mainChangeLevel(level, character, 0, entrance, mode,
// 0) at the next tick, as the game's own level exits call it. warp(level, character, entrance) resolves once the
// level the game is on (the halfword at 0x800A323C, mainGetCurrentLevel()) is that one, or with false after 30 s;
// level() gives it, and waitLevel(id, ms) waits for one. RDRAM is found as page_driver.mjs's n64r finds it; bytes and
// halfwords sit at the address XOR 3 and XOR 2 in its little-endian words.
(() => {
  if (!window.__rdram) {
    const h = HEAPU32;
    for (let i = 2; i < h.length - 8; i++) {
      if (h[i] === 0xB0000000 && h[i - 2] <= 2 && (h[i + 4] === 0x400000 || h[i + 4] === 0x800000)) {
        window.__rdram = i * 4 - 0x308;
        break;
      }
    }
  }
  const base = window.__rdram;
  const off = (a) => base + (a - 0x80000000);
  const r16 = (a) => HEAPU16[(off(a) ^ 2) >>> 1];
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const CURRENT = 0x800A323C;
  window.level = () => r16(CURRENT);
  window.waitLevel = async (id, ms = 120000) => {
    for (let t = 0; t < ms; t += 100) { if (r16(CURRENT) === id) return true; await sleep(100); }
    return false;
  };
  window.warp = async (id, character = 0, entrance = 0) => {
    Module._jfg_web_warp(id, character, entrance);
    return window.waitLevel(id, 30000);
  };
  return true;
})()
