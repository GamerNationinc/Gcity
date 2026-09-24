# `sim/items`

Item templates and instances, weapon frames and sockets, magazines as ordered
containers of round instances (design doc §11, §13.3; ADR-009).

| File | What |
|---|---|
| `item_system.gd` | `ItemSystem` (system id `items`): named containers, spawning from `weapon_frame` / `weapon_part` / `ammo` / `device_frame` / `device_module` / `currency` templates, attach/detach with resolver modifiers, load/unload, tactical and emergency reloads with auto-chambering and a busy window, corpse containers (`corpse.<id>`) and token containers (`token.<id>`, what a squad off-screen carries; M7 claim 12), both open like an inventory, and `move_container` as the one transfer death, looting and going off-screen are built from, money as ordinary items (`currency` notes with a `value` face stat, read back by `credits_in`), snapshot/restore with full validation. Owns the seven `item.*` / `magazine.*` / `weapon.*` command kinds. |

**Allowed imports:** `sim/` only.

**Introduced at:** M1 (one pistol). Modules follow at M2.

**Extension point:** [docs/extending-items.md](../../docs/extending-items.md).
