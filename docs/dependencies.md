# Dependencies

Every dependency is pinned by exact version and hash, with its maintenance status,
licence and transitive size recorded (engineering standards §5.4). Adding one is a
spec claim, never a side effect.

| Dependency | Version | Pinned in | Hash | Licence | Size | Maintenance | Why |
|---|---|---|---|---|---|---|---|
| Godot Engine | 4.6.1-stable | `tools/godot.pin` | SHA-256 of the Linux editor zip; SHA-512 of the export templates | MIT | 150 MB editor, 900 MB templates (cached, not shipped) | active, stable branch | the engine (ADR-001) |
| GodotSteam GDExtension | 4.22.1 (godot-cpp 4.4, Steamworks SDK 1.65) | `tools/godotsteam.pin` | SHA-256 of the release zip `2b12b349…bfa8f` | MIT (binding); Valve's Steamworks SDK terms for `libsteam_api.so` / `steam_api64.dll`, redistributable with a Steam app | 27 MB zip; shipped: 5.0 MB Linux release library + 0.4 MB Steam API, 4.0 MB + 0.3 MB on Windows (the debug libraries are installed for the editor, not exported) | active: releases every few weeks against each Steamworks SDK; GDExtension builds carry `compatibility_minimum = 4.4` and load in 4.6.1 (verified on the Deck 2026-09-21: `steamInitEx(480)` status 0 with the Steam client running) | Steamworks binding (standards §8.2; M5 spec claim 10) |
| Python | 3.11+ standard library | none needed | none | PSF | none | the fitness functions and validators use the standard library only | `tools/` |

## What is deliberately not a dependency

- Any Godot addon or asset-library package other than the binding above.
- The GodotSteam editor self-updater the release zip ships with (`addons/godotsteam/editor/`,
  `plugin.cfg`): dropped by `tools/godotsteam.sh`, because a pinned dependency does not
  update itself.
- Xvfb: a container tool for `tools/screenshot.sh`; the Deck captures with the client's
  own `--screenshot` flag.

## Upgrading

Change every line of the pin file together, re-run the install script, run
`tools/test.sh` and the M5 Steam probe (`tools/steam_probe.gd`) on the Deck, and record
the new hash and any behaviour change in the commit.
