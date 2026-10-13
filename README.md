# Pyros3D examples

Example projects for [Pyros3D](https://github.com/Peixinho/Pyros3D), browsable
from inside the editor.

**PyrosBuilder > File > Browse Examples** lists everything in here, downloads
the one you pick, and opens it. Nothing needs cloning, and no example costs you
the download of the others.

| Example | What it shows |
| --- | --- |
| [Rossio](Rossio) | A wave-defence firefight in a metro station — deferred rendering, skeletal animation, ragdolls, decals, particles, a Lua FPS controller |
| [Ember](Ember) | A 2D platformer where you play the Pyros logo — 2D lighting with occluder shadows, parallax layers, spritesheet animation, Box2D platforming, particles and a synthesised soundtrack |
| [Topple](Topple) | A physics toy with a sling: a hundred easy levels in five worlds, two of them at night under swinging lamps. Levels are prefabs dropped into a world's scene; 2D lights and shadows on normal-mapped sprites, joints, breakable blocks, particles, parallax, a full interface, sound and saved progress. [Play it in a browser](https://peixinho.github.io/pyros3d-examples/topple/), phones included |
| [Hopper](Hopper) | A platformer in fifty easy levels and five worlds, two of them lit by torches. Ground painted by terrain (the tile map picks its own corners), slopes, one-way bridges, ladders, moving logs, a mouse that finds its way to you; words in the world, eased motion, two languages, touch controls, Ogg music and saved progress. [Play it in a browser](https://peixinho.github.io/pyros3d-examples/hopper/), phones included |
| [Kickstart](Kickstart) | Side-on motocross in 3D: bikes are 2D physics bodies on sprung wheel joints with 3D models hung on them. Big jumps, flips and tricks, three rivals, a floodlit stadium; collision layers, torque-driven wheels, riders posed by two-bone reaches, colliding particles, a pitched engine loop, touch pedals. [Play it in a browser](https://peixinho.github.io/pyros3d-examples/kickstart/), phones included |

## Adding an example

**Every top-level folder with a `project.json` in it is an example.** There is
no index file to update: push a folder, and the editor lists it.

```
MyExample/
  project.json        <- required; this is what makes the folder an example
  scenes/
  assets/
  demo.json           <- optional
  README.md           <- optional
  preview.png         <- optional
```

`demo.json` is how a folder describes itself in the browser:

```json
{
    "name": "My Example",
    "description": "One or two sentences. This is the text people read in the list.",
    "author": "Your Name",
    "tags": ["2D", "physics"]
}
```

With no `demo.json`, the editor falls back to the folder name and to the first
paragraph of `README.md`. With neither, it still lists — just bare.

`preview.png` is the thumbnail. 16:9 is what the browser's detail pane is laid
out for.

### Before you push

* Keep it small. The browser shows a total size before downloading, but an
  example nobody waits for is an example nobody runs.
* Drop `.trash/` — the editor's undo-safety folder is not content.
* Check `project.json` for a `settings.aiAssistant` block. The editor strips
  it on install, but it should not be in a commit in the first place: it is
  where an API key lives.

## Pointing the editor somewhere else

The browser's **Repository** field takes any `owner/repo`, `owner/repo@branch`,
or github.com URL, so a team can keep its own shelf of examples and the editor
will list it the same way. The choice is remembered.

Listings use the GitHub API, which allows 60 calls an hour per IP
unauthenticated — one call per refresh. Set `GITHUB_TOKEN` in the environment
to lift that; the editor never stores a credential of its own.
