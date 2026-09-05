# Bolt Yard — Trailworks 0.4

An original offline Android offroading prototype with a native C++ deformable vehicle simulation and Godot 4.4.1 graphics. Version 0.4 rebuilds the tire contact and driving model, closes vehicle body seams, and gives Juniper Valley a new outdoor lighting and material treatment. Three vehicles, interchangeable equipment, saved builds and portrait support remain available.

## Explore and build

- **Juniper Valley:** a 768 × 768 metre landscape with a forest trail, terraced quarry, overlook, lake shore and ridge. Six named destinations appear on the terrain map. Choose a destination, follow its compass bearing and drive into its discovery radius; discoveries persist.
- **Three distinct vehicles:** Bison Pickup, Scout SUV and Nomad Buggy have different body shapes, native structural bracing, dimensions and weight distributions. Each uses 16 deformable frame/cab nodes and four physical wheel assemblies. Eighty derived tire guides preserve the 100-position render interface; they are no longer independent tire masses.
- **Six equipment slots:** tires, wheels, suspension, final drive, front bumper and roof equipment. Each vehicle has three compatible options per slot. The Nomad has its own nose brace and spare carrier; expedition armor and cargo racks fit the pickup/SUV. Equipment affects tire geometry and grip, suspension, gearing or mass distribution as appropriate.
- **Saved garage:** separate builds and six paint choices for every vehicle, with ten optional fine-tuning controls. Existing 0.2 pickup tuning migrates into the pickup bay; the old save remains intact. Equipping a part clears only the manual overrides affected by that part.
- **Portrait and landscape:** rotate while playing. The garage changes between a sidebar and bottom sheet, and driving controls rearrange for the screen. Input is cleared during rotation, pause and app backgrounding.
- **Connected vehicle bodywork:** one continuous deformation field keeps adjoining panels together. Enclosed wheel wells, body interiors, supported cage braces and real accessory brackets replace floating or incomplete sections. Clear-coated paint, tinted dielectric glass, metal wheels and rubber have distinct material responses.
- **A new landscape treatment:** weathered stone, olive vegetation, layered rock faces, detailed juniper branches, clustered ground cover and a terrain-clipped shoreline. Mipmapped ground materials reduce distant shimmer. A cloud sky and late-afternoon lighting carry into the vehicle reflections. Dry tire contacts leave subtle dust while driving.
- **Three graphics settings:** Performance is the default; Balanced and High add terrain material detail, longer shadows and a static camp reflection. 3D resolution scales to 75% / 85% / 100%, with 2× MSAA on Balanced/High; controls and text remain at full resolution. The panoramic sky also supplies reflections across the map. Reflections use cached environment captures rather than live mirrors.

Low range, differential coupling, live deformation, X-ray beam diagnostics, impact testing and repair/recovery remain available. The earlier construction sandbox is retained in `main.tscn`; the app opens `offroad_main.tscn`.

The simulation is experimental and is not calibrated to real vehicle or tire data. Obstacles use cylinder contacts, suspension uses simplified guides, and the lake is scenery without buoyancy. There is no vehicle self-collision, deformable soil, functioning winch, fluid mud, detachable panels or multiplayer. See [SIMULATION.md](SIMULATION.md) for the model and its limits.

## Install

Open the [verified 0.4 build](https://github.com/braydenparker999/Boltyard/actions/runs/33992149892) and download **bolt-yard-android**. Extract `bolt-yard-0.4.0-trailworks.apk` and open it on an ARM64 Android phone. Allow installation from your download/file app if Android asks.

The APK uses package `games.boltyard.prototype`, version 0.4.0 / code 4 and the same development signing key as earlier prototypes, so install it over the existing app to retain saves. The included key is only for development builds. The game needs no Play Store account, runtime network access or storage permission.

The user reported that 0.3 ran on a Samsung A15 but had slow, glitchy driving and incomplete-looking bodywork. The 0.4 rebuild targets those problems. New-version FPS, temperature, touch feel and sustained play still need validation on that phone. Start with Performance; compare Balanced if it stays smooth. Build verification and downloadable artifact details are recorded in [VALIDATION.md](VALIDATION.md).

## Measured handling improvement

Default pickup, flat ground, same desktop native benchmark:

| Measurement | 0.3 | 0.4 |
|---|---:|---:|
| Speed after 5 seconds | 17.4 km/h | 52.9 km/h |
| Distance after 10 seconds | 41.5 m | 123.5 m |
| Vertical velocity RMS on flat ground | 0.0444 m/s | 0.00018 m/s |

The new native simulation also uses less CPU in the same host benchmark. These results exclude rendering and are not phone performance claims. The frame/cab remain deformable; continuous round wheel contacts replace independently simulated polygon tire rings. See [SIMULATION.md](SIMULATION.md) for forces, tests and limits.

## Controls

Choose a vehicle and equipment, then tap **DRIVE**. Hold **GO** together with **LEFT** or **RIGHT**; **REV** reverses and **BRAKE** stops. **Map** selects a destination. **Repair & camp** rebuilds the vehicle at base camp while keeping builds and discoveries. Returning to the garage also resets the vehicle at camp. The garage includes orbit/zoom controls, **X-ray** and **Impact test**.

Keyboard: WASD or arrows drive and steer, Space brakes, R repairs, Tab changes garage/drive and M opens the map. Escape pauses or closes the map. Saves are local to the installed app.

## Build and test

GitHub Actions installs Godot 4.4.1, its Android template, JDK 17, Android SDK 34 and NDK 23.2.8568313. It pins godot-cpp to `e4b7c25e721ce3435a029087e3917a30aa73f06b` and SCons to 4.8.1, builds Linux and ARM64 GDExtensions, runs native and engine tests, drives two complete 1.3 km road loops, renders screenshots and a 21-second controlled driving movie, exports the APK and verifies its signature and native library contents.

Complete Ubuntu build with JDK 17 and Android SDK configured:

```bash
bash tools/ci_build.sh
```

Standalone physics tests, without Godot:

```bash
mkdir -p build
g++ -std=c++17 -O2 -Wall -Wextra -pedantic native/test_soft_rig.cpp -o build/test-soft-rig
build/test-soft-rig
```

Build native libraries with `bash tools/build_native.sh` before importing. The checked-in extension maps Linux x86_64 and Android ARM64 debug builds; other hosts and release exports need corresponding builds and mappings. Use Godot 4.4.1 export templates and **Export With Debug**.

```bash
godot --headless --path . --editor --import
godot --headless --path . --script tests/run.gd
godot --headless --path . --script tests/offroad.gd
godot --headless --path . --script tests/catalog.gd
godot --headless --path . --script tests/explorer.gd
godot --headless --path . --script tests/vehicle_geometry.gd
```

Run tests and screenshots against disposable user data. The explorer suite backs up/restores its save fixtures, but the retained prototype tests and capture script may write setup/blueprint saves. Mesa software-rendered screenshots are not phone performance measurements.

## Source map

| File | Purpose |
| --- | --- |
| `native/soft_rig.hpp` | Native node/beam model and XPBD solver |
| `native/terrain_v03.hpp` | Shared exploration heightfield, surfaces and obstacles |
| `native/binding.cpp` | Godot interface, fixed cadence and diagnostics |
| `native/test_soft_rig.cpp` | Physics behavior and stability checks |
| `scripts/vehicle_catalog.gd` | Vehicle definitions, compatible equipment and composed tuning |
| `scripts/offroad_truck.gd` | Persistent particle-bound vehicle geometry |
| `shaders/vehicle_skin.gdshaderinc` | GPU binding to chassis, cab, tire and suspension particles |
| `scripts/offroad_world.gd` | Terrain, vegetation, lighting and quality levels |
| `scripts/offroad_main.gd` | Garage, saves, responsive controls and camera |
| `scripts/exploration_map.gd` | Terrain map and selectable destinations |
| `tests/catalog.gd`, `tests/explorer.gd` | Equipment, save migration, discovery and orientation checks |
| `tools/ci_build.sh` | Test gates, screenshot capture, Android export and verification |

Original material sources and generation prompts are documented in `assets/world/TERRAIN_MATERIALS.md` and the three `assets/world/*.provenance.md` files.
