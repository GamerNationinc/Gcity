# Deck Verified self-assessment

Valve's four compatibility axes as gate criteria from M5 on (engineering standards
§8.4). Each row states the requirement, what we do, and the evidence a reviewer can
re-run. Assessed on the approver's Steam Deck (SteamOS, desktop mode, 1280×800),
2026-09-22, at the M5 gate.

## Input

| Requirement | Our answer | Evidence |
|---|---|---|
| Full controller support by default; every action reachable without changing a setting | Every world and device action has a controller binding in `project.godot`, and a Steam Input action manifest (`steam_input/game_actions.vdf`) declares the same two sets for the shipped layout. The three keyboard-only actions are debug: save, load and the Escape restart, and each has a controller route (a held View restarts; save and load are not player-facing). | `tests/client/test_input_glyphs.gd`: every `world_*` action has a Deck glyph, except the three named debug keys |
| Correct glyphs; mouse and keyboard glyphs hidden when they are not the active input | `client/input_glyphs.gd` draws prompts in the active device's own names, Deck (L1, R1, View, Menu, L4) or Xbox (LB, RB), keyboard names only after a key or mouse event. The controller type comes from Steam Input when Steam is up, from the hardware otherwise. | the same test; the HUD in `docs/gates/screenshots/M5-*.png` |
| On-screen keyboard where text is entered | No text entry exists: nothing in M5 asks the player to type. When one arrives (a save slot name), Steam's OSK is the hook. | debt, M6 |
| Default layout suits the hardware | The Deck layout drives device navigation from the right trackpad and puts the tactical reload and the overlay toggle on the back buttons, so no face button is spent on a debug action. | `steam_input/README.md` |

## Display

| Requirement | Our answer | Evidence |
|---|---|---|
| Native 1280×800 with good defaults | The project's design resolution is 1280×800; every capture in the gate packages is taken at it. | `project.godot`; the screenshots |
| Legible text | A minimum type size is enforced: 22 px body, 18 px secondary at 1280×800, on every device pane and its inline spans. | `tests/client/test_device_shell.gd::test_every_pane_meets_the_minimum_type_size` |
| No clipped or cut-off UI | The device is a fixed 896×560 panel centred in the viewport with a 24 px gutter; the world HUD is a single left-aligned column. | the screenshots |

## Seamlessness

| Requirement | Our answer | Evidence |
|---|---|---|
| No compatibility warnings, no launcher | Native Linux build from `tools/export.sh`; no launcher, no prompts before the game. | the export runs on the Deck from the M4 and M5 gate runs |
| Runs straight from a controller | The first frame is the world with the player in it: no menu to navigate. | the demo runs |

## System support

| Requirement | Our answer | Evidence |
|---|---|---|
| Runs on SteamOS | Every gate since G1 has been measured on the Deck itself. | `docs/gates/M4-gate.md` §2, this package's §2 |
| Middleware supported | One binary dependency, GodotSteam, pinned by hash with Linux x86-64 libraries; it loads in the pinned engine and reaches the Steam client on the Deck. | `docs/dependencies.md`; `tools/steam_probe.gd` |
| Cloud saves defined | The M2 file set (`docs/steam-cloud.md`) is what the Steamworks cloud configuration will point at; the client already writes it. | `docs/steam-cloud.md` |

## Not yet assessable

The axes Valve scores against a **Steam install** need the app id CEOGG registers
(standards §12 item 4): the shipped layout cannot be bound to an app under Valve's
test id, so `getActionSetHandle` resolves to nothing today and the input map is the
fallback. Everything above holds either way; binding the layout and re-running
`tools/steam_probe.gd` is the first item of the G6 Deck run.
