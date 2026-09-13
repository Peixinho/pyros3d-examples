# Rossio

A wave-defence firefight in a Lisbon metro station.

The level is authored entirely in PyrosBuilder — geometry, deferred lights,
props, particle emitters, the enemy pool and the HUD canvas all live in
`scenes/Rossio.json`. The scene script (`scenes/Rossio.lua`) only runs the
game: it loads the Lua modules, ticks the wave director, and pushes numbers
into HUD elements that already exist.

## Open it

File > Browse Examples in PyrosBuilder, pick Rossio, Download. Or clone this
repo and use File > Open Project on `Rossio/project.json`.

The project is set to the **deferred** renderer.

## What is in here

| Path | What it is |
| --- | --- |
| `scenes/Rossio.json` | The station: the playable scene, and the project's startup scene |
| `scenes/Rossio.lua` | Scene main script — module wiring, wave director, HUD updates |
| `assets/lua/fps/` | The FPS modules: `player`, `weapon`, `enemies`, `game`, `config` |
| `assets/lua/ragdoll.lua` | Rig-agnostic ragdoll module — discovers whatever skeleton it is given |
| `assets/models/` | Station props, the enemy character and its animations |
| `scenes/*Test.json` | The small scenes each system was built in: animation, enemies, ragdolls |

The `*Test` scenes are kept deliberately. They are one system each, with
nothing else in the way, which makes them a better place to learn a subsystem
than the full level is.

## Controls

Mouse look, `WASD` to move, `Shift` to sprint, `Space` to jump, `C` to
crouch, left mouse to fire, `R` to reload, `Tab` to release the mouse.

## Engine features it exercises

Deferred rendering with many point lights · skeletal animation and blending ·
ragdoll physics on death · decals on impact · particle emitters for muzzle
flash, impacts and station atmosphere · a UI canvas HUD · Lua components and
a scene main script.
