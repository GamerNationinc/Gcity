# Extending: items, weapons, parts and ammo

The minimal diff for each thing the item system (`sim/items/item_system.gd`) can be
extended with. Design doc §11, §13.3; ADR-009; M1 spec claims 6–10. This is the G1
extension exercise: a second weapon frame with data only and an empty `sim/` diff.

## Vocabulary

Every item instance is an entity (int) in exactly one named container:

| Container | Holds | Capacity |
|---|---|---|
| `world` | dropped items | unlimited |
| `inv.<actor>` | an actor's loose items | unlimited |
| `socket.<weapon>.<socket>` | the part fitted in that socket | 1 |
| `mag.<magazine>` | rounds, in order, last loaded on top | the part's `capacity` |
| `chamber.<weapon>` | the chambered round | 1 |

Item conservation is the system's core property (standards §3.2): no command creates,
duplicates or destroys an item except `item.spawn` (and, later, `weapon.fire` consuming
one round). `tests/items/test_item_system.gd` proves it over 10 000 random commands
and 10 000 hostile payloads.

## A new weapon frame: one file (+ its parts)

`content/weapon_frame/<id>.json`:

```json
{
	"schema_version": 1,
	"description": "…",
	"calibre": "9x19",
	"sockets": ["barrel", "slide", "optic", "magazine", "power_cell"],
	"tags": ["weapon", "weapon_class.handgun"],
	"stats": [{"stat": "hit_chance", "value": 650000}, {"stat": "reload_ticks", "value": 80000}]
}
```

- `calibre` and every socket are `ref`s to existing files; the validator rejects
  anything else at build time.
- Exactly one socket must be a container socket (`weapon_socket/<id>.json` with
  `"contains": "ammo"`); that is where magazines go. `ItemSystem.validate_content()`
  refuses to assemble otherwise.
- `stats` become the frame instance's bases in the resolver; `tags` become its tags, and
  a chambered round inherits them so tagged perks reach the shot.
- Parts declare which frames they fit, so a new frame usually comes with new part files
  (or an existing part gains the frame's id in its `fits` list).

## A new part: one file

`content/weapon_part/<id>.json` with `socket` (a `weapon_socket` id), `fits` (frame
ids) and `modifiers` (`{stat, class, value}` entries the resolver applies to the weapon
while the part is fitted, with `source` `part.<id>`). A part for the container socket
also carries `capacity` and `calibre`; a part for any other socket must not.

## A new round: one file

`content/ammo/<id>.json` with `calibre`, `tags` and `stats` (its `damage` base).
Loading checks the round's calibre against the magazine's; reloading checks the
magazine's against the frame's.

## A new socket kind: one file

`content/weapon_socket/<id>.json`. Frames list it, parts fit it. Add `"contains":
"ammo"` only for a socket whose parts are round containers; nothing else is a
container at M1 and the system refuses other values until a system needs them.

## Commands (all owned by the item system)

| Kind | Payload | Effect |
|---|---|---|
| `item.spawn` | `{kind, template, container, seed, count}` | debug-class; instances into `world` or `inv.<actor>` |
| `magazine.load` | `{actor, magazine, round}` | loose round onto the top of a loose magazine |
| `magazine.unload` | `{actor, magazine}` | top round of a loose magazine back to the inventory |
| `weapon.attach` | `{actor, weapon, part}` | loose part into its empty socket; modifiers applied |
| `weapon.detach` | `{actor, weapon, socket}` | part back to the inventory; modifiers removed |
| `weapon.reload_tactical` | `{actor, weapon, magazine}` | seat a magazine, old one to the inventory |
| `weapon.reload_emergency` | `{actor, weapon, magazine}` | seat a magazine, old one to `world` |

Reloads chamber the top round if the chamber was empty, apply the magazine's modifiers,
and make the weapon busy for `reload_ticks` (resolved, milli-ticks) during which weapon
commands are rejected. Payloads are exact: extra keys, wrong types, items the actor does
not hold, wrong calibres, full magazines and busy weapons are all rejected without any
state change. Until the actor system lands, "actor" is any positive int naming an
inventory; the actor system will gate it.

## Combat: profiles, stages, actors

The one pipeline (`sim/items/combat_system.gd`, design doc §13.1) runs the stages a
`content/combat_profile/<id>.json` enables, in the profile's order, on `weapon.fire`
`{actor, target}`: the shooter's wielded weapon, its chambered round, the target's
declared range. Then it consumes the round (the only way an item leaves the world),
chambers the next, makes the weapon busy for `cycle_ticks`, and emits `combat.fire` and
`combat.hit` on the event bus with the weapon's tags and the range, which is all the
progression system needs to know.

| To add | Do |
|---|---|
| A profile (arcade, sim, range dummy) | one file: `stages`, `range_falloff_per_m`, `health.nodes` (`id`, `max`, `fatal`), `health.routing` (`node`, `weight`). At least one fatal node; every routed node must exist. |
| A stage name | one file under `content/combat_stage/`. A profile may only enable names that code implements; `CombatSystem.validate_content()` refuses to assemble otherwise, so a typo or an aspirational stage fails at startup, not in play. |
| A stage implementation | one registration call, `combat.register_stage(&"armour", callable)`, from the system that owns the semantics. The callable gets the shot context dictionary and the sim, reads through the resolver, and writes `hit`, `damage`, `node`, `applied`, `killed`. `tests/items/test_combat_system.gd::test_extension_a_new_stage_is_a_registration_call_and_content_is_checked` is the performed instance. |
| An actor | `actor.spawn {profile, range_m}` (debug-class until the actor system gates it) and `actor.wield {actor, weapon}` for a frame in its inventory. |

Built-in stages: `hit_roll` (resolved `hit_chance` minus `range_m × range_falloff_per_m`,
clamped, rolled with `sim.rng()`), `damage` (the round's resolved `damage`), `routing`
(weighted pick from the routing table, then `ActorSystem.damage_node`). Because a
chambered round inherits the weapon's tags and the wielded weapon inherits from the
actor, a perk tagged `weapon_class.handgun` on the actor changes the applied damage by
exactly its factor with no combat code involved.

## What you may not do

- Move an item by editing a container array. Every move is `_move()`, which keeps the
  location index and capacities true; every command validates before it moves.
- Read a template number to compute a gameplay value. Templates set bases and
  modifiers in the resolver at spawn/attach time; gameplay reads `resolve()`.
- Add a weapon behaviour as code on a frame. If a frame needs something the data cannot
  express, it is a new socket kind or a new stat, and it goes through the same files.
- Branch on a profile name in code. Arcade and sim differ only in which stages a file
  enables and which numbers it carries.
