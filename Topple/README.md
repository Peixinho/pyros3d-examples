# Topple

A physics toy with a sling: fling round aliens at towers of wood, glass, stone
and metal until none of the square ones is left. A hundred levels in five
worlds - a meadow, a desert, a grove at night, a keep in the snow, and the
same country by moonlight - and a title screen that plays itself. Made to be
easy: every level leaves shots to spare, and one that will not fall can be
skipped.

**Play it in a browser:** https://peixinho.github.io/pyros3d-examples/topple/
(works on a phone - turn it sideways; on an iPhone, *Share > Add to Home
Screen* opens it full screen). Stars and best scores are kept on the device.

Drag the alien back and let go. Some shots do something when you tap again
while they fly: yellow speeds up, blue becomes three, pink goes off.

## What it shows

| In the game | What it is in the engine |
| --- | --- |
| A hundred levels, each one file | prefabs: a level is `assets/prefabs/L001.prefab`, put into its world's scene by `Prefab.instantiate` |
| Blocks that chip, crack and break | `Sprite2D` frames from one packed atlas; `Physics2D` bodies and `onContact` (how hard, and where) |
| Every block shaded by the lamps, and standing in their way | 2D point lights, a normal map for the whole atlas, bodies that cast 2D shadows |
| Lamps and a wrecking ball on ropes; a mill | `Joint2D`: distance, hinge with a motor, ignore |
| Ropes and the sling's bands | `Line2D`, two points each, moved by the script |
| The streak behind a shot | `Line2D` as a trail |
| The aiming dots | a `SpriteBatch2D`: twenty-eight sprites, one draw |
| Skies, hills, trees, grass in front | five `Layer2D` parallax layers the engine scrolls |
| Dust, splinters, stars, fire and smoke | `ParticleSystem` bursts (additive and alpha) |
| A view that looks at the targets, then the sling, then follows the shot | the scene's own 2D view, driven from script |
| Score, hints, the end-of-level card, the worlds and their level grid | a canvas of UI elements, nine-sliced buttons, distance-field text |
| Stars and best scores that are still there tomorrow | `store.read` / `store.write` (a file on a desktop, local storage in a browser) |
| Forty sounds | `Sound`, several voices each |

Everything was placed with the editor's own commands, and opens in it:
`scenes/World1..5.json` are the five stages (sky, ground, sling, interface),
`scenes/Title.json` the menu, and each level is a prefab - drag one into a
world's scene to see or change it. The rules are one script,
`assets/lua/topple/game.lua`, which reads a level by its objects' names
(`B_wood_plank_3` is a wooden plank, `T_green_1` a target, `A_blue_2` the
second shot).

Keys, for trying things: **R** starts the level again, **K** breaks whatever
is under the pointer, and on the title **F9** (or **B** held for a second)
has the game play every level itself and write down how each went - which is
how the hundred were checked to be winnable.

## Building it again

```
python3 tools/make_assets.py /path/to/unzipped/kenney   # picks the art and sounds (Pillow, ffmpeg)
# start PyrosBuilder, then:
python3 tools/build_levels.py                           # atlases, the title, the five worlds, the hundred levels
python3 tools/build_levels.py levels 41 60              # or some of them
```

The levels are laid out by `design()` in that script from a few kinds of
building; the number is the seed, so a level comes out the same each time.
*Build > Platform: web* makes the browser version.

## Credits

All art and sound is by **Kenney** (www.kenney.nl), public domain (CC0):
Physics Assets, Background Elements, Particle Pack, UI Pack, Impact Sounds,
Interface Sounds, Sci-Fi Sounds, RPG Audio, Digital Audio, Music Jingles and
Kenney Fonts. The normal map (`assets/textures/pieces_n.png`) is generated
from that art by `tools/make_normals.py`.
