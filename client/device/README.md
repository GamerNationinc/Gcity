# `client/device`

The personal device: shell plus apps. A client of the sim, never a store (design doc §12;
M5 spec claims 3–5, 8, 18).

| File | What |
|---|---|
| `device_shell.gd` | `DeviceShell`: the app strip, the secure indicator, the open pane and its prompts. Apps are `content/device_app/` entries whose `requires` tag the carried device's modules provide; views are registered by id (`register_view`). `refresh` rebuilds from the sim and returns whether anything changed, so the world view's `SubViewport` redraws only then. |
| `device_app.gd` | `DeviceApp`: the pane base. `refresh(sim, player) -> bool`, `handle(action, sim, player) -> bool`, `prompts(glyphs)`; `submit` and `note` reach the shell. |
| `apps/*_app.gd` + `.tscn` | The five M5 panes: inventory (every button an item command), map (top down, north up, centred on you), quests (accept, abandon, objectives), comms (the squads' radio state), drone (the hardware-gated placeholder). |

**Allowed imports:** `sim/` and `client/`.

**Holds no state:** `tools/check_dependencies.py` rule 4 refuses a class-level `var`
under this directory that is not a node, a scene, a callable, a string or an allow-listed
piece of view state (a cursor, the open app, the last drawn text, the map's draw cache).

**Raised and lowered** by the world view (`world_device`: View / I; a held View restarts).
Raising where the land says `safe` submits `sim.pause`; lowering submits `sim.resume`.

**Introduced at:** M5. Extension: [docs/extending-device.md](../../docs/extending-device.md).
