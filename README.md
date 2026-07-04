![Radiance Engine](https://github.com/iAmErmac/DoomXR/blob/doomxr/branding/banner.png)

# ⚡ DXR — an Untitled VR Light-Gun / Melee Game (Engine Overhaul)

> [!WARNING]
> **Status: work-in-progress, not yet headset-verified.**
> Almost everything below is implemented at the code level but has **not** been fully play-tested in a headset — the build currently **crashes on launch** due to an unresolved shader uniform-block (UBO) placement bug that is being worked on separately. Treat this as an active reconstruction, not a shippable release. A file-by-file, honest accounting of every change (including what's built vs. verified) lives in [`Documentation/DXR_VS_DOOMXR_CHANGES.md`](Documentation/DXR_VS_DOOMXR_CHANGES.md).

## 📟 What this is

DXR is a fork of **DoomXR** (iAmErmac's QuestZDoom-based VR fork of GZDoom) that turns the general-purpose VR engine into a purpose-built **VR light-gun / physical-melee game**. It adds a native first-person body with arm IK, a physics-driven melee/grapple arsenal, per-actor directional gravity, a hardpoint holster system, and a data-driven keyword metadata engine — while **extracting** the "glow-in-the-dark" (GITD) visual layer out of the core engine into a separate companion mod, so the base engine renders plainly on its own.

**Baseline vs. upstream DoomXR:** 439 files changed, +18.4k / −10.8k lines since the import.

## 🌟 What DXR adds

### 🧍 Native VR body & hands
* **First-person body avatar ("OUR BODY")** — your own 3D marine renders in-view, with auto-fit height matching your HMD and facing decoupled from head-turn (no torso-spin).
* **Native two-bone arm IK** — the avatar's arms track your real controllers via a native solver + procedural IQM bone posing.
* **Always-on dual VR hands** at both controllers (fixes the old invisible-hands / fist-swap-only behavior).
* **Analog grip** (continuous squeeze 0–1) on Touch and Index controllers, with a central **grip-intent arbiter** so climb / whip / gloves / holsters never fight over the same hand.

### ⚔️ Physics-driven VR arsenal
* **XRWhip** — a Verlet-rope bullwhip with a supersonic crack, two-hand control, grapple-swing, and entangle-yank (Indiana Jones / Castlevania IV / Bulletstorm feel).
* **VRSword** — a physically-swung melee blade with real segment collision that deflects bullets via the native parry system; swappable Steel / Lightsaber / Dragon's-Tooth blades.
* **ShieldSaw** — an off-hand block / saw / returning-boomerang tool.
* **IceHook** — a melee pick + thrown embedding hook; picks bite any solid wall for climbing.
* **M79 grenade launcher**, CVar-gated **alt-fire modes** on the conventional guns, and a **manual-reload chamber system** driven by baked model animations.
* **XR Gravity Path** — a palm-out power that paints an SDF walkway which reorients your personal gravity (Prey / Inception-style wall & ceiling walking), built on the new native directional-gravity core.
* **Physics interaction** — grab / throw / catch with sub-frame velocity tracking; barrels are grabbable and detonate on impact with correct kill credit.

### 🌀 Movement, world & engine systems
* **Per-actor directional gravity** (`GravityDir`) for ceiling-flip / wall-pull traversal.
* **Native hardpoint holsters** — shoulder / hip weapon holsters and wrist ability mounts you draw and stow by gripping near your body, with visible in-world markers.
* **Velocity-driven physical climbing**, including ice-pick climbing on any solid wall.
* **KEYWORDS.json metadata engine** — data-driven per-actor / per-weapon behavior (kickback, roles, anatomy, vulnerability, ballistics) with no hardcoding.
* **Crash-hardening** of the inherited base: a class of FString-in-`memset` fixes, null-deref guards, and 3D-weapon state-sync fixes.

### 🎨 Visuals split into a companion mod
The GITD "glow-in-the-dark" layer — neon glow-spots, in-air display panels, hit-reaction FX, and full-screen visual regimes (Tron / Thermal / System Shock / …) — has been **removed from the core engine** and now lives in the **[Radiance Control Panel](https://github.com/presidentkoopa/RadianceControlPanel)** mod, which overrides the engine's shader when loaded. With it absent, the engine renders plainly. The **[NeonGraveyards](https://github.com/presidentkoopa/NeonGraveyards)** mod adds holographic SDF tombstones.

## 🛠️ Custom Shader Workflow (No Engine Recompile)
Add new SDFs, glowing textures, or custom material/screen effects without recompiling the C++ engine:
1.  **Place shader files** (`.fp`) in your PK3 (e.g. `shaders/biohazard_sdf.fp`).
2.  **Bind via `GLDEFS`** in your PK3:
    ```text
    HardwareShader Texture "BIOHAZ0"
    {
        Shader "shaders/biohazard_sdf.fp"
    }
    ```
3.  **Control from ZScript** with standard actors and shader uniforms.

The engine compiles GLSL on the fly at runtime for rapid iteration. (Material shaders must define `ProcessTexel()`, not `main()`.)

---

### Source Code & Licensing
This fork builds on the open-source foundations of **DoomXR** (iAmErmac), **QuestZDoom**, **UZDoom**, and **GZDoom**. Source licensed under the **GPL v3**.
