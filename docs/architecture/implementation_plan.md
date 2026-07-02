# Universal 3D Weapon Shell (DoomXR Engine Level)

This plan outlines the architecture for a native C++ system in DoomXR that automatically maps foreign PK3/WAD weapons to high-quality 3D VR models. By operating at the engine level, we bypass ZScript limitations, enabling true inheritance-based identification and frame-accurate dynamic animation synchronization.

## User Review Required

> [!IMPORTANT]  
> Please review the **Adversarial Analysis** section below, specifically the refined approach to the Reload Heuristic and the JSON schema design.

## Proposed Architecture

The system consists of three core C++ engine components:

### 1. The Archetype Resolver (`src/xr_weapon_archetypes.cpp`)
This component runs immediately after all WADs/PK3s are parsed and the `PClass` list is finalized.
*   **Inheritance Mapping**: It traverses every loaded class. If `IsDescendantOf(PClass::FindClass("Shotgun"))` is true, it's flagged as a shotgun. This covers ~80% of mods out of the box.
*   **The External Override (JSON)**: For mods that build entirely custom weapons, we introduce an external JSON configuration file (e.g., `doomxr_weapons.json` in the user's config folder or bundled with mods). This acts as a dictionary, allowing modders or players to write simple definitions mapping a foreign class name directly to a 3D model, archetype, and custom state labels.
*   **Resolution Output**: Every weapon gets a native C++ struct attached to it defining its `VR_Archetype`, `VR_ModelDef`, and `VR_Scale/Offset`.

### 2. The Animation Synchronizer (`src/xr_weapon_anim.cpp`)
This is the heart of the "Frame-Accurate" goal. We hook into `AWeapon::SetState` (the engine function that changes weapon states).
*   **State Interception**: When a foreign weapon enters its `Fire`, `Reload`, or `Ready` state, our hook triggers the corresponding 3D model animation sequence.
*   **Dynamic Time Scaling (DTS)**: A foreign shotgun might take 20 tics to fire; another might take 5 tics. The synchronizer calculates the total duration (in tics) of the foreign weapon's state sequence and dynamically adjusts the playback speed of the 3D model's animation to match exactly. The 3D animation finishes exactly when the 2D logic finishes.

### 3. The Render Injector (`src/xr_model_render.cpp`)
Hooks into the HUD rendering pipeline (`DrawPSprite`).
*   **Suppression**: If the current player's ready weapon has a mapped VR archetype, the engine suppresses the 2D sprite draw call entirely.
*   **Injection**: It calculates the interpolated frame of the 3D animation (from the Synchronizer) and pushes the 3D model to the render queue at the correct HUD coordinates.
*   **Result**: The player sees our high-quality 3D model animating, while the underlying logic (damage, spread, projectile spawning, and sounds) is driven 100% by the foreign mod.

### 4. User Interface (In-Game Model Assignment Menu)
We will build a native engine menu (e.g., "VR Weapon Assignments") accessible from the Options menu.
*   **Dynamic Roster**: The menu reads the `PClass` list and dynamically populates a row for every weapon currently loaded in the game.
*   **Assignment**: Next to each weapon is a dropdown listing all available 3D archetypes (e.g., "Shotgun", "Rifle", "Revolver").
*   **Live Updates**: Changing an assignment immediately updates the `VR_Archetype` struct in memory and visually swaps the weapon in your hands.
*   **Persistence**: When you close the menu, the engine automatically serializes your choices and saves them to `doomxr_weapons.json`. This means you never have to edit the JSON by hand unless you want to configure advanced edge cases (like custom reload states).

## Model Packaging

Given that we have frame-accurate, position-accurate, scale-accurate VR Weapons for the vanilla Doom set, plus a rifle, SMG, and flamethrower:
*   **Engine Core Models**: We will package these core VR models directly into a `doomxr_core_models.pk3` that the engine automatically loads on startup (similar to `gzdoom.pk3`). This guarantees the base set is always available.
*   **Integrated Assets (IQM Hands)**: A fully rigged, animated IQM hand model (`vhand.iqm`) has been successfully integrated into the rendering pipeline. Any weapon tagged with the `fist` archetype will now automatically display this tracked 3D hand model. The engine architecture already supports the `.iqm` format for this.

---

## Adversarial Analysis (Playing Devil's Advocate)

Here are the immediate edge cases and problems we will face, and how we must solve them.

### Adversary 1: "Mods don't use standard Reload states."
**The Problem**: Vanilla Doom has no `Reload` state. While ZDoom introduced it, many complex mods (like *Brutal Doom* or *Golden Souls*) often implement reloading using custom inventory tokens and jumping to custom states inside the `Fire` sequence, or using `Weapon.CustomReload`.
**The Defense**: 
1.  **Refined Heuristic (The Clip Check)**: Instead of just checking if ammo increases (which fails on auto-regen weapons), we hook into the engine's inventory transfer. If a state sequence deducts from `Ammo2` (reserve) and adds to `Ammo1` (clip) within a short window, we classify it as a reload sequence.
2.  **The JSON Override (Bulletproof fallback)**: The JSON override is the ultimate source of truth. We can define custom reload state labels explicitly:
    ```json
    {
      "GS_Bouncer": {
        "archetype": "shotgun",
        "custom_reload_state": "DoReload"
      }
    }
    ```

### Adversary 2: "Inheritance is a liar."
**The Problem**: A modder wants a weapon that uses shotgun shells, so they inherit from `Shotgun` to save time, but they change the sprites and logic to make it a heavy sniper rifle. Our engine will map it to a VR Shotgun.
**The Defense**: The JSON override takes absolute precedence over inheritance mapping. If the community finds a popular mod that lies about inheritance, we just add an entry to the official JSON dictionary.

### Adversary 3: "The 3D model looks disconnected from the logic."
**The Problem**: A foreign weapon fires a burst of 3 shots in 10 tics. Our 3D model only has a single-shot animation. It will look terrible to speed up a single shot animation to 300% speed.
**The Defense**: The 3D model pack *must* have standardized animation sets for archetypes. We need animations for `Fire_Single`, `Fire_Auto`, and `Fire_Burst`. The engine checks how many times `A_FireBullets` or `A_FireProjectile` is called within the state loop to select the correct animation.

### Adversary 4: "Dual Wielding (Akimbo) breaks the illusion."
**The Problem**: Many popular mods (like *Brutal Doom* or *Guncaster*) support dual wielding. They achieve this by rendering a second weapon on a custom PSprite layer (e.g., `PSP_WEAPON + 1`). If we only hook the primary `PSP_WEAPON` layer, the player will see a 3D model in their right hand and a 2D sprite in their left hand.
**The Defense**: The Render Injector must map *all* PSprite layers used by the weapon. If the engine detects the foreign weapon drawing to an off-hand layer, it spawns a second, mirrored instance of the 3D model assigned to that hand. The Animation Synchronizer will track the state sequence of the off-hand layer independently.

### Adversary 5: "Floating 2D Muzzle Flashes."
**The Problem**: Doom engine weapons draw their muzzle flashes on a separate layer (`PSP_FLASH`). If we replace the main weapon with a 3D model but let the original 2D muzzle flash render, it will likely float awkwardly in space, misaligned with the 3D barrel.
**The Defense**: The Render Injector must aggressively suppress the `PSP_FLASH` layer whenever a VR model is active. Instead, the 3D models must provide their own localized muzzle flash particle effects tied directly to the barrel bone of the 3D model.

### Adversary 6: "What about Alt-Fire?"
**The Problem**: Many weapons have an alternative fire mode (e.g., aiming down sights, or an underslung grenade launcher). 
**The Defense**: The Animation Synchronizer explicitly tracks entry into the `AltFire` state. If the 3D model has a defined `AltFire` animation, it scales and plays it. If the model lacks an `AltFire` animation, the system gracefully falls back to scaling the standard `Fire` animation to ensure visual feedback occurs.

---

## Execution Roadmap (A to Z Approach)

To get us from zero to a fully functional universal 3D weapon shell, we will execute the following phases in order:

### Phase 1: Engine Scaffolding & Core Structs
1.  **Define Core Structs**: Create the C++ structs (`VR_Archetype`, `VRWeaponData`) that will sit on every `AWeapon` instance.
2.  **Asset Pipeline (`doomxr_core_models.pk3`)**: Build the build-script logic to compress the `vanillaweapons` folder into an engine-loaded core PK3. Ensure the engine's model parser can see them globally.

### Phase 2: The Resolver (Inheritance & JSON)
1.  **Inheritance Hook**: Modify the engine's initialization sequence (post-WAD load) to iterate the `PClass` list. Implement the `IsDescendantOf` logic to auto-populate the `VRWeaponData` structs.
2.  **JSON Parser Integration**: Integrate a lightweight JSON parser (if DoomXR doesn't have one exposed at this level yet) to read `doomxr_weapons.json` and override the inheritance mappings.

### Phase 3: The Render Hook (Suppression & Injection)
1.  **Sprite Suppression**: Hook into `DrawPSprite`. If the active weapon has a valid `VRWeaponData`, abort the 2D draw routine. Include suppression for off-hand layers and `PSP_FLASH`.
2.  **Static 3D Rendering**: Render the assigned 3D model at HUD coordinates in its `Ready` pose (frame 0). At this point, the visual shell is active but static.

### Phase 4: Animation Synchronization
1.  **State Interception**: Hook into `AWeapon::SetState`. Track state changes (Ready -> Fire, Ready -> Reload).
2.  **The Time Scaler**: Implement the logic that calculates the total tic duration of the foreign state sequence and scales the 3D animation's playback speed.
3.  **The Heuristics Engine**: Implement the "Clip Check" logic (detecting `Ammo2` drain and `Ammo1` gain) to identify non-standard reload states dynamically.

### Phase 5: User Interface
1.  **Native Menu Building**: Build the "VR Weapon Assignments" menu in the Options screen.
2.  **Data Binding**: Wire the menu dropdowns to dynamically read from the `PClass` weapon list and write changes directly to `doomxr_weapons.json`.

### Phase 6: QA & Adversarial Testing
1.  Load highly complex, adversarial mods (Golden Souls, Brutal Doom).
2.  Test dual-wielding, custom reload scripts, and auto-regenerating ammo edge cases to verify the heuristics hold.
