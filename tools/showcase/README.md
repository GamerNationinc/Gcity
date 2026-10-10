# `tools/showcase`

Pictures of sim work for a reader who does not read code (CLAUDE.md §13). A scenario is
a small script with `title()`, `content(db)`, `setup(sim, view)`, `before_tick(sim, view,
tick)`, `ticks_per_frame(tick)`, `end_tick()` and `caption(tick)`. It stages a situation
through the sim's own API and commands; the renderer draws what the sim holds.

```
tools/showcase.sh standing out.gif     # GIF + out-last.png
```

Conventions, from a review of how studios show systems work to non-programmers (Unreal
Gameplay Debugger categories, stealth-AI perception views, milestone review practice):

- one sentence of caption per phase, about what the player notices, never the code;
- the same colours everywhere: blue player, green unaware, amber suspicious, red
  alerted; a fixed legend in the corner;
- short labels on things in the world (name, state, heat), not a wall of numbers;
- a "what just happened" feed so a number that moves always has a visible reason;
- fast-forward is labelled as such; frames step the sim, so a run is reproducible.
