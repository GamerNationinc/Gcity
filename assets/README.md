# assets/

Art and audio source-of-truth for the client. The sim never reads anything in here
(dependency rule, CLAUDE.md §5): a model is presentation for state the sim already
holds. Deleting this whole directory must change nothing but what the screen shows.

## Layout

```
assets/
  concepts/          reference art: concept sheets, palettes, mood boards (PNG/JPG)
  models/
    agents/          one .glb per agent_profile id: assets/models/agents/<id>.glb
```

New kinds of asset (props, buildings, audio) add a sibling directory here with the
same convention-over-mapping rule: the file name is the content id it dresses.

## Conventions

- **Naming**: file name equals the content id it belongs to, `[a-z0-9_]+`, same as
  `content/` (CLAUDE.md §11). `assets/models/agents/op_heavy.glb` dresses
  `content/agent_profile/op_heavy.json`.
- **Lookup is by convention, not by table.** The client tries
  `res://assets/models/agents/<profile>.glb`; if it is missing, the actor renders as
  the grey-box capsule. Adding a variant is a content file plus a .glb — no code.
- **Orientation**: models face **+X** at rest (the capsule's nose direction), origin
  at the **mesh centre, 0.9 m above the feet** — the client places actor nodes at
  y = 0.9 with the same rotation math as the capsules.
- **StanceChip**: every agent model contains one mesh node named `StanceChip` (the
  visor/goggle bar). The client tints it with the stance colour each frame, replacing
  the whole-body stance tint the capsules used. Everything else keeps its palette.
- **Format**: .glb (binary glTF 2.0), vertex positions + normals + per-primitive
  base-colour materials. No textures at the placeholder stage; palette lives in
  material `baseColorFactor`s. Commit the generated `.import` files beside the .glb
  (as with `icon.svg.import`) so headless runs need no editor pass.
- **Generated placeholders**: current agent models are built by
  `tools/asset_gen/gen_operator_models.py` (Python stdlib only — no dependency to
  pin). Regenerate with `python3 tools/asset_gen/gen_operator_models.py` and commit
  the result. Hand-authored replacements later simply overwrite the .glb; the
  conventions above are the contract they must keep.

## Deck budgets (placeholder stage)

Standards §4 applies: the Deck numbers are the only numbers. Until a profile capture
says otherwise, agent placeholders stay within:

| Budget | Limit |
|---|---|
| Triangles per agent model | ≤ 2,000 |
| Materials per agent model | ≤ 6 |
| Textures | none (base-colour materials only) |
| .glb file size | ≤ 256 KiB |
| Skeleton / animation | none yet — actors are rigid, rotated whole, as the capsules were |

Raising a budget is a measured decision: profile on Deck first (standards §4.2),
then change this table in the same commit as the asset that needed it.
