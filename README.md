# Two Lanes

An endless, relaxing 3D driving game for the browser, drawn like a graphic print. As you drive, the game generates the road, terrain and scenery, so the road never ends and every seed is different.

## The look

The game is styled after graphic-art posters and riso prints rather than realism:

- **Toon shading:** everything has three flat light bands, with no soft gradients.
- **Ink outlines:** these come from depth edges, with tinted shadows and warm highlights.
- **Banded skies:** poster-style gradient bands with a big hard-edged sun. California's sun is striped near the horizon; Florida's has stepped halo rings. At night there's a crescent moon and stars.
- **Layered horizon silhouettes:** mountain ranges inland in California, pine treelines in Florida.
- **Flat two-tone pill clouds.**
- **Topographic contour lines** drawn on the ground.
- **A hand-picked palette for every time of day** in each region.

Press **X** to switch between three looks:

| Look | What it is |
| --- | --- |
| Poster | Toon shading, ink lines, split-tone grade, fine grain (default) |
| Riso | A risograph print: five ink levels, ordered dither, halftone dots in the shadows, slight colour misregistration, paper tint |
| Clean | Toon shading only, with no lines or print effects |

## Regions

- **California:** a coast road with the Pacific on your left, beaches and cliffs, golden hills with chaparral, oaks, eucalyptus, wind-bent cypress and palm-lined stretches. You drive a pastel convertible, and the radio plays lo-fi on *101.9 Coastline FM*.
- **North Florida:** flat backroads through slash pines and palmetto, live oaks with Spanish moss, cabbage palms, cypress swamps and power lines. You drive an old pickup, and the radio plays a country shuffle on *88.3 Backroads Radio*.

## Features

- Auto-drive is on by default, and **W/S** set the cruise speed. Steering with A/D or the arrow keys hands you full control.
- There's light oncoming traffic, and brushing a car gives you a bump.
- A **route map** in the bottom-right corner rotates with your heading. It shows the coastline or swamps, the road ahead, mile ticks and oncoming cars.
- **Photo mode** (F) pauses the drive and lets you orbit the car with the mouse and zoom with scroll. You can change the look and time of day, and **Enter** saves a PNG.
- Five times of day per region, plus an optional full day cycle.
- Three cameras: chase, driver's seat and cinematic roadside shots.
- The HUD shows speed in mph, miles driven, a clock and live coordinates.
- Your look, camera, map, radio and sound choices are remembered between visits.
- Resolution adjusts automatically to keep slower machines smooth.
- On touch screens you steer with the screen halves.

## Run it

It's a static site with no build step:

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000. Opening `index.html` straight from disk won't work, because ES modules need a server.

URL options:

| Option | What it does |
| --- | --- |
| `?region=ca` or `?region=fl` | Pick the region |
| `?seed=1234` | Replay a specific road |
| `?view=5` | Shorter draw distance, for weak GPUs |
| `?dynres=0` | Turn off automatic resolution scaling |

## Controls

| Key | Action |
| --- | --- |
| A D / ← → | Steer (takes over from auto-drive) |
| W S / ↑ ↓ | Gas / brake; in auto-drive, cruise speed up/down |
| E | Auto-drive on/off |
| C | Camera: chase, driver, cinematic |
| X | Look: poster, riso, clean |
| F | Photo mode (Enter saves a PNG, F/Esc exits) |
| T / Y | Next time of day / day cycle on/off |
| R | Radio |
| M | Route map |
| V | All sound |
| G | Switch between California and Florida |
| N | New road |
| U / P | Hide interface / pause |
| Mouse drag | Look around |

## Tests

`tests/smoke.cjs` runs both regions on a desktop viewport and a mobile (touch) viewport in headless Chromium. It checks that:

- the world generates and the title screen works;
- auto-drive stays in its lane;
- the route map renders;
- the looks and cameras switch;
- cruise control, steering takeover and braking work;
- photo mode freezes the drive and saves a PNG;
- settings persist;
- touch steering works and the buttons fit on a phone screen;
- the page logs no errors.

It saves screenshots to `tests/output/`.

```bash
node tests/smoke.cjs
```

```bash
node tests/smoke.cjs fl
```

The first command runs all four combinations; the second runs one region only. Both need Playwright installed.

## How it works

Everything is in `game.js`:

- **Road:** the centreline comes from a bounded sum of sines, so it winds but never loops back, and its elevation is Gaussian-smoothed.
- **Terrain:** a spatial hash finds the nearest road point, and terrain near the road is flattened and blended into the heightfield. The terrain streams in 64 m chunks, with plants merged into one mesh per chunk.
- **Rendering:** the scene renders to a multisampled float target, then one fullscreen pass adds the outlines, grading, print effects and grain.
- **Sound:** the engine, wind and radio are synthesised live with the Web Audio API.

Three.js r160 is vendored in `vendor/` (MIT, see `vendor/THREE-LICENSE`). The fonts are Syne, Space Grotesk and Space Mono from Google Fonts, with system fallbacks if you're offline.
