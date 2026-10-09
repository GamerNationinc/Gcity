# Gcity — Narrative Design: Main Quest Architecture

Status: **proposed** — this is a narrative architecture document, not a signed spec.
Nothing in it is buildable until it is broken into milestone specs under `docs/specs/`
and the ADR candidates in §13 are decided. It exists so the main story lands on the
systems the design doc already commits to — standing scalars, site binding, the quest
director, the bounty loop — instead of growing a parallel "story engine" beside them.

Reads with: `docs/gcity-design.md` §1.1 (pillars), §5.2–5.3 (route-graph-first; bind,
don't generate), §7.3–7.5 (standing, signals, threat director), §10 (progression),
§14 (enemy AI), §15 (Cold Storage); `docs/bounty-architecture.md` (brokers, trails,
fugitives); ADR-004 (sensor-gated detection, accepted), ADR-007 (death cost, accepted),
ADR-008 (arcade AI, accepted).
Depends on open decisions: ADR-010 (hub interiors), plus the ADR candidates in §13.
**None of those are resolved here.** Where this document needs a decision to keep its
internal logic coherent, it states a *working assumption*, clearly labelled, so the
assumption is visible and signable rather than implicit (standards §7 practice).

All names in this document — line titles, the antagonist, pillar names, stage names —
are **working titles**. They are placeholders so the structure can be discussed in
concrete terms; final naming is content work and CEOGG's call.

---

## 1. Concept

A brave new world: recognisably ours, drastically bent. The player is an **outsider to
the structured society** of the city — not born into its credentialed order, not
protected by it — who was crushed by someone inside it and climbs back. The climb is the
main story, and it can be made in two currencies:

- **Ruin** — complete destruction. Crew, firepower, raids, bodies. Crime.
- **Absorb** — corporate destruction. Capital, leverage, acquisition, manipulation of
  markets and people, superseding the rival by owning what they owned. *Legal* crime.

Both are legitimate from the first act, both demand escalating means (money, crew,
infrastructure), and the game never asks the player to pick one in a menu. The ending is
derived from what they actually did.

Around that revenge line sit two or three more main lines (§8), startable in any order
or simultaneously, each built from the same stage/avenue machinery. A playthrough is a
braid, not a corridor.

### 1.1 What this explicitly rejects

Recorded so intent doesn't drift during implementation (same discipline as design doc
§1.2). The anti-model is the Cyberpunk 2077 main quest:

| Rejected | Why | Replaced by |
|---|---|---|
| Dialogue wheels as the primary choice instrument | Choices made in menus feel weightless and read as arbitrary; the "choice" is often three phrasings of one outcome | **Outcomes over dialogue** (§6): choices are actions in the world, recorded as flags |
| A protagonist with a forced personality and pre-written attitude | Clashes with player intent on every replay; the player is cast rather than playing | Intent-based dialogue, minimal forced voice (§6.4, ADR candidate NARR-D) |
| Fixed quest order with hard act gates | Kills replay value; every run walks the same rail | Any-order, concurrent main lines (§3) |
| Narrow, locked branch points ("point of no return" walls) | Punishes exploration of the structure itself | Per-stage avenue choice, flag-derived endings, explicit and rare mutual exclusions (§6.3) |
| Branches that reconverge into identical scenes with one changed line | Replays feel repetitive and the branching reads as fake | Parallel avenues with **different rewards, different world-state consequences** (§5) |

### 1.2 Reference lineage additions

Extends the design doc §1.2 table for narrative and presentation:

| Source | What we take |
|---|---|
| **Metal Gear Solid (series)** | Per-enemy awareness indicators ("?"/"!" over the head), alert/evasion/caution phases as readable states. The tell, not the cutscene tonnage. |
| **Hitman (World of Assassination)** | A target as a *structure* to be studied and dismantled by any of several authored avenues; intel discovered in-world reshapes the plan. |
| **Deus Ex (HR/MD)** (already in lineage) | Extended from level design to quest design: every stage has multiple legitimate routes to its objective. |
| **Cowboy Bebop** (via `bounty-architecture.md`) | Episodic texture of the economy the main lines sit on top of. |
| *Rejected:* **Cyberpunk 2077 main quest** | Story kept at arm's length: we take its *city*, not its *rail* (see §1.1). |

---

## 2. Narrative pillars

Subordinate to the design doc's four pillars (§1.1); these govern story work
specifically.

1. **Outcomes over dialogue.** The game reads what the player *did* — who they killed,
   what they bought, which avenue they took — never what they clicked in a wheel.
   Dialogue frames consequences; it does not create them.
2. **Any order, always finishable.** Main lines start in any order or together, and no
   sequence of choices in one line may make another line uncompletable, except through
   a mutual exclusion that is declared in data and signed (§6.3). This is an invariant
   with a validator (§11), not a design hope.
3. **Avenues are parallel, not cosmetic.** Every stage offers at least two avenues with
   genuinely different system demands (stealth vs capital vs force vs social), different
   rewards, and different world-state consequences. Reconverging into an identical next
   scene is a bug.
4. **The story runs on the sim.** Narrative state is sim state: flags, standing scalars,
   faction records, site bindings. There is no cutscene-side truth. Co-op later means
   the story must already live where the authority lives.
5. **Legible stakes.** Per design pillar 3: when a stage closes an option, the player
   could have seen it coming. Foreshadow exclusions; never spring them.

---

## 3. Main line architecture

### 3.1 Lines, stages, avenues, outcomes

Four nested concepts, all data (`content/`, §10):

```
quest_line            a main story: 3–4 of these ship (NARR-C)
  └─ line_stage       a chapter: has an objective, an unlock condition, 2+ avenues
       └─ avenue      a legitimate route through the stage: requirements, missions,
       │              rewards, and the outcome flags it sets on completion
       └─ outcome     flags written to the player's flag ledger; consumed by later
                      stage conditions, dialogue, endings, and other lines
```

- A **line** is startable when its *intro trigger* fires (a broker introduction, a
  world event, a standing threshold). After that it advances only when the player
  pushes it. Lines never auto-advance on wall time.
- A **stage** is the unit of authorship and testing. It has exactly one *objective*
  (what must become true) and two or more *avenues* (ways of making it true).
- An **avenue** is a mission chain of one to three missions, built on the existing
  quest machinery (objectives credited over the EventBus, exactly as QuestSystem does
  now). Avenues carry **requirements** read from sim state — capital, notoriety, heat
  ceiling, crew count, a specific item, a discovered intel record — and the sim decides
  eligibility. The client requests, the sim decides (CLAUDE.md invariant 2).
- **Outcomes** are declared flags (`content/outcome_flag/`), not ad-hoc strings. A flag
  declares its id, description, and optionally an `exclusive_group` (§6.3).

### 3.2 Concurrency rules

- All intro-triggered lines may run simultaneously. There is no global act counter.
- Cross-line influence travels **only** through shared sim state: standing scalars
  (§7.3 of the design doc), faction records, outcome flags, site bindings. Line A may
  make line B *easier, harder, or different* — cheaper avenues unlocked, a broker's
  attitude shifted — but may hard-lock a stage of line B only via a declared exclusive
  flag pair (§6.3).
- Stage unlock conditions are pure predicates over the flag ledger + sim scalars:
  deterministic, hashable, replayable.

### 3.3 Spine model — working assumption (ADR candidate NARR-A)

Three candidate structures for how Ruin and Absorb relate inside a line:

- **A — Shared spine.** Every stage is shared; Ruin/Absorb are avenues within each
  stage. Cheapest to author; risk: avenues degrade into flavour.
- **B — Forked chains.** After an early act, Ruin and Absorb are separate stage chains.
  Strongest replay contrast; roughly doubles authored content per line and invites the
  reconvergence bug.
- **C — Hybrid: shared spine, forked finales.** Acts 1–3 are shared stages with
  Ruin/Absorb avenues per stage; the final act forks into distinct ending chains chosen
  by the accumulated flag mix (not by a menu). Cost between A and B; preserves contrast
  where it matters most (the ending the player earned).

**Working assumption for the rest of this document: C.** It is the structure assumed by
§4; it is signable, not signed.

---

## 4. Line One (dial-in target): the revenge line — working title **"UNDERTOW"**

The first line to be fully dialled in, per direction: one line at a time. §8's other
lines stay at concept level until this one is signed.

### 4.1 Premise

Before the game starts, the player had something: a small crew, a workshop, a name in
their district. The antagonist organisation — working title **the Meridian Group**, a
mid-tier corp with a licensed private-security arm and political cover in the city —
took it. Holdings seized under a legal pretext, crew scattered or dead, the player's
name blacklisted from licensed work. That blacklisting is *why* the player starts as an
outsider on a 40×40 plot with one container: the opening state of the game (design doc
§8.1) **is** the aftermath of the inciting incident. No flashback cinematic required;
the starter plot is the wound.

Meridian is a **faction record** (`content/faction/meridian.json`), not script. Its
standing toward the player, its district presence, and its security posture run through
the same district/threat machinery as every other faction (§7.2–7.5). The main story
antagonist is, mechanically, just the faction the story points the player at — which is
what lets Ruin and Absorb both work without special-casing.

### 4.2 The antagonist as a structure: five pillars

Meridian is authored as **five pillars**, each a record (`content/pillar/<id>.json`),
each independently removable, in any order, by either philosophy. Removing pillars
weakens the finale opposition and changes its staging. This is the replayability
engine: *pillar order × avenue choice × outcome flags*.

| Pillar (working names) | What it is | Ruin avenue (shape) | Absorb avenue (shape) |
|---|---|---|---|
| **The Arm** | Licensed security contractor force | Decapitate it: raid its depot, kill or capture its commander (full §14 AI engagement, high heat) | Outbid it: win its city contracts out from under it; requires capital + clean heat + a front business (base production modules as the front) |
| **The Ledger** | Finance arm; holds the debt and the seized assets | Burn it: destroy collateral records; physical intrusion, Cold-Storage-style stealth at scale | Buy it: acquire Meridian debt at distress prices via a broker; requires large capital + market-manipulation missions (emit false signals through §7.4 machinery — *legal crime*) |
| **The Cover** | A city-hall patron providing political protection | Expose or eliminate the patron (assassination or scandal-by-force; massive heat, district law_index shifts) | Replace the patron: become the district's larger taxpayer/landowner; land purchases through LandAuthority, visible-wealth threshold, bribery missions |
| **The Line** | Logistics: convoys between city and badlands sites | Interdict: ambush convoys on the route graph (uses convoy back-end pathing; overlaps bounty escort machinery) | Starve: take over the supplier settlements' contracts in the badlands (procgen settlement economy, M7-dependent) |
| **The Name** | The figurehead — the person who signed the order | Personal: hunt them when the other pillars fall and they run (hands directly to FugitiveSystem + TrailSystem from `bounty-architecture.md` — the final target is mechanically a fugitive with maximum escape traits) | Hollow them: force a buyout/absorption; they keep their life and lose everything; requires 3+ pillars absorbed |

Rules:

- Pillars are discoverable, not listed. Act 1 (§4.3) surfaces two; intel found in-world
  (hacked terminals, interrogations, broker purchases, trail beats — `content/intel/`)
  surfaces the rest, **from multiple independent sources**, so different playthroughs
  learn the structure in different orders. Intel also reveals *which avenue suits which
  build* — the "find out through multiple places which is the best avenue for your
  play" requirement is an intel-coverage requirement, enforced by the validator (§11):
  every avenue must be pointed at by ≥2 distinct intel sources.
- Each pillar's two avenues yield **different unique rewards** (§5.3): Ruin avenues pay
  in gear (a unique weapon, armour, a combat perk unlock); Absorb avenues pay in
  economy (an income stream, a unique base module, a crew specialist, a standing
  discount). Mixing philosophies across pillars is not merely allowed; it is the
  expected way most runs look.
- A pillar removed by Ruin raises **heat** and gang **notoriety**; removed by Absorb it
  raises **visible wealth** and corp-world notoriety. The existing three scalars (§7.3)
  are the story's memory — no new "karma meter".

### 4.3 Act structure (hybrid spine, working assumption NARR-A/C)

```
Act 0  THE WOUND        implicit: the starter plot, the blacklist, a cold open contract
Act 1  THE NAMEBOARD    find out who; surfaces Meridian + first two pillars   (2 stages)
Act 2  THE MEANS        open build-up: income, crew, base, first pillar       (2 stages)
Act 3  THE TEARDOWN     remaining pillars, any order, either philosophy       (3 stages)
Act 4  THE RECKONING    forked finales derived from the flag ledger           (1 stage, 4 variants)
```

- **Act 0** — ADR candidate **NARR-B**: whether M6's Cold Storage *is* the cold open
  (the exfiltrated data names Meridian) or stays a standalone fixer contract. Making it
  the cold open costs one extra data file and zero sim diff, and gives M6 a narrative
  payload for free; but it couples the vertical slice to a story decision. Not resolved
  here.
- **Act 1** is investigation: a stolen ledger fragment, a witness, a broker who knew the
  crew. Two stages, each with a stealth avenue, a social/purchase avenue, and a force
  avenue. Teaches the stage/avenue grammar on low stakes.
- **Act 2** is deliberately open and *thin on authored content*: its objective is a
  resource threshold ("be worth going to war with/against"), satisfiable through any of
  the game's income loops — bounties, contracts, base production, badlands salvage —
  plus one authored recruitment stage (first crew specialist, Ruin or Absorb flavoured).
  Act 2 is where the main line hands the player back to the sandbox on purpose.
- **Act 3** is the pillar teardown: three stages, but the *player* chooses which pillars
  and in which order; unchosen pillars remain and harden the finale. Minimum pillars to
  unlock Act 4: **two** (working number — tuning, not architecture).
- **Act 4** finale variants, derived (never menu-picked) from the ledger:

| Variant | Derivation (working thresholds) | Shape |
|---|---|---|
| **Scorched** | Ruin flags strictly dominate; The Name killed | Assault finale on the weakened remainder; the city remembers: permanent heat floor, Meridian districts destabilise |
| **Acquired** | Absorb flags strictly dominate; The Name hollowed | Boardroom finale; player *inherits* Meridian's remaining pillars as owned assets (LandAuthority transfers, income streams); permanent visible-wealth floor and corp attention |
| **Hollowing** | Mixed flags (the common case) | The player has broken what they couldn't buy and bought what they couldn't break; finale staging mixes both; inheritance is partial and contested — the richest variant, and deliberately the default-by-behaviour |
| **The Walk** | Optional: all pillars neutralised, The Name confronted and *released* | Quiet ending; large one-time standing effects; exists so mercy is a choice the system can read, not a dialogue line |

### 4.4 Resource gating — the escalation requirement

"Both paths require more means, finances and crew than the people above you" is
implemented as avenue requirements read from existing sim state, never bespoke
counters:

- **Capital** — credits (economy, M5+).
- **Crew** — recruited specialist records (`content/crew/<id>.json`, new content kind;
  crew members are agents with a roster record, hired via missions or payroll, usable
  as raid support or assigned to base modules as production staff — one record kind
  serving both philosophies).
- **Standing** — heat *ceilings* on Absorb avenues (a hot player can't do clean
  business), notoriety *floors* on Ruin avenues (nobody raids with a nobody), visible
  wealth floors on The Cover's absorb avenue.
- **Infrastructure** — specific base modules present and powered (a front business, a
  workshop tier, a comms module), read from the structure records (§8.2).
- **Intel** — a discovered `content/intel/` record naming the avenue.

A gated avenue is **shown with its requirement**, not hidden (legibility pillar):
the player can always see what the other road would have cost.

---

## 5. Avenues in depth

### 5.1 Minimum avenue contract

Every `content/avenue/<id>.json` declares:

```
avenue {
  id, stage_id
  philosophy        &"ruin" | &"absorb" | &"neutral"     (neutral: stealth/social routes)
  requirements[]    predicates over sim state (capital, crew, flags, items, standing)
  missions[]        1–3 mission refs (existing quest machinery; sites bound per §5.3)
  rewards[]         item grants, income streams, module unlocks, perk unlocks, crew offers
  sets_flags[]      outcome flags written on completion
  world_effects[]   standing deltas, faction state changes, district index changes
}
```

The validator (§11) rejects a stage whose avenues don't differ in at least two of:
philosophy, requirement class, reward class.

### 5.2 Avenue ≠ branch

Avenues are *parallel roads over the same ground*, Deus Ex style (design doc §15.2 is
the single-mission version; this is the quest-level version). The stage objective is
identical; the fiction, systems exercised, costs and rewards differ. A completed stage
reports *which* avenue in its flags, and later content may react — but the line's spine
does not fork until Act 4. This is what makes "multiple outcomes and multiple avenues on
the same path, parallel to each other" cheap enough to actually ship.

### 5.3 Avenue-gated uniques

Unique rewards bind to avenues, not stages: the Ruin route through The Arm yields a
weapon that exists nowhere else; the Absorb route yields a contract-income module that
exists nowhere else. Per run, the player can only earn one of each pair — the honest
cost of a choice, and the honest reason to replay. Uniques are ordinary content files
tagged `unique_source: <avenue_id>`; the validator confirms every unique has exactly
one source and every pillar avenue pair has non-overlapping reward classes.

---

## 6. Choice and consequence model

### 6.1 The flag ledger

One new sim concern: a **flag ledger** owned by a `LineSystem` (`&"lines"`, §9) —
an append-only set of declared `StringName` flags with the tick each was set. Snapshot
is a sorted array of `[flag, tick]` pairs (hashable, invariant 7). Everything narrative
reads this ledger; nothing narrative stores truth anywhere else (pillar 4, §2).

### 6.2 Outcomes over dialogue — the enforcement rule

A choice exists **only if** it is expressed as a sim command the player issued (an
attack, a purchase, an avenue acceptance, a release) that set a flag. Dialogue may
*offer* a command (accept avenue, release target) and must *reflect* flags; dialogue
alone never sets a flag that gates content. This is a lintable rule: dialogue content
files cannot reference `sets_flags`.

### 6.3 Mutual exclusion is declared, rare and foreshadowed

`outcome_flag` records may carry an `exclusive_group`: setting one flag in the group
permanently forecloses the others (e.g. `meridian.name_killed` vs
`meridian.name_hollowed`). Rules:

- Exclusions exist only inside a declared group — never emergent, never implicit.
- The validator proves every line remains completable under every exclusion combination
  (reachability over the flag graph, §11).
- UI rule: any command that would set an exclusive flag is marked in the client as
  irreversible before confirmation (legibility pillar; same presentation weight as a
  gate-signing action).

### 6.4 Protagonist voice — ADR candidate NARR-D

Working assumption: **intent-based dialogue** — the player picks terse intents
("press him" / "pay him" / "leave"), the protagonist's rendered line is minimal, no
imposed backstory monologues. Full silent protagonist and fully voiced are the other
options; cost and tone implications differ enormously (VO budget, localisation). Not
resolved here; nothing in this architecture depends on the answer.

---

## 7. Detection tells — player-facing awareness indicators

Direction: when an enemy sees the player, show it — a highlight or an indicator over
the head, Metal Gear style. This lands almost entirely in `client/`; the sim already
computes everything needed.

### 7.1 What the sim already provides

ADR-004 (accepted, sensor-gated) and design doc §14.1 give each agent a *perception
process*: per-target awareness that ramps with exposure, light, movement and distance,
with distinct thresholds for suspicion, investigation and alert, plus radio-mediated
escalation (§15.3). **No sim diff is required for tells.** The tell is a presentation
of existing per-agent awareness state.

### 7.2 Presentation spec (client)

Per visible hostile agent, a world-anchored indicator above the head:

| Sim state | Indicator | Behaviour |
|---|---|---|
| Unaware | none | — |
| Awareness ramping (sub-threshold) | **"?"** with a radial fill tracking the ramp | fill drains as the player breaks exposure — the drain *is* the stealth feedback loop |
| Investigation | solid "?", agent-coloured | agent is moving to the stimulus |
| Alert (threshold crossed) | **"!"** flash + audio sting, then persistent while engaged | one sting per agent per alert, never per frame |
| Radio escalation received | smaller "!" (second-hand) | distinguishes the spotter from the informed |
| Lost contact / search | "?" pulsing | matches §14 search behaviour |

Plus: an edge-of-screen chevron for off-screen agents whose awareness is ramping
(the player must be able to react to being seen from behind — legibility pillar), and
an optional target **highlight** (rim-light on the alerted agent) as a settings toggle.

Rules:

- Shapes before colours: "?" and "!" are distinguishable without colour vision; colour
  is reinforcement only. Sized for the Deck's 800p at arm's length (CLAUDE.md §10:
  handheld-first).
- Pure client: reads agent awareness via the existing sim-state read path; submits
  nothing; no new sim state (invariants 1–2). Thresholds for indicator stages come from
  a client-side data file (`content/ui_tells.json` or client config — content
  placement to be settled in the spec), not hardcoded.
- An **immersive mode** toggle hides all tells; stealth scoring (§15.4) is unaffected
  either way, because scoring reads sim counters, not UI.
- Budget: indicators are part of the client's existing frame allocation; cap of
  concurrently rendered tells (nearest N agents) rather than per-agent cost growth.

### 7.3 Scope note

This section is deliberately small because the system is deliberately small: it can
ship as a one-session client task against the M4 perception work, long before any
narrative milestone, and Cold Storage (M6) is strictly better to demo with it.

---

## 8. The other main lines — concept level only

Per direction, dialled in one at a time; these are one-paragraph stakes in the ground
so UNDERTOW's flags and systems are designed with neighbours in mind. Three sketched;
ship three or four (ADR candidate NARR-C).

- **Working title "CHARTER"** — the city-political line. The mayor's land regime
  (LandAuthority, districts, the instant-wanted rule on unowned city land) is not
  neutral physics; it is policy, and policy has authors. The player can entrench it,
  reform it, or corrupt it — expressed through land purchases, district index shifts
  and faction standing, the systems in §7 of the design doc. Natural Absorb-side
  pressure; interacts with UNDERTOW's The Cover pillar through shared flags.
- **Working title "WATERSHED"** — the frontier line. What is actually out in the
  procgen badlands, why the settlements are where they are, and who gets to own land
  nobody owns. The Valheim loop given a reason. M7-dependent by nature; natural
  Ruin-side pressure; interacts with The Line pillar.
- **Working title "SIGNALFADE"** — the brave-new-world line. The thing that makes this
  world drastically different from ours (deliberately unspecified here — this is the
  mystery line, and its premise is a creative decision for a session of its own).
  Built on the device, hacking, and the signals machinery (§7.4) read in reverse: the
  player as the observer.

Cross-line rule from §3.2 applies: these touch UNDERTOW only through shared sim state
and declared flags. No line references another line's internals.

---

## 9. Simulation systems

One new system plus content; everything else is reuse.

### 9.1 LineSystem (`&"lines"`)

- Owns the flag ledger (§6.1), the per-line stage state machine (locked / available /
  active / complete per stage), and avenue requirement evaluation.
- Registered in `sim/assembly.gd` in fixed order after QuestSystem (it consumes quest
  completion events; it must tick after the system that emits them).
- Advancement is command-driven: `&"line.accept_avenue"`, `&"line.abandon_avenue"`
  (abandoning returns the stage to available; progress inside the avenue's missions
  follows existing quest abandon rules). Handlers validate against requirements;
  the client never writes line state (invariant 2).
- Emits `&"line.stage_completed"`, `&"line.flag_set"`, `&"line.line_completed"` on the
  EventBus — the progression event bus the design doc already commits to (§10.1), which
  is how perks, brokers, districts and the other lines react without coupling.
- Snapshot: line/stage states + flag ledger, plain data only (invariant 7). Ticks are
  cheap: LineSystem does nothing per-tick except timed foreshadow events; it is
  event-driven.

### 9.2 Reuse map

| Need | Existing system (no new machinery) |
|---|---|
| Missions inside avenues | QuestSystem objectives + EventBus crediting (M5) |
| Mission locations | Site binding — quests reference site handles (design doc §5.3) |
| The Name's endgame flight | FugitiveSystem + TrailSystem (`bounty-architecture.md`) |
| Income for Act 2 | BountyDirector/BountySystem economy, base production modules |
| Story memory the world reads | Heat / notoriety / visible wealth (§7.3) + flag ledger |
| Meridian as an actor | Faction records + threat director (§7.5) |
| Convoy interdiction (The Line) | Route-graph convoy back-end pathing |
| Crew as raid support / staff | `sim/agents/` profiles + new `content/crew/` records |

### 9.3 Module and content layout

```
sim/quests/
  quest_system.gd                 existing — unchanged
  line_system.gd                  LineSystem (§9.1)
  (bounty systems per docs/bounty-architecture.md)

content/
  quest_line/<id>.json            line: intro trigger, ordered acts, stage refs
  line_stage/<id>.json            stage: objective, unlock predicate, avenue refs
  avenue/<id>.json                §5.1 contract
  outcome_flag/<id>.json          flag declarations, exclusive groups
  pillar/<id>.json                antagonist pillar records (UNDERTOW's five first)
  intel/<id>.json                 discoverable records pointing at pillars/avenues/rewards
  crew/<id>.json                  recruitable specialist records
  faction/meridian.json           the antagonist, as ordinary faction data

client/
  awareness tells (§7.2)          per-agent indicators — separate, earlier deliverable
  device "Threads" app            line/stage/avenue presentation on the device (§12 of
                                  the design doc: client of sim state, never a store)

tools/
  check_narrative_graph.py        §11 validator, wired into tools/test.sh fitness stage
  content_schemas/                schemas registered for every new content kind above
```

Every new kind obeys invariant 3: a new avenue, flag, pillar, intel record or crew
member is a file, never a `sim/` diff. If adding one requires a sim change, this
architecture is wrong and should be revisited rather than patched.

---

## 10. Determinism, saves, co-op posture

- All line state lives in LineSystem's snapshot: hashable, replayable, hashed in
  fixtures like everything else (invariants 6–7, 9).
- Avenue requirement evaluation is a pure function of sim state at the tick of the
  accept command — no wall clock, no global RNG.
- Intel discovery order uses `sim.rng()` where randomised (which broker sells which
  record this run), so a seed reproduces the whole investigative shape of a playthrough.
- Save format: flags and stage states ride the existing save overlay; content ids are
  versioned with the schema/migration machinery like all content (standards §6).
- Co-op later: because narrative truth is sim state mutated only by commands, a second
  player is only a second command source. The flag ledger is world-scoped in this
  document; per-player ledgers are a co-op-era decision explicitly out of scope.

---

## 11. Verification

Narrative structures rot silently; these make the rot loud. All run in the fitness
stage of `tools/test.sh`.

**Static validator** (`tools/check_narrative_graph.py`, pure content analysis):

1. **Reachability** — every ending variant of every line reachable from game start,
   under *every* combination of exclusive-group choices and *every* line
   interleaving (pillar 2 / §3.2). Model-checked over the flag graph, not play-tested
   into existence.
2. **No dead ends** — no reachable flag-ledger state from which any started line has
   zero completable continuations.
3. **Avenue plurality** — every stage ≥2 avenues; avenues differ per §5.1's rule.
4. **Intel coverage** — every avenue referenced by ≥2 intel sources (§4.2).
5. **Unique integrity** — every unique reward has exactly one source avenue; pillar
   avenue pairs have non-overlapping reward classes (§5.3).
6. **Dialogue lint** — no dialogue content carries `sets_flags` (§6.2).
7. Schema validation for every new content kind.

**Dynamic tests:**

- **Replay fixtures** — per stage: seed + command log through each avenue, state hash
  asserted (CLAUDE.md §7). The Act 4 derivation gets one fixture per finale variant.
- **Property tests** — generated command sequences across concurrently active lines:
  the stage state machine never enters an undeclared state; flags are append-only;
  requirement evaluation is order-independent for commuting commands. ≥10,000 cases;
  failing seeds committed permanently.
- **Metamorphic relations** — adding an avenue never reduces reachability of anything;
  tightening one avenue's requirement never makes a stage uncompletable while a sibling
  avenue exists; removing an intel record never drops avenue coverage below 2 (the
  validator catches it, the relation documents *why*).

---

## 12. Milestones and sequencing — proposal only

Not a schedule; a dependency sketch for CEOGG to carve into specs. Numbers beyond M7
are placeholders and collide with whatever the bounty work claims — sequencing the two
proposals against each other is itself a gate-level decision.

| Chunk | Contents | Depends on |
|---|---|---|
| **Tells** | §7 awareness indicators, client-only | M4 (done), M6 demo polish — cheap, early, one session |
| **Line core** | LineSystem, flag ledger, schemas, validator, fixtures — zero story content, proven with a synthetic test line | M5 quest machinery |
| **UNDERTOW Acts 0–1** | NARR-B outcome, nameboard stages, intel kinds, Meridian faction record | Line core; M6 (if NARR-B couples them) |
| **UNDERTOW Acts 2–3** | Crew records, pillar stages city-side (The Arm, The Ledger, The Cover) | Economy depth, base modules ADR, bounty loop |
| **UNDERTOW badlands + Act 4** | The Line pillar, finale variants, The Name → fugitive handoff | M7 (procgen settlements), bounty fugitive/trail systems |
| **Lines 2–4** | One at a time, each its own architecture pass like this one | UNDERTOW signed and shipped |

One system per session holds throughout: LineSystem is one session; the validator is
one; each stage's content is its own.

---

## 13. ADR candidates — open decisions, not resolved here

Per CLAUDE.md §1: these are surfaced, with a working assumption where the document
needed one to stay coherent. None is closed without CEOGG sign-off; numbers assigned
when the ADR files are cut.

| Candidate | Decision | Working assumption in this doc | Blocks |
|---|---|---|---|
| **NARR-A** | Spine model: shared spine / forked chains / hybrid (§3.3) | C — hybrid | Line core, all UNDERTOW authoring |
| **NARR-B** | Cold Storage as UNDERTOW's cold open vs standalone (§4.3) | none taken | UNDERTOW Act 0–1 content; touches M6 framing only in data |
| **NARR-C** | Three main lines vs four (§8) | none taken | Line 4 only; nothing structural |
| **NARR-D** | Protagonist voice: intent-based / silent / voiced (§6.4) | intent-based | All dialogue content; no sim impact |
| **NARR-E** | Ending derivation thresholds & whether a hybrid ending exists (§4.3) | hybrid exists, derived not picked | Act 4 content, finale fixtures |
| **NARR-F** | Flag ledger world-scoped vs per-player (co-op posture, §10) | world-scoped now, revisit at co-op | co-op milestone only |

Also depends on, but does not touch: ADR-010 (hub interiors — affects how alive
Meridian's city sites feel while the player is in the badlands).

---

## 14. What this document does not decide

- Final names for anything (§ preamble).
- Any tuning number: pillar minimum for Act 4, standing thresholds, payouts, flag
  derivation weights. Those belong to specs and playtests.
- The premise of SIGNALFADE (§8) — a creative session of its own.
- Milestone numbering past M7 (§12).
- Whether any of this starts before the bounty architecture's sessions — the two
  proposals share the quest module and must be sequenced by the approver, not by
  whichever document lands second.
