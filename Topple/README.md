# Topple

A physics toy: fling round aliens from a sling at towers of wood, glass, stone
and metal until none of the square ones is left standing. Four levels and a
title screen that plays itself.

**Play it in a browser:** https://peixinho.github.io/pyros3d-examples/topple/
(works on a phone - turn it sideways; on an iPhone, *Share > Add to Home
Screen* opens it full screen).

Drag the alien back and let go. Some shots do something when you tap again
while they fly: yellow speeds up, blue becomes three, pink goes off.

## What it shows

| In the game | What it is in the engine |
| --- | --- |
| Blocks that chip, crack and break | `Sprite2D` frames from one packed atlas; `Physics2D` bodies and `onContact` (how hard, and where) |
| Every block shaded by the lamps, and standing in their way | 2D point lights, a normal map for the whole atlas, bodies that cast 2D shadows |
| Lamps and a wrecking ball on ropes; a catapult; a mill; a trap on a pulley | `Joint2D`: distance, hinge with limits, hinge with a motor, pulley, ignore |
| Ropes and the sling's bands | `Line2D`, two points each, moved by the script |
| The streak behind a shot | `Line2D` as a trail |
| The aiming dots | a `SpriteBatch2D`: sixteen sprites, one draw |
| Skies, hills, trees, grass in front | five `Layer2D` parallax layers the engine scrolls |
| Dust, splinters, stars, fire and smoke | `ParticleSystem` bursts (additive and alpha) |
| A view that looks at the targets, then the sling, then follows the shot | the scene's own 2D view, driven from script |
| Score, hints, the end-of-level card, the level buttons | a canvas of UI elements, nine-sliced buttons, distance-field text |
| Forty sounds | `Sound`, several voices each |

Everything in a scene was placed with the editor's own commands - open any of
`scenes/*.json` in PyrosBuilder and move things about. The rules are one
script, `assets/lua/topple/game.lua`, which reads a scene by its objects'
names (`B_wood_plank_3` is a wooden plank, `T_green_1` a target, `A_blue_2`
the second shot). A level's own script is the three lines that differ.

**K** breaks whatever is under the pointer - not part of the game, but handy
for trying a level's machines. **R** starts the level again.

## Building it again

```
python3 tools/make_assets.py /path/to/unzipped/kenney   # picks the art and sounds (Pillow, ffmpeg)
# start PyrosBuilder, then:
python3 tools/build_levels.py                           # packs the atlases, builds every scene (Pillow, numpy)
```

`tools/build_levels.py Grove` rebuilds one scene. *Build > Platform: web*
makes the browser version.

## Credits

All art and sound is by **Kenney** (www.kenney.nl), public domain (CC0):
Physics Assets, Background Elements, Particle Pack, UI Pack, Impact Sounds,
Interface Sounds, Sci-Fi Sounds, RPG Audio, Digital Audio, Music Jingles and
Kenney Fonts. The normal map (`assets/textures/pieces_n.png`) is generated
from that art by `tools/make_normals.py`.
