# M1 — Stat resolver + one pistol: specification

Milestone M1 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2).

**Preconditions.** G0 is signed in `docs/gates/M0-gate.md`; ADR-002, ADR-003 and
ADR-009 are `accepted` (standards §7). This spec assumes ADR-009 closes as proposed
(option C: ordered containers in the sim, count presentation by default). If it closes
otherwise, claims 6–8 are rewritten before any code, not after. Nothing in M1 depends
on which way ADR-003 closes; it is a precondition because the standards say so, not
because the pistol needs terrain.

**The claim of the milestone.** One weapon exists end to end, as data:
template → instance → attachment resolution → damage → skill event → one perk that
measurably changes the damage. If that round trip is clean, every later weapon is a
file (design doc §16). Nothing else is built.

## Claims

### Stat resolver (`sim/progression/`)

1. **Every number reads through one resolver.** `StatResolver.get(entity, stat_id)`
   returns the resolved value of a stat for an entity (design doc §10.2). No system
   under `sim/` reads a base value or a modifier directly to compute a gameplay
   number; the fitness function in claim 15 fails CI if one does.
2. **Bases are never mutated.** A stat is a base plus an ordered stack of modifiers.
   A modifier is `{stat_id, class, value, source, tags}` where `class` is one of the
   registered modifier classes. M1 registers exactly two, both commutative within
   themselves: `add` (flat, integer) and `mul` (integer basis points; 1 000 = ×1.1).
   Resolution is `(base + Σadd) × Π(1 + mul/10 000)`, integer arithmetic, truncating
   once at the end. All stat values are integers in milli-units (a damage of 34.5 is
   `34500`), so resolution is exact, hashable and platform-independent.
3. **The resolver's invariants hold for all inputs** (standards §3.2), each as a
   property test over ≥10 000 generated cases: (a) applying a set of modifiers in any
   order resolves to the same value; (b) adding then removing a modifier restores the
   exact prior value; (c) after any sequence of operations every base equals what
   was registered; (d) a cached value never differs from an uncached resolution.
   Caching is invalidated by any modifier add/remove on the entity or on anything it
   inherits modifiers from (claim 4); it is an optimisation, never observable.
4. **Wielded items inherit their wielder's modifiers by tag.** Item instances are
   entities. Resolving a stat on an item held by an actor consults the item's own
   modifiers and the actor's modifiers whose `tags` filter matches the item's tags
   (e.g. a perk tagged `["weapon_class.handgun"]` applies to the pistol and not to a
   tag-less crowbar). This is how perks, cyberware and weapon parts become one
   mechanism (design doc §10.2) and it is the only inheritance rule at M1.
5. **Stats, modifier classes and tags are registry entries, not enums** (standards
   §6.2). A stat is `content/stat/<id>.json` carrying its default base; a modifier
   class is a registration call; a tag is any `[a-z0-9_.]+` string. Resolving an
   unregistered stat is a loud `push_error` and returns the integer `0`, never a crash.

### Items and the pistol (`sim/items/`)

6. **Items are templates plus seeds.** `content/weapon_frame/`, `content/weapon_part/`
   and `content/ammo/` are the first content kinds. An instance is
   `{template_id, seed, affix_ids}` and is re-resolved from those three fields
   (design doc §11.3); two instances rolled from the same template and seed are
   identical in every stat, 10 000 generated cases. Every instance has a sim-unique
   integer id issued by the item system; ids are never reused within a run.
7. **A weapon is a frame plus sockets** (design doc §11.1). A frame declares sockets by
   kind (`barrel`, `slide`, `optic`, `magazine`, `power_cell`); a part declares the
   socket kind it fits and the modifiers it contributes to the weapon's stats via the
   resolver. Attaching, detaching and the resulting handling stats (`damage`,
   `recoil`, `ergonomics`, `sway`, `aim_in_ticks`) are all resolver reads; there is
   no per-weapon code path. The one frame is `content/weapon_frame/g19.json`, a
   compact semi-auto 9 mm analog with no gimmick (design doc §11.2), with one barrel,
   one slide, one 15-round magazine and one 9 mm ammo template.
8. **Magazines are ordered containers of round instances** (ADR-009). A magazine
   instance holds an ordered list of round instance ids up to its capacity; the
   weapon tracks its chambered round separately. Four command kinds, each owned by
   the item system and each rejecting any payload that is malformed or would violate
   an invariant: `&"magazine.load"` (push one loose round of a compatible calibre),
   `&"magazine.unload"` (pop one), `&"weapon.reload_tactical"` (swap in a named
   magazine; the partial one returns to the actor's inventory), and
   `&"weapon.reload_emergency"` (swap in; the partial one is dropped to the world
   container). Each reload has a duration in ticks read through the resolver
   (`reload_ticks`), during which further weapon commands are rejected.
9. **Items are conserved.** Property tests over ≥10 000 generated sequences of load,
   unload, reload, fire and attach/detach: the multiset of item instance ids across
   all containers (inventory, magazines, chamber, world) never gains or loses an id
   except through an explicit `fire` (which consumes exactly one round) or an
   explicit spawn; no id is ever in two containers at once.
10. **Item state survives a save round-trip with partial magazines** (ADR-009
    verification, G1). `ItemSystem.snapshot()` followed by
    `ItemSystem.restore(snapshot)` on a fresh instance yields an equal snapshot and an
    equal `SimRoot.state_hash()` for generated states that include partially loaded
    magazines and a chambered round. `restore` treats its input as untrusted
    (standards §5.1) and returns an `Error` on any malformed field. Full sim save/load
    remains G2 scope.

### Combat (`sim/items/`, `sim/agents/`)

11. **One fire command runs the one pipeline under a data-selected profile** (design
    doc §13.1). `&"weapon.fire"` on a weapon with a chambered round: consumes the
    round, chambers the next from the magazine if any, emits a `fire` event, and runs
    the stages the active `content/combat_profile/<id>.json` enables. M1 implements
    the stages the arcade profile needs and no more: hit resolution (a roll from
    `sim.rng()` against the resolved `hit_chance` at the target's declared range, since
    no spatial world exists yet), post-armour damage (the round's resolved `damage`;
    armour and penetration stages are registered as names but have no
    implementation and are disabled in the shipped profile), and body-part routing
    through the profile's routing table onto the target's health graph. Stage names
    are registry entries; enabling a stage the code does not implement fails
    content validation, not the playtest.
12. **Actors are minimal.** `sim/agents/ActorSystem` owns the player and target dummies
    as entities with an inventory container, a wielded-weapon slot and a health graph
    (design doc §13.2) whose nodes and fatal flags come from the combat profile. The
    arcade profile's table routes everything to one node. The player and each dummy
    are created by `&"actor.spawn"` commands so that a fixture reproduces its entire
    starting state; the same holds for `&"item.spawn"`. Both kinds are recorded as
    debug-class commands in the debt log: acceptable in solo, to be gated before co-op.

### Progression (`sim/progression/`)

13. **Gameplay emits events and knows nothing about progression** (design doc §10.1).
    A confirmed hit emits `hit{weapon_class, range_m}` on the sim's event bus; the
    progression service subscribes, credits `content/skill/handguns.json` per its
    event-to-xp table and raises the level at the thresholds in that file. The weapon
    system contains no reference to skills, xp or perks. Adding a second weapon class
    later is a tag in a file.
14. **One perk measurably changes damage, and it is only numbers in a file.**
    `content/perk/handgun_focus.json` is `{id, prerequisites, cost, modifiers[]}`
    (design doc §10.3) whose modifier is `mul +1 000` on `damage` tagged
    `weapon_class.handgun`. `&"perk.unlock"` is rejected unless the prerequisites are
    met and the skill has unspent points. A test fires the same seed and command stream
    with and without the perk and asserts the damage applied to the dummy differs by
    exactly the factor in the file. No perk-hook category exists at M1; the first perk
    that needs behaviour creates it, with a debt entry.

### Content, tooling, client

15. **Content is validated structurally at build** (standards §3.7, §6.1). Each new
    kind registers `tools/content_schemas/<kind>.json` and `tools/validate_content.py`
    checks every file against it: required keys, types, integer ranges, id format, and
    cross-references (a part's socket kind exists on some frame; a modifier's stat id
    is a registered stat; a profile enables only implemented stages). The error names
    file, key and rule. The schema dialect is the small subset the validator
    implements in the standard library, documented in `tools/content_schemas/README.md`.
    The same commit adds a fitness check that no file under `sim/` outside
    `sim/progression/stat_resolver.gd` reads a base or modifier value directly (claim 1).
16. **The sim never reads a file.** `sim/` may reference `res://sim/` only (CLAUDE.md),
    so content is parsed by the host (`client/local_host.gd`, `tools/replay_hash.gd`,
    the tests) and handed to the sim as a `ContentDb` of dictionaries. The sim
    re-validates at that boundary and refuses to start on any defect. The `ContentDb`
    contributes a canonical digest of every loaded file to the state snapshot, so a
    rebalance changes every fixture hash visibly rather than silently.
17. **The client drives the whole chain with input and writes no state** (design doc
    §12.1). `client/main.tscn` gains a range view: resolved weapon stats, magazine and
    chamber counts, the dummy's health, skill xp/level and perk state, all read from
    the sim each frame; keyboard and gamepad actions submit `weapon.fire`, the two
    reloads, `magazine.load` and `perk.unlock`. A test asserts that `client/` contains
    no call that mutates sim state other than `SimRoot.submit`.
18. **A Linux export runs on a Steam Deck.** An export preset excludes `tests/` and
    `tools/` (M0 debt item 9); the exported binary starts on Deck hardware, shows the
    range view and completes the demo script's fire-and-reload sequence. This is the
    first Deck smoke run (M0 debt item 5; standards §8.1). No frame-budget claim is
    made; that begins at G4.
19. **Replay fixtures exercise real systems.** `tests/replay/m1-range.json` spawns the
    player, the pistol, two magazines, thirty rounds and one dummy, loads, fires,
    tactical-reloads, fires to empty, emergency-reloads, unlocks the perk and fires
    again; it reproduces its recorded hash twice in-process and across processes.
    `tests/replay/m1-perk-off.json` is the same stream without the unlock and its hash
    differs. The fuzz corpus gains hostile command payloads for every new kind.

## Out of scope (goes to the debt log if touched)

Ballistics, projectile travel, penetration and armour (registered as stage names only),
bleed, fracture or any status effect, the sim combat profile's routing table beyond the
arcade one, hit location from geometry, recoil and sway as anything but resolved numbers,
a second weapon class, a perk tree with more than one node, a perk-hook category, a
device app or any device shell, Steam Input, GodotSteam, full sim save/load, land,
building, AI, loot affix tables beyond an empty list, C#/Rust hot paths, any
performance number.

## Assumptions to record in the gate

- Milli-unit integer stats and basis-point multipliers are a spec decision, not a design
  doc one. Alternative rejected: floats, which make "restores the exact prior value"
  and cross-machine hashes depend on operation order.
- The combat pipeline lives in `sim/items/` at M1 because its only inputs are item
  stats; design doc §4.2 names no combat module. If M4 wants `sim/combat/`, the move
  is mechanical and goes in that gate's log.
- Hit resolution is a roll against a resolved chance because M1 has no space. It is
  replaced, not extended, when M4 introduces perception and M6 geometry.
- `actor.spawn` and `item.spawn` are debug-class commands (claim 12).

## Extension exercise for Q4 (standards §11, G1)

Add a second weapon frame, `content/weapon_frame/<id>.json`, with its own parts, using
only new files under `content/`; `tools/test.sh` passes and the diff under `sim/` is
empty. Additionally, and with the same constraint: a second perk node with a
prerequisite on the first, and a second ammo type of the same calibre with different
damage. `docs/extending-items.md` and `docs/extending-progression.md` record the
procedure; the performed instances are committed.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| Resolver order independence, removal, base immutability, cache | 10 000 each | `tests/progression/test_stat_resolver.gd` |
| Loot roll determinism (template + seed) | 10 000 | `tests/items/test_item_instance.gd` |
| Item conservation across generated command sequences | 10 000 | `tests/items/test_item_conservation.gd` |
| Item snapshot/restore round-trip with partial magazines | 10 000 | `tests/items/test_item_save.gd` |
| Command payload fuzz, every new kind | corpus + 10 000 mutations | `tests/fuzz/commands/` |

A failing seed is committed as a named regression case (standards §3.2).
