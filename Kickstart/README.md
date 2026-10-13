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
| The dirt | a model, with its outline as static chain bodies of a couple of hundred points each |
| Fork, swingarm and a rider who moves | 3D parts parented to the bodies; the script solves two-bone reaches for arms and legs every frame |
| Tricks | the same reaches, to other places: a pose is where the hips, hands and feet go |
| Dirt off the rear wheel that lands on the track | `ParticleSystem` with Collide 2D |
| Four riders under floodlights | forward rendering, a shadow-casting directional light, models with their own colours |
| A stand full of people | three crowd models set side by side - the engine draws repeats of a model together |
| One engine sound for every speed | an `AudioSource` loop whose pitch follows the revs |
| Position, time, score, the pedals | a UI canvas over the 3D scene; `ui.isHeld` for several thumbs at once |
| English and Portuguese, best times | `lang` / `tr`, `store` |

## How it is made

Everything is made by scripts, and placed with the editor's own commands:

```bash
blender --background --python tools/make_bike.py -- <work>          # bike and rider, in parts (BIKE_PAINT / BIKE_JERSEY / BIKE_SUFFIX for a rider's colours)
python3 tools/make_textures.py                                      # boards and banners
blender --background --python tools/make_track.py -- <work> art/textures      # the dirt, from a list of obstacles
blender --background --python tools/make_stadium.py -- <work> art/textures    # stands, crowd, barriers, lights
python3 tools/make_sounds.py /path/to/kenney                        # the engine loop is made here
# start PyrosBuilder, then:
python3 tools/build_game.py <work>                                  # the title and the three tracks
```

A track is a list of obstacles in `tools/make_track.py` - rollers, tabletops,
kickers and the hills they land on, whoops, steps - and changing a number and
running the three commands again is how one is tuned. The rules are one
script, `assets/lua/kickstart/game.lua`. **P** in a race puts your own bike on
its autopilot, which is how a track is checked to be one that can be ridden.

## Credits

The bike, the rider, the stadium and the tracks are modelled by the scripts
here. Dirt textures: [Poly Haven](https://polyhaven.com) (CC0). Font and
interface art: [Kenney](https://kenney.nl) (CC0). Sound effects: Kenney
(CC0); the engine, the crowd and the start beeps are generated.
