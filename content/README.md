# `content/`

Data files only: weapons, perks, modules, districts, town templates, quests. Systems
are few and generic; content is many and dumb (design doc §1.1, pillar 4).

Rules, enforced by `tools/validate_content.py` in CI:

- Layout is `content/<kind>/<id>.json`. `<kind>` names a schema registered under
  `tools/content_schemas/<kind>.json`; a file whose kind has no schema fails the build.
- Every file carries an integer `schema_version` (standards §6.3).
- No scripts or scenes. Content that needs behaviour is an event hook registered from
  code, and that category is kept deliberately small (design doc §10.3).

No content exists at M0. The first kind (weapon frames and parts) arrives with M1.
