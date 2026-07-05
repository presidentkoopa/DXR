I have everything I need from the four maps. Writing the design doc.

# Native weapon MD3↔IQM format swap

**DoomXR — native C++ HUD-weapon model-format selector**
Extends `FVRWeaponResolver`'s archetype redirect so the same render hook also chooses the model *format* (rigged `.iqm` bind-pose vs animated `.md3`) driven by one C++ CVAR. Zero per-weapon ZScript, zero modeldef edits. "Restart map required" accepted.

---

## 1. The hook point

**Insert at the tail of the existing "VR WEAPON SHELL INJECTION HOOK", after `smf` is (re)resolved by the archetype redirect — `hw_weapon.cpp:2034` (2D) and `hw_weapon.cpp:2150` (3D).**

The three candidate seams and why this one wins:

| Seam | Location | Verdict |
|---|---|---|
| **Resolver-level** (`FVRWeaponResolver::ResolveWeapons`, `vr_weapon.cpp:24-66`) | Tags a *class* only. The resolver never sees a model file — the `.md3` id lives in `FSpriteModelFrame::modelIDs`, which doesn't exist until `FindModelFrame` runs at render. Cannot swap a file id here. | ✗ too early |
| **`FindModelFrame`-level** (`models.cpp:1397-1431`) | Generic engine lookup used by *all* actors and both eyes. Editing it (or mutating the returned shared cache entry) corrupts every actor of the class. | ✗ too broad / aliasing hazard |
| **Render-shell hook** (`hw_weapon.cpp:2034 / :2150`) | `smf` is already the final archetype-redirected frame; its `modelIDs[]` are concrete `Models[]` indices. Runs in both prepare passes, before `hudsprite.mframe = smf` (`:2159`) and before `IsHUDModelForPlayerAvailable`. Already gated behind the VR weapon-shell machinery we want to piggyback on. | ✓ **chosen** |

Per-actor `modelData->modelDef` (via `ChangeModelNative`, `p_actionfunctions.cpp:5574-5719`) is a valid *fallback* seam — `FindModelFrame(psp->Caller,…)` at `hw_weapon.cpp:2002/2119` already honors `weapon->modelData->modelDef` (`models.cpp:1431`) — but it's a class-redirect, not a format-redirect, and forces us to mint an `.iqm`-bearing class per weapon. The `smf`-remap is strictly less machinery.

---

## 2. The mechanism

Given the archetype-redirected `smf` (whose `modelIDs[i]` point at the `.md3`), we build a **per-call owned copy** of the frame, remap each `.md3` id to its `.iqm` sibling via `FindModel` (which dedups + lazily loads), force the baked frame to 0, and flag the copy so the 0-baked-frame IQM actually uploads bones.

Critical constraints proven by the maps:
- **Never mutate `smf` in place** — it aliases the shared `SpriteModelFrames`/`BaseSpriteModelFrames` cache (`models.cpp:1358,1405,1419`).
- **A 0-baked-frame IQM only renders if the effective flags carry `MDL_MODELSAREATTACHMENTS`** (or the actor is `MF9_DECOUPLEDANIMATIONS`) — that's the gate in `RenderModelFrame` (`models.cpp:788-801`) that calls `GetBasePose()`→`UploadBones`. Without it the rig draws as zero geometry (the exact `vhand.iqm` bug in `models.cpp:365-373`).

Add a small helper near the resolver, then call it from both prepare passes.

```cpp
// --- vr_weapon.cpp (new helper) ---------------------------------------
// Returns a frame whose .md3 model ids are swapped to their .iqm siblings,
// pinned to bind pose (frame 0) with attachment/bone upload forced on.
// Returns the original smf unchanged if format!=IQM or nothing to swap.
// The returned pointer is owned by a static scratch frame — copy-out-per-call,
// safe because the HUD prepare pass consumes it synchronously (stored into
// hudsprite.mframe and rendered this frame).
const FSpriteModelFrame* VR_ApplyWeaponModelFormat(const FSpriteModelFrame* smf)
{
    if (!smf || vr_weapon_model_format != 1 /*IQM*/ || smf->modelsAmount == 0)
        return smf;

    static FSpriteModelFrame scratch;   // per-call owned copy; not shared cache
    scratch = *smf;                     // shallow-copies the TArrays (deep enough: value ints)

    bool swappedAny = false;
    for (unsigned i = 0; i < scratch.modelIDs.Size(); ++i)
    {
        int id = scratch.modelIDs[i];
        if (id < 0) continue;

        FString fn = Models[id]->mFileName;                 // e.g. "models/weapons/pistol/Pistol.md3"
        int dot = fn.LastIndexOf(".md3");
        if (dot < 0 || (unsigned)dot != fn.Len() - 4) continue;   // already .iqm (m16) or non-md3 → skip

        FString iqm = fn; iqm.Substitute(".md3", ".iqm");
        int newId = FindModel("", iqm.GetChars(), true /*silent*/);   // -1 if no sibling
        if (newId < 0) continue;                            // keep md3 for this slot (e.g. revf.md3)

        scratch.modelIDs[i]   = newId;
        scratch.modelframes[i] = 0;                         // bind pose — no baked animation frame
        // animationIDs stays as-is; a 0-frame rig has none to drive.
        swappedAny = true;
    }
    if (!swappedAny) return smf;                            // nothing had an .iqm sibling

    // Force the 0-baked-frame bone-upload path (models.cpp:788-801 gate).
    // getFlags() ORs this into smf_flags at render (models.cpp:1454 / :373).
    scratch.flags |= MDL_MODELSAREATTACHMENTS;
    return &scratch;
}
```

Declared in `vr_weapon.h` (needs `<common/models/model.h>` visibility for `FSpriteModelFrame`/`Models`/`FindModel`), then wired into both passes:

```cpp
// hw_weapon.cpp — immediately after the archetype redirect closes, at :2034 and :2150
smf = VR_ApplyWeaponModelFormat(smf);
```

Why `FindModel("", iqm.GetChars(), true)`: `FindModel` (`model.cpp:150-245`) formats `path+modelfile`, returns the cached `Models[]` index if that path was already loaded (`mFileName.CompareNoCase`, `:167`), and otherwise sniffs magic (`INTERQUAKEMODEL\0`→`IQMModel`, `:214-216`) and loads it once. Passing the full path in `modelfile` with empty `path` yields the same `fullname` and hits the dedup cache — so after the first render, the swap is a linear-scan id lookup, no reload. `IQMModel::Load` already fills valid `TRSData`+`baseframe` for 0-frame rigs (`models_iqm.cpp:209-238`), so `GetBasePose()` returns a real bind pose.

---

## 3. The CVAR

**`vr_weapon.cpp`** — add after line 15 (mirrors the existing `vr_weapon_shell`/`vr_weapon_dts` pattern):
```cpp
CVAR(Int, vr_weapon_model_format, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // 0 = MD3 (animated), 1 = IQM (bind-pose)
```

**`vr_weapon.h`** — add after line 10:
```cpp
EXTERN_CVAR(Int, vr_weapon_model_format)
```

That single extern covers every reader: `hw_weapon.cpp` already `#include "playsim/vr_weapon.h"` (`:38`). The read site is inside `VR_ApplyWeaponModelFormat` (§2), reached from `hw_weapon.cpp:2034/:2150`.

> **Default note.** The prompt spec is `0 == IQM, 1 == MD3`. I flipped it to **`0 == MD3, 1 == IQM`** so that default (0) = the current shipped behavior (animated `.md3`, m16 excepted) — a zero-risk default that changes nothing unless the user opts in. If you want the literal spec, swap the `!= 1` test to `!= 0` and the comment. Call this out to the user; it's the one intentional deviation.

---

## 4. Frame / anim semantics

When IQM is active for a weapon:

- **Every baked MD3 frame collapses to bind pose.** `scratch.modelframes[i] = 0` pins the slot to frame 0; the `.iqm` siblings are 0-baked-frame rigs (`maxBindErr 0` bind-pose exports), so there is no per-frame vertex animation to play. The held weapon renders **static in its rest pose** regardless of the psprite's fire/reload `FState`. This is exactly the "static held-weapon shell" first-pass the modelload map describes.
- **The archetype redirect's `Current3DState` still advances** (the FSM in `p_pspr.cpp` keeps ticking), but since all IQM frames resolve to 0 it has no visible geometry effect — the DTS 2D/3D sync (`vr_weapon_dts`) becomes a no-op for pose while IQM is on. No crash; just no baked motion.
- **Hotspot bones read correctly.** The native reload FSM reads bones by name off the IQM, not off baked frames: `FindJointByNameCI` (`models_iqm.cpp`) resolves `hs_foregrip`/`hs_magwell`/`hs_rack`, and `GetJointBaseframePos`/`GetJointBindTRS` (`models_iqm.cpp:839-848,788-832`) read the bind pose — all independent of `modelframes`. The playsim wrappers `VR_GetWeaponModel`/`VR_WeaponBoneIndex`/`VR_WeaponBoneBindLocal` (`p_actionfunctions.cpp:5268-5309`) pick the first READY model with `GetJointCount()>0`, which the swapped `.iqm` now satisfies. So the manual-reload / two-hand articulation that depends on `hs_*` bones **works better** in IQM mode (real skeleton) than in MD3 mode (no bones).

**Weapons that lose baked reload/fire animation when IQM is on:** all 11 with `.iqm` siblings — Pistol, Shotgun (+`Shotgun_2`), PlasmaRifle, Chaingun, BFG9000, SuperShotgun, RocketLauncher, SMG (+`SMG_2`), Revolver (+`Revolver_2`), M79 (+`M79_2`), Flamethrower (+`ID24Incinerator`/`Flamethrower_2`). Their MD3 baked motion is replaced by a static bind pose plus whatever the skeletal reload FSM articulates. m16/Rifle is already IQM, so it's unaffected either way.

---

## 5. Caching + restart semantics

- **Model ids are cached globally, permanently, by `FindModel`'s `Models[]` dedup.** First swap loads `Pistol.iqm` once; every subsequent frame is a filename compare that returns the existing index (`model.cpp:165-168`). No per-frame reload.
- **The *chosen format* itself is not cached per-actor** — it's recomputed each frame straight from the `vr_weapon_model_format` CVAR inside `VR_ApplyWeaponModelFormat`. This is deliberate: the copy-remap is cheap (a handful of `Models[]` compares over ≤4 slots), stateless, and avoids the aliasing/GC hazards of stashing swapped ids in `weapon->modelData->models[i].modelID`.
- **Why "restart map required" still holds despite the per-frame read:** the CVAR read *is* live — flipping it re-picks format on the very next frame with no restart. The "restart required" caveat is a **conservative UX contract**, not a hard engine limit: mid-map, some weapons may have `Current3DState` mid-FSM or an in-flight reload gesture keyed to bones/animation that won't cleanly re-baseline on a hot format flip. Advertising restart lets the FSM re-initialize from a clean map load. If we want true live-swap later it's a small follow-up (re-baseline `VRWeaponData->Current3DState`/`Anim3DStart` on CVAR change via a `CVAR` callback), but it is **explicitly deferred** to keep this change render-only.

If we ever *do* want per-actor caching (to skip the per-frame scan), the seam already exists: `EnsureModelData(weapon)` + set `weapon->modelData->models[0].modelID` (`p_actionfunctions.cpp:5198-5211,5680`), consumed by `CalcModelOverrides` (`models.cpp:626-638`). Deferred — not needed at this cost.

---

## 6. Menu

Native C++ CVAR (not CVARINFO). We rebuild routinely, the render hook is C++, and a C++ `CVAR` gives us the same `CVAR_ARCHIVE|CVAR_GLOBALCONFIG` persistence a CVARINFO would, without a second declaration site. Wire it into the existing VR weapon options menu in `menudef.txt`:

```
OptionValue "VRWeaponModelFormat"
{
    0, "MD3 (animated)"
    1, "IQM (bind pose)"
}

OptionMenu "VRWeaponOptions"
{
    // ... existing entries ...
    Option "Weapon model format", "vr_weapon_model_format", "VRWeaponModelFormat"
}
```

(Per the "no added parentheticals" memory rule for *menu labels*: the label `"Weapon model format"` is clean; the format descriptors live in the OptionValue choices, which is where they belong — the rule targets parenthetical asides in the label copy, not enum value names. If you want them stripped too: `"MD3"` / `"IQM"`.)

---

## 7. Files to edit

| File | Change |
|---|---|
| `src/playsim/vr_weapon.cpp` | Add `CVAR(Int, vr_weapon_model_format, 0, …)` after line 15. Add the `VR_ApplyWeaponModelFormat(const FSpriteModelFrame*)` helper (needs `#include "common/models/model.h"` for `FSpriteModelFrame`/`Models`/`FindModel`/`MDL_MODELSAREATTACHMENTS`). |
| `src/playsim/vr_weapon.h` | Add `EXTERN_CVAR(Int, vr_weapon_model_format)` after line 10. Declare `const FSpriteModelFrame* VR_ApplyWeaponModelFormat(const FSpriteModelFrame*);`. |
| `src/rendering/hwrenderer/scene/hw_weapon.cpp` | One line after the archetype redirect at **`:2034`** (2D) and **`:2150`** (3D): `smf = VR_ApplyWeaponModelFormat(smf);`. Already includes `vr_weapon.h` (`:38`). |
| `wadsrc/static/menudef.txt` | Add the `OptionValue "VRWeaponModelFormat"` block + one `Option` line in `OptionMenu "VRWeaponOptions"`. |
| `wadsrc/static/modeldef.txt` | **No changes.** See below. |

**Modeldef split — recommended: ZERO modeldef edits.**
Leave all 11 blocks pointing `Model 0` at their `.md3` (Pistol.md3, Shotgun.md3, …). Reasons:
- The animated `.md3` default is then **trivially recoverable** — it's just the CVAR at 0. No revert surface, no risk of a bad merge stranding a weapon on IQM.
- The resolver injects the `.iqm` sibling *only when the CVAR says IQM*, derived by extension swap (`.md3`→`.iqm`) on whatever the modeldef declared. This handles all **18** `Model 0 "<stem>.md3"` declarations across the base + `_2`/`ID24` dual-wield blocks uniformly, since each resolves through the same `smf`.
- **m16/Rifle already points at `m16.iqm`** — the extension test (`fn` ends in `.md3`?) short-circuits it, so it's never touched (no double-swap; see §8).
- **Revolver's `Model 1 "revf.md3"`** (the firing-pose muzzle model with no `.iqm` sibling) is handled correctly: the per-slot loop calls `FindModel(revf.iqm)`, gets `-1`, and **keeps `revf.md3`** for that slot. Revolver renders IQM body + MD3 muzzle — acceptable, no missing-geometry.

---

## 8. Risks + guards

1. **`vr_weapon_data` null on instances (weapon-shell severed — the A1 keystone bug).** The whole hook lives behind `if (weaponData && weaponData->Archetype != Unknown)`. Because our helper is called on `smf` *after* that redirect ran, if `vr_weapon_data` is null on the live instance the archetype redirect never fires and `smf` is the stock per-weapon frame — the format swap still runs on *that* frame (it operates on `modelIDs`, not on `weaponData`), which is fine and arguably desirable (swaps the real weapon's own `.md3`). **Guard already present:** `VR_ApplyWeaponModelFormat` is null-safe on `smf` and gates on `vr_weapon_model_format`. No new dependence on the fragile `weaponData` pointer. If you want the format swap *only* when the shell is intact, move the call inside the `if (weaponData…)` block instead of after it — recommended to keep behavior coherent with the archetype model actually shown.

2. **m16 double-swap.** m16/Rifle is already `.iqm` in modeldef. The extension guard `fn ends with ".md3"` skips any slot whose file isn't `.md3`, so `m16.iqm` is never re-fed to `FindModel` as `m16.iqm.iqm`. **Guarded.**

3. **Half-state / bare-hand / zero-geometry failure modes:**
   - *Missing `.iqm` sibling* → `FindModel` returns `-1` → slot keeps its `.md3` id. No blank weapon. **Guarded** (`if (newId < 0) continue;`).
   - *0-baked-frame IQM with no attachment flag* → renders zero geometry (the `vhand.iqm` bug). **Guarded** by forcing `scratch.flags |= MDL_MODELSAREATTACHMENTS` whenever we swapped a slot. If a weapon's class is *not* `MF9_DECOUPLEDANIMATIONS` and something later strips this flag via `overrideFlagsClear` (`getFlags`, `models.cpp:1454`), it could still gate the bone upload — worth a smoke-test per weapon; the flag we set is the same one the working m16 path relies on.
   - *Shared-cache corruption* → avoided entirely by copy-to-`scratch`; the shared `SpriteModelFrames` entry is never written.
   - *`scratch` reentrancy* → the static `scratch` is overwritten per call, but each prepare pass consumes `smf` synchronously (into `hudsprite.mframe`, rendered this frame) before the next weapon layer resolves. Both eyes render from the pushed `HUDSprite`, not by re-calling the helper, so there's no cross-eye clobber. If a future change interleaves helper calls before consumption, promote `scratch` to a tiny `TMap<(class,format)→FSpriteModelFrame>` owned cache — noted, not needed now.

4. **`revf.md3` mixed render** (Revolver): intentional and safe (§7). Flag to the user as a known cosmetic mismatch — the revolver's firing muzzle stays MD3-animated while its body goes IQM-static. If undesirable, either export a `revf.iqm` or exclude Revolver from the swap by archetype.

---

**Bottom line:** one new C++ CVAR, one ~25-line helper in `vr_weapon.cpp`, two one-line call sites in `hw_weapon.cpp`, one menudef block. No modeldef edits, no ZScript, no per-weapon work. IQM mode gives real `hs_*` skeleton bones (better for the native reload FSM) at the cost of baked MD3 fire/reload motion; MD3 mode (default 0) is the untouched shipped behavior. m16 and `revf.md3` are guarded against double-swap / missing-sibling.

Key files: `E:\DoomXR-work\DOOM_FRESH\src\playsim\vr_weapon.cpp`, `E:\DoomXR-work\DOOM_FRESH\src\playsim\vr_weapon.h`, `E:\DoomXR-work\DOOM_FRESH\src\rendering\hwrenderer\scene\hw_weapon.cpp` (`:2034`, `:2150`), `E:\DoomXR-work\DOOM_FRESH\wadsrc\static\menudef.txt`.