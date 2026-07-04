# GITD `main.fp` — Shader Feature Map & Cleanup Notes

**File:** `wadsrc\static\shaders\glsl\main.fp` (2066 lines, as of 2026-07-04)
**Scope:** full feature inventory of the fragment shader, written for someone new to this codebase.
**Note:** this file is in the SHADER LANE (see `SESSION_LANES.md`) — read/reference freely, but edits belong to the shader-owning session.

---

## 0. What this file is

`main.fp` is a fragment shader — a program that runs once per pixel, every frame, for every surface drawn. It's GZDoom's stock `main.fp` with a large amount of custom GITD (Glow In The Dark) code grafted in. Because it's GPU code with fixed-size uniform arrays, many variables are reused for 2-3 different meanings depending on the code path (no "extra room" to add new inputs without restructuring the data feeding the shader). `#ifdef` blocks mean this file compiles into several different actual programs depending on hardware — `SHADER_LITE` (stripped mobile/Quest path), and three alternate shadow implementations (`SUPPORTS_RAYTRACING` / `SUPPORTS_SHADOWMAPS` / neither).

---

## 1. Core engine pipeline (stock GZDoom, inherited)

- **`Material` struct** (L25-37): base/bright/glow/normal/PBR channel bundle every pixel gets filled into.
- **Color utilities** (L59-86): `hsv2rgb`/`rgb2hsv`, `grayscale`.
- **Desaturation** (L94-120): global color-drain slider (`uDesaturationFactor`).
- **Texture tinting/blending** (L133-186): `ApplyTextureManipulation` — colorize/invert/tint + 3 Build-engine blend modes (Screen/Overlay/Hardlight), carried over from JFDuke. General-purpose, not GITD-specific.
- **`getTexel`** (L194-264): master texture fetch — texture modes (stencil/opaque/inverse/alpha-from-grayscale/Y-clamp), tint/manipulation, Doom64-style object coloring.
- **Vanilla software-lighting emulation** (L271-376): `R_WallColormap`, `R_PlaneColormap`, `R_ZDoomColormap`, `R_DoomColormap`, `R_DoomLightingEquation` — recreates 1993 Doom software-renderer banding/falloff, selectable via `gl_lightmode`.
- **Shadow casting** (L384-604): raytraced path (`SUPPORTS_RAYTRACING`, real GPU rays + optional 9/18/27-sample soft jitter), shadow-map path (`SUPPORTS_SHADOWMAPS`, optional PCF blur), or always-lit fallback.
- **Spotlight cones** (L606-611): `spotLightAttenuation`.
- **Normal mapping** (L619-667): `ApplyNormalMap` + `cotangent_frame` tangent-space basis.
- **`SetMaterialProps`** (L689-716): assembles the final `Material` (base/normal/brightmap/detail/glowmap layers).

## 2. PS1 affine texture warp (small custom retro feature)

- [`GetAffineTexCoord`](L678) (L669-681): when `uAffineWarp` is on, uses non-perspective-corrected UVs (`noperspective in vec4 vTexCoordAffine`) instead of perspective-correct ones — the classic PS1/N64 "wobbly texture" look on angled surfaces.

## 3. GITD Wall/Floor Glow-Spot System — "impact glow pool" mechanic

Lives inside `getLightColor` (L842), L877-1619. Localized glowing patches on walls/floors/ceilings — likely bullet impacts, blood glow, muzzle-flash marks.

**Mechanics:** up to `MAX_WALL_GLOW_SPOTS` spots stream in per frame as `uWallGlowSpots[]`/`uWallGlowMask[]` (L878-885). Color is packed into one float as `R*65536+G*256+B` (L891-892). A second packed float splits into `wallPat` (hundreds digit, picks style) and `wgType` (remainder 0-26, picks shape). `isWall` (L902) routes to the wall-pattern set OR the floor-pattern set — and is unconditionally `true` whenever `wgType > 12.5`, which is how the neon air-panels (section 4) always take the wall path regardless of actual surface.

### 3a. Wall-surface patterns (6 styles, by `wallPat`, L1300-1362)
0. Breathing pool (animated, shimmer+pulse) — L1306-1313
1. Scanning band (sweeps up/down) — L1314-1320
2. Rotating checkerboard blocks — L1321-1334
3. Forward comet trail (red bleed) — L1335-1341
4. Reverse comet trail (orange tint) — L1342-1348
5. (fallback) Segmented radial pulse bars (7 wedges, independent decay) — L1349-1359
- Universal 2×2 ordered dither anti-banding pass at the end (L1360-1361).

### 3b. Floor/ceiling patterns (13 shapes, by `wgType`, L1364-1614)
- 12 — Label/line glow box (oriented rect, border+fill) — L1416-1430
- 11 — Strobe/invert (photo-negative flash core+rim) — L1431-1439
- 10 — Checkerboard wave — L1440-1458
- 9 — Starburst spike (12-point rotating burst) — L1459-1474
- 8 — Five-lobed pulsing ring burst — L1475-1489
- 7 — Square ring burst (banded) — L1490-1506
- 6 — Spiral burst — L1507-1522
- 5 — Rotating hexagon ring burst — L1523-1539
- 4 — Hex-tile flip wave (true hex grid, cells flip as wave passes) — L1540-1566
- 3 — Simple ring pulse — L1567-1572
- 2 — Scratch/jagged streak (directional gouge + red bleed) — L1573-1599
- 1 — Oriented glow bar — L1600-1610
- 0 (fallback) — Plain radial pool, **static, no animation** (unlike wall style 0) — L1611-1614
- **`wgType > 12.5` branch (L1366-1415) is DEAD CODE — confirmed unreachable.** To reach the floor/ceiling `else` block at all, `isWall` must be false, which by definition (L902) requires `wgType <= 12.5`. So the nested `wgType > 12.5` check inside it can never be true — this is a boolean-logic contradiction, not a guess. It implements a view-facing standing digit sign (billboard math + hardcoded 7-segment bitmask lookup, technique completely different from the SDF-font approach used everywhere else). Likely the original number-display design, superseded when air-panel `wgType==13` (section 4) was added and given unconditional `isWall=true` routing. Safe to delete; verified behavior-neutral either way.

## 4. GITD Neon Air-Panel Display System (`wgType` 13-26)

Floating, camera-facing billboard displays (not decals on real geometry) — set by the glow-billboard render pass. L732-841 (helpers) + L905-1298 (shapes).

**Shared helpers** (L732-841):
- `gitd_segDist`/`gitd_segMin` (L734-746): distance-to-line-segment, for tube-shaped strokes.
- `gitd_arc` (L748-758): distance to a circular arc (curved tube-font keystone).
- `gitd_hash`/`gitd_vnoise` (L760-764): cheap pseudo-random noise.
- `gitd_neonFlicker` (L767-779): signature neon-tube buzz — layered high-freq sine "buzz" + jitter noise + slow breathing pulse + occasional random brownout, per-panel seeded so multiple signs desync.
- `gitd_neonWarmup` (L781-787): over-brighten + shiver on spawn, like a warming tube.
- `gitd_vibrance` (L789-793): saturation boost without white blowout.
- `gitd_box` (L796-800): rounded-box SDF (brackets/gauge keystone).
- **`gy_sdf_slab`/`gy_sdf_obelisk`/`gy_sdf_cross`/`gy_sdf_monolith` ("Ghost Stone" primitives, L802-840) — DEAD CODE, never called anywhere in the file.** Procedural analytic shapes: tombstone (rounded-arch slab), tapering obelisk, rotating plus/X cross, glitching-jitter monolith slab.
  - **CONFIRMED SUPERSEDED (2026-07-04):** the real "Ghost Stone" graveyard feature already exists and uses a completely different technique — a baked SDF texture atlas (`gy_tombstone_sdf.fp`, in the `Graveyard_standalone` staging folder on Desktop) with holographic rim-glow/shiver via `ProcessTexel()`, backed by real ZScript actors (`gy_Stone.zs`, `gy_Death.zs`, `gy_EventHandler.zs`, `gy_Storage.zs`, `gy_VmAbortHandler.zs`) and art (`gy_tomb1-4.png`, `gy_ghost1-4.png`). That real implementation is mid-merge into the standalone `RadianceControlPanel_v1.0` mod (Desktop) — its `zscript\radiance\` already has the same 5 `gy_*.zs` files, but `Graveyard_standalone`'s copies are newer/ahead (diff-confirmed) and its shader/art haven't landed in v1.0 yet.
  - **Recommendation:** delete these 4 functions from `main.fp` outright rather than exporting/relocating — nothing of value would be lost, the working replacement already exists elsewhere and is actively being integrated by the shader-owning session. Do not add them into `RadianceControlPanel_v1.0` or `Graveyard_standalone` — that would just add a second, inferior implementation alongside the real one mid-merge.

**The display types** (all render into a shared "white-hot core + colored halo" look):
- **13 — Number/digit panel** (L905-1298): glass backplate + vignette/rim, 1-5 digits via a real SDF font atlas (`textures/neonfont.png`). Likely the ammo/score/damage-number display.
- **26 — Lightning bolt** (L922-939): jagged gold streak, layered sine jitter + faint branch bolt, rapid strobe flicker.
- **16 — Shell casing + damage stamp** (L947-986): rounded casing outline with open "mouth," damage number stamped on the body via the same SDF-font technique.
- **17 — Bounce/clink shard** (L987-1001): small crossed-sliver spark + hot center dot.
- **14 — Shockwave ring** (L1011-1026): expanding ring, thins and fades as it grows.
- **15 — Filled disc flash** (L1027-1041): solid glowing disc, appears then fades.
- **20 — Smoke puff** (L1042-1058): noise-broken fuzzy circle; deliberately soft-additive only, no white-hot core (never reads as a light source).
- **18 — Corner brackets** (L1071-1098): target-reticle L-brackets at the 4 corners of a rounded rect + center aiming pip.
- **19 — Waveform/oscilloscope** (L1099-1125): scrolling sine+noise trace line drawn as a glowing tube, faint center baseline.
- **21 — Segmented bar/gauge** (L1126-1158): 12-segment horizontal fill bar in a frame — sci-fi loading-bar/gauge look.
- **22 — Spectrum/heatmap strip** (L1159-1194): 14 animated vertical bars, warmer color for taller bars.
- **23 — Wireframe-to-solid skull** (L1195-1241): samples a dedicated 384×384 SDF skull baked into the neon font atlas; vertical "materialize" sweep (wireframe above the line, solid below), CRT scanline roll, cold-blue/hot-orange duotone by depth, flickering ember eye sockets.

## 5. Fog & Atmosphere

- **`applyFog`** (L1661-1664), **`AmbientOcclusionColor`** (L1672-1691), **`ApplyFadeColor`** (L1693-1721): stock fog / AO-fog-color / global fade-to-color.
- **`applyOmniFog`** (L1729-1768, custom): 5 modes via `u_gitd_fog_mode` — 0 passthrough to stock, 1 ground-mist height fog, 2 spectral-silhouette rim tint, 3 bit-crush color quantization, 4 vortex noise swirl. Optional "Light-Link" (L1738) tints fog to the room's glow color.
  - **Bug-prevention note (L2010-2014 in `main()`):** omni-fog only runs when a GITD mode is explicitly enabled; otherwise stock fallback. Exists because unconditional omni-fog previously caused the documented "black-world" regression (ordinary sectors default `uFogColor` to black).

## 6. Visual Regime — full-screen stylization filters

`applyVisualRegime` (L1770-1917), switched via `u_vr_visual_regime`.

- **VR safety — proximity mask** (L1774-1779): effect strength scales with world-space distance from the player (not screen-space), so hands/gun stay unaffected up close — avoids VR nausea from warping content right in front of the face. `u_vr_regime_bubble_size` can shrink the safe zone to zero.
- **Reactivity inputs** (L1781-1784): `damagePulse`, `firePulse`, `comboPulse` (kill streak) feed most regimes.
- **1 — System Shock**: green wireframe edge-highlight (rim/Fresnel-based), thickens with kill streak, flashes red on damage.
- **2 — Tron**: glowing world-space grid, radial "sonar ping" on fire, brightens with movement speed, blue→orange with kill streak.
- **3 — Blueprint**: navy CAD line art, auto-highlights bright/glowing objects in orange (tactical tag look).
- **4 — Thermal**: luminance → cold-blue/red/hot-yellow heat-map recolor.
- **5 — Digital Noir**: high-contrast grayscale except already-saturated (GITD neon) areas; color briefly floods back on damage ("adrenaline bleed").
- **7 — LSD**: continuous hue warp tied to player movement speed.
- **9 — Tetris**: voxelized world grid colored/textured like Tetris pieces, "falling"/cycling, white flash on kill streak.
- **Regimes 6 and 8 are absent** — reserved or removed, nothing there currently.

## 7. Reactive impact ripple (L1950-1970)

Expanding shockwave ring from the last hit point (~1s life) distorts the world-position used for Visual Regime sampling only — never applied to base textures/lighting (avoids constant-wobble nausea). Written into a separate `regimeWorldPos` copy rather than mutating `pixelpos` directly, because Vulkan/SPIR-V forbids writing to shader inputs (older GL silently tolerated it).

## 8. Misc + pipeline order

- **Dithered transparency** (`DITHERTRANS`, L2042-2060): classic Doom fake-translucency via 8×8 Bayer dither discard (e.g. Spectre-style effects).
- **G-buffer pass** (`GBUFFER_PASS`, L2062-2065): outputs AO-fog color + view-space normal for a deferred/SSAO pass.
- **`main()` order** (L1925-2066): clip discard → impact-ripple distortion → build `Material` → alpha-test discard → lighting + glow-spots + air-panels (`getLightColor`) → fog (stock or Omni) → fade color → Visual Regime (last, on top of everything) → output → optional dither discard / G-buffer output.

---

## 9. Open cleanup items

1. **Delete `gy_sdf_slab/obelisk/cross/monolith`** (L802-840, main.fp) — confirmed dead, confirmed superseded by the real atlas-based Ghost Stone shader already in the `RadianceControlPanel_v1.0` merge pipeline. No export/relocation needed.
2. **Delete the unreachable `wgType > 12.5` floor-branch** (L1366-1415, main.fp) — confirmed logically unreachable given the current `isWall` definition (L902); removal is behavior-neutral. When removing, fold the following `else if (wgType > 11.5)` into a plain `if` (it becomes the first condition in the chain).
3. Both edits fall in the **shader lane** (`SESSION_LANES.md`) — reserved for the shader-owning session; flagged here for that session (or explicit user override) to action, not applied automatically.
