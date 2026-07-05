# Documentation — all files, numbered by date of creation

Every document in this folder, ordered oldest → newest and given a running number.

**How the dates were derived.** Git history is useless for this — the whole folder was
committed to `presidentkoopa/DXR` in three bulk imports (Jul 3 23:22, Jul 4 03:37, Jul 4 04:00),
so every file shares one of three commit timestamps. The filesystem *birth* time is also an
artifact — most files were bulk-copied onto this drive at `2026-07-03 16:18:53`. The one signal
that survived from original authoring is each file's **modification time (mtime)**, which is
well-differentiated and is used here as the creation-date estimate. Where a file was created
natively on this drive and edited later (`VR_WEAPON_HANDLING_ENGINE_LEVEL.md`), its earlier
*birth* time is used instead.

This index is **non-destructive** — no files were renamed. The existing
[`00_GRAVITY_JOURNEY_READING_ORDER.md`](00_GRAVITY_JOURNEY_READING_ORDER.md) is a curated
*reading* order for the gravity/portal thread (deliberately not chronological) and is left
intact; it appears below at its own creation date like everything else.

| # | Created | Document | Project | What it is |
|--:|---------|----------|---------|------------|
| **Jul 2** | | | | |
| 1 | Jul 2, 17:36 | [status.txt](status.txt) | Vision | SDF-driven, keyword-divorced-from-Doom status/vision note |
| 2 | Jul 2, 18:27 | [DoomXR_Capability_Audit_FULL.txt](DoomXR_Capability_Audit_FULL.txt) | Audit | Full engine capability audit (212 KB dump) |
| **Jul 3** | | | | |
| 3 | Jul 3, 00:14 | [HF_NEON_ARCADE_PLAN.md](HF_NEON_ARCADE_PLAN.md) | HF | HF Neon Arcade — plan of action |
| 4 | Jul 3, 00:20 | [GRAVITY_CUBE_THEORY.md](GRAVITY_CUBE_THEORY.md) | Gravity | First investigation: gravity is a scalar, theorize the vector fix |
| 5 | Jul 3, 00:49 | [GRAVITY_PLAN_AUTOPSY.md](GRAVITY_PLAN_AUTOPSY.md) | Gravity | Red-team autopsy of the gravity-vector plan |
| 6 | Jul 3, 01:03 | [DXR_SWORD_SLICE_DOSSIER/](DXR_SWORD_SLICE_DOSSIER) | Sword | Blade-slicing + VR-sword dossier (4-part folder: 0 summary → 3 shader map) |
| 7 | Jul 3, 02:48 | [PORTAL_STACKING_ROTATING_CUBES_PLAN.md](PORTAL_STACKING_ROTATING_CUBES_PLAN.md) | Portal | Portal-group tiling + independently-rotatable cube rooms |
| 8 | Jul 3, 03:01 | [LIVE_SPINNING_PORTAL_GET_US_THERE.md](LIVE_SPINNING_PORTAL_GET_US_THERE.md) | Portal | "Get us there" — live-spinning walk-through portal |
| 9 | Jul 3, 03:10 | [DoomXR_Shader_Tweaks_Proposal.md](DoomXR_Shader_Tweaks_Proposal.md) | Shader | Shader tweaks proposal (dead ripplePos etc.) |
| 10 | Jul 3, 03:15 | [PORTAL_WAR_TEAM_VELOCITY.md](PORTAL_WAR_TEAM_VELOCITY.md) | Portal | Battle report — the cheap ~4-day spinning-airlock path |
| 11 | Jul 3, 03:16 | [DoomXR_Whip_IQM_Rigging_Patch_Spec.md](DoomXR_Whip_IQM_Rigging_Patch_Spec.md) | Whip | Whip IQM procedural-rigging patch spec |
| 12 | Jul 3, 03:16 | [PORTAL_WAR_TEAM_BEDROCK.md](PORTAL_WAR_TEAM_BEDROCK.md) | Portal | Battle report — the native "live seam" path |
| 13 | Jul 3, 03:16 | [DoomXR_Physics_Whip.md](DoomXR_Physics_Whip.md) | Whip | Physics whip & engine feature map |
| 14 | Jul 3, 03:17 | [PORTAL_WAR_VERDICT.md](PORTAL_WAR_VERDICT.md) | Portal | Referee's verdict: ship the 4-day portal, seamless is a scoped 14-day job |
| 15 | Jul 3, 03:18 | [DoomXR_VRSword_HandVelocity_Patch_Spec.md](DoomXR_VRSword_HandVelocity_Patch_Spec.md) | Sword | VR-sword hand-velocity native-binding patch spec |
| 16 | Jul 3, 03:31 | [SPHERE_BATTLEFIELDS.md](SPHERE_BATTLEFIELDS.md) | Gravity | Two flat arenas as inverted-sky spheres; next build |
| 17 | Jul 3, 03:40 | [XR_GRAVITY_PATH_POWER.md](XR_GRAVITY_PATH_POWER.md) | Gravity | Hand-cast gravity-painting power (became vr_gravity_path.zs) |
| 18 | Jul 3, 03:44 | [DoomXR_Holster_System_Plan.md](DoomXR_Holster_System_Plan.md) | Holster | Holster system plan (pure-ZScript v1) |
| 19 | Jul 3, 04:01 | [XR_SDF_GRAVITY_RIBBON.md](XR_SDF_GRAVITY_RIBBON.md) | Gravity | Fuse the power with SDF shader + grapple — neon-road visual |
| 20 | Jul 3, 04:42 | [GRAVITY_ENGINE_JOURNEY.md](GRAVITY_ENGINE_JOURNEY.md) | Gravity | One-page summary of the whole gravity/space arc |
| 21 | Jul 3, 14:37 | [DoomXR_Whip_Entangle_Yank_Engine_Feature_Report.md](DoomXR_Whip_Entangle_Yank_Engine_Feature_Report.md) | Whip | Whip entangle/yank as an engine-level physics feature |
| 22 | Jul 3, 16:15 | [DoomXR_Whip_MASTER_PLAN.md](DoomXR_Whip_MASTER_PLAN.md) | Whip | Whip master implementation plan |
| 23 | Jul 3, 16:16 | [XR_DEBUG_VISUALIZERS.md](XR_DEBUG_VISUALIZERS.md) | Debug | Cones/spheres/rays/colors for VR interaction volumes |
| 24 | Jul 3, 21:34 | [XR_GRAVITY_HANDOFF.md](XR_GRAVITY_HANDOFF.md) | Gravity | Exhaustive gravity-lane session handoff (build-verified) |
| 25 | Jul 3, 21:34 | [00_GRAVITY_JOURNEY_READING_ORDER.md](00_GRAVITY_JOURNEY_READING_ORDER.md) | Gravity | Curated reading order for the gravity/portal/sphere thread |
| **Jul 4** | | | | |
| 26 | Jul 4, 01:59 | [GITD_MAIN_FP_SHADER_FEATURE_MAP.md](GITD_MAIN_FP_SHADER_FEATURE_MAP.md) | Shader | GITD `main.fp` shader feature map & cleanup notes |
| 27 | Jul 4, 03:43 | [VR_WEAPON_HANDLING_ENGINE_LEVEL.md](VR_WEAPON_HANDLING_ENGINE_LEVEL.md) | Weapons | Engine-level articulated two-hand + manual reload |
| 28 | Jul 4, 04:24 | [DXR_VS_DOOMXR_CHANGES.md](DXR_VS_DOOMXR_CHANGES.md) | Reference | DXR vs. DoomXR — definitive change reference |
| 29 | Jul 4, 04:37 | [VR_WEAPON_HAND_RULESET.md](VR_WEAPON_HAND_RULESET.md) | Weapons | Canonical grab/equip/throw/catch/dual-wield ruleset |
| **Jul 5** | | | | |
| 30 | Jul 5 | [XR_INTERACTION_GLOWS_AND_HAND_COLLISION.md](XR_INTERACTION_GLOWS_AND_HAND_COLLISION.md) | VR QoL | Hand-vs-wall collision + IK clamp, and glow cues across grab/two-hand/hardpoint/reload/catch/throw/whip/hook; grab-weight sliders made real |

*The four files inside `DXR_SWORD_SLICE_DOSSIER/` (`0_EXECUTIVE_SUMMARY` … `3_SHADER_SYSTEM_MAP`,
authored Jul 3 01:03–03:25) are already self-numbered and are treated as one unit at #6.*
