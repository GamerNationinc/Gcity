# Extending: the device, its bays, apps and quests

The minimal diff for each thing the device (`client/device/`, `sim/items/`) and the
quest records (`sim/quests/`) can be extended with. Design doc §12; M5 spec claims
1–5, 9. The G5 extension exercise is a sixth app with no hardware requirement, a
second device module with an app gated on it, and a third quest: four content files,
two view scenes, one line of registration, no `sim/` diff.

## Vocabulary

- **Device frame**: a `content/device_frame/` item with bays (`content/device_socket/`
  ids) and stats. The player carries one (`actor.equip_device`), and it inherits the
  carrier's `device`-tagged modifiers like a wielded weapon.
- **Module**: a `content/device_module/` item that fits one bay, adds `modifiers`
  through the stat resolver, and offers `provides` tags.
- **App**: a `content/device_app/` entry with an `icon`, an `order` in the strip and a
  `requires` tag (or none). The shell offers the apps whose requirement the carried
  device provides.
- **View**: the scene a client registers for an app id. The shell knows nothing else
  about any app.
- **Quest**: a `content/quest/` record whose objectives are bus events credited to an
  actor named in the payload.

## A new app: one file and one registration

1. `content/device_app/<id>.json`: `title`, `icon` (one character the strip draws),
   `order`, `requires` (a module's `provides` tag, or `""`).
2. `client/device/apps/<id>_app.gd` extending `DeviceApp`, with its `.tscn`:
   - `refresh(sim, player) -> bool`: read the sim, rebuild the pane, return whether
     what it shows changed. The shell redraws the viewport only when something did.
   - `handle(action, sim, player) -> bool` for the device actions.
   - `prompts(glyphs) -> String` for the line under the pane.
   - `submit(kind, payload)` for every change: the pane never writes sim state.
3. One line in `client/world_view.gd`'s registration loop.

The device holds no state: `tools/check_dependencies.py` rule 4 refuses a class-level
`var` in this directory beyond nodes, scenes, callables, strings and the allow-listed
view state (a cursor, the last drawn text, a draw cache). Rebuild from the sim.

## A new module and the app it unlocks: two files

`content/device_module/<id>.json`: `socket`, `fits`, `modifiers`, `provides`. An app
whose `requires` names one of its `provides` tags appears when the module is in a bay
and goes when it is taken out; its modifiers reach the device through the resolver and
are removed exactly on detach.

## A new bay or frame: one file each

`content/device_socket/<id>.json` is a name. `content/device_frame/<id>.json` lists
its bays, `tags` (`device`) and `stats`. A device frame never carries a container
socket: rounds live in weapon magazines.

## A new quest: one file

`content/quest/<id>.json`: `title`, `text`, `objectives` and `reward`. Each objective
names an `event` on the bus, the payload field to `credit` (`shooter`, `target`,
`actor`), optional `tags_any`, and a `count`. The reward is `{kind, template, count}`
triples spawned into the inventory once, on completion. The events available are the
ones systems already emit (`combat.hit`, `combat.fire`, `build.changed`,
`perception.alerted`, `squad.report`, `quest.completed`); a new one is an `emit` call
in the system that owns the fact, not a special case here.

## What you may not do

- Let a pane keep an entity id, a count or a copy of a sim table between frames.
- Write sim state from the client: every change is a `SimCommand` the sim may refuse.
- Add an app with no registered view: the shell asserts at its first refresh.
- Reward a kind the item system cannot spawn: assembly refuses it.
- Assume the device pauses: `safe` is a right the land answers per parcel (ADR-006 C).
