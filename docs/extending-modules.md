# Extending: structures and modules

The minimal diff for each thing the structure system (`sim/land/structure_system.gd`)
can be extended with. Design doc §8.1–8.4; ADR-005; M2 spec claims 8–12. The G2
extension exercise is a fourth module with a dependency and water, data only, empty
`sim/` diff.

## Vocabulary

- **Structure**: an owner-agnostic record on the land: template, origin position (mm),
  one of four rotations, the owner tag of whoever placed it, and its modules. Its
  power and heat budgets are stats on its entity (`power_available`, `heat_headroom`)
  with the template's budget as base.
- **Socket grid**: `cols × rows` cells on the template's `pitch`; a module occupies a
  `cols × rows` block from its `(col, row)` corner.
- **Module**: a record in the structure's `modules` map, plus two negative `add`
  modifiers on the structure's budget stats from source `module.<id>`. Removing the
  module removes exactly those modifiers, so headroom is restored exactly (the M1
  resolver invariant).

## A new module: one file

`content/module/<id>.json`:

```json
{
	"schema_version": 1,
	"description": "…",
	"footprint": {"cols": 3, "rows": 2},
	"mass": 210,
	"power_draw": 900,
	"heat_output": 700,
	"water_in": 40,
	"water_out": 30,
	"depends_on": ["work_station"],
	"emits": ["signal.power_draw", "signal.emissions"]
}
```

- `power_draw` in watts; negative supplies power. `heat_output` in watts.
- `water_in` / `water_out` are carried and validated at M2; a water budget is not
  a stat until a system needs one.
- `depends_on` names module kinds that must already be installed on the same
  structure; a cycle refuses to assemble. Removing the last module of a kind that
  another installed module depends on is rejected.
- `emits` lists signal types (`[a-z0-9][a-z0-9_.]*`) the threat director reads from M8.

`tests/land/test_extension_content.gd` installs every module after its dependencies
on an empty container and checks both budgets stay non-negative, so a module that
cannot fit or cannot be powered fails the build, not the playtest.

## A new structure kind: one file

`content/structure/<id>.json` with an axis-aligned `footprint` (`x`, `z`, `height` in
mm), a `sockets` grid and the two budgets. Every module must fit at least one
structure's grid or the content refuses to assemble.

## Commands (owned by the structure system)

| Kind | Payload | Effect |
|---|---|---|
| `structure.place` | `{actor, template, x, y, z, rotation}` | needs `build` at every footprint corner; footprints never overlap in volume |
| `module.install` | `{actor, structure, template, col, row}` | needs `build` at the structure; on-grid, free cells, dependencies installed, both budgets non-negative after |
| `module.remove` | `{actor, structure, module}` | needs `build`; refuses to orphan a dependant |

Every payload is exact: extra keys, wrong types, unknown ids and actors that do not
exist are rejected with no state change (`tests/fuzz/commands/hostile_payloads.json`).

## What you may not do

- Compute a budget anywhere but the resolver. `power_available()` is
  `resolve(structure, &"power_available")`, nothing else.
- Give a module behaviour in code. A work station that does work is an event hook
  registered by the system that owns the work, keyed by the module's kind; the module
  file stays numbers.
- Branch on a template name. Arcade containers, bunkers and shacks differ only in
  their files.
