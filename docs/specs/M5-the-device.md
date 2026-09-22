# M5 — The device: specification

Milestone M5 of `docs/gcity-design.md` §16, in the terms of that document. Written
before implementation (standards §2.1, §10.2). Status: **approved** as written (CEOGG,
2026-09-21); implemented, G5 accepted 2026-09-22 (`docs/gates/M5-gate.md`).

**Preconditions.** G4 is signed in `docs/gates/M4-gate.md` (it is). **ADR-006** (does the
device pause time?) is `accepted` as **C** (CEOGG, 2026-09-21), pause only inside
owned or safe parcels, as this spec assumed: the design doc's terminal-hack tension
(§15.2) and the "caught with everything empty" failure state (§13.3) both depend on
it. ADR-007 (death cost) and ADR-010 (hub interiors) do not block M5.

**The claim of the milestone.** The device is the entire UI layer and holds no state
of its own (design doc §12.1): every pane renders sim state and every button submits
a command, so the device could sit on the far side of a socket without a rewrite.
The shell knows nothing about any app: an app is a content file naming its hardware
requirement and a view registered by name, so the device is an upgradeable item and
unlocking an app is acquiring a real object (§12.2). Pausing is a sim command the
land authority gates (ADR-006 C). The device is designed for a 7" screen and a
controller first: rendered at its own resolution to a texture, redrawn on change
(§12.4), every core task completable in seconds with a stick, a trackpad and the
face buttons. Steam Input and GodotSteam arrive with it, not at the end (standards
§8.2, §8.3). G5's proof (standards §11): Steam Input configuration shipped; Deck
Verified input and display axes self-assessed as passing; UI legible at 1280×800
handheld; GodotSteam integrated and pinned.

## Claims

### The device is an item (`sim/items/`)

1. **The device is an item entity.** `content/device_frame/<id>.json` declares its
   `sockets` (refs to `content/device_socket/`), `tags` (`device`), and `stats`
   (`memory_capacity`, `antenna_gain`, `battery_reserve`: milli-units, `content/stat/`).
   `content/device_module/<id>.json` declares the socket it fits, its `modifiers`
   (through the stat resolver, as weapon parts do) and the `provides` tags an app may
   require (`radio`, `daemon_coprocessor`). M5 ships one frame (`handset`), two
   sockets (`radio`, `coprocessor`), one module (`radio_module`), and the existing
   `weapon.attach` / `weapon.detach` generalised to `item.attach` / `item.detach`
   over any socketed frame, with the weapon commands kept as aliases for the fixtures
   (M1 claim 8's contract is unchanged).
2. **The player carries one device**: `actor.equip_device {actor, device}` binds a
   device item in the actor's inventory as the one the shell reads; the item's
   resolved stats and `provides` tags are what the shell sees. An actor without a
   device has no apps; the world view's HUD stays.

### Shell and apps (`client/device/`)

3. **Apps are content, views are registrations.** `content/device_app/<id>.json`
   declares `icon`, `order`, `requires` (a `provides` tag, or none) and `description`.
   The shell lists the apps whose requirement the equipped device provides, in
   `order`; the client registers one view scene per app id
   (`DeviceShell.register_view(&"<id>", scene)`) and an app with no registered view
   fails the client's startup, not the playtest. M5 ships `inventory`, `map`, `quests`,
   `comms` (base unit; `comms` shows the squad radio traffic the sim already emits,
   M4 claim 11) and `drone` (requires `radio`; a placeholder pane that reports "no
   drone in range", since drones are M7: it exists to prove the gate).
4. **The device holds no state.** Every pane reads through `SimAssembly.*_of(sim)`
   and submits `SimCommand`s; the fitness function gains a rule: nothing under
   `client/device/` declares a `var` holding an entity id, count, or dictionary
   copied from the sim beyond the current frame (a per-file allow-list for view
   state: scroll position, selected index, the open app). `tools/check_dependencies.py`
   enforces it.
5. **Rendered at its own resolution, redrawn on change** (§12.4): the device draws
   into a `SubViewport` of 960×600 shown on a quad filling most of the world view
   when raised, with `render_target_update_mode = UPDATE_ONCE` set only when a pane
   reports a change (its sim read differs from the last frame's) or input arrives.
   The gate records the device's draw cost on the Deck raised and idle versus lowered.

### Pause (`sim/core/`, `sim/land/`)

6. **`safe` is a sixth right.** Every district's rights table gains a `safe` column
   (owner / other / unowned); `LandAuthority.rights_at()` returns it with the other
   five and it is in every district file (a validator-checked required key). Shipped
   content: `safe` is true for owners everywhere and false otherwise; a hub district
   that grants it to everyone is one content change.
7. **Pause is a sim command.** `sim.pause {actor}` is accepted only when the actor is
   alive and holds `safe` where it stands (a refusal is a `land.violation` like any
   rights failure, so it is visible); `sim.resume {actor}` is accepted only while
   paused. While paused the root does not advance its tick: `step()` dispatches only
   the commands registered **pause-safe** (`CommandRegistry.register(kind, handler,
   pause_safe)`; at M5: `sim.resume`, the item commands the inventory app issues, and
   `quest.accept` / `quest.abandon`) from the next tick's queue, in submission order,
   leaves the rest queued, ticks no system, and counts `paused_steps` in the
   snapshot, so a save taken paused restores paused and two sims paused for
   different wall times hash equal. Property: over 10 000 generated pause/resume
   interleavings, the state hash after resume equals that of the same command
   stream with the pauses removed, except for `paused_steps`.
8. **The device shows the rule.** A `secure` indicator on the shell reads `safe`
   from `rights_at`; raising the device where it is true submits `sim.pause`, lowering
   it submits `sim.resume`; where it is false the device raises unpaused and the
   indicator says so. The gate's legibility check (claim 14) is done with the device
   unpaused in a hostile parcel, as ADR-006's consequences require.

### Quest records (`sim/quests/`)

9. **A quest is content with event objectives.** `content/quest/<id>.json` declares
   `title`, `text`, `objectives` (each an event kind on the bus, optional `tags_any`
   and a `count`, as `skill` xp rules already do) and `reward` (item templates
   spawned into the actor's inventory on completion). `QuestSystem` (system id
   `quests`) owns `quest.accept {actor, quest}` and `quest.abandon {actor, quest}`,
   advances objectives from bus events for the actor, emits `quest.completed` and
   grants the reward once. State: per actor, per quest, the objective counts and
   status. The director, offers, dialogue and site binding are M6/M7 (design doc
   §5.3, §15.1); M5 ships two quests over existing events (`combat.hit` with the
   handgun tag; `build.changed` for the placed piece) so the app has something true
   to show, and the fixture completes one.

### Steam (`client/steam/`, `tools/`)

10. **GodotSteam is integrated and pinned** (standards §5.4, §8.2): the GDExtension
    release for the pinned engine, downloaded by `tools/godotsteam.sh` into
    `addons/godotsteam/` and verified by SHA-256 like the engine; version, hash,
    Steamworks SDK version, licence (MIT), maintenance status and transitive size
    recorded in `tools/godotsteam.pin` and `docs/dependencies.md`. `SteamHost`
    (`client/steam/steam_host.gd`) initialises Steam with the test app id when the
    Steam client is running and reports "offline" otherwise: the game never requires
    Steam to run. The overlay note of §8.2 is verified on the Deck and recorded.
11. **Steam Input configuration shipped**: an action manifest and a default Deck
    layout (`steam_input/`) with action sets `world` and `device`, the trackpad
    driving device navigation and the back buttons carrying lean placeholders and
    tactical reload (§8.3); glyphs come from Steam Input's glyph API when Steam is
    up and from a bundled Deck/Xbox set otherwise, and the HUD's prompts show only
    the active device's glyphs (keyboard hidden under a controller). Without Steam
    the existing input map remains the fallback.
12. **Steam Cloud** points at the M2 file set (`docs/steam-cloud.md`): the cloud
    configuration is recorded in the package; conflict handling is the client's
    existing slot-meta rule.

### Legibility, fixtures, save, corpus, client

13. **Minimum type size enforced**: a theme constant of 22 px at 1280×800 for body
    text and 18 px for secondary, asserted by a client test that walks every device
    pane's labels; nothing smaller ships.
14. **Time-to-complete recorded** (ADR-006 verification): the gate package records,
    with a controller on the Deck, the seconds to: load a magazine from loose rounds,
    swap a magazine, attach a part, accept a quest, find a parcel on the map, and
    lower the device; each under 10 s, the reload tasks under 4 s.
15. **Fixtures**: `m5-inventory.json` (the device's command stream loads a
    magazine, wields, attaches the radio module; the state matches doing it by
    hand), `m5-quest.json` (accept, hit the dummy three times, completed, reward in
    the inventory), `m5-pause.json` (pause in the starter plot, a reload submitted
    during the pause is still pending at resume; a pause outside the plot is a
    violation).
16. **Everything is in the snapshot and survives the round trip**: the equipped
    device, quest states, the paused flag and `paused_steps`; the save property's
    stream gains every new command kind. Save schema stays at version 1.
17. **Schemas** for `device_frame`, `device_socket`, `device_module`, `device_app`,
    `quest`; the district schema gains `safe`. **Corpus** extended with every new
    command kind.
18. **Client**: the device raised and lowered on Select / Backspace (restart moves
    to a held Select; the overlay toggle to a back button in the Steam layout), the
    five panes, the secure indicator, the glyph-aware prompts. Screenshots of every
    pane in the package.
19. **Deck Verified self-assessment**: `docs/deck-verified.md` walks Valve's input
    and display axes (standards §8.4) item by item with the evidence for each; the
    seamlessness and system-support axes are noted as satisfied by construction.

## Out of scope (goes to the debt log if touched)

Drone control (M7), hacking (M6), the quest director, offers and dialogue (M6), site
binding (M7), achievements (subscribers on the bus, after M6), SteamPipe upload and
the `dev`/`gate` depots (CEOGG's external action; the package records the depot plan),
the economy and credits, comms beyond the squad radio feed, any pane for systems that
do not exist yet, controller remapping UI (Steam Input's own), localisation.

## Open points

- ADR-006: accepted as C together with this spec (2026-09-21).
- **The Steam app id**: the test app (480) until CEOGG registers the Steamworks app
  (standards §12 item 4, still open); `SteamHost` reads it from `tools/godotsteam.pin`.
- **GodotSteam release availability** for Godot 4.6.1: verified at the start of the
  first M5 session; if no GDExtension release matches, the spike of standards §8.2
  decides between a nearby release and building the module, and the spec is amended.

## Assumptions to record in the gate

- The device is raised, not held at arm's length (§12.4): it covers about 70 % of the
  viewport; the world keeps rendering behind it at its own rate.
- Pause-safe commands are the inventory app's item commands and the quest commands;
  building, moving and firing are never pause-safe (a paused sim cannot be exploited
  to act while nobody else can).
- The map shows what the sim holds, not what the player knows: fog of war is M7 with
  the route graph.

## Extension exercise for Q4 (standards §11, G5)

Add a sixth app (`content/device_app/notes.json`, no hardware requirement) with one
registered view (a scene under `client/device/apps/`), a second device module
(`content/device_module/daemon_coprocessor.json`, `provides: ["daemon_coprocessor"]`)
that unlocks a placeholder `hacking` app, and a third quest, using only new content
files and one `register_view` call; `tools/test.sh` passes, the pane test walks the
new pane, and the diff under `sim/` is empty. `docs/extending-device.md` records the
procedure.

## Fixtures and property seeds

| Test | Cases | Fixed seed constant |
|---|---|---|
| Pause: hash after resume equals the stream without pauses (save for `paused_steps`); paused-safe dispatch order | 10 000 interleavings | `tests/sim/test_pause.gd` |
| Quest objectives: counts never exceed `count`, completion exactly once, reward granted once | 10 000 event streams | `tests/quests/test_quest_system.gd` |
| Device stats: attach/detach round trip restores the exact prior value (M1 claim 3 on the device) | 10 000 | `tests/items/test_device.gd` |
| Save round trip with device, quest and pause commands in the stream | 10 000 | `tests/sim/test_save_file.gd` (extended) |
| Command payload fuzz, every new kind | corpus + 10 000 mutations | `tests/fuzz/commands/` |
| Every device pane's labels at or above the minimum size | walk | `tests/client/test_device_legibility.gd` |

A failing seed is committed as a named regression case (standards §3.2).
