# Two Lanes

An endless 3D driving game for the browser. The road, terrain, plants and a whole city are generated as you drive, so the road never ends and every seed is different.

## Regions

- **Los Angeles / California:** the drive starts in LA (Downtown LA towers, the beach cities, palm-lined neighbourhoods) and runs out onto a coast road with the Pacific on your left, beaches and cliffs, golden hills with chaparral, oaks, sycamores, eucalyptus, wind-bent cypress and palm-lined stretches. You drive a pastel convertible with whitewall tyres, and the radio plays lo-fi on *101.9 Coastline FM*.
- **South Florida:** an endless city with five districts:
  - **Downtown:** glass towers with podiums, setbacks, lit crowns and red beacons.
  - **Art deco beach strip:** pastel hotels with eyebrow ledges, neon fins, rounded corners and neon signs, opposite a promenade, palms and the beach.
  - **Residential:** houses with hip roofs and pools.
  - **Shop strips:** awnings and neon signs.
  - **Causeways:** long crossings over the bay on piers.

  The corridor has sidewalks, crosswalks and traffic signals at every block, cross streets, royal palms and streetlights. Beyond it, a street grid fills with more buildings, parks with banyan trees, beaches with lifeguard huts and umbrellas, mangroves at the waterline, and a skyline on the horizon that lights up at night. You drive an '80s wedge coupe, and the radio plays *104.3 Neon Coast*: synth pads, a tumbao bass line, clave and congas.

## Graphics

- **Lighting and materials:** physically based materials lit by the sun with soft shadows, plus reflections of the live sky. Glass towers, wet roads and clear-coated car paint all reflect the sky.
- **Post-processing:** HDR rendering with multi-level bloom, filmic (ACES) tone mapping, colour grading, subtle chromatic aberration, grain and a vignette.
- **Sky:** procedural clouds lit by the sun, a sun disc, a moon and stars.
- **Water:** an ocean and bay that reflect the sky.
- **Weather:** rain with falling streaks, wet and shiny roads, darker skies and denser fog.
- **Night:** lit windows, glowing shop fronts, neon, streetlights that light the road, headlights and tail lights.
- **Details:** foliage that sways in the wind, and soft shading at building bases.
- **Cars:** extruded bodies with wheel arches, lathed tyres, five-spoke rims and suspension that moves each wheel.

Press **X** to switch between three looks: **Cinematic** (default), **Poster** (ink outlines and flat tones) and **Riso** (a risograph print).

## Seasons

**Z** moves to the next season, and **Shift+Z** makes the seasons cycle by themselves, changing every 90 seconds. Transitions blend smoothly. The game starts in the real-world season.

| | California | South Florida |
| --- | --- | --- |
| Spring | Green hills with wildflowers, blossom on the trees | Bougainvillea in full bloom |
| Summer | Golden hills, clear skies | Lush, with afternoon thunderstorms |
| Fall | Orange and red oaks and sycamores | Breezy, with occasional rain |
| Winter | Green hills, rain, snow on the high peaks | Clear and dry; holiday lights on the palms at night |

## Driving

- **Physics** runs at a fixed 120 Hz and is interpolated for rendering, so motion stays smooth at any frame rate.
- **Handling:** the car has real velocity and grip; the handbrake lets the back end slide.
- **Suspension:** springs on body height, pitch and roll, so the car leans in corners and dips under braking.
- **The camera** follows on springs and leans into slides.
- **World generation** runs in a Web Worker and is uploaded in small pieces each frame, so building the city never stalls a frame.
- **Collisions:** buildings and causeway barriers are solid. Oncoming traffic gives you a bump if you hit it.

## Controls

| Key | Action |
| --- | --- |
| A D / ← → | Steer (takes over from auto-drive) |
| W S / ↑ ↓ | Gas / brake; in auto-drive, cruise speed up/down |
| Space | Handbrake |
| R | Back on the road |
| E | Auto-drive on/off |
| C | Camera: chase, driver, cinematic |
| Z / Shift+Z | Next season / seasons cycle by themselves |
| T / Y | Next time of day / day cycle on/off |
| X | Look: cinematic, poster, riso |
| F | Photo mode (drag to orbit, scroll to zoom, Enter saves a PNG) |
| L / J | Headlights auto/on/off / horn |
| Q / V / M | Radio / all sound / route map |
| G / N | Switch region / new road |
| U / P | Hide interface / pause |

On touch screens, hold the left or right half of the screen to steer.

## Run it

It's a static site with no build step:

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

URL options:

| Option | What it does |
| --- | --- |
| `?region=ca` or `?region=sf` | Pick the region |
| `?seed=1234` | Replay a specific road |
| `?view=5` | Shorter draw distance, for weak GPUs |
| `?dynres=0` | Turn off automatic resolution scaling |

Links can also use `#sf` or `#sf-1234`.

## Tests

`tests/smoke.cjs` runs both regions on a desktop viewport and a mobile (touch) viewport in headless Chromium. It checks that:

- the world builds in the worker, and auto-drive stays in its lane;
- the map renders, and the looks and cameras switch;
- cruise control, steering takeover, braking and the handbrake work;
- R returns the car to the road;
- all four seasons cycle;
- the physics state stays finite;
- photo mode freezes the drive and saves a PNG;
- settings persist;
- touch steering works and the buttons fit on a phone screen;
- the page logs no errors.

It saves screenshots to `tests/output/`.

```bash
node tests/smoke.cjs
```

## Files

| File | What it holds |
| --- | --- |
| `world.js` | Noise, terrain heights, the endless road and its queries. Shared by the main thread and the worker. |
| `gen.js` | Geometry for terrain chunks, plants, buildings, sidewalks and street furniture. |
| `gen-worker.js` | Runs `gen.js` in a background thread. |
| `game.js` | Rendering and post-processing, sky and weather, seasons, vehicle physics, camera, audio, the map and the UI. |

Three.js r160 is vendored in `vendor/` (MIT, see `vendor/THREE-LICENSE`).
