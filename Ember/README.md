# Ember

A 2D platformer where you play the Pyros logo. Open the project and press
Play.

Your flame is your health, your light and your clock, all at once. It burns
down on its own, ember shards feed it, frostlings eat it, and the mid-air
flare jump spends it — so being bright enough to see the next ledge is the
same resource as being able to reach it. Light the five torches on the way
(each is a checkpoint), and light the brazier at the end.

| Keys | |
| --- | --- |
| **A / D** or **← / →** | move |
| **Space**, **W** or **↑** | jump — hold for height, release early to cut it short |
| **Space** again, in the air | **flare**: a second jump that burns fuel |
| **R** | give up and go back to the last lit torch |

Land on a frostling to melt it. Walk into one and it takes a bite out of your
flame. Fall in the cold and you go out.

## What it shows

| What you see | Feature |
| --- | --- |
| Hills, ridges and a burning volcano drifting at different rates | **Layer2D parallax** — five layers at 0.04 / 0.25 / 0.55 / 1.0 / 1.18, driven from `world.lua` |
| Ember flickers, leans into a run, stretches off a jump, squashes on landing | **Spritesheet animation** — four sheets sliced in the editor, one per state, plus scale-driven squash and stretch |
| The dark is real; you carry the only warm light in it | **2D lighting** — every gameplay sprite is 2D-lit, and Ember's own PointLight scales with how much fuel he has left |
| Hard shadows off the pillars | **Occluder2D** — five of them, which is most of the scene's 32-segment budget |
| Crates topple, platforms carry you, the lift lifts | **Box2D** — a dynamic body for Ember, static floors, kinematic movers, and dynamic crates |
| Spark trail, jump dust, melt steam, the brazier going up | **Particles** — one trail emitter authored in the scene, three one-shot emitters built by the script |
| Flame meter, ember count, titles, the hit and death washes | **UI canvas** — authored in the editor, driven by `ui.setFill` / `ui.setText` / `ui.setTint` |
| Music, footsteps, the whoosh of a flare, the hiss of going out | **Audio** — a looping AudioSource in the scene plus a ten-sound `Sound` bank |

Every asset is generated, nothing is licensed: the hero is the Pyros logo
warped frame by frame, the rest is drawn with a few hundred lines of PIL, and
the music and the sound effects are synthesised as raw WAV. The scripts that
make all of it are in [`tools/`](tools) - see that folder's README.

## Notes for anyone reading the code

- **The level is in `Ember.json`, not in the script.** `world.lua` walks the
  scene once and finds the floors by their `Physics2D` half-extents, the
  checkpoints by their torch lights, and each frostling's patrol from the
  platform it was placed on. Move a platform in the editor and the patrol,
  the ground test and the camera all move with it. The only thing the script
  states itself is where the two moving platforms travel to.

- **Box2D's gravity is -10, which at this scale is a moon.** Vertical motion
  is re-integrated in `player.lua` every frame (`RISE_G` 40 up, `FALL_G` 56
  down, `HANG_G` 26 near the apex) — that is what gives the jump an arc you
  can feel, and what makes it variable-height and cuttable.

- **Overlaps are tested against a swept band, not a position.** The physics
  runs a fixed 60 Hz step and catches up to eight of them in one frame, so a
  fast fall moves two metres between two script frames. Testing "is he on top
  of the frostling right now" turns every stomp into a hit; testing the range
  of heights he passed through does not.

- **The camera's X is the engine's, its Y is the game's.** `view.follow()`
  handles the horizontal with lag and bounds. Vertically the script holds the
  height of the floor Ember last stood on, so jumping does not take the
  ground off the bottom of the screen.
