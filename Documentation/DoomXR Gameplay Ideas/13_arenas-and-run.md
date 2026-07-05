# 13 — Arenas & the run structure

The level layer. Maps are **reconfigurable holodeck stages** wired into a **portal lattice**.
A run is a 3D graph of rooms you thread with gravity and whips, and every portal is a branch.

## The holodeck principle

Maps are still maps — authored space — but each room is a **reconfigurable stage, not a
static level.** The model is the Star Trek TNG holodeck: a grid that physically re-forms
into the next program.

- A room = a grid of **player-sized tiles** on **floor and ceiling** (`y × y`),
  **dynamically textured**, with about **six presets** you call up to reshape it.
- Plus **floating polyobject platforms** to ride around inside.
- Rooms **rotate** (Inception) — this is where the gravity code cashes out. A floor exit
  turns into a wall, then a ceiling exit, as the room spins.

## The constraint tree (curated variety, not procedural slop)

Every room is tagged with a **type**, and the type gates a tree of what can happen in it:

```
ROOM TYPE  (this room is type C)
   └─ allows TEMPLATES:  V, R, 5, X
         └─ V allows SET-PIECES:  13, 55, 22
         └─ R allows SET-PIECES:  04, 33
         └─ ...
```

The tree is a **curation layer** — that's what makes this good instead of chaos. A type-C
room only ever runs coherent type-C things. You author a finite pile of set-pieces,
templates, and types, and the constraints yield huge variety while **every combination
still fits.** That's the difference between the holodeck running a program and a room
barfing random junk.

**It's data.** Types, templates, set-pieces are tables. Build the stage engine once; new
content is new rows in the tree, not new code. (Same philosophy as the gesture engine,
[11](11_gesture-engine.md).)

## The stage is played by the difficulty director

The difficulty director ([06](06_difficulty-director-dda.md)) is the **holodeck
computer** — it picks the next template/set-piece **from the room's allowed menu** based
on how hard you're dominating. Coherent, not arbitrary: the type→template→set-piece tree
is exactly what keeps the director's choices in-bounds. The physical reconfiguration
(rotation, rising tiles, retexture) is *how* the room re-forms between the director's cues.

## The run = a portal lattice

Macro layout = **Smash TV, but 3D.**

- A lattice of cube rooms.
- **8 exits per room: 4 in the floor, 4 in the ceiling.** Each is a **portal** to the next
  node.
- So the "map" isn't a plane of rooms you walk between — it's a **3D grid you thread on any
  axis.**
- **Whips + grav panels are the traversal grammar** that makes the ceiling exits reachable.
  "Which of the 8 doors do I take" becomes a movement puzzle — swing up to a ceiling
  portal, or flip gravity and walk to a side-turned one.

## Portals = the run's branches (a spatial roguelite)

A portal doesn't just go "next fight." The nodes on the other side vary:

- another **arena** (combat / loot)
- the **shop** (spend gold on gestures + abilities — [07](07_economy-shop.md))
- a **bonus** level
- a **secret**
- a **joke / breather** room

That portal-choice is the **entire roguelite decision layer** — Hades/Isaac/FTL
door-choice, but the doors are physical portals in rotating 3D cubes. *Do I push into
another fight for loot, bank at the shop, or take the breather?* Nobody's really done the
door-choice as an actual 3D orientation puzzle.

## Earned path control (a modicum)

Give the player **a nudge** on their path — enough that the run feels theirs, **not** so
much they can trivially steer to the shop every time. Full control kills roguelite
tension; zero feels random. "A modicum" is the dial. Two mechanisms, both riding systems
that already exist:

- **Playstyle-driven (passive).** The director's read — dominance, per-gun TTK, aggression
  — biases which exits open or where they lead. Stomping aggressively → more combat/loot
  portals surface. Hurt / playing careful → a shop or breather portal shows up. The map
  quietly bends toward how you're already playing; the player never has to ask.
- **Goal-driven (active).** The room hands you an objective — "15-kill chain," "clear
  without a hit," "3 headshots" — and hitting it **reorients an exit in your favor.**
  Opt-in, skill-expressed. Detection is *free*: the combo chain ([04](04_scoring-combo.md))
  and crit system ([05](05_crits-locational.md)) already track exactly those things.

**"Reorient" can be literal.** Because the rooms rotate, a favorable outcome doesn't just
flag a better portal — it can physically **turn the room** so the good exit swings into
reach, or light a gold door on a face that was pointing away. The reward is spatial.

**Legibility knob:** hidden influence ("huh, chaining kills opened a gold door") = discovery
and mystique; surfaced ("Objective: chain 15 → vault portal") = a challenge to chase. Mix
them — obvious goals early to teach the system, hidden ones later for depth.

## How this ties the whole arsenal together

| System | Role in the run/room layer |
|---|---|
| SDF drawing / shapes | room UI, objective callouts, shop, score pops, sigils |
| Combo chain + score ([04](04_scoring-combo.md)) | goal detection + the play-quality read |
| Loot / rarity / upgrades ([02](02_classes-and-loadout.md), [08](08_encounter-spikes.md)) | the progression chase inside combat rooms |
| Captains / minibosses ([08](08_encounter-spikes.md)) | the set-piece spikes a room builds around |
| Color-tier monsters + glow ([06](06_difficulty-director-dda.md)) | director escalation made visible |
| Gravity code | room flipping + reaching ceiling exits |
| Whips | traversal across the lattice to the portals |
| Gold economy ([07](07_economy-shop.md)) | the shop node between fights |
| C++ + map control | the reconfigurable rooms exist because you own the engine |

## Build shape (data-driven, same bones as everything else)

- **Build once:** the stage engine (reconfiguring tile grid + rotation + the tree-runner)
  and the portal / run-graph system.
- **Then content = data:** room types, templates, set-pieces, node types, path-control
  rules — all tables/JSON.
- One engine, an infinite tree of content. Capability was never the blocker; this is the
  connective tissue that turns the arsenal into a run.

## Open questions

- Tile grid size `y` per room; how many presets (6 is the working number); rotation model
  (snap 90° vs. free-turn).
- Path-control legibility: hidden, surfaced, or mixed?
- Node-type mix per run (combat / shop / bonus / joke ratios) — a pacing call.
- Is the run graph hand-authored, generated from the tree, or hybrid?
- How does room rotation reconcile the derived body anchors + gravity (anchors assume a
  "down"; the room turning changes it) — ties to [12](12_hardpoint-map.md) / the gravity system.
