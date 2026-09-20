# Extending: stats and modifiers

The minimal diff for each thing the stat resolver (`sim/progression/stat_resolver.gd`)
can be extended with. Design doc §10.2 and §10.3; M1 spec claims 1–5. Skills and perks
join this file when their systems land.

## A new stat: one file

Create `content/stat/<id>.json`:

```json
{
	"schema_version": 1,
	"default_base": 0,
	"description": "What the number means and its unit (milli-units)."
}
```

`tools/validate_content.py` checks it against `tools/content_schemas/stat.json` at
build time; `SimAssembly.build()` registers it with the resolver at startup. Zero code.
Any system may then `resolve(entity, &"<id>")`, `set_base(entity, &"<id>", value)` or
attach modifiers to it. Removing the file removes the stat; anything still resolving it
gets `0` and a loud error, which the tests catch.

Values are integers in milli-units (34.5 is `34500`). Percentages are basis points of a
percent where that is what the stat means (see `hit_chance`).

## A new modifier: one dictionary

```gdscript
var handle: int = stats.add_modifier(entity, {
	"stat": &"damage", "class": &"mul", "value": 1000,
	"source": &"perk.handgun_focus", "tags": [&"weapon_class.handgun"],
})
# ... later
stats.remove_modifier(handle)
```

- `class` is `&"add"` (flat, milli-units) or `&"mul"` (basis points; `1000` is +10 %).
  Modifiers of one class sum; `(base + Σadd) × (10 000 + Σmul) / 10 000`, truncated once.
- `source` is an id-like `StringName` naming what contributed the modifier; it is state
  and shows up in snapshots, so name it by owning system: `&"perk.handgun_focus"`,
  `&"part.compensator"`.
- `tags` (optional) make the modifier reach entities that inherit from this one and
  carry a matching tag: a perk on an actor tagged `weapon_class.handgun` applies to the
  wielded pistol (`set_tags(pistol, [...])`, `set_inherits(pistol, actor)`) and not to
  the wielded crowbar. Untagged modifiers apply to their own entity only.
- The return value is `-1`, with an error, for any malformed input. Command handlers
  validate payloads before they get here; a `-1` in sim code is a programming error.

Perks, weapon parts, ammo, cyberware and buffs are all this one call with different
`source`s. There is no other way to change a number.

## A new modifier class: one registration call

Only when a new *kind of arithmetic* is needed, which should be rare. The class must be
commutative within itself (the resolver sums its modifiers) and its fold a pure function:

```gdscript
# in the system that owns the semantics, at assembly time
var err: Error = stats.register_modifier_class(&"floor", 200,
	func(acc: int, sum: int) -> int: return maxi(acc, sum))
```

`order` decides where the class folds relative to the others (`add` is 0, `mul` is 100).
The class id and order are part of the snapshot; the callable is code and therefore the
same for every run. `tests/progression/test_stat_resolver.gd::test_extension_a_new_class_is_a_registration_call`
is the performed instance. Nothing under `sim/progression/stat_resolver.gd` changes.

## What you may not do

- Read a base or a modifier directly to compute a gameplay number. Everything goes
  through `resolve()`.
- Mutate a base to apply an effect. Effects are modifiers; bases change only when the
  thing itself changes (a different frame, a different round).
- Encode a stat, class or tag as an enum or a `match` arm. They are registry entries.
- Store a resolved value anywhere in sim state. Resolve again; it is cached.
