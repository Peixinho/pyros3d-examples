# Hopper

A platformer: run, jump, climb, ride the logs across the water, find the key,
get to the flag. Fifty levels in five worlds - a meadow, dunes, a cavern lit
by torches, the frost, and a mushroom wood at dusk. Made to be easy: three
gems to find in every level, no game over, and a fall puts you back where you
last stood.

**Play it in a browser:** https://peixinho.github.io/pyros3d-examples/hopper/
(works on a phone - turn it sideways; on an iPhone, *Share > Add to Home
Screen* opens it full screen). Stars are kept on the device.

Keys: **A/D** or the arrows to run, **Space** to jump (hold it for a higher
one), **W/S** on a ladder, **S** to drop through a bridge, **R** to start the
level again. A gamepad works. On a phone a stick and a jump button appear the
first time the screen is touched.

## What it shows

| In the game | What it is in the engine |
| --- | --- |
| Ground whose corners and edges fit themselves | `TileMap2D` painted by **terrain**: sixteen tiles per terrain, the map picks by each cell's neighbours (`paint_terrain`) |
| Hills to walk up | tiles with a slope shape; one collider made from the map's solid cells |
| Bridges to stand on, walk under and jump up through | a second tile map whose body is **one-way** |
| Ladders, spikes, water | tags on tiles, asked for by the script (`tileHasTag`) |
| The mouse that comes after you | `map:findWalkPath` - the map answers "how do I get there", jumps and drops included |
| Logs that carry you over water | kinematic bodies moved with `moveTo`; `getGroundVelocity` |
| Planks that give way | `Joint2D` welds with a **break force** |
| The hero's walk, jump and climb | `Sprite2D` clips from a packed atlas, played by name |
| "+1" off a coin, what a sign says | `Text2D`: words in the world |
| Everything that eases - pickups, the end card, the fades between levels | `tween` |
| English and Portuguese | `lang` / `tr`, labels authored `@key`, `assets/lang/*.json` |
| A stick and a button for two thumbs | `touch`, `ui.stick`, `ui.isHeld` |
| The cavern and the dusk | 2D point lights on lit sprites and lit tile maps, a light the hero carries |
| Sky, clouds and hills that slide | `Layer2D` parallax layers the engine scrolls; a view that follows with a dead zone and look-ahead, kept inside the level |
| Music and effects | Ogg Vorbis, streamed and played |
| Stars that are still there tomorrow | `store` (a file on a desktop, local storage in a browser) |
| Fifty levels, each one file | prefabs: `assets/prefabs/H001..H050.prefab`, put into the world's scene by `Prefab.instantiate` |

Everything was placed with the editor's own commands and opens in it:
`scenes/World1..5.json` are the five stages (backdrop, hero, interface,
music), `scenes/Title.json` the menu, and each level is a prefab - drag one
into a world's scene to see or change it, and paint on its tile map with the
terrain brush. The rules are one script, `assets/lua/hopper/game.lua`, which
reads a level by its objects' names (`Coin_3`, `Slime_1`, `Ferry_2`, `Goal`).
Holding **B** for a second on the title has the game play itself through
every level - how they are checked to be finishable.

## Building it again

```bash
python3 tools/make_assets.py /path/to/kenney /path/to/music   # once: picks the art and sound out of the packs
# start PyrosBuilder, then:
python3 tools/build_game.py            # atlases, tile set, title, worlds, levels
python3 tools/build_game.py levels 11 20
```

A level is drawn in `tools/build_game.py` from pieces a dozen columns wide,
each a picture in text; which pieces, and in what order, comes from the
level's number.

## Credits

Art and sound effects: [Kenney](https://kenney.nl) - New Platformer Pack, UI
Pack, Particle Pack, Interface Sounds, Music Jingles (CC0). Music: Juhani
Junkala, "Chiptune Adventures" (CC0, opengameart.org).
