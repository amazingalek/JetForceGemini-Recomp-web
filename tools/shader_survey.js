// Evaluated in the page by N64Recomp-browser's tools/record_shaders.mjs and play_page.mjs (tools/shader_plan.json,
// tools/play_plan.json), to reach any level by code, without anyone playing. The page's build exports the debug
// menu's level warp (src/jfg/jfg_debug_menu.cpp, jfg_web_warp): mainChangeLevel(level, character, 0, entrance, mode,
// 0) at the next tick, as the game's own level exits call it. warp(level, character, entrance) resolves once the
// level the game is on (the halfword at 0x800A323C, mainGetCurrentLevel()) is that one, or with false after 30 s;
// level() gives it, and waitLevel(id, ms) waits for one. arm() sets the game's invulnerability cheat
// (invulnerabilityCheat, 0x800A5070) and gives each character every weapon with at least 150 rounds, as the debug
// menu's weapons editor does (the owned mask at +0x0A of the character, the count at +0x6F, ammo at +0x14), so a
// section can fight with them all. RDRAM is found as page_driver.mjs's n64r finds it; bytes and halfwords sit at the
// address XOR 3 and XOR 2 in its little-endian words.
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
  const r32 = (a) => HEAPU32[off(a) >>> 2];
  const w8 = (a, v) => { HEAPU8[off(a) ^ 3] = v; };
  const w16 = (a, v) => { HEAPU16[(off(a) ^ 2) >>> 1] = v; };
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
  window.arm = () => {
    const game = r32(0x800FD7D4);
    if (game < 0x80000400 || game >= 0x80800000) return false;
    w8(0x800A5070, 1);
    for (let c = 0; c < 3; c++) {
      const p = game + 0x15C + c * 0x76;
      w16(p + 0x0A, 0x7FFF);
      w8(p + 0x6F, 15);
      for (let s = 1; s < 15; s++) if (r16(p + 0x14 + 2 * s) < 150) w16(p + 0x14 + 2 * s, 150);
    }
    return true;
  };
  return true;
})()
