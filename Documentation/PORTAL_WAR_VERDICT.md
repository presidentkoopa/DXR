# ⚔️ PORTAL WAR — REFEREE'S VERDICT

**Combatants:** Team Velocity (`PORTAL_WAR_TEAM_VELOCITY.md`) vs Team Bedrock (`PORTAL_WAR_TEAM_BEDROCK.md`)
**Contested hill:** a live-rotating walk-through portal in DoomXR — is "cheap" seamless enough, or is a native rewrite required?

---

## THE RULING

**Both armies won — because they were fighting over two different products, and the war forced each to prove exactly where the line between them is.**

### Velocity takes the week. ✅
Their trace holds: for an **INTERACTIVE** portal on a rotating polyobject, the render transform is *stateless* — recomputed every frame from live linedef geometry (`SetPortalRotation` portal.cpp:214, invoked at :457/:485/:504, driven per render pass from hw_portal.cpp:640). No cache → no drift → no seam tear. Rotation is applied *correctly by construction* at render and at crossing, because interactive portals never touch the translation-only displacement table. **The spinning airlock ships in ~4 days:** map (Day 1) → `XR_PolyPortalCarrier.zs` crossing script (Day 2) → headset tuning (Day 3) → optional ~20-line C++ fill of the engine's own `// Fixme` at po_man.cpp:1110 (Day 4).

**Bedrock formally conceded this** (§5.4 of their report): "If your seam can tolerate the recursive 'window' feel... you don't need this build at all. That is a legitimate product choice."

### Bedrock takes the campaign — and shrank the mountain. ✅
Their 8-break list (blockmap misses at ~71% of range at 45°, sound panned to the wrong ear, monster sight firing at ghosts, VR right-eye skew, netcode rubber-banding) is **real — but it applies to rotating a LINKED seam cheaply, which nobody should ever ship.** Their killer proof: `FDisplacement` = `{DVector2 pos; bool isSet;}` — no angle, no pivot — and the engine *deliberately amputates* rotation for linked portals (portal.cpp:237-240 "Linked portals have no angular difference").

**The war's biggest prize:** Bedrock's architect found the design that collapses "months" into **14 days**:
- Add `DAngle angle` + `DVector2 pivot` to `FDisplacement`; new `getOffsetRot(x, y, testPos)` with an `angle==0` fast path → **every existing map byte-identical, zero regression.**
- `MoveRotateGroup` mirrors the existing `MoveGroup` pattern (~1-line call from `UpdateLinks`).
- **No coverage/BSP rebuild needed** — rotation is deferred to *query time*, so the load-time coverage cache (keyed on displacement) stays valid. This kills the scariest cost from the earlier 45–70-day estimates.
- Migration: physics → sight → sound → automap → render → netcode, borrowing the rotation math already proven in the interactive path.

### What the earlier gauntlet said "45–70 days," this war priced at **14.**
That's the value of the fight: the query-time-rotation insight + the coverage-cache dodge weren't in any earlier swarm's plan.

---

## THE DECISION TREE

1. **NOW (~4 days):** Ship Velocity's interactive spinning airlock. Single-eye correct, walk-through carried, comfort-tunable. Bedrock's break-list becomes the **v1 test plan** (check: sound through the seam, monster combat at the seam, second-eye skew).
2. **GATE:** Feel it in the headset. If the "window" render quality and absent cross-seam sound are fine for the game → done, save 14 days.
3. **IF the design demands linked-quality** (continuous coverage, sound/sight/blockmap continuity, monsters fighting *across* the spinning seam): fund **Bedrock's 14-day native build**. It is no longer a "months" decision.

## SHARED DEBT (both paths)
- **VR right-eye skew at a rotating seam** (right eye derived from prev-frame delta, hw_drawinfo.cpp) — deferred by decree; fix later by computing the right-eye portal transform independently (~1.5d per earlier gauntlet).
- Netplay 2v2 waits on the pre-existing VR-aim checksum blindspot — orthogonal to portals.

## CASUALTY REPORT
- Velocity lost 1 of 4 combatants (structured-output failure); field marshal covered the ground.
- Bedrock's "45–70 day" fear from the earlier gauntlet is KIA — killed by their own architect's 14-day design.
