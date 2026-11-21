# Two Lanes

An endless open-world driving game for the browser. The road, terrain, plants and whole cities are generated as you drive, so the road never ends and every seed is different.

## Regions

- **Los Angeles and the Pacific coast:** the drive starts in LA, in Downtown LA, the beach cities or palm-lined neighbourhoods. It then runs out onto a coast road with the Pacific on your left: beaches and cliffs, and golden hills with chaparral, oaks, sycamores, eucalyptus and wind-bent cypress. More LA stretches come back along the way. The radio plays lo-fi on *101.9 Coastline FM*.
Four cities. Each has hand-modelled landmarks along the drive: recognisable approximations at roughly real size, built from code. The district name in the corner switches to the landmark's name as you pass it.

- **Los Angeles and the Pacific coast:** the drive starts in LA, in Downtown LA, the beach cities or palm-lined neighbourhoods. It then runs out onto a coast road with the Pacific on your left: beaches and cliffs, and golden hills with chaparral, oaks, sycamores, eucalyptus and wind-bent cypress. More LA stretches come back along the way. The radio plays lo-fi on *101.9 Coastline FM*.
  - **Landmarks:** U.S. Bank Tower, Walt Disney Concert Hall (stainless sails), Capitol Records Building, Griffith Observatory and the Hollywood Sign on their own hills, the LAX Theme Building, and Santa Monica Pier with its ferris wheel.
- **Miami (South Florida):** an endless city with five districts:
  - **Downtown:** glass towers with podiums, setbacks, lit crowns and red beacons.
  - **Art deco beach strip:** pastel hotels with eyebrow ledges, neon fins and signs, opposite a beachfront promenade.
  - **Residential:** houses with hip roofs and pools.
  - **Shop strips:** awnings and neon signs.
  - **Causeways:** long crossings over the bay on piers.

  The radio plays *104.3 Neon Coast*: synth pads, a tumbao bass line, clave and congas.
  - **Landmarks:** the Freedom Tower, the Atlantis (with its sky-court hole, palm and red spiral stair), Panorama Tower, Miami Tower's glowing half-moon crown, the Colony Hotel's blue neon on Ocean Drive, and rainbow lifeguard towers on South Beach.
- **Chicago:** the Loop, three-flat neighbourhoods with bay windows, and Grant Park, with Lake Michigan on your right. Street trees change with the seasons. The elevated *L* crosses the boulevard on rusty steel trestles.
  - **Landmarks:** Willis Tower (nine bundled black tubes and two antennas), Cloud Gate in a granite plaza, Buckingham Fountain, the X-braced 875 North Michigan, the twin corn-cob Marina City towers, the Wrigley Building's clock tower, and Navy Pier with its wheel.
- **New York:** Midtown towers and pre-war masonry with water tanks, brownstone blocks with stoops and fire escapes, Central Park behind its stone wall, and the Hudson on your left. Yellow cabs fill the traffic. Sometimes the road leaves the island on a suspension bridge with Gothic stone towers and cables.
  - **Landmarks:** the Empire State Building, the Flatiron Building, Times Square's screens, the Chrysler Building's stainless sunburst crown, One World Trade Center, and the Statue of Liberty on her island in the harbour.

## Open world

- **The main street** is a four-lane boulevard, two lanes each way, with dashed lane lines and a signal over every lane.
- **Side streets** at every intersection lead into a grid of real four-lane back streets, every 64 m, with centre and edge lines and zebra crossings at each corner. You can leave the main road and explore. Buildings are solid.
- **Traffic** fills all four lanes of the boulevard. It follows the car ahead and stops at red lights. Signals cycle green, yellow, red.
- **Back-street traffic** drives the grid, turns at corners and stops for you.
- **Pedestrians** walk the sidewalks and cross at crosswalks when the light is red. They jump out of the way of slow cars. Hit one and they're knocked flat, lie there for a few seconds, then get up and walk back to the kerb.
- **Auto-drive** follows traffic, stops at lights and keeps to city speed in town.
- **Police chase (K):** cruisers with flashing light bars and a siren pursue you, ram you and box you in. Stay 180 m clear for 12 seconds to escape. If you stop with a cruiser on you, you're busted.
- **Street detail:**
  - Sidewalks with benches, bus shelters, hydrants, newspaper boxes and trash cans.
  - Street-name signs, crosswalks and stop lines.
  - Royal or fan palms (LA, Miami) or leafy street trees (Chicago, New York), and streetlights.
  - Brick, brownstone and limestone facades in Chicago and New York.
- **Trees** are leafy clumps, not smooth balls, and deciduous trees go bare in winter instead of turning into grey blobs.
  - Rooftop AC units, water towers and billboards that light up at night.

## Garage (V)

Ten cars, each with its own top speed, acceleration, grip and engine sound, and ten paint colours. There are no real brands, badges or replicas.

| # | Car | Kind |
| --- | --- | --- |
| 1 | **Rosso Dodici** | Red front-mid V12 berlinetta in the Italian style: long bonnet, rear haunches, twin round tail lamps, quad pipes |
| 2 | **Saetta LP12** | Faceted V12 wedge in the Italian style: Y-shaped lights, hexagonal pipes, louvred engine cover |
| 3 | **Rosso Spider** | Open mid-engine V8 spider, yellow |
| 4 | **Furia V10** | Smaller faceted wedge with a fixed carbon wing |
| 5 | Apex HX | Hypercar |
| 6 | Vector 84 | '80s wedge |
| 7 | Gran Corsa GT | Grand tourer |
| 8 | Circuit R | Track car |
| 9 | Volta E | Electric hyper |
| 10 | Aria Concept | A detailed 3D concept-car model (see credits) |

Cars 1–4 are lofted: their bodies are swept through cross-sections, like a clay model, with wheel arches, fender flares, a separate glass cabin, and their own lights, vents, diffusers and wings. They're original designs in the style of Italian supercars, with no real names, badges or replicas. Cars 5–9 are smoothed side silhouettes sculpted with tumblehome and plan-view taper. Traffic uses lower-detail versions of them.

## Graphics

- **Lighting and materials:** physically based materials lit by the sun with soft shadows, plus reflections of the live sky on glass, wet roads and clear-coated paint.
- **Post-processing:** HDR rendering with multi-level bloom, filmic (ACES) tone mapping, colour grading, slight chromatic aberration, grain and a vignette.
- **Sky:** procedural clouds lit by the sun, a moon and stars.
- **Water:** a reflective ocean and bay.
- **Weather:** rain with wet roads.
- **Night:** lit windows and shop fronts, neon, and streetlights that light the road.
- **Foliage** sways in the wind.

Press **X** to switch looks: **Cinematic** (default), **Poster** or **Riso**.

## Seasons

**Z** moves to the next season, and **Shift+Z** cycles through them every 90 seconds.

| | California | South Florida |
| --- | --- | --- |
| Spring | Green hills with wildflowers, blossom | Bougainvillea in bloom |
| Summer | Golden hills | Afternoon thunderstorms |
| Fall | Orange and red trees | Breezy, occasional rain |
| Winter | Green hills, rain, snowy peaks | Clear; holiday lights on the palms at night |

## Driving and engine

- **Physics:** fixed 120 Hz steps with interpolated rendering, real velocity and grip, a handbrake slide, and sprung body pitch and roll.
- **Camera:** follows on springs.
- **World generation** runs in a Web Worker and is uploaded in small pieces each frame.
- **Resolution** adjusts automatically on slower machines.

## Controls

| Key | Action |
| --- | --- |
| A D / ← → | Steer (takes over from auto-drive) |
| W S / ↑ ↓ | Gas / brake; in auto-drive, cruise speed |
| Space | Handbrake |
| R | Back on the road |
| E | Auto-drive on/off |
| K | Start or stop a police chase |
| V | Garage |
| C | Camera: chase, driver, cinematic |
| Z / Shift+Z | Next season / cycle seasons |
| T / Y | Time of day / day cycle |
| X | Look |
| F | Photo mode (Enter saves a PNG) |
| L / J | Headlights / horn |
| Q / Shift+V / B | Radio / all sound / map |
| G / N | Next city (LA, Miami, Chicago, New York) / new road |
| M / Esc | Menu |

On phones: a steering pad at bottom left, Gas, Brake and Handbrake at bottom right, and Chase, Auto and Reset above them.

## Run it

It's a static site with no build step:

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

URL options:

| Option | What it does |
| --- | --- |
| `?region=ca`, `sf`, `chi` or `ny` | Pick the city |
| `?seed=1234` | Replay a specific road |
| `?view=5` | Shorter draw distance, for weak GPUs |
| `?dynres=0` | Turn off automatic resolution scaling |

Links can also use `#sf` or `#sf-1234`.

## Tests

`tests/smoke.cjs` runs both regions on a desktop viewport and a mobile (touch) viewport in headless Chromium. It checks:

- **World:** it builds in the worker; traffic, pedestrians and signals are present; auto-drive stays in lane.
- **Open world:** the main street has four lanes and traffic in both its inner and outer lanes; cars drive the four-lane back-street grid; pedestrians fall over when hit; landmarks are placed and clear their ground.
- **Cities:** LA and Miami run on desktop and phone layouts; Chicago and New York on desktop.
- **Map and looks:** the map renders; looks and cameras switch.
- **Driving:** cruise control, steering takeover, braking and the handbrake; R returns to the road; physics stays finite.
- **Seasons:** all four cycle.
- **Menus and modes:**
  - the pause menu opens and closes;
  - the garage lists 10 cars and swaps them;
  - K starts and ends a chase;
  - photo mode freezes the drive and saves a PNG;
  - settings and the chosen car persist.
- **Phone controls:** steering, pedals, Reset, Auto and Chase; the layout fits.
- **Errors:** the page logs none.

```bash
node tests/smoke.cjs
```

```bash
node tests/smoke.cjs sf mobile
```

The first runs everything; the second runs one region on one device.

## Files

| File | What it holds |
| --- | --- |
| `world.js` | Noise, terrain, districts, the endless road and its queries. Shared by the main thread and the worker. |
| `gen.js` | Geometry for terrain, plants, buildings, sidewalks, street furniture and building footprints. |
| `gen-worker.js` | Runs `gen.js` in a background thread. |
| `cars.js` | The ten cars: the lofted and silhouette car builders and the glTF loader. |
| `landmarks.js` | The hand-modelled landmarks of all four cities. |
| `game.js` | Rendering and post-processing, sky, weather and seasons, physics and collisions, traffic, pedestrians, signals, police, camera, audio, the map and the interface. |
| `assets/cars/hero.glb` | The hero car model. |

## Credits

- **Aria Concept:** the *CarConcept* glTF sample by Eric Chadwick (Darmstadt Graphics Group, 2024), [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/). It was started from a public-domain model by Unity Fan and taken from the [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/CarConcept). Changes for this game: the Khronos and 3D Commerce logo meshes were removed, meshes were simplified and meshopt-compressed, textures were converted to WebP at 1024 px, and the paint, glass and lights are replaced at runtime.
- **Three.js r160** and its glTF loader, BufferGeometryUtils and meshopt decoder are vendored in `vendor/` (MIT, see `vendor/THREE-LICENSE`).
- **Archivo** typeface via Google Fonts (SIL Open Font License).
