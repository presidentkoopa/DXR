Verified. The main.fp anchors line up: getLightColor at 826, Material struct at 23-35, entry-point declarations at 37-43 (ProcessTexel:38, deprecated ProcessMaterial:39, SetupMaterial:40), fragment inputs at 3-10, output FragColor at 17, wgType branching at 878-880, isWall/panel routing at 886-895, VR early-return note at 1047. The reports are accurate against the live tree. I have enough to write the deliverable.

---

# DoomXR Shader System â€” Read-Only Reference Map

Fused from five recon passes, spot-verified against the live tree at `E:/DoomXR-work/DOOM_FRESH` (repo `presidentkoopa/DoomXR-2.0-The-Wired`). Every claim below carries a `file:line` anchor. This is a **read-only** map â€” the shader lane is reserved (see Â§6).

---

## 1. Architecture at a glance

### Where source lives
- Core GLSL: `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/shaders/glsl/` â€” `main.vp`, `main.fp`, the `func_*.fp` material/light helpers, and custom sprite shaders (`monster_neon.fp`, `vr_sdf_procedural.fp`).
- Post-process: `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/shaders/pp/` â€” includes stereo present shaders (`present_row3d.fp`, `present_column3d.fp`, `present_checker3d.fp`).
- All of the above are packed into `doomxr.pk3` at build time.

### Registration (gldefs)
- `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/gldefs.txt` declares `HardwareShader Sprite TEXNAME { Shader path/to/shader.fp }` for sprite materials and `HardwareShader PostProcess ...` for screen effects.
- Parsed by `ParseHardwareShader()` at `E:/DoomXR-work/DOOM_FRESH/src/r_data/gldefs.cpp:1514`; material texture/type assignments at `gldefs.cpp:1785-1823`, custom `#define` parsing at `gldefs.cpp:1863`, and each descriptor collected into the global `usershaders` TArray at `gldefs.cpp:1920`.
- The global `usershaders` array is declared `extern` in `E:/DoomXR-work/DOOM_FRESH/src/common/textures/textures.h`.
- Built-in material set: `defaultshaders[]` at `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/hwrenderer/data/hw_shaderpatcher.cpp:276` (Default, Warp1/2, Specular, PBR, Paletted, NoTexture, fuzz variants); `effectshaders[]` at `hw_shaderpatcher.cpp:296` (fogboundary, spheremap, burn, stencil, dithertrans). Struct shapes in `hw_shaderpatcher.h:11-26`.

### Load order & override story (GL â€” the important one)
`FShader::Load()` at `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/gl/gl_shader.cpp:215` assembles the program. The **override-critical** lines (verified):
- Vertex shader: `CheckNumForFullName(vert_prog_lump)` **global-first** at `gl_shader.cpp:397`, IWAD fallback at `:398`.
- Fragment shader: `CheckNumForFullName(frag_prog_lump)` **global-first** at `gl_shader.cpp:401`, IWAD fallback at `:402`.
- The inline comments literally read *"global FIRST so a mod/loose pk3 can override core shaders (e.g. main.fp)"*. **This is the loose-`main.fp` hot-load path** â€” a loose file in the mod dir wins over `doomxr.pk3` on GL/GLES, no rebuild.
- **Anomaly â€” core internals forced IWAD-only**: the material/light helper lumps deliberately invert the search. `proc_prog_lump` is loaded IWAD-first (`CheckNumForFullName(proc_prog_lump, 0)`) at `gl_shader.cpp:453` with the comment *"if it's a core shader, ignore overrides by user mods"*; `func_defaultmat.fp`/`func_defaultmat2.fp`/`func_defaultlight.fp` are all `(path, 0)` IWAD-only (`gl_shader.cpp:464, 470, 496, 518`). This prevents mods from contaminating engine internals.

### Compile pipeline (state machine)
- `FShaderCollection::CompileNextShader()` at `gl_shader.cpp:856` sequences: default shaders â†’ NAT (non-alphatest) â†’ user shaders from `usershaders[]` â†’ effect shaders. `Compile()` assembles `version/defines/i_data/main.vp/main.fp/proc_prog_lump/func_default*.fp/light` â€” the material lump is inserted **between** `main.fp` (loaded at `gl_shader.cpp:444`) and `func_defaultlight.fp`.
- `#define NO_ALPHATEST` added when `usediscard==false` (GL side, per recon `gl_shader.cpp:731`); `GBUFFER_PASS` detection for deferred multi-pass at `gl_shader.cpp:732` â†’ drives `FragNormal`/`FragFog` MRT outputs (`main.fp:18-20`).

### Vulkan â€” same semantics, one hard caveat
- `LoadPrivateShaderLump()` at `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/vulkan/shaders/vk_shader.cpp:617` does the same global-first / IWAD-fallback (`:619`/`:620`).
- `VkShaderManager::CompileNextShader()` at `vk_shader.cpp:33`; `LoadFragShader()` at `vk_shader.cpp:494` inserts the material lump (`:517-574`) then the light lump.
- **CAVEAT (critical for testing):** on Vulkan, shader pipelines are compiled to SPIR-V and effectively baked; **loose/mod-pk3 shader overrides are ignored** â€” you must edit into `doomxr.pk3` and rebuild. The loose-`main.fp` hot-load trick works **only on GL/GLES**. (Consistent across all five recon passes; matches memory note *vulkan-shader-override-trap*.)

### GLES
- `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/gles/gles_shader.cpp` mirrors GL infrastructure (ProgramBinary cache, identical lump loading). No multiview (see Â§5).

### GL binary cache
- `FShader::Load()` caches compiled binaries keyed by MD5(vendor/renderer/version/vp_comb/fp_comb). Mismatches silently recompile; nuke the cache (`shadercache.zdsc` / `~/.zdoom/cache`) to force a rebuild.

---

## 2. The material shader contract

### Entry model
A custom `.fp` provides **one** of three entry points (declared in `main.fp:37-41`, verified):
- `vec4 ProcessTexel();` (`main.fp:38`) â€” the common legacy path; return the base texel color. `monster_neon.fp:10` and `vr_sdf_procedural.fp:51` both use this.
- `Material ProcessMaterial();` (`main.fp:39`) â€” **deprecated**; the comment on that very line says *"Use SetupMaterial!"*. Triggers `#define LEGACY_USER_SHADER` (disables features it can't support).
- `void SetupMaterial(inout Material mat);` (`main.fp:40`) â€” modern convention; fills the `Material` struct.

The `Material` struct (`main.fp:23-35`, verified): `Base, Bright, Glow` (vec4), `Normal, Specular` (vec3), then `Glossiness, SpecularLevel, Metallic, Roughness, AO` (float).

### Auto-detection & compat injection
The loader text-scans the custom source and injects glue (`gl_shader.cpp`, verified):
- If neither modern nor deprecated entry is present (`:458`), it's an old shader â†’ inject `func_defaultmat.fp` (or `func_defaultmat2.fp` if the shader declares `GetTexCoord`, `:462-466`).
- Even-older shaders lacking `ProcessTexel` get a call-site substitution (`:479`).
- Old `ProcessLight` signature forwarded via a shim (`:483-488`).
- Deprecated-entry-only shaders get `LEGACY_USER_SHADER` (`:502-505`).
- `func_defaultmat.fp` is the default `SetupMaterial` implementation that calls `ProcessTexel()` and applies normal maps.

### Available inputs (fragment, `main.fp:3-10`, verified)
- `vTexCoord` (loc 0) â€” UV in `.st` (with padding).
- `vColor` (loc 1) â€” vertex color.
- `pixelpos` (loc 2) â€” **`.xyz` = world position**, **`.w` = eye-space depth for fog** (set in `main.vp`, do not confuse with XYZ).
- `glowdist` (loc 3) / `gradientdist` (loc 4) â€” plane distances computed once in the vertex stage (world-space, not per-eye).
- `vWorldNormal` (loc 5), `vEyeNormal` (loc 6).
- `vLightmap` (loc 9).
- `timer` uniform â€” global real-time animation clock (GL uniform declared per recon at `gl_shader.cpp:357`; in StreamData at `hw_renderstate.h:192`). Used all through the glow code.

### Outputs
- `FragColor` (loc 0, `main.fp:17`). Under `GBUFFER_PASS`, also `FragFog` (loc 1) and `FragNormal` (loc 2) at `main.fp:18-20`.
- Material flow: your entry fills `material`, then `getLightColor(material, fogdist, fogfactor)` (`main.fp:826`) produces the final lit+glow color.

### The trap â€” describe-don't-trigger
The loader **branches on the literal presence of two setup-word strings** in your shader text (`gl_shader.cpp:458` and `:502`). If those exact words appear anywhere â€” including comments or string literals â€” in a file the loader scans, the compat-injection logic mis-fires and linking breaks. **Do not write those two words (the modern setup entry and its deprecated cousin) into any scanned file** unless you genuinely mean them as the entry point. This is the same substring-scan hazard flagged in memory (*doomxr-shader-substring-scan-trap*). Also: a custom material must **not** define `main()` â€” `main()` already lives in `main.fp` and a second one is a link error.

---

## 3. Uniform / data channels

### The plumbing (three backends, one struct)
The per-draw uniform payload is the `StreamData` struct â€” the C++ master at `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/hwrenderer/data/hw_renderstate.h:180-268` (verified), mirrored byte-for-byte in GLSL at `vk_shader.cpp:226-310`.

- **Vulkan:** `StreamData` is a std140 UBO. `FRenderState::mStreamData` is memcpy'd into a ring buffer (`vk_streambuffer.cpp:34`), indexed on the GPU by the `uDataIndex` push constant. Bound at `layout(set=1, binding=2, std140) uniform StreamUBO` (`vk_shader.cpp:312`), accessed via `#define uObjectColor data[uDataIndex].uObjectColor`-style aliases.
- **GL:** **no UBO** â€” each `StreamData` field becomes a separate immediate-mode uniform / vertex attribute in `ApplyShader()` (`gl_renderstate.cpp:92`, per-field `Set()` calls `:123-167`). GLES follows the same immediate-mode pattern.
- **Consequence:** adding a field to `StreamData` means updating the C++ struct **and** the Vulkan GLSL mirror **and** adding GL/GLES `Set()` calls â€” 3+ places, std140-aligned. `MAX_WALL_GLOW_SPOTS 16` is `#define`d once at `hw_renderstate.h:178` but must be echoed in every backend prelude.
- **std140 land-mine (verified):** `hw_renderstate.h:226-232` carries explicit `padding2..6` pads with a comment warning that without them every GITD fog/regime field shifts 12 bytes â†’ "black world + mis-coloured glyph spray". Reordering `StreamData` is genuinely dangerous.

### Concrete channels to push a param
1. **Existing radial pool â€” `uWallGlowSpots[16]`** (`hw_renderstate.h:202`): `.xy` = world x,z center, `.z` = packed RGB, `.w` = radius. Paired mask `uWallGlowMask[16]` (`:206`): `.x` = wipeType, `.y` = progress 0..1, `.zw` = wipe direction. Fed from ZScript via `AddGlowSpotWiped`/`AddGlowPanel`; C++ API `SetWallGlowSpots()` (`hw_renderstate.h:602-611`). Consumed in `getLightColor()` at `main.fp:826+`.
2. **Spare int slots â€” `u_gitd_pad0`, `u_gitd_pad1`** (`hw_renderstate.h:264-265`, verified): 4 bytes each, currently unused. The cleanest low-risk lane for a small custom scalar/packed param **without** growing the struct.
3. **Spare vec4 `.w` lanes** â€” `u_gitd_last_impact_pos` (`hw_renderstate.h:267`) uses `.xyz`; its `.w` is free.
4. **`timer`** (`hw_renderstate.h:192`) â€” global animation clock, already wired.
5. **Post-process CVAR path** â€” `Shader.SetUniform*()` from ZScript, but **post-process shaders only** (player scope), used today for BloomBoost (`gitd_shaderbridge.zs:65-109`). Scene-material CVARâ†’StreamData per-frame sync is **noted but not implemented** (`gitd_shaderbridge.zs:55-59`).

### What a cut-plane vs a blade-glow uniform would each use
- **Cut-plane clip:** cheapest = pack plane normal + distance into `u_gitd_pad0`/`u_gitd_pad1` (`hw_renderstate.h:264-265`) or the spare `.w` of `u_gitd_last_impact_pos`. ~8 bytes, no struct growth, no std140 re-sync. Fragment does an early discard/RETURN when the pixel is outside the plane, reading world pos from `pixelpos.xyz`.
- **Blade glow/trail:** two options. (a) Reuse existing `uWallGlowSpots` entries as blade-segment glow points (0 new bytes) â€” encode center/color/radius per segment and drive direction via `uWallGlowMask[].zw`. (b) Grow `MAX_WALL_GLOW_SPOTS` 16â†’32 for dedicated capacity (~64 bytes, requires the 3-place backend sync). Option (a) is the reserved-lane-friendly choice.

---

## 4. GITD effect catalog

All emission lives in **one** function: `getLightColor()` at `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/shaders/glsl/main.fp:826` (verified). It runs once per pixel and adds emissive glow to the base color. Effects are keyed by `wgType`, unpacked at `main.fp:878-880` (verified): `wgTypeRaw` splits into `wallPat = floor(raw/100)` (font-block / wall-animation index) and `wgType = raw âˆ’ wallPat*100`.

**Surface glow (ambient):**
- Wall-glow-spot loop over `uWallGlowSpots[0..count-1]` â€” distance-to-pixel test, unpack packed RGB, add (`main.fp:864+`). Plane glow via `uGlowTopColor`/`uGlowBottomColor` + `glowdist`.
- Floor/ceiling ambient glow driven from ZScript `HF_GlowHandler` (`E:/DoomXR-work/DOOM_FRESH/wadsrc/static/zscript/radiance/gitd_glow.zs:43-873`) via native `SetGlowColor`/`SetGlowHeight`. Liquid-flat auto-color by flat name at `gitd_glow.zs:800-814`. Killstreak red-floor at `HF_ApplyKillstreakGlow` (`gitd_glow.zs:353-400`). Impact ripples via `HF_ImpactRipple` (`gitd_glow.zs:885-1006`).
- Per-texture glowmap sampling gated by `TEXF_Glowmap` (`main.fp:697-698`).

**Neon shape primitives** (verified branch table, `main.fp`, each with mandatory white-hot early-RETURN except smoke):
- 14 Shockwave ring (`:995`), 15 Filled-disc flash (`:1011`), 16 Casing (`:931`), 17 Shard (`:971`), 18 Corner brackets (`:1055`), 19 Waveform/oscilloscope (`:1083`), 20 Smoke puff (`:1026` â€” *deliberately no early-return*), 21 Segmented bar/gauge (`:1110`), 22 Spectrum/heatmap strip (`:1143`), 23 Skull materialize (`:1179`, samples reserved 384Ã—384 SDF block in the atlas), 26 Lightning bolt (`:906`).
- SDF helper library (capsule/arc/box + ghost-stone slab/obelisk/cross/monolith) and flicker/warmup modulation live in the `main.fp:716-825` block (per recon).

**Air panels + digits (`wgType==13`):**
- Panel routing: `isWall` heuristic at `main.fp:886`, panel special-case at `:889-895` (verified) â€” `wgType==13` **always** takes the wall/panel branch so the digit renders (comment at `:882-884` explains the prior floor-branch bug).
- Digit painting for `wgType < 13.5` at `main.fp:1231-1282` (verified), sampling the combined multi-font SDF atlas `textures/neonfont.png` (`main.fp:1251`). Font block selected by `wallPat`.
- World-space camera-facing billboard construction (per-pixel, per-eye) at `main.fp:1350+` (verified `wgType > 12.5` branch at `:1350`).

**Gameplay triggers (ZScript):**
- `GITD_ComboTag` / `GITD_ComboHandler` â€” damage accumulator floating over monsters; `AddGlowPanel`/`AddGlowSpotWiped` (`E:/DoomXR-work/DOOM_FRESH/wadsrc/static/zscript/radiance/gitd_combo.zs:20-195`).
- `GITD_ScoreBurst` â€” converging gold digit shards on final score (`E:/DoomXR-work/DOOM_FRESH/wadsrc/static/zscript/radiance/gitd_scoreburst.zs:8-70`).
- `gitd_shaderbridge.zs` â€” `syncBloomBoost()` pushes bloom uniforms (`:65-109`); reactive fire/damage monitoring.

**Visual regimes:** `applyVisualRegime()` (per recon `main.fp:1754-1901`) â€” System Shock / Tron / Blueprint / Thermal / Noir / etc., driven by `u_vr_visual_regime` + reactive fields (`u_gitd_last_hit_time`, `u_gitd_kill_streak`, `u_gitd_player_speed` at `hw_renderstate.h:245-258`). **Spatial-proximity masked** (distance to `uCameraPos`), not screen-space â€” deliberately, for VR nausea safety.

---

## 5. VR gotchas â€” what any new effect must respect

**Stereo model.** Each eye renders `main.fp` with its own view matrices. In Vulkan multiview, `gl_ViewIndex` â†’ `hwViewIndex` (loc 15) selects from `viewpoints[2]` (`vk_shader.cpp:200-218`, `SUPPORTS_MULTIVIEW` ifdef at `main.vp:40-41`). GL runs the geometry per-eye sequentially; **GLES has no multiview**. Per-eye `uCameraPos` shift comes from `VREyeInfo::GetViewShift()` (`hw_vrmodes.cpp:834-848`) scaled by `vr_ipd` (default 0.064 m, `hw_vrmodes.cpp:375`).

**The digit / additive-content fix (the big one).** Neon shapes and digits **must** early-`RETURN vec4(coreColor, 1.0)` from `getLightColor()` rather than accumulating into `wgAdd`. The comment at `main.fp:1047` states it outright: *"MANDATORY for VR (post-processing swallows non-returned additive content)"*. The stereo present shaders sample **separate** `LeftEyeTexture`/`RightEyeTexture`; content that hasn't committed to `FragColor` before `getLightColor()` returns is invisible in the headset. Early returns are at `main.fp:906/931/971/995/1011/1055/1083/1110/1143/1179` etc. (verified branch offsets) â€” smoke (20, `:1026`) is the one intentional exception (soft haze, no white-hot return).

**Panel-normal / right-eye routing.** `wgType==13` overrides the surface-normal `isWall` heuristic (`main.fp:886`, verified) so foreshortening/normal-read error in VR can't blank the panel backplate+rim. World-space billboards recompute their facing per-pixel from per-eye `uCameraPos` (`main.fp:1350+`), so orientation is correct per eye â€” at a per-pixel `normalize`/`cross` cost with no off-panel early-exit.

**Stereo presentation.** `present_row3d.fp` / `present_column3d.fp` / `present_checker3d.fp` interleave the two eye textures by `gl_FragCoord` parity with a `WindowPositionParity` offset (mis-alignment â†’ eye-swap), applying per-eye gamma. These are **2D screen-space** â€” they have **no** viewpoint uniforms, so any world-space effect (cut-plane, blade) must fully commit during `main.fp`; the present stage cannot add geometry, only tone-map/interleave.

**Regime safety.** Anything that perturbs `pixelpos`/normal in `applyVisualRegime()` must use the proximity mask (distance to per-eye `uCameraPos`), never screen-space, or geometry "shakes" differently per eye and induces nausea.

---

## 6. Enablement â€” cut-plane clip & blade glow

> **RESERVED SHADER LANE.** Everything below touches `main.fp`, `StreamData` (`hw_renderstate.h`), the Vulkan GLSL mirror (`vk_shader.cpp`), the GL uniform setters (`gl_renderstate.cpp`), and possibly `gldefs.txt`/`gldefs.cpp`. Per the multi-session lane rules (memory: *dxr-multisession-lanes*), `.fp` / `gldefs` / `*_shader.cpp` / `hw_renderstate.h` are the **user's shader lane â€” hands off**. This section is a *plan/where-it-would-go* map, not a change to make.

### (a) World-space monster cut-plane clip
- **Data:** pack plane normal + distance into `u_gitd_pad0`/`u_gitd_pad1` (`hw_renderstate.h:264-265`) or the spare `.w` of `u_gitd_last_impact_pos` (`:267`) â€” ~8 bytes, no struct growth, no std140 re-sync, no GL divergence pain.
- **Shader:** in `main.fp`, read `pixelpos.xyz` (`:5`) and `vWorldNormal` (`:8`), compute signed distance to the plane, and `discard` (hard cut) or `smoothstep` alpha (soft edge). Must be **per-eye correct** â€” use per-eye `uCameraPos` for any view-relative culling, and **early-RETURN/commit** so the stereo present stage sees it (Â§5).
- **Feed:** set the pad fields per-draw during monster/model submission (the `SetWallGlowSpots`-style API pattern in `hw_renderstate.h:568-623`), or via a new `Set*` on `FRenderState`. No `gldefs` entry needed if it rides the existing material path; a dedicated `HardwareShader Sprite` entry (`gldefs.txt` + `gldefs.cpp:1514`) if you want it as an override material.
- **Files/lanes touched:** `main.fp`, `hw_renderstate.h`, `vk_shader.cpp` mirror (if any new field), `gl_renderstate.cpp` (GL setter) â€” **all reserved lane.**

### (b) Blade glow/trail (saber + Deus Ex Dragon's Tooth)
- **Reference impl:** `monster_neon.fp:10` (`ProcessTexel` + Sobel edge glow + `timer` pulse, `:22-53`) is the closest existing pattern; the neon core/halo SDF shapes (`main.fp` wgType 14-23) are the reference for core+halo emission.
- **Cheapest data path:** reuse `uWallGlowSpots` (`hw_renderstate.h:202`) â€” one spot per blade segment, `.xy` center, `.z` packed RGB, `.w` radius; direction via `uWallGlowMask[].zw` (`:206`); a `wipeType 1` seam wipe drives the trail fade via `progress`. Zero new bytes. If more capacity is needed, grow `MAX_WALL_GLOW_SPOTS` 16â†’32 at `hw_renderstate.h:178` â€” but that forces the 3-backend prelude sync and is the higher-risk route.
- **Emission:** populate `material.Glow`, or early-RETURN a bright color from `getLightColor()` like the digits do (`main.fp` early-return pattern); `timer` (`hw_renderstate.h:192`) drives trail fade/pulse.
- **VR:** blade geometry is world-space and identical per eye (only camera perspective differs); trail glow **must early-RETURN** so the stereo interleave captures it; use `pixelpos.w`/distance-to-`uCameraPos` for depth-correct falloff.
- **Feed:** spawn the glow spots per-tic from ZScript (`AddGlowSpotWiped`/`AddGlowPanel`, as `gitd_combo.zs` / `gitd_scoreburst.zs` do) â€” **this half is outside the shader lane**; the shader-side rendering is inside it.
- **Files/lanes touched:** shader-lane = `main.fp`, `hw_renderstate.h` (+ mirrors if array grows); ZScript spawn side = `wadsrc/static/zscript/radiance/*` (not the shader lane).

---

### Key file anchors (quick index)
- `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/gl/gl_shader.cpp` â€” load order `:397-403`, compat scan `:458`/`:502-505`, core-internal IWAD-lock `:453/464/470/496`, state machine `:856`.
- `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/vulkan/shaders/vk_shader.cpp` â€” load `:617-620`, frag assembly `:494-574`, StreamData GLSL mirror `:226-310`, multiview `:164-218`.
- `E:/DoomXR-work/DOOM_FRESH/src/common/rendering/hwrenderer/data/hw_renderstate.h` â€” `MAX_WALL_GLOW_SPOTS :178`, `StreamData :180-268`, glow-spot pool `:202/206`, spare pads `:264-267`, std140 pad warning `:226-232`, glow API `:568-623`.
- `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/shaders/glsl/main.fp` â€” inputs `:3-10`, out `:17`, Material `:23-35`, entry decls `:37-43`, glowmap `:697-698`, `getLightColor :826`, wgType unpack `:878-880`, panel routing `:886-895`, VR early-return `:1047`, atlas `:1251`.
- `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/shaders/glsl/monster_neon.fp` â€” `ProcessTexel` reference `:10`.
- `E:/DoomXR-work/DOOM_FRESH/src/r_data/gldefs.cpp` â€” `ParseHardwareShader :1514`, usershaders register `:1920`.
- `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/zscript/radiance/gitd_glow.zs`, `gitd_combo.zs`, `gitd_scoreburst.zs`, `gitd_shaderbridge.zs` â€” ZScript effect drivers.
- Stereo present: `E:/DoomXR-work/DOOM_FRESH/wadsrc/static/shaders/pp/present_{row,column,checker}3d.fp`.
