# DoomXR — Session Lanes (multi-session coordination)

**Repo — everyone works here:** `E:\DoomXR-work\DOOM_FRESH`
**NOT** `C:\Users\Command\DoomXR\DoomXR-doomxr\...`. That cwd is a **populated-but-STALE mirror** (full `src\`
+ `wadsrc\`, ~1,194 src files) — a red herring. Grep it only if you must; **line numbers have DRIFTED vs `E:`**,
so re-anchor every symbol by grepping in `E:` before editing. **Never edit in `C:` — it does not affect the build.**

---

## 🔒 SHADER LANE — reserved (shader owner only; other sessions DO NOT edit)
- `wadsrc\static\shaders\**`  (all `.fp`)
- `wadsrc\static\gldefs.txt`
- `src\common\rendering\vulkan\shaders\vk_shader.cpp`
- `src\common\rendering\gl\gl_shader.cpp`
- `src\common\rendering\gles\gles_shader.cpp`
- `src\common\rendering\hwrenderer\data\hw_renderstate.h`  (the StreamData shader uniforms)

## ✅ NON-SHADER LANE — open for the other sessions
- `wadsrc\static\zscript\**`
- `CVARINFO`, `menudef.txt`, `sndinfo.txt`, `modeldef.txt`
- `sprites\`, `sounds\`, other assets
- **the rest of `src\` C++** — everything except the six shader-lane files above

> Multiple non-shader sessions: split by file/feature area so two of you don't edit the same file at once.

---

## 🛑 ONE BUILD AT A TIME (hard rule)
Every session compiles to the **same** output: `E:\DoomXR-work\DOOM_FRESH\build\Release\`
→ `doomxr.exe` + `doomxr.pk3`.

Two MSBuilds running at once **race on those files and corrupt the output.**

**→ Coordinate builds, or let ONE session own "the build" and the others just edit + tell it when to rebuild.**
