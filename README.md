# Pyros3D examples

Example projects for [Pyros3D](https://github.com/Peixinho/Pyros3D), browsable
from inside the editor.

**PyrosBuilder > File > Browse Examples** lists everything in here, downloads
the one you pick, and opens it. Nothing needs cloning, and no example costs you
the download of the others.

| Example | What it shows |
| --- | --- |
| [Rossio](Rossio) | A wave-defence firefight in a metro station — deferred rendering, skeletal animation, ragdolls, decals, particles, a Lua FPS controller |

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
