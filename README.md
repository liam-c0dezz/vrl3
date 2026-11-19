# Two Lanes

An endless, relaxing 3D driving game that runs in the browser. The road, terrain and scenery are generated as you drive, so the road never ends and every seed is different.

Pick a region on the title screen:

- **California:** a coast road with the Pacific on your left, beaches and cliffs, golden hills with chaparral, oaks, eucalyptus and wind-bent cypress, and stretches lined with palms. You drive a pastel convertible, and the radio plays lo-fi on *101.9 Coastline FM*. The default time is golden hour, with the sun setting over the ocean.
- **North Florida:** flat backroads through slash-pine flatwoods with palmetto understory, live oaks hung with Spanish moss, cabbage palms, cypress swamps and roadside power lines. You drive an old pickup, and the radio plays a walking-bass country shuffle on *88.3 Backroads Radio*. The air is hazy, and thunderheads build in the afternoon.

## Run it

It's a static site with no build step. Serve the folder and open it in a browser:

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000. (Opening `index.html` straight from disk won't work, because ES modules need a server.)

URL options: `?region=ca` or `?region=fl`, and `?seed=1234` to replay a specific road.

## Controls

| Key | Action |
| --- | --- |
| W / ↑ | Gas |
| S / ↓ | Brake / reverse |
| A D / ← → | Steer (takes over from auto-drive) |
| E | Auto-drive on/off |
| C | Camera: chase, driver, cinematic |
| Mouse drag | Look around |
| T / Y | Next time of day / day cycle on/off |
| R | Radio on/off |
| M | All sound on/off |
| G | Switch between California and Florida |
| N | New road |
| U | Hide interface |
| P / Esc | Pause |

On touch screens, hold the left or right side of the screen to steer; the car keeps cruising on its own.

## How it works

- `game.js` holds everything. The road centreline comes from a bounded sum of sines, so it winds but never loops back. Its elevation is smoothed with a Gaussian window. A spatial hash finds the nearest road point, and terrain within ~40 m of the road is flattened and blended into the natural heightfield.
- The terrain streams in 64 m chunks around the car. Trees, palms and props are merged into one mesh per chunk.
- The engine, wind and radio music are synthesised live with the Web Audio API, so there are no audio files.
- Three.js r160 is vendored in `vendor/` (MIT, see `vendor/THREE-LICENSE`).
