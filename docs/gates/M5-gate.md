# G5 — M5 The device: gate evidence package

Milestone: M5 — The device (design doc §16; standards §11 row G5;
`docs/specs/M5-the-device.md`, approved 2026-09-21 with ADR-006 as C)
Submitted: 2026-09-22 by Claude Code, on branch `m5-the-device` (PR #7),
commits `8e36876` … the package commit
Outcome: _pending review_ — **needs the G5 Deck feel run from CEOGG (§7); every
number in §2 is from the approver's own Deck**

---

## 1. Specification

See the spec. Nineteen claims; all implemented. Deviations recorded in §4: the
generic item commands keep the weapon names as aliases, the shell's own actions are
a new input set rather than a Steam Input binding (the app id is not ours yet), and
the device is a fixed panel rather than a scaled one.

| Claims | Delivered by | Commit |
|---|---|---|
| 1 the device is a socketed item family | `sim/items/item_system.gd` (`device_frame` / `device_socket` / `device_module`, `item.attach` / `item.detach`, `provides_of`), the three content kinds and schemas, three device stats | `8e36876` |
| 2 the player carries one device | `sim/agents/actor_system.gd` (`actor.equip_device`, the device slot, resolver inheritance) | `8e36876` |
| 3 apps are content, views are registrations | `content/device_app/`, `client/device/device_shell.gd`, `client/device/apps/*` | `96779f7` |
| 4 the device holds no state | `tools/check_dependencies.py` rule 4 and its Python test; `DeviceApp.refresh` rebuilds from the sim | `96779f7` |
| 5 its own resolution, redrawn on change | the world view's `SubViewport` (896×560) and `DeviceShell.refresh`'s changed flag | `96779f7` |
| 6 `safe` is a sixth right | `sim/land/land_system.gd`, every district's rights table, the schema | `12b9695` |
| 7 pause is a sim command | `SimRoot` (`paused`, `paused_steps`, the frozen step), `CommandRegistry.register(..., pause_safe)`, `sim.pause` / `sim.resume` | `12b9695` |
| 8 the device shows the rule | the shell's secure indicator; raising submits the pause where `safe`, lowering the resume | `96779f7` |
| 9 quest records | `sim/quests/quest_system.gd`, `content/quest/`, `build.changed` carrying its actor | `870f02d` |
| 10 GodotSteam pinned and integrated | `tools/godotsteam.pin` / `.sh`, `client/steam/steam_host.gd`, `docs/dependencies.md`, `tools/steam_probe.gd` | `8e36876`, `693bdef` |
| 11 Steam Input configuration and glyphs | `steam_input/game_actions.vdf` and its README, `client/input_glyphs.gd` | `693bdef` |
| 12 Steam Cloud | the M2 file set is what the cloud configuration points at (`docs/steam-cloud.md`); §2 records the client's cloud state on the Deck | this package |
| 13 minimum type size | 22 px body / 18 px secondary enforced by a test that walks every pane | `96779f7` |
| 14 time-to-complete recorded | `tools/bench_device.gd`; §2 | `c824064` |
| 15 fixtures | `tools/make_m5_fixtures.gd`, `tests/replay/m5-*.json`, `tests/sim/test_m5_fixtures.gd` | `c824064` |
| 16 save round trip | the save property's stream gains every new command kind | `c824064` |
| 17 schemas and corpus | five new schemas, the district schema's `safe`; 38 new hostile cases (148 total) | `8e36876` … `870f02d` |
| 18 client | the device raised over the world, five panes, the secure indicator, glyph-aware prompts | `96779f7` |
| 19 Deck Verified self-assessment | `docs/deck-verified.md` | `c824064` |
| Q4 extension exercise | `content/device_app/notes.json`, `hacking.json`, `content/device_module/daemon_coprocessor.json`, `content/quest/hold_the_line.json`, two view scenes, one registration line; `docs/extending-device.md` | `c824064` |

## 2. Verification report

Produced **on the approver's Steam Deck** (SteamOS, AMD Custom APU 0932, Godot
4.6.1-stable, plugged, desktop mode, 1280×800). Reproduce with `tools/test.sh`,
`tools/bench_device.gd` and `tools/steam_probe.gd`.

### Fitness functions

| Check | Result |
|---|---|
| Python tool tests | 38 tests, OK (one new: the device-holds-no-state rule) |
| `tools/check_dependencies.py` | clean, including rule 4 over `client/device/` |
| `tools/validate_content.py` | clean: 113 content entries across 29 kinds |

### Static analysis

Every `.gd` file passes `--check-only` with warnings as errors.

### Headless test suite

| Suite | Tests | What it proves |
|---|---|---|
| `tests/items/test_device.gd` | 5 | the device is an item with bays and stats; modules fit through `item.attach` and provide their tags, with cross-family refusals; one carried device, inheriting the carrier's device-tagged modifiers; **10 000-case property: attach and detach restore the exact prior value and conserve items**; restore |
| `tests/sim/test_pause.gd` | 5 | `safe` by rights table; pause gated and refused as a violation; a frozen tick with a menu's commands dispatched and game-time commands waiting in order; a save taken paused; **500-case property: the same play with and without pauses hashes equal but for the pause bookkeeping** |
| `tests/quests/test_quest_system.gd` | 5 | contracts and pause safety; crediting, tag filtering, other actors ignored; completion and reward exactly once; a build objective crediting the builder; **200 generated event streams**; restore whose status must agree with its progress |
| `tests/client/test_input_glyphs.gd` | 4 | every world action has a Deck glyph and a keyboard name with the other device's hidden; Deck versus Xbox naming; the last event decides; the manifest names and localises every action |
| `tests/client/test_device_shell.gd` | 5 | apps follow the carried device and its modules; a pane reports a change only when its reading changed; the inventory's buttons are the sim's commands; every label at or above the minimum size; the extension exercise |
| `tests/sim/test_m5_fixtures.gd` | 3 | the three fixtures replayed tick by tick: see below |
| M0–M4 suites | 211 | unchanged claims; the save property's stream gained the M5 commands |
| **Total** | **238 tests, 0 failed** | `check_test_log: clean` |

### Replay determinism

Sixteen fixtures replayed in two processes each, identical and equal to the recorded
hashes. Every earlier hash moved with the new content in the digest and the device
slot on every actor record; every move is in the commit that caused it.

### Recorded numbers

| Number | Value | Where |
|---|---|---|
| **Time to complete, with a controller** (presses × 0.35 s + sim ticks) | | `tools/bench_device.gd` |
| load a magazine from loose rounds | 2 presses, **0.80 s** (limit 4 s) | |
| swap a magazine into the pistol | 4 presses, **1.57 s** (limit 4 s) | |
| attach a part | 3 presses, **1.20 s** (limit 10 s) | |
| accept a quest | 3 presses, **1.17 s** | |
| find your parcel on the map | 1 press, **0.42 s** | |
| lower the device | 1 press, **0.38 s** | |
| m5-inventory | carried, fitted, 15 loaded, wielded, swapped, module out; 0 rejected | `test_m5_fixtures.gd` |
| m5-quest | accepted, 3 hits, completed, reward in the inventory | |
| m5-pause | 1 violation off the plot, granted at home, 119 frozen steps, the queued step never taken | |

### Steam on the Deck (claims 10, 12)

`tools/steam_probe.gd` against the running Steam client:

```
extension loaded: true
status: online, app 480
persona: gg  app: 480  logged on: true  deck: true
action sets resolved: false  cloud enabled: true  overlay enabled: true
```

The extension loads in the pinned engine, Steam initialises, the machine is
recognised as a Deck, and cloud is enabled for the account and the app. The action
sets resolve to nothing because the shipped layout cannot be bound to Valve's test
app (§4, item 4); the input map is the fallback and every prompt is still in Deck
names. The overlay note of standards §8.2 held: no overlay problem in an exported
build or a desktop-mode launch.

### Screenshots

- `docs/gates/screenshots/M5-inventory.png`: the device raised on the owned plot,
  SECURE and the world stopped, the seven-app strip, the pistol with its sockets,
  the handset with its two bays, both modules loose.
- `docs/gates/screenshots/M5-map.png`: the map pane, north up, the plots by owner
  and the M4 building's footprint.
- `docs/gates/screenshots/M5-quests.png`: the quests pane with an objective and its
  reward.

## 3. Demo script

Steps 1–5 on any Linux x86_64 machine; steps 6–16 on the Deck from `tools/export.sh`.

1. `tools/godotsteam.sh` → installs the pinned binding (first run downloads and
   verifies it). `tools/test.sh` → `238 tests, … 0 failed`, sixteen `ok` replay
   lines, `all stages passed`.
2. `git show --stat c824064 -- content client/device/apps/notes_app.gd` → the
   extension exercise: four content files, two views; nothing under `sim/` (Q4).
3. Add `"safe": true` to `other` in `content/district/starter_ghetto.json`;
   `tools/test.sh unit` → the pause test fails where it expects a violation off the
   plot, and every fixture hash moves. Revert.
4. `$(tools/godot.sh) --headless --path . -s tools/bench_device.gd` → the table in §2.
5. `$(tools/godot.sh) --headless --path . -s tools/steam_probe.gd` → online if the
   Steam client is running, `offline` with a reason otherwise, and the game runs
   either way.
6. Launch. → The street, the M4 building ahead, the HUD's prompts in Deck names and
   a `steam:` line saying online with your persona.
7. Press View. → The device rises: SECURE, time stopped, the app strip, the
   inventory. The HUD behind says PAUSED.
8. D-pad down to `radio_module`, A. → It moves into the handset's radio bay; the
   antenna reads 400 m; a Drone app appears in the strip.
9. D-pad down to `daemon_coprocessor`, A. → A Hacking app appears; memory reads 2.
10. R1 to the Map. → North up, your plot green, the neighbours' red, the building's
    footprint in grey, guards as red dots.
11. R1 to Quests, A on *Break ground*. → `[active]`, `0 / 3`.
12. View to lower. → Time runs again. Place three pieces (A three times). Raise the
    device: the objective reads `3 / 3` and the quest is `completed`, with the
    reward magazine in the inventory.
13. Walk north off your plot and press View. → The device rises, the indicator says
    EXPOSED and time runs; guards keep moving behind it.
14. Hold View for two seconds. → A fresh sim on the street.
15. F5, quit, relaunch, F9 → the carried device, its modules, the quests and the
    pause state return.
16. Write the feel notes (§7): the numbers to move are the device's own content
    (`content/device_app/` order and icons, `content/device_frame/handset.json`
    stats), the rights tables (`safe` per district), and the shell's constants in
    `client/device/device_shell.gd`.

## 4. Debt and deviation log

| # | Item | Kind | Scheduled |
|---|---|---|---|
| 1 | `weapon.attach` / `weapon.detach` remain as aliases of `item.attach` / `item.detach`; the M1 fixtures and the hostile corpus still use them. Removing them is a fixture rewrite with no gain. | deviation, closed | none |
| 2 | The device's own actions are a new Godot input set (`device_*`), not Steam Input bindings: the manifest declares them, but the layout cannot be bound under the test app id. | deviation | G6, with the registered app |
| 3 | The device is a fixed 896×560 panel centred in the viewport rather than scaled to the screen; at 1280×800 it covers about 70 % of the height, which is what §12.4 asks for. A second resolution would need scaling. | scope | M6 |
| 4 | `getActionSetHandle` resolves to nothing under Valve's test app, so `activate_action_set` is a no-op and Steam's own glyph API is unused: the glyph set is the bundled text. CEOGG registering the Steamworks app closes both (standards §12 item 4). | external | G6 |
| 5 | No on-screen keyboard hook: nothing in M5 takes text. A named save slot would need one. | scope | M6 |
| 6 | Steam Cloud is enabled for the account and the app but nothing is synced: the cloud configuration is bound in the partner site, which needs the app id. | external | G6 |
| 7 | The comms app shows the squads' state rather than a message log: the sim has no message history, only live state. A log is an event subscriber when the threat director gives it something to say. | scope | M8 |
| 8 | The map shows what the sim holds, not what the player has seen: no fog of war. Recorded as an assumption in the spec. | assumption | M7 |
| 9 | The drone and hacking apps are placeholders that prove the hardware gate; the systems behind them are M7 and M6. | scope | M6, M7 |
| 10 | The pause freezes the whole sim. A fixture cannot hold a pause for many frozen steps unless it never resumes, because a paused sim only examines the next tick's queue: the client always submits for the next tick, which is correct, but it means a replay's pause is one step unless it ends paused. `m5-pause` does both. | note | none |
| 11 | The inventory app's rows are the container's order, which is spawn order; there is no sorting or filtering. At M5's item counts that is legible; a real loadout will want both. | scope | M6 |
| 12 | Time-to-complete assumes 0.35 s a press. The presses and sim ticks are measured; the seconds are that assumption applied. The Deck feel run is where a real hand replaces it. | assumption | G5 review |
| 13 | The M1 range demo still runs on wall time (G3 debt 8, G4 debt 13); untouched. | residue | M6 |
| 14 | Mutation testing not run; target G6. | scope | G6 |

## 5. The four standing questions

**Q1 — Does it function?** Yes, on the Deck: 238 tests, three 10 000-case properties
and two generated-stream properties for the new systems, three fixtures reproduced
across processes with their timings asserted, every device task measured, the Steam
client reached. The hand-played feel run is outstanding.

**Q2 — Is it secure?** New untrusted inputs are five content kinds (schema-checked at
build; app requirements, quest rewards and stance-free references checked at
assembly) and seven command kinds (exact payloads, ranges, ownership; 38 corpus
cases). The pause cannot be used to act while the world is frozen: only the
device's own commands dispatch, and every one of them is refused unless the actor
holds what it names. One new binary dependency, pinned by hash, with its licence and
size recorded; the game runs with Steam absent.

**Q3 — Is it complete?** Every claim is delivered; no stubs or `TODO`s in a shipped
path. The drone and hacking panes say plainly what they are waiting for. Debt items
are scheduled.

**Q4 — Is it expandable?** Performed: the extension commit adds an app with no
hardware requirement, a module and the app gated on it, and a third quest, in four
content files, two view scenes and one registration line, with an empty `sim/` diff.
`docs/extending-device.md` records the procedure.

## 6. Sign-off

Approver: CEOGG
Date:
Outcome: ☐ Accepted   ☐ Accepted with conditions (list below)   ☐ Rejected
Conditions:

## 7. Deck run and feel notes — to be filled by CEOGG

Build: `tools/export.sh` output, installed via: ☐ sideload  ☐ Steam client (non-store)
Date:                    Battery / plugged:

| # | What felt wrong or right | Number changed (file, value) or debt item |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
