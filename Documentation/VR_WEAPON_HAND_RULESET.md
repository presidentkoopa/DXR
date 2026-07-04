# DoomXR — Canonical Grab / Equip / Throw / Catch / Dual-Wield Ruleset

**Status: source of truth. Verified against `E:\DoomXR-work\DOOM_FRESH` this session. Not yet built.**

This is the single agreed contract for how a weapon (or pickup, or prop) moves into,
between, and out of the player's hands in VR. Every menu (3D wheel, Check-Your-Watch
forearm grid, Seam-Reveal chest bag) and the gravity-glove/throw/catch flow obey it.

Legend:
- **[WORKS]** — already behaves this way today.
- **[GLUE]** — machinery exists; one named ZScript/thin-branch wire-up is all that's missing. No C++ engine feature.
- **[NEW]** — no native path exists; genuinely new work.

**Headline: nothing in this contract needs a new native engine feature. Every gap is ZScript glue.**

---

## The two tracking systems (why this doc exists)

The engine tracks "what's in a hand" in two systems that never talk to each other:

- **Physics-held** — `player->vr_held_items[hand]` (raw `AActor*`). What gravity-glove/catch
  holds. Throwable. **Not fireable** — it's a gripped object, not an equipped weapon.
  (`p_user.cpp:1857`)
- **Equipped** — `player->ReadyWeapon` (main) / `player->OffhandWeapon` (off), inventory
  `Weapon*` pointers. The only fireable path. Which hand a weapon is in is stored on the
  weapon as `Weapon.bOffhandWeapon`, which routes it to the `PSP_OFFHANDWEAPON` render
  layer. (`weapons.zs:283`)

The single hand-aware bridge between "owned weapon" and "in this specific hand" is
`PlayerPawn.MoveWeaponToHand(weap, hand)` (`player.zs:2565-2603`). Every rule below is
about wiring the physics-held side into that bridge correctly.

---

## RULE 1 — Grab dispatches by object type

Grab site: `p_user.cpp:1837-1843` (item arrived within 12u of hand, `vr_autoequip` on).
Today the only test there is a blanket `heldItem->flags & MF_SPECIAL` — there is **no**
weapon-vs-consumable-vs-prop router.

- **1.1 Pickup (health / ammo / armor) → auto-applies on grab.** **[WORKS]**
  `MF_SPECIAL` routes `P_TouchSpecialThing → CallTouch → Inventory.Touch → CallTryPickup`
  = vanilla consume. Grab == stepping on it: applied and gone.
- **1.2 Prop (barrel, `flags:grabprop`) → held, throwable/shootable in flight.** **[WORKS]**
  No `MF_SPECIAL`, so it skips auto-consume; magnet-held, and on release thrown with real
  velocity, `+SHOOTABLE` so it can be shot mid-air, toward or away from you.
- **1.3 Weapon → equips to the GRABBING hand, becomes fireable.** **[GLUE]**
  *Broken today:* a Weapon is `MF_SPECIAL` like a medikit, so it hits the same auto-consume
  branch and does a **hand-blind** vanilla give — always main hand, never the grabbing hand,
  and `bOffhandWeapon` is never set.
  *The fix (entire delta):* one type branch at `p_user.cpp:1837` — if
  `heldItem is "Weapon"`, route through `MoveWeaponToHand(weap, hand)` with the grabbing
  hand's index instead of the blind give. Leave 1.1 and 1.2 untouched.

---

## RULE 2 — Same weapon, second grab (akimbo)

- **2.1 Same weapon into the SAME hand → just ammo.** **[WORKS]**
  Vanilla: `Weapon.HandlePickup` matches the class, grants ammo, returns. `MaxAmount`
  defaults to 1 so no second instance is created. Correct as-is.
- **2.2 Same weapon into the OTHER (empty) hand → a real second instance (shotgun in each hand).** **[GLUE]**
  *Not supported today:* weapons hard-cap at one instance per class (`MaxAmount 1`,
  `inventory.zs:82`), and the hand bridges collapse same-class (`MoveWeaponToHand →
  WeaponsMatch on GetClass() → SwitchWeaponHand`, which just moves the one instance).
  *But it's glue, not engine work:* dual-hand firing is **instance-based, not class-based**
  — `ReadyWeapon` and `OffhandWeapon` are independent slots with independent render layers.
  The glue: (1) lift the one-instance cap for that weapon (raise `MaxAmount`, or bypass
  `HandlePickup` on the equip path), then (2) a custom equip routine that assigns the two
  **distinct** instances — one to `ReadyWeapon` (`bOffhandWeapon=false`), one to
  `OffhandWeapon` (`bOffhandWeapon=true`). Do **not** use `MoveWeaponToHand` here (it
  collapses same-class). Pure ZScript. No C++.

---

## RULE 3 — Toss-and-catch (catch into an occupied hand → swap + rotate)

- **3.1 Catch into an EMPTY hand → equip into that hand.** **[GLUE]**
  Catch today only stores a raw `AActor*` into `vr_held_items[hand]`; it never equips.
  The equip machinery (`MoveWeaponToHand` into an empty hand → `BringUpWeapon`) exists;
  the catch→equip trigger must be written.
- **3.2 Catch a self-tossed weapon into an OCCUPIED hand → caught weapon in, displaced weapon rotates to the other (just-emptied) hand. Nothing lost.** **[GLUE]**
  Key finding: **`DropWeapon` is a misnomer** — it does NOT throw a weapon to the world.
  It only lowers that hand's PSprite and raises the pending weapon; the displaced weapon
  survives in inventory. So the rotate is achievable with existing calls: capture the
  displaced weapon (`targetcurrent`, `player.zs:2590`), relocate it to the empty other hand
  **first** via `SwitchWeaponHand` (atomic), then bring the caught weapon into the freed hand.
  *Correctness constraint:* the raise path is deferred and single-slotted (`PendingWeapon`
  is one slot, `A_Lower→BringUpWeapon` spans several tics). Do the displaced-weapon
  relocation via `SwitchWeaponHand` first; never fire a bare `DropWeapon` mid-rotate (it
  clobbers `PendingWeapon`). Needs a thin wrapper (`CatchWeaponIntoHand`) to orchestrate.
- **3.3 Both hands full → background the displaced weapon (safe).** **[WORKS]**
  Nowhere to rotate; the existing occupied-hand path backgrounds the displaced weapon into
  inventory (still owned, re-selectable, never lost to the world). A literal world-drop
  fallback would be **[NEW]** (via the separate throw path) — only if ever desired.

---

## RULE 4 — Toss backfill (what fills the throwing hand after it empties)

Native option `vr_toss_backfill` (CVAR), read at the throw site (`p_user.cpp:1641-1672`,
where the hand index and `player` pointer are both already in scope). Applies whenever a
hand empties by tossing — both the throw-at-world case and the toss-to-own-other-hand
handoff empty the throwing hand, so backfill runs for both.

- **4.1 VR hands (empty)** — hand stays bare, ready to grab/punch/gesture. **[WORKS]**
  This is the default; the throw already nulls the hand.
- **4.2 Next weapon** — **[WORKS mechanic → native wire]**
  `PlayerPawn.PickNextWeapon(hand)` (`player.zs:2667`) already exists and is **hand-aware** —
  it reads `ReadyWeapon` vs `OffhandWeapon` and filters by `bOffhandWeapon`. Native CCMD
  `weapnext <hand>` exists (`g_game.cpp:482`). Backfill = a native CVar read + hand-aware
  call at the throw site. Light, native, no ZScript hackery.
- **4.3 Previous weapon** — **[WORKS mechanic → native wire]**
  Same, via `PickPrevWeapon(hand)` (`player.zs:2723`) / `weapprev <hand>` (`g_game.cpp:516`).
- **4.4 Last held weapon (per hand)** — **[NEW — native state]**
  No per-hand last-weapon memory exists today. There's only a global respawn flag
  (`sv_rememberlastweapon`, main-hand-only, respawn-only) and per-morph storage
  (`PremorphWeapon`/`PremorphWeaponOffhand`, unmorph recovery only, `d_player.h:419-420`).
  So this needs a new native per-hand field: `AActor* vr_last_held_weapon[2]` on `player_t`
  (mirrors `vr_held_items[2]`), **serialized** (per the save/load landmine below), updated on
  every equip. Small, clean native addition — exactly the native-first shape.

Modder exposure: `vr_toss_backfill` is an engine-level CVAR (native-first rule: engine-level
+ modder-exposed). v1 is one global option; a per-hand variant can come later.

## Summary ledger

| Rule | Behavior | Status |
|------|----------|--------|
| 1.1 | pickup → auto-apply | **WORKS** |
| 1.2 | prop → hold / throw / shoot-in-flight | **WORKS** |
| 1.3 | weapon → equip to grabbing hand | **NATIVE** — type branch @ `p_user.cpp:1837` → native `VR_EquipToHand` |
| 2.1 | same weapon, same hand → ammo | **WORKS** |
| 2.2 | same weapon, other hand → akimbo | **NATIVE** — lift one-instance cap + assign two distinct instances directly (not `MoveWeaponToHand`) |
| 3.1 | catch into empty hand → equip | **NATIVE** — wire catch → `VR_EquipToHand(weap, hand)` |
| 3.2 | catch into occupied → swap + rotate | **NATIVE** — `VR_CatchWeaponIntoHand`, `SwitchWeaponHand`-first ordering |
| 3.3 | both hands full → background (safe) | **WORKS** (world-drop variant = NEW) |
| 4.1 | toss backfill: VR hands (empty) | **WORKS** (default) |
| 4.2 | toss backfill: next weapon | **WORKS** mechanic → native wire (hand-aware `PickNextWeapon`) |
| 4.3 | toss backfill: prev weapon | **WORKS** mechanic → native wire (hand-aware `PickPrevWeapon`) |
| 4.4 | toss backfill: last held (per hand) | **NEW** native field `vr_last_held_weapon[2]` (serialized) |

**Native-first note (per project standing rule):** the items previously framed as "ZScript
glue" are graded here as **NATIVE** seams — a native `VR_EquipToHand(weap, hand)` C++ owner
that sets the per-hand slot + `bOffhandWeapon` + `PendingWeapon` directly, rather than routing
through the ZScript `MoveWeaponToHand`/`WeaponsMatch` helpers that collapse same-class and
can't be serialized or net-routed from the content layer. ZScript weapons are the things
being moved; the native layer does the moving.

The two "works today" thirds (1.1, 1.2) work by accident of vanilla `MF_SPECIAL`/grabprop
flags, not an intentional router. Everything marked GLUE is ZScript composed from calls
that already exist.

---

## Cross-cutting invariants (hold for all menus + throw/catch)

- **One hand, one thing.** A hand is empty, holds one equipped weapon, or holds one physics prop — never more.
- **A weapon is in exactly one place.** Equipped, OR physics-held, OR flying/in-world — never two at once.
- **The grabbing/catching hand is the owning hand.** Always pass the acting hand's index to `MoveWeaponToHand`; never rely on vanilla's main-hand-default give.
- **Weapon state rides the actor** (ammo/condition), inherent to inventory items. Caveat: while a weapon is a loose thrown/held prop it is out of inventory; the re-acquire path must reuse the same instance, not spawn a class default, or ammo resets. **[verify before relying on]**
- **Menus are a view, not a store.** Selecting a cell issues a `MoveWeaponToHand`; the cell is never an authoritative location.

## Open decisions (need the user)

1. **Akimbo MaxAmount approach** — raise the weapon's `MaxAmount` globally (also changes floor-pickup stacking) vs. bypass `HandlePickup` only on the catch/equip path. Both ZScript; different side effects.
2. **Both-hands-full fallback** — background the displaced weapon into inventory (safe default, works today) vs. an actual world-drop (new work). Default assumed: background.

## Known landmines (from the prior spec pass, still true)

- **Save/load loses physics-held items.** `vr_held_items[2]` is not serialized; equipped weapons are. A weapon being held (not equipped) at save time is lost on load. Needs a rule.
- **Multiplayer desync.** `MoveWeaponToHand` mutates local playsim state with no net command. Solo-safe; will desync in netplay. Ties into the standing net-sanitize mission.
- **"Instantly fireable" has raise latency.** Equipping plays a raise animation — fireable in a fraction of a second, not the same tic.
