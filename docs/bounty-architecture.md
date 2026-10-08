# Gcity — Bounty System: Architecture

Status: **proposed** — this is an architecture document, not a signed spec. Nothing in it
is buildable until it is broken into milestone specs under `docs/specs/` and the ADR
candidates in §12 are decided. It exists so the bounty loop lands on the systems the
design doc already commits to, instead of growing sideways.

Reads with: `docs/gcity-design.md` §5.2 (route-graph-first), §5.3 (bind, don't
generate), §7.3–7.5 (standing, signals, threat director), §14 (enemy AI);
`sim/quests/README.md`; ADR-004 (sensor-gated detection), ADR-008 (arcade AI).
Depends on open decisions: ADR-007 (death cost), ADR-010 (hub interiors), plus the two
new ADR candidates in §12. **None of those are resolved here.**

---

## 1. Concept

Bounties are short stories, not fetch quests — Cowboy Bebop structure: episodic
contracts with wildly different tones, targets that are rarely what the dossier says,
payouts that sometimes fall through, and a few targets who escape and become recurring
fugitives the player re-acquires through a cooling trail. Mechanically that means:
composed (archetype × twist × tone) contract generation, per-target behaviour traits
that govern fight-or-flight, an escape path over the route graph, a persistent fugitive
ledger, and a trail system whose beats decay on sim ticks.

---

## 2. Module layout

```
sim/quests/                      existing module — the bounty loop is quest machinery
  quest_system.gd                existing: records, objectives, rewards (M5) — unchanged
  bounty_director.gd             BountyDirector: composes + offers contracts
  bounty_system.gd               BountySystem: contract lifecycle, capture/kill, turn-in
  fugitive_system.gd             FugitiveSystem: escaped-target ledger, off-screen relocation
  trail_system.gd                TrailSystem: trail beats, heat decay, re-acquisition

content/
  bounty_archetype/<id>.json     who the target is (embezzler, gang lieutenant, synth…)
  bounty_twist/<id>.json         what the dossier got wrong (trap, innocent, double-offer…)
  bounty_tone/<id>.json          tragic / comic / noir / action — pacing + dialogue table refs
  bounty_trait/<id>.json         fight-or-flight behaviour (rabbit, burrower, loyalist, stander)
  broker/<id>.json               who issues contracts, where, payout rules, stiff-chance
  trail_beat/<id>.json           beat templates (witness, ditched vehicle, credstick, rumor)

client/                          device app "Contracts" (ledger UI), dossier presentation,
                                 broker dialogue — reads sim state, submits commands only
```

Rules this layout obeys (CLAUDE.md §5, §6):

- Everything authoritative is in `sim/`; the device's Contracts app is a **client of
  quest/bounty state**, never a store (design doc §12.1).
- Every new target archetype, twist, tone, trait, broker or beat is a **content file**,
  never a `match` arm. Adding a twist must require zero `sim/` diff (invariant 3).
- Each of the four new systems is a `SimSystem` registered in `sim/assembly.gd` in
  fixed order, snapshot-hashable, ticked deterministically.
- One system per implementation session; this document maps to **at least four
  sessions** plus content and client work (§11).

---

## 3. Simulation systems

### 3.1 BountyDirector (`&"bounty_director"`)

Composes and offers contracts. Analogous to the quest director already planned for
M6/M7 — it may *be* that director's first concrete client.

- Holds the **offer pool** per broker: a bounded list of composed contracts
  (archetype + twist + tone + trait + payout + site request).
- Composition is a pure function of `sim.rng()` + content + composition constraints
  (§4.4). No wall clock, no global RNG (invariant 6).
- Enforces **tone rotation**: never deals the same tone twice consecutively from the
  same broker (per-broker last-tone in snapshot state).
- Requests a **site binding** from the world/quests site machinery when a contract is
  accepted (design doc §5.3: contracts reference site handles, never coordinates).
- Owns nothing after acceptance — hands the contract record to BountySystem.

### 3.2 BountySystem (`&"bounty"`)

The contract lifecycle state machine (§5). Owns active contracts: objective wiring onto
the EventBus (same credited-event pattern QuestSystem uses), alive-vs-dead capture
state, escort/haul state, turn-in validation, payout (including the stiff path), and
emitting the events every other system consumes.

- **Does not** spawn or drive the target's combat AI — that is `sim/agents/`
  (perception, stance, squad, stress systems already exist). BountySystem *tags* the
  target actor and its muscle squad with the contract id; agents behave per their
  profiles.
- **Does not** decide escapes — it *reacts* to `&"bounty.target_escaped"` from the
  trait logic (§3.5) by converting the contract to an open contract and handing the
  target to FugitiveSystem.

### 3.3 FugitiveSystem (`&"fugitives"`)

The ledger of escaped targets. One record per fugitive: identity, trait, escape count,
current bounty value (escalates per escape, §6.3), muscle tier, and an **abstract
location** — a route-graph node id, not coordinates, consistent with route-graph-first
generation (design doc §5.2) and bind-don't-generate (§5.3).

- Off-screen fugitives move as **graph-walk simulation on ticks**: a fugitive advances
  along route-graph edges on a cadence derived from its trait, settling at candidate
  nodes (settlement/town sites). This is deliberately the same shape as the convoy
  back-end pathing so it inherits that machinery rather than duplicating it.
- Fidelity of off-screen simulation is **gated on ADR-010** (hub interiors). Until that
  is signed, this document assumes the cheapest model: abstract node position + timers,
  no agent instantiated until the player closes to hydration range (design doc §6.2).
- Re-acquisition: when a trail is followed to completion (§3.4) or a cold fugitive
  resurfaces (§6.4), FugitiveSystem asks the director to re-issue the contract with
  escalated terms and the fugitive's remembered history flags (dialogue hooks:
  "you're the one from the refinery").

### 3.4 TrailSystem (`&"trails"`)

Trail beats and heat decay for open contracts.

- On escape, TrailSystem materialises **2–4 beats** (count by trait + escape route
  length) from `content/trail_beat/` templates, each bound to a site handle along or
  near the fugitive's actual escape walk — beats are *true*, derived from the same
  deterministic walk, so a player who reads them correctly is genuinely tracking.
- Each beat and the trail as a whole carries **heat**, an integer tick budget:
  `hot → warm → cold` thresholds defined in the trait/beat content, decremented in
  `tick()`. Hot allows direct pursuit (fugitive still in flight on the graph); warm
  requires following beats; cold removes the trail but **not** the fugitive — the
  ledger entry persists and resurfacing (§6.4) takes over.
- Discovering a beat (interacting at the site, buying a broker rumor) emits
  `&"trail.beat_found"` and refreshes trail heat by the beat's content-defined amount.

### 3.5 Behaviour traits

Traits are **content**, evaluated by a small decision hook in the agent layer (a
`bounty_trait` reference on the target's `agent_profile`), not a new AI:

| Trait id | Trigger condition (event-driven, sensor-gated per ADR-004) | Response |
|---|---|---|
| `rabbit` | first hostile perception event involving its squad, or any alarm signal | immediate flight along a **pre-planned escape route** (graph path computed and stored at contract spawn) |
| `burrower` | same triggers | breaks line of sight, moves to nearest `hide` site feature, holds |
| `loyalist` | squad casualty or alarm | squad switches to delaying stances; target flees only when squad ≤ threshold |
| `stander` | never flees | escalating combat profile; boss-fight stress/morale tuning |

- Triggers consume the **existing** perception/signal events (design doc §7.4, §14.1)
  — no new sensing. The pre-planned escape route is computed once, deterministically,
  at contract-site spawn, so "cut the escape route first" is a real tactic: destroying
  or blocking route edges before the trigger forces a re-plan the player can exploit.
- The dossier **telegraphs** the trait (content field `dossier_hint`), so escapes read
  as earned, not scripted theft.

---

## 4. Content schemas

All ids `[a-z0-9_]+`, file name equals id, schema registered in
`tools/content_schemas/`. Versioned with migrations like every other kind. Illustrative
shapes (field lists are the spec-stage deliverable, these fix intent):

### 4.1 Archetype — `content/bounty_archetype/corpo_embezzler.json`

```json
{
  "schema": 1,
  "id": "corpo_embezzler",
  "display": "Corporate embezzler",
  "agent_profile": "operator_medium",
  "muscle": {"faction_tag": "corp_security", "tiers": ["light_recon", "medium_operator"]},
  "site_tags": ["office", "safehouse"],
  "base_payout": {"min": 800, "max": 1400},
  "trait_weights": {"rabbit": 5, "burrower": 2, "loyalist": 2, "stander": 1},
  "compatible_twists": ["any"],
  "dialogue_table": "archetype_embezzler"
}
```

### 4.2 Twist — `content/bounty_twist/client_is_the_criminal.json`

```json
{
  "schema": 1,
  "id": "client_is_the_criminal",
  "display": "The client is the real criminal",
  "reveal": {"stage": "confrontation", "channel": "dialogue"},
  "alt_resolution": {"command": "bounty.turn_on_client", "payout_mult": 0.0,
                     "standing": {"notoriety": 2, "heat": 0}},
  "stiff_chance_mult": 1.0,
  "weight": 2,
  "excludes_archetypes": ["rogue_drone_swarm"]
}
```

### 4.3 Trait — `content/bounty_trait/rabbit.json`

```json
{
  "schema": 1,
  "id": "rabbit",
  "display": "Rabbit",
  "dossier_hint": "Known to abandon associates at the first sign of trouble.",
  "flee_triggers": ["perception.hostile_contact", "signal.alarm"],
  "squad_casualty_threshold": 0,
  "escape": {"preplanned_route": true, "graph_speed": 3},
  "trail": {"beats_min": 3, "beats_max": 4,
            "hot_ticks": 36000, "warm_ticks": 432000}
}
```

(Tick budgets illustrative; real numbers are a spec/tuning concern at `SimRoot.TICK_HZ`.)

### 4.4 Composition constraints

Compatibility lives **in the content** (`compatible_twists`, `excludes_archetypes`,
tone weights per archetype), so the director's composer stays generic: filter → weight
→ `sim.rng()` pick. Authored flagship contracts (§7) are complete `bounty` content
records that bypass composition and pin every slot.

---

## 5. Contract lifecycle

```
                 compose (director)                     accept (command)
  content decks ────────────────▶ OFFERED ──────────────────────▶ ACTIVE
                                     │ expire (ticks)                │
                                     ▼                               │ target downed
                                  WITHDRAWN                          ▼
                                                    ┌──────── CAPTURE (alive) / KILL
          trait trigger fires                       │                │ haul/escort to broker
  ACTIVE ───────────────────────▶ TARGET_FLEEING ───┤                ▼
                                     │ escape walk  │             TURN_IN ──▶ PAID
                                     │ completes    │                │ stiff roll (broker content)
                                     ▼              │                ▼
                                  ESCAPED ──────────┘             STIFFED (story consequence,
                                     │                             standing delta, no payout)
                                     ▼
                              OPEN_CONTRACT (fugitive ledger + trail)
                                     │ trail followed / resurfaces
                                     ▼
                              re-offered ACTIVE (escalated)
```

Rules:

- **Alive pays 3×, dead pays base** (multiplier is broker content, not code). Alive
  requires non-lethal downing and a haul/escort leg that reuses existing
  movement/escort machinery; the struggling-target escape roll during haul is trait
  content.
- **Stiffing is rare, content-defined, and never silent**: a stiffed contract always
  produces a story consequence (twist follow-up, standing delta, or a lead on the
  client) so the player loses money but gains narrative — the Bebop rule.
- Killing a target **inside city limits** emits the same signal/heat events as any
  civilian-visible violence (design doc §7.3–7.4); the bounty system adds no bespoke
  wanted logic. Outlands sites carry no heat jurisdiction.
- Payouts enter the normal economy (land purchases are the intended sink).

## 6. Fugitive lifecycle

### 6.1 Escape walk

On `TARGET_FLEEING → ESCAPED`, the agent de-hydrates into a FugitiveSystem record at
its current graph node. The pre-planned route (or re-plan, if the player severed it)
continues as the abstract graph walk. Pursuit during **hot** heat intercepts the walk
at a node — hydrating the target back into an agent at that site.

### 6.2 Settling

The walk terminates at a candidate settlement node (filtered by archetype `site_tags`
and faction territory). The fugitive **exists there**: if the player visits for any
reason, the fugitive hydrates per normal site hydration — recognisable, armed, and
with its history flags.

### 6.3 Escalation

Per escape: bounty value multiplier, muscle tier bump (next tier from the archetype's
list — the A1 roster: light_recon → medium_operator → heavy_assault → drone_hunter as
faction-appropriate), and a `remembers_player` flag feeding dialogue tables.

### 6.4 Resurfacing

A cold fugitive re-enters the offer pool after a content-defined tick delay, optionally
re-skinned (`new_identity` content hook: same record, new display name, dossier notes
the alias) or promoted (joined/ranked up in a faction, changing its muscle faction tag).

## 7. Authored and composed contracts

- A small set of **flagship contracts** are fully authored content records (fixed
  archetype/twist/tone/trait, authored dialogue, scripted guaranteed-escape beats for
  long-arc nemeses). They slot into the hand-authored M6 world ("Cold Storage") and are
  indistinguishable at the ledger/UI level from composed ones.
- Guaranteed escape is expressed as a trait variant (`escape.guaranteed: true` stages),
  **only** valid on authored records — the schema validator rejects it on composed
  pools so procgen targets can never cheat. Whether guaranteed escapes are acceptable
  at all is ADR candidate B (§12).

## 8. Commands and events

Commands (registered in `CommandRegistry`, client submits, sim validates):

```
&"bounty.accept"          actor, contract id (from an offered pool entry)
&"bounty.abandon"         actor, contract id (pause-safe, converts to WITHDRAWN)
&"bounty.turn_in"         actor, contract id, at broker site
&"bounty.turn_on_client"  actor, contract id (twist alt-resolution, validated by twist content)
&"trail.read_beat"        actor, beat id (at the beat's site)
&"trail.buy_rumor"        actor, broker id, fugitive id (credits cost, reveals a beat)
```

Events (EventBus; progression/threat/dialogue subscribe — the bounty systems never
reach into those modules):

```
&"bounty.offered"   &"bounty.accepted"   &"bounty.target_downed"
&"bounty.target_escaped"   &"bounty.completed"   &"bounty.stiffed"
&"trail.beat_found"   &"trail.went_cold"   &"fugitive.resurfaced"
```

`&"bounty.completed"` carries the same credited-actor payload shape as
`&"quest.completed"` so existing quest-objective wiring ("complete 3 bounties") works
with zero new code.

## 9. Determinism, snapshots and performance

- All composition, trait rolls, stiff rolls, walk cadence and beat placement draw from
  `sim.rng()`; twist reveals and resurfacing are tick-scheduled. Same seed + input log
  ⇒ same contracts, same escapes, same trails (invariant 6). Dictionary iterations in
  the composer sort keys before weighting.
- Snapshots: each system returns primitive-only dictionaries (invariant 7) — offer
  pools, contract records, fugitive ledger (node ids as ints/StringNames-as-strings),
  trail beats with remaining-tick integers.
- Director composition and fugitive graph walks are **time-sliced**: the director
  refreshes at most one broker pool per tick budget window; fugitive walks advance on a
  coarse cadence (every N ticks), never per-tick pathfinding. Both fit the existing
  interruptible-work rule (CLAUDE.md §8); budget allocation is a spec-stage number
  against the 25 ms Deck frame.
- Content validation at `attach()` (like QuestSystem), fuzz targets for every new
  schema parser, corpora committed.

## 10. Verification

- **Replay fixtures**: (a) accept → kill → turn-in → paid; (b) accept → rabbit flees →
  escaped → trail beats found → re-acquire → capture alive; hashes asserted, shipped
  with the implementing milestone.
- **Property tests** (≥10k cases): composer output always satisfies content
  compatibility constraints; tone never repeats consecutively per broker; trail beats
  always lie on/adjacent to the actual escape walk; heat decay is monotonic;
  `load(save(x)) == x` for all new record types.
- **Metamorphic relations** (no oracle for escapes): severing an edge on the
  pre-planned escape route must not *decrease* interception probability; raising trail
  heat must not reduce the number of discoverable beats; increasing a fugitive's
  escape count must not decrease its bounty value.
- Mutation score counts toward the ≥70% `sim/` target.

## 11. Milestone mapping

| Piece | Earliest home | Why |
|---|---|---|
| Content schemas + composer (BountyDirector, offline/offered only) | M6 | pure data + rng; testable headless against the Cold Storage world |
| BountySystem lifecycle, traits wired to existing perception/stress, flagship authored contracts | M6 | needs the hand-authored world and the M4 AI, nothing procedural |
| Escape walks, FugitiveSystem, TrailSystem | M7 | entirely dependent on the route graph + site binding |
| Heat/notoriety consequences of city kills, broker standing | M8 | threat director territory; bounty systems only emit events until then |

Each row is its own spec in `docs/specs/` with its own gate evidence. Nothing here
spans modules in one session: director, lifecycle, fugitives and trails are separate
passes.

## 12. Open decisions (ADR candidates)

- **ADR-A: Fugitive off-screen fidelity.** Abstract graph-walk (assumed here) vs
  partially simulated agents. Interacts directly with open ADR-010; should likely be
  decided with or after it. Blocks FugitiveSystem implementation detail, not its
  interface.
- **ADR-B: Guaranteed escapes on authored contracts.** Scripted first-encounter escapes
  for long-arc nemeses vs trait-only escapes everywhere (pure systemic). Affects
  flagship content authoring and player trust; blocks flagship contract content, not
  the systems.
- Touches **ADR-007** (death cost): dying while hauling a live capture — does the
  capture escape, and does the contract survive death? The answer falls out of
  ADR-007's model and should be recorded there or in a follow-up.

## 13. Out of scope

Dialogue presentation, broker voice/portraits, co-op contract sharing, bounty boards as
physical world objects (vs device app only), faction-issued counter-bounties *on the
player*. Each is a future spec; the event surface in §8 is sufficient for all of them.
