# The asset generators

Every texture and every sound in this game is produced by these four scripts.
Nothing here is licensed artwork and nothing was drawn by hand.

```bash
python3 tools/gen_world.py    # slabs, backdrops, frostlings, shards, props, particles
python3 tools/gen_player.py   # Ember's four sprite sheets, warped from pyros.png
python3 tools/gen_audio.py    # ten sound effects, a fire loop and the music
```

`gen_world.py` and `gen_player.py` need Pillow; `gen_audio.py` needs nothing
but the standard library. They write straight into `../assets/`.

`pyros.png` is the Pyros3D logo, and it IS the hero: `gen_player.py` crops it,
then for each frame shifts every row sideways by a two-harmonic sine whose
amplitude grows towards the top, so the flame licks while his feet stay
planted. Squash, stretch and lean are the same function's other arguments.

After regenerating a **sheet**, re-slice it in the editor (Properties >
Spritesheet, or `slice_spritesheet`) so the per-frame PNGs the scene
references are rebuilt.

`gen_audio.py` is a small mono synth - oscillators, one-pole filters, a delay
line - plus the arrangement of one eight-bar loop in D minor at 144. The loop
is crossfaded into itself at both ends so it has no seam.
