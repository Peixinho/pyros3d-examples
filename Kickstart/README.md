# Kickstart

Motocross, seen from the side, in 3D: four riders, a stadium, a dirt track of
big jumps, and tricks in the air. Three tracks - Rookie Park, Rhythm Section,
Big Air - against three rivals, with your best time kept for each.

**Play it in a browser:** https://peixinho.github.io/pyros3d-examples/kickstart/
(works on a phone - turn it sideways; on an iPhone, *Share > Add to Home
Screen* opens it full screen). Best times are kept on the device.

Keys: **W** gas, **S** brake, **A / D** lean back and forward (in the air that
turns the bike: a whole turn is a flip). In the air, **J** is a Superman, **K**
a no-hander, **L** a can-can - let go before you land. A clean landing after a
trick or a flip scores, and gives a burst of speed; landing mid-trick is a
bail. **R** sets the bike back on its wheels. A gamepad works; on a phone the
pedals and a trick button appear when the screen is touched.

## What it shows

| In the game | What it is in the engine |
| --- | --- |
| Bikes that pitch, wheelie, bottom out and flip | 2D physics in a 3D scene: a chassis and two wheels as `Physics2D` bodies in the plane of the screen |
| Suspension | `Joint2D` wheel joints: free to turn, sprung along one line, with limits |
| The engine, the brakes, the rider's weight | torques (`applyTorque`) on the wheel and, the other way, on the frame |
| Bikes that pass through each other but all ride the dirt | collision layers: a layer a bike, each colliding only with the ground's |
| The dirt | an `Extrusion2D`: an outline given depth, textured, with its collider kept along it - **drag its points in the editor to reshape the track** |
| Fork, swingarm and a rider who moves | 3D parts parented to the bodies; the script solves two-bone reaches for arms and legs every frame |
| Tricks | the same reaches, to other places: a pose is where the hips, hands and feet go |
| Dirt off the rear wheel that lands on the track | `ParticleSystem` with Collide 2D |
| Four riders under floodlights | forward rendering, a shadow-casting directional light, models with their own colours |
| A stand full of people | three crowd models set side by side - the engine draws repeats of a model together |
| One engine sound for every speed | an `AudioSource` loop whose pitch follows the revs |
| Position, time, score, the pedals | a UI canvas over the 3D scene; `ui.isHeld` for several thumbs at once |
| English and Portuguese, best times | `lang` / `tr`, `store` |

## Changing it in the editor

Open a track scene (`scenes/Track1.json`), select **Track**, and tick **Edit
Outline** in its Extrusion 2D panel: the track's points appear in the view.
Drag one to raise a jump or lengthen a landing; Shift-click on the line to add
a point, Alt-click one to remove it. The dirt and what the wheels touch both
follow. **Start** and **Finish** are objects - move them and the race moves.
The bikes are bodies and joints you can select and retune; the rules are one
script, `assets/lua/kickstart/game.lua`. **P** in a race puts your own bike on
its autopilot, a quick way to see whether a reshaped track can still be ridden.

## How it was made

The models and the first shape of each track come from scripts, placed with
the editor's own commands:

```bash
blender --background --python tools/make_bike.py -- <work>          # bike and rider, in parts (BIKE_PAINT / BIKE_JERSEY / BIKE_SUFFIX for a rider's colours)
python3 tools/make_textures.py                                      # boards and banners
python3 tools/make_track.py <work>                                  # each track's outline, from a list of obstacles
blender --background --python tools/make_stadium.py -- <work> art/textures    # stands, crowd, barriers, lights, the start and finish boards
python3 tools/make_sounds.py /path/to/kenney                        # the engine loop is made here
# start PyrosBuilder, then:
python3 tools/build_game.py <work>                                  # the title and the three tracks
```

## Credits

The bike, the rider and the stadium are modelled by the scripts here. Dirt textures: [Poly Haven](https://polyhaven.com) (CC0). Font and
interface art: [Kenney](https://kenney.nl) (CC0). Sound effects: Kenney
(CC0); the engine, the crowd and the start beeps are generated.
