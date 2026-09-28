# M8 — Look and feel: specification

Milestone M8 of `docs/gcity-design.md` §16, **proposed as a new milestone** ahead of the
threat director. Written before implementation (standards §2.1, §10.2). Status:
**proposed** (Claude Code, 2026-09-27), for CEOGG's approval.

**Why this milestone exists.** Eight milestones have built the simulation: stats, land,
building, the portal graph, perception AI, the device, a stealth mission with three
routes, and a generated world with roads, towns, patrols and bound sites. 425 tests
and 24 replay fixtures prove it behaves. None of those milestones was allowed to spend
anything on what the player sees or hears, and it shows: guards are capsules, pieces are
untextured boxes, the wilds are flat-shaded rock, the HUD is debug text, and there is no
sound at all. M6 was called the playable vertical slice. It is playable; it is not yet a
slice of a game anyone would recognise. The design doc's build order (§16) goes straight
on to the threat director, which would put a sixth invisible system under the same
capsules. This milestone puts presentation in front of it instead, while there is still
only one mission to dress.

**Preconditions.** G7 is signed. **ADR-011** (art direction and asset sourcing,
proposed with this spec) is accepted: claims 3–13 depend on it, and CLAUDE.md does not
let an open ADR be guessed around. The reorder in §16 below is approved.

**The claim of the milestone.** Someone watching thirty seconds of the Deck playing the
Cold Storage mission sees and hears a game, not a test harness, **and the simulation is
exactly the one G7 signed**: M8 is presentation only. Every one of the 24 replay fixtures
reproduces its G7 hash unchanged at the M8 gate, and the diff under `sim/` is empty.
That is what makes a milestone this visual checkable: it can make everything look
different, and it cannot make anything behave differently.

**What this milestone is not.** It is not new systems, new missions or new content
volume. It is not Red Dead Redemption 2: that is the long-run bar (M7 spec, open points),
and this milestone must not foreclose it, but it does not reach for it. It is not
weather, a day/night cycle as sim state, or tall vegetation (claim 9 says why).

**Size.** Larger than M6 in files, smaller in logic: most of it is assets, shaders,
scenes and client code reading sim state that already exists. It is ordered so the
first two claims pay for everything after them.

**Hardware.** Visual work needs a GPU and a real display. Development moves to the
gaming laptop (the Deck's 80-minute suite and 14 GB shared memory were the main source of
lost time in M7); **the Deck remains the only machine whose numbers count** (standards
§4.2), and claim 14 is measured there.

## Claims

### Faster to change (`tools/`, `tests/`)

1. **A fast suite for every commit, the full suite for gates.** `tools/test.sh quick`
   runs every test with each 10 000-case property cut to a sample (environment
   `GCITY_PROPERTY_CASES`, default 10 000, `quick` sets 500), and runs test files in
   parallel across cores (`tools/run_parallel.py`, one engine process per file, logs
   merged and checked by the existing `tools/check_test_log.py`). The full 10 000-case
   run is required at every gate and runs nightly. Target: the quick suite under 10
   minutes on the development machine. **Standards amendment, proposed:** §3.2's 10 000
   cases apply to gate and nightly runs, not to every commit. Mutation testing already
   runs "periodically, not per commit" (§3.6) and stays that way.
2. **Presentation has its own quick check.** `tools/look.sh` captures a fixed set of
   views (the city street, the gate, the road out, a guard close up, the server room,
   the device open) as PNGs from scripted camera positions on a fixed seed, so a change
   to how anything looks is reviewed by looking at six pictures, not by launching the
   game. The set is the evidence for claims 3–12 and goes in the gate package.

### The look (`client/`, `assets/`)

3. **An art direction, written down.** `docs/art-direction.md`: palette (city and wilds
   separately), shape language, material vocabulary, lighting mood per region, UI style,
   and three reference boards. Everything after this claim is checked against it. The
   direction itself is ADR-011's decision.
4. **Assets are dependencies.** Every file under `assets/` is listed in
   `assets/MANIFEST.md` with its source, author, licence and SHA-256, and a new fitness
   function (`tools/check_assets.py`) fails the build for a file that is not listed, a
   hash that does not match, or a licence not on the allowed list (ADR-011). Per-asset
   budgets are checked in the same pass: triangles per character and per prop, texture
   size, audio length. Standards §5.4 already says this of code; M8 makes it true of art.
5. **Characters are people.** The player and the guards are rigged humanoid models with
   an animation set — idle, walk, run, crouch, climb, aim, fire, reload, hit, fall,
   death — driven by an `AnimationTree` from sim state that already exists (stance,
   position change per tick, wielded weapon, aim, health events). Factions are
   distinguishable at 20 m on the Deck's screen by silhouette and colour, not by a label
   (pillar 3, legibility). The capsule stays as a debug view.
6. **Motion is smooth.** The client interpolates every actor's transform between sim
   ticks (the sim stays at its fixed tick, ADR-002); the camera is a third-person spring
   arm with collision, a shoulder swap, and the first-person toggle the design doc names
   (§1). Nothing the camera does is sim state.
7. **The build is made of materials.** Every `build_piece` renders with a mesh and PBR
   material for its `material` (concrete, metal, glass, wood …), chosen by a look file
   `assets/looks/material/<id>.tres` keyed by the content id rather than by code, so a
   new material's look is a file. **Looks live under `assets/`, never in `content/`**:
   the content digest is hashed into the sim state (G6 debt 11), so a presentation field
   in a content file would move every fixture hash and break claim 13. Cold Storage and
   the fixer's office are dressed with non-colliding props only.
8. **Light and air.** A `WorldEnvironment` per region: sky, sun and shadows, fog and
   distance haze, ambient occlusion within budget, a filmic tonemap and a colour grade.
   The gate's load window becomes a proper transition. Time of day is a fixed preset
   per scene in M8; a clock as sim state belongs to the environment milestones.
9. **The wilds have a surface.** Terrain chunks are shaded by a triplanar material that
   blends by slope and by the biome the sim already reports per slot, roads get their
   own surface, and **ground-hugging scatter** (grass, pebbles, low scrub) is placed on
   the client from the seed. Scatter is deliberately limited to things below knee
   height: anything tall enough to hide a guard would be cover the player can see but
   the sim's perception cannot, and a loss behind a bush that did not block sight would
   not be readable as the player's mistake (pillar 3). Tall vegetation needs sim
   occlusion and belongs to the environment milestones.

### The feel (`client/`)

10. **Shooting reads.** Muzzle flash, tracer, recoil camera kick, impact effects and
    decals by surface, a hit marker, and a hit reaction on the target — each a
    presentation of a combat event the sim already emits (`combat.fire`, `combat.hit`).
    `time_to_first_shot` (G4) is re-checked unchanged: feel is added on top, never by
    retuning the sim.
11. **Sound.** Footsteps by surface, gunshots with distance falloff and a
    region-appropriate reverb, city and wilds ambience, the gate, the device's UI, the
    hack in progress. Audio buses with a budget. Sound tells the truth about the sim: a gunshot or a
    breach is audible to the player at least as far as the sim's hearing carries it
    (60 m for a guard today), so a guard reacting to a noise is never reacting to one
    the player could not have heard.
12. **A HUD and a front door.** The debug text becomes a debug overlay behind a flag;
    the HUD shows health, weapon and magazine, stance, and a detection indicator that
    reads perception's alert state — the legibility pillar's most direct tool. A title
    screen with continue, new game, settings (look sensitivity, FOV, invert, volumes,
    subtitles for the device) and quit; a pause menu. Launching the export starts the
    game, not a flag. Everything legible at 1280×800 handheld (G5's bar, re-checked).

### Verification

13. **The sim did not move.** All 24 replay fixtures reproduce their G7 hashes
    unchanged; `git diff --stat <G7 sign-off>..HEAD -- sim/` is empty. A claim that
    needs a sim change is not an M8 claim: it goes to the debt log with the reason.
14. **It holds 40 fps on the Deck with the look on.** `--mission --demo` and a `--wilds`
    walk captured on the Deck, plugged and on battery: 1 % low ≥ 40 fps; 0.1 % low
    recorded; render submission within its 8.0 ms (§4.1); a 30-minute thermal soak
    reporting the final five minutes (§4.2). If the look cannot hold the frame rate, the
    look gives way — lower settings are the fallback, recorded as a deviation, never the
    frame rate.
15. **A look review.** The gate package carries the claim-2 view set, a two-minute Deck
    capture of the mission, and CEOGG's feel notes from a hand-played run, which M6 and
    M7 both went without.

## Order

Claims 1–2 first (every later claim is cheaper for them). Then 3–4 (nothing is built
before the direction and the manifest exist). Then 5–6 (characters and motion are most
of the difference). Then 7–9, 10–11, 12. Claims 13–15 are checked continuously and
closed at the gate.

## Out of scope (goes to the debt log if touched)

Any `sim/` change; new missions, factions, weapons or systems; the threat director and
raids (M9 under the proposed reorder); weather, a day/night clock, tall vegetation,
wildlife; facial animation and lip sync; cutscenes; voice acting; music beyond an
ambience bed; interiors of procedural settlements; multiplayer.

## Open points

- **Art direction is CEOGG's call** (ADR-011). The recommendation there is grounded
  near-future grit — a readable, slightly stylised realism that CC0 and stock assets can
  reach and the Deck can render — rather than photorealism, which neither the budget
  nor the asset sources can reach yet.
- **Asset sourcing is the schedule risk.** Free CC0 packs (characters, animation sets,
  props, textures, sounds) get the milestone moving and will not look unified until the
  art direction's palette and materials are applied over them. Anything bought or
  commissioned is a licence line in the manifest and CEOGG's spend.
- **Animation on a fixed-tick sim.** Actors move in tick-sized steps; claim 6's
  interpolation hides that at 40 fps, but a stance change that the sim applies in one
  tick needs a blend the client chooses. That is a client decision and stays one.
- **The Deck GPU.** Render submission has 8 ms. Shadows, AO and fog are the expensive
  items; claim 14 decides how much of each the Deck gets.

## Proposed change to the design doc (§16) and standards (§11)

- §16: insert **M8 — Look and feel** (this spec); the threat director and raids become
  **M9**. §11: the G8 row becomes this spec's claims 13–15; the current G8 row moves to
  G9 unchanged.
- §3.2: the 10 000-case rule applies to gate and nightly runs (claim 1).

## Extension exercise for Q4 (standards §11, G8)

Give a faction a new look — a different model, palette and set of sounds — and add a
new material for build pieces, using only files under `assets/` (looks for a faction and a
material that content already names). The diff under `client/`, `content/` and `sim/` is
empty, every fixture hash is unchanged, `tools/test.sh` passes, and `tools/look.sh`
shows both. `docs/extending-look.md` records the procedure.

## Assumptions to record in the gate

- Presentation reads sim state and events only; it never submits a command the player
  did not ask for.
- One art direction for the whole game; regions vary within it.
- The Deck at its default settings is the reference; higher settings on the laptop are
  a convenience, not evidence.
