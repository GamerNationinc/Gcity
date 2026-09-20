# Gcity — Architecture & Design

Working design document for a cyberpunk survival-immersive-sim built for the Steam Deck.
This is the reference doc for implementation work in Claude Code. It records decisions made,
decisions still open, and the reasoning behind both.

Status: pre-production. No code written yet.

---

## 1. Concept

A third-person survival game (first-person toggle) set in a near-future city and the
procedurally generated badlands beyond it. The player starts with a small city plot and a
20ft container, takes contract work in and out of the city, builds out a base, and
progressively expands outward into land nobody owns.

Valheim's build-survive-expand loop, wearing a Deus Ex / Cyberpunk skin, with Tarkov-grade
combat lethality.

### 1.1 Pillars

1. **Ownership is the world's core rule.** Everywhere you stand belongs to someone, or to
   no one. What you may build, dig, carry and shoot is decided by that one fact.
2. **The city is authored, the wilds are yours.** Handcrafted districts with a stable,
   repeatable questline; a procgen world beyond the walls that differs per player.
3. **Legibility over difficulty.** Combat and AI are lethal, but every loss must be
   readable as a mistake the player made.
4. **Data over code.** Weapons, perks, modules, districts and quests are content files.
   Systems are few and generic.

### 1.2 Reference lineage

Explicit record of what is being borrowed from where, so intent doesn't drift during
implementation.

| Source | What we take |
|---|---|
| **Valheim** | Core loop: gather, build, fortify, push into more dangerous territory. Base raids. Structural building with support rules. |
| **Cyberpunk 2077** | City/Badlands split. District class stratification. Fixers as quest brokers. Wanted-level escalation. Cyberware-as-stat-modifier. |
| **Deus Ex (HR/MD)** | Immersive-sim level design: multiple routes through authored space, vents/hacks/social as real alternatives to combat. Full-body first person. |
| **Rust** | Raid economics. Doors and windows as the only cheap entry points; every wall is a breachable but expensive one. Base defence as cost calculus. |
| **Skyrim** | Use-based skill progression. Perk trees as the spend mechanism. *Rejected:* level-scaled world difficulty. |
| **Fallout (Pip-Boy)** | The single diegetic device as the whole UI layer — inventory, quests, map, skills. |
| **Escape from Tarkov** | Ballistics, armour penetration, per-limb health, magazines as physical containers, loot-on-death stakes. |
| **Ready or Not** | Enemy AI that reads: perception delay, peeking and angle-holding, stress/morale, surrender, suppression that changes behaviour. |

---

## 2. Target platform

**Steam Deck is the primary and design target**, not a port.

| Constraint | Value | Consequence |
|---|---|---|
| Display | 1280×800, 7" | UI text must be readable handheld. No small-text-on-a-prop. |
| GPU | RDNA2, 8 CU | Render budget is tight but not the bottleneck. |
| CPU | Zen2 4c/8t | **This is the bottleneck.** Chunk meshing, pathfinding, AI. |
| Memory | 16 GB shared with VRAM | Streaming budget is real. |
| Power | 15 W shared TDP | CPU and GPU compete. |

**Frame target: locked 40 fps**, not 60. Every subsystem must be time-sliceable and
interruptible. Design for job threads from day one; do not treat threading as a later
optimisation pass.

---

## 3. Engine and language

**Godot 4.x.**

Rationale:
- Native Linux/Vulkan — the Deck is a first-class target, not a Proton gamble.
- Scenes and resources are text — readable and diffable by Claude Code.
- Runs headless for automated testing.
- Small enough to understand end to end.

Rejected: Unity (binary scenes fight AI-assisted development), Unreal (Deck performance
ceiling, heavyweight for a small team).

**Language split:**
- GDScript for gameplay glue, UI, content-driven systems.
- C# or a GDExtension (Rust/C++) for hot paths only: chunk meshing, flood fill, pathfinding,
  ballistics. Do not pre-emptively write these in the fast language; profile first.

> **Open decision D-01:** whether any existing codebase is being carried forward. Current
> assumption is a clean start.

---

## 4. Foundational architecture

### 4.1 Simulation / presentation split — non-negotiable

Multiplayer scope is **solo now, co-op later**. Retrofitting multiplayer into a solo
codebase is the single most expensive refactor in this genre, so:

- All authoritative state lives in a **sim** module: world deltas, inventories, entity
  transforms, ownership, quest state, heat.
- The sim module never touches rendering, input, or UI.
- In solo, a local host and a local client run in the same process.
- Adding co-op later means putting a socket between them, not rewriting systems.

Cost now: roughly 10% more plumbing. Cost of skipping it: a rewrite.

> **Open decision D-02:** tick-based deterministic sim, or variable-step. Deterministic is
> easier to test headless and to sync later; it constrains physics use.

### 4.2 Module layout

```
sim/            authoritative state, no rendering
  world/        chunks, terrain, generation
  nav/          route graph, portal graph, macro pathing
  land/         parcels, rights, ownership
  agents/       AI, perception, utility scoring, squads
  progression/  skills, perks, stat resolver
  items/        templates, instances, weapons, modules
  quests/       director, site binding, objectives
  threat/       heat, notoriety, suspicion, raid scheduling
client/         rendering, input, camera, audio
  device/       the personal computer shell + apps
  hud/
content/        data files — weapons, perks, modules, districts, town templates
tools/          editors, validators, telemetry dumps
```

Rule: a system in `sim/` may not import from `client/`. Enforce it with a CI check early;
it's the only thing keeping 4.1 true.

---

## 5. World structure

### 5.1 Authored hubs + procedural wilds

Two region types behind one interface:

- `AuthoredRegion` — static scene, baked navmesh, baked lighting, hand-placed props.
  The city and major facilities.
- `WildRegion` — seeded, streamed in chunks, deformable, runtime navigation.

Player controller, inventory, AI, quests and saving talk to `Region` only, never to either
implementation. The transition between them is a designed seam with in-fiction
justification — a gate, an airlock, a transit car — which also gives a load window.

### 5.2 Route-graph-first generation

**The single most important generation decision.** Do not generate terrain and then find
paths across it. Generate the route graph first and treat it as authoritative.

```
World seed
   └─> Route graph          nodes: city gates, settlements, POIs, junctions
        │                   edges: corridors with guaranteed traversable width
        ├─> Terrain generator    carves, bridges and tunnels around every edge
        └─> Site slots           tagged candidate locations
             └─> Quest director  binds a slot when a quest is accepted
```

Terrain is a *consumer* of the graph. Where an edge crosses a ravine the generator emits a
bridge; where it hits rock, a pass or tunnel. Connectivity becomes true by construction
rather than something to verify.

This is what guarantees AI can always traverse between locations, which was the original
requirement.

### 5.3 Quest-driven location generation — bind, don't generate

World generation emits **site slots**: candidate locations tagged by terrain suitability
(flat enough, near an edge, biome, `industrial` / `agricultural` / `ruin` / `corp`).

When a quest is accepted, the quest director queries for a slot matching constraints
(`8–15 km from city`, `tag=refinery`, `undiscovered`), picks one deterministically from the
seed, and writes the binding into the save overlay. From that moment the site is permanent
for that player, appears on the map, and gains a route graph node with edges stitched in.

Consequence: **quests reference site handles, never coordinates.** The city questline stays
fully authored and repeatable even though the geography it points into varies per player.

### 5.4 Procedural settlements

Prefab kit + placement grammar, not noise-generated buildings.

Each town template ships:
- its own road sockets, so it snaps onto the route graph as a subgraph;
- its own prebaked navmesh, so AI inside works immediately with no runtime baking;
- a district record (see §7.2).

Seeded variation controls block selection, rotation, density and faction ownership.

### 5.5 Terrain representation

> **Open decision D-03 — blocking.** Heightmap-with-carving (cheap, Valheim's approach, no
> caves or overhangs) vs true volumetric voxels with surface nets (caves, tunnels,
> underground bases, roughly 5–10× the CPU and memory cost).
>
> This decides meshing, navigation, collider generation and save format. The vertical
> parcel rules in §6.2 and the "tunnel under the wall" play assume volumetric. **Decide
> before any world code is written.**

### 5.6 Save format

`save = world seed + overlay`

Overlay holds: bound sites, discovered nodes, player terrain edits (chunk deltas), parcel
ownership, structure data, faction and quest state, heat values. Kilobytes to low megabytes,
never a full world snapshot.

---

## 6. Navigation

### 6.1 Two tiers

| Tier | Data | Used by | Cost |
|---|---|---|---|
| **Macro** | Route graph (§5.2) | Convoys, couriers, patrols, fast travel, quest distance, response ETAs | Near zero; works with the world unloaded |
| **Micro** | Navmesh / steering inside loaded chunks | Anything the player can see | Only near the player |

### 6.2 Hydration

An off-screen agent is a token: `{edge_id, progress, faction, payload}`. When the player
comes within range, the token hydrates into real entities at the world position its progress
maps to; it dehydrates back to a token when the player leaves.

**AI cannot get stuck in the wilds because off-screen AI never touches the wilds.**

### 6.3 Portal graph (player-built structures)

Player structures are never navmeshed. Instead:

- A flood fill runs whenever a build piece is placed or destroyed.
- Output: enclosed volumes as **nodes**, and every door, window or hatch as an **edge**.
- Recompute happens on build, not per frame — effectively free at runtime.
- Agents plan on the portal graph and do local steering only once inside a volume.

**Every wall is also an edge, just an expensive one.** Each edge carries a breach cost
derived from material HP, the tool required, and the noise it makes. A sealed bunker with no
doors isn't unraidable — it simply has a high minimum cost.

Raid planning = A* to the highest-value container, with breach cost as edge weight.

```
Outside ──[front door: 40]──> Entry bay ──[inner door: 120]──> Vault     total 160
Outside ──[wall section: 400]───────────────────────────────> Vault     total 400
```

Emergent consequence: players deliberately make the cheap path cheap and turn it into a
killbox. That's defensive design we don't have to author.

### 6.4 Player path traces

Record player movement as a sparse weighted digraph — quantised to 2–4 m cells, sampled at
1–2 Hz, a few bytes per cell, with visit counters on transitions.

The value is not the frequency counts. **A recorded transition is proof of traversability.**
In a game where players build the geometry, no static bake knows that a stacked crate is a
step onto the catwalk. The player demonstrating it is ground truth. This fills the gap
between the portal graph (room to room) and local steering (last few metres).

Correctness constraints:
- **Capability tags** on each transition — walk, vault, jump, climb, mantle. Filter by what
  the agent can actually do, or a heavy security mech walks off a catwalk the player
  grappled to.
- **Build-state version stamp** per edge, so traces invalidate when a wall goes up or a
  floor comes down. Stale traces through a vanished wall is the failure mode.

Two separate maps, and they must not be merged:

| Map | Content | Who may use it |
|---|---|---|
| **Traversal** | "This route is physically walkable" | Anyone. It's just better pathfinding, and it's fair. |
| **Habit** | "This is where *you* tend to go" | Only factions whose own sensors, tails, informants or cameras contributed observations. |

The habit map plugs directly into the suspicion system (§7.3). Raiders cannot know about a
tunnel they have never observed. Being followed home by a fixer's scout becomes a real
event with a real consequence.

Add noise on use — perfect retracing of the player's exact route reads as psychic. Sample a
high-traffic route, not the single most-travelled one.

Budget: cap cells per chunk, decay counters over time, drop the map for chunks far from
anything the player owns.

Side benefit: free telemetry. Heat-mapping where players actually walk shows which parts of
the authored city nobody ever sees. Wire this up before there's much content to test.

---

## 7. Ownership, law and threat

### 7.1 Land authority

One spatial query underlies the whole game:

```
LandAuthority.rights_at(position, actor) -> {build, dig, enter, carry, loot}
```

The build system, the drill, door locks and the weapon holster all ask this before acting.
Unowned wilderness is a parcel with a null owner and permissive rights, so there is **one
code path, not two**.

Parcels are polygons with a vertical extent, indexed spatially (quadtree/grid) — never
per-voxel ownership. In the authored city they are hand-placed at design time. In procgen
they attach to route graph nodes, so a generated settlement claims a radius automatically
the moment it spawns.

**Vertical extent matters.** A floor depth and ceiling height mean digging under a
neighbour is trespass. Tunnelling out under the city wall to bypass a checkpoint, or
breaching up into a corp basement from below, fall out of the same rule with no
special-casing.

Violating rights emits an event; it does not directly set a wanted level.

### 7.2 Districts

A district is a data record, not just art direction:

```
district {
  law_index          # police response speed AND raid frequency
  wealth_index       # median visible wealth
  response_time      # derived
  gang_control       # which faction, how strongly
  informant_density  # how fast signals propagate to observers
}
```

Authored for city districts, generated for badlands settlements. Police response time and
raid probability both derive from `law_index`, pulling in opposite directions:

- **Corporate district:** police arrive in seconds — and raid you constantly.
- **Starter ghetto:** slow response, high informant density; neighbours notice a rich
  resident immediately.
- **Badlands outskirts:** nobody comes when you scream, and nobody investigates your
  workshop either — but the local gang notices a wealthy stranger at once.

One number, the whole risk/reward geography.

### 7.3 Player standing — three scalars, not one wanted level

| Scalar | Raised by | Read by |
|---|---|---|
| **Heat** | Rights violations, witnessed crime, evidence | Police, corp security |
| **Notoriety** | Completed contracts, underworld reputation, fame | Gangs, fixers, raiders |
| **Visible wealth** | Gear, vehicles, base value, spending | Neighbours, criminals |

Neighbour informants read the *gap* between visible wealth and the district median — which
is exactly the "rich player still living in the starter ghetto" mechanic.

### 7.4 Signals and suspicion

Hidden dice rolls are the wrong answer to "they caught wind of it somehow". Instead,
illicit activity **emits signals**: power draw, emissions, delivery traffic, noise,
unusual purchases.

Signals propagate to observers in range — neighbours, cameras, patrols, drones — weighted by
`informant_density`, and accumulate as **suspicion held by that faction**, not by the world.

This gives counterplay, and the counterplay is module-shaped: scrubbers, off-grid generation
instead of metered power, soundproofing, a bribe to the local fixer, or running the lab
*under* the parcel rather than on it.

> **Open decision D-04:** sensor-gated detection (above) vs instant-star on violation.
> Sensor-gated is assumed throughout this doc because stealth needs it, but it requires a
> full perception system. Instant-star is trivial and reads as arbitrary.

### 7.5 Threat director

A single director ticks periodically, scores each faction's pressure against the player, and
schedules **at most one pending event**. Police, gangs, neighbours and corps are all
factions with different scoring weights over the scalars in §7.3.

**Raids are never instant.** Suspicion crossing a threshold opens an *investigation phase*
with visible tells — a patrol slows as it passes, a neighbour lingers, a drone overflies
twice — and schedules the raid hours later. That window is the gameplay: move stock, hide
the goods, fortify, bribe, or be elsewhere. Instant unavoidable loss teaches save-scumming.

---

## 8. Building and bases

### 8.1 Starter plot

The player begins with a ~40×40 ft city plot and one 20ft container. Cramped on purpose: it
teaches snapping, power budget and module dependency before the player has room to be
sloppy. The upgrade path is obvious — buy the adjacent parcel, or leave the city entirely
and claim land nobody owns.

### 8.2 Modules are data

The container is a chassis with sockets on a 2 ft interior grid. A module declares:

```
module {
  id, display_name
  footprint          # grid cells
  mass
  power_draw
  heat_output
  water_in / water_out
  depends_on         # other module ids
  emits              # signal types (ties into §7.4)
}
```

Starter catalogue: Work Station, Power, Sustainment, Work & Repair, Drone Automation
Station. Extending the catalogue is adding a file, never touching code.

A shared **power and thermal budget** is what makes a small container interesting to
optimise rather than merely decorate. It's also the hook for the economy: modules need parts
the city sells at a markup, or doesn't sell at all. That's the reason to go out into the
badlands.

### 8.3 Structural rules

Snap sockets on piece prefabs plus a structural-support propagation pass (Valheim's
stability rule), run on a dirty set rather than per frame.

### 8.4 No-build enforcement via ownership

There is no special "no-build volume" system. `rights_at()` already answers it. Terraforming
or building on land owned by the city-state or an NPC is a rights violation, which raises
heat through the normal path. You can build there *once you've purchased the parcel*.

---

## 9. Base security and raids

### 9.1 Sensors

Security modules are sensors on the portal graph. A camera, tripwire, motion plate or power
monitor watches an edge or a volume and emits an alert event to the player's device.

Power loss and intrusion are not special cases — they're alert types. **Cutting power should
be the raiders' opening move**, because that gives the player a warning phase before
anything is lost. That warning is the entire point of the system.

### 9.2 Base state machine

```
secure → alerted → under attack → looted → claimed
```

Each transition has a timer, and those timers are the design. The alert-to-attack window
must be long enough that a player out in the badlands can decide whether to run for it. The
macro route graph already knows travel time from player to base, so the device can show a
real ETA — including one the player can see they won't make.

### 9.3 Resolution — present vs absent

- **Player responds:** hydrate the raid into a live defensive fight.
- **Player absent:** resolve with the same numbers — defence score (turrets, door HP along
  the cheapest breach path, garrison) vs raid party strength.

One model, two presentations. The loss ladder is how far resolution got: valuables taken at
one threshold, ownership flipped at the next.

### 9.4 Takeover

Cheap, because ownership is already a parcel field. A faction claiming the base is one write
plus a flag turning it into a route graph POI. Reclaiming your own base becomes an assault
mission for free.

> **Open decision D-05:** does a claimed base keep the player's built structure, or get
> replaced with a faction template? Keeping it is far more satisfying and costs nothing at
> build time (pieces are already data), but the save must hold a full structure under
> another owner, and raid AI must path through a base designed to stop it.

---

## 10. Progression

### 10.1 Three systems, event-coupled

Gameplay systems emit progression events and know nothing about progression itself:

- The pistol emits `hit{weapon_class: handgun, range: 18}`.
- The build system emits `placed{piece_class: structural}`.
- A progression service subscribes, credits the right skill, and raises levels.

Adding a weapon type later means adding an event tag, not touching level code.

### 10.2 Stat resolver — build this first

**Never mutate base values.** A stat is a base plus an ordered stack of modifiers
contributed by perks, implants, weapon parts, ammo, buffs and status effects, resolved on
query and cached until invalidated.

```
StatResolver.get(entity, stat_id) -> value
```

Every number in the game reads through this one resolver. Perks, weapon mods, cyberware and
device upgrades then become the same mechanism wearing different hats. Retrofitting this is
brutal — it's where Cyberpunk 2077 itself shipped broken.

### 10.3 Perk trees are data

A node is `{id, prerequisites, cost, modifiers[]}`. Most perks are nothing but numbers in a
file. Keep a second, smaller category for perks needing real behaviour, implemented as event
hooks — and resist letting that category grow. Claude Code generates and validates large
trees of the first kind very well, and fifty bespoke perk classes very badly.

### 10.4 Difficulty: region-gated, not level-scaled

Skyrim-style level scaling makes the world feel flat and fights the procgen — everything is
equally dangerous everywhere. **Danger tier is a property of route graph distance from the
city.** Near the walls is starter difficulty; far edges are lethal. Expansion becomes a real
progression axis rather than a number that follows the player around.

---

## 11. Items and weapons

### 11.1 Composition, not class hierarchy

A weapon is a frame plus sockets: barrel, slide, optic, magazine, power cell, plus an ammo
type and a fire-mode component. **One ranged weapon implementation, driven by data**, covers
the entire eventual arsenal.

Handling derives from attached parts through the stat resolver: ergonomics, recoil, sway,
aim-in speed. A compensator and a heavier barrel trade recoil against handling
automatically. Tune part values, not a hundred hand-built weapon variants.

### 11.2 First weapon

A Glock 19 analog. Chosen precisely because it's boring: compact, semi-auto, mid-capacity,
no gimmick. The future layer is caseless ammo, a smart-link optic, and a trigger
software-locked to its owner — which also hands us an illegal-modification mechanic feeding
back into heat (§7.3).

### 11.3 Loot instances

Roll from `template + seed`. Save the template id, the seed and rolled affix ids; re-resolve
on load. Saves stay small, and a rebalance patch applies to items players already own
instead of stranding them.

---

## 12. The personal device

A Pip-Boy equivalent, as if designed by a future Apple. It is the entire UI layer:
inventory, skills, quests, map, comms, drone control, hacking.

### 12.1 Client, never a store

The device holds **no state of its own**. Inventory lives in the sim, skills in the
progression service, quests in the director. The device renders views and issues commands.
Letting the UI own authoritative state is what would make co-op impossible later.

### 12.2 Shell + apps

An app declares `{id, icon, hardware_requirement, view}`. The shell knows nothing about any
specific app. This makes the device an upgradeable item:

- Base unit: inventory, map, quests, comms.
- Drone control: requires a radio module.
- Hacking: requires a daemon coprocessor.

Because it's an equippable with modifier sockets, it feeds the same stat resolver — memory
capacity becomes concurrent daemons, antenna gain becomes drone range. Unlocking an app is
acquiring a real object, not ticking a checkbox.

### 12.3 Control authority (drones)

A general abstraction: the player controller can **bind to any controllable entity**, with
camera and input routing following the binding. The player's body stays in the world while
flying — which is exactly the vulnerability that makes drone use a decision.

Same mechanism later covers hijacked turrets and captured enemy drones, and it's the same
machinery as the first/third person camera states.

Drone app content: map with waypoints, telemetry strip, link margin, battery reserve,
return-to-home as a real behaviour with a real flight time. **Link budget is a real
mechanic** — fly past a ridge and lose the feed, so plan around terrain or place a relay.

### 12.4 Deck-specific constraints

- Raise the device to fill most of the viewport rather than holding it at arm's length.
  Fallout 4's handheld Pip-Boy is the anti-pattern at 7".
- Render the UI at its own resolution to a texture; redraw only on change. A
  full-resolution UI compositing every frame is a real cost on this APU, and this device
  will be open constantly.

> **Open decision D-06:** does time pause while the device is raised? Pausing makes it a
> safe menu in a diegetic costume. Not pausing makes it real risk (reloading through a menu
> while something walks toward you) and fits the immersive-sim half of the pitch — but
> forces every pane to be operable in ~2 seconds. Middle ground: pause only inside owned or
> safe parcels, which `rights_at()` can already answer.

---

## 13. Combat

### 13.1 One pipeline, two profiles

**Do not build two combat systems.** Arcade is the simulation with stages disabled and
coefficients flattened, selected by a combat profile asset.

```
fire event → ballistic solve → surface hit → armour lookup →
penetration resolve → post-armour damage → body part routing → effects
```

- **Sim profile:** all stages. Travelled projectile, penetration, per-limb routing, bleed
  and fracture.
- **Arcade profile:** hitscan, no penetration, single pooled health node, no status effects.

Because it's data, it can be applied selectively: arcade for the tutorial and scripted city
fights, full sim once the player is outside the walls.

### 13.2 Health as a graph

Separate pools per limb; fatal on head and thorax; blackout on limbs with knock-on effects
on aim sway and movement. Arcade collapses this to one node via a data-driven routing table,
not a code branch.

### 13.3 Magazines — decide before inventory is written

Tarkov-style: rounds are objects, magazines are ordered containers, the chambered round is
tracked separately, a tactical reload keeps the partial mag while an emergency reload drops
it.

This reaches deep into the inventory model, so it is a **blocking decision for the item
system**. The payoff lands on the device: loading mags is a real task with a real time cost
done at base, and being caught with everything empty is a genuine failure state.

### 13.4 Performance

Per-part hit resolution raycasts against skeleton-driven capsules **only on hit candidates**.
Distant or low-priority agents drop to a single capsule.

> **Open decision D-07:** what death costs in a persistent open world. Tarkov's full kit
> loss works because a raid is bounded. Here, full loss on every death gets punishing fast;
> no loss makes the lethality meaningless. Assumed answer: a corpse persisting at the
> location with your gear on it and a recovery run to get it back, softened inside city
> limits where the police-response fiction already provides a reason.

---

## 14. Enemy AI

The goal is Ready or Not's legibility: enemies that commit to a stance the player can read.
Lethal, but every death reads as a mistake rather than a dice roll.

### 14.1 Perception is a process, not a check

An agent accumulates awareness of a contact over time, driven by exposure, lighting, player
movement speed, stance and noise, with a **detection delay** before the first shot and a
memory that decays.

`time_to_first_shot` is the single biggest lever on whether combat feels fair. Instant fire
on line-of-sight is what makes lethal AI feel cheap.

### 14.2 Aim quality is separate from awareness

An alerted agent that hasn't settled shoots wide. Model it as an error cone converging on a
curve while the target stays visible, resetting on broken contact, plus a swing-through
penalty on a target that appears suddenly.

This produces **peeker's advantage for free**, which is what makes slicing a corner feel
like skill.

### 14.3 Stress and morale

Per-agent state. Under fire, seeing a squadmate drop, or getting flashed degrades aim,
prompts breaking for cover, and at a threshold triggers surrender or rout.

Suppression that only reduces accuracy is invisible to the player. Suppression that changes
*behaviour* is readable across the room.

### 14.4 Decision architecture

- **Utility scoring** for stance selection: hold, advance, flank, retreat, surrender.
- **Behaviour tree / state machine** only for executing the chosen stance.
- **Hysteresis** so a chosen stance persists a minimum duration.

Pure behaviour trees make an agent that can't change its mind. Pure utility makes one that
twitches.

### 14.5 Squad coordination

Runs on the **portal graph**, not shared omniscience. One agent breaching the front door
while another covers a window is a squad-level planner assigning different edges.

Contact reports propagate **by radio**, using the same signal machinery as §7.4 — so jamming
or killing the radio is a legitimate tactic.

### 14.6 Budget

Utility scoring at 2–5 Hz, time-sliced across agents. Hard cap on fully-simulated agents
near the player; everyone else runs on the macro token model (§6.2).

> **Open decision D-08:** do arcade-profile enemies use the same AI with different tuning,
> or a genuinely simpler agent? Same AI with a shorter detection delay and wider error cone
> is usually sufficient and saves a second implementation.

---

## 15. First mission — vertical slice

**"Cold Storage"** — the first contract. Sneak into a building, hack a terminal, exfiltrate
the data, sell it to a fixer. A full stealth run pays a bonus.

This is the correct first mission because it exercises nearly every system above in one loop
without needing a single finished weapon balance pass.

### 15.1 Systems exercised

| Beat | Systems proven |
|---|---|
| Accept contract from fixer | Quest director, site binding (§5.3), dialogue, device quest app |
| Travel to site | Route graph, region transition, macro nav, danger tier |
| Approach and case the building | Land authority (trespass), district data, perception AI |
| Entry | Portal graph, doors/windows as edges, breach vs bypass |
| Hack terminal | Device hacking app, hardware requirement gating, signal emission |
| Exfil | Alert state machine, squad coordination, path traces |
| Sell to fixer | Economy, notoriety, item instance transfer |
| Stealth bonus | Stealth scoring (§15.4) |

### 15.2 Structure

Three routes in, Deus Ex style, all authored, all legitimate:

1. **Front** — social or credential bypass. A stolen or forged access token gets you past
   the door check. Fails loudly if your heat is already high.
2. **Side** — a maintenance window on the second floor. Requires reaching it (climb, crate
   stack, or a drone-carried line) and is silent if the power monitor is spoofed first.
3. **Under** — a service tunnel. Requires a dig or a grate cut, and is the only route that
   bypasses the lobby camera entirely. Proves the vertical parcel rules (§6.1).

All three converge on a server room with the target terminal. The terminal hack takes real
time — a progress window during which the player is stationary and exposed, which is the
core tension of the mission and the argument for D-06 (no pause).

### 15.3 Opposition

Four to six guards on patrol routes, running the full §14 stack at low stress. One is a
static post in the lobby. Two patrol the upper floor. One roams.

They must demonstrate, in this mission:
- detection delay (the player can be briefly seen and still break contact);
- investigation behaviour (a guard walks to a noise, looks, returns to patrol);
- escalation by radio (one guard spotting you alerts others by transmission, not telepathy);
- morale (suppressed or isolated guards break rather than fight to the death).

### 15.4 Stealth scoring

Track four counters for the run:

```
times_detected        # awareness crossed the alert threshold
alarms_raised         # a guard successfully transmitted
bodies                # kills, lethal or otherwise
traces_left           # doors breached, cameras destroyed, terminals left logged-in
```

**Full stealth bonus requires all four at zero.** Not "nobody survived to tell" — genuinely
unobserved. Killing a guard is a body even if nobody saw it, which forces non-lethal or
avoidance rather than silent-takedown-everyone.

Partial credit is a fixer payout multiplier. Failure states are not mission failure — a loud
run still completes, pays less, and raises heat.

### 15.5 Payoff

The fixer pays in credits plus a module or weapon part. Selling the data raises **notoriety**
(§7.3), which is the player's first taste of the tradeoff: reputation opens contracts and
attracts raiders.

Design intent: the first time the player's base gets cased, it should be traceable back to
this mission.

---

## 16. Build order

Milestones ordered so each one proves an architectural claim rather than adding content.

**M0 — Skeleton**
Godot project, sim/client split with a CI check enforcing it, headless test harness,
deterministic tick loop (pending D-02). No gameplay.

**M1 — Stat resolver + one pistol**
The entire chain for one weapon and nothing else: template → instance → attachment
resolution → damage → skill event → one perk that measurably changes damage. If this round
trip is clean, every later weapon is a data file.

**M2 — Land authority + starter plot**
Parcels, rights query, the 40×40 plot, one container, three modules with a shared power
budget. Proves §7.1 and §8.2.

**M3 — Portal graph + build system**
Flood fill, enclosed volumes, doors and windows as edges, breach costs. Prove it with a
dumb agent A*-ing to a vault.

**M4 — Perception AI**
The full §14 stack on 4–6 agents in a hand-built test building. Tune
`time_to_first_shot` here, in isolation, before any level design depends on it.

**M5 — The device**
Shell plus inventory, map and quest apps. Proves §12.1.

**M6 — "Cold Storage"**
The §15 mission, in an authored building, with no procgen at all. This is the playable
vertical slice.

**M7 — Route graph + procgen wilds**
Only after the slice plays well. Generation, site binding, region transition, macro nav
hydration.

**M8 — Threat director + raids**
Signals, suspicion, investigation phase, base state machine, absent resolution.

Everything else — drone control, hacking depth, additional weapons, perk breadth, economy —
is content on top of finished systems.

---

## 17. Open decisions

| # | Decision | Blocks |
|---|---|---|
| D-01 | Clean start vs existing codebase | M0 |
| D-02 | Deterministic tick vs variable step | M0, co-op later |
| D-03 | **Heightmap carving vs volumetric voxels** | M7, all terrain code |
| D-04 | Sensor-gated detection vs instant wanted level | M4, M8 |
| D-05 | Claimed base keeps player structure vs faction template | M8 |
| D-06 | Does the device pause time? | M5, M6 |
| D-07 | Death cost / kit loss model | M6 |
| D-08 | Arcade enemies: same AI retuned, or simpler agent | M4 |
| D-09 | Magazines as ordered containers (assumed yes) | M1, item system |
| D-10 | Are hub interiors simulated when the player is elsewhere? | M7 |

D-03 and D-09 are the two that get more expensive every week they stay open.
