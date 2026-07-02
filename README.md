![Radiance Engine](https://github.com/iAmErmac/DoomXR/blob/doomxr/branding/banner.png)

# ⚡ DoomXR 2.0: "The Wired" Engine Overhaul

> [!IMPORTANT]
> **Status: ACTIVE ENGINE RECONSTRUCTION**
> This project is currently undergoing a total transition from ZScript-driven proxies to high-performance, native C++ hardware implementation. Expect major architectural shifts in the rendering and physics pipelines.

## 📟 Project Vision
To transform the Radiance Engine into a reactive, systemic "TRON" digital layer with native 3D physical presence (IQM), sub-frame VR responsiveness, and a systemic arcade economy.

By integrating custom rendering pipelines directly into the hardware renderer, this engine allows gameplay logic (ZScript) to drive the environment's visual state in real-time.

## 🌟 Master Engine Features

### 🎨 The "Wired" Shader Pipeline (`main.fp`)
The heart of DoomXR's visual identity. We've bypassed traditional texture sampling in favor of a procedural, hardware-accelerated aesthetic:
*   **TRON-Style Vector Grids**: The floor isn't just a texture—it's a living, breathing outrun grid that reacts to the music and combat intensity.
*   **Neon Silhouette Reconstruction**: Real-time edge detection and stencil-buffering create pulsating, high-contrast outlines for every enemy, even in total darkness.
*   **Digital Horizon Skirts**: Procedural UV-fading and wireframe horizons dissolve the boundaries of the map, creating a vast, cyberspace-native feeling.
*   **High-Resolution Spatial SDFs**: Utilizing GPU-accelerated Signed Distance Fields for razor-sharp, glowing UI and iconography that materializes directly in the world geometry.

### 🥽 Total VR Immersion & 3D Presence
DoomXR 2.0 isn't just GZDoom in VR; it's a dedicated VR engine fork designed for physical presence:
*   **Skeletal IQM Hand System**: Fully rigged, animated 3D hands (`vhand.iqm`) that mirror your real-world finger placement. Features analog grip/trigger interpolation for high-fidelity interaction.
*   **Universal 3D Weapon Shells**: Frame-accurate 3D models replace all 2D sprites. Every firing state and reload is dynamically synchronized to foreign mod logic via our native C++ Animation Time-Scaler.
*   **Standardized Model Framework**: A high-performance C++ interception layer that synchronizes 3D animation ticks to ZScript `SetState` calls, ensuring mod compatibility without manual patching.
*   **Dynamic Time Scaling (DTS)**: Automatically calculates and adjusts 3D animation playback speeds to match the exact tic-duration of the active 2D weapon state.
*   **Weapon Archetype Scanner**: A dedicated VR-native UI for real-time weapon mapping. Features dual-pointer interaction support and persistent JSON configuration (`doomxr_weapons.json`).
*   **Gravity Glove "Alyx" Mechanics**: The definitive VR interaction system for Doom. Grab objects from across the room with holographic intent cones and flick them back with physics-accurate trajectory arcs.
*   **Physical Climbing System**: Scale the environment with 1:1 world-space movement. Feel the "texture" of the walls through native surface-haptic micro-pulses in your controllers.
*   **Systemic VR Throwing**: Don't just "use" objects—launch them. Our physics-integrated throwing logic uses sub-frame velocity tracking to make every grenade or barrel toss feel weighted and precise.
*   **Locational Damage & Critical Hits**: Native C++ combat layer that calculates height-based headshots and leg-shots. Includes a systemic critical hit engine with configurable probabilities and multipliers for a deeper "arcade" feel.

## 🛠️ Custom Shader Workflow (No Engine Recompile)
To add new 2D SDFs, glowing textures, or custom screen/material effects without recompiling the C++ engine:
1.  **Place Shader files** (`.fp`) directly in your PK3 mod (e.g., `shaders/biohazard_sdf.fp`).
2.  **Bind Shaders via `GLDEFS`** in your PK3 to associate them with textures or sprites:
    ```text
    HardwareShader Texture "BIOHAZ0"
    {
        Shader "shaders/biohazard_sdf.fp"
    }
    ```
3.  **Spawn and Control via ZScript** using standard actors and setting shader uniforms dynamically with `Shader.SetUniform1f()`.

The engine compiles GLSL shaders on the fly at runtime, allowing rapid iteration on visuals!

## 🥽 VR Stereoscopic Consistency
Special care has been taken in the Vulkan and OpenXR hardware pipelines to ensure:
1.  **Crash Protection**: Robust `IsInitialized()` state checks gracefully fall back to desktop mono mode when VR runtimes are disconnected.
2.  **State Pollution Fixes**: Deep fixes to the `hw_sprites.cpp` rendering loops guarantee that custom stencil and depth-bias passes do not leak across left/right eye stereoscopic boundaries.

---

### Source Code & Licensing
This branch builds upon the open-source foundations of DoomXR, GZDoom, and UZDoom.
Source code licensed under the GPL v3.
