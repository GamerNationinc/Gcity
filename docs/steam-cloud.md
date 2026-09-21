# Steam Cloud file set

Defined at M2, when the save format was first written (engineering standards §8.5;
M2 spec claim 18). No Steam API is called at M2: this is the file layout GodotSteam's
cloud configuration points at from M5.

## What syncs

One slot per world under the user data directory (`user://` in Godot terms):

| Path | Content | Written by |
|---|---|---|
| `user://saves/<slot>/world.json` | The save: `SaveFile.serialize()` of the root snapshot, i.e. world seed + overlay (design doc §5.6). Kilobytes to low megabytes. | the client, on an explicit save |
| `user://saves/<slot>/meta.json` | `{schema_version, seed, tick, last_played_unix, game_version, content_digest, save_schema_version}`: enough to list slots and detect conflicts without parsing the world. | the client, with `world.json` |
| `user://settings.json` | Player settings (bindings, accessibility, video). | the client |

`<slot>` is `[a-z0-9_]{1,32}`. Both files of a slot are written together, `world.json`
first; a slot with a `meta.json` whose `tick` or `seed` disagrees with `world.json`
is treated as corrupt (the world file wins for loading, and the mismatch is reported).

## What does not sync

- Replay recordings and fixtures: development artefacts, potentially large.
- Telemetry and path-trace heatmaps (design doc §6.4): local-first, aggregate,
  never uploaded by the save path.
- Logs, crash dumps, screenshots.

## Conflicts

Steam Cloud can present two versions of a slot (played on two machines while
offline). The rule (standards §8.5): **never silently pick one.** The client keeps
both, renames the non-local one to `<slot>.conflict-<unix time>`, and shows a choice
with each version's `meta.json` (tick, last played, game version). The sim is never
involved; a conflict is a client and platform matter.

## Trust

Cloud payloads are untrusted, exactly like local saves (standards §5.1): everything
goes through `SaveFile.parse()` and `SimAssembly.load_save()`, which validate the
envelope, every system's state and the root before anything is applied, and refuse a
save made over different content (`content_digest`).

## Size budget

The M2 populated-sim save is under 64 KiB (asserted by
`tests/sim/test_save_file.gd`). Steam Cloud's per-user quota is configured per app in
Steamworks; the app's quota and file count are set at M5 with the binding, and the
file count here is deliberately three per slot plus one.
