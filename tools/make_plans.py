#!/usr/bin/env python3
"""Writes tools/shader_plan.json and tools/play_plan.json, the plans N64Recomp-browser's tools/record_shaders.mjs and
play_page.mjs follow for the web page (src/rt64_shaders.txt's header says how the list was recorded with the first).
Both reach the game the same way: the save deleted, so that Game 1 is a new game on every load, then the launcher's
Start Game, the logos and the title, Start to the file select, A on New Game and on the name keyboard's 1, the stick
down to END and A, the story intro skipped with Start, and the character select. From there a section picks Juno,
whose opening is Goldwood's, and tools/shader_survey.js warps to each room of a planet by the game's level numbers
(a warp straight from the character select leaves the screen black); in each the camera turns (the C buttons, the
arrow keys) and the character walks (W) for a few seconds. A section a planet: every room of the planet's regions (the
region is byte 0x102 of a level's header, src/jfg/jfg_debug_menu.cpp's region_names), the cutscenes and test rooms
that belong to none left out. Run it again after changing PLANETS."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))

# A section a planet, in the order the game reaches them: its rooms, the first where a player lands, and the character
# who plays there first, by the game's numbers.
VELA, JUNO, LUPUS = 0, 1, 2
PLANETS = [
    ("goldwood", JUNO, [21, 16, 26, 288, 289, 25, 106, 126, 169, 211, 215, 218, 219, 290, 291, 27, 54, 85, 236,
                        24, 87, 95, 227, 228, 310]),
    ("anubis", JUNO, [37, 39, 40, 84, 129, 130, 131, 134, 241, 38, 123, 124, 128, 154, 297, 86, 152, 156]),
    ("tawfret", JUNO, [158, 115, 118, 231, 242, 244, 247, 255, 256, 257, 121, 125, 132, 133, 147, 149, 150, 217, 259,
                       260, 261, 136, 138, 254, 318, 194, 195]),
    ("walkway", JUNO, [22, 6, 12, 13, 34]),
    ("sekhmet", JUNO, [67, 4, 5, 7, 8, 10, 11, 50, 51, 52]),
    ("rithessa", JUNO, [29, 65, 80, 81, 167, 30, 31, 56, 112, 32, 82, 179, 182, 186, 196, 208, 209]),
    ("cerulean", VELA, [53, 2, 14, 113, 114, 265, 266, 298]),
    ("ichor", VELA, [43, 18, 19, 41, 42, 44, 119, 139, 49, 143, 187, 262, 339, 375]),
    ("spawnship", VELA, [3, 55, 57, 58, 59, 60, 61, 62, 63, 64]),
    ("waterruin", LUPUS, [229, 246]),
    ("gemquarry", LUPUS, [272, 267, 36, 294, 295, 403]),
    ("eschebone", JUNO, [216, 198, 183, 184, 188, 191, 120, 142, 148, 189, 190, 203, 204, 205, 249, 206, 214]),
    ("spacestation", JUNO, [276, 9, 104, 264]),
    ("mizar", JUNO, [232, 192, 201, 213, 299, 300, 301, 222, 223, 234, 311, 243, 315, 316, 317]),
    ("asteroid", JUNO, [332, 28, 220, 224, 225, 226, 337, 396]),
]

def key(name, code, ms):
    return ["hold", name, name if len(name) > 1 else name.lower(), code, ms]

LOOK = [key("ArrowLeft", 37, 1500), ["hold", "KeyW", "w", 87, 1500], key("ArrowRight", 39, 1500), ["wait", 1000]]

def visit(level, character):
    return [["eval", f"warp({level}, {character})"], ["wait", 3500], *LOOK]

LOAD = [["until", "Device Name", 30000], ["wait", 9000]]
TITLE, STORY_FIRST, CHARACTER_SELECT, GOLDWOOD_OPENING = 349, 322, 127, 93
SETUP = [["rom", 473, 197], ["wait", 4000]]
# A press of the stick: one row of the name keyboard.
DOWN = [["hold", "KeyS", "s", 83, 150], ["wait", 400]]
START = [["eval", "try { FS.unlink('/home/web_user/saves/jfg-us.bin'); } catch (e) {}"],
         ["click", 765, 277], ["until", "Initialized RDRAM", 60000], ["wait", 3000],
         ["evalFile", "shader_survey.js"], ["eval", f"waitLevel({TITLE}, 60000)"],
         ["pressUntil", "Enter", "Enter", 13, 100, 1500, f"level() !== {TITLE}", 30000], ["wait", 2500],
         ["key", "Space", " ", 32], ["wait", 2000], ["key", "Space", " ", 32], ["wait", 1000],
         *DOWN * 4, ["key", "Space", " ", 32], ["eval", f"waitLevel({STORY_FIRST}, 15000)"],
         ["pressUntil", "Enter", "Enter", 13, 100, 1500, f"level() === {CHARACTER_SELECT}", 60000], ["wait", 3000]]
# Juno picked at the character select, into Goldwood's opening; kept only in Goldwood's section.
ENTER = [["pressUntil", "Space", " ", 32, 100, 1500, f"level() !== {CHARACTER_SELECT}", 30000],
         ["eval", f"waitLevel({GOLDWOOD_OPENING}, 15000)"], ["wait", 1500]]

def section_steps(name, character, rooms):
    enter = ENTER if name == "goldwood" else [["keep", False], *ENTER, ["keep", True]]
    return enter + [s for level in rooms for s in visit(level, character)]

shader_plan = {
    # The list's header (record_shaders.mjs writes it at the top of src/rt64_shaders.txt).
    "header": [
        "The RT64 shaders the web page builds: one shader description a line, other mode L and H, color combiner L and H,",
        "flags, in hex. RT64 specializes each one's WGSL when the page is built. The list is in sections (N64Recomp-browser's",
        "README, \"Give RT64 a list of the game's shaders\"): the lines above the first \"section\" line are the boot, built",
        "before the game starts, and each section after it is built when the game first draws with 4 of its shaders, the game",
        "waiting for it in Firefox (Chrome builds the whole list behind the game, a section at a time). One missing here is",
        "built behind the game when it is first drawn, and the page remembers it for the next visit.",
        "",
        "Recorded by tools/shader_plan.json (written by tools/make_plans.py, whose docstring says how it plays) with",
        "N64Recomp-browser's tools/record_shaders.mjs, from the page opened with ?record-shaders at its default settings,",
        "each section from a fresh load of the page: the boot is the launcher, the logos, the title, the file select, the",
        "name keyboard, the story intro and the character select; each section after it is one planet, every room of its",
        "regions reached by tools/shader_survey.js (make_plans.py lists them), the camera turned and the character walked",
        "a few steps in each, Goldwood's with its opening. Not played: enemies fought, weapons fired, bosses, cutscenes,",
        "the minigames, multiplayer and the rooms that belong to no planet."],
    "page": "JetForceGeminiRecompiled.html",
    "load": LOAD, "setup": SETUP, "start": START,
    "sections": [{"name": name, "steps": section_steps(name, character, rooms)}
                 for name, character, rooms in PLANETS],
}
play_plan = {
    "header": [
        "Jet Force Gemini's play plan for N64Recomp-browser's tools/play_page.mjs, written by tools/make_plans.py: the boot",
        "as the shader plan's, then the first room of every planet in turn."],
    "page": "JetForceGeminiRecompiled.html",
    "load": LOAD, "setup": SETUP, "start": START,
    "play": ENTER + [s for _, character, rooms in PLANETS for s in visit(rooms[0], character)],
}
for name, plan in (("shader_plan.json", shader_plan), ("play_plan.json", play_plan)):
    with open(os.path.join(HERE, name), "w", newline="\n") as f:
        json.dump(plan, f, indent=1)
        f.write("\n")
